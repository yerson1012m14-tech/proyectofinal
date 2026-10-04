#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Device-initiated pairing host for iOS 27. Every handler runs on the main
/// queue. The PIN comes directly from idevice's live SRP handshake.
@interface XFOnDevicePairing : NSObject
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, copy, nullable) void (^readyHandler)(NSString *hostName);
@property (nonatomic, copy, nullable) void (^pinHandler)(NSString *sixDigitPIN);
@property (nonatomic, copy, nullable) void (^completionHandler)(NSURL * _Nullable recordURL,
                                                               NSError * _Nullable error);
- (void)start;
/// Aborts listener/peer I/O. Native handles are freed only after the blocking
/// handshake returns, and completion fires exactly once for this attempt.
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
