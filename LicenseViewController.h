#import <UIKit/UIKit.h>

@interface LicenseViewController : UIViewController

@property (nonatomic, copy) void (^onLicenseValidated)(void);

@end
