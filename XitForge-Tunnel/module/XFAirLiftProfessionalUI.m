#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "XFAirLiftViewController.h"
#import "XFOnDevicePairing.h"

#pragma mark - XITFORGE visual language

static UIColor *XFRed(void) {
    return [UIColor colorWithRed:0.95 green:0.10 blue:0.16 alpha:1.0];
}

static UIColor *XFRedDark(void) {
    return [UIColor colorWithRed:0.16 green:0.035 blue:0.045 alpha:1.0];
}

static UIColor *XFBackground(void) {
    return [UIColor colorWithRed:0.018 green:0.018 blue:0.025 alpha:1.0];
}

static UIColor *XFCard(void) {
    return [UIColor colorWithWhite:0.055 alpha:1.0];
}

static UIColor *XFCardRaised(void) {
    return [UIColor colorWithWhite:0.075 alpha:1.0];
}

static UIColor *XFSecondaryText(void) {
    return [UIColor colorWithWhite:0.58 alpha:1.0];
}

static UIView *XFMakeCard(CGFloat radius) {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = XFCard();
    view.layer.cornerRadius = radius;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.24;
    view.layer.shadowRadius = 14.0;
    view.layer.shadowOffset = CGSizeMake(0.0, 7.0);
    return view;
}

static UILabel *XFMakeLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.numberOfLines = 0;
    return label;
}

static UIImageView *XFMakeIcon(NSString *name, UIColor *tint, CGFloat pointSize) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                        weight:UIImageSymbolWeightSemibold];
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:
            [[UIImage systemImageNamed:name] imageWithConfiguration:configuration]];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.tintColor = tint;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    return imageView;
}

static void XFPresentSimpleAlert(UIViewController *controller,
                                 NSString *title,
                                 NSString *message) {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Entendido"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static void XFSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) return;
    method_exchangeImplementations(originalMethod, replacementMethod);
}

#pragma mark - Tab order

static UIViewController *XFRootController(UIViewController *controller) {
    if ([controller isKindOfClass:UINavigationController.class]) {
        return ((UINavigationController *)controller).viewControllers.firstObject;
    }
    return controller;
}

static void XFReorderMainTabs(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    SEL getter = NSSelectorFromString(@"mainTabBar");
    if (![delegate respondsToSelector:getter]) return;

    id candidate = ((id (*)(id, SEL))objc_msgSend)(delegate, getter);
    if (![candidate isKindOfClass:UITabBarController.class]) return;

    UITabBarController *tabs = candidate;
    NSMutableArray<UIViewController *> *items = [tabs.viewControllers mutableCopy];
    if (!items.count) return;

    UIViewController *tunnel = nil;
    UIViewController *settings = nil;

    for (UIViewController *item in items) {
        UIViewController *root = XFRootController(item);
        if ([root isKindOfClass:XFAirLiftViewController.class]) tunnel = item;
        if ([item.tabBarItem.title isEqualToString:@"Ajustes"]) settings = item;
    }

    if (!tunnel) return;

    [items removeObject:tunnel];
    [items insertObject:tunnel atIndex:MIN((NSUInteger)1, items.count)];

    if (settings) {
        [items removeObject:settings];
        [items insertObject:settings atIndex:MIN((NSUInteger)2, items.count)];
    }

    [tabs setViewControllers:items animated:NO];
}

#pragma mark - Console

@interface XFConsoleViewController : UIViewController
@property (nonatomic, copy) NSString * (^reportProvider)(void);
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (instancetype)initWithProvider:(NSString * (^)(void))provider;
@end

@implementation XFConsoleViewController

