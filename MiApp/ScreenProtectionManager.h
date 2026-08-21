#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScreenProtectionManager : NSObject

+ (instancetype)shared;

- (void)enableProtection;
- (void)disableProtection;

- (BOOL)isProtectionEnabled;

@end

NS_ASSUME_NONNULL_END
