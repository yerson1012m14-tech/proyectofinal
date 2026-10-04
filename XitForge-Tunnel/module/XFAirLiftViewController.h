#import <UIKit/UIKit.h>

@class XFAirLiftBackend;

NS_ASSUME_NONNULL_BEGIN

/// An application browser with explicit known-file replacement and deletion. The backend performs all device operations
/// on a serial queue shared with the pushed browser screens.
/// On iOS 27 the optional on-device pairing screen displays the protocol's PIN;
/// importing an existing pairing record remains available on earlier versions.
@interface XFAirLiftViewController : UITableViewController
- (instancetype)init;
- (instancetype)initWithBackend:(XFAirLiftBackend *)backend NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