- (instancetype)initWithProvider:(NSString * (^)(void))provider {
    self = [super init];
    if (self) {
        _reportProvider = [provider copy];
        self.title = @"Consola";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = XFBackground();

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = XFBackground();
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]
    };
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.tintColor = XFRed();

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Cerrar"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(closeConsole)];

    UIBarButtonItem *copy =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyConsole)];

    UIBarButtonItem *refresh =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(refreshConsole)];

    self.navigationItem.rightBarButtonItems = @[refresh, copy];

    UIView *card = XFMakeCard(20.0);
    [self.view addSubview:card];

    UILabel *label = XFMakeLabel(@"XITFORGE CONSOLE",
                                 11.0,
                                 UIFontWeightBold,
                                 XFRed());
    [card addSubview:label];

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.backgroundColor = [UIColor colorWithWhite:0.025 alpha:1.0];
    self.textView.textColor = [UIColor colorWithWhite:0.84 alpha:1.0];
    self.textView.font = [UIFont monospacedSystemFontOfSize:12.5
                                                    weight:UIFontWeightRegular];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.layer.cornerRadius = 14.0;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;
    self.textView.textContainerInset = UIEdgeInsetsMake(14.0, 14.0, 14.0, 14.0);
    [card addSubview:self.textView];

    self.spinner =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = XFRed();
    self.spinner.hidesWhenStopped = YES;
    [card addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0],
        [card.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14.0],
        [card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16.0],

        [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [label.topAnchor constraintEqualToAnchor:card.topAnchor constant:17.0],

        [self.textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [self.textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [self.textView.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:12.0],
        [self.textView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.textView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.textView.centerYAnchor],
    ]];

    [self refreshConsole];
}

- (void)closeConsole {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyConsole {
    if (!self.textView.text.length) return;
    UIPasteboard.generalPasteboard.string = self.textView.text;
}

- (void)refreshConsole {
    [self.spinner startAnimating];
    self.textView.text = @"Cargando consola…";

    NSString * (^provider)(void) = [self.reportProvider copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = provider ? provider() : @"";
        if (![report isKindOfClass:NSString.class] || !report.length) {
            report = @"Sin información disponible.";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.textView.text =
                [NSString stringWithFormat:
                    @"XITFORGE TÚNEL\n"
                     "────────────────────────\n"
                     "%@\n"
                     "────────────────────────\n"
                     "Actualizado: %@",
                    report,
                    [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                   dateStyle:NSDateFormatterShortStyle
                                                   timeStyle:NSDateFormatterMediumStyle]];
        });
    });
}

@end

#pragma mark - Existing private UI exposed to the category

@interface XFConnectionStatusView : UIStackView
@property (nonatomic, strong) UILabel *tunnelLabel;
@property (nonatomic, strong) UILabel *pairingLabel;
- (void)showConnected:(BOOL)connected pairingAvailable:(BOOL)available;
- (void)showPairingInProgress:(BOOL)inProgress available:(BOOL)available;
@end

@interface XFAirLiftViewController (XFV3Private)
@property (nonatomic, strong) id backend;
@property (nonatomic, strong) dispatch_queue_t operationQueue;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) XFConnectionStatusView *connectionStatus;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *pairButton;
@property (nonatomic, strong) UIButton *cancelPairButton;
@property (nonatomic, strong) UIButton *pinCopyButton;
@property (nonatomic, strong) UILabel *pairingPINLabel;
@property (nonatomic, strong) UILabel *pairingGuideLabel;
@property (nonatomic, strong) XFOnDevicePairing *pairingService;
@property (nonatomic, assign) BOOL tunnelConnected;
@property (nonatomic, assign) BOOL pairingAvailable;
@property (nonatomic, assign) BOOL applicationFileAccessAvailable;
@property (nonatomic, assign) BOOL busy;
- (void)updateButtons;
- (void)startOnDevicePairing;
- (void)xfv3_openConsole;
@end

#pragma mark - Status view: match Home UI instead of generic tinted card

@implementation XFConnectionStatusView (XFV2)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XFSwizzle(self,
                  @selector(showConnected:pairingAvailable:),
                  @selector(xfv2_showConnected:pairingAvailable:));
        XFSwizzle(self,
                  @selector(showPairingInProgress:available:),
                  @selector(xfv2_showPairingInProgress:available:));
    });
}

- (void)xfv2_showConnected:(BOOL)connected pairingAvailable:(BOOL)available {
    [self xfv2_showConnected:connected pairingAvailable:available];

    self.backgroundColor = UIColor.clearColor;
    self.layer.cornerRadius = 0.0;
    self.layer.borderWidth = 0.0;
    self.layer.shadowOpacity = 0.0;

    self.tunnelLabel.text =
        connected ? @"CONECTADO" : @"DESCONECTADO";
    self.tunnelLabel.textColor =
        connected ? XFRed() : [UIColor colorWithWhite:0.48 alpha:1.0];
    self.tunnelLabel.font =
        [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];

    [self xfv2_showPairingInProgress:NO available:available];
}

