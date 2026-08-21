#import "LicenseViewController.h"
#import <QuartzCore/QuartzCore.h>

@interface LicenseViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *licenseField;

@end

@implementation LicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.015 green:0.015 blue:0.02 alpha:1.0];
    [self setupUI];
}

#pragma mark - UI

- (void)setupUI {
    UIColor *redColor = [UIColor colorWithRed:0.95 green:0.04 blue:0.08 alpha:1.0];
    UIColor *softWhite = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *mutedWhite = [UIColor colorWithWhite:0.62 alpha:1.0];
    UIColor *fieldFill = [UIColor colorWithRed:0.035 green:0.035 blue:0.045 alpha:0.96];

    // Fondo con degradado muy sutil.
    CAGradientLayer *backgroundGradient = [CAGradientLayer layer];
    backgroundGradient.frame = self.view.bounds;
    backgroundGradient.colors = @[
        (__bridge id)[UIColor colorWithRed:0.012 green:0.012 blue:0.016 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithRed:0.025 green:0.012 blue:0.016 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithRed:0.008 green:0.008 blue:0.012 alpha:1.0].CGColor
    ];
    backgroundGradient.startPoint = CGPointMake(0.5, 0.0);
    backgroundGradient.endPoint = CGPointMake(0.5, 1.0);
    [self.view.layer insertSublayer:backgroundGradient atIndex:0];

    // Contenedor central para mantener todo perfectamente alineado.
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentFill;
    contentStack.distribution = UIStackViewDistributionFill;
    contentStack.spacing = 0;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contentStack];

    // MARK: Logo
    UIStackView *logoStack = [[UIStackView alloc] init];
    logoStack.axis = UILayoutConstraintAxisHorizontal;
    logoStack.alignment = UIStackViewAlignmentCenter;
    logoStack.spacing = 0;
    logoStack.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *logoLeft = [[UILabel alloc] init];
    logoLeft.text = @"XIT";
    logoLeft.font = [UIFont systemFontOfSize:42 weight:UIFontWeightHeavy];
    logoLeft.textColor = softWhite;
    logoLeft.textAlignment = NSTextAlignmentRight;
    logoLeft.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *logoRight = [[UILabel alloc] init];
    logoRight.text = @"FARGE";
    logoRight.font = [UIFont systemFontOfSize:42 weight:UIFontWeightHeavy];
    logoRight.textColor = redColor;
    logoRight.textAlignment = NSTextAlignmentLeft;
    logoRight.translatesAutoresizingMaskIntoConstraints = NO;

    [logoStack addArrangedSubview:logoLeft];
    [logoStack addArrangedSubview:logoRight];
    [contentStack addArrangedSubview:logoStack];

    // Línea roja luminosa debajo del logo.
    UIView *logoGlow = [[UIView alloc] init];
    logoGlow.backgroundColor = redColor;
    logoGlow.layer.cornerRadius = 1.5;
    logoGlow.layer.shadowColor = redColor.CGColor;
    logoGlow.layer.shadowOpacity = 0.9;
    logoGlow.layer.shadowRadius = 10.0;
    logoGlow.layer.shadowOffset = CGSizeZero;
    logoGlow.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:logoGlow];

    // MARK: Texto principal
    UILabel *promptTop = [[UILabel alloc] init];
    promptTop.text = @"INGRESA TU CLAVE DE LICENCIA";
    promptTop.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    promptTop.textColor = mutedWhite;
    promptTop.textAlignment = NSTextAlignmentCenter;
    promptTop.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:promptTop];

    UILabel *promptBottom = [[UILabel alloc] init];
    promptBottom.text = @"para continuar";
    promptBottom.font = [UIFont systemFontOfSize:25 weight:UIFontWeightSemibold];
    promptBottom.textColor = softWhite;
    promptBottom.textAlignment = NSTextAlignmentCenter;
    promptBottom.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:promptBottom];

    // MARK: Campo de licencia
    self.licenseField = [[UITextField alloc] init];
    self.licenseField.backgroundColor = fieldFill;
    self.licenseField.layer.cornerRadius = 16.0;
    self.licenseField.layer.borderWidth = 1.0;
    self.licenseField.layer.borderColor = [redColor colorWithAlphaComponent:0.72].CGColor;
    self.licenseField.layer.shadowColor = redColor.CGColor;
    self.licenseField.layer.shadowOpacity = 0.14;
    self.licenseField.layer.shadowRadius = 14.0;
    self.licenseField.layer.shadowOffset = CGSizeZero;
    self.licenseField.textColor = softWhite;
    self.licenseField.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightMedium];
    self.licenseField.textAlignment = NSTextAlignmentCenter;
    self.licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.licenseField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.licenseField.keyboardType = UIKeyboardTypeASCIICapable;
    self.licenseField.returnKeyType = UIReturnKeyDone;
    self.licenseField.delegate = self;
    self.licenseField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"XXXX-XXXX-XXXX-XXXX"
                                                                                attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.34 alpha:1.0],
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightMedium]
    }];
    self.licenseField.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *keyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key.fill"]];
    keyIcon.tintColor = redColor;
    keyIcon.contentMode = UIViewContentModeCenter;
    keyIcon.frame = CGRectMake(0, 0, 50, 30);
    self.licenseField.leftView = keyIcon;
    self.licenseField.leftViewMode = UITextFieldViewModeAlways;

    [contentStack addArrangedSubview:self.licenseField];

    // MARK: Botón
    UIButton *activateButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [activateButton setTitle:@"CONTINUAR" forState:UIControlStateNormal];
    [activateButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    activateButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    activateButton.backgroundColor = redColor;
    activateButton.layer.cornerRadius = 16.0;
    activateButton.layer.shadowColor = redColor.CGColor;
    activateButton.layer.shadowOpacity = 0.34;
    activateButton.layer.shadowRadius = 18.0;
    activateButton.layer.shadowOffset = CGSizeMake(0, 8);
    activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [activateButton addTarget:self action:@selector(activateLicense) forControlEvents:UIControlEventTouchUpInside];
    [contentStack addArrangedSubview:activateButton];

    // MARK: Pie pequeño
    UILabel *footer = [[UILabel alloc] init];
    footer.text = @"Tu licencia. Tu acceso.";
    footer.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    footer.textColor = [UIColor colorWithWhite:0.34 alpha:1.0];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:footer];

    // ---- Auto Layout ----
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:26],
        [contentStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-26],
        [contentStack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-15],
        [contentStack.widthAnchor constraintLessThanOrEqualToConstant:520],

        [logoStack.heightAnchor constraintEqualToConstant:52],
        [logoGlow.widthAnchor constraintEqualToConstant:150],
        [logoGlow.heightAnchor constraintEqualToConstant:3],
        [logoGlow.centerXAnchor constraintEqualToAnchor:contentStack.centerXAnchor],

        [promptTop.topAnchor constraintEqualToAnchor:logoGlow.bottomAnchor constant:38],
        [promptTop.heightAnchor constraintEqualToConstant:22],
        [promptBottom.topAnchor constraintEqualToAnchor:promptTop.bottomAnchor constant:2],
        [promptBottom.heightAnchor constraintEqualToConstant:36],

        [self.licenseField.topAnchor constraintEqualToAnchor:promptBottom.bottomAnchor constant:28],
        [self.licenseField.heightAnchor constraintEqualToConstant:62],

        [activateButton.topAnchor constraintEqualToAnchor:self.licenseField.bottomAnchor constant:16],
        [activateButton.heightAnchor constraintEqualToConstant:58],

        [footer.topAnchor constraintEqualToAnchor:activateButton.bottomAnchor constant:30],
        [footer.heightAnchor constraintEqualToConstant:20],
        [footer.bottomAnchor constraintEqualToAnchor:contentStack.bottomAnchor]
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CALayer *background = self.view.layer.sublayers.firstObject;
    if ([background isKindOfClass:[CAGradientLayer class]]) {
        background.frame = self.view.bounds;
    }
}

