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

    /*
     * Ventana principal
     */

    self.window =
        [[UIWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];

    ViewController *viewController =
        [[ViewController alloc] init];

    UINavigationController *navigationController =
        [[UINavigationController alloc]
            initWithRootViewController:viewController];

    self.window.rootViewController =
        navigationController;

    [self.window makeKeyAndVisible];

    /*
     * Protección de pantalla
     */

    [self applyProtectionFromSettings];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(protectionSettingChanged:)
               name:kProtectionChangedNotification
             object:nil];

    /*
     * Pantalla de licencia
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

    /*
     * Si ya existe una licencia con el formato correcto,
     * no mostramos la pantalla de licencia.
     */
    if (license.length > 0 &&
        [self validarFormatoLicencia:license]) {

        return;
    }

    LicenseViewController *licenseViewController =
        [[LicenseViewController alloc] init];

    licenseViewController.modalPresentationStyle =
        UIModalPresentationFullScreen;

    __weak typeof(self) weakSelf = self;

    licenseViewController.onLicenseValidated = ^{

        dispatch_async(dispatch_get_main_queue(), ^{

            /*
             * Cerramos la ventana de licencia.
             */
            weakSelf.lockWindow.hidden = YES;
            weakSelf.lockWindow = nil;

            /*
             * Volvemos a preparar la protección.
             */
            [[ScreenProtectionManager shared]
                enableProtection];
        });
    };

    /*
     * Ventana de licencia.
     */
    self.lockWindow =
        [[UIWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];

    self.lockWindow.rootViewController =
        [[UIViewController alloc] init];

    self.lockWindow.windowLevel =
        UIWindowLevelAlert + 1;

    [self.lockWindow makeKeyAndVisible];

    [self.lockWindow.rootViewController
        presentViewController:licenseViewController
                     animated:YES
                   completion:nil];
}

#pragma mark - License Validation

- (BOOL)validarFormatoLicencia:(NSString *)license {

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", regex];

    return [predicate evaluateWithObject:license];
}

@end
