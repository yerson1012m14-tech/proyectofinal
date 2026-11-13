#import <NetworkExtension/NetworkExtension.h>
#import <sys/socket.h>
#import "XFProxyProtocol.h"

@interface XFProxyPacketTunnelProvider : NEPacketTunnelProvider <NSURLSessionWebSocketDelegate>
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSURLSession *webSession;
@property (nonatomic, strong) NSURLSessionWebSocketTask *socket;
@property (nonatomic, strong) dispatch_source_t heartbeat;
@property (nonatomic, copy) void (^startCompletion)(NSError *);
@property (nonatomic) BOOL applyingSettings;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL waitingForPong;
@end

@implementation XFProxyPacketTunnelProvider

- (instancetype)init {
    self = [super init];
    if (self) _queue = dispatch_queue_create("com.xitforge.proxy.provider", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)startTunnelWithOptions:(NSDictionary<NSString *, NSObject *> *)options completionHandler:(void (^)(NSError *))completion {
    dispatch_async(self.queue, ^{
        NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)self.protocolConfiguration;
        NSURL *gateway = [protocol isKindOfClass:NETunnelProviderProtocol.class] ?
            XFProxyValidatedGateway(protocol.providerConfiguration[XFProxyGatewayKey]) : nil;
        if (!gateway) {
            completion(XFProxyError(XFProxyErrorConfiguration, @"Falta configurar el servidor del proxy en esta versión."));
            return;
        }
        id token = options[XFProxyTokenOption];
        if (!XFProxyValidToken(token)) {
            completion(XFProxyError(XFProxyErrorLicenseDenied, @"Abre XITFORGE y vuelve a conectar el proxy."));
            return;
        }
        self.startCompletion = completion;
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 15;
        configuration.HTTPShouldSetCookies = NO;
        configuration.URLCredentialStorage = nil;
        self.webSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:gateway];
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        NSURLSessionWebSocketTask *task = [self.webSession webSocketTaskWithRequest:request];
        task.maximumMessageSize = XFProxyPacketLimit;
        self.socket = task;
        [task resume];
        [self receive:task];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), self.queue, ^{
            if (self.socket == task && self.startCompletion) {
                [self fail:XFProxyError(XFProxyErrorTimeout, @"El servidor del proxy tardó demasiado en responder.")];
            }
        });
    });
}

- (void)receive:(NSURLSessionWebSocketTask *)task {
    __weak typeof(self) weakSelf = self;
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        XFProxyPacketTunnelProvider *provider = weakSelf;
        if (!provider) return;
        dispatch_async(provider.queue, ^{
            if (provider.socket != task) return;
            if (error || !message) {
                [provider fail:[provider failureForTask:task]];
                return;
            }
            if (!provider.active) {
                NSData *jsonData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
                id json = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL] : nil;
                if (message.type != NSURLSessionWebSocketMessageTypeString || ![json isKindOfClass:NSDictionary.class] ||
                    ![json[@"type"] isEqual:@"ready"] || provider.applyingSettings) {
                    [provider fail:XFProxyError(XFProxyErrorProtocol, @"El servidor devolvió una respuesta incompatible.")];
                    return;
                }
                [provider applySettingsForTask:task];
                return;
            }
            if (message.type != NSURLSessionWebSocketMessageTypeData || !XFProxyValidPacket(message.data, NO)) {
                [provider fail:XFProxyError(XFProxyErrorProtocol, @"El servidor devolvió un paquete incompatible.")];
                return;
            }
            [provider.packetFlow writePackets:@[message.data] withProtocols:@[@(AF_INET)]];
            [provider receive:task];
        });
    }];
}

- (void)applySettingsForTask:(NSURLSessionWebSocketTask *)task {
    self.applyingSettings = YES;
    // iOS excludes tunnelRemoteAddress from the route. The real transport is a separate WSS connection.
    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[XFProxyClientAddress] subnetMasks:@[@"255.255.255.255"]];
    ipv4.includedRoutes = @[[[NEIPv4Route alloc] initWithDestinationAddress:XFProxyRemoteAddress subnetMask:@"255.255.255.255"]];
    settings.IPv4Settings = ipv4;
    settings.MTU = @(XFProxyMTU);

    NEProxySettings *proxy = [NEProxySettings new];
    proxy.HTTPEnabled = YES;
    proxy.HTTPSEnabled = YES;
    proxy.HTTPServer = [[NEProxyServer alloc] initWithAddress:XFProxyRemoteAddress port:XFProxyPort];
    proxy.HTTPSServer = [[NEProxyServer alloc] initWithAddress:XFProxyRemoteAddress port:XFProxyPort];
    proxy.excludeSimpleHostnames = YES;
    proxy.matchDomains = @[@"freefiremobile.com", @"loginbp.ggpolarbear.com", @"loginbp.ppmainecoonghj.com"];
    settings.proxySettings = proxy;

    __weak typeof(self) weakSelf = self;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError *error) {
        XFProxyPacketTunnelProvider *provider = weakSelf;
        if (!provider) return;
        dispatch_async(provider.queue, ^{
            if (provider.socket != task) return;
            provider.applyingSettings = NO;
            if (error) {
                [provider fail:XFProxyError(XFProxyErrorConfiguration, @"iOS no pudo aplicar la configuración del proxy.")];
                return;
            }
            provider.active = YES;
            void (^completion)(NSError *) = provider.startCompletion;
            provider.startCompletion = nil;
            if (completion) completion(nil);
            [provider beginHeartbeat:task];
            [provider receive:task];
            [provider readPackets:task];
        });
    }];
}

