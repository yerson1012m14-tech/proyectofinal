#import <Foundation/Foundation.h>

@interface XITForgeForceTunnelFallback : NSObject
@end

@implementation XITForgeForceTunnelFallback

+ (void)load {
    NSLog(@"XITFORGE: ForceTunnelFallback legacy desactivado; Home/TwoFiles usan el flujo unificado.");
}

@end
