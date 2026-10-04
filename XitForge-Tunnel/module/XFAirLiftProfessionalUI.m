#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "XFAirLiftViewController.h"
#import "XFOnDevicePairing.h"

static UIColor *XFProfessionalRed(void) {
    return [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
}

static UIColor *XFProfessionalDark(void) {
    return [UIColor colorWithRed:0.018 green:0.012 blue:0.014 alpha:1.0];
}

static UIColor *XFProfessionalPanel(void) {
    return [UIColor colorWithRed:0.055 green:0.025 blue:0.028 alpha:1.0];
}

static void XFProfessionalAlert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Entendido"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static void XFProfessionalSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) return;
    method_exchangeImplementations(originalMethod, replacementMethod);
}

static UIViewController *XFProfessionalRootController(UIViewController *controller) {
    if ([controller isKindOfClass:UINavigationController.class]) {
        return ((UINavigationController *)controller).viewControllers.firstObject;
    }
    return controller;
}

static void XFProfessionalReorderTabs(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    if (![delegate respondsToSelector:NSSelectorFromString(@"mainTabBar")]) return;

    UITabBarController *tabs =
        ((id (*)(id, SEL))objc_msgSend)(delegate, NSSelectorFromString(@"mainTabBar"));

    if (![tabs isKindOfClass:UITabBarController.class] || tabs.viewControllers.count < 2) return;

    NSMutableArray<UIViewController *> *controllers = [tabs.viewControllers mutableCopy];
    UIViewController *tunnel = nil;
    UIViewController *settings = nil;

    for (UIViewController *controller in controllers) {
        UIViewController *root = XFProfessionalRootController(controller);
        if ([root isKindOfClass:XFAirLiftViewController.class]) tunnel = controller;
        if ([controller.tabBarItem.title isEqualToString:@"Ajustes"]) settings = controller;
    }

    if (!tunnel) return;

    [controllers removeObject:tunnel];
    [controllers insertObject:tunnel atIndex:MIN((NSUInteger)1, controllers.count)];

    if (settings) {
        [controllers removeObject:settings];
        [controllers insertObject:settings atIndex:MIN((NSUInteger)2, controllers.count)];
    }

    [tabs setViewControllers:controllers animated:NO];
}

@interface XFConnectionStatusView : UIStackView
@property (nonatomic, strong) UILabel *tunnelLabel;
@property (nonatomic, strong) UILabel *pairingLabel;
- (void)showConnected:(BOOL)connected pairingAvailable:(BOOL)available;
- (void)showPairingInProgress:(BOOL)inProgress available:(BOOL)available;
@end

@implementation XFConnectionStatusView (XFProfessional)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XFProfessionalSwizzle(self,
            @selector(showConnected:pairingAvailable:),
            @selector(xfp_showConnected:pairingAvailable:));
        XFProfessionalSwizzle(self,
            @selector(showPairingInProgress:available:),
            @selector(xfp_showPairingInProgress:available:));
    });
}

- (void)xfp_showConnected:(BOOL)connected pairingAvailable:(BOOL)available {
    [self xfp_showConnected:connected pairingAvailable:available];
    self.tunnelLabel.textColor =
        connected ? XFProfessionalRed() : UIColor.systemGrayColor;
    self.backgroundColor = XFProfessionalPanel();
    self.layer.cornerRadius = 18.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor =
        [[XFProfessionalRed() colorWithAlphaComponent:0.35] CGColor];
}

- (void)xfp_showPairingInProgress:(BOOL)inProgress available:(BOOL)available {
    [self xfp_showPairingInProgress:inProgress available:available];
    if (inProgress) {
        self.pairingLabel.textColor = UIColor.systemOrangeColor;
    } else {
        self.pairingLabel.textColor =
            available ? XFProfessionalRed() : UIColor.systemGrayColor;
    }
}

@end

