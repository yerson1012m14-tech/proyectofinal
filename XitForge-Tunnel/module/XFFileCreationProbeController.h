#import <UIKit/UIKit.h>
@class XFAirLiftBackend;
@interface XFFileCreationProbeController : UIViewController
- (instancetype)initWithBackend:(XFAirLiftBackend *)backend queue:(dispatch_queue_t)queue;
@end
