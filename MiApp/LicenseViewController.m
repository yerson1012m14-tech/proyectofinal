#import "LicenseViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>

@interface LicenseViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *licenseField;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) CAGradientLayer *buttonGradient;
@property (nonatomic, strong) CAGradientLayer *fieldGlow;
@property (nonatomic, strong) UIView *topGlow;
@property (nonatomic, strong) UIView *bottomGlow;
@property (nonatomic, strong) UILabel *brand;
@property (nonatomic, strong) UIView *brandLine;
@property (nonatomic, strong) UIButton *buttonShadow;
@property (nonatomic, strong) UIStackView *blockIndicators;
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
    UIColor *redDark = [UIColor colorWithRed:0.72 green:0.03 blue:0.05 alpha:1.0];
    
    // ===== GLOWS DE FONDO ANIMADOS =====
    self.topGlow = [[UIView alloc] init];
    self.topGlow.translatesAutoresizingMaskIntoConstraints = NO;
    self.topGlow.backgroundColor = [red colorWithAlphaComponent:0.06];
    self.topGlow.layer.cornerRadius = 170.0;
    self.topGlow.layer.masksToBounds = YES;
    self.topGlow.userInteractionEnabled = NO;
    [self.view addSubview:self.topGlow];
    
    self.bottomGlow = [[UIView alloc] init];
    self.bottomGlow.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomGlow.backgroundColor = [red colorWithAlphaComponent:0.05];
    self.bottomGlow.layer.cornerRadius = 150.0;
    self.bottomGlow.layer.masksToBounds = YES;
    self.bottomGlow.userInteractionEnabled = NO;
    [self.view addSubview:self.bottomGlow];
    
    // ===== LOGO / MARCA =====
    self.brand = [[UILabel alloc] init];
    self.brand.translatesAutoresizingMaskIntoConstraints = NO;
    self.brand.textAlignment = NSTextAlignmentCenter;
    self.brand.text = @"XITFORGE";
    self.brand.textColor = white;
    self.brand.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightBlack];
    self.brand.adjustsFontSizeToFitWidth = YES;
    self.brand.minimumScaleFactor = 0.75;
    self.brand.alpha = 0;
    [self.view addSubview:self.brand];
    
    // Línea roja debajo del logo con glow
    self.brandLine = [[UIView alloc] init];
    self.brandLine.translatesAutoresizingMaskIntoConstraints = NO;
    self.brandLine.backgroundColor = red;
    self.brandLine.layer.cornerRadius = 1.0;
    self.brandLine.layer.shadowColor = red.CGColor;
    self.brandLine.layer.shadowOpacity = 0.5;
    self.brandLine.layer.shadowRadius = 8.0;
    self.brandLine.layer.shadowOffset = CGSizeZero;
    self.brandLine.alpha = 0;
    [self.view addSubview:self.brandLine];
    
    // Subtítulo elegante
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"LICENSE ACTIVATION";
    subtitle.textColor = muted;
    subtitle.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.letterSpacing = 3.0;
    subtitle.alpha = 0;
    [self.view addSubview:subtitle];
    
    // ===== CAMPO DE TEXTO CON GLOW =====
    self.licenseField = [[UITextField alloc] init];
    self.licenseField.translatesAutoresizingMaskIntoConstraints = NO;
    self.licenseField.backgroundColor = fieldFill;
    self.licenseField.textColor = white;
    self.licenseField.font = [UIFont monospacedSystemFontOfSize:18.0 weight:UIFontWeightSemibold];
    self.licenseField.textAlignment = NSTextAlignmentCenter;
    self.licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.licenseField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.licenseField.smartQuotesType = UITextSmartQuotesTypeNo;
    self.licenseField.smartDashesType = UITextSmartDashesTypeNo;
    self.licenseField.keyboardType = UIKeyboardTypeASCIICapable;
    self.licenseField.returnKeyType = UIReturnKeyDone;
    self.licenseField.delegate = self;
    self.licenseField.layer.cornerRadius = 16.0;
    self.licenseField.layer.borderWidth = 1.5;
    self.licenseField.layer.borderColor = fieldBorder.CGColor;
    self.licenseField.layer.shadowColor = [UIColor blackColor].CGColor;
    self.licenseField.layer.shadowOpacity = 0.3;
    self.licenseField.layer.shadowRadius = 20.0;
    self.licenseField.layer.shadowOffset = CGSizeMake(0, 10);
    self.licenseField.alpha = 0;
    
    self.licenseField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"XXXX-XXXX-XXXX-XXXX"
        attributes:@{
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.30 alpha:1.0],
            NSFontAttributeName: [UIFont monospacedSystemFontOfSize:17.0 weight:UIFontWeightMedium]
        }];
    [self.view addSubview:self.licenseField];
    
    // Glow del campo (se activa al editar)
    self.fieldGlow = [CAGradientLayer layer];
    self.fieldGlow.colors = @[
        (id)[red colorWithAlphaComponent:0.0].CGColor,
        (id)[red colorWithAlphaComponent:0.3].CGColor,
        (id)[red colorWithAlphaComponent:0.0].CGColor
    ];
    self.fieldGlow.startPoint = CGPointMake(0.0, 0.5);
    self.fieldGlow.endPoint = CGPointMake(1.0, 0.5);
    self.fieldGlow.opacity = 0;
    [self.licenseField.layer insertSublayer:self.fieldGlow atIndex:0];
    
    // ===== INDICADORES DE BLOQUES (4 puntitos) =====
    self.blockIndicators = [UIStackView new];
    self.blockIndicators.translatesAutoresizingMaskIntoConstraints = NO;
    self.blockIndicators.axis = UILayoutConstraintAxisHorizontal;
    self.blockIndicators.distribution = UIStackViewDistributionFillEqually;
    self.blockIndicators.spacing = 12;
    self.blockIndicators.alpha = 0;
    
    for (int i = 0; i < 4; i++) {
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        dot.layer.cornerRadius = 4;
        dot.tag = 100 + i;
        [self.blockIndicators addArrangedSubview:dot];
    }
    [self.view addSubview:self.blockIndicators];
    
    // ===== BOTÓN CON GRADIENTE =====
    self.buttonShadow = [UIButton buttonWithType:UIButtonTypeCustom];
    self.buttonShadow.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttonShadow.backgroundColor = [red colorWithAlphaComponent:0.2];
    self.buttonShadow.layer.cornerRadius = 28.0;
    self.buttonShadow.layer.shadowColor = red.CGColor;
    self.buttonShadow.layer.shadowOpacity = 0.4;
    self.buttonShadow.layer.shadowRadius = 24.0;
    self.buttonShadow.layer.shadowOffset = CGSizeZero;
    self.buttonShadow.userInteractionEnabled = NO;
    self.buttonShadow.alpha = 0;
    [self.view addSubview:self.buttonShadow];
    
    self.continueButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.continueButton setTitle:@"CONTINUAR" forState:UIControlStateNormal];
    [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.continueButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    self.continueButton.letterSpacing = 1.5;
    self.continueButton.layer.cornerRadius = 14.0;
    self.continueButton.layer.masksToBounds = YES;
    [self.continueButton addTarget:self action:@selector(buttonPressed) forControlEvents:UIControlEventTouchDown];
    [self.continueButton addTarget:self action:@selector(buttonReleased) forControlEvents:UIControlEventTouchUpInside];
    [self.continueButton addTarget:self action:@selector(buttonReleased) forControlEvents:UIControlEventTouchUpOutside];
    [self.continueButton addTarget:self action:@selector(activateLicense) forControlEvents:UIControlEventTouchUpInside];
    self.continueButton.alpha = 0;
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
    
    // ===== FOOTER =====
    UILabel *footer = [[UILabel alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.text = @"Secured by XITFORGE Engine";
    footer.textColor = [UIColor colorWithWhite:0.30 alpha:1.0];
    footer.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightRegular];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.alpha = 0;
    [self.view addSubview:footer];
    
    // ===== CONSTRAINTS =====
    [NSLayoutConstraint activateConstraints:@[
        // Glows
        [self.topGlow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.topGlow.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:-220],
        [self.topGlow.widthAnchor constraintEqualToConstant:340],
        [self.topGlow.heightAnchor constraintEqualToConstant:340],
        
        [self.bottomGlow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.bottomGlow.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:170],
        [self.bottomGlow.widthAnchor constraintEqualToConstant:300],
        [self.bottomGlow.heightAnchor constraintEqualToConstant:300],
        
        // Brand
        [self.brand.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.brand.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:90],
        [self.brand.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.brand.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-30],
        [self.brand.heightAnchor constraintEqualToConstant:42],
        
        [self.brandLine.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.brandLine.topAnchor constraintEqualToAnchor:self.brand.bottomAnchor constant:10],
        [self.brandLine.widthAnchor constraintEqualToConstant:50],
        [self.brandLine.heightAnchor constraintEqualToConstant:2],
        
        // Subtitle
        [subtitle.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:self.brandLine.bottomAnchor constant:14],
        [subtitle.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:30],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-30],
        
        // Field
        [self.licenseField.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.licenseField.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:60],
        [self.licenseField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.licenseField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [self.licenseField.heightAnchor constraintEqualToConstant:60],
        
        // Block indicators
        [self.blockIndicators.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.blockIndicators.topAnchor constraintEqualToAnchor:self.licenseField.bottomAnchor constant:16],
        [self.blockIndicators.widthAnchor constraintEqualToConstant:120],
        [self.blockIndicators.heightAnchor constraintEqualToConstant:8],
        
        // Button shadow
        [self.buttonShadow.centerXAnchor constraintEqualToAnchor:self.continueButton.centerXAnchor],
        [self.buttonShadow.centerYAnchor constraintEqualToAnchor:self.continueButton.centerYAnchor constant:8],
        [self.buttonShadow.widthAnchor constraintEqualToAnchor:self.continueButton.widthAnchor constant:-6],
        [self.buttonShadow.heightAnchor constraintEqualToAnchor:self.continueButton.heightAnchor constant:-6],
        
        // Button
        [self.continueButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.continueButton.topAnchor constraintEqualToAnchor:self.blockIndicators.bottomAnchor constant:30],
        [self.continueButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.continueButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [self.continueButton.heightAnchor constraintEqualToConstant:56],
        
        // Footer
        [footer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [footer.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:30],
        [footer.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-30],
    ]];
    
    [self updateButtonGradientFrame];
    [self updateFieldGlowFrame];
    
    // Iniciar animación de glow de fondo
    [self startAmbientAnimation];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateButtonGradientFrame];
    [self updateFieldGlowFrame];
}

- (void)updateButtonGradientFrame {
    self.buttonGradient.frame = self.continueButton.bounds;
    self.buttonGradient.cornerRadius = self.continueButton.layer.cornerRadius;
}

- (void)updateFieldGlowFrame {
    self.fieldGlow.frame = self.licenseField.bounds;
    self.fieldGlow.cornerRadius = self.licenseField.layer.cornerRadius;
}

#pragma mark - Animaciones

- (void)animateEntrance {
    // Secuencia escalonada
    [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        self.brand.alpha = 1;
        self.brand.transform = CGAffineTransformMakeTranslation(0, 0);
    } completion:nil];
    
    [UIView animateWithDuration:0.5 delay:0.1 options:0 animations:^{
        self.brandLine.alpha = 1;
        self.brandLine.transform = CGAffineTransformMakeScale(1, 1);
    } completion:nil];
    
    [UIView animateWithDuration:0.5 delay:0.2 options:0 animations:^{
        // Subtitle
        for (UIView *sub in self.view.subviews) {
            if ([sub isKindOfClass:[UILabel class]] && [(UILabel *)sub.text isEqualToString:@"LICENSE ACTIVATION"]) {
                sub.alpha = 1;
            }
        }
    } completion:nil];
    
    [UIView animateWithDuration:0.6 delay:0.3 usingSpringWithDamping:0.75 initialSpringVelocity:0.3 options:0 animations:^{
        self.licenseField.alpha = 1;
    } completion:nil];
    
    [UIView animateWithDuration:0.5 delay:0.45 options:0 animations:^{
        self.blockIndicators.alpha = 1;
    } completion:nil];
    
    [UIView animateWithDuration:0.6 delay:0.55 usingSpringWithDamping:0.7 initialSpringVelocity:0.4 options:0 animations:^{
        self.continueButton.alpha = 1;
        self.buttonShadow.alpha = 1;
    } completion:nil];
    
    [UIView animateWithDuration:0.5 delay:0.7 options:0 animations:^{
        for (UIView *sub in self.view.subviews) {
            if ([sub isKindOfClass:[UILabel class]] && [(UILabel *)sub.text isEqualToString:@"Secured by XITFORGE Engine"]) {
                sub.alpha = 1;
            }
        }
    } completion:nil];
}

- (void)startAmbientAnimation {
    // Glow superior respira
    [UIView animateWithDuration:3.0 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
        self.topGlow.alpha = 0.6;
        self.topGlow.transform = CGAffineTransformMakeScale(1.08, 1.08);
    } completion:nil];
    
    // Glow inferior respira (desfasado)
    [UIView animateWithDuration:3.5 delay:1.0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
        self.bottomGlow.alpha = 0.7;
        self.bottomGlow.transform = CGAffineTransformMakeScale(1.06, 1.06);
    } completion:nil];
}

