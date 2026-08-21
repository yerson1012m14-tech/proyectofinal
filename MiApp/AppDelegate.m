#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UIView *protectionView;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL protectionEnabled;
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
    
    // Cargar configuración de protección
    self.protectionEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"screenProtection"];
    
    if (self.protectionEnabled) {
        [self setupProtection];
    }
    
    [self mostrarPantallaLicencia];
    
    return YES;
}

- (void)setupProtection {
    // Crear la vista de protección (pantalla negra)
    // Esta vista SIEMPRE está presente pero invisible normalmente
    self.protectionView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.protectionView.backgroundColor = [UIColor blackColor];
    self.protectionView.alpha = 0.0;
    self.protectionView.tag = 9999;
    self.protectionView.userInteractionEnabled = NO;
    [self.window addSubview:self.protectionView];
    
    // 1. Protección contra grabación de pantalla
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenCaptureDidChange)
                                                 name:UIScreen.capturedDidChangeNotification
                                               object:nil];
    
    // 2. Protección contra capturas de pantalla
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDidTakeScreenshot)
                                                 name:UIApplication.userDidTakeScreenshotNotification
                                               object:nil];
    
    // 3. Protección al cambiar de app / multitarea
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Verificar si ya está grabando al iniciar
    self.isRecording = [UIScreen mainScreen].isCaptured;
    if (self.isRecording) {
        [self showProtection];
    }
}

#pragma mark - Grabación de pantalla

- (void)screenCaptureDidChange {
    BOOL isCaptured = [UIScreen mainScreen].isCaptured;
    
    if (isCaptured && !self.isRecording) {
        // Empezó a grabar - poner pantalla negra inmediatamente
        self.isRecording = YES;
        [self showProtection];
    } else if (!isCaptured && self.isRecording) {
        // Paró de grabar - quitar pantalla negra
        self.isRecording = NO;
        [self hideProtection];
    }
}

#pragma mark - Captura de pantalla

- (void)userDidTakeScreenshot {
    // La captura ya se tomó, pero activamos la protección inmediatamente
    // para que la siguiente captura (si hay) salga negra
    [self showProtection];
    
    // Después de un breve momento, ocultamos (si no está grabando)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isRecording) {
            [self hideProtection];
        }
    });
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

#pragma mark - Mostrar/Ocultar protección

- (void)showProtection {
    // Sin animación para que sea instantáneo
    self.protectionView.alpha = 1.0;
}

- (void)hideProtection {
    // Sin animación para que sea instantáneo
    self.protectionView.alpha = 0.0;
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
