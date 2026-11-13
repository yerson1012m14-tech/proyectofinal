#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const XFProxyVPNDidChangeNotification;

@interface XFProxyVPNManager : NSObject
@property (nonatomic, readonly) NEVPNStatus status;
@property (nonatomic, readonly, getter=isConnecting) BOOL connecting;
@property (nonatomic, copy, readonly, nullable) NSString *statusMessage;
@property (nonatomic, readonly, nullable) NSURL *profileURL;

+ (instancetype)shared;
- (void)refresh;
- (void)connect;
- (void)disconnect;
@end

NS_ASSUME_NONNULL_END