@interface XFAirLiftViewController (XFProfessionalPrivate)
@property (nonatomic, strong) id backend;
@property (nonatomic, strong) dispatch_queue_t operationQueue;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) id connectionStatus;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *pairButton;
@property (nonatomic, strong) UIButton *cancelPairButton;
@property (nonatomic, strong) UIButton *pinCopyButton;
@property (nonatomic, strong) XFOnDevicePairing *pairingService;
@property (nonatomic, assign) BOOL tunnelConnected;
@property (nonatomic, assign) BOOL applicationFileAccessAvailable;
@property (nonatomic, assign) BOOL busy;
- (void)updateButtons;
- (void)startOnDevicePairing;
- (void)showTunnelHelp;
@end

static const void *XFOpenFilesButtonKey = &XFOpenFilesButtonKey;

@implementation XFAirLiftViewController (XFProfessional)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XFProfessionalSwizzle(self, @selector(viewDidLoad), @selector(xfp_viewDidLoad));
        XFProfessionalSwizzle(self, @selector(updateButtons), @selector(xfp_updateButtons));
        XFProfessionalSwizzle(self,
            @selector(tableView:numberOfRowsInSection:),
            @selector(xfp_tableView:numberOfRowsInSection:));
        XFProfessionalSwizzle(self,
            @selector(tableView:titleForHeaderInSection:),
            @selector(xfp_tableView:titleForHeaderInSection:));
        XFProfessionalSwizzle(self,
            @selector(tableView:titleForFooterInSection:),
            @selector(xfp_tableView:titleForFooterInSection:));
        XFProfessionalSwizzle(self,
            @selector(startOnDevicePairing),
            @selector(xfp_startOnDevicePairing));
        XFProfessionalSwizzle(self,
            @selector(showTunnelHelp),
            @selector(xfp_showTunnelHelp));

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self
                   selector:@selector(xfp_applicationReady:)
                       name:UIApplicationDidFinishLaunchingNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(xfp_applicationReady:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:nil];
    });
}

+ (void)xfp_applicationReady:(NSNotification *)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            XFProfessionalReorderTabs();
        });
    });
}

- (UIButton *)xfp_secondaryButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButtonConfiguration *configuration = UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.baseForegroundColor = XFProfessionalRed();
    configuration.baseBackgroundColor = [XFProfessionalRed() colorWithAlphaComponent:0.14];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(13, 16, 13, 16);

    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.layer.cornerRadius = 14.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor =
        [XFProfessionalRed() colorWithAlphaComponent:0.30].CGColor;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)xfp_styleButton:(UIButton *)button prominent:(BOOL)prominent {
    if (!button) return;

    UIButtonConfiguration *configuration =
        button.configuration ?: (prominent
            ? UIButtonConfiguration.filledButtonConfiguration
            : UIButtonConfiguration.tintedButtonConfiguration);

    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.baseForegroundColor =
        prominent ? UIColor.whiteColor : XFProfessionalRed();
    configuration.baseBackgroundColor =
        prominent ? XFProfessionalRed() :
        [XFProfessionalRed() colorWithAlphaComponent:0.14];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(13, 16, 13, 16);
    button.configuration = configuration;

    button.layer.cornerRadius = 14.0;
    button.layer.borderWidth = prominent ? 0.0 : 1.0;
    button.layer.borderColor =
        [XFProfessionalRed() colorWithAlphaComponent:0.30].CGColor;
}