- (void)xfv2_showPairingInProgress:(BOOL)inProgress available:(BOOL)available {
    [self xfv2_showPairingInProgress:inProgress available:available];

    if (inProgress) {
        self.pairingLabel.text = @"ESPERANDO APROBACIÓN";
        self.pairingLabel.textColor = UIColor.systemOrangeColor;
    } else if (available) {
        self.pairingLabel.text = @"PAIRING GUARDADO";
        self.pairingLabel.textColor = XFRed();
    } else {
        self.pairingLabel.text = @"SIN EMPAREJAR";
        self.pairingLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
    }

    self.pairingLabel.font =
        [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
}

@end

#pragma mark - Main professional tunnel screen

static const void *XFV2OpenFilesKey = &XFV2OpenFilesKey;
static const void *XFV2HeaderBuiltKey = &XFV2HeaderBuiltKey;

@implementation XFAirLiftViewController (XFV2)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XFSwizzle(self, @selector(viewDidLoad), @selector(xfv2_viewDidLoad));
        XFSwizzle(self, @selector(updateButtons), @selector(xfv2_updateButtons));

        XFSwizzle(self,
                  @selector(tableView:numberOfRowsInSection:),
                  @selector(xfv2_tableView:numberOfRowsInSection:));
        XFSwizzle(self,
                  @selector(tableView:titleForHeaderInSection:),
                  @selector(xfv2_tableView:titleForHeaderInSection:));
        XFSwizzle(self,
                  @selector(tableView:titleForFooterInSection:),
                  @selector(xfv2_tableView:titleForFooterInSection:));

        XFSwizzle(self,
                  @selector(startOnDevicePairing),
                  @selector(xfv2_startOnDevicePairing));

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self
                   selector:@selector(xfv2_appReady:)
                       name:UIApplicationDidFinishLaunchingNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(xfv2_appReady:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:nil];
    });
}

+ (void)xfv2_appReady:(NSNotification *)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            XFReorderMainTabs();
        });
    });
}

#pragma mark Buttons styled like XITFORGE Home

- (void)xfv2_stylePrimaryButton:(UIButton *)button title:(NSString *)title {
    if (!button) return;

    button.configuration = nil;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font =
        [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];

    button.backgroundColor = XFRed();
    button.layer.cornerRadius = 16.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [XFRed() colorWithAlphaComponent:0.9].CGColor;
    button.layer.shadowColor = XFRed().CGColor;
    button.layer.shadowOpacity = 0.20;
    button.layer.shadowRadius = 10.0;
    button.layer.shadowOffset = CGSizeMake(0.0, 5.0);

    button.contentEdgeInsets = UIEdgeInsetsMake(15.0, 18.0, 15.0, 18.0);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52.0].active = YES;
}

- (void)xfv2_styleSecondaryButton:(UIButton *)button title:(NSString *)title {
    if (!button) return;

    button.configuration = nil;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font =
        [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];

    button.backgroundColor = [UIColor colorWithWhite:0.085 alpha:1.0];
    button.layer.cornerRadius = 15.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;

    button.contentEdgeInsets = UIEdgeInsetsMake(13.0, 16.0, 13.0, 16.0);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48.0].active = YES;
}

- (UIButton *)xfv2_actionRowWithTitle:(NSString *)title
                             subtitle:(NSString *)subtitle
                                 icon:(NSString *)icon
                             selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = XFCardRaised();
    button.layer.cornerRadius = 18.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
    [button addTarget:self
               action:selector
     forControlEvents:UIControlEventTouchUpInside];

    UIView *iconBox = [[UIView alloc] init];
    iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    iconBox.backgroundColor = XFRedDark();
    iconBox.layer.cornerRadius = 14.0;

    UIImageView *iconView = XFMakeIcon(icon, XFRed(), 18.0);
    [iconBox addSubview:iconView];

    UILabel *titleLabel =
        XFMakeLabel(title, 15.0, UIFontWeightSemibold, UIColor.whiteColor);

    UILabel *subtitleLabel =
        XFMakeLabel(subtitle, 12.5, UIFontWeightRegular, XFSecondaryText());

    UIImageView *chevron =
        XFMakeIcon(@"chevron.right", [UIColor colorWithWhite:0.38 alpha:1.0], 13.0);

    [button addSubview:iconBox];
    [button addSubview:titleLabel];
    [button addSubview:subtitleLabel];
    [button addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:74.0],

        [iconBox.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:14.0],
        [iconBox.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [iconBox.widthAnchor constraintEqualToConstant:44.0],
        [iconBox.heightAnchor constraintEqualToConstant:44.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconBox.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconBox.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:24.0],
        [iconView.heightAnchor constraintEqualToConstant:24.0],

        [chevron.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16.0],
        [chevron.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:10.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconBox.trailingAnchor constant:13.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],
        [titleLabel.topAnchor constraintEqualToAnchor:button.topAnchor constant:16.0],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
        [subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-14.0],
    ]];

    return button;
}

