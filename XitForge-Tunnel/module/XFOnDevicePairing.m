#import "XFOnDevicePairing.h"
#import "XFIDeviceABI.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <fcntl.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

static NSString * const XFPairErrorDomain = @"XitForge.OnDevicePairing";
static NSError *XFPairError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:XFPairErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSError *XFPairNativeError(IdeviceFfiError *native, NSString *operation) {
    if (!native) return nil;
    NSString *detail = native->message ? [NSString stringWithUTF8String:native->message] : @"Error del servicio";
    NSError *result = XFPairError(native->code, [NSString stringWithFormat:@"%@: %@ (código %d/%d).",
        operation, detail ?: @"Respuesta no válida", native->code, native->sub_code]);
    idevice_error_free(native);
    return result;
}
static void XFLE16(NSMutableData *data, uint16_t value) {
    value = CFSwapInt16HostToLittle(value); [data appendBytes:&value length:sizeof(value)];
}
static void XFLE32(NSMutableData *data, uint32_t value) {
    value = CFSwapInt32HostToLittle(value); [data appendBytes:&value length:sizeof(value)];
}
static NSData *XFSilentWAV(void) {
    const uint32_t sampleRate = 8000, dataLength = sampleRate * 2;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"RIFF" length:4]; XFLE32(data, 36 + dataLength);
    [data appendBytes:"WAVEfmt " length:8]; XFLE32(data, 16);
    XFLE16(data, 1); XFLE16(data, 1); XFLE32(data, sampleRate);
    XFLE32(data, sampleRate * 2); XFLE16(data, 2); XFLE16(data, 16);
    [data appendBytes:"data" length:4]; XFLE32(data, dataLength);
    [data increaseLengthBy:dataLength];
    return data;
}

// Accept only a connection originating from this device's own interfaces.
// Bonjour remains native NSNetService, so no multicast entitlement is needed.
static BOOL XFIsLocalPeer(const struct sockaddr *peer) {
    if (!peer) return NO;
    struct in_addr ipv4 = {0}; BOOL isV4 = peer->sa_family == AF_INET;
    if (isV4) ipv4 = ((const struct sockaddr_in *)peer)->sin_addr;
    if (peer->sa_family == AF_INET6) {
        const struct in6_addr *address = &((const struct sockaddr_in6 *)peer)->sin6_addr;
        if (IN6_IS_ADDR_LOOPBACK(address)) return YES;
        if (IN6_IS_ADDR_V4MAPPED(address)) {
            memcpy(&ipv4, &address->s6_addr[12], sizeof(ipv4)); isV4 = YES;
        }
    }
    if (isV4 && (ntohl(ipv4.s_addr) >> 24) == 127) return YES;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return NO;
    BOOL local = NO;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr) continue;
        if (isV4 && item->ifa_addr->sa_family == AF_INET) {
            if (((struct sockaddr_in *)item->ifa_addr)->sin_addr.s_addr == ipv4.s_addr) { local = YES; break; }
        } else if (!isV4 && peer->sa_family == AF_INET6 && item->ifa_addr->sa_family == AF_INET6) {
            if (memcmp(&((const struct sockaddr_in6 *)peer)->sin6_addr,
                       &((struct sockaddr_in6 *)item->ifa_addr)->sin6_addr, sizeof(struct in6_addr)) == 0) { local = YES; break; }
        }
    }
    freeifaddrs(interfaces);
    return local;
}

@interface XFOnDevicePairing () <NSNetServiceDelegate> {
    NSLock *_stateLock;
    dispatch_queue_t _nativeQueue;
    BOOL _running;
    BOOL _cancelled;
    NSUInteger _attempt;
    int _listenerFD;
    int _peerFD;
    NSError *_stopError;
    PairableHostHandle *_preparedHost;
    NSString *_serviceID;
    NSDictionary<NSString *, NSData *> *_TXT;
    NSData *_hostAltIRK;
    NSNetService *_advertisement;
    AVAudioPlayer *_keepAlivePlayer;
    NSString *_previousAudioCategory;
    NSString *_previousAudioMode;
    AVAudioSessionCategoryOptions _previousAudioOptions;
    BOOL _ownsAudioSession;
    dispatch_source_t _deadline;
    UIBackgroundTaskIdentifier _backgroundTask;
    NSURL *_recordURL;
    void (^_activeReady)(NSString *);
    void (^_activePIN)(NSString *);
    void (^_activeCompletion)(NSURL *, NSError *);
}
- (void)receivePIN:(NSString *)pin attempt:(NSUInteger)attempt;
- (void)stopWithError:(NSError *)error;
@end

