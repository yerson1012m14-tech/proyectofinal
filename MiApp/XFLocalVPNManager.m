#import "XFLocalVPNManager.h"
#import <NetworkExtension/NetworkExtension.h>
#import <arpa/inet.h>

@interface XFLocalVPNManager ()
@property(nonatomic,strong) NETunnelProviderManager *manager;
@property(nonatomic,strong) NSMutableArray *waiters;
@property(nonatomic,copy) NSString *peer;
@property(nonatomic,strong) id observer;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL wasConnected;
@property(nonatomic) NSUInteger generation;
@end
@implementation XFLocalVPNManager
+ (instancetype)shared {
    static XFLocalVPNManager *instance; static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [self new]; }); return instance;
}
+ (void)connectWithPeerAddress:(NSString *)address completion:(void (^)(NSError *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{ [[self shared] connect:address completion:completion]; });
}
- (NSError *)failure:(NSString *)message {
    return [NSError errorWithDomain:@"XITFORGE.LocalVPN" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
- (void)finish:(NSError *)error {
    NSArray *callbacks = [self.waiters copy]; self.waiters = nil; self.started = NO; self.generation++;
    for (void (^callback)(NSError *) in callbacks) callback(error);
}
- (void)statusChanged {
    NEVPNStatus status = self.manager.connection.status;
    if (status == NEVPNStatusConnecting || status == NEVPNStatusReasserting) { self.started = YES; return; }
    if (status == NEVPNStatusConnected) {
        self.wasConnected = YES;
        if (self.waiters) [self finish:nil];
    } else if (status == NEVPNStatusDisconnected || status == NEVPNStatusInvalid) {
        if (self.wasConnected) {
            self.wasConnected = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:@"XITForgeLocalVPNDisconnected" object:nil];
        }
        if (self.started && self.waiters) [self finish:[self failure:@"No se pudo iniciar la red local. Comprueba que tu firma incluya la extensión VPN y su permiso de red."]];
    }
}
- (void)connect:(NSString *)address completion:(void (^)(NSError *))completion {
    struct in_addr ipv4;
    if (!address.length || inet_pton(AF_INET, address.UTF8String, &ipv4) != 1) {
        if (completion) completion([self failure:@"La dirección de la red local no es válida."]); return;
    }
    if (self.waiters) {
        if ([self.peer isEqualToString:address]) { if(completion)[self.waiters addObject:[completion copy]]; }
        else if(completion)completion([self failure:@"Hay otra conexión en curso. Espera a que termine."]);
        return;
    }
    self.peer = address; self.waiters = [NSMutableArray array];
    if (completion) [self.waiters addObject:[completion copy]];
    NSUInteger generation = ++self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.waiters && self.generation == generation) {
            [self.manager.connection stopVPNTunnel];
            [self finish:[self failure:@"La red local no respondió. Comprueba el permiso VPN en Ajustes y vuelve a conectar."]];
        }
    });
    NSURL *extension = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"XFLocalTunnel.appex"];
    if (!extension || ![NSFileManager.defaultManager fileExistsAtPath:extension.path]) {
        [self finish:[self failure:@"Esta instalación no incluye la extensión VPN. Instala la IPA completa conservando sus extensiones."]]; return;
    }
    NSString *providerID = [NSBundle bundleWithURL:extension].bundleIdentifier;
    if (!providerID.length) { [self finish:[self failure:@"La extensión VPN no tiene un identificador válido. Reinstala la IPA completa."]]; return; }
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation || !self.waiters) return;
            if (error) { NSLog(@"XITFORGE LocalVPN preferences failure: %@", error); [self finish:[self failure:@"No se pudo consultar la configuración VPN. Hay que comprobar la firma y la instalación de su extensión; este fallo por sí solo no confirma que falte el permiso de red."]]; return; }
            NETunnelProviderManager *manager = nil;
            for (NETunnelProviderManager *item in managers) {
                NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)item.protocolConfiguration;
                if ([protocol isKindOfClass:NETunnelProviderProtocol.class] && [protocol.providerBundleIdentifier isEqualToString:providerID]) { manager = item; break; }
            }
            if (!manager) manager = [NETunnelProviderManager new];
            self.manager = manager;
            if (self.observer) [NSNotificationCenter.defaultCenter removeObserver:self.observer];
            self.observer = [NSNotificationCenter.defaultCenter addObserverForName:NEVPNStatusDidChangeNotification object:manager.connection queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [self statusChanged]; }];
            NETunnelProviderProtocol *old = (NETunnelProviderProtocol *)manager.protocolConfiguration;
            if (manager.connection.status == NEVPNStatusConnected && [old.providerConfiguration[@"peerAddress"] isEqual:address]) { [self statusChanged]; return; }
            if (manager.connection.status != NEVPNStatusDisconnected && manager.connection.status != NEVPNStatusInvalid) [manager.connection stopVPNTunnel];
            NETunnelProviderProtocol *protocol = [NETunnelProviderProtocol new];
            protocol.providerBundleIdentifier = providerID; protocol.serverAddress = address;
            protocol.providerConfiguration = @{@"peerAddress":address}; protocol.disconnectOnSleep = NO;
            manager.protocolConfiguration = protocol; manager.localizedDescription = @"XITFORGE · Red local"; manager.enabled = YES;
            [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.generation != generation || !self.waiters) return;
                    if (saveError) { [self finish:[self failure:@"No se pudo guardar la VPN. Acepta el permiso de iOS y comprueba la firma de la extensión."]]; return; }
                    [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (self.generation != generation || !self.waiters) return;
                            if (loadError) { [self finish:[self failure:@"No se pudo cargar la configuración VPN. Vuelve a conectar."]]; return; }
                            NSError *startError = nil; self.started = NO;
                            if (![manager.connection startVPNTunnelAndReturnError:&startError]) {
                                [self finish:[self failure:@"iOS no permitió iniciar la VPN integrada. Comprueba el certificado y la firma de la extensión."]];
                            } else [self statusChanged];
                        });
                    }];
                });
            }];
        });
    }];
}
@end
