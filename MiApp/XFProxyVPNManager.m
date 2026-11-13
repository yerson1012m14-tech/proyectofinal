#import "XFProxyVPNManager.h"
#import "LicenseValidator.h"
#import "XFLocalVPNManager.h"
#import "../XFProxyTunnel/XFProxyProtocol.h"

NSNotificationName const XFProxyVPNDidChangeNotification = @"XFProxyVPNDidChangeNotification";

@interface XFProxyVPNManager () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NETunnelProviderManager *manager;
@property (nonatomic, strong) id observer;
@property (nonatomic, strong) NSURLSession *licenseSession;
@property (nonatomic, strong) NSURLSessionDataTask *licenseTask;
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, getter=isConnecting) BOOL connecting;
@property (nonatomic) BOOL startRequested;
@property (nonatomic) BOOL wasConnected;
@property (nonatomic) BOOL userStopped;
@property (nonatomic) NSUInteger generation;
@end

@implementation XFProxyVPNManager

+ (instancetype)shared {
    static XFProxyVPNManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (NEVPNStatus)status {
    return self.manager ? self.manager.connection.status : NEVPNStatusDisconnected;
}

- (NSURL *)gatewayURL {
    return XFProxyValidatedGateway([NSBundle.mainBundle objectForInfoDictionaryKey:XFProxyGatewayKey]);
}

- (NSURL *)profileURL {
    NSURLComponents *parts = [NSURLComponents componentsWithURL:self.gatewayURL resolvingAgainstBaseURL:NO];
    parts.scheme = @"https";
    parts.path = @"/ca.mobileconfig";
    return parts.URL;
}

- (NSString *)providerID {
    NSURL *extension = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"XFProxyTunnel.appex"];
    return extension ? [NSBundle bundleWithURL:extension].bundleIdentifier : nil;
}

- (NETunnelProviderManager *)managerForID:(NSString *)providerID inManagers:(NSArray<NETunnelProviderManager *> *)managers {
    for (NETunnelProviderManager *item in managers) {
        NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)item.protocolConfiguration;
        if ([protocol isKindOfClass:NETunnelProviderProtocol.class] && [protocol.providerBundleIdentifier isEqualToString:providerID]) return item;
    }
    return nil;
}

- (void)observeManager:(NETunnelProviderManager *)manager {
    if (self.manager == manager) return;
    if (self.observer) [NSNotificationCenter.defaultCenter removeObserver:self.observer];
    self.observer = nil;
    self.manager = manager;
    self.wasConnected = manager.connection.status == NEVPNStatusConnected;
    if (!manager) return;
    __weak typeof(self) weakSelf = self;
    self.observer = [NSNotificationCenter.defaultCenter addObserverForName:NEVPNStatusDidChangeNotification
                                                                    object:manager.connection queue:NSOperationQueue.mainQueue
                                                                usingBlock:^(NSNotification *notification) { [weakSelf statusChanged]; }];
}

- (void)refresh {
    if (self.manager || self.connecting) return;
    NSString *providerID = self.providerID;
    if (!providerID.length) return;
    NSUInteger generation = self.generation;
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation || self.manager || error) return;
            [self observeManager:[self managerForID:providerID inManagers:managers]];
            [self publish];
        });
    }];
}

- (void)connect {
    if (self.connecting || self.status == NEVPNStatusConnected || self.status == NEVPNStatusDisconnecting || self.status == NEVPNStatusReasserting) return;
    if (XFLocalVPNManager.isPreparingConnection) {
        self.statusMessage = @"Espera a que termine la conexión del túnel antes de conectar el proxy.";
        [self publish];
        return;
    }
    NSURL *gateway = self.gatewayURL;
    NSString *providerID = self.providerID;
    if (!gateway || !providerID.length) {
        self.statusMessage = !gateway ? @"Falta configurar el servidor del proxy en esta versión." : @"Esta instalación no incluye la extensión del proxy.";
        [self publish];
        return;
    }

    NSUInteger generation = ++self.generation;
    self.userStopped = NO;
    self.connecting = YES;
    self.startRequested = NO;
    self.statusMessage = @"Preparando la conexión…";
    [self publish];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 42 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.generation != generation || !self.connecting) return;
        [self completeWithMessage:@"La conexión tardó demasiado. Vuelve a intentarlo."];
        [self.manager.connection stopVPNTunnel];
    });

    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation) return;
            if (error) { [self configurationFailed]; return; }
            NETunnelProviderManager *manager = [self managerForID:providerID inManagers:managers];
            if (manager.connection.status == NEVPNStatusConnected) {
                [self observeManager:manager];
                [self statusChanged];
                return;
            }
            for (NETunnelProviderManager *other in managers) {
                if (other == manager) continue;
                if (other.connection.status != NEVPNStatusDisconnected && other.connection.status != NEVPNStatusInvalid) {
                    [self completeWithMessage:@"Desconecta la otra VPN de XITFORGE antes de conectar el proxy."];
                    return;
                }
            }
            [self observeManager:manager ?: [NETunnelProviderManager new]];
            [self prepareGateway:gateway providerID:providerID generation:generation];
        });
    }];
}