- (void)readPackets:(NSURLSessionWebSocketTask *)task {
    __weak typeof(self) weakSelf = self;
    [self.packetFlow readPacketsWithCompletionHandler:^(NSArray<NSData *> *packets, NSArray<NSNumber *> *families) {
        XFProxyPacketTunnelProvider *provider = weakSelf;
        if (!provider) return;
        dispatch_async(provider.queue, ^{
            if (provider.socket == task && provider.active) [provider sendPackets:packets families:families index:0 task:task];
        });
    }];
}

- (void)sendPackets:(NSArray<NSData *> *)packets families:(NSArray<NSNumber *> *)families index:(NSUInteger)index task:(NSURLSessionWebSocketTask *)task {
    NSUInteger count = MIN(packets.count, families.count);
    while (index < count && (families[index].intValue != AF_INET || !XFProxyValidPacket(packets[index], YES))) index++;
    if (index == count) {
        [self readPackets:task];
        return;
    }
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:packets[index]];
    __weak typeof(self) weakSelf = self;
    [task sendMessage:message completionHandler:^(NSError *error) {
        XFProxyPacketTunnelProvider *provider = weakSelf;
        if (!provider) return;
        dispatch_async(provider.queue, ^{
            if (provider.socket != task || !provider.active) return;
            if (error) [provider fail:[provider failureForTask:task]];
            else [provider sendPackets:packets families:families index:index + 1 task:task];
        });
    }];
}

- (void)beginHeartbeat:(NSURLSessionWebSocketTask *)task {
    self.heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(self.heartbeat, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), 20 * NSEC_PER_SEC, NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.heartbeat, ^{
        XFProxyPacketTunnelProvider *provider = weakSelf;
        if (!provider || provider.socket != task) return;
        if (provider.waitingForPong) {
            [provider fail:XFProxyError(XFProxyErrorTimeout, @"Se perdió la conexión con el servidor del proxy.")];
            return;
        }
        provider.waitingForPong = YES;
        [task sendPingWithPongReceiveHandler:^(NSError *error) {
            dispatch_async(provider.queue, ^{
                if (provider.socket != task) return;
                provider.waitingForPong = NO;
                if (error) [provider fail:[provider failureForTask:task]];
            });
        }];
    });
    dispatch_resume(self.heartbeat);
}

- (NSError *)failureForTask:(NSURLSessionWebSocketTask *)task {
    return [self failureForTask:task closeCode:task.closeCode];
}

- (NSError *)failureForTask:(NSURLSessionWebSocketTask *)task closeCode:(NSInteger)code {
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    if (status == 401 || status == 403 || code == 4003) {
        return XFProxyError(XFProxyErrorLicenseDenied, @"La licencia ya no autoriza esta conexión. Revisa tu key en XITFORGE.");
    }
    if (status == 503 || code == 1013) {
        return XFProxyError(XFProxyErrorLicenseUnavailable, @"No se pudo comprobar el acceso al proxy. Intenta de nuevo.");
    }
    if (code == 1008) return XFProxyError(XFProxyErrorProtocol, @"El servidor rechazó la configuración del túnel.");
    return XFProxyError(XFProxyErrorTransport, @"Se interrumpió la conexión con el servidor del proxy.");
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {
    dispatch_async(self.queue, ^{
        if (self.socket == task) [self fail:[self failureForTask:task closeCode:code]];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) return;
    dispatch_async(self.queue, ^{
        if (self.socket == task) [self fail:[self failureForTask:self.socket]];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    // The grant is only valid at the configured gateway.
    completion(nil);
}

- (void)fail:(NSError *)error {
    void (^completion)(NSError *) = self.startCompletion;
    self.startCompletion = nil;
    BOOL wasActive = self.active;
    [self closeTransport];
    if (completion) completion(error);
    else if (wasActive) [self cancelTunnelWithError:error];
}

- (void)closeTransport {
    self.active = NO;
    self.applyingSettings = NO;
    self.waitingForPong = NO;
    if (self.heartbeat) dispatch_source_cancel(self.heartbeat);
    self.heartbeat = nil;
    NSURLSessionWebSocketTask *task = self.socket;
    self.socket = nil;
    [task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    [self.webSession invalidateAndCancel];
    self.webSession = nil;
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completion {
    dispatch_async(self.queue, ^{
        void (^pending)(NSError *) = self.startCompletion;
        self.startCompletion = nil;
        [self closeTransport];
        if (pending) pending([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        completion();
    });
}

@end
