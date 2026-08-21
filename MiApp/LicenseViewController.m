#import "LicenseViewController.h"
#import <QuartzCore/QuartzCore.h>

@interface LicenseViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *licenseField;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) CAGradientLayer *buttonGradient;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, assign) NSInteger selectedLanguage;
@property (nonatomic, assign) BOOL screenProtection;
@property (nonatomic, assign) NSInteger selectedBgColor;
@property (nonatomic, assign) NSInteger selectedTextColor;
@end

@implementation LicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.018 green:0.018 blue:0.022 alpha:1.0];
    [self loadSettings];
    [self setupUI];
}

#pragma mark - UI

- (void)setupUI {
    UIColor *white = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *muted = [UIColor colorWithWhite:0.50 alpha:1.0];
    UIColor *fieldBorder = [UIColor colorWithWhite:0.20 alpha:1.0];
    UIColor *fieldFill = [UIColor colorWithWhite:0.065 alpha:1.0];
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    
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
    
    UILabel *brand = [[UILabel alloc] init];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    brand.textAlignment = NSTextAlignmentCenter;
    brand.text = @"XITFORGE";
    brand.textColor = white;
    brand.font = [UIFont systemFontOfSize:31.0 weight:UIFontWeightBold];
    brand.adjustsFontSizeToFitWidth = YES;
    brand.minimumScaleFactor = 0.75;
    [self.view addSubview:brand];
    
    UIView *brandLine = [[UIView alloc] init];
    brandLine.translatesAutoresizingMaskIntoConstraints = NO;
    brandLine.backgroundColor = red;
    brandLine.layer.cornerRadius = 1.0;
    brandLine.layer.shadowColor = red.CGColor;
    brandLine.layer.shadowOpacity = 0.30;
    brandLine.layer.shadowRadius = 5.0;
    brandLine.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:brandLine];
    
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
    
    self.continueButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueButton.layer.cornerRadius = 14.0;
    self.continueButton.layer.masksToBounds = YES;
    
    [self.continueButton setAttributedTitle:[[NSAttributedString alloc] initWithString:@"CONTINUAR"
        attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSKernAttributeName: @1.5
        }] forState:UIControlStateNormal];
    
    [self.continueButton addTarget:self action:@selector(activateLicense) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueButton];
    
    self.buttonGradient = [CAGradientLayer layer];
    self.buttonGradient.colors = @[
        (id)[UIColor colorWithRed:0.98 green:0.12 blue:0.14 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.72 green:0.03 blue:0.05 alpha:1.0].CGColor
    ];
    self.buttonGradient.startPoint = CGPointMake(0.0, 0.5);
    self.buttonGradient.endPoint = CGPointMake(1.0, 0.5);
    self.buttonGradient.cornerRadius = 14.0;
    [self.continueButton.layer insertSublayer:self.buttonGradient atIndex:0];
    
    UIView *buttonShadow = [[UIView alloc] init];
    buttonShadow.translatesAutoresizingMaskIntoConstraints = NO;
    buttonShadow.backgroundColor = [red colorWithAlphaComponent:0.16];
    buttonShadow.layer.cornerRadius = 28.0;
    buttonShadow.layer.shadowColor = red.CGColor;
    buttonShadow.layer.shadowOpacity = 0.35;
    buttonShadow.layer.shadowRadius = 20.0;
    buttonShadow.layer.shadowOffset = CGSizeZero;
    buttonShadow.userInteractionEnabled = NO;
    [self.view insertSubview:buttonShadow belowSubview:self.continueButton];
    
    // Botón de configuración
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.settingsButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    [self.settingsButton setTintColor:white];
    self.settingsButton.contentMode = UIViewContentModeScaleAspectFit;
    [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.settingsButton];
    
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
        
        [self.licenseField.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.licenseField.topAnchor constraintEqualToAnchor:brandLine.bottomAnchor constant:86],
        [self.licenseField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:38],
        [self.licenseField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-38],
        [self.licenseField.heightAnchor constraintEqualToConstant:56],
        
        [buttonShadow.centerXAnchor constraintEqualToAnchor:self.continueButton.centerXAnchor],
        [buttonShadow.centerYAnchor constraintEqualToAnchor:self.continueButton.centerYAnchor constant:6],
        [buttonShadow.widthAnchor constraintEqualToAnchor:self.continueButton.widthAnchor constant:-8],
        [buttonShadow.heightAnchor constraintEqualToAnchor:self.continueButton.heightAnchor constant:-8],
        
        [self.continueButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.continueButton.topAnchor constraintEqualToAnchor:self.licenseField.bottomAnchor constant:18],
        [self.continueButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:38],
        [self.continueButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-38],
        [self.continueButton.heightAnchor constraintEqualToConstant:54],
        
        [self.settingsButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.settingsButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.settingsButton.widthAnchor constraintEqualToConstant:28],
        [self.settingsButton.heightAnchor constraintEqualToConstant:28],
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