- (void)animateShake {
    // Vibración háptica
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.duration = 0.5;
    shake.values = @[@-15, @15, @-12, @12, @-6, @6, @0];
    shake.keyTimes = @[@0, @0.15, @0.3, @0.45, @0.65, @0.8, @1];
    [self.licenseField.layer addAnimation:shake forKey:@"shake"];
    
    // Borde rojo temporal
    self.licenseField.layer.borderColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0].CGColor;
    [UIView animateWithDuration:1.5 delay:0 options:0 animations:^{
        self.licenseField.layer.borderColor = [UIColor colorWithWhite:0.20 alpha:1.0].CGColor;
    } completion:nil];
}

- (void)animateSuccess {
    // Vibración de éxito
    AudioServicesPlaySystemSound(1520);
    
    // Campo se pone verde brevemente
    self.licenseField.layer.borderColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0].CGColor;
    self.licenseField.layer.borderWidth = 2.0;
    
    [UIView animateWithDuration:1.2 delay:0.3 options:0 animations:^{
        self.licenseField.layer.borderColor = [UIColor colorWithWhite:0.20 alpha:1.0].CGColor;
        self.licenseField.layer.borderWidth = 1.5;
    } completion:nil];
    
    // Todos los indicadores se llenan
    for (int i = 0; i < 4; i++) {
        UIView *dot = [self.view viewWithTag:100 + i];
        if (dot) {
            [UIView animateWithDuration:0.3 delay:i * 0.1 options:UIViewAnimationOptionCurveEaseOut animations:^{
                dot.backgroundColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
                dot.transform = CGAffineTransformMakeScale(1.3, 1.3);
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.2 animations:^{
                    dot.transform = CGAffineTransformIdentity;
                }];
            }];
        }
    }
}

