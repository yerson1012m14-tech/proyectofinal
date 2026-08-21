#import "CALayer+SecureCapture.h"

@implementation CALayer (SecureCapture)

- (void)setCaptureDisabled:(BOOL)disabled {
    if (disabled) {
        [self setValue:@(0x12) forKey:@"disableUpdateMask"];
    } else {
        [self setValue:@(0) forKey:@"disableUpdateMask"];
    }
}

@end
