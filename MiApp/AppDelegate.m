#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UITextField *secureField;
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
        [self enableSecureProtection];
    }
    
    // Escuchar cambios
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(protectionSettingChanged)
                                                 name:@"ProtectionSettingChanged"
                                               object:nil];
    
    [self mostrarPantallaLicencia];
    
    return YES;
}

- (void)enableSecureProtection {
    // Crear un UITextField invisible con isSecureTextEntry
    // iOS automáticamente oculta su contenido en capturas y grabaciones
    self.secureField = [[UITextField alloc] initWithFrame:self.window.bounds];
    self.secureField.isSecureTextEntry = YES;
    self.secureField.backgroundColor = [UIColor clearColor];
    self.secureField.userInteractionEnabled = NO;
    self.secureField.alpha = 0.01; // Casi invisible pero presente
    self.secureField.tag = 8888;
    
    // Mover todas las subvistas existentes dentro del secureField
    NSArray *existingViews = [self.window.subviews copy];
    for (UIView *view in existingViews) {
        if (view != self.secureField && view.tag != 9999) {
            [view removeFromSuperview];
            [self.secureField addSubview:view];
        }
    }
    
    [self.window addSubview:self.secureField];
    [self.window bringSubviewToFront:self.secureField];
}

- (void)disableSecureProtection {
    if (self.secureField) {
        // Mover todas las vistas de vuelta a la ventana
        NSArray *secureViews = [self.secureField.subviews copy];
        for (UIView *view in secureViews) {
            [view removeFromSuperview];
            [self.window addSubview:view];
        }
        [self.secureField removeFromSuperview];
        self.secureField = nil;
    }
}

- (void)protectionSettingChanged {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"screenProtection"];
    
    if (enabled && !self.protectionEnabled) {
        [self enableSecureProtection];
    } else if (!enabled && self.protectionEnabled) {
        [self disableSecureProtection];
    }
    
    self.protectionEnabled = enabled;
}

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
