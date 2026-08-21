#import "ScreenProtectionManager.h"

@interface ScreenProtectionManager ()

@property (nonatomic, assign) BOOL protectionEnabled;
@property (nonatomic, assign) BOOL screenCaptured;

/*
 * Vista que utiliza UITextField secureTextEntry como
 * superficie de renderizado protegida.
 */
@property (nonatomic, strong) UITextField *secureContainerField;

/*
 * Vista negra utilizada durante screen recording /
 * mirroring / AirPlay.
 */
@property (nonatomic, strong) UIView *recordingOverlay;

@property (nonatomic, weak) UIWindow *protectedWindow;

@end

@implementation ScreenProtectionManager

#pragma mark - Singleton

+ (instancetype)shared {

    static ScreenProtectionManager *manager = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        manager = [[ScreenProtectionManager alloc] init];
    });

    return manager;
}

#pragma mark - Init

- (instancetype)init {

    self = [super init];

    if (self) {

        _protectionEnabled = NO;
        _screenCaptured = NO;
    }

    return self;
}

#pragma mark - Public

- (void)enableProtection {

    if (self.protectionEnabled) {
        [self refreshProtection];
        return;
    }

    self.protectionEnabled = YES;

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    /*
     * Screen recording / mirroring / AirPlay.
     */
    [center addObserver:self
               selector:@selector(screenCaptureChanged:)
                   name:UIScreenCapturedDidChangeNotification
                 object:nil];

    /*
     * El screenshot notification NO se utiliza para
     * proteger la imagen, porque Apple lo envía después
     * de que el screenshot ya fue tomado.
     */
    [center addObserver:self
               selector:@selector(applicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];

    dispatch_async(dispatch_get_main_queue(), ^{

        [self locateMainWindow];
        [self installSecureContainer];
        [self installRecordingOverlay];

        [self updateCaptureState];
    });
}

- (void)disableProtection {

    self.protectionEnabled = NO;
    self.screenCaptured = NO;

    [[NSNotificationCenter defaultCenter]
        removeObserver:self
                  name:UIScreenCapturedDidChangeNotification
                object:nil];

    [[NSNotificationCenter defaultCenter]
        removeObserver:self
                  name:UIApplicationDidBecomeActiveNotification
                object:nil];

    dispatch_async(dispatch_get_main_queue(), ^{

        [self.recordingOverlay removeFromSuperview];
        self.recordingOverlay = nil;

        [self.secureContainerField removeFromSuperview];
        self.secureContainerField = nil;

        self.protectedWindow = nil;
    });
}

- (BOOL)isProtectionEnabled {
    return self.protectionEnabled;
}

#pragma mark - Window

- (void)locateMainWindow {

    UIWindow *foundWindow = nil;

    if (@available(iOS 13.0, *)) {

        for (UIScene *scene
             in [UIApplication sharedApplication].connectedScenes) {

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

                if (window.isKeyWindow &&
                    !window.hidden &&
                    window.alpha > 0.0) {

                    foundWindow = window;
                    break;
                }
            }

            if (foundWindow) {
                break;
            }
        }
    }

    if (!foundWindow) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

        for (UIWindow *window
             in [UIApplication sharedApplication].windows) {

            if (window.isKeyWindow &&
                !window.hidden &&
                window.alpha > 0.0) {

                foundWindow = window;
                break;
            }
        }

#pragma clang diagnostic pop
    }

    if (!foundWindow) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

        foundWindow =
            [UIApplication sharedApplication].windows.firstObject;

#pragma clang diagnostic pop
    }

    self.protectedWindow = foundWindow;
}

#pragma mark - Secure Screenshot Surface