#pragma mark - Button press effect

- (void)buttonPressed {
    [UIView animateWithDuration:0.1 animations:^{
        self.continueButton.transform = CGAffineTransformMakeScale(0.96, 0.96);
        self.buttonShadow.transform = CGAffineTransformMakeScale(0.96, 0.96);
    }];
}

- (void)buttonReleased {
    [UIView animateWithDuration:0.2 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 animations:^{
        self.continueButton.transform = CGAffineTransformIdentity;
        self.buttonShadow.transform = CGAffineTransformIdentity;
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
    
    // Actualizar indicadores de bloques
    [self updateBlockIndicators:uppercase.length];
    
    return NO;
}

- (void)updateBlockIndicators:(NSInteger)charCount {
    NSInteger completedBlocks = charCount / 4;
    for (int i = 0; i < 4; i++) {
        UIView *dot = [self.view viewWithTag:100 + i];
        if (dot) {
            UIColor *color = (i < completedBlocks) 
                ? [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0]
                : [UIColor colorWithWhite:0.15 alpha:1.0];
            [UIView animateWithDuration:0.2 animations:^{
                dot.backgroundColor = color;
            }];
        }
    }
}

#pragma mark - License action

- (void)activateLicense {
    [self.view endEditing:YES];
    NSString *input = [self.licenseField.text uppercaseString];
    
    if ([self validarFormatoLicencia:input]) {
        [self animateSuccess];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSUserDefaults standardUserDefaults] setObject:input forKey:@"MiFilzaLicenseKey"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            if (self.onLicenseValidated) {
                self.onLicenseValidated();
            }
        });
    } else {
        [self animateShake];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clave no válida"
            message:@"Ingresa una clave con el formato XXXX-XXXX-XXXX-XXXX."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reintentar" style:UIAlertActionStyleDefault handler:nil]];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self presentViewController:alert animated:YES completion:nil];
        });
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

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    // Activar glow del campo
    [UIView animateWithDuration:0.3 animations:^{
        self.fieldGlow.opacity = 1;
        self.licenseField.layer.borderColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:0.5].CGColor;
    }];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // Desactivar glow
    [UIView animateWithDuration:0.3 animations:^{
        self.fieldGlow.opacity = 0;
        self.licenseField.layer.borderColor = [UIColor colorWithWhite:0.20 alpha:1.0].CGColor;
    }];
}

@end
