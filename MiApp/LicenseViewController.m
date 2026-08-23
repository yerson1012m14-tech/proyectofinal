#import "LicenseViewController.h"
#import "LicenseValidator.h"
#import "SettingsViewController.h"
#import "Translations.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

@interface LicenseViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *licenseField;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) CAGradientLayer *buttonGradient;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIView *engineStatusBadge;
@property (nonatomic, strong) UILabel *engineStatusLabel;
@property (nonatomic, assign) NSInteger selectedLanguage;
@property (nonatomic, assign) BOOL screenProtection;
@end

/*
 * Comprobación no destructiva de compatibilidad del motor.
 *
 * Solo se marca COMPATIBLE cuando:
 *  - están disponibles las funciones esenciales del motor;
 *  - MCMFilzaStart puede inicializarse;
 *  - el motor devuelve un VirtualRoot real, existente, directorio y legible.
 *
 * No se llama TweakInit.
 * No se habilita MCMFilzaSetUnrestrictedFilesystem.
 * No se crea, modifica ni elimina ningún archivo.
 */
static BOOL XITForgeEngineIsCompatible(void) {

    void (*start)(void) =
        (void (*)(void))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaStart"
        );

    NSString *(*dataPath)(NSString *, NSString **) =
        (NSString *(*)(NSString *, NSString **))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaDataContainerPath"
        );

    NSString *(*virtualRoot)(void) =
        (NSString *(*)(void))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaVirtualRoot"
        );

    if (!start || !dataPath || !virtualRoot) {
        return NO;
    }

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        start();
    });

    NSString *root =
        virtualRoot();

    if (
        ![root isKindOfClass:[NSString class]] ||
        root.length == 0
    ) {
        return NO;
    }

    NSString *standardRoot =
        [root stringByStandardizingPath];

    NSFileManager *fm =
        [NSFileManager defaultManager];

    BOOL isDirectory =
        NO;

    if (
        ![fm fileExistsAtPath:standardRoot
                  isDirectory:&isDirectory] ||
        !isDirectory
    ) {
        return NO;
    }

    if (![fm isReadableFileAtPath:standardRoot]) {
        return NO;
    }

    return YES;
}

@implementation LicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadSettings];
    [Translations setLanguage:self.selectedLanguage];
    [self setupUI];
}

#pragma mark - UI