typedef struct {
    __unsafe_unretained XFOnDevicePairing *owner;
    NSUInteger attempt;
} XFPairCallbackContext;
static void XFNativePIN(const char *pin, void *context) {
    XFPairCallbackContext *callback = context;
    if (!callback || !pin) return;
    NSString *copy = [NSString stringWithUTF8String:pin];
    XFOnDevicePairing *owner = callback->owner;
    NSUInteger attempt = callback->attempt;
    if (owner && copy) [owner receivePIN:copy attempt:attempt];
}

@implementation XFOnDevicePairing
- (instancetype)init {
    if ((self = [super init])) {
        _stateLock = [NSLock new];
        _nativeQueue = dispatch_queue_create("XitForge.Pairing.Native", DISPATCH_QUEUE_SERIAL);
        _listenerFD = -1; _peerFD = -1; _backgroundTask = UIBackgroundTaskInvalid;
        NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
        _recordURL = [[base URLByAppendingPathComponent:@"XitForge/AirLift" isDirectory:YES]
                         URLByAppendingPathComponent:@"on-device-pairing.plist"];
    }
    return self;
}
- (void)dealloc {
    // An active native block retains self through handshake cleanup. Reaching
    // dealloc therefore means no callback or FFI call still uses this handle.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_preparedHost) pairable_host_free(_preparedHost);
}
- (BOOL)running { [_stateLock lock]; BOOL value = _running; [_stateLock unlock]; return value; }
- (void)start {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self start]; }); return; }
    [_stateLock lock];
    if (_running) { [_stateLock unlock]; return; }
    _running = YES; _cancelled = NO; _stopError = nil; _attempt++;
    NSUInteger attempt = _attempt;
    _activeReady = [self.readyHandler copy]; _activePIN = [self.pinHandler copy];
    _activeCompletion = [self.completionHandler copy];
    [_stateLock unlock];
    if (![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){27, 0, 0}]) {
        [self finishAttempt:attempt recordURL:nil error:XFPairError(2001, @"El emparejamiento iniciado desde Ajustes requiere iOS 27 o posterior.")];
        return;
    }
    NSError *audioError = [self beginKeepAlive];
    if (audioError) { [self finishAttempt:attempt recordURL:nil error:audioError]; return; }
    _backgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"XitForge Pairing"
        expirationHandler:^{ [self stopWithError:XFPairError(2002, @"iOS detuvo el emparejamiento en segundo plano. Vuelve a XitForge e inténtalo de nuevo.")]; }];
    _deadline = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_deadline, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_deadline, ^{
        [weakSelf stopWithError:XFPairError(2003, @"El emparejamiento no se aprobó en cinco minutos. Vuelve a iniciarlo desde XitForge.")];
    });
    dispatch_resume(_deadline);
    dispatch_async(_nativeQueue, ^{ @autoreleasepool { [self runAttempt:attempt]; } });
}
- (void)cancel {
    [self stopWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError
                                      userInfo:@{NSLocalizedDescriptionKey:@"Emparejamiento cancelado."}]];
}
- (void)stopWithError:(NSError *)error {
    [_stateLock lock];
    if (!_running || _cancelled) { [_stateLock unlock]; return; }
    _cancelled = YES; _stopError = error;
    // shutdown affects the duplicated descriptor owned by Rust too. Merely
    // closing our descriptor would leave its asynchronous read alive.
    if (_listenerFD >= 0) shutdown(_listenerFD, SHUT_RDWR);
    if (_peerFD >= 0) shutdown(_peerFD, SHUT_RDWR);
    [_stateLock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_advertisement stop]; });
}
- (BOOL)isCancelled { [_stateLock lock]; BOOL value = _cancelled; [_stateLock unlock]; return value; }
- (NSError *)cancellationError {
    [_stateLock lock]; NSError *error = _stopError; [_stateLock unlock];
    return error ?: XFPairError(2004, @"Emparejamiento cancelado.");
}
- (NSError *)beginKeepAlive {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    _previousAudioCategory = session.category; _previousAudioMode = session.mode;
    _previousAudioOptions = session.categoryOptions;
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionMixWithOthers error:&error])
        return error ?: XFPairError(2005, @"No se pudo preparar el audio que mantiene activo el emparejamiento.");
    _ownsAudioSession = YES;
    if (![session setActive:YES error:&error])
        return error ?: XFPairError(2005, @"No se pudo activar el audio que mantiene activo el emparejamiento.");
    _keepAlivePlayer = [[AVAudioPlayer alloc] initWithData:XFSilentWAV() error:&error];
    if (!_keepAlivePlayer) return error ?: XFPairError(2005, @"No se pudo mantener activo el emparejamiento al abrir Ajustes.");
    _keepAlivePlayer.numberOfLoops = -1; _keepAlivePlayer.volume = 0;
    [_keepAlivePlayer prepareToPlay];
    if (![_keepAlivePlayer play]) return XFPairError(2005, @"No se pudo mantener activo el emparejamiento al abrir Ajustes.");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterrupted:)
        name:AVAudioSessionInterruptionNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioReset:)
        name:AVAudioSessionMediaServicesWereResetNotification object:session];
    return nil;
}
- (void)audioInterrupted:(NSNotification *)notification {
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan)
        [self stopWithError:XFPairError(2006, @"Una interrupción de audio detuvo el emparejamiento. Vuelve a XitForge para iniciarlo de nuevo.")];
}
- (void)audioReset:(NSNotification *)notification {
    [self stopWithError:XFPairError(2006, @"iOS reinició el audio que mantenía activo el emparejamiento. Vuelve a intentarlo.")];
}
- (void)endKeepAlive {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    [_keepAlivePlayer stop]; _keepAlivePlayer = nil;
    if (_ownsAudioSession) {
        AVAudioSession *session = AVAudioSession.sharedInstance;
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:NULL];
        [session setCategory:_previousAudioCategory ?: AVAudioSessionCategorySoloAmbient
                       mode:_previousAudioMode ?: AVAudioSessionModeDefault options:_previousAudioOptions error:NULL];
        _ownsAudioSession = NO;
    }
}
- (void)receivePIN:(NSString *)pin attempt:(NSUInteger)attempt {
    BOOL valid = pin.length == 6;
    for (NSUInteger index = 0; valid && index < pin.length; index++) {
        unichar character = [pin characterAtIndex:index]; valid = character >= '0' && character <= '9';
    }
    if (!valid) { [self stopWithError:XFPairError(2007, @"El servicio devolvió un PIN no válido.")]; return; }
    NSString *copy = [pin copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_stateLock lock]; BOOL deliver = self->_running && !self->_cancelled && self->_attempt == attempt; [self->_stateLock unlock];
        if (deliver && self->_activePIN) self->_activePIN(copy);
    });
}
- (NSError *)prepareHost {
    if (_preparedHost) return nil; // Stable identity across retries in this instance.
    char *identifier = NULL; uint8_t *TXTBytes = NULL; size_t TXTLength = 0;
    uint8_t hostIRK[16] = {0};
    NSError *error = XFPairNativeError(pairable_host_prepare("XitForge", "Mac17,7", false,
        &_preparedHost, &identifier, &TXTBytes, &TXTLength, hostIRK), @"Preparar host de emparejamiento");
    if (!error) {
        NSString *serviceID = identifier ? [NSString stringWithUTF8String:identifier] : nil;
        NSData *xml = TXTBytes ? [NSData dataWithBytes:TXTBytes length:TXTLength] : nil;
        NSDictionary *dictionary = xml ? [NSPropertyListSerialization propertyListWithData:xml
            options:NSPropertyListImmutable format:NULL error:&error] : nil;
        if (![dictionary isKindOfClass:NSDictionary.class] || !serviceID.length) {
            error = error ?: XFPairError(2008, @"El servicio no devolvió una identidad Bonjour válida.");
        } else {
            NSMutableDictionary<NSString *, NSData *> *records = [NSMutableDictionary new];
            for (id key in dictionary) {
                id value = dictionary[key];
                if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) {
                    error = XFPairError(2008, @"El servicio devolvió un registro Bonjour no válido."); break;
                }
                NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
                if (!bytes) { error = XFPairError(2008, @"El registro Bonjour no tiene un formato válido."); break; }
                records[key] = bytes;
            }
            if (!error) { _serviceID = serviceID; _TXT = records; _hostAltIRK = [NSData dataWithBytes:hostIRK length:16]; }
        }
    }
    if (identifier) idevice_string_free(identifier);
    if (TXTBytes) idevice_data_free(TXTBytes, TXTLength);
    if (error && _preparedHost) { pairable_host_free(_preparedHost); _preparedHost = NULL; }
    return error;
}
- (int)createListenerWithPort:(uint16_t *)port error:(NSError **)error {
    int listener = socket(AF_INET6, SOCK_STREAM, 0);
    if (listener < 0) { if (error) *error = XFPairError(errno, @"No se pudo abrir el listener de emparejamiento."); return -1; }
    if (listener >= FD_SETSIZE) {
        if (error) *error = XFPairError(2014, @"La app tiene demasiadas conexiones abiertas para iniciar el emparejamiento.");
        close(listener); return -1;
    }
    int zero = 0, one = 1;
    setsockopt(listener, IPPROTO_IPV6, IPV6_V6ONLY, &zero, sizeof(zero));
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(listener, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    struct sockaddr_in6 address = {0}; address.sin6_len = sizeof(address); address.sin6_family = AF_INET6;
    address.sin6_addr = in6addr_any; address.sin6_port = 0;
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 4) != 0) {
        if (error) *error = XFPairError(errno, @"No se pudo iniciar el listener de emparejamiento."); close(listener); return -1;
    }
    socklen_t length = sizeof(address);
    if (getsockname(listener, (struct sockaddr *)&address, &length) != 0) {
        if (error) *error = XFPairError(errno, @"No se pudo consultar el puerto de emparejamiento."); close(listener); return -1;
    }
    int flags = fcntl(listener, F_GETFL, 0);
    if (flags < 0 || fcntl(listener, F_SETFL, flags | O_NONBLOCK) < 0) {
        if (error) *error = XFPairError(errno, @"No se pudo configurar el listener."); close(listener); return -1;
    }
    *port = ntohs(address.sin6_port); return listener;
}
- (void)publishPort:(uint16_t)port attempt:(NSUInteger)attempt {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_stateLock lock]; BOOL publish = self->_running && !self->_cancelled && self->_attempt == attempt; [self->_stateLock unlock];
        if (!publish) return;
        self->_advertisement = [[NSNetService alloc] initWithDomain:@"local."
            type:@"_remotepairing-pairable-host._tcp." name:self->_serviceID port:port];
        self->_advertisement.delegate = self;
        NSData *TXT = [NSNetService dataFromTXTRecordDictionary:self->_TXT];
        if (![self->_advertisement setTXTRecordData:TXT]) {
            [self stopWithError:XFPairError(2009, @"No se pudo publicar la identidad de emparejamiento.")]; return;
        }
        [self->_advertisement publish];
    });
}
- (void)netServiceDidPublish:(NSNetService *)sender {
    [_stateLock lock]; BOOL deliver = _running && !_cancelled && sender == _advertisement; [_stateLock unlock];
    if (deliver && _activeReady) _activeReady(@"XitForge");
}
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    if (sender != _advertisement) return;
    [self stopWithError:XFPairError(2010, [NSString stringWithFormat:@"No se pudo anunciar XitForge por Bonjour (código %@). Activa Wi-Fi y permite Red local en Ajustes > XitForge.", errorDict[NSNetServicesErrorCode] ?: @0])];
}
- (NSURL *)saveRecord:(RpPairingFileHandle *)record error:(NSError **)error {
    uint8_t *bytes = NULL; size_t length = 0;
    NSError *failure = XFPairNativeError(rp_pairing_file_to_bytes(record, &bytes, &length), @"Guardar emparejamiento");
    NSData *data = failure ? nil : [NSData dataWithBytes:bytes length:length];
    if (bytes) idevice_data_free(bytes, length);
    NSMutableDictionary *dictionary = data ? [[NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListMutableContainers format:NULL error:&failure] mutableCopy] : nil;
    if (![dictionary isKindOfClass:NSMutableDictionary.class]) failure = failure ?: XFPairError(2011, @"El servicio no devolvió un registro de emparejamiento válido.");
    if (!failure) {
        dictionary[@"XitForgeHostAltIRK"] = _hostAltIRK;
        dictionary[@"XitForgePairingServiceID"] = _serviceID;
        dictionary[@"XitForgePairingHostName"] = @"XitForge";
        data = [NSPropertyListSerialization dataWithPropertyList:dictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:&failure];
    }
    if (!failure) {
        NSURL *directory = [_recordURL URLByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES
            attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&failure]) { /* error is returned below */ }
        else if ([data writeToURL:_recordURL options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&failure]) {
            chmod(_recordURL.fileSystemRepresentation, S_IRUSR | S_IWUSR);
            [_recordURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
        }
    }
    if (failure) { if (error) *error = failure; return nil; }
    return _recordURL;
}
- (void)runAttempt:(NSUInteger)attempt {
    NSError *error = nil; NSURL *saved = nil;
    if ([self isCancelled]) { [self finishAttempt:attempt recordURL:nil error:[self cancellationError]]; return; }
    // Only this explicit pairing action prepares a host. Ordinary connections
    // use the previously imported record without generating keys or an IRK.
    // Keep that record untouched until a new approved handshake commits.
    error = [self prepareHost];
    if (error) { [self finishAttempt:attempt recordURL:nil error:error]; return; }
    uint16_t port = 0;
    int listener = [self createListenerWithPort:&port error:&error];
    if (listener < 0) { [self finishAttempt:attempt recordURL:nil error:error]; return; }
    [_stateLock lock]; _listenerFD = listener; BOOL cancelled = _cancelled; [_stateLock unlock];
    if (!cancelled) [self publishPort:port attempt:attempt];
    int peer = -1;
    while (![self isCancelled]) {
        fd_set readable; FD_ZERO(&readable); FD_SET(listener, &readable);
        struct timeval timeout = {0, 250000};
        int ready = select(listener + 1, &readable, NULL, NULL, &timeout);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) { error = XFPairError(errno, @"El listener de emparejamiento dejó de responder."); break; }
        if (ready == 0) continue;
        struct sockaddr_storage address = {0}; socklen_t length = sizeof(address);
        peer = accept(listener, (struct sockaddr *)&address, &length);
        if (peer < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (peer < 0) { error = XFPairError(errno, @"No se pudo aceptar el emparejamiento del iPhone."); break; }
        if (!XFIsLocalPeer((struct sockaddr *)&address)) { close(peer); peer = -1; continue; }
        int one = 1; setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        [_stateLock lock]; _peerFD = peer; cancelled = _cancelled;
        if (cancelled) shutdown(peer, SHUT_RDWR);
        [_stateLock unlock];
        break;
    }
    [_stateLock lock]; _listenerFD = -1; [_stateLock unlock]; close(listener);
    if (peer >= 0 && ![self isCancelled]) {
        XFPairCallbackContext context = {self, attempt};
        RpPairingFileHandle *record = NULL; RpPairingPeerDeviceC *device = NULL;
        error = XFPairNativeError(pairable_host_accept_fd(_preparedHost, peer, XFNativePIN,
            &context, &device, &record), @"Aprobar emparejamiento");
        // Serialize cancellation and commit: once cancel returns, this attempt
        // cannot overwrite the stored record or return a successful callback.
        [_stateLock lock];
        BOOL canCommit = !_cancelled && _running && _attempt == attempt;
        if (!error && record && canCommit) saved = [self saveRecord:record error:&error];
        [_stateLock unlock];
        if (!error && !record) error = XFPairError(2012, @"El iPhone no devolvió un registro de emparejamiento.");
        if (device) rppairing_peer_device_free(device);
        if (record) rp_pairing_file_free(record);
    }
    [_stateLock lock]; _peerFD = -1; cancelled = _cancelled; [_stateLock unlock];
    if (peer >= 0) { shutdown(peer, SHUT_RDWR); close(peer); }
    if (cancelled) { saved = nil; error = [self cancellationError]; }
    [self finishAttempt:attempt recordURL:saved error:error ?: (saved ? nil : XFPairError(2013, @"El emparejamiento no se completó."))];
}
- (void)finishAttempt:(NSUInteger)attempt recordURL:(NSURL *)URL error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_stateLock lock];
        if (!self->_running || self->_attempt != attempt) { [self->_stateLock unlock]; return; }
        NSURL *completionURL = self->_cancelled ? nil : URL;
        NSError *completionError = self->_cancelled ? (self->_stopError ?: XFPairError(2004, @"Emparejamiento cancelado.")) : error;
        self->_running = NO;
        void (^completion)(NSURL *, NSError *) = self->_activeCompletion;
        self->_activeReady = nil; self->_activePIN = nil; self->_activeCompletion = nil;
        [self->_stateLock unlock];
        [self->_advertisement stop]; self->_advertisement.delegate = nil; self->_advertisement = nil;
        if (self->_deadline) { dispatch_source_cancel(self->_deadline); self->_deadline = nil; }
        [self endKeepAlive];
        if (self->_backgroundTask != UIBackgroundTaskInvalid) {
            [UIApplication.sharedApplication endBackgroundTask:self->_backgroundTask]; self->_backgroundTask = UIBackgroundTaskInvalid;
        }
        if (completion) completion(completionURL, completionError);
    });
}
@end
