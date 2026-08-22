#import "AppDelegate.h"
#import "ViewController.h"
#import "HomeViewController.h"
#import "MainSettingsViewController.h"
#import "LicenseViewController.h"
#import "LicenseValidator.h"
#import "ScreenProtectionManager.h"
#import "AppVersionChecker.h"
#import "AppVersionLockViewController.h"

@interface AppDelegate ()

@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UITabBarController *mainTabBar;
@property (nonatomic, strong) UIWindow *versionWindow;
@property (nonatomic, assign) BOOL versionCheckInProgress;
@property (nonatomic, assign) BOOL initialVersionGateCompleted;

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
     * Solo CONFIGURACIÓN usa título rojo arriba.
     * No cambia el color de Inicio ni el resto de la interfaz.
     */
    UIColor *settingsRed =
        [UIColor colorWithRed:0.95
                        green:0.08
                         blue:0.10
                        alpha:1.0];

    UINavigationBarAppearance *settingsAppearance =
        [[UINavigationBarAppearance alloc] init];

    [settingsAppearance configureWithOpaqueBackground];

    settingsAppearance.backgroundColor =
        [UIColor blackColor];

    settingsAppearance.shadowColor =
        [UIColor colorWithWhite:0.25 alpha:1.0];

    NSDictionary *settingsTitleAttributes = @{
        NSForegroundColorAttributeName: settingsRed,
        NSFontAttributeName:
            [UIFont fontWithName:@"Menlo-Bold" size:17.0]
    };

    settingsAppearance.titleTextAttributes =
        settingsTitleAttributes;

    settingsAppearance.largeTitleTextAttributes =
        @{
            NSForegroundColorAttributeName: settingsRed,
            NSFontAttributeName:
                [UIFont boldSystemFontOfSize:32.0]
        };

    settingsNav.navigationBar.standardAppearance =
        settingsAppearance;

    settingsNav.navigationBar.scrollEdgeAppearance =
        settingsAppearance;

    settingsNav.navigationBar.compactAppearance =
        settingsAppearance;

    settingsNav.navigationBar.tintColor =
        settingsRed;

    /*
     * =========================================================
     * TAB BAR PRINCIPAL
     * =========================================================
     */

    self.mainTabBar =
        [[UITabBarController alloc] init];

    /*
     * EXPLORAR queda creado arriba y su código NO se borra.
     * Simplemente no lo incluimos por ahora en las pestañas visibles.
     * Para mostrarlo otra vez, basta con volver a agregar explorerNav
     * a este arreglo.
     */
    self.mainTabBar.viewControllers =
        @[
            homeNav,
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

    /*
     * Mientras se verifica la versión, mostramos únicamente
     * un fondo negro. Así NO aparece por un instante ni el Home,
     * ni el login, ni la pantalla de "Verificando versión".
     */
    UIViewController *versionGatePlaceholder =
        [[UIViewController alloc] init];

    versionGatePlaceholder.view.backgroundColor =
        [UIColor blackColor];

    self.window.rootViewController =
        versionGatePlaceholder;

    [self.window makeKeyAndVisible];

    /*
     * =========================================================
     * PROTECCIÓN GUARDADA
     * =========================================================
     */

    [self applySavedScreenProtection];

    /*
     * =========================================================
     * CONTROL DE VERSIÓN
     * =========================================================
     *
     * La licencia NO se muestra hasta que el servidor confirme
     * que esta versión de la IPA puede seguir utilizándose.
     */

    [self verificarVersionDeApp];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {

    /*
     * Volver a consultar cada vez que la app regresa al frente.
     * Así una versión que fue bloqueada mientras estaba abierta
     * queda bloqueada al volver a la app.
     */

    if (self.window && !self.versionCheckInProgress) {
        [self verificarVersionDeApp];
    }
}

#pragma mark - App Version Gate

- (void)verificarVersionDeApp {

    if (self.versionCheckInProgress) {
        return;
    }

    /*
     * No mostramos ninguna tarjeta durante la comprobación normal.
     * El usuario ve únicamente el fondo negro durante esos instantes.
     * La pantalla de bloqueo solo aparece si realmente hace falta.
     */

    self.versionCheckInProgress = YES;

    __weak typeof(self) weakSelf = self;

    [AppVersionChecker
        checkWithCompletion:
    ^(BOOL success,
      BOOL blocked,
      BOOL updateAvailable,
      NSString *currentVersion,
      NSString *latestVersion,
      NSString *minimumVersion,
      NSString *message,
      NSString *downloadURL,
      NSString * _Nullable errorMessage) {

        __strong typeof(weakSelf) strongSelf = weakSelf;

        if (!strongSelf) {
            return;
        }

        strongSelf.versionCheckInProgress = NO;

        /*
         * FAIL CLOSED:
         * Si no se puede verificar con el servidor, la app no
         * continúa. Esto evita saltarse el control quitando Internet.
         */
        if (!success) {

            [strongSelf
                mostrarBloqueoDeVersionConTitulo:
                    @"No se pudo verificar la versión"
                mensaje:
                    (errorMessage.length > 0
                        ? errorMessage
                        : @"Comprueba tu conexión a Internet y vuelve a intentarlo.")
                versionActual:currentVersion
                versionRequerida:@""
                downloadURL:@""
                mostrarDescarga:NO];

            return;
        }

        if (blocked) {

            NSString *finalMessage =
                message.length > 0
                    ? message
                    : @"Esta versión de XITFORGE ya no está disponible. Descarga la nueva versión para continuar.";

            NSString *required =
                minimumVersion.length > 0
                    ? minimumVersion
                    : latestVersion;

            [strongSelf
                mostrarBloqueoDeVersionConTitulo:
                    @"Actualización requerida"
                mensaje:finalMessage
                versionActual:currentVersion
                versionRequerida:required
                downloadURL:downloadURL
                mostrarDescarga:(downloadURL.length > 0)];

            return;
        }

        /*
         * Versión permitida.
         *
         * En el primer arranque cambiamos el fondo negro por la
         * interfaz principal SOLO después de recibir la aprobación
         * del servidor. Esto elimina el parpadeo visual.
         */
        BOOL firstSuccessfulVersionCheck =
            !strongSelf.initialVersionGateCompleted;

        if (firstSuccessfulVersionCheck) {

            strongSelf.initialVersionGateCompleted = YES;

            strongSelf.window.rootViewController =
                strongSelf.mainTabBar;
        }

        [strongSelf cerrarBloqueoDeVersion];

        /*
         * El flujo de licencia solo se inicia una vez.
         * Las comprobaciones posteriores al volver al primer plano
         * únicamente sirven para bloquear si la versión cambió.
         */
        if (firstSuccessfulVersionCheck) {
            [strongSelf mostrarPantallaLicencia];
        }
    }];
}

- (void)mostrarBloqueoDeVersionConTitulo:(NSString *)titulo
                                 mensaje:(NSString *)mensaje
                           versionActual:(NSString *)versionActual
                       versionRequerida:(NSString *)versionRequerida
                             downloadURL:(NSString *)downloadURL
                         mostrarDescarga:(BOOL)mostrarDescarga {

    AppVersionLockViewController *vc = nil;

    if ([self.versionWindow.rootViewController
            isKindOfClass:[AppVersionLockViewController class]]) {

        vc =
            (AppVersionLockViewController *)
                self.versionWindow.rootViewController;
    }

    if (!vc) {

        vc = [[AppVersionLockViewController alloc] init];

        self.versionWindow =
            [[UIWindow alloc]
                initWithFrame:[UIScreen mainScreen].bounds];

        self.versionWindow.windowLevel =
            UIWindowLevelAlert + 10;

        self.versionWindow.backgroundColor =
            [UIColor blackColor];

        self.versionWindow.rootViewController = vc;
    }

    vc.headline = titulo ?: @"";
    vc.messageText = mensaje ?: @"";
    vc.currentVersion = versionActual ?: @"";
    vc.requiredVersion = versionRequerida ?: @"";
    vc.downloadURL = downloadURL ?: @"";
    vc.showDownloadButton = mostrarDescarga;

    __weak typeof(self) weakSelf = self;

    vc.retryHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf verificarVersionDeApp];
        }
    };

    [self.versionWindow makeKeyAndVisible];
}

- (void)cerrarBloqueoDeVersion {

    if (!self.versionWindow) {
        [self.window makeKeyAndVisible];
        return;
    }

    [self.versionWindow resignKeyWindow];
    self.versionWindow.hidden = YES;
    self.versionWindow.rootViewController = nil;
    self.versionWindow = nil;

    [self.window makeKeyAndVisible];
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
