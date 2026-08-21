#import "AppDelegate.h"
#import "ViewController.h"
#import "HomeViewController.h"
#import "MainSettingsViewController.h"
#import "LicenseViewController.h"
#import "LicenseValidator.h"
#import "ScreenProtectionManager.h"

@interface AppDelegate ()

@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UITabBarController *mainTabBar;

@end

@implementation AppDelegate

#pragma mark - Application

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    UIColor *acento =
        [UIColor colorWithRed:0.2
                        green:1.0
                         blue:0.5
                        alpha:1.0];

    /*
     * =========================================================
     * NAVIGATION BAR
     * =========================================================
     */

    UINavigationBarAppearance *ap =
        [[UINavigationBarAppearance alloc] init];

    [ap configureWithOpaqueBackground];

    ap.backgroundColor =
        [UIColor blackColor];

    ap.shadowColor =
        [UIColor colorWithWhite:0.25 alpha:1.0];

    ap.titleTextAttributes = @{
        NSForegroundColorAttributeName: acento,
        NSFontAttributeName:
            [UIFont fontWithName:@"Menlo-Bold" size:17.0]
    };

    [[UINavigationBar appearance]
        setStandardAppearance:ap];

    [[UINavigationBar appearance]
        setScrollEdgeAppearance:ap];

    [[UINavigationBar appearance]
        setTintColor:acento];

    /*
     * =========================================================
     * TAB BAR
     * =========================================================
     */

    UITabBarAppearance *tabAppearance =
        [[UITabBarAppearance alloc] init];

    [tabAppearance configureWithOpaqueBackground];

    tabAppearance.backgroundColor =
        [UIColor blackColor];

    [[UITabBar appearance]
        setStandardAppearance:tabAppearance];

    [[UITabBar appearance]
        setScrollEdgeAppearance:tabAppearance];

    [[UITabBar appearance]
        setTintColor:acento];

    [[UITabBar appearance]
        setUnselectedItemTintColor:[UIColor grayColor]];

    /*
     * =========================================================
     * HOME
     * =========================================================
     */

    HomeViewController *homeVC =
        [[HomeViewController alloc] init];

    UINavigationController *homeNav =
        [[UINavigationController alloc]
            initWithRootViewController:homeVC];

    homeNav.tabBarItem =
        [[UITabBarItem alloc]
            initWithTitle:@"Inicio"
                      image:[UIImage systemImageNamed:@"house.fill"]
                        tag:0];

    /*
     * =========================================================
     * EXPLORAR
     * =========================================================
     */

    ViewController *explorerVC =
        [[ViewController alloc] init];

    UINavigationController *explorerNav =
        [[UINavigationController alloc]
            initWithRootViewController:explorerVC];

    explorerNav.tabBarItem =
        [[UITabBarItem alloc]
            initWithTitle:@"Explorar"
                      image:[UIImage systemImageNamed:@"magnifyingglass"]
                        tag:1];

    /*
     * =========================================================
     * AJUSTES
     * =========================================================
     */

    MainSettingsViewController *settingsVC =
        [[MainSettingsViewController alloc] init];

    UINavigationController *settingsNav =
        [[UINavigationController alloc]
            initWithRootViewController:settingsVC];

    settingsNav.tabBarItem =
        [[UITabBarItem alloc]
            initWithTitle:@"Ajustes"
                      image:[UIImage systemImageNamed:@"gearshape.fill"]
                        tag:2];

    /*
     * =========================================================
     * TAB BAR PRINCIPAL
     * =========================================================
     */

    self.mainTabBar =
        [[UITabBarController alloc] init];

    self.mainTabBar.viewControllers =
        @[
            homeNav,
            explorerNav,
            settingsNav
        ];

    self.mainTabBar.selectedIndex = 0;

    /*
     * =========================================================
     * WINDOW PRINCIPAL
     * =========================================================
     */

    self.window =
        [[UIWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];

    self.window.rootViewController =
        self.mainTabBar;

    [self.window makeKeyAndVisible];

    /*
     * =========================================================
     * PROTECCIÓN GUARDADA
     * =========================================================
     */

    [self applySavedScreenProtection];

    /*
     * =========================================================
     * COMPROBACIÓN DE LICENCIA
     * =========================================================
     */

    [self mostrarPantallaLicencia];

    return YES;
}

#pragma mark - Screen Protection

- (void)applySavedScreenProtection {

    BOOL enabled =
        [[NSUserDefaults standardUserDefaults]
            boolForKey:@"screenProtection"];

    if (enabled) {

        [[ScreenProtectionManager shared]
            enableProtection];

    } else {

        [[ScreenProtectionManager shared]
            disableProtection];
    }
}

#pragma mark - License Validation

