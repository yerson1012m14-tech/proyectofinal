#import <Foundation/Foundation.h>
#include <netinet/in.h>

static NSString *const XFProxyLicenseURL = @"https://xitforge-license-server.onrender.com/api/proxy/session";
static NSString *const XFProxyGatewayKey = @"XFProxyGatewayURL";
static NSString *const XFProxyTokenOption = @"XFProxyToken";
static NSString *const XFProxyRemoteAddress = @"10.76.0.1";
static NSString *const XFProxyClientAddress = @"10.76.0.2";
static NSString *const XFProxyErrorDomain = @"XITFORGE.Proxy";
static const NSUInteger XFProxyPort = 10055;
static const NSUInteger XFProxyMTU = 1280;
static const NSUInteger XFProxyPacketLimit = 1500;

typedef NS_ENUM(NSInteger, XFProxyErrorCode) {
    XFProxyErrorConfiguration = 1,
    XFProxyErrorLicenseDenied,
    XFProxyErrorLicenseUnavailable,
    XFProxyErrorTransport,
    XFProxyErrorTimeout,
    XFProxyErrorProtocol,
};

static inline NSError *XFProxyError(XFProxyErrorCode code, NSString *message) {
    return [NSError errorWithDomain:XFProxyErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static inline NSURL *XFProxyValidatedGateway(id candidate) {
    if (![candidate isKindOfClass:NSString.class]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:candidate];
    if (![parts.scheme.lowercaseString isEqualToString:@"wss"] || !parts.host.length ||
        parts.user || parts.password || parts.query || parts.fragment || ![parts.path isEqualToString:@"/v1/tunnel"]) return nil;
    return parts.URL;
}

static inline BOOL XFProxyValidToken(id candidate) {
    if (![candidate isKindOfClass:NSString.class]) return NO;
    NSString *token = candidate;
    if (token.length != 68 || ![token hasPrefix:@"xfp_"]) return NO;
    for (NSUInteger i = 4; i < token.length; i++) {
        unichar c = [token characterAtIndex:i];
        if (!(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f')) return NO;
    }
    return YES;
}

static inline BOOL XFProxyValidPacket(NSData *packet, BOOL outbound) {
    if (packet.length < 40 || packet.length > XFProxyPacketLimit) return NO;
    const uint8_t *bytes = packet.bytes;
    NSUInteger headerLength = (bytes[0] & 15) * 4;
    NSUInteger totalLength = ((NSUInteger)bytes[2] << 8) | bytes[3];
    if (bytes[0] >> 4 != 4 || bytes[9] != IPPROTO_TCP || headerLength < 20 ||
        headerLength + 20 > packet.length || totalLength != packet.length ||
        (bytes[6] & 0x3f) || bytes[7]) return NO;

    const uint8_t *client = bytes + (outbound ? 12 : 16);
    const uint8_t *server = bytes + (outbound ? 16 : 12);
    const uint8_t *port = bytes + headerLength + (outbound ? 2 : 0);
    return client[0] == 10 && client[1] == 76 && client[2] == 0 && client[3] == 2 &&
        server[0] == 10 && server[1] == 76 && server[2] == 0 && server[3] == 1 &&
        (((NSUInteger)port[0] << 8) | port[1]) == XFProxyPort;
}
