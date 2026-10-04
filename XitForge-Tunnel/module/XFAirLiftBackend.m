#import "XFAirLiftBackend.h"
#import "XFIDeviceABI.h"
#import "XFStreamBridge.h"
#import "XFATCDirectory.h"
#import "XFMHAContainerAccess.h"
#import "XFFileServiceListing.h"
#import <CommonCrypto/CommonDigest.h>
#import <arpa/inet.h>
#import <sys/stat.h>
#import <string.h>
#import <stdlib.h>

static NSString * const XFErrorDomain = @"XitForge.AirLift";
static const NSUInteger XFMaximumReadSize = 128 * 1024 * 1024;
static const NSUInteger XFMaximumKnownFileSize = 64 * 1024 * 1024;
static NSError *XFError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:XFErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
static BOOL XFConsume(IdeviceFfiError *native, NSString *action, NSError **error) {
    if (!native) return YES;
    NSString *detail = native->message ? [NSString stringWithUTF8String:native->message] : @"Error del servicio iOS";
    NSInteger code = native->code;
    if (error) *error = XFError(code, [NSString stringWithFormat:@"%@: %@ (código %d/%d).", action,
        detail ?: @"Respuesta no válida", native->code, native->sub_code]);
    idevice_error_free(native);
    return NO;
}

// FileService owns a separate tunnel for each operation. All three handles
// are created and released on XFNativeWorker, including partial failures.
typedef struct {
    AdapterHandle *adapter;
    RsdHandshakeHandle *handshake;
    FileServiceHandle *service;
} XFFileServiceSession;
static void XFCloseFileServiceSession(XFFileServiceSession *session) {
    if (session->service) { file_service_free(session->service); session->service = NULL; }
    if (session->handshake) { rsd_handshake_free(session->handshake); session->handshake = NULL; }
    if (session->adapter) {
        XFConsume(adapter_close(session->adapter), @"Cerrar conexión de archivos", NULL);
        adapter_free(session->adapter); session->adapter = NULL;
    }
}

// GCD serial queues can change OS threads. Native adapter/stream handles are
// instead confined to one NSThread for their complete lifetime.
@interface XFNativeWorker : NSObject
@property (nonatomic, strong) NSThread *thread;
@property (nonatomic) BOOL stopping;
- (void)perform:(dispatch_block_t)block;
- (void)stop;
@end
@implementation XFNativeWorker
- (instancetype)init {
    if ((self = [super init])) {
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
        _thread.name = @"XitForge.AirLift.Native";
        [_thread start];
    }
    return self;
}
- (void)run {
    @autoreleasepool {
        NSPort *port = [NSMachPort port];
        [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
        while (!self.stopping) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                        beforeDate:[NSDate distantFuture]];
            }
        }
        [[NSRunLoop currentRunLoop] removePort:port forMode:NSDefaultRunLoopMode];
    }
}
- (void)runBlock:(dispatch_block_t)block { @autoreleasepool { block(); } }
- (void)perform:(dispatch_block_t)block {
    if ([NSThread currentThread] == self.thread) { block(); return; }
    [self performSelector:@selector(runBlock:) onThread:self.thread withObject:[block copy] waitUntilDone:YES];
}
- (void)markStopped { self.stopping = YES; }
- (void)stop {
    if (self.stopping) return;
    [self performSelector:@selector(markStopped) onThread:self.thread withObject:nil waitUntilDone:NO];
}
@end

@interface XFAirLiftBackend () {
    AdapterHandle *_adapter;
    RsdHandshakeHandle *_handshake;
    XFNativeWorker *_worker;
    NSData *_pairingData;
    BOOL _hasRemote;
    BOOL _hasClassic;
    BOOL _connected;
    NSString *_applicationCatalogSource;
    NSMutableDictionary<NSString *, NSString *> *_applicationContainers;
    NSMutableDictionary<NSString *, NSString *> *_groupContainers;
    NSMutableDictionary<NSString *, NSDictionary *> *_applicationContainerResolution;
    NSMutableDictionary<NSString *, NSDictionary *> *_groupContainerResolution;
    NSDictionary *_containerResolution;
    NSDictionary *_nativeContainerFailure;
    NSDictionary *_nativeContainerAttempt;
    NSDictionary *_fileServiceAttempt;
    XFATCDirectory *_atcDirectory;
    NSString *_directoryWarning;
    NSURL *_lastDeletedFileBackupURL;
    BOOL _lastDeletionAbsenceConfirmed;
    NSMutableDictionary<NSString *, NSNumber *> *_catalogResultCodes;
    NSMutableDictionary<NSString *, NSNumber *> *_routeResultCodes;
    BOOL _containersQueried;
    NSString *_connectionAddress;
    BOOL _connectionUsesRemote;
    BOOL _connectionUsesRemoteXPC;
    NSInteger _connectionRemotePort;
}
@property (nonatomic, strong) NSURL *pairingURL;
@end