#pragma mark Build redesigned header

- (void)xfv2_viewDidLoad {
    [self xfv2_viewDidLoad];

    self.view.backgroundColor = XFBackground();
    self.tableView.backgroundColor = XFBackground();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.navigationItem.searchController = nil;

    self.title = @"Túnel";

    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithOpaqueBackground];
    nav.backgroundColor = XFBackground();
    nav.shadowColor = UIColor.clearColor;
    nav.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]
    };

    self.navigationController.navigationBar.standardAppearance = nav;
    self.navigationController.navigationBar.scrollEdgeAppearance = nav;
    self.navigationController.navigationBar.compactAppearance = nav;
    self.navigationController.navigationBar.tintColor = XFRed();

    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Consola"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(xfv3_openConsole)];

    if (![objc_getAssociatedObject(self, XFV2HeaderBuiltKey) boolValue]) {
        objc_setAssociatedObject(self,
                                 XFV2HeaderBuiltKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self xfv2_buildHeader];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        XFReorderMainTabs();
        [self.view setNeedsLayout];
    });
}

- (void)xfv2_buildHeader {
    NSArray<UIView *> *oldViews = [self.headerStack.arrangedSubviews copy];
    for (UIView *view in oldViews) {
        [self.headerStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    self.headerStack.spacing = 14.0;
    self.headerStack.layoutMargins =
        UIEdgeInsetsMake(18.0, 0.0, 22.0, 0.0);
    self.headerStack.layoutMarginsRelativeArrangement = YES;

    // Hero
    UIView *hero = XFMakeCard(22.0);
    hero.backgroundColor = [UIColor colorWithWhite:0.045 alpha:1.0];

    UIView *accent = [[UIView alloc] init];
    accent.translatesAutoresizingMaskIntoConstraints = NO;
    accent.backgroundColor = XFRed();
    accent.layer.cornerRadius = 2.0;

    UILabel *eyebrow =
        XFMakeLabel(@"XITFORGE", 11.0, UIFontWeightBold, XFRed());
    eyebrow.text = @"XITFORGE  •  TÚNEL";

    UILabel *headline =
        XFMakeLabel(@"Control del dispositivo", 22.0, UIFontWeightBold, UIColor.whiteColor);

    UILabel *sub =
        XFMakeLabel(@"Empareja, conecta y administra el acceso desde un solo lugar.",
                    13.0,
                    UIFontWeightRegular,
                    XFSecondaryText());

    UIView *iconBox = [[UIView alloc] init];
    iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    iconBox.backgroundColor = XFRedDark();
    iconBox.layer.cornerRadius = 18.0;

    UIImageView *heroIcon = XFMakeIcon(@"network", XFRed(), 24.0);
    [iconBox addSubview:heroIcon];

    [hero addSubview:accent];
    [hero addSubview:eyebrow];
    [hero addSubview:headline];
    [hero addSubview:sub];
    [hero addSubview:iconBox];

    [NSLayoutConstraint activateConstraints:@[
        [accent.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:18.0],
        [accent.topAnchor constraintEqualToAnchor:hero.topAnchor constant:20.0],
        [accent.widthAnchor constraintEqualToConstant:4.0],
        [accent.heightAnchor constraintEqualToConstant:34.0],

        [eyebrow.leadingAnchor constraintEqualToAnchor:accent.trailingAnchor constant:12.0],
        [eyebrow.topAnchor constraintEqualToAnchor:hero.topAnchor constant:18.0],

        [headline.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [headline.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:5.0],
        [headline.trailingAnchor constraintLessThanOrEqualToAnchor:iconBox.leadingAnchor constant:-14.0],

        [sub.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:headline.bottomAnchor constant:7.0],
        [sub.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-18.0],
        [sub.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-20.0],

        [iconBox.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-18.0],
        [iconBox.topAnchor constraintEqualToAnchor:hero.topAnchor constant:18.0],
        [iconBox.widthAnchor constraintEqualToConstant:52.0],
        [iconBox.heightAnchor constraintEqualToConstant:52.0],

        [heroIcon.centerXAnchor constraintEqualToAnchor:iconBox.centerXAnchor],
        [heroIcon.centerYAnchor constraintEqualToAnchor:iconBox.centerYAnchor],
        [heroIcon.widthAnchor constraintEqualToConstant:28.0],
        [heroIcon.heightAnchor constraintEqualToConstant:28.0],
    ]];

    [self.headerStack addArrangedSubview:hero];

    // Estado
    UIView *statusCard = XFMakeCard(20.0);
    UILabel *statusTitle =
        XFMakeLabel(@"ESTADO", 11.0, UIFontWeightBold, XFSecondaryText());

    self.connectionStatus.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionStatus.axis = UILayoutConstraintAxisVertical;
    self.connectionStatus.spacing = 7.0;
    self.connectionStatus.backgroundColor = UIColor.clearColor;
    self.connectionStatus.layoutMarginsRelativeArrangement = NO;

    [statusCard addSubview:statusTitle];
    [statusCard addSubview:self.connectionStatus];

    [NSLayoutConstraint activateConstraints:@[
        [statusTitle.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:18.0],
        [statusTitle.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:17.0],
        [statusTitle.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-18.0],

        [self.connectionStatus.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:18.0],
        [self.connectionStatus.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-18.0],
        [self.connectionStatus.topAnchor constraintEqualToAnchor:statusTitle.bottomAnchor constant:11.0],
        [self.connectionStatus.bottomAnchor constraintEqualToAnchor:statusCard.bottomAnchor constant:-17.0],
    ]];

    [self.headerStack addArrangedSubview:statusCard];

    // Emparejamiento
    UIView *pairCard = XFMakeCard(20.0);
    UILabel *pairTitle =
        XFMakeLabel(@"EMPAREJAMIENTO", 11.0, UIFontWeightBold, XFSecondaryText());
    UILabel *pairHeading =
        XFMakeLabel(@"Vincula este iPhone", 17.0, UIFontWeightSemibold, UIColor.whiteColor);

    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.statusLabel.textColor = XFSecondaryText();

    self.pairingGuideLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pairingGuideLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    self.pairingGuideLabel.font =
        [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];

    self.pairingPINLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pairingPINLabel.textColor = UIColor.whiteColor;
    self.pairingPINLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:32.0 weight:UIFontWeightBold];

    UIView *pinBox = XFMakeCard(16.0);
    pinBox.backgroundColor = [UIColor colorWithWhite:0.085 alpha:1.0];
    pinBox.layer.shadowOpacity = 0.0;

    [pinBox addSubview:self.pairingPINLabel];

    [self xfv2_stylePrimaryButton:self.pairButton title:@"EMPAREJAR ESTE IPHONE"];
    [self xfv2_styleSecondaryButton:self.cancelPairButton title:@"CANCELAR EMPAREJAMIENTO"];
    [self xfv2_styleSecondaryButton:self.importButton title:@"IMPORTAR EMPAREJAMIENTO"];
    [self xfv2_styleSecondaryButton:self.pinCopyButton title:@"COPIAR CÓDIGO"];

    UIStackView *pairActions =
        [[UIStackView alloc] initWithArrangedSubviews:@[
            self.pairButton,
            self.cancelPairButton,
            self.importButton
        ]];
    pairActions.translatesAutoresizingMaskIntoConstraints = NO;
    pairActions.axis = UILayoutConstraintAxisVertical;
    pairActions.spacing = 9.0;

    [pairCard addSubview:pairTitle];
    [pairCard addSubview:pairHeading];
    [pairCard addSubview:self.statusLabel];
    [pairCard addSubview:self.pairingGuideLabel];
    [pairCard addSubview:pinBox];
    [pairCard addSubview:self.pinCopyButton];
    [pairCard addSubview:pairActions];

    [NSLayoutConstraint activateConstraints:@[
        [pairTitle.leadingAnchor constraintEqualToAnchor:pairCard.leadingAnchor constant:18.0],
        [pairTitle.topAnchor constraintEqualToAnchor:pairCard.topAnchor constant:18.0],
        [pairTitle.trailingAnchor constraintEqualToAnchor:pairCard.trailingAnchor constant:-18.0],

        [pairHeading.leadingAnchor constraintEqualToAnchor:pairTitle.leadingAnchor],
        [pairHeading.trailingAnchor constraintEqualToAnchor:pairTitle.trailingAnchor],
        [pairHeading.topAnchor constraintEqualToAnchor:pairTitle.bottomAnchor constant:7.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:pairTitle.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:pairTitle.trailingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:pairHeading.bottomAnchor constant:7.0],

        [self.pairingGuideLabel.leadingAnchor constraintEqualToAnchor:pairTitle.leadingAnchor],
        [self.pairingGuideLabel.trailingAnchor constraintEqualToAnchor:pairTitle.trailingAnchor],
        [self.pairingGuideLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:10.0],

        [pinBox.leadingAnchor constraintEqualToAnchor:pairTitle.leadingAnchor],
        [pinBox.trailingAnchor constraintEqualToAnchor:pairTitle.trailingAnchor],
        [pinBox.topAnchor constraintEqualToAnchor:self.pairingGuideLabel.bottomAnchor constant:12.0],
        [pinBox.heightAnchor constraintGreaterThanOrEqualToConstant:68.0],

        [self.pairingPINLabel.centerXAnchor constraintEqualToAnchor:pinBox.centerXAnchor],
        [self.pairingPINLabel.centerYAnchor constraintEqualToAnchor:pinBox.centerYAnchor],
        [self.pairingPINLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:pinBox.leadingAnchor constant:12.0],
        [self.pairingPINLabel.trailingAnchor constraintLessThanOrEqualToAnchor:pinBox.trailingAnchor constant:-12.0],

        [self.pinCopyButton.leadingAnchor constraintEqualToAnchor:pairTitle.leadingAnchor],
        [self.pinCopyButton.trailingAnchor constraintEqualToAnchor:pairTitle.trailingAnchor],
        [self.pinCopyButton.topAnchor constraintEqualToAnchor:pinBox.bottomAnchor constant:9.0],

        [pairActions.leadingAnchor constraintEqualToAnchor:pairTitle.leadingAnchor],
        [pairActions.trailingAnchor constraintEqualToAnchor:pairTitle.trailingAnchor],
        [pairActions.topAnchor constraintEqualToAnchor:self.pinCopyButton.bottomAnchor constant:12.0],
        [pairActions.bottomAnchor constraintEqualToAnchor:pairCard.bottomAnchor constant:-18.0],
    ]];

    [self.headerStack addArrangedSubview:pairCard];

    // Conexión
    UIView *connectCard = XFMakeCard(20.0);
    UILabel *connectTitle =
        XFMakeLabel(@"CONEXIÓN", 11.0, UIFontWeightBold, XFSecondaryText());
    UILabel *connectHeading =
        XFMakeLabel(@"Activa el túnel", 17.0, UIFontWeightSemibold, UIColor.whiteColor);
    UILabel *connectInfo =
        XFMakeLabel(@"Con el pairing listo y LocalDevVPN activo, comprueba la conexión.",
                    13.0,
                    UIFontWeightRegular,
                    XFSecondaryText());

    [self xfv2_stylePrimaryButton:self.connectButton title:@"CONECTAR TÚNEL"];

    [connectCard addSubview:connectTitle];
    [connectCard addSubview:connectHeading];
    [connectCard addSubview:connectInfo];
    [connectCard addSubview:self.connectButton];

    [NSLayoutConstraint activateConstraints:@[
        [connectTitle.leadingAnchor constraintEqualToAnchor:connectCard.leadingAnchor constant:18.0],
        [connectTitle.topAnchor constraintEqualToAnchor:connectCard.topAnchor constant:18.0],
        [connectTitle.trailingAnchor constraintEqualToAnchor:connectCard.trailingAnchor constant:-18.0],

        [connectHeading.leadingAnchor constraintEqualToAnchor:connectTitle.leadingAnchor],
        [connectHeading.trailingAnchor constraintEqualToAnchor:connectTitle.trailingAnchor],
        [connectHeading.topAnchor constraintEqualToAnchor:connectTitle.bottomAnchor constant:7.0],

        [connectInfo.leadingAnchor constraintEqualToAnchor:connectTitle.leadingAnchor],
        [connectInfo.trailingAnchor constraintEqualToAnchor:connectTitle.trailingAnchor],
        [connectInfo.topAnchor constraintEqualToAnchor:connectHeading.bottomAnchor constant:6.0],

        [self.connectButton.leadingAnchor constraintEqualToAnchor:connectTitle.leadingAnchor],
        [self.connectButton.trailingAnchor constraintEqualToAnchor:connectTitle.trailingAnchor],
        [self.connectButton.topAnchor constraintEqualToAnchor:connectInfo.bottomAnchor constant:15.0],
        [self.connectButton.bottomAnchor constraintEqualToAnchor:connectCard.bottomAnchor constant:-18.0],
    ]];

    [self.headerStack addArrangedSubview:connectCard];

    // Herramienta de archivos sin catálogo
    UIButton *openFiles =
        [self xfv2_actionRowWithTitle:@"Abrir archivos"
                             subtitle:@"Accede mediante el identificador de la app"
                                 icon:@"folder.fill"
                             selector:@selector(xfv2_openFilesByIdentifier)];
    openFiles.enabled = NO;
    objc_setAssociatedObject(self,
                             XFV2OpenFilesKey,
                             openFiles,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self.headerStack addArrangedSubview:openFiles];

    // Nota mínima
    UILabel *footer =
        XFMakeLabel(@"El catálogo de aplicaciones está oculto.",
                    11.5,
                    UIFontWeightRegular,
                    [UIColor colorWithWhite:0.34 alpha:1.0]);
    footer.textAlignment = NSTextAlignmentCenter;
    [self.headerStack addArrangedSubview:footer];

    self.navigationItem.searchController = nil;
}

#pragma mark Hide old catalog

- (NSInteger)xfv2_tableView:(UITableView *)tableView
      numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 0;
}

- (NSString *)xfv2_tableView:(UITableView *)tableView
     titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return nil;
}