- (void)xfp_viewDidLoad {
    [self xfp_viewDidLoad];

    self.tableView.backgroundColor = XFProfessionalDark();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.refreshControl.tintColor = XFProfessionalRed();

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColor.blackColor;
    appearance.shadowColor = [XFProfessionalRed() colorWithAlphaComponent:0.18];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: XFProfessionalRed(),
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]
    };

    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;
    self.navigationController.navigationBar.tintColor = XFProfessionalRed();
    self.navigationItem.searchController = nil;

    for (UIView *view in self.headerStack.arrangedSubviews) {
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            if ([label.text isEqualToString:@"Archivos por túnel"]) {
                label.text = @"XITFORGE TÚNEL";
                label.textColor = XFProfessionalRed();
                label.font = [UIFont systemFontOfSize:24 weight:UIFontWeightHeavy];
                label.textAlignment = NSTextAlignmentCenter;
            }
        }
    }

    [self xfp_styleButton:self.connectButton prominent:YES];
    [self xfp_styleButton:self.pairButton prominent:NO];
    [self xfp_styleButton:self.importButton prominent:NO];
    [self xfp_styleButton:self.cancelPairButton prominent:NO];
    [self xfp_styleButton:self.pinCopyButton prominent:NO];

    UIButtonConfiguration *connectConfiguration = self.connectButton.configuration;
    connectConfiguration.title = @"Conectar túnel";
    self.connectButton.configuration = connectConfiguration;

    UIButton *openFiles =
        [self xfp_secondaryButtonWithTitle:@"Abrir archivos por identificador"
                                 selector:@selector(xfp_openFilesByIdentifier)];
    openFiles.enabled = NO;
    objc_setAssociatedObject(self,
                             XFOpenFilesButtonKey,
                             openFiles,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.headerStack addArrangedSubview:openFiles];

    XFConnectionStatusView *status =
        [self.connectionStatus isKindOfClass:XFConnectionStatusView.class]
            ? self.connectionStatus : nil;
    if (status) {
        status.backgroundColor = XFProfessionalPanel();
        status.layer.cornerRadius = 18.0;
        status.layer.borderWidth = 1.0;
        status.layer.borderColor =
            [XFProfessionalRed() colorWithAlphaComponent:0.35].CGColor;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        XFProfessionalReorderTabs();
        [self.view setNeedsLayout];
    });
}

- (NSString *)xfp_cleanStatusText:(NSString *)text {
    if (![text isKindOfClass:NSString.class] || !text.length) return text;

    NSString *clean =
        [text stringByReplacingOccurrencesOfString:@"Conectar y cargar apps"
                                        withString:@"Conectar túnel"];

    NSString *lower = clean.lowercaseString;
    BOOL mentionsCatalog =
        [lower containsString:@"catálogo"] ||
        [lower containsString:@"apps en"];

    if (!mentionsCatalog) return clean;

    NSRange warningRange = [clean rangeOfString:@"\n\n"];
    NSString *warning = warningRange.location == NSNotFound
        ? @""
        : [clean substringFromIndex:warningRange.location];

    NSString *base = self.tunnelConnected
        ? (self.applicationFileAccessAvailable
            ? @"Túnel conectado correctamente. Servicios de archivos disponibles."
            : @"Túnel conectado correctamente.")
        : @"Comprobando el túnel…";

    return [base stringByAppendingString:warning];
}

- (void)xfp_updateButtons {
    [self xfp_updateButtons];

    self.statusLabel.text = [self xfp_cleanStatusText:self.statusLabel.text];

    UIButton *openFiles =
        objc_getAssociatedObject(self, XFOpenFilesButtonKey);
    openFiles.enabled = !self.busy && self.tunnelConnected;

    UIButtonConfiguration *configuration = self.connectButton.configuration;
    if (configuration) {
        configuration.title = @"Conectar túnel";
        self.connectButton.configuration = configuration;
    }
}

- (NSInteger)xfp_tableView:(UITableView *)tableView
     numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 0;
}

- (NSString *)xfp_tableView:(UITableView *)tableView
    titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return nil;
}

- (NSString *)xfp_tableView:(UITableView *)tableView
    titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    NSString *version =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"XFTunnelModuleVersion"];
    if (![version isKindOfClass:NSString.class] || !version.length) version = @"1.3.1";

    return [NSString stringWithFormat:
        @"Módulo %@ · Conexión y emparejamiento administrados por XITFORGE.",
        version];
}

- (void)xfp_requestPairingNotifications {
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;

        [center requestAuthorizationWithOptions:
            (UNAuthorizationOptionAlert |
             UNAuthorizationOptionSound |
             UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError *error) {
            (void)granted;
            (void)error;
        }];
    }];
}