@implementation XFAirLiftBackend
+ (instancetype)sharedBackend {
    static XFAirLiftBackend *backend;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        backend = [[self alloc] init];
    });
    return backend;
}
- (instancetype)init {
    if ((self = [super init])) {
        _worker = [XFNativeWorker new];
        _deviceAddress = @"10.7.0.1";
        _remotePairingPort = 49152;
        _applicationCatalogSource = @"";
        _applicationContainers = [NSMutableDictionary new];
        _groupContainers = [NSMutableDictionary new];
        _applicationContainerResolution = [NSMutableDictionary new];
        _groupContainerResolution = [NSMutableDictionary new];
        _containerResolution = @{};
        _nativeContainerFailure = @{};
        _nativeContainerAttempt = @{};
        _fileServiceAttempt = @{};
        _catalogResultCodes = [NSMutableDictionary new];
        _routeResultCodes = [NSMutableDictionary new];
        _directoryWarning = @"";
        NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
        NSURL *directory = [base URLByAppendingPathComponent:@"XitForge/AirLift" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES
                                                  attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
                                                       error:NULL];
        _pairingURL = [directory URLByAppendingPathComponent:@"pairing.plist"];
        NSData *saved = [NSData dataWithContentsOfURL:_pairingURL];
        if (saved.length) [_worker perform:^{ [self validatePairingData:saved error:NULL]; }];
    }
    return self;
}
- (void)dealloc {
    AdapterHandle *adapter = _adapter;
    RsdHandshakeHandle *handshake = _handshake;
    [_worker perform:^{
        if (handshake) rsd_handshake_free(handshake);
        if (adapter) { XFConsume(adapter_close(adapter), @"Cerrar túnel", NULL); adapter_free(adapter); }
    }];
    [_worker stop];
}
- (BOOL)connected { __block BOOL value; [_worker perform:^{ value = self->_connected; }]; return value; }
// A closed base adapter is a tunnel failure. Permission errors and a closed
// individual service channel do not imply that the complete tunnel is down.
- (void)recordClosedAdapterError:(NSError *)error {
    if ([error.domain isEqualToString:XFErrorDomain] &&
        [error.localizedDescription rangeOfString:@"adapter closed" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        _connected = NO;
    }
}
- (BOOL)hasPairingRecord { __block BOOL value; [_worker perform:^{ value = self->_pairingData.length > 0; }]; return value; }
- (NSURL *)lastDeletedFileBackupURL {
    __block NSURL *value;
    [_worker perform:^{ value = [self->_lastDeletedFileBackupURL copy]; }];
    return value;
}
- (BOOL)lastDeletionAbsenceConfirmed {
    __block BOOL value = NO;
    [_worker perform:^{ value = self->_lastDeletionAbsenceConfirmed; }];
    return value;
}
- (NSString *)applicationCatalogSource {
    __block NSString *value;
    [_worker perform:^{ value = [self->_applicationCatalogSource copy]; }];
    return value ?: @"";
}
- (BOOL)fileServiceAvailable {
    // Informational snapshot of the base connection, never an operation gate.
    __block BOOL available = NO;
    [_worker perform:^{
        available = [self hasRSDService:"com.apple.coredevice.fileservice.control"];
    }];
    return available;
}
- (BOOL)applicationFileAccessAvailable {
    __block BOOL available = NO;
    [_worker perform:^{
        // A connected device is eligible for fresh FileService discovery.
        available = [XFMHAContainerAccess availableWithError:NULL] || self->_connected;
    }];
    return available;
}
- (BOOL)directContainerAccessAvailable {
    __block BOOL available = NO;
    [_worker perform:^{ available = [XFMHAContainerAccess availableWithError:NULL]; }];
    return available;
}
- (BOOL)atcDirectoryAvailableNative {
    return [self hasRSDService:"com.apple.atc.shim.remote"] &&
           [self hasRSDService:"com.apple.streaming_zip_conduit.shim.remote"] &&
           [self hasRSDService:"com.apple.afc.shim.remote"];
}
- (NSString *)fileAccessSummary {
    __block NSString *summary;
    [_worker perform:^{
        NSMutableArray *routes = [NSMutableArray new];
        if ([XFMHAContainerAccess availableWithError:NULL]) [routes addObject:@"Acceso directo a apps"];
        if (self->_connected) [routes addObject:@"Archivos: comprobar al abrir"];
        if ([self hasRSDService:"com.apple.mobile.house_arrest.shim.remote"]) [routes addObject:@"Documentos de apps"];
        if ([self atcDirectoryAvailableNative]) [routes addObject:@"AirLift: carpetas"];
        summary = routes.count ? [routes componentsJoinedByString:@" · "] : @"Sin ruta de carpetas anunciada";
    }];
    return summary;
}
- (NSString *)lastDirectoryWarning {
    __block NSString *value;
    [_worker perform:^{ value = [self->_directoryWarning copy]; }];
    return value ?: @"";
}
- (NSString *)connectionDiagnostics {
    __block NSString *result;
    [_worker perform:^{
        NSMutableArray *services = [NSMutableArray new];
        if (self->_handshake) {
            uint8_t *bytes = NULL; size_t length = 0;
            if (XFConsume(xf_rsd_advertised_services(self->_handshake, &bytes, &length), @"Consultar servicios anunciados", NULL)) {
                id decoded = bytes && length ? [NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:bytes length:length] options:NSPropertyListImmutable format:NULL error:NULL] : nil;
                if ([decoded isKindOfClass:NSDictionary.class] && [decoded count] <= 2048) {
                    for (id key in [[decoded allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
                        if (![key isKindOfClass:NSString.class] || [key length] > 512) continue;
                        id item = decoded[key]; if (![item isKindOfClass:NSDictionary.class]) continue;
                        id port = item[@"Port"];
                        NSInteger number = ([port isKindOfClass:NSString.class] || [port isKindOfClass:NSNumber.class]) ? [port integerValue] : 0;
                        id properties = item[@"Properties"];
                        id xpc = [properties isKindOfClass:NSDictionary.class] ? properties[@"UsesRemoteXPC"] : nil;
                        [services addObject:@{@"name":key, @"port":@(number > 0 && number <= UINT16_MAX ? number : 0),
                            @"usesRemoteXPC":@([xpc isKindOfClass:NSNumber.class] && [xpc boolValue])}];
                    }
                }
            }
            if (bytes) idevice_data_free(bytes, length);
        }
        size_t version = 0;
        if (self->_handshake) XFConsume(rsd_get_protocol_version(self->_handshake, &version), @"Consultar versión RSD", NULL);
        NSDictionary *report = @{@"moduleVersion":[[NSBundle mainBundle] objectForInfoDictionaryKey:@"XFTunnelModuleVersion"] ?: @"desconocida",
            @"systemVersion":NSProcessInfo.processInfo.operatingSystemVersionString,
            @"kernelBuild":[XFMHAContainerAccess kernelBuild],
            @"connected":@(self->_connected), @"rsdProtocolVersion":@(version),
            @"catalogResultCodes":[self->_catalogResultCodes copy], @"routeResultCodes":[self->_routeResultCodes copy], @"services":services,
            @"airLiftProtocol":self->_atcDirectory.protocolDiagnostics?:@{},
            @"containerResolution":self->_containerResolution?:@{},
            @"nativeContainerFailure":self->_nativeContainerFailure?:@{},
            @"nativeContainerAttempt":self->_nativeContainerAttempt?:@{},
            @"fileServiceAttempt":self->_fileServiceAttempt?:@{},
            @"directContainerAccessConfigured":@([XFMHAContainerAccess availableWithError:NULL]),
            @"scope":@"Versiones y servicios anunciados; excluye emparejamiento y datos de apps."};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        result = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"No se pudo crear el diagnóstico.";
    }];
    return result;
}
// Native service inspection must run on the same worker as the tunnel.
- (BOOL)hasRSDService:(const char *)name {
    if (!_connected || !_handshake) return NO;
    CRsdService *service = NULL;
    IdeviceFfiError *failure = rsd_get_service_info(_handshake, name, &service);
    BOOL available = failure == NULL && service != NULL && service->port != 0;
    if (failure) idevice_error_free(failure);
    if (service) rsd_free_service(service);
    return available;
}
- (NSString *)pairingKind {
    __block NSString *value;
    [_worker perform:^{ value = self->_hasRemote ? (self->_hasClassic ? @"Remote + Lockdown" : @"Remote") : (self->_hasClassic ? @"Lockdown" : @"Sin pairing"); }];
    return value;
}
- (BOOL)validatePairingData:(NSData *)data error:(NSError **)error {
    RpPairingFileHandle *remote = NULL;
    IdevicePairingFile *classic = NULL;
    IdeviceFfiError *remoteError = rp_pairing_file_from_bytes(data.bytes, data.length, &remote);
    IdeviceFfiError *classicError = idevice_pairing_file_from_bytes(data.bytes, data.length, &classic);
    BOOL remoteValid = remoteError == NULL && remote != NULL;
    BOOL classicValid = classicError == NULL && classic != NULL;
    if (remoteError) idevice_error_free(remoteError);
    if (classicError) idevice_error_free(classicError);
    if (remote) rp_pairing_file_free(remote);
    if (classic) idevice_pairing_file_free(classic);
    if (!remoteValid && !classicValid) {
        if (error) *error = XFError(1001, @"El archivo no contiene un registro Remote Pairing o Lockdown válido. Importa el pairing de este iPhone.");
        return NO;
    }
    _pairingData = [data copy]; _hasRemote = remoteValid; _hasClassic = classicValid;
    return YES;
}
- (BOOL)importPairingRecordURL:(NSURL *)url error:(NSError **)error {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!data.length) { if (error) *error = readError ?: XFError(1002, @"El archivo de pairing está vacío."); return NO; }
    if (data.length > 1024 * 1024) { if (error) *error = XFError(1003, @"El archivo supera el tamaño de un registro de pairing válido."); return NO; }
    __block BOOL success = NO; __block NSError *failure;
    [_worker perform:^{
        NSData *oldData = self->_pairingData; BOOL oldRemote = self->_hasRemote, oldClassic = self->_hasClassic;
        if (![self validatePairingData:data error:&failure]) return;
        if (![data writeToURL:self.pairingURL options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&failure]) {
            self->_pairingData = oldData; self->_hasRemote = oldRemote; self->_hasClassic = oldClassic;
            return;
        }
        chmod(self.pairingURL.fileSystemRepresentation, S_IRUSR | S_IWUSR);
        [self disconnectNative]; success = YES;
    }];
    if (!success && error) *error = failure;
    return success;
}
- (void)disconnectNative {
    _connected = NO;
    _applicationCatalogSource = @"";
    _atcDirectory = nil;
    [_applicationContainers removeAllObjects];
    [_groupContainers removeAllObjects];
    [_applicationContainerResolution removeAllObjects];
    [_groupContainerResolution removeAllObjects];
    _containerResolution = @{};
    _nativeContainerFailure = @{};
    _nativeContainerAttempt = @{};
    _fileServiceAttempt = @{};
    [_catalogResultCodes removeAllObjects];
    [_routeResultCodes removeAllObjects];
    _containersQueried = NO;
    _directoryWarning = @"";
    _lastDeletedFileBackupURL = nil;
    _lastDeletionAbsenceConfirmed = NO;
    _connectionAddress=nil;
    if (_handshake) { rsd_handshake_free(_handshake); _handshake = NULL; }
    if (_adapter) { XFConsume(adapter_close(_adapter), @"Cerrar túnel", NULL); adapter_free(_adapter); _adapter = NULL; }
}
- (void)disconnect { [_worker perform:^{ [self disconnectNative]; }]; }
- (BOOL)connectRemoteAtAddress:(NSString *)address remoteXPC:(BOOL)remoteXPC error:(NSError **)error {
    return [self newRemoteTunnelAtAddress:address remoteXPC:remoteXPC port:self.remotePairingPort adapter:&_adapter handshake:&_handshake error:error];
}
- (BOOL)newRemoteTunnelAtAddress:(NSString *)address remoteXPC:(BOOL)remoteXPC port:(NSInteger)port adapter:(AdapterHandle **)adapter handshake:(RsdHandshakeHandle **)handshake error:(NSError **)error {
    if(port<=0||port>UINT16_MAX){if(error)*error=XFError(1010,@"El puerto guardado del túnel no es válido.");return NO;}
    struct sockaddr_in endpoint = {0}; endpoint.sin_len = sizeof(endpoint); endpoint.sin_family = AF_INET;
    endpoint.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, address.UTF8String, &endpoint.sin_addr) != 1) {
        if (error) *error = XFError(1004, @"La dirección del túnel debe ser una dirección IPv4 válida."); return NO;
    }
    RpPairingFileHandle *pairing = NULL;
    if (!XFConsume(rp_pairing_file_from_bytes(_pairingData.bytes, _pairingData.length, &pairing), @"Leer Remote Pairing", error)) return NO;
    IdeviceFfiError *result = remoteXPC
        ? tunnel_create_remotexpc((const struct sockaddr *)&endpoint, sizeof(endpoint), "airlift-mini", pairing, NULL, NULL, adapter, handshake)
        : tunnel_create_rppairing((const struct sockaddr *)&endpoint, sizeof(endpoint), "airlift-mini", pairing, NULL, NULL, adapter, handshake);
    BOOL success = XFConsume(result, @"Abrir túnel Remote Pairing", error);
    if (success) {
        uint8_t *serialized = NULL; size_t length = 0;
        if (XFConsume(rp_pairing_file_to_bytes(pairing, &serialized, &length), @"Guardar Remote Pairing", NULL)) {
            NSData *fresh = [NSData dataWithBytes:serialized length:length];
            NSDictionary *original = [NSPropertyListSerialization propertyListWithData:_pairingData options:NSPropertyListImmutable format:NULL error:NULL];
            NSDictionary *updated = [NSPropertyListSerialization propertyListWithData:fresh options:NSPropertyListImmutable format:NULL error:NULL];
            if ([original isKindOfClass:NSDictionary.class] && [updated isKindOfClass:NSDictionary.class]) {
                NSMutableDictionary *merged = [original mutableCopy]; [merged addEntriesFromDictionary:updated];
                fresh = [NSPropertyListSerialization dataWithPropertyList:merged format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
            }
            if (fresh.length && [fresh writeToURL:self.pairingURL options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:NULL]) {
                _pairingData = fresh; chmod(self.pairingURL.fileSystemRepresentation, S_IRUSR | S_IWUSR);
            }
            idevice_data_free(serialized, length);
        }
    }
    rp_pairing_file_free(pairing);
    return success && *adapter && *handshake;
}
- (BOOL)connectClassicAtAddress:(NSString *)address error:(NSError **)error {
    return [self newClassicTunnelAtAddress:address adapter:&_adapter handshake:&_handshake error:error];
}
- (BOOL)newClassicTunnelAtAddress:(NSString *)address adapter:(AdapterHandle **)adapter handshake:(RsdHandshakeHandle **)handshake error:(NSError **)error {
    struct sockaddr_in endpoint = {0}; endpoint.sin_len = sizeof(endpoint); endpoint.sin_family = AF_INET;
    endpoint.sin_port = htons(62078);
    if (inet_pton(AF_INET, address.UTF8String, &endpoint.sin_addr) != 1) {
        if (error) *error = XFError(1004, @"La dirección del túnel debe ser una dirección IPv4 válida."); return NO;
    }
    IdevicePairingFile *pairing = NULL; IdeviceProviderHandle *provider = NULL; CoreDeviceProxyHandle *proxy = NULL;
    BOOL success = XFConsume(idevice_pairing_file_from_bytes(_pairingData.bytes, _pairingData.length, &pairing), @"Leer pairing Lockdown", error);
    if (success) {
        success = XFConsume(idevice_tcp_provider_new((const struct sockaddr *)&endpoint, pairing, "XitForge", &provider), @"Preparar conexión Lockdown", error);
        if (success) pairing = NULL; // provider consumes the pairing handle.
    }
    if (success) success = XFConsume(core_device_proxy_connect(provider, &proxy), @"Abrir CoreDeviceProxy", error);
    uint16_t rsdPort = 0;
    if (success) success = XFConsume(core_device_proxy_get_server_rsd_port(proxy, &rsdPort), @"Consultar puerto RSD", error);
    if (success) {
        CoreDeviceProxyHandle *consumed = proxy; proxy = NULL;
        success = XFConsume(core_device_proxy_create_tcp_adapter(consumed, adapter), @"Crear adaptador CoreDevice", error);
    }
    ReadWriteOpaque *stream = NULL;
    if (success) success = XFConsume(adapter_connect(*adapter, rsdPort, &stream), @"Conectar RSD", error);
    if (success) success = XFConsume(rsd_handshake_new(stream, handshake), @"Verificar servicios RSD", error); // consumes stream.
    if (proxy) core_device_proxy_free(proxy);
    if (provider) idevice_provider_free(provider);
    if (pairing) idevice_pairing_file_free(pairing);
    return success && *adapter && *handshake;
}
- (BOOL)newServiceTunnelWithAdapter:(AdapterHandle **)adapter handshake:(RsdHandshakeHandle **)handshake error:(NSError **)error {
    *adapter=NULL;*handshake=NULL;
    if(![self requireConnection:error]||!_connectionAddress.length)return NO;
    return _connectionUsesRemote
        ?[self newRemoteTunnelAtAddress:_connectionAddress remoteXPC:_connectionUsesRemoteXPC port:_connectionRemotePort adapter:adapter handshake:handshake error:error]
        :[self newClassicTunnelAtAddress:_connectionAddress adapter:adapter handshake:handshake error:error];
}
- (BOOL)connectWithError:(NSError **)error {
    __block BOOL success = NO; __block NSError *failure;
    NSString *address = [self.deviceAddress copy];
    [_worker perform:^{
        [self disconnectNative];
        if (!self->_pairingData.length) { failure = XFError(1005, @"Importa primero el pairing de este iPhone."); return; }
        if (self.remotePairingPort == 0 || self.remotePairingPort > UINT16_MAX) {
            failure = XFError(1010, @"El puerto del túnel debe estar entre 1 y 65535."); return;
        }
        idevice_set_global_timeout(5);
        NSArray<NSString *> *addresses = [address isEqualToString:@"127.0.0.1"] ? @[address] : @[address, @"127.0.0.1"];
        for (NSString *candidate in addresses) {
            if (self->_hasRemote) {
                // RSD and raw RPPairing are different Bonjour services. Do not
                // send both protocols to one port: a mismatched handshake can
                // wait indefinitely in the upstream FFI library.
                success = [self connectRemoteAtAddress:candidate remoteXPC:self.usesRemoteXPC error:&failure];
                if (success) {self->_connectionAddress=[candidate copy];self->_connectionUsesRemote=YES;self->_connectionUsesRemoteXPC=self.usesRemoteXPC;self->_connectionRemotePort=self.remotePairingPort;break;}
                [self disconnectNative];
            }
            if (self->_hasClassic) {
                success = [self connectClassicAtAddress:candidate error:&failure];
                if (success) {self->_connectionAddress=[candidate copy];self->_connectionUsesRemote=NO;self->_connectionUsesRemoteXPC=NO;break;}
                [self disconnectNative];
            }
        }
        self->_connected = success;
        BOOL tunnelEstablished = success;
        if (success) {
            XFATCDirectory *directory = [self atcDirectoryNativeWithError:&failure];
            if (!directory || ![directory recoverPendingTransaction:&failure]) {
                id pending = failure.userInfo[@"KnownFileRecoveryPending"];
                BOOL manualFileRecovery = directory && [failure.domain isEqualToString:@"XitForge.ATCDirectory"] &&
                    failure.code == 2210 && [pending isKindOfClass:NSNumber.class] && [pending boolValue];
                if (manualFileRecovery) {
                    // The validated journal requires explicit action for this
                    // exact file. Keep metadata/tunnel access for that action;
                    // the ATC module blocks new moves until recovery resolves it.
                    id deletionCommitted=failure.userInfo[@"KnownFileDeleteCommitted"];
                    BOOL retainedDelete=[deletionCommitted isKindOfClass:NSNumber.class]&&[deletionCommitted boolValue];
                    self->_directoryWarning = retainedDelete?
                        [NSString stringWithFormat:@"El retiro ya se confirmó y se conservó la copia. Vuelve a conectar para reintentar la recuperación del estado temporal; el archivo no se restaurará en la app. %@",failure.localizedDescription?:@""]:
                        [NSString stringWithFormat:@"Hay un original pendiente de recuperar. En XitForge, selecciona la app correspondiente y usa «Abrir ruta» → «Restaurar original pendiente» con la misma ruta. %@", failure.localizedDescription ?: @""];
                    self->_routeResultCodes[@"AirTrafficRecovery"] = @(2210);
                } else {
                    success = NO;
                    [self disconnectNative];
                }
            } else {
                self->_directoryWarning = [directory.lastWarning copy] ?: @"";
            }
            if (directory.deletedFileBackupURL) {
                self->_lastDeletedFileBackupURL = [directory.deletedFileBackupURL copy];
                self->_lastDeletionAbsenceConfirmed = directory.deletionAbsenceConfirmed;
            }
        }
        if (!success) {
            failure = tunnelEstablished
                ? XFError(failure.code ?: 1029, [NSString stringWithFormat:@"El túnel respondió, pero hay una recuperación de la exploración que debe completarse antes de continuar. %@", failure.localizedDescription ?: @"No se pudo verificar el estado pendiente."])
                : XFError(failure.code ?: 1006, [NSString stringWithFormat:@"No se pudo verificar la conexión con el iPhone. Activa LocalDevVPN y comprueba que el pairing corresponde a este dispositivo. %@", failure.localizedDescription ?: @""]);
        }
    }];
    if (!success && error) *error = failure;
    return success;
}
- (BOOL)requireConnection:(NSError **)error {
    if (_connected && _adapter && _handshake) return YES;
    if (error) *error = XFError(1007, @"Conecta primero el túnel con el iPhone."); return NO;
}
- (NSArray<NSDictionary *> *)sortedApplicationRows:(NSArray<NSDictionary *> *)rows {
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"name"] localizedStandardCompare:b[@"name"]];
        return order == NSOrderedSame ? [a[@"bundleIdentifier"] compare:b[@"bundleIdentifier"]] : order;
    }];
}
// Only retain canonical data-container roots returned by Installation Proxy.
// Never accept an app bundle path or an arbitrary absolute path as a container.
- (NSString *)validatedContainerRoot:(id)value shared:(BOOL)shared {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *path = value;
    if ([path hasPrefix:@"/private/var/"]) path = [path substringFromIndex:8];
    const char *bytes = path.UTF8String;
    if (!bytes || strlen(bytes) != [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) return nil;
    NSString *prefix = shared ? @"/var/mobile/Containers/Shared/AppGroup/" : @"/var/mobile/Containers/Data/Application/";
    if (![path hasPrefix:prefix]) return nil;
    NSString *component = [path substringFromIndex:prefix.length];
    if ([component hasSuffix:@"/"]) component = [component substringToIndex:component.length - 1];
    if (!component.length || [component containsString:@"/"] || ![[NSUUID alloc] initWithUUIDString:component]) return nil;
    return [prefix stringByAppendingString:component];
}
- (XFATCDirectory *)atcDirectoryNativeWithError:(NSError **)error {
    if (_atcDirectory) return _atcDirectory;
    if (!_adapter || !_handshake) return nil;
    char *nativeUUID = NULL;
    if (!XFConsume(rsd_get_uuid(_handshake, &nativeUUID), @"Identificar dispositivo para recuperar la operación", error)) return nil;
    NSString *identity = nativeUUID ? [NSString stringWithUTF8String:nativeUUID] : nil;
    if (nativeUUID) rsd_free_string(nativeUUID);
    if (!identity.length) {
        if (error) *error = XFError(1023, @"El dispositivo no devolvió una identidad válida para recuperar operaciones pendientes.");
        return nil;
    }
    NSDictionary *record = [NSPropertyListSerialization propertyListWithData:_pairingData options:NSPropertyListImmutable format:NULL error:NULL];
    NSData *data = nil;
    if ([record isKindOfClass:NSDictionary.class]) {
        id irk = record[@"alt_irk"];
        id udid = record[@"UDID"];
        id deviceCertificate = record[@"DeviceCertificate"];
        if ([irk isKindOfClass:NSData.class] && [irk length] == 16) {
            NSMutableData *material = [[@"RemoteDeviceIRK:" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            [material appendData:irk]; data = material;
        } else if ([udid isKindOfClass:NSString.class] && [udid length]) {
            data = [[@"LockdownDevice:" stringByAppendingString:udid] dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([deviceCertificate isKindOfClass:NSData.class] && [deviceCertificate length]) {
            NSMutableData *material = [[@"LockdownCertificate:" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            [material appendData:deviceCertificate]; data = material;
        }
    }
    // RSD UUID alone has no documented cross-boot guarantee. Pending journals
    // from every other identity are checked below before allowing a new one.
    if (!data) data = [[@"RSD:" stringByAppendingString:identity] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *key = [NSMutableString new];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [key appendFormat:@"%02x", digest[index]];
    NSURL *recoveryRoot = [self.pairingURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"ATCRecovery" isDirectory:YES];
    NSArray<NSURL *> *previous = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:recoveryRoot includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *other in previous) {
        if ([other.lastPathComponent isEqualToString:key]) continue;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[[other URLByAppendingPathComponent:@"active.plist"] path]]) {
            if (error) *error = XFError(1024, @"Hay una operación de carpetas pendiente de recuperar con otro emparejamiento. Vuelve a conectar el iPhone y el registro usados en esa operación antes de iniciar otra.");
            return nil;
        }
    }
    NSURL *journal = [recoveryRoot URLByAppendingPathComponent:key isDirectory:YES];
    __weak XFAirLiftBackend *owner=self;
    XFATCTunnelFactory factory=^BOOL(AdapterHandle **adapter,RsdHandshakeHandle **rsd,NSError **failure) {
        XFAirLiftBackend *backend=owner;
        if(!backend){*adapter=NULL;*rsd=NULL;return NO;}
        return [backend newServiceTunnelWithAdapter:adapter handshake:rsd error:failure];
    };
    _atcDirectory = [[XFATCDirectory alloc] initWithAdapter:_adapter rsd:_handshake journalURL:journal tunnelFactory:factory];
    return _atcDirectory;
}
// These helpers are called only on _worker, where the adapter and service
// handles remain confined for their entire lifetime.
- (NSArray<NSDictionary *> *)applicationsFromAppServiceWithError:(NSError **)error {
    AppServiceHandle *service = NULL; AppListEntryC *apps = NULL; size_t count = 0;
    BOOL ok = XFConsume(app_service_connect_rsd(_adapter, _handshake, &service),
        @"Abrir catálogo CoreDevice", error);
    if (ok && !service) {
        if (error) *error = XFError(1012, @"CoreDevice no devolvió un servicio de catálogo válido.");
        ok = NO;
    }
    if (ok) ok = XFConsume(app_service_list_apps(service, 1, 1, 1, 0, 1, &apps, &count),
        @"Consultar catálogo CoreDevice", error);
    if (ok && count && !apps) {
        if (error) *error = XFError(1012, @"CoreDevice devolvió un catálogo sin datos.");
        ok = NO;
    }
    NSMutableDictionary<NSString *, NSDictionary *> *rows = [NSMutableDictionary new];
    if (ok) {
        for (size_t index = 0; index < count; index++) {
            AppListEntryC app = apps[index];
            NSString *identifier = app.bundle_identifier ? [NSString stringWithUTF8String:app.bundle_identifier] : nil;
            if (!identifier.length) continue;
            NSString *name = app.name ? [NSString stringWithUTF8String:app.name] : identifier;
            rows[identifier] = @{@"bundleIdentifier":identifier, @"name":name.length ? name : identifier,
                @"isDeveloperApp":@(app.is_developer_app != 0), @"isFirstParty":@(app.is_first_party != 0)};
        }
        if (count && !rows.count) {
            if (error) *error = XFError(1012, @"CoreDevice no devolvió identificadores de apps válidos.");
            ok = NO;
        }
    }
    if (apps) app_service_free_app_list(apps, count);
    if (service) app_service_free(service);
    return ok ? [self sortedApplicationRows:rows.allValues] : nil;
}
- (NSArray<NSDictionary *> *)applicationsFromInstallationProxyWithError:(NSError **)error {
    InstallationProxyClientHandle *client = NULL;
    void *rawResults = NULL; size_t count = 0;
    BOOL ok = XFConsume(installation_proxy_connect_rsd(_adapter, _handshake, &client),
        @"Abrir catálogo Installation Proxy", error);
    if (ok && !client) {
        if (error) *error = XFError(1013, @"Installation Proxy no devolvió un servicio de catálogo válido.");
        ok = NO;
    }
    if (ok) ok = XFConsume(installation_proxy_get_apps(client, "Any", NULL, 0, &rawResults, &count),
        @"Consultar apps con Installation Proxy", error);
    if (ok && count && !rawResults) {
        if (error) *error = XFError(1013, @"Installation Proxy devolvió un catálogo sin datos.");
        ok = NO;
    }
    NSMutableDictionary<NSString *, NSDictionary *> *rows = [NSMutableDictionary new];
    plist_t *plists = (plist_t *)rawResults;
    NSMutableDictionary<NSString *, NSString *> *containers = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *groups = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSDictionary *> *containerResolution = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSDictionary *> *groupResolution = [NSMutableDictionary new];
    if (ok) {
        for (size_t index = 0; index < count; index++) {
            char *xml = NULL; uint32_t length = 0;
            plist_err_t serialized = plists[index] ? plist_to_xml(plists[index], &xml, &length) : PLIST_ERR_INVALID_ARG;
            NSDictionary *info = nil;
            if (serialized == PLIST_ERR_SUCCESS && xml && length) {
                NSData *data = [NSData dataWithBytes:xml length:length];
                id decoded = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
                if ([decoded isKindOfClass:NSDictionary.class]) info = decoded;
            }
            if (xml) plist_mem_free(xml);
            if (!info) {
                if (error) *error = XFError(1013, @"Installation Proxy devolvió datos de catálogo no válidos.");
                ok = NO; break;
            }
            NSString *identifier = [info[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ? info[@"CFBundleIdentifier"] : nil;
            if (!identifier.length) continue;
            NSString *primaryContainer = [self validatedContainerRoot:info[@"Container"] shared:NO];
            NSString *alternateContainer = [self validatedContainerRoot:info[@"DataContainer"] shared:NO];
            // Supplied 3105 applicationRecord chooses Container. This restores
            // field precedence; it does not establish the cause of AFC 106/8.
            NSString *container = primaryContainer ?: alternateContainer;
            if (container) {
                containers[identifier] = container;
                containerResolution[identifier] = @{
                    @"sourceField":primaryContainer ? @"Container" : @"DataContainer",
                    @"conflictingRootValues":@(primaryContainer && alternateContainer && ![primaryContainer isEqualToString:alternateContainer])};
            }
            id advertisedGroups = info[@"GroupContainers"];
            if ([advertisedGroups isKindOfClass:NSDictionary.class]) {
                for (id groupID in advertisedGroups) {
                    if (![groupID isKindOfClass:NSString.class] || ![groupID length]) continue;
                    NSString *groupRoot = [self validatedContainerRoot:advertisedGroups[groupID] shared:YES];
                    if (groupRoot) {
                        BOOL conflict = [groupResolution[groupID][@"conflictingRootValues"] boolValue] ||
                            (groups[groupID] && ![groups[groupID] isEqualToString:groupRoot]);
                        groups[groupID] = groupRoot;
                        groupResolution[groupID] = @{@"sourceField":@"GroupContainers", @"conflictingRootValues":@(conflict)};
                    }
                }
            }
            NSString *name = [info[@"CFBundleDisplayName"] isKindOfClass:NSString.class] ? info[@"CFBundleDisplayName"] : nil;
            if (!name.length && [info[@"CFBundleName"] isKindOfClass:NSString.class]) name = info[@"CFBundleName"];
            if (!name.length) name = identifier;
            // Installation Proxy does not provide AppService's developer-app
            // flag. Preserve the shared schema without claiming debug access.
            rows[identifier] = @{@"bundleIdentifier":identifier, @"name":name,
                @"isDeveloperApp":@NO, @"isDeveloperAppKnown":@NO,
                @"isFirstParty":@([identifier hasPrefix:@"com.apple."]),
                @"fileSharingEnabled":@([info[@"UIFileSharingEnabled"] respondsToSelector:@selector(boolValue)] && [info[@"UIFileSharingEnabled"] boolValue])};
        }
        if (ok && count && !rows.count) {
            if (error) *error = XFError(1013, @"Installation Proxy no devolvió identificadores de apps válidos.");
            ok = NO;
        }
    }
    if (rawResults && count) {
        idevice_plist_array_free(plists, count);
        // Pinned idevice 0.1.68 Apple build uses Rust's System allocator;
        // its __rdl_dealloc is a direct call to libc free (verified in binary).
        // idevice_plist_array_free only frees elements, not the outer Box slice.
        // Never free a zero-length Box slice: its pointer may be dangling.
        free(rawResults);
    }
    if (client) installation_proxy_client_free(client);
    if (ok) {
        _applicationContainers = containers;
        _groupContainers = groups;
        _applicationContainerResolution = containerResolution;
        _groupContainerResolution = groupResolution;
        _containersQueried = YES;
    } else {
        // Failed metadata refresh must never authorize a cached absolute root.
        [_applicationContainers removeAllObjects];
        [_groupContainers removeAllObjects];
        [_applicationContainerResolution removeAllObjects];
        [_groupContainerResolution removeAllObjects];
        _containersQueried = NO;
    }
    return ok ? [self sortedApplicationRows:rows.allValues] : nil;
}
- (NSArray<NSDictionary *> *)installedApplicationsWithError:(NSError **)error {
    __block NSArray *result; __block NSError *failure;
    [_worker perform:^{
        self->_applicationCatalogSource = @"";
        if (![self requireConnection:&failure]) return;
        NSError *appServiceFailure = nil;
        result = [self applicationsFromAppServiceWithError:&appServiceFailure];
        self->_catalogResultCodes[@"AppService"] = @(result ? 0 : appServiceFailure.code ?: -1);
        if (result) { self->_applicationCatalogSource = @"CoreDevice AppService"; return; }
        NSError *installationFailure = nil;
        result = [self applicationsFromInstallationProxyWithError:&installationFailure];
        self->_catalogResultCodes[@"InstallationProxy"] = @(result ? 0 : installationFailure.code ?: -1);
        if (result) { self->_applicationCatalogSource = @"Installation Proxy"; return; }
        failure = XFError(1014, [NSString stringWithFormat:
            @"No se pudieron consultar las apps mediante esta conexión.\n\nCoreDevice: %@\n\nInstallation Proxy: %@",
            appServiceFailure.localizedDescription ?: @"Sin respuesta válida.",
            installationFailure.localizedDescription ?: @"Sin respuesta válida."]);
        [self recordClosedAdapterError:failure];
    }];
    if (!result && error) *error = failure;
    return result;
}
- (NSString *)validatedRelativePath:(NSString *)path error:(NSError **)error {
    const char *utf8 = path.UTF8String;
    if ([path hasPrefix:@"/"] || !utf8 || strlen(utf8) != [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
        if (error) *error = XFError(1008, @"Introduce una ruta relativa dentro del contenedor de la app."); return nil;
    }
    for (NSString *part in path.pathComponents) {
        if ([part isEqualToString:@".."]) { if (error) *error = XFError(1008, @"La ruta no puede salir del contenedor de la app."); return nil; }
    }
    return path.length ? path : @".";
}
- (NSString *)validatedKnownFileRelativePath:(NSString *)path error:(NSError **)error {
    const char *bytes = [path isKindOfClass:NSString.class] ? path.UTF8String : NULL;
    if (!bytes || !path.length || [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096 ||
        strlen(bytes) != [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] ||
        [path hasPrefix:@"/"] || [path containsString:@"\\"]) {
        if (error) *error = XFError(1008, @"Introduce la ruta relativa completa de un archivo dentro del contenedor de la app.");
        return nil;
    }
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count > 128) {
        if (error) *error = XFError(1008, @"La ruta del archivo contiene demasiadas carpetas."); return nil;
    }
    for (NSString *part in parts) {
        if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."]) {
            if (error) *error = XFError(1008, @"La ruta debe identificar un archivo y no puede salir del contenedor de la app.");
            return nil;
        }
    }
    return path;
}
- (void)recordFileServiceStage:(NSString *)stage success:(BOOL)success error:(NSError *)error {
    NSMutableDictionary *report = [_fileServiceAttempt mutableCopy];
    report[@"stage"] = stage;
    report[@"stageSucceeded"] = @(success);
    report[@"code"] = @(success ? 0 : error.code ?: -1);
    _fileServiceAttempt = [report copy];
}
- (BOOL)openFileServiceDomain:(IdeviceFileServiceDomain)domain identifier:(NSString *)identifier session:(XFFileServiceSession *)session error:(NSError **)error {
    const char *identifierBytes = identifier.UTF8String;
    if (!identifier.length || !identifierBytes || strlen(identifierBytes) != [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
        if (error) *error = XFError(1009, @"Falta un identificador válido de la app o App Group."); return NO;
    }
    // Never skip FileService because the catalog's retained RSD map omitted it.
    // The supplied 3105 executable discovers services on a fresh tunnel here.
    BOOL success = [self newServiceTunnelWithAdapter:&session->adapter handshake:&session->handshake error:error];
    [self recordFileServiceStage:@"tunnel" success:success error:error ? *error : nil];
    NSMutableDictionary *report = [_fileServiceAttempt mutableCopy];
    report[@"freshTunnelEstablished"] = @(success);
    if (success) {
        CRsdService *advertised = NULL;
        IdeviceFfiError *probe = rsd_get_service_info(session->handshake, "com.apple.coredevice.fileservice.control", &advertised);
        report[@"controlAdvertised"] = @(!probe && advertised && advertised->port != 0);
        if (probe) idevice_error_free(probe);
        if (advertised) rsd_free_service(advertised);
    }
    _fileServiceAttempt = [report copy];
    if (!success) return NO;
    success = XFConsume(file_service_connect_rsd(session->adapter, session->handshake, &session->service), @"Abrir servicio de archivos en una conexión nueva", error);
    if (success && !session->service) {
        success = NO;
        if (error) *error = XFError(1031, @"El servicio no devolvió una conexión de archivos.");
    }
    [self recordFileServiceStage:@"connect" success:success error:error ? *error : nil];
    if (!success) return NO;
    success = XFConsume(file_service_create_session(session->service, domain, identifierBytes, NULL), @"Abrir contenedor de archivos", error);
    [self recordFileServiceStage:@"session" success:success error:error ? *error : nil];
    return success;
}
- (NSArray<NSDictionary *> *)listDomain:(IdeviceFileServiceDomain)domain identifier:(NSString *)identifier path:(NSString *)path error:(NSError **)error {
    __block NSArray *result; __block NSError *failure;
    [_worker perform:^{
        NSString *relative = [self validatedRelativePath:path error:&failure]; if (!relative) return;
        self->_fileServiceAttempt = @{@"operation":@"List", @"domain":@(domain), @"freshTunnelEstablished":@NO};
        XFFileServiceSession session = {0};
        char **names = NULL; size_t count = 0;
        @try {
            if (![self openFileServiceDomain:domain identifier:identifier session:&session error:&failure]) return;
            BOOL success = XFConsume(file_service_retrieve_directory_list(session.service, relative.UTF8String, &names, &count), @"Listar carpeta", &failure);
            if (success && count && !names) {
                success = NO; failure = XFError(1031, @"El servicio devolvió un listado sin datos.");
            }
            [self recordFileServiceStage:@"list" success:success error:failure];
            if (!success) return;
            NSMutableDictionary<NSString *, NSDictionary *> *byName = [NSMutableDictionary new];
            for (size_t index = 0; index < count; index++) {
                const char *raw = names[index];
                XFFileServiceListingPath entry;
                if (!raw || !XFFileServiceListingParsePath(raw, strlen(raw), &entry)) continue;
                NSString *name = [[NSString alloc] initWithBytes:entry.name length:entry.nameLength encoding:NSUTF8StringEncoding];
                if (!name.length) continue;
                BOOL directory = entry.directoryByDescendant || [byName[name][@"isDirectory"] boolValue];
                byName[name] = @{@"name":name, @"isDirectory":@(directory), @"typeKnown":@(directory)};
            }
            // Match 3105's app-root navigation after a successful response.
            // An error never reaches this block or creates directory rows.
            if (domain == IdeviceFileServiceDomainAppDataContainer && [relative isEqualToString:@"."]) {
                for (NSString *name in @[@"Documents", @"Library", @"SystemData", @"tmp"])
                    byName[name] = @{@"name":name, @"isDirectory":@YES, @"typeKnown":@YES};
            }
            NSMutableArray *rows = [[byName allValues] mutableCopy];
            [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedStandardCompare:b[@"name"]]; }];
            result = rows;
        } @finally {
            if (names) file_service_free_directory_list(names, count);
            XFCloseFileServiceSession(&session);
        }
    }];
    if (!result && error) *error = failure;
    return result;
}
- (NSData *)readDomain:(IdeviceFileServiceDomain)domain identifier:(NSString *)identifier path:(NSString *)path error:(NSError **)error {
    __block NSData *result; __block NSError *failure;
    [_worker perform:^{
        NSString *relative = [self validatedRelativePath:path error:&failure]; if (!relative) return;
        self->_fileServiceAttempt = @{@"operation":@"Read", @"domain":@(domain), @"freshTunnelEstablished":@NO};
        XFFileServiceSession session = {0};
        CRsdService *dataService = NULL;
        uint8_t *bytes = NULL; size_t length = 0;
        @try {
            if (![self openFileServiceDomain:domain identifier:identifier session:&session error:&failure]) return;
            BOOL success = XFConsume(rsd_get_service_info(session.handshake, "com.apple.coredevice.fileservice.data", &dataService), @"Consultar canal de descarga de la conexión nueva", &failure);
            if (success && (!dataService || !dataService->port)) {
                success = NO; failure = XFError(1031, @"El servicio no devolvió un canal de descarga válido.");
            }
            [self recordFileServiceStage:@"data_service" success:success error:failure];
            if (!success) return;
            success = XFConsume(file_service_retrieve_file(session.service, relative.UTF8String, session.adapter, dataService->port, &bytes, &length), @"Leer archivo", &failure);
            if (success) {
                if (length > XFMaximumReadSize) {
                    failure = XFError(1012, @"El archivo supera el límite de lectura de 128 MB.");
                } else if (length && bytes) {
                    result = [[NSData alloc] initWithBytesNoCopy:bytes length:length
                                            deallocator:^(void *buffer, NSUInteger bufferLength) {
                        idevice_data_free(buffer, bufferLength);
                    }];
                    if (result) bytes = NULL; // NSData owns the Rust allocation.
                } else if (length == 0) {
                    result = [NSData data];
                } else {
                    failure = XFError(1011, @"El servicio devolvió un tamaño de archivo sin datos.");
                }
            }
            [self recordFileServiceStage:@"read" success:result != nil error:failure];
        } @finally {
            if (bytes) idevice_data_free(bytes, length);
            if (dataService) rsd_free_service(dataService);
            XFCloseFileServiceSession(&session);
        }
    }];
    if (!result && error) *error = failure;
    return result;
}
- (NSArray<NSDictionary *> *)listDirectoryForApplication:(NSString *)bundleIdentifier relativePath:(NSString *)relativePath error:(NSError **)error {
    return [self accessApplication:bundleIdentifier path:relativePath readFile:NO error:error];
}
- (NSData *)readFileForApplication:(NSString *)bundleIdentifier relativePath:(NSString *)relativePath error:(NSError **)error {
    return [self accessApplication:bundleIdentifier path:relativePath readFile:YES error:error];
}
// Local container leases are independent of pairing and the tunnel. Release the
// extension after copying the listing or file bytes, including failed reads.
- (id)accessNativeContainer:(NSString *)identifier group:(BOOL)group path:(NSString *)path readFile:(BOOL)readFile error:(NSError **)error {
    _nativeContainerFailure = @{};
    _nativeContainerAttempt = @{};
    NSError *failure = nil;
    XFMHAContainerAccess *lease = [XFMHAContainerAccess leaseForBundleID:identifier group:group error:&failure];
    _nativeContainerAttempt = @{@"method":lease.accessMethod ?: @"Unresolved",
        @"alternateBuildSupported":@([XFMHAContainerAccess alternateAccessSupported]),
        @"leaseOpened":@(lease != nil)};
    id result = nil;
    if (lease) {
        @try {
            NSString *relative = [path isEqualToString:@"."] ? @"" : path;
            result = readFile ? [lease readFile:relative maximumBytes:XFMaximumReadSize error:&failure]
                              : [lease listDirectory:relative error:&failure];
        } @finally {
            [lease invalidate];
        }
    }
    _routeResultCodes[group ? @"MHA-C2Group" : @"MHA-C2"] = @(result ? 0 : failure.code ?: -1);
    if (!result) {
        NSMutableDictionary *diagnostic = [NSMutableDictionary new];
        id stage = failure.userInfo[@"MHAStage"];
        if ([stage isKindOfClass:NSString.class] &&
            [@[@"query_result", @"object_copy", @"sandbox_token", @"sandbox_activate"] containsObject:stage]) diagnostic[@"MHAStage"] = stage;
        id nativeError = failure.userInfo[@"NativePOSIXError"];
        if ([nativeError isKindOfClass:NSNumber.class]) diagnostic[@"NativePOSIXError"] = @([nativeError longLongValue]);
        id alternateStage = failure.userInfo[@"BadQueryStage"];
        if ([alternateStage isKindOfClass:NSString.class] &&
            [@[@"invalid_input",@"missing_api",@"allocation",@"query_result",@"sandbox_token",@"sandbox_consume"] containsObject:alternateStage]) diagnostic[@"BadQueryStage"] = alternateStage;
        id originalCode = failure.userInfo[@"MHAErrorCode"];
        if ([originalCode isKindOfClass:NSNumber.class]) diagnostic[@"MHAErrorCode"] = @([originalCode longLongValue]);
        _nativeContainerFailure = [diagnostic copy];
    }
    if (result && !readFile) _directoryWarning = @"Carpeta abierta mediante acceso directo. Puedes previsualizar o exportar los archivos que iOS permita leer.";
    if (!result && error) *error = failure;
    return result;
}
- (NSArray<NSDictionary *> *)listDirectoryForAppGroup:(NSString *)groupIdentifier relativePath:(NSString *)relativePath error:(NSError **)error {
    __block NSArray *result; __block NSError *failure;
    [_worker perform:^{
        self->_directoryWarning = @"";
        self->_fileServiceAttempt = @{};
        NSString *relative = [self validatedRelativePath:relativePath error:&failure]; if (!relative) return;
        NSError *nativeFailure = nil;
        result = [self accessNativeContainer:groupIdentifier group:YES path:relative readFile:NO error:&nativeFailure];
        if (result) return;
        if (![self requireConnection:&failure]) {
            failure = XFError(1025, [NSString stringWithFormat:@"Acceso directo: %@\n\nTúnel: %@", nativeFailure.localizedDescription ?: @"No autorizado.", failure.localizedDescription]);
            return;
        }
        NSError *fileFailure = nil;
        result = [self listDomain:IdeviceFileServiceDomainAppGroupDataContainer identifier:groupIdentifier path:relative error:&fileFailure];
        self->_routeResultCodes[@"CoreDeviceGroup"] = @(result ? 0 : fileFailure.code ?: -1);
        if (result) return;
        result = [self listATCDirectoryForIdentifier:groupIdentifier shared:YES path:relative error:&failure];
        if (!result) failure = XFError(1025, [NSString stringWithFormat:@"Acceso directo: %@\n\nCoreDevice: %@\n\nAirLift: %@", nativeFailure.localizedDescription ?: @"No autorizado.", fileFailure.localizedDescription ?: @"Servicio no disponible.", failure.localizedDescription ?: @"No se pudo listar la carpeta."]);
    }];
    if (!result && error) *error = failure;
    return result;
}
- (NSData *)readFileForAppGroup:(NSString *)groupIdentifier relativePath:(NSString *)relativePath error:(NSError **)error {
    __block NSData *result; __block NSError *failure;
    [_worker perform:^{
        self->_fileServiceAttempt = @{};
        NSString *relative = [self validatedRelativePath:relativePath error:&failure]; if (!relative) return;
        NSError *nativeFailure = nil;
        result = [self accessNativeContainer:groupIdentifier group:YES path:relative readFile:YES error:&nativeFailure];
        if (result) return;
        result = [self readDomain:IdeviceFileServiceDomainAppGroupDataContainer identifier:groupIdentifier path:relative error:&failure];
        self->_routeResultCodes[@"CoreDeviceGroup"] = @(result ? 0 : failure.code ?: -1);
        if (!result) failure = XFError(1025, [NSString stringWithFormat:@"Acceso directo: %@\n\nCoreDevice: %@", nativeFailure.localizedDescription ?: @"No autorizado.", failure.localizedDescription ?: @"No se pudo leer el archivo."]);
    }];
    if (!result && error) *error = failure;
    return result;
}
// VendContainer and VendDocuments both consume the HouseArrest handle, even
// when the device rejects the command. Each attempt needs a fresh connection.
- (AfcClientHandle *)openHouseArrestForApplication:(NSString *)identifier documentsOnly:(BOOL)documentsOnly error:(NSError **)error {
    HouseArrestClientHandle *client = NULL;
    if (!XFConsume(house_arrest_client_connect_rsd(_adapter, _handshake, &client),
                   @"Abrir acceso a documentos de apps", error)) {
        if (client) house_arrest_client_free(client);
        return NULL;
    }
    if (!client) {
        if (error) *error = XFError(1015, @"El iPhone no devolvió una conexión válida para los archivos de apps.");
        return NULL;
    }
    AfcClientHandle *afc = NULL;
    HouseArrestClientHandle *consumed = client;
    client = NULL;
    IdeviceFfiError *native = documentsOnly
        ? house_arrest_vend_documents(consumed, identifier.UTF8String, &afc)
        : house_arrest_vend_container(consumed, identifier.UTF8String, &afc);
    BOOL ok = XFConsume(native, documentsOnly ? @"Solicitar carpeta Documents" : @"Solicitar contenedor de la app", error);
    if (!ok || !afc) {
        if (afc) afc_client_free(afc);
        if (ok && error) *error = XFError(1015, @"El iPhone no devolvió una conexión válida para esta carpeta.");
        return NULL;
    }
    return afc;
}
- (NSString *)normalizedApplicationPath:(NSString *)relative {
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    for (NSString *part in relative.pathComponents) {
        if (!part.length || [part isEqualToString:@"."]) continue;
        [parts addObject:part];
    }
    return [parts componentsJoinedByString:@"/"];
}
- (NSArray<NSDictionary *> *)listAFC:(AfcClientHandle *)afc path:(NSString *)path error:(NSError **)error {
    char **names = NULL; size_t count = 0;
    BOOL ok = XFConsume(afc_list_directory(afc, path.UTF8String, &names, &count), @"Listar carpeta de la app", error);
    if (ok && count && !names) {
        if (error) *error = XFError(1016, @"El iPhone devolvió un listado sin datos.");
        ok = NO;
    }
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray new];
    if (ok) {
        for (size_t index = 0; index < count; index++) {
            NSString *name = names[index] ? [NSString stringWithUTF8String:names[index]] : nil;
            if (!name.length || [name isEqualToString:@"."] || [name isEqualToString:@".."] || [name containsString:@"/"]) continue;
            AfcFileInfo info = {0};
            NSString *entryPath = [path stringByAppendingPathComponent:name];
            IdeviceFfiError *statFailure = afc_get_file_info(afc, entryPath.UTF8String, &info);
            BOOL directory = NO, typeKnown = NO;
            if (!statFailure && info.st_ifmt) {
                directory = strcmp(info.st_ifmt, "S_IFDIR") == 0;
                // Symlinks and other types remain unknown to the browser.
                typeKnown = directory || strcmp(info.st_ifmt, "S_IFREG") == 0;
            }
            if (statFailure) idevice_error_free(statFailure);
            afc_file_info_free(&info);
            [rows addObject:@{@"name":name, @"isDirectory":@(directory), @"typeKnown":@(typeKnown)}];
        }
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedStandardCompare:b[@"name"]];
        }];
    }
    if (names) {
        for (size_t index = 0; index < count; index++) {
            if (names[index]) idevice_string_free(names[index]);
        }
        // afc_list_directory allocates count + 1 pointers with Rust's System
        // allocator in the pinned Apple build; the final pointer is NULL.
        free(names);
    }
    return ok ? rows : nil;
}
- (NSData *)readAFC:(AfcClientHandle *)afc path:(NSString *)path error:(NSError **)error {
    AfcFileInfo info = {0};
    if (!XFConsume(afc_get_file_info(afc, path.UTF8String, &info), @"Consultar archivo de la app", error)) {
        afc_file_info_free(&info);
        return nil;
    }
    BOOL regular = info.st_ifmt && strcmp(info.st_ifmt, "S_IFREG") == 0;
    size_t length = info.size;
    afc_file_info_free(&info);
    if (!regular) {
        if (error) *error = XFError(1017, @"La ruta seleccionada no es un archivo regular. Abre las carpetas desde el listado.");
        return nil;
    }
    if (length > XFMaximumReadSize) {
        if (error) *error = XFError(1018, @"El archivo supera el límite de lectura de 128 MB.");
        return nil;
    }
    AfcFileHandle *file = NULL;
    if (!XFConsume(afc_file_open(afc, path.UTF8String, AfcRdOnly, &file), @"Abrir archivo de la app", error)) return nil;
    if (!file) {
        if (error) *error = XFError(1016, @"El iPhone no devolvió un archivo válido.");
        return nil;
    }
    // Bound each Rust allocation and the result. Do not call read_entire,
    // whose convenience implementation allocates from a fresh remote stat.
    NSMutableData *data = [NSMutableData dataWithCapacity:MIN(length, (size_t)(1024 * 1024))];
    BOOL ok = YES;
    while (data.length < length) {
        size_t wanted = MIN(length - data.length, (size_t)(1024 * 1024));
        uint8_t *bytes = NULL; size_t received = 0;
        ok = XFConsume(afc_file_read(file, &bytes, wanted, &received), @"Leer archivo de la app", error);
        if (ok && (!received || !bytes || received > wanted)) {
            if (error) *error = XFError(1016, @"La lectura del archivo quedó incompleta. El archivo puede haber cambiado; inténtalo otra vez.");
            ok = NO;
        }
        if (ok) [data appendBytes:bytes length:received];
        if (bytes) afc_file_read_data_free(bytes, received);
        if (!ok) break;
    }
    // Closing consumes the handle even on a native error; the AFC client stays
    // alive until this returns, all on the same dedicated worker thread.
    NSError *closeFailure = nil;
    BOOL closed = XFConsume(afc_file_close(file), @"Cerrar archivo de la app", &closeFailure);
    file = NULL;
    if (ok && !closed) {
        if (error) *error = closeFailure;
        ok = NO;
    }
    return ok ? data : nil;
}
- (id)accessHouseArrestApplication:(NSString *)identifier path:(NSString *)relative readFile:(BOOL)readFile error:(NSError **)error {
    NSString *normalized = [self normalizedApplicationPath:relative];
    NSMutableArray<NSString *> *failures = [NSMutableArray new];
    for (NSNumber *documentsMode in @[@NO, @YES]) {
        BOOL documentsOnly = documentsMode.boolValue;
        NSError *failure = nil;
        AfcClientHandle *afc = [self openHouseArrestForApplication:identifier documentsOnly:documentsOnly error:&failure];
        id result = nil;
        if (afc) {
            if (documentsOnly && !normalized.length && !readFile) {
                // VendDocuments exposes the same AFC namespace, but only the
                // Documents subtree is permitted. Confirm it before showing a
                // virtual app root containing that single folder.
                if ([self listAFC:afc path:@"/Documents" error:&failure]) {
                    result = @[@{@"name":@"Documents", @"isDirectory":@YES, @"typeKnown":@YES}];
                }
            } else if (documentsOnly && !([normalized isEqualToString:@"Documents"] || [normalized hasPrefix:@"Documents/"])) {
                failure = XFError(1019, @"Esta app solo permite compartir su carpeta Documents. La ruta solicitada queda fuera de esa carpeta.");
            } else {
                NSString *afcPath = normalized.length ? [@"/" stringByAppendingString:normalized] : @"/";
                result = readFile ? [self readAFC:afc path:afcPath error:&failure]
                                  : [self listAFC:afc path:afcPath error:&failure];
            }
            afc_client_free(afc);
        }
        if (result) return result;
        [failures addObject:[NSString stringWithFormat:@"%@: %@", documentsOnly ? @"Documents" : @"Contenedor",
            failure.localizedDescription ?: @"El iPhone no concedió acceso."]];
    }
    if (error) *error = XFError(1020, [failures componentsJoinedByString:@"\n\n"]);
    return nil;
}
- (NSString *)atcAbsolutePathForIdentifier:(NSString *)identifier shared:(BOOL)shared path:(NSString *)relative error:(NSError **)error {
    _containerResolution = @{@"sourceField":@"None", @"conflictingRootValues":@NO,
                            @"metadataRefreshed":@NO, @"previousRootChanged":@NO};
    if (![self requireConnection:error]) return nil;
    if (![self atcDirectoryAvailableNative]) {
        if (error) *error = XFError(1026, @"La conexión no anuncia los tres servicios necesarios para la ruta AirLift.");
        return nil;
    }
    NSString *previousRoot = shared ? _groupContainers[identifier] : _applicationContainers[identifier];
    NSError *metadataFailure = nil;
    NSArray *metadata = [self applicationsFromInstallationProxyWithError:&metadataFailure];
    _catalogResultCodes[@"InstallationProxyMetadata"] = @(metadata ? 0 : metadataFailure.code ?: -1);
    if (!metadata) { if (error) *error = metadataFailure; return nil; }
    NSString *root = [self validatedContainerRoot:(shared ? _groupContainers[identifier] : _applicationContainers[identifier]) shared:shared];
    NSDictionary *resolution = shared ? _groupContainerResolution[identifier] : _applicationContainerResolution[identifier];
    // Only fixed field names and booleans leave the worker in diagnostics.
    _containerResolution = @{@"sourceField":resolution[@"sourceField"] ?: @"None",
        @"conflictingRootValues":@([resolution[@"conflictingRootValues"] boolValue]),
        @"metadataRefreshed":@YES,
        @"previousRootChanged":@(previousRoot.length && ![previousRoot isEqualToString:root])};
    if (!root.length) {
        if (error) *error = XFError(1027, @"iOS no devolvió la ruta del contenedor de datos de esta entrada. Algunas entradas del catálogo son servicios del sistema y no tienen un contenedor de app que pueda explorarse.");
        return nil;
    }
    NSString *normalized = [self normalizedApplicationPath:relative];
    return normalized.length ? [root stringByAppendingPathComponent:normalized] : root;
}
- (NSData *)readATCFileForIdentifier:(NSString *)identifier shared:(BOOL)shared path:(NSString *)relative error:(NSError **)error {
    NSString *filePath = [self validatedKnownFileRelativePath:relative error:error];
    NSString *absolute = filePath ? [self atcAbsolutePathForIdentifier:identifier shared:shared path:filePath error:error] : nil;
    XFATCDirectory *directory = absolute ? [self atcDirectoryNativeWithError:error] : nil;
    NSData *result = directory ? [directory readAbsoluteFile:absolute maximumBytes:XFMaximumKnownFileSize error:error] : nil;
    _routeResultCodes[shared ? @"AirTrafficReadGroup" : @"AirTrafficRead"] = @(result ? 0 : (error && *error ? (*error).code : -1));
    if (directory) _directoryWarning = [directory.lastWarning copy] ?: @"";
    return result;
}
- (BOOL)replaceFileForApplication:(NSString *)identifier relativePath:(NSString *)path data:(NSData *)data error:(NSError **)error {
    __block BOOL replaced = NO; __block NSError *failure = nil;
    if (![data isKindOfClass:NSData.class] || data.length > XFMaximumKnownFileSize) {
        if (error) *error = XFError(1033, @"El archivo elegido supera el límite de reemplazo de 64 MiB."); return NO;
    }
    NSData *replacement = [data copy];
    [_worker perform:^{
        self->_directoryWarning = @"";
        self->_fileServiceAttempt = @{};
        const char *identifierBytes = [identifier isKindOfClass:NSString.class] ? identifier.UTF8String : NULL;
        if (!identifier.length || !identifierBytes || strlen(identifierBytes) != [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
            failure = XFError(1009, @"Falta un identificador válido de la app."); return;
        }
        NSString *relative = [self validatedKnownFileRelativePath:path error:&failure];
        NSString *absolute = relative ? [self atcAbsolutePathForIdentifier:identifier shared:NO path:relative error:&failure] : nil;
        XFATCDirectory *directory = absolute ? [self atcDirectoryNativeWithError:&failure] : nil;
        if (directory) {
            replaced = [directory replaceAbsoluteFile:absolute data:replacement error:&failure];
            self->_directoryWarning = [directory.lastWarning copy] ?: @"";
        }
        self->_routeResultCodes[@"AirTrafficReplace"] = @(replaced ? 0 : failure.code ?: -1);
    }];
    if (!replaced && error) *error = failure;
    return replaced;
}
- (BOOL)restorePendingFileForApplication:(NSString *)identifier relativePath:(NSString *)path error:(NSError **)error {
    __block BOOL restored = NO; __block NSError *failure = nil;
    [_worker perform:^{
        self->_directoryWarning = @"";
        self->_fileServiceAttempt = @{};
        const char *identifierBytes = [identifier isKindOfClass:NSString.class] ? identifier.UTF8String : NULL;
        if (!identifier.length || !identifierBytes || strlen(identifierBytes) != [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
            failure = XFError(1009, @"Falta un identificador válido de la app."); return;
        }
        NSString *relative = [self validatedKnownFileRelativePath:path error:&failure];
        NSString *absolute = relative ? [self atcAbsolutePathForIdentifier:identifier shared:NO path:relative error:&failure] : nil;
        XFATCDirectory *directory = absolute ? [self atcDirectoryNativeWithError:&failure] : nil;
        if (directory) {
            restored = [directory recoverPendingKnownFileAtPath:absolute error:&failure];
            self->_directoryWarning = [directory.lastWarning copy] ?: @"";
        }
        self->_routeResultCodes[@"AirTrafficRestore"] = @(restored ? 0 : failure.code ?: -1);
    }];
    if (!restored && error) *error = failure;
    return restored;
}
- (BOOL)deleteFileForApplication:(NSString *)identifier relativePath:(NSString *)path error:(NSError **)error {
    __block BOOL deleted = NO; __block NSError *failure = nil;
    [_worker perform:^{
        self->_directoryWarning = @"";
        self->_fileServiceAttempt = @{};
        self->_lastDeletedFileBackupURL = nil;
        self->_lastDeletionAbsenceConfirmed = NO;
        const char *identifierBytes = [identifier isKindOfClass:NSString.class] ? identifier.UTF8String : NULL;
        if (!identifier.length || !identifierBytes || strlen(identifierBytes) != [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
            failure = XFError(1009, @"Falta un identificador válido de la app."); return;
        }
        NSString *relative = [self validatedKnownFileRelativePath:path error:&failure];
        if ([@[@"Documents", @"Library", @"SystemData", @"tmp"] containsObject:relative]) {
            failure = XFError(1034, @"La ruta corresponde a una carpeta de la app. Elige un archivo dentro de ella."); return;
        }
        NSString *absolute = relative ? [self atcAbsolutePathForIdentifier:identifier shared:NO path:relative error:&failure] : nil;
        XFATCDirectory *directory = absolute ? [self atcDirectoryNativeWithError:&failure] : nil;
        if (directory) {
            deleted = [directory deleteAbsoluteFile:absolute error:&failure];
            self->_directoryWarning = [directory.lastWarning copy] ?: @"";
            self->_lastDeletedFileBackupURL = [directory.deletedFileBackupURL copy];
            self->_lastDeletionAbsenceConfirmed = directory.deletionAbsenceConfirmed;
        }
        self->_routeResultCodes[@"AirTrafficDelete"] = @(deleted ? 0 : failure.code ?: -1);
    }];
    if (!deleted && error) *error = failure;
    return deleted;
}
- (NSArray<NSDictionary *> *)listATCDirectoryForIdentifier:(NSString *)identifier shared:(BOOL)shared path:(NSString *)relative error:(NSError **)error {
    NSString *absolute = [self atcAbsolutePathForIdentifier:identifier shared:shared path:relative error:error];
    if (!absolute) return nil;
    XFATCDirectory *directory = [self atcDirectoryNativeWithError:error];
    if (!directory) return nil;
    NSArray<NSDictionary *> *result = [directory listAbsoluteDirectory:absolute error:error];
    _routeResultCodes[@"AirTrafficDirectory"] = @(result ? 0 : (error && *error ? (*error).code : -1));
    _directoryWarning = [directory.lastWarning copy] ?: @"";
    if (!result) return nil;
    // Permit a fresh FileService read attempt. A retained service map cannot
    // decide whether the next connection will offer a download channel.
    BOOL readRoute = _connected;
    if (!readRoute) {
        NSMutableArray *rows = [NSMutableArray new];
        for (NSDictionary *entry in result) {
            NSMutableDictionary *row = [entry mutableCopy]; row[@"canRead"] = @NO; [rows addObject:row];
        }
        NSString *note = @"AirLift permite listar estas carpetas. Esta conexión aún no tiene una ruta para previsualizar o exportar su contenido.";
        _directoryWarning = _directoryWarning.length ? [NSString stringWithFormat:@"%@\n%@", note, _directoryWarning] : note;
        return rows;
    }
    return result;
}
- (id)accessApplication:(NSString *)identifier path:(NSString *)path readFile:(BOOL)readFile error:(NSError **)error {
    __block id result = nil; __block NSError *failure = nil;
    [_worker perform:^{
        self->_directoryWarning = @"";
        self->_fileServiceAttempt = @{};
        const char *identifierBytes = identifier.UTF8String;
        if (!identifier.length || !identifierBytes || strlen(identifierBytes) != [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
            failure = XFError(1009, @"Falta un identificador válido de la app.");
            return;
        }
        NSString *relative = [self validatedRelativePath:path error:&failure];
        if (!relative) return;
        NSError *nativeFailure = nil;
        result = [self accessNativeContainer:identifier group:NO path:relative readFile:readFile error:&nativeFailure];
        if (result) return;
        if (![self requireConnection:&failure]) {
            failure = XFError(1022, [NSString stringWithFormat:@"Acceso directo: %@\n\nTúnel: %@", nativeFailure.localizedDescription ?: @"No autorizado.", failure.localizedDescription]);
            return;
        }
        NSError *fileServiceFailure = nil;
        result = readFile
            ? [self readDomain:IdeviceFileServiceDomainAppDataContainer identifier:identifier path:relative error:&fileServiceFailure]
            : [self listDomain:IdeviceFileServiceDomainAppDataContainer identifier:identifier path:relative error:&fileServiceFailure];
        self->_routeResultCodes[@"CoreDevice"] = @(result ? 0 : fileServiceFailure.code ?: -1);
        if (result) return;
        NSError *houseArrestFailure = nil;
        if ([self hasRSDService:"com.apple.mobile.house_arrest.shim.remote"]) {
            result = [self accessHouseArrestApplication:identifier path:relative readFile:readFile error:&houseArrestFailure];
            self->_routeResultCodes[@"HouseArrest"] = @(result ? 0 : houseArrestFailure.code ?: -1);
        } else {
            houseArrestFailure = XFError(1021, @"El iPhone no anunció el servicio de documentos de apps.");
            self->_routeResultCodes[@"HouseArrest"] = @(1021);
        }
        if (result) return;
        NSError *atcFailure = nil;
        if (!readFile) {
            result = [self listATCDirectoryForIdentifier:identifier shared:NO path:relative error:&atcFailure];
            if (result) {
                [self recordClosedAdapterError:houseArrestFailure];
                return;
            }
        } else {
            result = [self readATCFileForIdentifier:identifier shared:NO path:relative error:&atcFailure];
            if (result) {
                [self recordClosedAdapterError:houseArrestFailure];
                return;
            }
        }
        if (!result) {
            failure = XFError(1022, [NSString stringWithFormat:
                @"No se pudo abrir esta ruta de la app.\n\nAcceso directo: %@\n\nCoreDevice: %@\n\nDocumentos de apps: %@\n\nAirLift: %@",
                nativeFailure.localizedDescription ?: @"No se pudo autorizar el contenedor.",
                fileServiceFailure.localizedDescription ?: @"No se pudo abrir la ruta.",
                houseArrestFailure.localizedDescription ?: @"No se pudo abrir la ruta.",
                atcFailure.localizedDescription ?: @"No hay una ruta adicional de lectura."]);
            [self recordClosedAdapterError:houseArrestFailure];
        }
    }];
    if (!result && error) *error = failure;
    return result;
}
@end