- (void)setupUI {
    UIColor *white = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *fieldBorder = [UIColor colorWithWhite:0.20 alpha:1.0];
    UIColor *fieldFill = [UIColor colorWithWhite:0.065 alpha:1.0];
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];

    self.view.backgroundColor = [UIColor blackColor];

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
    self.licenseField.font = [UIFont monospacedSystemFontOfSize:17.0
                                                          weight:UIFontWeightMedium];
    self.licenseField.textAlignment = NSTextAlignmentCenter;
    self.licenseField.autocapitalizationType =
        UITextAutocapitalizationTypeAllCharacters;
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

    self.licenseField.attributedPlaceholder =
        [[NSAttributedString alloc]
            initWithString:@"XXXX-XXXX-XXXX-XXXX"
                attributes:@{
                    NSForegroundColorAttributeName:
                        [UIColor colorWithWhite:0.30 alpha:1.0],
                    NSFontAttributeName:
                        [UIFont monospacedSystemFontOfSize:17.0
                                                     weight:UIFontWeightMedium]
                }];

    [self.view addSubview:self.licenseField];

    self.continueButton =
        [UIButton buttonWithType:UIButtonTypeCustom];

    self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueButton.layer.cornerRadius = 14.0;
    self.continueButton.layer.masksToBounds = YES;

    [self updateContinueButtonText];

    [self.continueButton
        addTarget:self
           action:@selector(activateLicense)
 forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:self.continueButton];

    self.buttonGradient = [CAGradientLayer layer];

    self.buttonGradient.colors = @[
        (id)[UIColor colorWithRed:0.98
                            green:0.12
                             blue:0.14
                            alpha:1.0].CGColor,

        (id)[UIColor colorWithRed:0.72
                            green:0.03
                             blue:0.05
                            alpha:1.0].CGColor
    ];

    self.buttonGradient.startPoint = CGPointMake(0.0, 0.5);
    self.buttonGradient.endPoint = CGPointMake(1.0, 0.5);
    self.buttonGradient.cornerRadius = 14.0;

    [self.continueButton.layer
        insertSublayer:self.buttonGradient
               atIndex:0];

    UIView *buttonShadow = [[UIView alloc] init];
    buttonShadow.translatesAutoresizingMaskIntoConstraints = NO;
    buttonShadow.backgroundColor =
        [red colorWithAlphaComponent:0.16];
    buttonShadow.layer.cornerRadius = 28.0;
    buttonShadow.layer.shadowColor = red.CGColor;
    buttonShadow.layer.shadowOpacity = 0.35;
    buttonShadow.layer.shadowRadius = 20.0;
    buttonShadow.layer.shadowOffset = CGSizeZero;
    buttonShadow.userInteractionEnabled = NO;

    [self.view insertSubview:buttonShadow
             belowSubview:self.continueButton];

    self.settingsButton =
        [UIButton buttonWithType:UIButtonTypeCustom];

    self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;

    [self.settingsButton
        setImage:[UIImage systemImageNamed:@"gearshape.fill"]
        forState:UIControlStateNormal];

    [self.settingsButton setTintColor:white];

    self.settingsButton.contentMode =
        UIViewContentModeScaleAspectFit;

    [self.settingsButton
        addTarget:self
           action:@selector(showSettings)
 forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:self.settingsButton];

    /*
     * Estado del motor: esquina inferior izquierda de la pantalla de key.
     * Empieza como "VERIFICANDO..." y después solo muestra COMPATIBLE
     * cuando la comprobación real del motor pasa.
     */
    self.engineStatusBadge =
        [[UIView alloc] init];

    self.engineStatusBadge.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.engineStatusBadge.backgroundColor =
        [UIColor colorWithWhite:0.055 alpha:0.96];

    self.engineStatusBadge.layer.cornerRadius =
        12.0;

    self.engineStatusBadge.layer.borderWidth =
        1.0;

    self.engineStatusBadge.layer.borderColor =
        [UIColor colorWithWhite:0.18 alpha:1.0].CGColor;

    [self.view addSubview:self.engineStatusBadge];


    self.engineStatusLabel =
        [[UILabel alloc] init];

    self.engineStatusLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.engineStatusLabel.text =
        @"MOTOR · VERIFICANDO...";

    self.engineStatusLabel.textAlignment =
        NSTextAlignmentCenter;

    self.engineStatusLabel.textColor =
        [UIColor colorWithWhite:0.52 alpha:1.0];

    self.engineStatusLabel.font =
        [UIFont systemFontOfSize:10.5
                          weight:UIFontWeightBold];

    self.engineStatusLabel.adjustsFontSizeToFitWidth =
        YES;

    self.engineStatusLabel.minimumScaleFactor =
        0.75;

    [self.engineStatusBadge
        addSubview:self.engineStatusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [topGlow.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [topGlow.topAnchor
            constraintEqualToAnchor:self.view.topAnchor
            constant:-220],

        [topGlow.widthAnchor
            constraintEqualToConstant:340],

        [topGlow.heightAnchor
            constraintEqualToConstant:340],

        [bottomGlow.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [bottomGlow.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor
            constant:170],

        [bottomGlow.widthAnchor
            constraintEqualToConstant:300],

        [bottomGlow.heightAnchor
            constraintEqualToConstant:300],

        [brand.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [brand.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
            constant:108],

        [brand.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
            constant:30],

        [brand.trailingAnchor
            constraintLessThanOrEqualToAnchor:self.view.trailingAnchor
            constant:-30],

        [brand.heightAnchor
            constraintEqualToConstant:38],

        [brandLine.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [brandLine.topAnchor
            constraintEqualToAnchor:brand.bottomAnchor
            constant:12],

        [brandLine.widthAnchor
            constraintEqualToConstant:44],

        [brandLine.heightAnchor
            constraintEqualToConstant:2],

        [self.licenseField.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [self.licenseField.topAnchor
            constraintEqualToAnchor:brandLine.bottomAnchor
            constant:86],

        [self.licenseField.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor
            constant:38],

        [self.licenseField.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor
            constant:-38],

        [self.licenseField.heightAnchor
            constraintEqualToConstant:56],

        [buttonShadow.centerXAnchor
            constraintEqualToAnchor:self.continueButton.centerXAnchor],

        [buttonShadow.centerYAnchor
            constraintEqualToAnchor:self.continueButton.centerYAnchor
            constant:6],

        [buttonShadow.widthAnchor
            constraintEqualToAnchor:self.continueButton.widthAnchor
            constant:-8],

        [buttonShadow.heightAnchor
            constraintEqualToAnchor:self.continueButton.heightAnchor
            constant:-8],

        [self.continueButton.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [self.continueButton.topAnchor
            constraintEqualToAnchor:self.licenseField.bottomAnchor
            constant:18],

        [self.continueButton.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor
            constant:38],

        [self.continueButton.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor
            constant:-38],

        [self.continueButton.heightAnchor
            constraintEqualToConstant:54],

        [self.settingsButton.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
            constant:16],

        [self.settingsButton.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor
            constant:-20],

        [self.settingsButton.widthAnchor
            constraintEqualToConstant:28],

        [self.settingsButton.heightAnchor
            constraintEqualToConstant:28],


        [self.engineStatusBadge.leadingAnchor
            constraintEqualToAnchor:
                self.view.safeAreaLayoutGuide.leadingAnchor
                constant:16],

        [self.engineStatusBadge.bottomAnchor
            constraintEqualToAnchor:
                self.view.safeAreaLayoutGuide.bottomAnchor
                constant:-14],

        [self.engineStatusBadge.heightAnchor
            constraintEqualToConstant:30],

        [self.engineStatusBadge.widthAnchor
            constraintEqualToConstant:164],


        [self.engineStatusLabel.leadingAnchor
            constraintEqualToAnchor:
                self.engineStatusBadge.leadingAnchor
                constant:10],

        [self.engineStatusLabel.trailingAnchor
            constraintEqualToAnchor:
                self.engineStatusBadge.trailingAnchor
                constant:-10],

        [self.engineStatusLabel.centerYAnchor
            constraintEqualToAnchor:
                self.engineStatusBadge.centerYAnchor]
    ]];

    [self updateButtonGradientFrame];
    [self updateEngineCompatibilityStatus];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateButtonGradientFrame];
}

- (void)updateButtonGradientFrame {
    self.buttonGradient.frame = self.continueButton.bounds;
    self.buttonGradient.cornerRadius =
        self.continueButton.layer.cornerRadius;
}

- (void)updateEngineCompatibilityStatus {

    BOOL compatible =
        XITForgeEngineIsCompatible();

    UIColor *green =
        [UIColor colorWithRed:0.20
                        green:0.86
                         blue:0.42
                        alpha:1.0];

    UIColor *red =
        [UIColor colorWithRed:0.96
                        green:0.16
                         blue:0.18
                        alpha:1.0];

    if (compatible) {

        self.engineStatusLabel.text =
            @"MOTOR · COMPATIBLE";

        self.engineStatusLabel.textColor =
            green;

        self.engineStatusBadge.layer.borderColor =
            [green colorWithAlphaComponent:0.34].CGColor;

        self.engineStatusBadge.backgroundColor =
            [green colorWithAlphaComponent:0.065];

    } else {

        self.engineStatusLabel.text =
            @"MOTOR · NO COMPATIBLE";

        self.engineStatusLabel.textColor =
            red;

        self.engineStatusBadge.layer.borderColor =
            [red colorWithAlphaComponent:0.30].CGColor;

        self.engineStatusBadge.backgroundColor =
            [red colorWithAlphaComponent:0.055];
    }
}


- (void)updateContinueButtonText {
    [self.continueButton
        setAttributedTitle:
        [[NSAttributedString alloc]
            initWithString:[Translations tr:@"continue"]
                attributes:@{
                    NSFontAttributeName:
                        [UIFont systemFontOfSize:15.0
                                          weight:UIFontWeightBold],

                    NSForegroundColorAttributeName:
                        [UIColor whiteColor],

                    NSKernAttributeName:
                        @1.5
                }]
        forState:UIControlStateNormal];
}

#pragma mark - Settings

- (void)loadSettings {
    NSUserDefaults *d =
        [NSUserDefaults standardUserDefaults];

    self.selectedLanguage =
        [d integerForKey:@"selectedLanguage"];

    self.screenProtection =
        [d boolForKey:@"screenProtection"];
}

- (void)saveSettings {
    NSUserDefaults *d =
        [NSUserDefaults standardUserDefaults];

    [d setInteger:self.selectedLanguage
           forKey:@"selectedLanguage"];

    [d setBool:self.screenProtection
        forKey:@"screenProtection"];

    [d synchronize];
}

- (void)showSettings {

    SettingsViewController *svc =
        [[SettingsViewController alloc] init];

    svc.selectedLanguage =
        self.selectedLanguage;

    svc.screenProtection =
        self.screenProtection;

    __weak typeof(self) weakSelf = self;
    __weak typeof(svc) weakSvc = svc;

    svc.onSettingsChanged = ^{

        if (!weakSelf || !weakSvc) {
            return;
        }

        weakSelf.selectedLanguage =
            weakSvc.selectedLanguage;

        weakSelf.screenProtection =
            weakSvc.screenProtection;

        [weakSelf saveSettings];

        [Translations
            setLanguage:weakSelf.selectedLanguage];

        [weakSelf
            updateContinueButtonText];
    };

    svc.modalPresentationStyle =
        UIModalPresentationPageSheet;

    if (@available(iOS 15.0, *)) {

        UISheetPresentationController *sheet =
            svc.sheetPresentationController;

        sheet.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];

        sheet.preferredCornerRadius = 20;
    }

    [self presentViewController:svc
                       animated:YES
                     completion:nil];
}

#pragma mark - License formatting

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {

    NSString *currentText =
        textField.text ?: @"";

    NSString *newText =
        [currentText
            stringByReplacingCharactersInRange:range
                                    withString:string];

    NSCharacterSet *allowed =
        [NSCharacterSet alphanumericCharacterSet];

    NSMutableString *clean =
        [NSMutableString stringWithCapacity:newText.length];

    for (NSUInteger i = 0;
         i < newText.length;
         i++) {

        unichar c =
            [newText characterAtIndex:i];

        if ([allowed characterIsMember:c]) {
            [clean appendFormat:@"%C", c];
        }
    }

    NSString *uppercase =
        [clean uppercaseString];

    if (uppercase.length > 16) {
        uppercase =
            [uppercase substringToIndex:16];
    }

    NSMutableString *formatted =
        [NSMutableString string];

    for (NSUInteger i = 0;
         i < uppercase.length;
         i++) {

        if (i > 0 && i % 4 == 0) {
            [formatted appendString:@"-"];
        }

        [formatted
            appendFormat:@"%C",
             [uppercase characterAtIndex:i]];
    }

    textField.text = formatted;

    return NO;
}

#pragma mark - License action

- (void)activateLicense {

    [self.view endEditing:YES];

    NSString *input =
        [[[self.licenseField.text
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            uppercaseString]
            copy];

    if (input.length == 0) {

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:
                    [Translations tr:@"incorrect"]
                message:nil
                preferredStyle:
                    UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [self presentViewController:alert
                           animated:YES
                         completion:nil];

        return;
    }

    self.continueButton.enabled = NO;
    self.licenseField.userInteractionEnabled = NO;

    __weak typeof(self) weakSelf = self;

    [LicenseValidator
        validateKey:input
        completion:
        ^(BOOL valid,
          NSString * _Nullable reason,
          NSString * _Nullable expiresAt) {

        __strong typeof(weakSelf) strongSelf = weakSelf;

        if (!strongSelf) {
            return;
        }

        strongSelf.continueButton.enabled = YES;
        strongSelf.licenseField.userInteractionEnabled = YES;

        if (valid) {

            NSUserDefaults *defaults =
                [NSUserDefaults standardUserDefaults];

            [defaults setObject:input
                         forKey:@"MiFilzaLicenseKey"];

            if (expiresAt.length > 0) {

                [defaults setObject:expiresAt
                             forKey:@"MiFilzaLicenseExpiresAt"];

            } else {

                [defaults removeObjectForKey:
                    @"MiFilzaLicenseExpiresAt"];
            }

            [defaults synchronize];

            if (strongSelf.onLicenseValidated) {
                strongSelf.onLicenseValidated();
            }

            return;
        }

        NSString *message =
            @"Licencia incorrecta.";

        if ([reason isEqualToString:@"expired"]) {
            message =
                @"La licencia ha expirado.";
        }
        else if ([reason isEqualToString:@"revoked"]) {
            message =
                @"La licencia ha sido revocada.";
        }
        else if ([reason isEqualToString:@"device_limit"]) {
            message =
                @"Se alcanzó el límite de dispositivos.";
        }
        else if ([reason isEqualToString:@"network_error"]) {
            message =
                @"No se pudo conectar con el servidor.";
        }
        else if ([reason isEqualToString:@"not_found"]) {
            message =
                @"La licencia no existe.";
        }
        else if ([reason isEqualToString:@"invalid_format"]) {
            message =
                @"El formato de la licencia no es válido.";
        }

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:
                    [Translations tr:@"incorrect"]
                message:message
                preferredStyle:
                    UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [strongSelf presentViewController:alert
                                 animated:YES
                               completion:nil];
    }];
}

#pragma mark - Keyboard

- (BOOL)textFieldShouldReturn:(UITextField *)textField {

    [textField resignFirstResponder];

    [self activateLicense];

    return YES;
}

@end
