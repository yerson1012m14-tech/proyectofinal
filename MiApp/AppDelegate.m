#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"
#import "ScreenProtectionManager.h"

static NSString * const kProtectionChangedNotification =
    @"ProtectionChanged";

static NSString * const kScreenProtectionKey =
    @"screenProtection";

@interface AppDelegate ()

@property (nonatomic, strong) UIWindow *lockWindow;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window =
        [[UIWindow alloc]
            initWithFrame:UIScreen.mainScreen.bounds];

    ViewController *vc =
        [[ViewController alloc] init];

    UINavigationController *nav =
        [[UINavigationController alloc]
            initWithRootViewController:vc];

    self.window.rootViewController = nav;

    [self.window makeKeyAndVisible];

    /*
     * Activar protección según Settings.
     */
    [self applyProtectionFromSettings];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(protectionSettingChanged:)
               name:kProtectionChangedNotification
             object:nil];

    /*
     * Tu pantalla de licencia.
     */
    [self mostrarPantallaLicencia];

    return YES;
}

#pragma mark - Protection

- (void)applyProtectionFromSettings {

    BOOL enabled =
        [[NSUserDefaults standardUserDefaults]
            boolForKey:kScreenProtectionKey];

    ScreenProtectionManager *manager =
        [ScreenProtectionManager shared];

    if (enabled) {
        [manager enableProtection];
    } else {
        [manager disableProtection];
    }
}

- (void)protectionSettingChanged:(NSNotification *)notification {

    [self applyProtectionFromSettings];
}

#pragma mark - License

- (void)mostrarPantallaLicencia {

    NSString *license =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:@"MiFilzaLicenseKey"];

    if (license.length > 0 &&
        [self validarFormatoLicencia:license]) {

        return;
    }

    LicenseViewController *licenseVC =
        [[LicenseViewController alloc] init];

    licenseVC.modalPresentationStyle =
        UIModalPresentationFullScreen;

    __weak typeof(self) weakSelf = self;

    licenseVC.onLicenseValidated = ^{

        dispatch_async(dispatch_get_main_queue(), ^{

            weakSelf.lockWindow.hidden = YES;
            weakSelf.lockWindow = nil;

            /*
             * Reaplicar protección después de cerrar
             * la pantalla de licencia.
             */
            [[ScreenProtectionManager shared]
                refreshProtection];
        });
    };

    self.lockWindow =
        [[UIWindow alloc]
            initWithFrame:UIScreen.mainScreen.bounds];

    self.lockWindow.rootViewController =
        [[UIViewController alloc] init];

    self.lockWindow.windowLevel =
        UIWindowLevelAlert + 1;

    [self.lockWindow makeKeyAndVisible];

    [self.lockWindow.rootViewController
        presentViewController:licenseVC
                     animated:YES
                   completion:nil];
}

- (BOOL)validarFormatoLicencia:(NSString *)license {

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", regex];

    return [predicate evaluateWithObject:license];
}

@end
