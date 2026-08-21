#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UIView *protectionView;
@property (nonatomic, assign) BOOL isRecording;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIColor *acento = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
    UINavigationBarAppearance *ap = [[UINavigationBarAppearance alloc] init];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = [UIColor blackColor];
    ap.shadowColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    ap.titleTextAttributes = @{
        NSForegroundColorAttributeName: acento,
        NSFontAttributeName: [UIFont fontWithName:@"Menlo-Bold" size:17]
    };
    [[UINavigationBar appearance] setStandardAppearance:ap];
    [[UINavigationBar appearance] setScrollEdgeAppearance:ap];
    [[UINavigationBar appearance] setTintColor:acento];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ViewController *vc = [[ViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    
    // Verificar si la protección está activada
    BOOL protectionEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"screenProtection"];
    if (protectionEnabled) {
        [self setupProtection];
    }
    
    [self mostrarPantallaLicencia];
    
    return YES;
}

- (void)setupProtection {
    // Crear la vista de protección (pantalla negra)
    self.protectionView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.protectionView.backgroundColor = [UIColor blackColor];
    self.protectionView.alpha = 0.0;
    self.protectionView.tag = 9999;
    [self.window addSubview:self.protectionView];
    
    // 1. Protección al cambiar de app / multitarea
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // 2. Protección contra grabación de pantalla
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenCaptureDidChange)
                                                 name:UIScreen.capturedDidChangeNotification
                                               object:nil];
    
    // 3. Protección contra capturas de pantalla
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDidTakeScreenshot)
                                                 name:UIApplication.userDidTakeScreenshotNotification
                                               object:nil];
    
    // Verificar si ya está grabando al iniciar
    self.isRecording = [UIScreen mainScreen].isCaptured;
    if (self.isRecording) {
        [self showProtection];
    }
}

#pragma mark - Cambio de app / Multitarea

- (void)appWillResignActive {
    [self showProtection];
}

- (void)appDidBecomeActive {
    // Solo quitar la protección si no está grabando
    if (!self.isRecording) {
        [self hideProtection];
    }
}

#pragma mark - Grabación de pantalla

- (void)screenCaptureDidChange {
    BOOL isCaptured = [UIScreen mainScreen].isCaptured;
    
    if (isCaptured && !self.isRecording) {
        // Empezó a grabar
        self.isRecording = YES;
        [self showProtection];
        
        // Mostrar alerta
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Grabación detectada"
                message:@"La pantalla se ha ocultado por seguridad."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Entendido" style:UIAlertActionStyleDefault handler:nil]];
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    } else if (!isCaptured && self.isRecording) {
        // Paró de grabar
        self.isRecording = NO;
        [self hideProtection];
    }
}

#pragma mark - Captura de pantalla

- (void)userDidTakeScreenshot {
    // La captura ya se tomó, no se puede prevenir
    // Pero podemos mostrar una advertencia
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Captura detectada"
            message:@"Las capturas de pantalla están prohibidas y pueden ser registradas."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Entendido" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Mostrar/Ocultar protección

- (void)showProtection {
    [UIView animateWithDuration:0.3 animations:^{
        self.protectionView.alpha = 1.0;
    }];
}

- (void)hideProtection {
    [UIView animateWithDuration:0.3 animations:^{
        self.protectionView.alpha = 0.0;
    }];
}

#pragma mark - Pantalla de licencia

- (void)mostrarPantallaLicencia {
    NSString *licenciaGuardada = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiFilzaLicenseKey"];
    if (licenciaGuardada && [self validarFormatoLicencia:licenciaGuardada]) {
        return;
    }
    
    LicenseViewController *licenseVC = [[LicenseViewController alloc] init];
    licenseVC.modalPresentationStyle = UIModalPresentationFullScreen;
    
    __weak typeof(self) weakSelf = self;
    licenseVC.onLicenseValidated = ^{
        [weakSelf.lockWindow.rootViewController dismissViewControllerAnimated:YES completion:^{
            weakSelf.lockWindow.hidden = YES;
            weakSelf.lockWindow = nil;
        }];
    };
    
    self.lockWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.lockWindow.rootViewController = [[UIViewController alloc] init];
    self.lockWindow.windowLevel = UIWindowLevelAlert + 1;
    [self.lockWindow makeKeyAndVisible];
    [self.lockWindow.rootViewController presentViewController:licenseVC animated:YES completion:nil];
}

- (BOOL)validarFormatoLicencia:(NSString *)licencia {
    NSString *regex = @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";
    NSPredicate *predicado = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
    return [predicado evaluateWithObject:licencia];
}

@end
