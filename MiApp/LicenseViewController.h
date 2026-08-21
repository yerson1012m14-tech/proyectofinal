#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LicenseViewController : UIViewController

@property (nonatomic, copy) void (^onLicenseValidated)(void);

@end

NS_ASSUME_NONNULL_END
