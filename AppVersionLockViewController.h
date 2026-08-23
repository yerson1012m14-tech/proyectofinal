#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppVersionLockViewController : UIViewController

@property (nonatomic, copy) NSString *headline;
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *currentVersion;
@property (nonatomic, copy) NSString *requiredVersion;
@property (nonatomic, copy) NSString *downloadURL;
@property (nonatomic, assign) BOOL showDownloadButton;
@property (nonatomic, copy, nullable) void (^retryHandler)(void);

@end

NS_ASSUME_NONNULL_END