- (NSString *)xfv2_tableView:(UITableView *)tableView
     titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return nil;
}

#pragma mark Keep toolbar/nav polished after original updates

- (void)xfv2_updateButtons {
    [self xfv2_updateButtons];

    // La barra superior queda limpia: solo Consola.
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Consola"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(xfv3_openConsole)];
    self.navigationItem.rightBarButtonItem.enabled = !self.busy;

    UIButton *openFiles = objc_getAssociatedObject(self, XFV2OpenFilesKey);
    openFiles.enabled = !self.busy && self.tunnelConnected;
    openFiles.alpha = openFiles.enabled ? 1.0 : 0.45;

    self.statusLabel.text =
        [self.statusLabel.text
            stringByReplacingOccurrencesOfString:@"Conectar y cargar apps"
                                      withString:@"Conectar túnel"];

    [self xfv2_stylePrimaryButton:self.connectButton title:@"CONECTAR TÚNEL"];
}

#pragma mark Console

- (void)xfv3_openConsole {
    __weak typeof(self) weakSelf = self;

    XFConsoleViewController *console =
        [[XFConsoleViewController alloc] initWithProvider:^NSString *{
            typeof(self) self = weakSelf;
            if (!self) return @"XITFORGE no está disponible.";

            id backend = self.backend;
            SEL selector = NSSelectorFromString(@"connectionDiagnostics");
            NSString *diagnostics = @"";

            if (backend && [backend respondsToSelector:selector]) {
                diagnostics =
                    ((id (*)(id, SEL))objc_msgSend)(backend, selector);
            }

            if (![diagnostics isKindOfClass:NSString.class] || !diagnostics.length) {
                diagnostics = @"No se recibió diagnóstico del túnel.";
            }

            NSString *connection =
                self.tunnelConnected ? @"CONECTADO" : @"DESCONECTADO";
            NSString *pairing =
                self.pairingAvailable ? @"GUARDADO" : @"PENDIENTE";

            return [NSString stringWithFormat:
                @"ESTADO DEL TÚNEL: %@\n"
                 "PAIRING: %@\n\n"
                 "%@",
                connection,
                pairing,
                diagnostics];
        }];

    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:console];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

