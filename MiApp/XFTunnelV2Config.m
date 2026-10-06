#import "XFTunnelV2Config.h"

static NSString * const XFTunnelV2BundleMapDefaultsKey =
    @"XITFORGE_TUNNEL_V2_BUNDLE_MAP";

@implementation XFTunnelV2Config

+ (nullable NSString *)validatedBundleId:(id)rawValue {
    if (![rawValue isKindOfClass:NSString.class]) return nil;

    NSString *value =
        [(NSString *)rawValue stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (value.length == 0 || value.length > 255) return nil;

    if ([value hasPrefix:@"."] ||
        [value hasSuffix:@"."] ||
        [value containsString:@".."]) {
        return nil;
    }

    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];

    if ([value rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        return nil;
    }

    return value;
}

+ (nullable NSString *)tunnelBundleIdFromOptionDictionary:(NSDictionary *)option {
    if (![option isKindOfClass:NSDictionary.class]) return nil;
    return [self validatedBundleId:option[@"tunnelBundleId"]];
}

+ (NSDictionary<NSString *, NSString *> *)bundleMap {
    id stored =
        [NSUserDefaults.standardUserDefaults
            dictionaryForKey:XFTunnelV2BundleMapDefaultsKey];

    if (![stored isKindOfClass:NSDictionary.class]) return @{};

    NSMutableDictionary<NSString *, NSString *> *clean =
        [NSMutableDictionary dictionary];

    [(NSDictionary *)stored enumerateKeysAndObjectsUsingBlock:
        ^(id key, id value, BOOL *stop) {
            (void)stop;
            NSString *legacy = [self validatedBundleId:key];
            NSString *tunnel = [self validatedBundleId:value];
            if (legacy.length && tunnel.length) clean[legacy] = tunnel;
        }];

    return [clean copy];
}

+ (void)rememberTunnelBundleId:(NSString *)tunnelBundleId
             forLegacyBundleId:(NSString *)legacyBundleId {
    NSString *legacy = [self validatedBundleId:legacyBundleId];
    NSString *tunnel = [self validatedBundleId:tunnelBundleId];

    if (!legacy.length || !tunnel.length) return;

    NSMutableDictionary *map = [[self bundleMap] mutableCopy];
    map[legacy] = tunnel;

    [NSUserDefaults.standardUserDefaults
        setObject:[map copy]
        forKey:XFTunnelV2BundleMapDefaultsKey];

    NSLog(@"XITFORGE Tunnel V2: bundle registrado %@ -> %@",
          legacy, tunnel);
}

+ (nullable NSString *)tunnelBundleIdForLegacyBundleId:(NSString *)legacyBundleId {
    NSString *legacy = [self validatedBundleId:legacyBundleId];
    if (!legacy.length) return nil;

    NSString *value = [self bundleMap][legacy];
    return [self validatedBundleId:value];
}

+ (BOOL)isRememberedTunnelBundleId:(NSString *)bundleId {
    NSString *candidate = [self validatedBundleId:bundleId];
    if (!candidate.length) return NO;

    for (NSString *value in [self bundleMap].allValues) {
        if ([value isEqualToString:candidate]) return YES;
    }
    return NO;
}

@end
