// Based on the local IPv4 packet reflection used by LocalDevVPN / SideStore Team.
// Attribution and original license: LOCALDEVVPN-LICENSE.txt and README_MEJORAS.md.
#import <NetworkExtension/NetworkExtension.h>
#import <arpa/inet.h>
#import <string.h>
@interface XFLocalPacketTunnelProvider : NEPacketTunnelProvider
@property(nonatomic) BOOL running;
@end
@implementation XFLocalPacketTunnelProvider
- (void)startTunnelWithOptions:(NSDictionary<NSString *,NSObject *> *)options completionHandler:(void (^)(NSError *))completion {
    NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)self.protocolConfiguration;
    NSString *peer = protocol.providerConfiguration[@"peerAddress"] ?: @"10.7.0.1";
    struct in_addr ip;
    if (![peer isKindOfClass:NSString.class] || inet_pton(AF_INET, peer.UTF8String, &ip) != 1) {
        completion([NSError errorWithDomain:@"XITFORGE.LocalVPN" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Dirección local no válida."}]); return;
    }
    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:peer];
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[@"10.7.1.1"] subnetMasks:@[@"255.255.255.255"]];
    ipv4.includedRoutes = @[[[NEIPv4Route alloc] initWithDestinationAddress:peer subnetMask:@"255.255.255.255"]];
    ipv4.excludedRoutes = @[NEIPv4Route.defaultRoute]; settings.IPv4Settings = ipv4;
    self.running = YES;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError *error) {
        if (!self.running && !error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
        if (!error) [self readPackets]; else self.running = NO;
        completion(error);
    }];
}
- (void)readPackets {
    if (!self.running) return;
    __weak typeof(self) weakSelf = self;
    [self.packetFlow readPacketsWithCompletionHandler:^(NSArray<NSData *> *packets, NSArray<NSNumber *> *protocols) {
        typeof(self) strongSelf = weakSelf; if (!strongSelf || !strongSelf.running) return;
        NSMutableArray *output = [NSMutableArray array], *families = [NSMutableArray array];
        for (NSUInteger i=0; i<MIN(packets.count,protocols.count); i++) {
            NSData *packet = packets[i];
            if (protocols[i].intValue != AF_INET || packet.length < 20) continue;
            const unsigned char *input = packet.bytes;
            NSUInteger headerLength = (input[0] & 15) * 4;
            NSUInteger totalLength = ((NSUInteger)input[2] << 8) | input[3];
            if (input[0] >> 4 != 4 || headerLength < 20 || headerLength > packet.length || totalLength < headerLength || totalLength > packet.length) continue;
            NSMutableData *copy = [packet mutableCopy]; unsigned char *bytes = copy.mutableBytes;
            unsigned char source[4]; memcpy(source,bytes+12,4); memcpy(bytes+12,bytes+16,4); memcpy(bytes+16,source,4);
            // Swapping IPv4 addresses preserves the IP and transport pseudo-header checksums.
            [output addObject:copy]; [families addObject:protocols[i]];
        }
        if (output.count) [strongSelf.packetFlow writePackets:output withProtocols:families];
        [strongSelf readPackets];
    }];
}
- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completion {
    self.running = NO; completion();
}
@end
