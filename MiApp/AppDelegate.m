#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"
#import "ScreenProtectionManager.h"

static NSString * const kProtectionChangedNotification = @"ProtectionChanged";
static NSString * const kScreenProtectionKey = @"screenProtection";

@interface AppDelegate ()

@property (nonatomic, strong) UIWindow *lockWindow;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    UIColor *acento =
        [UIColor colorWithRed:0.2
                        green:1.0
                         blue:0.5
                        alpha:1.0];

    UINavigationBarAppearance *ap =
        [[UINavigationBarAppearance alloc] init];

    [ap configureWithOpaqueBackground];

    ap.backgroundColor = UIColor.blackColor;

    ap.shadowColor =
        [UIColor colorWithWhite:0.25 alpha:1.0];

    ap.titleTextAttributes = @{
        NSForegroundColorAttributeName : acento,
        NSFontAttributeName :
            [UIFont fontWithName:@"Menlo-Bold" size:17]
    };

    [[UINavigationBar appearance]
        setStandardAppearance:ap];

    [[UINavigationBar appearance]
        setScrollEdgeAppearance:ap];

    [[UINavigationBar appearance]
        setTintColor:acento];

    /*
     * Ventana principal
     */

    self.window =
        [[UIWindow alloc] initWithFrame:
            [UIScreen mainScreen].bounds];

    ViewController *vc =
        [[ViewController alloc] init];

    UINavigationController *nav =
        [[UINavigationController alloc]
            initWithRootViewController:vc];

    self.window.rootViewController = nav;

    [self.window makeKeyAndVisible];

    /*
     * Protección
     */

    [self applyProtectionFromSettings];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(protectionSettingChanged)
               name:kProtectionChangedNotification
             object:nil];

    /*
     * Pantalla de licencia
     */

    [self mostrarPantallaLicencia];

    return YES;
}

#pragma mark - Protección

- (void)applyProtectionFromSettings {

    BOOL enabled =
        [[NSUserDefaults standardUserDefaults]
            boolForKey:kScreenProtectionKey];

    ScreenProtectionManager *manager =
        [ScreenProtectionManager shared];

    if (enabled) {

        if (![manager isProtectionEnabled]) {
            [manager enableProtection];
        }

    } else {

        if ([manager isProtectionEnabled]) {
            [manager disableProtection];
        }
    }
}

- (void)protectionSettingChanged {

    [self applyProtectionFromSettings];
}

#pragma mark - Licencia

- (void)mostrarPantallaLicencia {

    NSString *licenciaGuardada =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:@"MiFilzaLicenseKey"];

    if (licenciaGuardada &&
        [self validarFormatoLicencia:licenciaGuardada]) {

        return;
    }

    LicenseViewController *licenseVC =
        [[LicenseViewController alloc] init];

    licenseVC.modalPresentationStyle =
        UIModalPresentationFullScreen;

    __weak typeof(self) weakSelf = self;

    licenseVC.onLicenseValidated = ^{

        [weakSelf.lockWindow.rootViewController
            dismissViewControllerAnimated:YES
                             completion:nil];

        weakSelf.lockWindow.hidden = YES;
        weakSelf.lockWindow = nil;

        /*
         * La ventana principal puede haber cambiado.
         * Volvemos a comprobar la protección.
         */

        dispatch_async(dispatch_get_main_queue(), ^{
            [[ScreenProtectionManager shared] enableProtection];
        });
    };

    self.lockWindow =
        [[UIWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];

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

- (BOOL)validarFormatoLicencia:(NSString *)licencia {

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicado =
        [NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", regex];

    return [predicado evaluateWithObject:licencia];
}

@end
