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
    
    // Cargar configuración
    self.protectionEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"screenProtection"];
    
    if (self.protectionEnabled) {
        [self setupProtection];
    }
    
    // Escuchar cambios
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(protectionSettingChanged)
                                                 name:@"ProtectionSettingChanged"
                                               object:nil];
    
    [self mostrarPantallaLicencia];
    
    return YES;
}

- (void)setupProtection {
    // Vista negra que se pone encima cuando hay grabación
    self.protectionView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.protectionView.backgroundColor = [UIColor blackColor];
    self.protectionView.alpha = 0.0;
    self.protectionView.tag = 9999;
    self.protectionView.userInteractionEnabled = NO;
    [self.window addSubview:self.protectionView];
    [self.window bringSubviewToFront:self.protectionView];
    
    // 1. Detectar grabación de pantalla
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenCaptureDidChange)
                                                 name:UIScreen.capturedDidChangeNotification
                                               object:nil];
    
    // 2. Detectar captura de pantalla
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDidTakeScreenshot)
                                                 name:UIApplicationUserDidTakeScreenshotNotification
                                               object:nil];
    
    // 3. Cambio de app / multitarea
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Verificar si ya está grabando
    self.isRecording = [UIScreen mainScreen].isCaptured;
    if (self.isRecording) {
        [self showProtection];
    }
}

#pragma mark - Grabación

- (void)screenCaptureDidChange {
    BOOL isCaptured = [UIScreen mainScreen].isCaptured;
    
    if (isCaptured && !self.isRecording) {
        self.isRecording = YES;
        [self showProtection];
    } else if (!isCaptured && self.isRecording) {
        self.isRecording = NO;
        if (![self isAppInBackground]) {
            [self hideProtection];
        }
    }
}

#pragma mark - Captura

- (void)userDidTakeScreenshot {
    // Flash negro rápido para que la siguiente captura (si es rápida) salga negra
    [self showProtection];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isRecording && ![self isAppInBackground]) {
            [self hideProtection];
        }
    });
}

#pragma mark - Cambio de app

- (void)appWillResignActive {
    [self showProtection];
}

- (void)appDidBecomeActive {
    if (!self.isRecording) {
        [self hideProtection];
    }
}

- (BOOL)isAppInBackground {
    UIApplication *app = [UIApplication sharedApplication];
    return app.applicationState != UIApplicationStateActive;
}

#pragma mark - Mostrar/Ocultar

- (void)showProtection {
    [UIView animateWithDuration:0.15 animations:^{
        self.protectionView.alpha = 1.0;
    }];
}

- (void)hideProtection {
    [UIView animateWithDuration:0.15 animations:^{
        self.protectionView.alpha = 0.0;
    }];
}

- (void)protectionSettingChanged {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"screenProtection"];
    
    if (enabled && !self.protectionEnabled) {
        self.protectionEnabled = YES;
        [self setupProtection];
    } else if (!enabled && self.protectionEnabled) {
        self.protectionEnabled = NO;
        [self hideProtection];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIScreen.capturedDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationUserDidTakeScreenshotNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    }
}

#pragma mark - Licencia

- (void)mostrarPantallaLicencia {
    NSString *licenciaGuardada = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiFilzaLicenseKey"];
    if (licenciaGuardada && [self validarFormatoLicencia:licenciaGuardada]) {
        return;
    }
    
    LicenseViewController *licenseVC = [[LicenseViewController alloc] init];
    licenseVC.modalPresentationStyle = UIModalPresentationFullScreen;
    
    __weak typeof(self) weakSelf = self;
    licenseVC.onLicenseValidated = ^{
        [weakSelf.lockWindow.rootViewController dismissViewControllerAnimated:YES completion:nil];
        weakSelf.lockWindow.hidden = YES;
        weakSelf.lockWindow = nil;
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
