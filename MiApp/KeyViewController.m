#import "KeyViewController.h"
#import "ViewController.h"

static NSString *const kSettingsTextColor = @"settingsTextColor";
static NSString *const kSettingsBgColor = @"settingsBgColor";
static NSString *const kSettingsAccentColor = @"settingsAccentColor";
static NSString *const kSettingsLanguage = @"settingsLanguage";

#pragma mark - Theme Helpers

static UIColor *keyFondo(void) {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingsBgColor];
    if (data) return [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
    return [UIColor colorWithWhite:0.05 alpha:1.0];
}

static UIColor *keyAcento(void) {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingsAccentColor];
    if (data) return [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
    return [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
}

static UIColor *keyTextColor(void) {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingsTextColor];
    if (data) return [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
    return [UIColor whiteColor];
}

static NSString *keyLang(void) {
    NSString *lang = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingsLanguage];
    return lang ?: @"es";
}

static void saveColor(NSString *key, UIColor *color) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Translations

static NSString *t(NSString *key) {
    NSString *lang = keyLang();
    NSDictionary *es = @{
        @"subtitle": @"Licencia requerida para acceder",
        @"keyPlaceholder": @"XXXX-XXXX-XXXX-XXXX",
        @"acceder": @"ACCEDER",
        @"invalidKey": @"✗ Key inválida. Intenta de nuevo.",
        @"accessGranted": @"✓ Acceso concedido",
        @"version": @"v1.0 — Freebuff Build",
        @"settings": @"Configuración",
        @"textColor": @"Color del texto",
        @"bgColor": @"Color de fondo",
        @"accentColor": @"Color de acento",
        @"language": @"Idioma",
        @"close": @"Cerrar",
        @"save": @"Guardar"
    };
    NSDictionary *en = @{
        @"subtitle": @"License required to access",
        @"keyPlaceholder": @"XXXX-XXXX-XXXX-XXXX",
        @"acceder": @"ACCESS",
        @"invalidKey": @"✗ Invalid key. Try again.",
        @"accessGranted": @"✓ Access granted",
        @"version": @"v1.0 — Freebuff Build",
        @"settings": @"Settings",
        @"textColor": @"Text color",
        @"bgColor": @"Background color",
        @"accentColor": @"Accent color",
        @"language": @"Language",
        @"close": @"Close",
        @"save": @"Save"
    };
    NSDictionary *dict = [lang isEqualToString:@"en"] ? en : es;
    return dict[key] ?: key;
}

#pragma mark - Animated Background Dots

@interface KeyParticleView : UIView
@property (nonatomic, strong) NSMutableArray *dots;
@property (nonatomic, strong) CADisplayLink *link;
@end

@implementation KeyParticleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.dots = [NSMutableArray new];
        for (int i = 0; i < 40; i++) {
            UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 2, 2)];
            dot.backgroundColor = [keyAcento() colorWithAlphaComponent:arc4random_uniform(30) / 100.0 + 0.05];
            dot.layer.cornerRadius = 1;
            dot.center = CGPointMake(arc4random_uniform((uint32_t)frame.size.width),
                                     arc4random_uniform((uint32_t)frame.size.height));
            [self addSubview:dot];
            [self.dots addObject:dot];
        }
        self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)tick {
    for (UIView *dot in self.dots) {
        CGRect f = dot.frame;
        f.origin.y -= 0.3;
        if (f.origin.y < -5) {
            f.origin.y = self.bounds.size.height + 5;
            f.origin.x = arc4random_uniform((uint32_t)self.bounds.size.width);
        }
        dot.frame = f;
    }
}

- (void)dealloc { [self.link invalidate]; }

@end

#pragma mark - Key Validation

