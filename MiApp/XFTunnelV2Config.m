#import "XFTunnelV2Config.h"

@implementation XFTunnelV2Config

+ (nullable NSString *)tunnelBundleIdFromOptionDictionary:(NSDictionary *)option {
    id rawValue = option[@"tunnelBundleId"];

    if (![rawValue isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *value =
        [(NSString *)rawValue stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (value.length == 0 || value.length > 255) {
        return nil;
    }

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

@end
