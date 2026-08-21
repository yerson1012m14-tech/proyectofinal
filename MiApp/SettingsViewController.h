#import <UIKit/UIKit.h>

@interface SettingsViewController : UIViewController

@property (nonatomic, assign) NSInteger selectedLanguage;
@property (nonatomic, assign) BOOL screenProtection;
@property (nonatomic, copy) void (^onSettingsChanged)(void);

@end