- (void)xfp_sendPairingPINNotification:(NSString *)PIN {
    if (PIN.length != 6) return;

    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        BOOL allowed =
            settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional ||
            settings.authorizationStatus == UNAuthorizationStatusEphemeral;

        if (!allowed) return;

        UNMutableNotificationContent *content =
            [[UNMutableNotificationContent alloc] init];
        content.title = @"XITFORGE · CÓDIGO DE EMPAREJAMIENTO";
        content.body =
            [NSString stringWithFormat:
                @"Tu código es %@. Introdúcelo en Ajustes para completar el emparejamiento.",
                PIN];
        content.sound = UNNotificationSound.defaultSound;
        content.threadIdentifier = @"com.xitforge.pairing";

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.25
                                                               repeats:NO];

        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:
                [NSString stringWithFormat:@"xitforge-pairing-%@",
                    NSUUID.UUID.UUIDString]
                                              content:content
                                              trigger:trigger];

        [center addNotificationRequest:request withCompletionHandler:nil];
    }];
}

- (void)xfp_startOnDevicePairing {
    [self xfp_requestPairingNotifications];
    [self xfp_startOnDevicePairing];

    XFOnDevicePairing *service = self.pairingService;
    if (!service || !service.pinHandler) return;

    static const void *XFPairingNotificationWrappedKey =
        &XFPairingNotificationWrappedKey;

    if ([objc_getAssociatedObject(service, XFPairingNotificationWrappedKey) boolValue]) {
        return;
    }

    objc_setAssociatedObject(service,
                             XFPairingNotificationWrappedKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    void (^originalPINHandler)(NSString *) = [service.pinHandler copy];
    __weak typeof(self) weakSelf = self;

    service.pinHandler = ^(NSString *PIN) {
        if (originalPINHandler) originalPINHandler(PIN);
        [weakSelf xfp_sendPairingPINNotification:PIN];
    };
}

- (void)xfp_showTunnelHelp {
    XFProfessionalAlert(
        self,
        @"Activar el túnel",
        @"1. Mantén el Wi-Fi encendido.\n"
         "2. Empareja este iPhone o importa un registro válido.\n"
         "3. Activa LocalDevVPN.\n"
         "4. Vuelve a XITFORGE y pulsa «Conectar túnel».\n\n"
         "El estado solo aparecerá como conectado cuando el dispositivo responda correctamente."
    );
}

- (void)xfp_openFilesByIdentifier {
    if (!self.tunnelConnected) {
        XFProfessionalAlert(
            self,
            @"Conecta el túnel",
            @"Primero pulsa «Conectar túnel» y comprueba que la conexión esté activa."
        );
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Abrir archivos de una app"
                                            message:@"Escribe el identificador de la app. El catálogo permanece oculto."
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"com.ejemplo.app";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak UIAlertController *weakAlert = alert;
    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction actionWithTitle:@"Abrir"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
        (void)action;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSString *identifier =
            [weakAlert.textFields.firstObject.text
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];

        if (!identifier.length) {
            XFProfessionalAlert(
                strongSelf,
                @"Identificador requerido",
                @"Escribe el identificador de la app que quieres abrir."
            );
            return;
        }

        Class directoryClass = NSClassFromString(@"XFAirLiftDirectoryController");
        SEL initializer =
            NSSelectorFromString(@"initWithBackend:queue:applicationID:relativePath:");

        if (!directoryClass ||
            ![directoryClass instancesRespondToSelector:initializer]) {
            XFProfessionalAlert(
                strongSelf,
                @"No disponible",
                @"No se pudo abrir el administrador de archivos."
            );
            return;
        }

        id queueObject = strongSelf.operationQueue;
        id controller =
            ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
                [directoryClass alloc],
                initializer,
                strongSelf.backend,
                queueObject,
                identifier,
                @"");

        if ([controller isKindOfClass:UIViewController.class]) {
            [strongSelf.navigationController
                pushViewController:(UIViewController *)controller
                          animated:YES];
        }
    }]];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"Cancelar"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
