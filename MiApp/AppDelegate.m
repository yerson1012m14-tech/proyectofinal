#import "AppDelegate.h"
#import "ViewController.h"
#import "KeyViewController.h"
#import "KeyManager.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    UIViewController *rootVC;
    if ([[KeyManager sharedManager] isKeyValid]) {
        ViewController *main = [[ViewController alloc] init];
        rootVC = [[UINavigationController alloc] initWithRootViewController:main];
    } else {
        rootVC = [[KeyViewController alloc] init];
    }
    
    self.window.rootViewController = rootVC;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
