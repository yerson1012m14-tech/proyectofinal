#import "LicenseViewController.h"
#import <QuartzCore/QuartzCore.h>

@interface LicenseViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *licenseField;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) CAGradientLayer *buttonGradient;
@property (nonatomic, strong) UIView *buttonShadow;
@property (nonatomic, assign) BOOL hasAnimated;
@end

@implementation LicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.018 green:0.018 blue:0.022 alpha:1.0];
    self.hasAnimated = NO;
    [self setupUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.hasAnimated) {
        self.hasAnimated = YES;
        [self animateEntrance];
    }
}

#pragma mark - UI Setup

- (void)setupUI {
    UIColor *white = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *muted = [UIColor colorWithWhite:0.50 alpha:1.0];
    UIColor *fieldBorder = [UIColor colorWithWhite:0.20 alpha:1.0];
    UIColor *fieldFill = [UIColor colorWithWhite:0.065 alpha:1.0];
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    
    // ===== GLOWS DE FONDO =====
    UIView *topGlow = [[UIView alloc] init];
    topGlow.translatesAutoresizingMaskIntoConstraints = NO;
    topGlow.backgroundColor = [red colorWithAlphaComponent:0.055];
    topGlow.layer.cornerRadius = 170.0;
    topGlow.layer.masksToBounds = YES;
    topGlow.userInteractionEnabled = NO;
    [self.view addSubview:topGlow];
    
    UIView *bottomGlow = [[UIView alloc] init];
    bottomGlow.translatesAutoresizingMaskIntoConstraints = NO;
    bottomGlow.backgroundColor = [red colorWithAlphaComponent:0.045];
    bottomGlow.layer.cornerRadius = 150.0;
    bottomGlow.layer.masksToBounds = YES;
    bottomGlow.userInteractionEnabled = NO;
    [self.view addSubview:bottomGlow];
    
    // ===== LOGO =====
    UILabel *brand = [[UILabel alloc] init];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    brand.textAlignment = NSTextAlignmentCenter;
    brand.text = @"XITFORGE";
    brand.textColor = white;
    brand.font = [UIFont systemFontOfSize:31.0 weight:UIFontWeightBold];
    brand.adjustsFontSizeToFitWidth = YES;
    brand.minimumScaleFactor = 0.75;
    [self.view addSubview:brand];
    
    // Línea roja
    UIView *brandLine = [[UIView alloc] init];
    brandLine.translatesAutoresizingMaskIntoConstraints = NO;
    brandLine.backgroundColor = red;
    brandLine.layer.cornerRadius = 1.0;
    brandLine.layer.shadowColor = red.CGColor;
    brandLine.layer.shadowOpacity = 0.30;
    brandLine.layer.shadowRadius = 5.0;
    brandLine.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:brandLine];
    
    // Subtítulo con letterSpacing (iOS 17+)
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"LICENSE ACTIVATION";
    subtitle.textColor = muted;
    subtitle.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    subtitle.letterSpacing = 3.0;
    subtitle.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:subtitle];
    
    // ===== CAMPO DE TEXTO =====
    self.licenseField = [[UITextField alloc] init];
    self.licenseField.translatesAutoresizingMaskIntoConstraints = NO;
    self.licenseField.backgroundColor = fieldFill;
    self.licenseField.textColor = white;
    self.licenseField.font = [UIFont monospacedSystemFontOfSize:17.0 weight:UIFontWeightMedium];
    self.licenseField.textAlignment = NSTextAlignmentCenter;
    self.licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.licenseField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.licenseField.smartQuotesType = UITextSmartQuotesTypeNo;
    self.licenseField.smartDashesType = UITextSmartDashesTypeNo;
    self.licenseField.keyboardType = UIKeyboardTypeASCIICapable;
    self.licenseField.returnKeyType = UIReturnKeyDone;
    self.licenseField.delegate = self;
    self.licenseField.layer.cornerRadius = 14.0;
    self.licenseField.layer.borderWidth = 1.0;
    self.licenseField.layer.borderColor = fieldBorder.CGColor;
    self.licenseField.layer.shadowColor = [UIColor blackColor].CGColor;
    self.licenseField.layer.shadowOpacity = 0.25;
    self.licenseField.layer.shadowRadius = 16.0;
    self.licenseField.layer.shadowOffset = CGSizeMake(0, 8);
    
    self.licenseField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"XXXX-XXXX-XXXX-XXXX"
        attributes:@{
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.30 alpha:1.0],
            NSFontAttributeName: [UIFont monospacedSystemFontOfSize:17.0 weight:UIFontWeightMedium]
        }];
    [self.view addSubview:self.licenseField];
    
    // ===== BOTÓN =====
    self.buttonShadow = [[UIView alloc] init];
    self.buttonShadow.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttonShadow.backgroundColor = [red colorWithAlphaComponent:0.16];
    self.buttonShadow.layer.cornerRadius = 28.0;
    self.buttonShadow.layer.shadowColor = red.CGColor;
    self.buttonShadow.layer.shadowOpacity = 0.35;
    self.buttonShadow.layer.shadowRadius = 20.0;
    self.buttonShadow.layer.shadowOffset = CGSizeZero;
    self.buttonShadow.userInteractionEnabled = NO;
    [self.view addSubview:self.buttonShadow];
    
    self.continueButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueButton.layer.cornerRadius = 14.0;
    self.continueButton.layer.masksToBounds = YES;
    [self.continueButton setTitle:@"CONTINUAR" forState:UIControlStateNormal];
    [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.continueButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    self.continueButton.letterSpacing = 1.5;
    [self.continueButton addTarget:self action:@selector(activateLicense) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueButton];
    
    // Gradiente del botón
    self.buttonGradient = [CAGradientLayer layer];
    self.buttonGradient.colors = @[
        (id)[UIColor colorWithRed:0.98 green:0.12 blue:0.14 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.72 green:0.03 blue:0.05 alpha:1.0].CGColor
    ];
    self.buttonGradient.startPoint = CGPointMake(0.0, 0.5);
    self.buttonGradient.endPoint = CGPointMake(1.0, 0.5);
    self.buttonGradient.cornerRadius = 14.0;
    [self.continueButton.layer insertSublayer:self.buttonGradient atIndex:0];
    
    // ===== CONSTRAINTS =====
    [NSLayoutConstraint activateConstraints:@[
        [topGlow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [topGlow.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:-220],
        [topGlow.widthAnchor constraintEqualToConstant:340],
        [topGlow.heightAnchor constraintEqualToConstant:340],
        
        [bottomGlow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [bottomGlow.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:170],
        [bottomGlow.widthAnchor constraintEqualToConstant:300],
        [bottomGlow.heightAnchor constraintEqualToConstant:300],
        
        [brand.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [brand.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:108],
        [brand.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:30],
        [brand.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-30],
        [brand.heightAnchor constraintEqualToConstant:38],
        
        [brandLine.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [brandLine.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:12],
        [brandLine.widthAnchor constraintEqualToConstant:44],
        [brandLine.heightAnchor constraintEqualToConstant:2],
        
        [subtitle.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:brandLine.bottomAnchor constant:14],
        [subtitle.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:30],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-30],
        
        [self.licenseField.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.licenseField.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:86],
        [self.licenseField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:38],
        [self.licenseField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-38],
        [self.licenseField.heightAnchor constraintEqualToConstant:56],
        
        [self.buttonShadow.centerXAnchor constraintEqualToAnchor:self.continueButton.centerXAnchor],
        [self.buttonShadow.centerYAnchor constraintEqualToAnchor:self.continueButton.centerYAnchor constant:6],
        [self.buttonShadow.widthAnchor constraintEqualToAnchor:self.continueButton.widthAnchor constant:-8],
        [self.buttonShadow.heightAnchor constraintEqualToAnchor:self.continueButton.heightAnchor constant:-8],
        
        [self.continueButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.continueButton.topAnchor constraintEqualToAnchor:self.licenseField.bottomAnchor constant:18],
        [self.continueButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:38],
        [self.continueButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-38],
        [self.continueButton.heightAnchor constraintEqualToConstant:54],
    ]];
    
    [self updateButtonGradientFrame];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateButtonGradientFrame];
}

- (void)updateButtonGradientFrame {
    self.buttonGradient.frame = self.continueButton.bounds;
    self.buttonGradient.cornerRadius = self.continueButton.layer.cornerRadius;
}

#pragma mark - Animaciones

- (void)animateEntrance {
    self.brand.alpha = 0;
    self.licenseField.alpha = 0;
    self.continueButton.alpha = 0;
    self.buttonShadow.alpha = 0;
    
    [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        self.brand.alpha = 1;
    } completion:nil];
    
    [UIView animateWithDuration:0.6 delay:0.3 usingSpringWithDamping:0.75 initialSpringVelocity:0.3 options:0 animations:^{
        self.licenseField.alpha = 1;
    } completion:nil];
    
    [UIView animateWithDuration:0.6 delay:0.5 usingSpringWithDamping:0.7 initialSpringVelocity:0.4 options:0 animations:^{
        self.continueButton.alpha = 1;
        self.buttonShadow.alpha = 1;
    } completion:nil];
}

#pragma mark - License formatting

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *currentText = textField.text ?: @"";
    NSString *newText = [currentText stringByReplacingCharactersInRange:range withString:string];
    
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *clean = [NSMutableString stringWithCapacity:newText.length];
    for (NSUInteger i = 0; i < newText.length; i++) {
        unichar c = [newText characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [clean appendFormat:@"%C", c];
        }
    }
    
    NSString *uppercase = [clean uppercaseString];
    if (uppercase.length > 16) {
        uppercase = [uppercase substringToIndex:16];
    }
    
    NSMutableString *formatted = [NSMutableString string];
    for (NSUInteger i = 0; i < uppercase.length; i++) {
        if (i > 0 && i % 4 == 0) {
            [formatted appendString:@"-"];
        }
        [formatted appendFormat:@"%C", [uppercase characterAtIndex:i]];
    }
    
    textField.text = formatted;
    return NO;
}

#pragma mark - License action

- (void)activateLicense {
    [self.view endEditing:YES];
    NSString *input = [self.licenseField.text uppercaseString];
    
    if ([self validarFormatoLicencia:input]) {
        [[NSUserDefaults standardUserDefaults] setObject:input forKey:@"MiFilzaLicenseKey"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        if (self.onLicenseValidated) {
            self.onLicenseValidated();
        }
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clave no válida"
            message:@"Ingresa una clave con el formato XXXX-XXXX-XXXX-XXXX."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reintentar" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (BOOL)validarFormatoLicencia:(NSString *)licencia {
    NSString *regex = @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";
    NSPredicate *predicado = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
    return [predicado evaluateWithObject:licencia];
}

#pragma mark - Keyboard

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self activateLicense];
    return YES;
}

@end
