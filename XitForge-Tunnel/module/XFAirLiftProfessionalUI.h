#import <Foundation/Foundation.h>
void XFRequestPairingNotificationPermission(void (^completion)(BOOL allowed, NSString *message));
void XFPostPairingPINNotification(NSString *PIN, void (^completion)(NSError *error));
void XFClearPairingPINNotification(void);
