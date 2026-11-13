#import "XFProxyViewController.h"
#import "XFProxyVPNManager.h"

@interface XFProxyViewController ()
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *connectionButton;
@property (nonatomic, strong) UIButton *profileButton;
@end

@implementation XFProxyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Proxy";
    self.view.backgroundColor = UIColor.blackColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.stateLabel = [self label:UIFontTextStyleTitle2 color:UIColor.whiteColor];
    self.stateLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    self.messageLabel = [self label:UIFontTextStyleSubheadline color:UIColor.secondaryLabelColor];
    self.connectionButton = [self button:@"Conectar" image:@"power" primary:YES action:@selector(toggleConnection)];
    self.profileButton = [self button:@"Instalar certificado" image:@"arrow.down.document" primary:NO action:@selector(openProfile)];

    UIStackView *status = [self card:@[self.stateLabel, self.messageLabel, self.connectionButton]];
    UILabel *setup = [self label:UIFontTextStyleSubheadline color:UIColor.secondaryLabelColor];
    setup.text = @"Si ya instalaste el certificado de XITFORGE y activaste su confianza, puedes conectar directamente.";
    UIStackView *certificate = [self card:@[self.profileButton, setup]];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[status, certificate]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 14;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(connectionChanged:)
                                                name:XFProxyVPNDidChangeNotification object:XFProxyVPNManager.shared];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:)
                                                name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [XFProxyVPNManager.shared refresh];
    [self updateConnection];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UILabel *)label:(UIFontTextStyle)style color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)button:(NSString *)title image:(NSString *)image primary:(BOOL)primary action:(SEL)action {
    UIButtonConfiguration *configuration = primary ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:image];
    configuration.imagePadding = 10;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.baseBackgroundColor = primary ? [UIColor colorWithRed:0.72 green:0.08 blue:0.15 alpha:1] : [UIColor colorWithWhite:0.24 alpha:1];
    configuration.baseForegroundColor = UIColor.whiteColor;
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIStackView *)card:(NSArray<UIView *> *)items {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:items];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.layoutMarginsRelativeArrangement = YES;
    stack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(16, 16, 16, 16);
    stack.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    stack.layer.cornerRadius = 16;
    return stack;
}

- (void)becameActive:(NSNotification *)notification {
    if (self.viewIfLoaded.window) [XFProxyVPNManager.shared refresh];
    [self updateConnection];
}

- (void)connectionChanged:(NSNotification *)notification {
    [self updateConnection];
}

- (void)updateConnection {
    XFProxyVPNManager *manager = XFProxyVPNManager.shared;
    NEVPNStatus status = manager.status;
    BOOL connected = status == NEVPNStatusConnected;
    BOOL connecting = manager.isConnecting || status == NEVPNStatusConnecting || status == NEVPNStatusReasserting;
    BOOL stopping = status == NEVPNStatusDisconnecting;
    self.stateLabel.text = connected ? @"Conectado" : stopping ? @"Desconectando…" : connecting ? @"Conectando…" : @"Desconectado";
    self.stateLabel.textColor = connected ? UIColor.systemGreenColor : UIColor.whiteColor;
    self.messageLabel.text = manager.statusMessage;
    self.messageLabel.hidden = !manager.statusMessage.length;
    self.profileButton.enabled = manager.profileURL != nil;
    UIButtonConfiguration *button = self.connectionButton.configuration;
    button.title = connected ? @"Desconectar" : connecting ? @"Cancelar" : @"Conectar";
    self.connectionButton.configuration = button;
    self.connectionButton.enabled = !stopping;
}

- (void)toggleConnection {
    XFProxyVPNManager *manager = XFProxyVPNManager.shared;
    if (manager.isConnecting || manager.status == NEVPNStatusConnecting || manager.status == NEVPNStatusReasserting || manager.status == NEVPNStatusConnected) {
        [manager disconnect];
    } else {
        [manager connect];
    }
}

- (void)openProfile {
    NSURL *url = XFProxyVPNManager.shared.profileURL;
    if (!url) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Instalar certificado"
        message:@"Abre el enlace, instala el perfil desde Ajustes y activa su confianza en General → Información → Ajustes de confianza de certificados."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Abrir descarga" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
