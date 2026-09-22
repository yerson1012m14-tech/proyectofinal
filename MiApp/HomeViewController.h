#import <UIKit/UIKit.h>

@interface HomeViewController : UIViewController
// Reports YES only after the configured ORIGINAL files were applied and verified.
+ (void)xfDeactivatePersistedOptionsWithCompletion:(void (^)(BOOL success))completion;
@end
