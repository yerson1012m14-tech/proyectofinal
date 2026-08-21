#import "AppDelegate.h"
#import "ViewController.h"
#import "HomeViewController.h"
#import "SettingsViewController.h"
#import "LicenseViewController.h"
#import "LicenseValidator.h"

@interface AppDelegate ()
@property (nonatomic, strong) UINavigationController *navigationController;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    UIColor *acento = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];

    UINavigationBarAppearance *ap = [[UINavigationBarAppearance alloc] init];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = UIColor.blackColor;
    ap.shadowColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    ap.titleTextAttributes = @{
        NSForegroundColorAttributeName : acento,
        NSFontAttributeName : [UIFont fontWithName:@"Menlo-Bold" size:17]
    };

    [[UINavigationBar appearance] setStandardAppearance:ap];
    [[UINavigationBar appearance] setScrollEdgeAppearance:ap];
    [[UINavigationBar appearance] setTintColor:acento];

    // Estilo de la barra de pestañas
    UITabBarAppearance *tabAppearance = [[UITabBarAppearance alloc] init];
    [tabAppearance configureWithOpaqueBackground];
    tabAppearance.backgroundColor = [UIColor blackColor];
    [[UITabBar appearance] setStandardAppearance:tabAppearance];
    [[UITabBar appearance] setTintColor:acento];
    [[UITabBar appearance] setUnselectedItemTintColor:[UIColor colorWithWhite:0.40 alpha:1.0]];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    // Crear las 3 pestañas
    HomeViewController *homeVC = [[HomeViewController alloc] init];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:homeVC];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Inicio" image:[UIImage systemImageNamed:@"house.fill"] tag:0];

    ViewController *explorerVC = [[ViewController alloc] init];
    UINavigationController *explorerNav = [[UINavigationController alloc] initWithRootViewController:explorerVC];
    explorerNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Explorar" image:[UIImage systemImageNamed:@"magnifyingglass"] tag:1];

    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Ajustes" image:[UIImage systemImageNamed:@"gearshape.fill"] tag:2];

    UITabBarController *tabBar = [[UITabBarController alloc] init];
    tabBar.viewControllers = @[homeNav, explorerNav, settingsNav];
    tabBar.selectedIndex = 0;

    self.navigationController = [[UINavigationController alloc] initWithRootViewController:tabBar];

    LicenseViewController *licenseVC = [[LicenseViewController alloc] init];

    __weak typeof(self) weakSelf = self;

    licenseVC.onLicenseValidated = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.window.rootViewController = strongSelf.navigationController;
            [strongSelf.window makeKeyAndVisible];
        });
    };

    NSString *savedLicense = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiFilzaLicenseKey"];

    if (savedLicense.length > 0) {
        self.window.rootViewController = licenseVC;
        [self.window makeKeyAndVisible];

        __weak LicenseViewController *weakLicenseVC = licenseVC;

        [LicenseValidator validateKey:savedLicense
                           completion:^(BOOL valid, NSString * _Nullable reason, NSString * _Nullable expiresAt) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!valid) {
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MiFilzaLicenseKey"];
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MiFilzaLicenseExpiresAt"];
                    return;
                }

                if (expiresAt.length > 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:expiresAt forKey:@"MiFilzaLicenseExpiresAt"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                }

                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.window.rootViewController = strongSelf.navigationController;
                [strongSelf.window makeKeyAndVisible];
            });
        }];
    } else {
        self.window.rootViewController = licenseVC;
        [self.window makeKeyAndVisible];
    }

    return YES;
}

@end
