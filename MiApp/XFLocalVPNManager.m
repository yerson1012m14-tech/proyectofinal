#import "XFLocalVPNManager.h"
#import <NetworkExtension/NetworkExtension.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import "../XitForge-Tunnel/shared/XFLocalVPNPolicy.h"

static BOOL XFHasExistingLocalConnection(NSString *address) {
    struct in_addr peer;
    if (inet_pton(AF_INET, address.UTF8String, &peer) != 1) return NO;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return NO;
    BOOL found = NO;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || !item->ifa_netmask || item->ifa_addr->sa_family != AF_INET ||
            (item->ifa_netmask->sa_family != AF_INET && item->ifa_netmask->sa_family != AF_UNSPEC)) continue;
        uint32_t local = ntohl(((struct sockaddr_in *)item->ifa_addr)->sin_addr.s_addr);
        uint32_t mask = ntohl(((struct sockaddr_in *)item->ifa_netmask)->sin_addr.s_addr);
        if (XFLocalVPNInterfaceCandidate(item->ifa_name, (item->ifa_flags & IFF_UP) != 0,
                                        local, mask, ntohl(peer.s_addr))) { found = YES; break; }
    }
    freeifaddrs(interfaces);
    return found;
}

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
- (void)reuseExistingConnection {
    NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)self.manager.protocolConfiguration;
    BOOL ownsConnection = self.manager.connection.status == NEVPNStatusConnected &&
        [protocol isKindOfClass:NETunnelProviderProtocol.class] &&
        [protocol.providerConfiguration[@"peerAddress"] isEqual:self.peer];
    if (!ownsConnection) {
        // Never stop or try to manage a VPN belonging to another app. Remove
        // the stale own-session observer so it cannot cancel this new tunnel.
        if (self.observer) [NSNotificationCenter.defaultCenter removeObserver:self.observer];
        self.observer = nil; self.manager = nil; self.wasConnected = NO;
    }
}
- (void)finishUnavailable:(NSError *)underlying {
    NSLog(@"XITFORGE integrated VPN could not be prepared: %@", underlying);
    if (XFHasExistingLocalConnection(self.peer)) {
        [self reuseExistingConnection]; [self finish:nil]; return;
    }
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey:
        @"No se pudo iniciar la conexión integrada en esta instalación. Activa LocalDevVPN, vuelve a XITFORGE y pulsa Conectar túnel."} mutableCopy];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    [self finish:[NSError errorWithDomain:@"XITFORGE.LocalVPN" code:XFLocalVPNExternalRequired userInfo:info]];
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
        if (self.started && self.waiters) [self finishUnavailable:[self failure:@"La conexión se interrumpió."]];
    }
}
- (void)connect:(NSString *)address completion:(void (^)(NSError *))completion {
    struct in_addr ipv4;
    if (!address.length || inet_pton(AF_INET, address.UTF8String, &ipv4) != 1) {
        if (completion) completion([self failure:@"Revisa la configuración de la conexión y vuelve a intentarlo."]); return;
    }
    if (self.waiters) {
        if ([self.peer isEqualToString:address]) { if(completion)[self.waiters addObject:[completion copy]]; }
        else if(completion)completion([self failure:@"Hay otra conexión en curso. Espera a que termine."]);
        return;
    }
    self.peer = address; self.waiters = [NSMutableArray array];
    if (completion) [self.waiters addObject:[completion copy]];
    // Reuse LocalDevVPN (or an already active own tunnel) before touching
    // Network Extension preferences, which a sideloaded signature may deny.
    if (XFHasExistingLocalConnection(address)) {
        [self reuseExistingConnection]; [self finish:nil]; return;
    }
    NSUInteger generation = ++self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.waiters && self.generation == generation) {
            if (XFHasExistingLocalConnection(address)) {
                [self reuseExistingConnection]; [self finish:nil]; return;
            }
            [self.manager.connection stopVPNTunnel];
            [self finishUnavailable:[self failure:@"La conexión está tardando demasiado."]];
        }
    });
    NSURL *extension = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"XFLocalTunnel.appex"];
    if (!extension || ![NSFileManager.defaultManager fileExistsAtPath:extension.path]) {
        [self finishUnavailable:[self failure:@"La instalación no incluye la extensión VPN."]]; return;
    }
    NSString *providerID = [NSBundle bundleWithURL:extension].bundleIdentifier;
    if (!providerID.length) { [self finishUnavailable:[self failure:@"La extensión VPN no tiene identificador."]]; return; }
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation || !self.waiters) return;
            if (error) { [self finishUnavailable:error]; return; }
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
                    if (saveError) { [self finishUnavailable:saveError]; return; }
                    [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (self.generation != generation || !self.waiters) return;
                            if (loadError) { [self finishUnavailable:loadError]; return; }
                            NSError *startError = nil; self.started = NO; if (![manager.connection startVPNTunnelAndReturnError:&startError]) {
                                [self finishUnavailable:startError];
                            } else [self statusChanged];
                        });
                    }];
                });
            }];
        });
    }];
}
@end
