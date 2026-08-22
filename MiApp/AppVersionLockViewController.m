#import "AppVersionLockViewController.h"

@interface AppVersionLockViewController ()

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIButton *retryButton;

@end

@implementation AppVersionLockViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];

    UIColor *primary =
        [UIColor colorWithWhite:0.97 alpha:1.0];

    UIColor *secondary =
        [UIColor colorWithWhite:0.62 alpha:1.0];

    UIColor *accent =
        [UIColor colorWithRed:0.46 green:0.36 blue:1.0 alpha:1.0];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:0.075 alpha:1.0];
    card.layer.cornerRadius = 26.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [self.view addSubview:card];

    UIImageView *icon =
        [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"arrow.down.circle.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = accent;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:icon];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textColor = primary;
    self.titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    [card addSubview:self.titleLabel];

    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.messageLabel.textColor = secondary;
    self.messageLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    [card addSubview:self.messageLabel];

    self.versionLabel = [[UILabel alloc] init];
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.versionLabel.textColor = primary;
    self.versionLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.versionLabel.textAlignment = NSTextAlignmentCenter;
    self.versionLabel.numberOfLines = 0;
    [card addSubview:self.versionLabel];

    self.downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.downloadButton.backgroundColor = accent;
    self.downloadButton.tintColor = [UIColor whiteColor];
    self.downloadButton.layer.cornerRadius = 14.0;
    self.downloadButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    [self.downloadButton setTitle:@"DESCARGAR NUEVA VERSIÓN" forState:UIControlStateNormal];
    [self.downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.downloadButton];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.retryButton.tintColor = primary;
    self.retryButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    [self.retryButton setTitle:@"REINTENTAR" forState:UIControlStateNormal];
    [self.retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.retryButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:22.0],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-22.0],
        [card.widthAnchor constraintLessThanOrEqualToConstant:430.0],

        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:30.0],
        [icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:46.0],
        [icon.heightAnchor constraintEqualToConstant:46.0],

        [self.titleLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:22.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],

        [self.messageLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:14.0],
        [self.messageLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.messageLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],

        [self.versionLabel.topAnchor constraintEqualToAnchor:self.messageLabel.bottomAnchor constant:18.0],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.versionLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],

        [self.downloadButton.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:24.0],
        [self.downloadButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.downloadButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [self.downloadButton.heightAnchor constraintEqualToConstant:52.0],

        [self.retryButton.topAnchor constraintEqualToAnchor:self.downloadButton.bottomAnchor constant:10.0],
        [self.retryButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.retryButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [self.retryButton.heightAnchor constraintEqualToConstant:46.0],
        [self.retryButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22.0]
    ]];

    [self refreshContent];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshContent];
}

- (void)refreshContent {

    if (!self.isViewLoaded) {
        return;
    }

    self.titleLabel.text =
        self.headline.length > 0
            ? self.headline
            : @"Actualización requerida";

    self.messageLabel.text =
        self.messageText.length > 0
            ? self.messageText
            : @"Debes actualizar XITFORGE para continuar.";

    if (self.requiredVersion.length > 0) {
        self.versionLabel.text =
            [NSString stringWithFormat:
                @"Tu versión: %@\nVersión requerida: %@",
                self.currentVersion.length > 0 ? self.currentVersion : @"—",
                self.requiredVersion];
    } else {
        self.versionLabel.text =
            [NSString stringWithFormat:
                @"Tu versión: %@",
                self.currentVersion.length > 0 ? self.currentVersion : @"—"];
    }

    BOOL canDownload =
        self.showDownloadButton &&
        self.downloadURL.length > 0;

    self.downloadButton.hidden = !canDownload;
    self.downloadButton.userInteractionEnabled = canDownload;
}

- (void)setHeadline:(NSString *)headline {
    _headline = [headline copy];
    [self refreshContent];
}

- (void)setMessageText:(NSString *)messageText {
    _messageText = [messageText copy];
    [self refreshContent];
}

- (void)setCurrentVersion:(NSString *)currentVersion {
    _currentVersion = [currentVersion copy];
    [self refreshContent];
}

- (void)setRequiredVersion:(NSString *)requiredVersion {
    _requiredVersion = [requiredVersion copy];
    [self refreshContent];
}

- (void)setDownloadURL:(NSString *)downloadURL {
    _downloadURL = [downloadURL copy];
    [self refreshContent];
}

- (void)setShowDownloadButton:(BOOL)showDownloadButton {
    _showDownloadButton = showDownloadButton;
    [self refreshContent];
}

- (void)downloadTapped {

    NSURL *url = [NSURL URLWithString:self.downloadURL ?: @""];

    if (!url) {
        return;
    }

    [[UIApplication sharedApplication]
        openURL:url
        options:@{}
        completionHandler:nil];
}

- (void)retryTapped {
    if (self.retryHandler) {
        self.retryHandler();
    }
}

@end