- (void)prepareGateway:(NSURL *)gateway providerID:(NSString *)providerID generation:(NSUInteger)generation {
    NETunnelProviderManager *manager = self.manager;
    NETunnelProviderProtocol *previous = (NETunnelProviderProtocol *)manager.protocolConfiguration;
    if (manager.enabled && !manager.onDemandEnabled && [previous isKindOfClass:NETunnelProviderProtocol.class] &&
        [previous.providerBundleIdentifier isEqualToString:providerID] && [previous.serverAddress isEqualToString:gateway.host] &&
        [previous.providerConfiguration[XFProxyGatewayKey] isEqualToString:gateway.absoluteString]) {
        [self authorizeGatewayForGeneration:generation];
        return;
    }

    NETunnelProviderProtocol *protocol = [NETunnelProviderProtocol new];
    protocol.providerBundleIdentifier = providerID;
    protocol.serverAddress = gateway.host;
    protocol.providerConfiguration = @{XFProxyGatewayKey: gateway.absoluteString};
    protocol.disconnectOnSleep = NO;
    protocol.enforceRoutes = YES;
    manager.protocolConfiguration = protocol;
    manager.localizedDescription = @"XITFORGE · Proxy";
    manager.onDemandEnabled = NO;
    manager.enabled = YES;
    [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation) return;
            if (saveError) { [self configurationFailed]; return; }
            [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.generation != generation) return;
                    if (loadError) { [self configurationFailed]; return; }
                    [self authorizeGatewayForGeneration:generation];
                });
            }];
        });
    }];
}

- (void)authorizeGatewayForGeneration:(NSUInteger)generation {
    self.statusMessage = @"Verificando tu acceso…";
    [self publish];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:XFProxyLicenseURL]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    request.HTTPMethod = @"POST";
    [LicenseValidator authorizeRequest:request completion:^(BOOL authorized) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation) return;
            if (!authorized) {
                [self completeWithMessage:@"No se pudo verificar la sesión de XITFORGE. Revisa tu key y tu conexión."];
                return;
            }
            [self issueGrantWithRequest:request generation:generation];
        });
    }];
}

- (void)issueGrantWithRequest:(NSURLRequest *)request generation:(NSUInteger)generation {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 12;
    configuration.HTTPShouldSetCookies = NO;
    configuration.URLCredentialStorage = nil;
    self.licenseSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.licenseTask = [self.licenseSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation) return;
            [self cancelLicenseRequest];
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            if (status == 401 || status == 403) {
                [self completeWithMessage:@"Tu licencia actual no tiene acceso al proxy. Revisa tu key."];
                return;
            }
            if (error || status != 200 || data.length > 4096) {
                [self completeWithMessage:@"No se pudo verificar el acceso al proxy. Intenta de nuevo."];
                return;
            }
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            id token = [json isKindOfClass:NSDictionary.class] && [json[@"ok"] isEqual:@YES] ? json[@"proxyToken"] : nil;
            if (!XFProxyValidToken(token)) {
                [self completeWithMessage:@"El servidor de licencias devolvió una respuesta inválida."];
                return;
            }
            [self startWithToken:token];
        });
    }];
    [self.licenseTask resume];
}

- (void)startWithToken:(NSString *)token {
    NETunnelProviderSession *session = (NETunnelProviderSession *)self.manager.connection;
    if (![session isKindOfClass:NETunnelProviderSession.class]) { [self configurationFailed]; return; }
    self.statusMessage = @"Conectando al servidor…";
    [self publish];
    NSError *error = nil;
    if (![session startTunnelWithOptions:@{XFProxyTokenOption: token} andReturnError:&error]) {
        [self configurationFailed];
        return;
    }
    self.startRequested = YES;
    if (self.status == NEVPNStatusConnected) [self statusChanged];
}

- (void)statusChanged {
    NEVPNStatus status = self.status;
    if (status == NEVPNStatusConnected) {
        self.wasConnected = YES;
        self.startRequested = NO;
        self.connecting = NO;
        self.statusMessage = nil;
    } else if ((status == NEVPNStatusDisconnected || status == NEVPNStatusInvalid) && (self.startRequested || self.wasConnected)) {
        self.startRequested = NO;
        self.wasConnected = NO;
        self.connecting = NO;
        if (!self.userStopped) {
            NSUInteger generation = ++self.generation;
            self.statusMessage = @"Se interrumpió la conexión con el proxy.";
            [self.manager.connection fetchLastDisconnectErrorWithCompletionHandler:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.generation || self.status == NEVPNStatusConnected) return;
                    NSError *providerError = error;
                    while (providerError && ![providerError.domain isEqualToString:XFProxyErrorDomain]) {
                        providerError = providerError.userInfo[NSUnderlyingErrorKey];
                    }
                    if (providerError) self.statusMessage = providerError.localizedDescription;
                    [self publish];
                });
            }];
        }
    }
    [self publish];
}

- (void)disconnect {
    self.userStopped = YES;
    [self completeWithMessage:nil];
    if (self.manager) {
        [self.manager.connection stopVPNTunnel];
        return;
    }
    NSString *providerID = self.providerID;
    if (!providerID.length) return;
    NSUInteger generation = self.generation;
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && self.generation == generation) {
                [[self managerForID:providerID inManagers:managers].connection stopVPNTunnel];
            }
        });
    }];
}

- (void)configurationFailed {
    [self completeWithMessage:@"iOS no pudo iniciar la VPN. Revisa que la firma incluya la extensión de red y que no haya otra VPN conectada."];
}

- (void)completeWithMessage:(NSString *)message {
    self.generation++;
    self.startRequested = NO;
    self.connecting = NO;
    self.statusMessage = message;
    [self cancelLicenseRequest];
    [self publish];
}

- (void)cancelLicenseRequest {
    [self.licenseTask cancel];
    self.licenseTask = nil;
    [self.licenseSession invalidateAndCancel];
    self.licenseSession = nil;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    completion(nil);
}

- (void)publish {
    [NSNotificationCenter.defaultCenter postNotificationName:XFProxyVPNDidChangeNotification object:self];
}

@end
