#import "XFAirLiftProfessionalUI.h"
#import <UserNotifications/UserNotifications.h>

static NSString * const XFPINNotificationID = @"com.xitforge.pairing.pin";
static NSString *XFPINActiveNotification;

@interface XFPairingNotificationPresenter : NSObject <UNUserNotificationCenterDelegate>
@property (nonatomic, weak) id<UNUserNotificationCenterDelegate> previousDelegate;
@end
@implementation XFPairingNotificationPresenter
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
      willPresentNotification:(UNNotification *)notification
        withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completion {
    if ([notification.request.identifier hasPrefix:XFPINNotificationID]) {
        completion(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
    } else if ([self.previousDelegate respondsToSelector:_cmd]) {
        [self.previousDelegate userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completion];
    } else { completion(UNNotificationPresentationOptionNone); }
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
        withCompletionHandler:(void (^)(void))completion {
    if ([self.previousDelegate respondsToSelector:_cmd]) {
        [self.previousDelegate userNotificationCenter:center didReceiveNotificationResponse:response withCompletionHandler:completion];
    } else { completion(); }
}
@end

static void XFInstallPINPresenter(void) {
    static XFPairingNotificationPresenter *presenter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ presenter=[XFPairingNotificationPresenter new]; });
    UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;
    if (center.delegate!=presenter) { presenter.previousDelegate=center.delegate; center.delegate=presenter; }
}

void XFRequestPairingNotificationPermission(void (^completion)(BOOL, NSString *)) {
    XFInstallPINPresenter();
    UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;
    void (^finish)(BOOL)=^(BOOL allowed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(allowed, allowed?nil:@"Activa las notificaciones de XITFORGE en Ajustes para recibir el código de emparejamiento.");
        });
    };
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if(settings.authorizationStatus==UNAuthorizationStatusNotDetermined) {
            [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound
                completionHandler:^(BOOL granted,NSError *error) { finish(granted&&!error); }];
        } else { finish(settings.authorizationStatus==UNAuthorizationStatusAuthorized||settings.authorizationStatus==UNAuthorizationStatusProvisional||settings.authorizationStatus==UNAuthorizationStatusEphemeral); }
    }];
}

void XFPostPairingPINNotification(NSString *PIN, void (^completion)(NSError *)) {
    XFInstallPINPresenter();
    XFClearPairingPINNotification();
    NSString *identifier=[XFPINNotificationID stringByAppendingFormat:@".%@",NSUUID.UUID.UUIDString];
    XFPINActiveNotification=identifier;
    UNMutableNotificationContent *content=[UNMutableNotificationContent new];
    content.title=@"XITFORGE · Emparejamiento";
    content.body=[NSString stringWithFormat:@"Código: %@. Introdúcelo en Ajustes para aprobar el emparejamiento.",PIN];
    content.sound=UNNotificationSound.defaultSound;
    content.threadIdentifier=@"com.xitforge.pairing";
    UNNotificationRequest *request=[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(![XFPINActiveNotification isEqual:identifier]) {
                [UNUserNotificationCenter.currentNotificationCenter removePendingNotificationRequestsWithIdentifiers:@[identifier]];
                [UNUserNotificationCenter.currentNotificationCenter removeDeliveredNotificationsWithIdentifiers:@[identifier]];
            }
            if(completion)completion(error);
        });
    }];
}

void XFClearPairingPINNotification(void) {
    UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;
    if(XFPINActiveNotification) {
        [center removePendingNotificationRequestsWithIdentifiers:@[XFPINActiveNotification]];
        [center removeDeliveredNotificationsWithIdentifiers:@[XFPINActiveNotification]];
        XFPINActiveNotification=nil;
    }
}
