#import <UIKit/UIKit.h>

@interface HomeViewController : UIViewController
// Reports YES after the downloaded panel originals were applied; the tunnel
// confirms transfer completion without relocating the app file for read-back.
+ (void)xfDeactivatePersistedOptionsWithCompletion:(void (^)(BOOL success))completion;
@end
