#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"
#import "ScreenProtectionManager.h"

static NSString * const kProtectionChangedNotification =
    @"ProtectionChanged";

static NSString * const kScreenProtectionKey =
    @"screenProtection";

static NSString * const kLicenseKey =
    @"MiFilzaLicenseKey";

@interface AppDelegate ()

@property (nonatomic, strong) UINavigationController *navigationController;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    /*
     * ============================================================
     * VENTANA PRINCIPAL
     * ============================================================
     */

    self.window =
        [[UIWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];

    /*
     * ============================================================
     * VIEW CONTROLLER PRINCIPAL
     * ============================================================
     */

    ViewController *viewController =
        [[ViewController alloc] init];

    self.navigationController =
        [[UINavigationController alloc]
            initWithRootViewController:viewController];

    /*
     * ============================================================
     * COMPROBAR LICENCIA ANTES DE MOSTRAR NADA
     * ============================================================
     */

    NSString *license =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:kLicenseKey];

    BOOL licenseValid =
        license.length > 0 &&
        [self validarFormatoLicencia:license];

    /*
     * ============================================================
     * ELEGIR ROOT VIEW CONTROLLER
     *
     * Si hay licencia:
     *     → ViewController
     *
     * Si NO hay licencia:
     *     → LicenseViewController
     *
     * Así ViewController jamás se dibuja antes de la
     * pantalla de licencia.
     * ============================================================
     */

    if (licenseValid) {

        self.window.rootViewController =
            self.navigationController;

    } else {

        LicenseViewController *licenseViewController =
            [[LicenseViewController alloc] init];

        licenseViewController.modalPresentationStyle =
            UIModalPresentationFullScreen;

        __weak typeof(self) weakSelf = self;

        licenseViewController.onLicenseValidated = ^{

            dispatch_async(dispatch_get_main_queue(), ^{

                __strong typeof(weakSelf) strongSelf = weakSelf;

                if (!strongSelf) {
                    return;
                }

                /*
                 * Cambiar directamente el root.
                 *
                 * No presentamos ni hacemos dismiss.
                 * Esto evita el pestañeo completamente.
                 */

                strongSelf.window.rootViewController =
                    strongSelf.navigationController;

                [strongSelf.window makeKeyAndVisible];

                /*
                 * Volver a activar la protección.
                 */

                [[ScreenProtectionManager shared]
                    enableProtection];
            });
        };

        self.window.rootViewController =
            licenseViewController;
    }

    /*
     * ============================================================
     * MOSTRAR VENTANA
     *
     * Se hace SOLO después de haber elegido el root correcto.
     * ============================================================
     */

    [self.window makeKeyAndVisible];

    /*
     * ============================================================
     * PROTECCIÓN DE PANTALLA
     * ============================================================
     */

    [self applyProtectionFromSettings];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(protectionSettingChanged:)
               name:kProtectionChangedNotification
             object:nil];

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

        [manager enableProtection];

    } else {

        [manager disableProtection];
    }
}

- (void)protectionSettingChanged:(NSNotification *)notification {

    [self applyProtectionFromSettings];
}

#pragma mark - Licencia

- (BOOL)validarFormatoLicencia:(NSString *)license {

    if (license.length == 0) {
        return NO;
    }

    /*
     * Formato:
     * XXXX-XXXX-XXXX-XXXX
     */

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", regex];

    return [predicate evaluateWithObject:license];
}

#pragma mark - Cleanup

- (void)dealloc {

    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
}

@end