static BOOL validarKey(NSString *key) {
    NSString *k = [[key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] uppercaseString];
    if (k.length == 0) return NO;

    // Format: XXXX-XXXX-XXXX-XXXX (4 groups of 4 alphanumeric chars)
    NSString *pattern = @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if (![regex firstMatchInString:k options:0 range:NSMakeRange(0, k.length)]) return NO;

    // Pre-defined valid keys in XXXX-XXXX-XXXX-XXXX format
    NSArray *validKeys = @[
        @"XFAR-G202-4PR0-XXXX",
        @"FREE-KEYS-202-4XFT",
        @"XITF-ARGE-PRO-0001",
        @"DEVK-E202-4XFT-ARGE",
        @"LIBR-EACC-ESOX-FXXX",
        @"AAAA-BBBB-CCCC-DDDD",
        @"TEST-KEY0-0001-USED"
    ];
    for (NSString *vk in validKeys) {
        if ([k isEqualToString:vk]) return YES;
    }

    // Any key matching the format is valid (for testing)
    return YES;
}

#pragma mark - KeyViewController

@interface KeyViewController ()
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UIButton *accederBtn;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) KeyParticleView *particles;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIView *settingsOverlay;
@property (nonatomic, strong) UIView *settingsPanel;
@end

@implementation KeyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = keyFondo();
    [self rebuildUI];
}

- (void)rebuildUI {
    // Remove all subviews
    for (UIView *v in self.view.subviews) [v removeFromSuperview];

    self.view.backgroundColor = keyFondo();

    // Particles
    self.particles = [[KeyParticleView alloc] initWithFrame:self.view.bounds];
    self.particles.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.particles];

    CGFloat w = self.view.bounds.size.width;
    CGFloat padding = 32;

    // Settings button (top right)
    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.frame = CGRectMake(w - 50, 50, 36, 36);
    settingsBtn.tintColor = [UIColor grayColor];
    [settingsBtn setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    [settingsBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:settingsBtn];

    // Shield icon
    CGFloat logoY = self.view.bounds.size.height * 0.22;
    UIImageView *shieldIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, logoY, 60, 60)];
    shieldIcon.center = CGPointMake(w / 2, logoY);
    shieldIcon.image = [[UIImage systemImageNamed:@"lock.shield.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    shieldIcon.tintColor = keyAcento();
    shieldIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:shieldIcon];

    // Title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, logoY + 75, w - padding * 2, 40)];
    self.titleLabel.text = @"xitfarge";
    self.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:28];
    self.titleLabel.textColor = keyAcento();
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLabel];

    // Subtitle
    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, logoY + 115, w - padding * 2, 30)];
    self.subtitleLabel.text = t(@"subtitle");
    self.subtitleLabel.font = [UIFont fontWithName:@"Menlo" size:11];
    self.subtitleLabel.textColor = [UIColor grayColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.subtitleLabel];

    // Key input
    CGFloat fieldY = logoY + 170;
    self.keyField = [[UITextField alloc] initWithFrame:CGRectMake(padding, fieldY, w - padding * 2, 44)];
    self.keyField.placeholder = t(@"keyPlaceholder");
    self.keyField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.keyField.layer.cornerRadius = 12;
    self.keyField.layer.borderWidth = 1;
    self.keyField.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    self.keyField.textColor = keyTextColor();
    self.keyField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyField.returnKeyType = UIReturnKeyGo;
    self.keyField.textAlignment = NSTextAlignmentCenter;
    self.keyField.delegate = (id)self;

    UIImageView *keyIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 24, 20)];
    keyIcon.image = [[UIImage systemImageNamed:@"key.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    keyIcon.tintColor = [UIColor grayColor];
    keyIcon.contentMode = UIViewContentModeCenter;
    self.keyField.leftView = keyIcon;
    self.keyField.leftViewMode = UITextFieldViewModeAlways;
    [self.view addSubview:self.keyField];

    // Error
    self.errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, fieldY + 50, w - padding * 2, 20)];
    self.errorLabel.font = [UIFont fontWithName:@"Menlo" size:11];
    self.errorLabel.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.errorLabel];

    // Button
    CGFloat btnY = fieldY + 80;
    self.accederBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.accederBtn.frame = CGRectMake(padding, btnY, w - padding * 2, 48);
    [self.accederBtn setTitle:t(@"acceder") forState:UIControlStateNormal];
    self.accederBtn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16];
    [self.accederBtn setTitleColor:keyFondo() forState:UIControlStateNormal];
    self.accederBtn.backgroundColor = keyAcento();
    self.accederBtn.layer.cornerRadius = 12;
    [self.accederBtn addTarget:self action:@selector(intentarAcceso) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.accederBtn];

    // Version
    self.versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, self.view.bounds.size.height - 50, w - padding * 2, 20)];
    self.versionLabel.text = t(@"version");
    self.versionLabel.font = [UIFont fontWithName:@"Menlo" size:9];
    self.versionLabel.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.versionLabel.textAlignment = NSTextAlignmentCenter;
    self.versionLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.versionLabel];

    // Tap to dismiss
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.particles.frame = self.view.bounds;
}

