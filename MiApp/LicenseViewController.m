#import "LicenseViewController.h"

@interface LicenseViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *licenseField;

@end

@implementation LicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0]; // Fondo negro profundo
    
    [self setupUI];
}

- (void)setupUI {
    UIColor *redColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:1.0];
    
    // 1. LOGO (XITFARGE)
    UILabel *logoLeft = [[UILabel alloc] init];
    logoLeft.text = @"XIT";
    logoLeft.font = [UIFont fontWithName:@"Menlo-Bold" size:34];
    logoLeft.textColor = [UIColor whiteColor];
    logoLeft.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *logoRight = [[UILabel alloc] init];
    logoRight.text = @"FARGE";
    logoRight.font = [UIFont fontWithName:@"Menlo-Bold" size:34];
    logoRight.textColor = redColor;
    logoRight.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIView *logoContainer = [[UIView alloc] init];
    logoContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [logoContainer addSubview:logoLeft];
    [logoContainer addSubview:logoRight];
    [self.view addSubview:logoContainer];
    
    // Línea roja sutil debajo del logo (como en tu imagen)
    UIView *lineView = [[UIView alloc] init];
    lineView.backgroundColor = redColor;
    lineView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:lineView];
    
    // 2. CAMPO DE TEXTO (con formato automático de guiones)
    self.licenseField = [[UITextField alloc] init];
    self.licenseField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.licenseField.layer.cornerRadius = 8;
    self.licenseField.layer.borderWidth = 1;
    self.licenseField.layer.borderColor = redColor.CGColor; // Borde rojo
    self.licenseField.textColor = [UIColor whiteColor];
    self.licenseField.font = [UIFont fontWithName:@"Menlo" size:16];
    self.licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.licenseField.keyboardType = UIKeyboardTypeASCIICapable;
    self.licenseField.returnKeyType = UIReturnKeyDone;
    self.licenseField.delegate = self;
    self.licenseField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"XXXX-XXXX-XXXX-XXXX" 
                                                                             attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.3 alpha:1.0]}];
    self.licenseField.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Icono de llave dentro del campo
    UIImageView *keyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key"]];
    keyIcon.tintColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    keyIcon.contentMode = UIViewContentModeCenter;
    keyIcon.frame = CGRectMake(0, 0, 30, 30);
    self.licenseField.leftView = keyIcon;
    self.licenseField.leftViewMode = UITextFieldViewModeAlways;
    
    [self.view addSubview:self.licenseField];
    
    // 3. BOTÓN ACTIVAR
    UIButton *activateButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [activateButton setTitle:@"ACTIVAR" forState:UIControlStateNormal];
    [activateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    activateButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16];
    activateButton.backgroundColor = redColor;
    activateButton.layer.cornerRadius = 8;
    activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [activateButton addTarget:self action:@selector(activateLicense) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:activateButton];
    
    // ---- CONSTRAINTS (Auto Layout) ----
    [NSLayoutConstraint activateConstraints:@[
        // Logo Container
        [logoContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [logoContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:80],
        [logoLeft.leadingAnchor constraintEqualToAnchor:logoContainer.leadingAnchor],
        [logoLeft.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [logoRight.leadingAnchor constraintEqualToAnchor:logoLeft.trailingAnchor],
        [logoRight.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [logoContainer.trailingAnchor constraintEqualToAnchor:logoRight.trailingAnchor],
        
        // Línea roja debajo del logo
        [lineView.topAnchor constraintEqualToAnchor:logoContainer.bottomAnchor constant:8],
        [lineView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [lineView.widthAnchor constraintEqualToConstant:120],
        [lineView.heightAnchor constraintEqualToConstant:3],
        [lineView.layer setValue:@(1.5) forKeyPath:@"cornerRadius"], // Redondear puntas de la línea
        
        // Campo de texto
        [self.licenseField.topAnchor constraintEqualToAnchor:lineView.bottomAnchor constant:50],
        [self.licenseField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.licenseField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.licenseField.heightAnchor constraintEqualToConstant:48],
        
        // Botón Activar
        [activateButton.topAnchor constraintEqualToAnchor:self.licenseField.bottomAnchor constant:20],
        [activateButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [activateButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [activateButton.heightAnchor constraintEqualToConstant:50]
    ]];
}

#pragma mark - Lógica de Auto-formato con guiones (XXXX-XXXX-XXXX-XXXX)

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Obtener el texto actual y aplicar el reemplazo
    NSString *currentText = textField.text;
    NSString *newText = [currentText stringByReplacingCharactersInRange:range withString:string];
    
    // Eliminar cualquier carácter que no sea alfanumérico
    newText = [[newText componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
    
    // Limitar a 16 caracteres
    if (newText.length > 16) {
        return NO;
    }
    
    // Insertar guiones automáticamente
    NSMutableString *formattedString = [NSMutableString string];
    for (int i = 0; i < newText.length; i++) {
        unichar character = [newText characterAtIndex:i];
        if (i > 0 && i % 4 == 0) {
            [formattedString appendString:@"-"];
        }
        [formattedString appendFormat:@"%C", character];
    }
    
    textField.text = formattedString;
    return NO; // Evita que se aplique el cambio predeterminado
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"El formato debe ser exactamente XXXX-XXXX-XXXX-XXXX (solo letras y números)."
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

#pragma mark - UITextFieldDelegate (para el botón Done del teclado)

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self activateLicense];
    return YES;
}

@end
