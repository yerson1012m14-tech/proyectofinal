#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "XFAirLiftViewController.h"

/// Adds a tab to the app's existing tab controller. The existing root controller
/// and the app's version and license windows remain managed by AppDelegate.
@interface XFAirLiftInstaller : NSObject
@end

@implementation XFAirLiftInstaller

+ (void)load {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(applicationReady:)
                   name:UIApplicationDidFinishLaunchingNotification object:nil];
    [center addObserver:self selector:@selector(applicationReady:)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [self installIfAvailable]; });
}

+ (void)applicationReady:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self installIfAvailable]; });
}

+ (void)installIfAvailable {
    NSAssert(NSThread.isMainThread, @"AirLift installation must run on the main thread.");
    id delegate = UIApplication.sharedApplication.delegate;
    SEL getter = NSSelectorFromString(@"mainTabBar");
    if (![delegate respondsToSelector:getter]) return;
    id candidate = ((id (*)(id, SEL))objc_msgSend)(delegate, getter);
    if (![candidate isKindOfClass:UITabBarController.class]) return;

    UITabBarController *tabController = candidate;
    NSArray<UIViewController *> *existing = tabController.viewControllers;
    if (!existing.count) return;
    UIViewController *selected = tabController.selectedViewController;
    NSMutableArray<UIViewController *> *updated = [existing mutableCopy];
    UIViewController *tunnel = nil;
    for (UIViewController *controller in existing) {
        UIViewController *root = [controller isKindOfClass:UINavigationController.class]
            ? ((UINavigationController *)controller).viewControllers.firstObject : controller;
        if ([root isKindOfClass:XFAirLiftViewController.class]) { tunnel = controller; break; }
    }
    if (!tunnel) {
        XFAirLiftViewController *browser = [[XFAirLiftViewController alloc] init];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:browser];
        navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Túnel"
            image:[UIImage systemImageNamed:@"network"] tag:73105];
        tunnel = navigation;
    }
    [updated removeObjectIdenticalTo:tunnel];
    [updated insertObject:tunnel atIndex:MIN((NSUInteger)1, updated.count)];
    if (![existing isEqualToArray:updated]) {
        [tabController setViewControllers:updated animated:NO];
        if (selected && [updated containsObject:selected]) tabController.selectedViewController = selected;
    }
}

@end
