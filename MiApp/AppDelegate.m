//
//  AppDelegate.m
//  MiApp
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Estilo de la barra de estado
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = (UIWindowScene *)application.windows.firstObject.windowScene;
        scene.statusBarStyle = UIStatusBarStyleLightContent;
    }
    return YES;
}

// ... resto igual
@end