- (void)installSecureContainer {

    if (!self.protectionEnabled) {
        return;
    }

    [self locateMainWindow];

    UIWindow *window = self.protectedWindow;

    if (!window) {
        return;
    }

    if (self.secureContainerField) {
        return;
    }

    /*
     * UITextField seguro.
     *
     * secureTextEntry hace que iOS trate la superficie
     * de ese campo como contenido protegido durante
     * determinadas operaciones de captura.
     */
    UITextField *field =
        [[UITextField alloc] initWithFrame:CGRectZero];

    field.secureTextEntry = YES;
    field.userInteractionEnabled = NO;
    field.hidden = YES;
    field.backgroundColor = UIColor.clearColor;
    field.textColor = UIColor.clearColor;
    field.tintColor = UIColor.clearColor;

    /*
     * Evita que aparezca cualquier texto.
     */
    field.text = @"";

    [window addSubview:field];

    field.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor
            constraintEqualToAnchor:window.leadingAnchor],

        [field.trailingAnchor
            constraintEqualToAnchor:window.trailingAnchor],

        [field.topAnchor
            constraintEqualToAnchor:window.topAnchor],

        [field.bottomAnchor
            constraintEqualToAnchor:window.bottomAnchor]
    ]];

    /*
     * Intentamos activar la superficie segura interna
     * del UITextField.
     */
    UIView *secureView = nil;

    for (UIView *subview in field.subviews) {

        NSString *className =
            NSStringFromClass(subview.class);

        if ([className containsString:@"Text"]) {
            secureView = subview;
            break;
        }
    }

    /*
     * Fallback.
     */
    if (!secureView) {
        secureView = field;
    }

    /*
     * No mostramos el UITextField al usuario.
     */
    field.alpha = 0.01;
    field.hidden = NO;

    /*
     * Mantenerlo debajo del contenido normal.
     * La protección real depende del comportamiento
     * de renderizado seguro de UIKit/iOS.
     */
    [window sendSubviewToBack:field];

    self.secureContainerField = field;
}

#pragma mark - Recording Protection

- (void)installRecordingOverlay {

    if (!self.protectionEnabled) {
        return;
    }

    [self locateMainWindow];

    UIWindow *window = self.protectedWindow;

    if (!window) {
        return;
    }

    if (!self.recordingOverlay) {

        UIView *overlay =
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

        self.recordingOverlay = overlay;
    }

    [window bringSubviewToFront:self.recordingOverlay];
}

#pragma mark - Capture State

- (void)updateCaptureState {

    if (!self.protectionEnabled) {
        return;
    }

    BOOL captured = NO;

    if (@available(iOS 11.0, *)) {
        captured = UIScreen.mainScreen.isCaptured;
    }

    self.screenCaptured = captured;

    [self updateRecordingOverlay];
}

- (void)screenCaptureChanged:(NSNotification *)notification {

    dispatch_async(dispatch_get_main_queue(), ^{

        if (!self.protectionEnabled) {
            return;
        }

        UIScreen *screen =
            notification.object ?: UIScreen.mainScreen;

        if (@available(iOS 11.0, *)) {
            self.screenCaptured = screen.isCaptured;
        } else {
            self.screenCaptured = NO;
        }

        /*
         * Sin animación para minimizar el tiempo
         * entre detección y ocultación.
         */
        [self updateRecordingOverlay];
    });
}

- (void)updateRecordingOverlay {

    if (!self.recordingOverlay) {
        return;
    }

    /*
     * Cuando hay grabación/mirroring, mostramos NEGRO.
     *
     * Esto sí funciona con la prueba que ya hiciste:
     * el vídeo que grabaste terminó sin mostrar la app.
     */
    self.recordingOverlay.hidden =
        !self.screenCaptured;

    if (self.screenCaptured) {
        [self.protectedWindow
            bringSubviewToFront:self.recordingOverlay];
    }
}

#pragma mark - Refresh

- (void)refreshProtection {

    if (!self.protectionEnabled) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{

        [self locateMainWindow];

        if (!self.secureContainerField) {
            [self installSecureContainer];
        }

        if (!self.recordingOverlay) {
            [self installRecordingOverlay];
        }

        [self updateCaptureState];
    });
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {

    if (!self.protectionEnabled) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshProtection];
    });
}

#pragma mark - Cleanup

- (void)dealloc {

    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
}

@end