#pragma mark - Lógica de Auto-formato con guiones (XXXX-XXXX-XXXX-XXXX)

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *currentText = textField.text;
    NSString *newText = [currentText stringByReplacingCharactersInRange:range withString:string];

    newText = [[newText componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];

    // Máximo 16 caracteres: XXXX-XXXX-XXXX-XXXX
    if (newText.length > 16) {
        return NO;
    }

    // Todo a mayúsculas para que la validación siga siendo consistente.
    newText = [newText uppercaseString];

    NSMutableString *formattedString = [NSMutableString string];
    for (NSUInteger i = 0; i < newText.length; i++) {
        if (i > 0 && i % 4 == 0) {
            [formattedString appendString:@"-"];
        }
        [formattedString appendFormat:@"%C", [newText characterAtIndex:i]];
    }

    textField.text = formattedString;
    return NO;
}

#pragma mark - Acción del botón

- (void)activateLicense {
    NSString *input = self.licenseField.text;
    if ([self validarFormatoLicencia:input]) {
        [[NSUserDefaults standardUserDefaults] setObject:input forKey:@"MiFilzaLicenseKey"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        if (self.onLicenseValidated) {
            self.onLicenseValidated();
        }
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Licencia no válida"
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

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self activateLicense];
    return YES;
}

@end
