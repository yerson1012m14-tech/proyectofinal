#import "AppDelegate.h"
#import "ViewController.h"
#import "LicenseViewController.h"
#import "Translations.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UIView *protectionView;
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
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger lang = [d integerForKey:@"selectedLanguage"];
    BOOL protection = [d boolForKey:@"screenProtection"];
    
    [Translations setLanguage:lang];
    
    if (protection) {
        [self setupProtection];
    }
    
    [self mostrarPantallaLicencia];
    
    return YES;
}

- (void)setupProtection {
    self.protectionView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.protectionView.backgroundColor = [UIColor blackColor];
    self.protectionView.tag = 9999;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hideScreen)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showScreen)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)hideScreen {
    if (!self.protectionView.superview) {
        [self.window addSubview:self.protectionView];
    }
}

- (void)showScreen {
    [self.protectionView removeFromSuperview];
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