- (void)mostrarPantallaLicencia {

    NSString *savedKey =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:@"MiFilzaLicenseKey"];

    /*
     * =========================================================
     * NO HAY KEY
     * =========================================================
     */

    if (savedKey.length == 0) {

        [self mostrarVentanaDeLicencia];

        return;
    }

    /*
     * =========================================================
     * HAY KEY
     *
     * NO confiamos solamente en el formato.
     * Consultamos el servidor.
     * =========================================================
     */

    [LicenseValidator
        validateKey:savedKey
        completion:^(BOOL valid,
                    NSString * _Nullable reason,
                    NSString * _Nullable expiresAt) {

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                /*
                 * =================================================
                 * LICENCIA VÁLIDA
                 * =================================================
                 */

                if (valid) {

                    NSUserDefaults *defaults =
                        [NSUserDefaults standardUserDefaults];

                    /*
                     * Actualizar la fecha recibida
                     * desde el servidor.
                     */

                    if (expiresAt.length > 0) {

                        [defaults
                            setObject:expiresAt
                            forKey:@"MiFilzaLicenseExpiresAt"];

                    } else {

                        [defaults
                            removeObjectForKey:
                                @"MiFilzaLicenseExpiresAt"];
                    }

                    [defaults synchronize];

                    [self applySavedScreenProtection];

                    return;
                }

                /*
                 * =================================================
                 * LICENCIA INVÁLIDA
                 *
                 * revoked
                 * expired
                 * not_found
                 * device_limit
                 * server_error
                 * network_error
                 * =================================================
                 */

                NSLog(
                    @"XITFORGE License rejected: %@",
                    reason
                );

                NSUserDefaults *defaults =
                    [NSUserDefaults standardUserDefaults];

                /*
                 * Eliminar sesión local.
                 */

                [defaults
                    removeObjectForKey:
                        @"MiFilzaLicenseKey"];

                [defaults
                    removeObjectForKey:
                        @"MiFilzaLicenseExpiresAt"];

                [defaults synchronize];

                /*
                 * Desactivar protección.
                 */

                [[ScreenProtectionManager shared]
                    disableProtection];

                /*
                 * Volver a pedir la licencia.
                 */

                [self mostrarVentanaDeLicencia];
            }
        );
    }];
}

#pragma mark - License Window

- (void)mostrarVentanaDeLicencia {

    /*
     * Si ya existe una ventana de licencia,
     * simplemente traerla al frente.
     */

    if (self.lockWindow) {

        [self.lockWindow makeKeyAndVisible];

        return;
    }

    LicenseViewController *licenseVC =
        [[LicenseViewController alloc] init];

    licenseVC.modalPresentationStyle =
        UIModalPresentationFullScreen;

    __weak typeof(self) weakSelf = self;

    licenseVC.onLicenseValidated = ^{

        __strong typeof(weakSelf) strongSelf =
            weakSelf;

        if (!strongSelf) {
            return;
        }

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                /*
                 * Aplicar protección guardada.
                 */

                [strongSelf applySavedScreenProtection];

                /*
                 * Cerrar ventana de licencia.
                 */

                [strongSelf.lockWindow
                    resignKeyWindow];

                strongSelf.lockWindow.hidden =
                    YES;

                strongSelf.lockWindow =
                    nil;

                /*
                 * Devolver foco a la ventana principal.
                 */

                [strongSelf.window
                    makeKeyAndVisible];
            }
        );
    };

    /*
     * =========================================================
     * LOCK WINDOW
     * =========================================================
     */

    self.lockWindow =
        [[UIWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];

    self.lockWindow.windowLevel =
        UIWindowLevelAlert + 1;

    self.lockWindow.backgroundColor =
        [UIColor blackColor];

    self.lockWindow.rootViewController =
        [[UIViewController alloc] init];

    [self.lockWindow makeKeyAndVisible];

    [self.lockWindow.rootViewController
        presentViewController:licenseVC
                     animated:YES
                   completion:nil];
}

#pragma mark - License Logout Support

- (void)logoutCurrentLicense {

    NSUserDefaults *defaults =
        [NSUserDefaults standardUserDefaults];

    /*
     * Cerrar sesión SOLO en este dispositivo.
     * No revoca la licencia del servidor.
     */

    [defaults
        removeObjectForKey:
            @"MiFilzaLicenseKey"];

    [defaults
        removeObjectForKey:
            @"MiFilzaLicenseExpiresAt"];

    [defaults synchronize];

    [[ScreenProtectionManager shared]
        disableProtection];

    [self mostrarVentanaDeLicencia];
}

#pragma mark - License Format

- (BOOL)validarFormatoLicencia:(NSString *)licencia {

    if (licencia.length == 0) {
        return NO;
    }

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicado =
        [NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", regex];

    return
        [predicado evaluateWithObject:licencia];
}

@end
