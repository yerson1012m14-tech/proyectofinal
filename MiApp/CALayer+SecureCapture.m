#import "CALayer+SecureCapture.h"

@implementation CALayer (SecureCapture)

- (void)setSecureCapture:(BOOL)enabled {
    // disableUpdateMask es una propiedad privada de CALayer
    // 0x12 = ocultar de capturas y grabaciones
    if (enabled) {
        [self setValue:@(0x12) forKey:@"disableUpdateMask"];
    } else {
        [self setValue:@(0) forKey:@"disableUpdateMask"];
    }
}

@end
