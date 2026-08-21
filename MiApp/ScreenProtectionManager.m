#import "ScreenProtectionManager.h"

@interface ScreenProtectionManager ()

@property (nonatomic, assign) BOOL protectionActive;
@property (nonatomic, assign) BOOL isCaptured;

@property (nonatomic, strong) NSMutableDictionary<NSValue *, UIView *> *overlayViews;

@end

@implementation ScreenProtectionManager

#pragma mark - Singleton

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
        _protectionActive = NO;
        _isCaptured = NO;
        _overlayViews = [NSMutableDictionary dictionary];
    }

    return self;
}

#pragma mark - Public API

- (void)enableProtection {

    if (self.protectionActive) {
        [self refreshWindows];
        return;
    }

    self.protectionActive = YES;

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center addObserver:self
               selector:@selector(capturedDidChange:)
                   name:UIScreenCapturedDidChangeNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(willResignActive:)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(didBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];

    if (@available(iOS 11.0, *)) {
        self.isCaptured = UIScreen.mainScreen.isCaptured;
    } else {
        self.isCaptured = NO;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshWindows];
        [self updateOverlayVisibility];
    });
}

- (void)disableProtection {

    if (!self.protectionActive) {
        return;
    }

    self.protectionActive = NO;
    self.isCaptured = NO;

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center removeObserver:self
                      name:UIScreenCapturedDidChangeNotification
                    object:nil];

    [center removeObserver:self
                      name:UIApplicationWillResignActiveNotification
                    object:nil];

    [center removeObserver:self
                      name:UIApplicationDidBecomeActiveNotification
                    object:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *overlay in self.overlayViews.allValues) {
            overlay.hidden = YES;
        }
    });
}

- (BOOL)isProtectionEnabled {
    return self.protectionActive;
}

#pragma mark - Capture detection

- (void)capturedDidChange:(NSNotification *)notification {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIScreen *screen =
            notification.object ?: UIScreen.mainScreen;

        if (@available(iOS 11.0, *)) {
            self.isCaptured = screen.isCaptured;
        } else {
            self.isCaptured = NO;
        }

        [self refreshWindows];
        [self updateOverlayVisibility];
    });
}

#pragma mark - App state

- (void)willResignActive:(NSNotification *)notification {

    /*
     No mostramos el overlay únicamente porque la app
     pasó a segundo plano.

     Esperamos a que iOS indique que realmente hay captura.
     */
}

- (void)didBecomeActive:(NSNotification *)notification {

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 11.0, *)) {
            self.isCaptured = UIScreen.mainScreen.isCaptured;
        } else {
            self.isCaptured = NO;
        }

        [self refreshWindows];
        [self updateOverlayVisibility];
    });
}

#pragma mark - Windows

- (void)refreshWindows {

    if (!self.protectionActive) {
        return;
    }

    NSArray<UIWindow *> *windows = [self applicationWindows];

    NSMutableSet<NSValue *> *aliveKeys =
        [NSMutableSet set];

    for (UIWindow *window in windows) {

        if (!window) {
            continue;
        }

        /*
         No creamos overlays para nuestro propio overlay.
         */
        if (window == [UIApplication sharedApplication].keyWindow &&
            window.hidden) {
            continue;
        }

        NSValue *key =
            [NSValue valueWithNonretainedObject:window];

        [aliveKeys addObject:key];

        UIView *overlay =
            self.overlayViews[key];

        if (!overlay) {

            overlay =
                [[UIView alloc] initWithFrame:CGRectZero];

            overlay.backgroundColor =
                UIColor.blackColor;

            overlay.userInteractionEnabled = NO;
            overlay.hidden = YES;

            overlay.translatesAutoresizingMaskIntoConstraints =
                NO;

            [window addSubview:overlay];

            [NSLayoutConstraint activateConstraints:@[
                [overlay.leadingAnchor
                    constraintEqualToAnchor:window.leadingAnchor],

                [overlay.trailingAnchor
                    constraintEqualToAnchor:window.trailingAnchor],

                [overlay.topAnchor
                    constraintEqualToAnchor:window.topAnchor],

                [overlay.bottomAnchor
                    constraintEqualToAnchor:window.bottomAnchor]
            ]];

            self.overlayViews[key] = overlay;
        }

        /*
         Siempre queda por encima del contenido de la ventana.
         */
        [window bringSubviewToFront:overlay];
    }

    /*
     Elimina referencias a ventanas que ya no existen.
     */
    NSArray<NSValue *> *existingKeys =
        self.overlayViews.allKeys.copy;

    for (NSValue *key in existingKeys) {

        if (![aliveKeys containsObject:key]) {

            UIView *overlay =
                self.overlayViews[key];

            [overlay removeFromSuperview];

            [self.overlayViews removeObjectForKey:key];
        }
    }
}

- (NSArray<UIWindow *> *)applicationWindows {

    NSMutableArray<UIWindow *> *result =
        [NSMutableArray array];

    if (@available(iOS 13.0, *)) {

        NSSet<UIScene *> *scenes =
            [UIApplication sharedApplication].connectedScenes;

        for (UIScene *scene in scenes) {

            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateUnattached) {
                continue;
            }

            for (UIWindow *window in windowScene.windows) {

                if (!window) {
                    continue;
                }

                if (window.hidden) {
                    continue;
                }

                if (window.alpha <= 0.0) {
                    continue;
                }

                [result addObject:window];
            }
        }

    } else {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

        NSArray<UIWindow *> *windows =
            [UIApplication sharedApplication].windows;

        for (UIWindow *window in windows) {

            if (!window.hidden &&
                window.alpha > 0.0) {

                [result addObject:window];
            }
        }

#pragma clang diagnostic pop
    }

    return result;
}

#pragma mark - Overlay

- (void)updateOverlayVisibility {

    if (!self.protectionActive) {

        for (UIView *overlay in self.overlayViews.allValues) {
            overlay.hidden = YES;
        }

        return;
    }

    /*
     Sin animación.
     Cuando iOS informa captura, el overlay pasa a visible
     inmediatamente para minimizar frames expuestos.
     */
    BOOL shouldHideContent = self.isCaptured;

    for (UIView *overlay in self.overlayViews.allValues) {
        overlay.hidden = !shouldHideContent;
    }
}

@end
