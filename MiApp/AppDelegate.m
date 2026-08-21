#import "AppDelegate.h"
#import "ViewController.h"
#import "HomeViewController.h"
#import "SettingsViewController.h"
#import "LicenseViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) UITabBarController *mainTabBar;
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
    
    UITabBarAppearance *tabAppearance = [[UITabBarAppearance alloc] init];
    [tabAppearance configureWithOpaqueBackground];
    tabAppearance.backgroundColor = [UIColor blackColor];
    [[UITabBar appearance] setStandardAppearance:tabAppearance];
    [[UITabBar appearance] setTintColor:acento];
    [[UITabBar appearance] setUnselectedItemTintColor:[UIColor grayColor]];
    
    HomeViewController *homeVC = [[HomeViewController alloc] init];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:homeVC];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Inicio" image:[UIImage systemImageNamed:@"house.fill"] tag:0];
    
    ViewController *explorerVC = [[ViewController alloc] init];
    UINavigationController *explorerNav = [[UINavigationController alloc] initWithRootViewController:explorerVC];
    explorerNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Explorar" image:[UIImage systemImageNamed:@"magnifyingglass"] tag:1];
    
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Ajustes" image:[UIImage systemImageNamed:@"gearshape.fill"] tag:2];
    
    self.mainTabBar = [[UITabBarController alloc] init];
    self.mainTabBar.viewControllers = @[homeNav, explorerNav, settingsNav];
    self.mainTabBar.selectedIndex = 0;
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = self.mainTabBar;
    [self.window makeKeyAndVisible];
    
    [self mostrarPantallaLicencia];
    
    return YES;
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
