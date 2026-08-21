#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScreenProtectionManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

- (void)startMonitoring;
- (void)stopMonitoring;

@end

NS_ASSUME_NONNULL_END