#pragma mark Pairing notification

- (void)xfv2_requestNotificationPermission {
    UNUserNotificationCenter *center =
        UNUserNotificationCenter.currentNotificationCenter;

    [center getNotificationSettingsWithCompletionHandler:
        ^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;

        [center requestAuthorizationWithOptions:
            (UNAuthorizationOptionAlert |
             UNAuthorizationOptionSound |
             UNAuthorizationOptionBadge)
                              completionHandler:
            ^(BOOL granted, NSError *error) {
                (void)granted;
                (void)error;
            }];
    }];
}

- (void)xfv2_notifyPIN:(NSString *)PIN {
    if (PIN.length != 6) return;

    UNUserNotificationCenter *center =
        UNUserNotificationCenter.currentNotificationCenter;

    [center getNotificationSettingsWithCompletionHandler:
        ^(UNNotificationSettings *settings) {
        BOOL allowed =
            settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional ||
            settings.authorizationStatus == UNAuthorizationStatusEphemeral;

        if (!allowed) return;

        UNMutableNotificationContent *content =
            [[UNMutableNotificationContent alloc] init];
        content.title = @"XITFORGE";
        content.body =
            [NSString stringWithFormat:@"Código de emparejamiento: %@", PIN];
        content.sound = UNNotificationSound.defaultSound;

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.25
                                                               repeats:NO];

        UNNotificationRequest *request =
            [UNNotificationRequest
                requestWithIdentifier:
                    [NSString stringWithFormat:@"xitforge-pair-%@",
                                               NSUUID.UUID.UUIDString]
                              content:content
                              trigger:trigger];

        [center addNotificationRequest:request withCompletionHandler:nil];
    }];
}

