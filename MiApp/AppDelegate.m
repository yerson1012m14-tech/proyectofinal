#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"
#import "LicenseValidator.h"

@interface AppDelegate ()

@property (nonatomic, strong) UINavigationController *navigationController;

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
            [UIFont fontWithName:@"Menlo-Bold"
                            size:17]
    };

    [[UINavigationBar appearance]
        setStandardAppearance:ap];

    [[UINavigationBar appearance]
        setScrollEdgeAppearance:ap];

    [[UINavigationBar appearance]
        setTintColor:acento];

    /*
     * Ventana.
     */

    self.window =
        [[UIWindow alloc]
            initWithFrame:
                UIScreen.mainScreen.bounds];

    /*
     * ViewController principal.
     */

    ViewController *viewController =
        [[ViewController alloc] init];

    self.navigationController =
        [[UINavigationController alloc]
            initWithRootViewController:viewController];

    /*
     * ------------------------------------------------------------
     * Importante:
     *
     * Primero mostramos LicenseViewController.
     * ViewController NO se muestra hasta que el servidor
     * confirme la licencia.
     * ------------------------------------------------------------
     */

    LicenseViewController *licenseVC =
        [[LicenseViewController alloc] init];

    __weak typeof(self) weakSelf = self;

    licenseVC.onLicenseValidated = ^{

        dispatch_async(dispatch_get_main_queue(), ^{

            __strong typeof(weakSelf) strongSelf =
                weakSelf;

            if (!strongSelf) {
                return;
            }

            strongSelf.window.rootViewController =
                strongSelf.navigationController;

            [strongSelf.window makeKeyAndVisible];
        });
    };

    /*
     * ------------------------------------------------------------
     * Comprobar licencia guardada contra EL SERVIDOR.
     * ------------------------------------------------------------
     */

    NSString *savedLicense =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:@"MiFilzaLicenseKey"];

    if (savedLicense.length > 0) {

        /*
         * Mostramos temporalmente LicenseViewController
         * mientras comprobamos la key guardada.
         */

        self.window.rootViewController =
            licenseVC;

        [self.window makeKeyAndVisible];

        __weak LicenseViewController *weakLicenseVC =
            licenseVC;

        [LicenseValidator validateKey:savedLicense
                           completion:
        ^(BOOL valid,
          NSString * _Nullable reason,
          NSString * _Nullable expiresAt) {

            dispatch_async(dispatch_get_main_queue(), ^{

                if (!valid) {

                    /*
                     * La key guardada ya no es válida.
                     * La eliminamos.
                     */

                    [[NSUserDefaults standardUserDefaults]
                        removeObjectForKey:@"MiFilzaLicenseKey"];

                    [[NSUserDefaults standardUserDefaults]
                        removeObjectForKey:@"MiFilzaLicenseExpiresAt"];

                    return;
                }

                /*
                 * Actualizar expiración.
                 */

                if (expiresAt.length > 0) {

                    [[NSUserDefaults standardUserDefaults]
                        setObject:expiresAt
                           forKey:@"MiFilzaLicenseExpiresAt"];

                    [[NSUserDefaults standardUserDefaults]
                        synchronize];
                }

                /*
                 * La key sigue válida.
                 * Entrar directamente.
                 */

                __strong typeof(weakSelf) strongSelf =
                    weakSelf;

                if (!strongSelf) {
                    return;
                }

                strongSelf.window.rootViewController =
                    strongSelf.navigationController;

                [strongSelf.window makeKeyAndVisible];
            });
        }];

    } else {

        /*
         * Primera vez:
         * mostrar directamente la pantalla de licencia.
         */

        self.window.rootViewController =
            licenseVC;

        [self.window makeKeyAndVisible];
    }

    return YES;
}

@end
