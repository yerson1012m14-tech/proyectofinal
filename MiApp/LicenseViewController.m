#import "LicenseViewController.h"

@interface LicenseViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *licenseField;
@property (nonatomic, strong) UIButton *activateButton;

@end

@implementation LicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0]; // Fondo casi negro
    
    [self setupUI];
}

- (void)setupUI {
    // Colores
    UIColor *redColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:1.0];
    UIColor *textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    UIColor *secondaryTextColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    
    // 1. Logo (XITFARGE) - Usaremos dos labels para simular el color
    UILabel *logoLeft = [[UILabel alloc] init];
    logoLeft.text = @"XIT";
    logoLeft.font = [UIFont fontWithName:@"Menlo-Bold" size:32];
    logoLeft.textColor = [UIColor whiteColor];
    logoLeft.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *logoRight = [[UILabel alloc] init];
    logoRight.text = @"FARGE";
    logoRight.font = [UIFont fontWithName:@"Menlo-Bold" size:32];
    logoRight.textColor = redColor;
    logoRight.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIView *logoContainer = [[UIView alloc] init];
    logoContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [logoContainer addSubview:logoLeft];
    [logoContainer addSubview:logoRight];
    
    [self.view addSubview:logoContainer];
    
    // 2. Título "ACTIVAR LICENCIA"
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"ACTIVAR LICENCIA";
    titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:15];
    titleLabel.textColor = textColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];
    
    // 3. Icono de escudo (sistema)
    UIImageView *shieldIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.fill"]];
    shieldIcon.tintColor = redColor;
    shieldIcon.contentMode = UIViewContentModeScaleAspectFit;
    shieldIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:shieldIcon];
    
    // 4. Texto "Ingresa tu licencia para continuar"
    UILabel *instructionLabel = [[UILabel alloc] init];
    instructionLabel.text = @"Ingresa tu licencia para continuar";
    instructionLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightLight];
    instructionLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    instructionLabel.textAlignment = NSTextAlignmentCenter;
    instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:instructionLabel];
    
    // 5. Campo de entrada (con icono de llave)
    self.licenseField = [[UITextField alloc] init];
    self.licenseField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.licenseField.layer.cornerRadius = 8;
    self.licenseField.layer.borderWidth = 1;
    self.licenseField.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    self.licenseField.textColor = [UIColor whiteColor];
    self.licenseField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.licenseField.keyboardType = UIKeyboardTypeASCIICapable;
    self.licenseField.returnKeyType = UIReturnKeyDone;
    self.licenseField.delegate = self;
    self.licenseField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Ingresa tu licencia" attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.4 alpha:1.0]}];
    self.licenseField.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Icono de llave dentro del campo
    UIImageView *keyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key"]];
    keyIcon.tintColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    keyIcon.contentMode = UIViewContentModeCenter;
    keyIcon.frame = CGRectMake(0, 0, 30, 30);
    self.licenseField.leftView = keyIcon;
    self.licenseField.leftViewMode = UITextFieldViewModeAlways;
    
    [self.view addSubview:self.licenseField];
    
    // 6. Botón ACTIVAR
    self.activateButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.activateButton setTitle:@"ACTIVAR" forState:UIControlStateNormal];
    [self.activateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.activateButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16];
    self.activateButton.backgroundColor = redColor;
    self.activateButton.layer.cornerRadius = 8;
    self.activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activateButton addTarget:self action:@selector(activateLicense) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.activateButton];
    
    // 7. Separador "ó"
    UIView *separatorContainer = [[UIView alloc] init];
    separatorContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:separatorContainer];
    
    UIView *lineLeft = [[UIView alloc] init];
    lineLeft.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    lineLeft.translatesAutoresizingMaskIntoConstraints = NO;
    [separatorContainer addSubview:lineLeft];
    
    UILabel *orLabel = [[UILabel alloc] init];
    orLabel.text = @"ó";
    orLabel.textColor = secondaryTextColor;
    orLabel.font = [UIFont systemFontOfSize:14];
    orLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [separatorContainer addSubview:orLabel];
    
    UIView *lineRight = [[UIView alloc] init];
    lineRight.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    lineRight.translatesAutoresizingMaskIntoConstraints = NO;
    [separatorContainer addSubview:lineRight];
    
    // 8. Botón Escanear
    UIButton *scanButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [scanButton setTitle:@"Escanear licencia" forState:UIControlStateNormal];
    [scanButton setTitleColor:redColor forState:UIControlStateNormal];
    [scanButton setImage:[UIImage systemImageNamed:@"viewfinder"] forState:UIControlStateNormal];
    scanButton.tintColor = redColor;
    scanButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    // Ajustar espaciado entre icono y texto
    scanButton.imageEdgeInsets = UIEdgeInsetsMake(0, -8, 0, 8);
    scanButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, -8);
    [scanButton addTarget:self action:@selector(scanLicense) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:scanButton];
    
    // ---- CONSTRAINTS (Auto Layout) ----
    [NSLayoutConstraint activateConstraints:@[
        // Logo Container
        [logoContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [logoContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:60],
        [logoLeft.leadingAnchor constraintEqualToAnchor:logoContainer.leadingAnchor],
        [logoLeft.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [logoRight.leadingAnchor constraintEqualToAnchor:logoLeft.trailingAnchor],
        [logoRight.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [logoContainer.trailingAnchor constraintEqualToAnchor:logoRight.trailingAnchor],
        
        // Title
        [titleLabel.topAnchor constraintEqualToAnchor:logoContainer.bottomAnchor constant:40],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        // Shield Icon
        [shieldIcon.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20],
        [shieldIcon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [shieldIcon.widthAnchor constraintEqualToConstant:60],
        [shieldIcon.heightAnchor constraintEqualToConstant:60],
        
        // Instruction
        [instructionLabel.topAnchor constraintEqualToAnchor:shieldIcon.bottomAnchor constant:20],
        [instructionLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        // License Field
        [self.licenseField.topAnchor constraintEqualToAnchor:instructionLabel.bottomAnchor constant:20],
        [self.licenseField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.licenseField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.licenseField.heightAnchor constraintEqualToConstant:44],
        
        // Activate Button
        [self.activateButton.topAnchor constraintEqualToAnchor:self.licenseField.bottomAnchor constant:20],
        [self.activateButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.activateButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.activateButton.heightAnchor constraintEqualToConstant:50],
        
        // Separator Container
        [separatorContainer.topAnchor constraintEqualToAnchor:self.activateButton.bottomAnchor constant:20],
        [separatorContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [separatorContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [separatorContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [separatorContainer.heightAnchor constraintEqualToConstant:20],
        
        // Inside Separator
        [lineLeft.leadingAnchor constraintEqualToAnchor:separatorContainer.leadingAnchor],
        [lineLeft.centerYAnchor constraintEqualToAnchor:separatorContainer.centerYAnchor],
        [lineLeft.heightAnchor constraintEqualToConstant:1],
        [lineLeft.trailingAnchor constraintEqualToAnchor:orLabel.leadingAnchor constant:-10],
        
        [orLabel.centerXAnchor constraintEqualToAnchor:separatorContainer.centerXAnchor],
        [orLabel.centerYAnchor constraintEqualToAnchor:separatorContainer.centerYAnchor],
        
        [lineRight.leadingAnchor constraintEqualToAnchor:orLabel.trailingAnchor constant:10],
        [lineRight.centerYAnchor constraintEqualToAnchor:separatorContainer.centerYAnchor],
        [lineRight.heightAnchor constraintEqualToConstant:1],
        [lineRight.trailingAnchor constraintEqualToAnchor:separatorContainer.trailingAnchor],
        
        // Scan Button
        [scanButton.topAnchor constraintEqualToAnchor:separatorContainer.bottomAnchor constant:20],
        [scanButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [scanButton.heightAnchor constraintEqualToConstant:44]
    ]];
}

#pragma mark - Acciones

- (void)activateLicense {
    NSString *input = [self.licenseField.text uppercaseString];
    if ([self validarFormatoLicencia:input]) {
        [[NSUserDefaults standardUserDefaults] setObject:input forKey:@"MiFilzaLicenseKey"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // Llamar al bloque de éxito
        if (self.onLicenseValidated) {
            self.onLicenseValidated();
        }
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"El formato debe ser exactamente XXXX-XXXX-XXXX-XXXX (letras y números)."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reintentar" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)scanLicense {
    // Placeholder para el escáner.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Escanear"
                                                                   message:@"Función de escaneo no implementada aún."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Validación

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