- (void)xfv2_startOnDevicePairing {
    [self xfv2_requestNotificationPermission];

    [self xfv2_startOnDevicePairing];

    XFOnDevicePairing *service = self.pairingService;
    if (!service || !service.pinHandler) return;

    static const void *XFV2WrappedPINKey = &XFV2WrappedPINKey;
    if ([objc_getAssociatedObject(service, XFV2WrappedPINKey) boolValue]) return;

    objc_setAssociatedObject(service,
                             XFV2WrappedPINKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    void (^original)(NSString *) = [service.pinHandler copy];
    __weak typeof(self) weakSelf = self;

    service.pinHandler = ^(NSString *PIN) {
        if (original) original(PIN);
        [weakSelf xfv2_notifyPIN:PIN];
    };
}

#pragma mark Open files without app catalog

- (void)xfv2_openFilesByIdentifier {
    if (!self.tunnelConnected) {
        XFPresentSimpleAlert(
            self,
            @"Túnel desconectado",
            @"Conecta el túnel antes de abrir los archivos de una app."
        );
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Abrir archivos"
                                            message:@"Escribe el identificador de la app."
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
        typeof(self) self = weakSelf;
        if (!self) return;

        NSString *identifier =
            [weakAlert.textFields.firstObject.text
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];

        if (!identifier.length) {
            XFPresentSimpleAlert(
                self,
                @"Falta el identificador",
                @"Escribe el identificador de la app."
            );
            return;
        }

        Class directoryClass = NSClassFromString(@"XFAirLiftDirectoryController");
        SEL initSelector =
            NSSelectorFromString(@"initWithBackend:queue:applicationID:relativePath:");

        if (!directoryClass ||
            ![directoryClass instancesRespondToSelector:initSelector]) {
            XFPresentSimpleAlert(
                self,
                @"No disponible",
                @"No se pudo abrir el administrador de archivos."
            );
            return;
        }

        id controller =
            ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
                [directoryClass alloc],
                initSelector,
                self.backend,
                self.operationQueue,
                identifier,
                @"");

        if ([controller isKindOfClass:UIViewController.class]) {
            [self.navigationController
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