#pragma mark - Settings

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.selectedLanguage = [defaults integerForKey:@"selectedLanguage"];
    self.screenProtection = [defaults boolForKey:@"screenProtection"];
    self.selectedBgColor = [defaults integerForKey:@"selectedBgColor"];
    self.selectedTextColor = [defaults integerForKey:@"selectedTextColor"];
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.selectedLanguage forKey:@"selectedLanguage"];
    [defaults setBool:self.screenProtection forKey:@"screenProtection"];
    [defaults setInteger:self.selectedBgColor forKey:@"selectedBgColor"];
    [defaults setInteger:self.selectedTextColor forKey:@"selectedTextColor"];
    [defaults synchronize];
}

- (void)showSettings {
    UIAlertController *settingsAlert = [UIAlertController alertControllerWithTitle:@"Configuración" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *langES = [UIAlertAction actionWithTitle:@"🇪🇸 Español" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedLanguage = 0;
        [self saveSettings];
    }];
    UIAlertAction *langEN = [UIAlertAction actionWithTitle:@"🇺 English" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedLanguage = 1;
        [self saveSettings];
    }];
    UIAlertAction *langPT = [UIAlertAction actionWithTitle:@"🇷 Português" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedLanguage = 2;
        [self saveSettings];
    }];
    
    NSString *protText = self.screenProtection ? @"🛡️ Desactivar Protección" : @"🛡️ Activar Protección";
    UIAlertAction *protection = [UIAlertAction actionWithTitle:protText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.screenProtection = !self.screenProtection;
        [self saveSettings];
    }];
    
    UIAlertAction *bgRed = [UIAlertAction actionWithTitle:@"🔴 Fondo Rojo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedBgColor = 0;
        [self saveSettings];
        [self applyTheme];
    }];
    UIAlertAction *bgGray = [UIAlertAction actionWithTitle:@" Fondo Gris" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedBgColor = 1;
        [self saveSettings];
        [self applyTheme];
    }];
    UIAlertAction *bgBlue = [UIAlertAction actionWithTitle:@" Fondo Azul" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedBgColor = 2;
        [self saveSettings];
        [self applyTheme];
    }];
    UIAlertAction *bgPurple = [UIAlertAction actionWithTitle:@"🟣 Fondo Morado" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedBgColor = 3;
        [self saveSettings];
        [self applyTheme];
    }];
    
    UIAlertAction *textWhite = [UIAlertAction actionWithTitle:@"⚪ Texto Blanco" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedTextColor = 0;
        [self saveSettings];
        [self applyTheme];
    }];
    UIAlertAction *textGray = [UIAlertAction actionWithTitle:@"🔘 Texto Gris" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedTextColor = 1;
        [self saveSettings];
        [self applyTheme];
    }];
    UIAlertAction *textRed = [UIAlertAction actionWithTitle:@"🔴 Texto Rojo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedTextColor = 2;
        [self saveSettings];
        [self applyTheme];
    }];
    UIAlertAction *textGreen = [UIAlertAction actionWithTitle:@"🟢 Texto Verde" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedTextColor = 3;
        [self saveSettings];
        [self applyTheme];
    }];
    
    [settingsAlert addAction:langES];
    [settingsAlert addAction:langEN];
    [settingsAlert addAction:langPT];
    [settingsAlert addAction:protection];
    [settingsAlert addAction:bgRed];
    [settingsAlert addAction:bgGray];
    [settingsAlert addAction:bgBlue];
    [settingsAlert addAction:bgPurple];
    [settingsAlert addAction:textWhite];
    [settingsAlert addAction:textGray];
    [settingsAlert addAction:textRed];
    [settingsAlert addAction:textGreen];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil];
    [settingsAlert addAction:cancel];
    
    [self presentViewController:settingsAlert animated:YES completion:nil];
}

- (void)applyTheme {
    NSArray *bgColors = @[
        [UIColor colorWithRed:0.018 green:0.018 blue:0.022 alpha:1.0],
        [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0],
        [UIColor colorWithRed:0.02 green:0.05 blue:0.15 alpha:1.0],
        [UIColor colorWithRed:0.08 green:0.02 blue:0.12 alpha:1.0]
    ];
    
    NSArray *textColors = @[
        [UIColor colorWithWhite:0.96 alpha:1.0],
        [UIColor colorWithWhite:0.60 alpha:1.0],
        [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0],
        [UIColor colorWithRed:0.20 green:0.90 blue:0.30 alpha:1.0]
    ];
    
    UIColor *bgColor = bgColors[self.selectedBgColor];
    UIColor *textColor = textColors[self.selectedTextColor];
    
    [UIView animateWithDuration:0.3 animations:^{
        self.view.backgroundColor = bgColor;
        self.licenseField.textColor = textColor;
    }];
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
