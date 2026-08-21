#import "ScreenProtectionManager.h"

@interface ScreenProtectionManager ()

@property (nonatomic, assign, getter=isProtectionEnabled) BOOL protectionEnabled;
@property (nonatomic, weak) UIWindow *observedWindow;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, assign) BOOL isCaptured;

@end

@implementation ScreenProtectionManager

+ (instancetype)shared {
    static ScreenProtectionManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ScreenProtectionManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _protectionEnabled = NO;
        _isCaptured = NO;
    }
    return self;
}

#pragma mark - Public API

- (void)enableProtection {
    if (self.isProtectionEnabled) {
        return;
    }
    self.isProtectionEnabled = YES;

    UIWindow *window = [self keyWindow];
    self.observedWindow = window;

    if (!self.overlayView) {
        UIView *overlay = [[UIView alloc] initWithFrame:window.bounds];
        overlay.backgroundColor = [UIColor blackColor];
        overlay.alpha = 0.0;
        overlay.tag = 99991;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.userInteractionEnabled = NO;
        self.overlayView = overlay;
    }

    if (self.overlayView.superview != window) {
        [window addSubview:self.overlayView];
    }
    [window bringSubviewToFront:self.overlayView];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    [nc addObserver:self
           selector:@selector(capturedDidChange:)
               name:UIScreenCapturedDidChangeNotification
             object:nil];

    [nc addObserver:self
           selector:@selector(userDidTakeScreenshot:)
               name:UIApplicationUserDidTakeScreenshotNotification
             object:nil];

    [nc addObserver:self
           selector:@selector(willResignActive:)
               name:UIApplicationWillResignActiveNotification
             object:nil];

    [nc addObserver:self
           selector:@selector(didBecomeActive:)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];

    self.isCaptured = [UIScreen mainScreen].isCaptured;
    [self applyOverlayVisibility];
}

- (void)disableProtection {
    if (!self.isProtectionEnabled) {
        return;
    }
    self.isProtectionEnabled = NO;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:UIScreenCapturedDidChangeNotification object:nil];
    [nc removeObserver:self name:UIApplicationUserDidTakeScreenshotNotification object:nil];
    [nc removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [nc removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];

    [UIView animateWithDuration:0.15 animations:^{
        self.overlayView.alpha = 0.0;
    }];
}

#pragma mark - Notification handlers

- (void)capturedDidChange:(NSNotification *)notification {
    BOOL captured = [UIScreen mainScreen].isCaptured;
    if (captured != self.isCaptured) {
        self.isCaptured = captured;
        [self applyOverlayVisibility];
    }
}

- (void)userDidTakeScreenshot:(NSNotification *)notification {
    [self showOverlayTemporarily];
}

- (void)willResignActive:(NSNotification *)notification {
    [UIView animateWithDuration:0.15 animations:^{
        self.overlayView.alpha = 1.0;
    }];
}

- (void)didBecomeActive:(NSNotification *)notification {
    [self applyOverlayVisibility];
}

#pragma mark - Overlay visibility

- (void)applyOverlayVisibility {
    if (!self.isProtectionEnabled) {
        return;
    }

    CGFloat targetAlpha = self.isCaptured ? 1.0 : 0.0;

    [UIView animateWithDuration:0.2 animations:^{
        self.overlayView.alpha = targetAlpha;
    }];
}

- (void)showOverlayTemporarily {
    if (!self.isProtectionEnabled) {
        return;
    }
    self.overlayView.alpha = 1.0;

    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), ^{
        if (!self.isCaptured && self.isProtectionEnabled) {
            [UIView animateWithDuration:0.2 animations:^{
                self.overlayView.alpha = 0.0;
            }];
        }
    });
}

#pragma mark - Helpers

- (UIWindow *)keyWindow {
    UIWindow *found = nil;

    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in windowScene.windows) {
                if (w.isKeyWindow) {
                    found = w;
                    break;
                }
            }
            if (found) break;
        }
    }

    if (!found) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) {
                found = w;
                break;
            }
        }
    }

    return found ?: [UIApplication sharedApplication].delegate.window;
}

@end