- (void)dismissKeyboard { [self.view endEditing:YES]; }

#pragma mark - Key Access

- (void)intentarAcceso {
    NSString *key = self.keyField.text;
    if (validarKey(key)) {
        self.errorLabel.textColor = keyAcento();
        self.errorLabel.text = t(@"accessGranted");
        self.accederBtn.enabled = NO;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self abrirAppPrincipal];
        });
    } else {
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        shake.duration = 0.5;
        shake.values = @[@(-12), @(12), @(-10), @(10), @(-6), @(6), @(0)];
        [self.keyField.layer addAnimation:shake forKey:@"shake"];

        self.errorLabel.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
        self.errorLabel.text = t(@"invalidKey");

        [UIView animateWithDuration:0.3 animations:^{
            self.keyField.layer.borderColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.8].CGColor;
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3 animations:^{
                self.keyField.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
            }];
        }];
    }
}

- (void)abrirAppPrincipal {
    ViewController *vc = [[ViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Settings Panel

- (void)openSettings {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Overlay
    self.settingsOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.settingsOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    self.settingsOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeSettings)];
    [self.settingsOverlay addGestureRecognizer:closeTap];
    [self.view addSubview:self.settingsOverlay];

    // Panel
    CGFloat panelH = 420;
    self.settingsPanel = [[UIView alloc] initWithFrame:CGRectMake(0, h, w, panelH)];
    self.settingsPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.settingsPanel.layer.cornerRadius = 20;
    self.settingsPanel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.view addSubview:self.settingsPanel];

    // Title bar
    UILabel *settingsTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, w - 80, 30)];
    settingsTitle.text = t(@"settings");
    settingsTitle.font = [UIFont fontWithName:@"Menlo-Bold" size:17];
    settingsTitle.textColor = keyAcento();
    [self.settingsPanel addSubview:settingsTitle];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 50, 16, 30, 30);
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor grayColor];
    [closeBtn addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsPanel addSubview:closeBtn];

    CGFloat y = 60;
    CGFloat rowH = 52;

    // --- Text Color ---
    y = [self addColorRowWith:y label:t(@"textColor") key:kSettingsTextColor rowH:rowH];

    // --- Background Color ---
    y = [self addColorRowWith:y label:t(@"bgColor") key:kSettingsBgColor rowH:rowH];

    // --- Accent Color ---
    y = [self addColorRowWith:y label:t(@"accentColor") key:kSettingsAccentColor rowH:rowH];

    // --- Language ---
    y += 8;
    UILabel *langLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 20)];
    langLabel.text = t(@"language");
    langLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    langLabel.textColor = [UIColor lightGrayColor];
    [self.settingsPanel addSubview:langLabel];

    y += 26;
    NSString *currentLang = keyLang();
    UISegmentedControl *langSeg = [[UISegmentedControl alloc] initWithItems:@[@"Español", @"English"]];
    langSeg.frame = CGRectMake(20, y, w - 40, 36);
    langSeg.selectedSegmentIndex = [currentLang isEqualToString:@"en"] ? 1 : 0;
    langSeg.selectedSegmentTintColor = keyAcento();
    [langSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:12]} forState:UIControlStateSelected];
    [langSeg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor grayColor], NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:12]} forState:UIControlStateNormal];
    langSeg.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    [langSeg addTarget:self action:@selector(langChanged:) forControlEvents:UIControlEventValueChanged];
    [self.settingsPanel addSubview:langSeg];

    // Animate in
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:0 animations:^{
        CGRect f = self.settingsPanel.frame;
        f.origin.y = h - panelH;
        self.settingsPanel.frame = f;
    } completion:nil];
}

