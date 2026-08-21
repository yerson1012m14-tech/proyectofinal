#import "CALayer+SecureCapture.h"

@implementation CALayer (SecureCapture)

- (void)setCaptureDisabled:(BOOL)disabled {
    // disableUpdateMask es una propiedad privada de CALayer
    // Valor 0x12 = (1 << 1) | (1 << 4) oculta la capa de capturas y grabaciones
    if (disabled) {
        [self setValue:@(0x12) forKey:@"disableUpdateMask"];
    } else {
        [self setValue:@(0) forKey:@"disableUpdateMask"];
    }
}

@end
