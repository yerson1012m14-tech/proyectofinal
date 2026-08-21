#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ScreenProtectionManager : NSObject

+ (instancetype)shared;

- (void)enableProtection;
- (void)disableProtection;
- (BOOL)isProtectionEnabled;

@end