- (CGFloat)addColorRowWith:(CGFloat)y label:(NSString *)label key:(NSString *)key rowH:(CGFloat)rowH {
    CGFloat w = self.view.bounds.size.width;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 20)];
    lbl.text = label;
    lbl.font = [UIFont fontWithName:@"Menlo" size:13];
    lbl.textColor = [UIColor lightGrayColor];
    [self.settingsPanel addSubview:lbl];

    NSArray *colors = @[
        @{@"name": @"Verde",    @"color": [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0]},
        @{@"name": @"Azul",     @"color": [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0]},
        @{@"name": @"Morado",   @"color": [UIColor colorWithRed:0.7 green:0.3 blue:1.0 alpha:1.0]},
        @{@"name": @"Rojo",     @"color": [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0]},
        @{@"name": @"Naranja",  @"color": [UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:1.0]},
        @{@"name": @"Rosa",     @"color": [UIColor colorWithRed:1.0 green:0.4 blue:0.7 alpha:1.0]},
        @{@"name": @"Blanco",   @"color": [UIColor whiteColor]},
        @{@"name": @"Gris",     @"color": [UIColor grayColor]},
    ];

    // Scrollable color dots
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(20, y + 24, w - 40, 30)];
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.backgroundColor = [UIColor clearColor];
    [self.settingsPanel addSubview:scroll];

    CGFloat dotX = 0;
    for (int i = 0; i < (int)colors.count; i++) {
        NSDictionary *cd = colors[i];
        UIColor *c = cd[@"color"];
        UIButton *dot = [UIButton buttonWithType:UIButtonTypeSystem];
        dot.frame = CGRectMake(dotX, 0, 28, 28);
        dot.layer.cornerRadius = 14;
        dot.backgroundColor = c;
        dot.tag = i;
        dot.layer.borderWidth = 2;
        dot.layer.borderColor = [UIColor clearColor].CGColor;
        dot.clipsToBounds = YES;

        // Check if selected
        NSData *saved = [[NSUserDefaults standardUserDefaults] objectForKey:key];
        UIColor *savedColor = saved ? [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:saved error:nil] : nil;
        if (savedColor && [self color:savedColor isEqualTo:c]) {
            dot.layer.borderColor = [UIColor whiteColor].CGColor;
        }

        [dot addTarget:self action:@selector(colorDotTapped:) forControlEvents:UIControlEventTouchUpInside];
        dot.accessibilityHint = key;
        dot.accessibilityValue = cd[@"name"];
        [scroll addSubview:dot];
        dotX += 36;
    }
    scroll.contentSize = CGSizeMake(dotX, 30);

    return y + rowH;
}

- (BOOL)color:(UIColor *)c1 isEqualTo:(UIColor *)c2 {
    CGFloat r1, g1, b1, a1, r2, g2, b2, a2;
    [c1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [c2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return fabs(r1-r2) < 0.05 && fabs(g1-g2) < 0.05 && fabs(b1-b2) < 0.05;
}

- (void)colorDotTapped:(UIButton *)sender {
    NSString *key = sender.accessibilityHint;
    NSArray *colors = @[
        [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0],
        [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0],
        [UIColor colorWithRed:0.7 green:0.3 blue:1.0 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.4 blue:0.7 alpha:1.0],
        [UIColor whiteColor],
        [UIColor grayColor],
    ];
    if (sender.tag < (int)colors.count) {
        saveColor(key, colors[sender.tag]);
        [self rebuildUI];
        [self openSettings];
    }
}

- (void)langChanged:(UISegmentedControl *)seg {
    NSString *lang = seg.selectedSegmentIndex == 0 ? @"es" : @"en";
    [[NSUserDefaults standardUserDefaults] setObject:lang forKey:kSettingsLanguage];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self rebuildUI];
    [self openSettings];
}

- (void)closeSettings {
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.settingsPanel.frame;
        f.origin.y = self.view.bounds.size.height;
        self.settingsPanel.frame = f;
        self.settingsOverlay.alpha = 0;
    } completion:^(BOOL finished) {
        [self.settingsOverlay removeFromSuperview];
        [self.settingsPanel removeFromSuperview];
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self intentarAcceso];
    return YES;
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

@end
