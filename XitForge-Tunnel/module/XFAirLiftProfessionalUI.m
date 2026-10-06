#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "XFAirLiftViewController.h"
#import "XFOnDevicePairing.h"
#import "XFFileCreationProbeController.h"

static void XFSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) return;
    method_exchangeImplementations(originalMethod, replacementMethod);
}


static NSString * const XFPINDeliveredInternalNotification =
    @"XITFORGE.PairingPINDelivered";

static BOOL XFNotificationsAllowed(UNNotificationSettings *settings) {
    return settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
           settings.authorizationStatus == UNAuthorizationStatusProvisional ||
           settings.authorizationStatus == UNAuthorizationStatusEphemeral;
}

static void XFSendPairingPINNotification(NSString *PIN) {
    if (![PIN isKindOfClass:NSString.class] || PIN.length != 6) return;

    UNUserNotificationCenter *center =
        UNUserNotificationCenter.currentNotificationCenter;

    [center getNotificationSettingsWithCompletionHandler:
        ^(UNNotificationSettings *settings) {
        if (!XFNotificationsAllowed(settings)) return;

        UNMutableNotificationContent *content =
            [[UNMutableNotificationContent alloc] init];

        content.title = @"XITFORGE";
        content.subtitle = @"CÓDIGO DE EMPAREJAMIENTO";
        content.body =
            [NSString stringWithFormat:@"Código: %@", PIN];
        content.sound = UNNotificationSound.defaultSound;
        content.threadIdentifier = @"com.xitforge.pairing";

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger
                triggerWithTimeInterval:0.10
                                repeats:NO];

        NSString *identifier =
            [NSString stringWithFormat:@"xitforge-pair-%@",
                                       NSUUID.UUID.UUIDString];

        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:trigger];

        [center addNotificationRequest:request
                 withCompletionHandler:^(NSError *error) {
            if (error) {
                NSLog(@"XITFORGE pairing notification error: %@", error);
            }
        }];
    }];
}

#pragma mark - Pairing PIN notification delivery

@implementation XFOnDevicePairing (XFSystemPINNotification)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XFSwizzle(self, @selector(start), @selector(xfn_start));
    });
}

- (void)xfn_start {
    static const void *XFPINHandlerWrappedKey = &XFPINHandlerWrappedKey;

    if (![objc_getAssociatedObject(self, XFPINHandlerWrappedKey) boolValue]) {
        void (^originalHandler)(NSString *) = [self.pinHandler copy];

        self.pinHandler = ^(NSString *PIN) {
            // Preserve the original pairing state machine first.
            if (originalHandler) originalHandler(PIN);

            // Deliver the PIN through iOS, not through the XITFORGE screen.
            XFSendPairingPINNotification(PIN);

            // Tell the UI only that delivery happened; never pass/display the PIN there.
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter
                    postNotificationName:XFPINDeliveredInternalNotification
                                  object:nil];
            });
        };

        objc_setAssociatedObject(self,
                                 XFPINHandlerWrappedKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Calls the original XFOnDevicePairing -start after swizzling.
    // At this point its pinHandler is already wrapped, so _activePIN captures it.
    [self xfn_start];
}

@end
