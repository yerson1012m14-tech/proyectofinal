#import "ViewController.h"

@interface ViewController ()
@property (nonatomic, strong) UITextField *keyTextField;
@property (nonatomic, strong) UIButton *validateButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self setupVisualInterface];
}

- (void)setupVisualInterface {
    // 1. Crear el campo de texto para la Key
    self.keyTextField = [[UITextField alloc] initWithFrame:CGRectMake(50, 200, self.view.bounds.size.width - 100, 40)];
    self.keyTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.keyTextField.placeholder = @"Ingresa tu Key (Ej: ABC-1234-5678-9012)";
    self.keyTextField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.keyTextField.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.keyTextField];
    
    // 2. Crear el botón de validación
    self.validateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.validateButton.frame = CGRectMake(100, 260, self.view.bounds.size.width - 200, 45);
    [self.validateButton setTitle:@"Validar Key" forState:UIControlStateNormal];
    self.validateButton.backgroundColor = [UIColor systemBlueColor];
    [self.validateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.validateButton.layer.cornerRadius = 8; // Bordes redondeados para que se vea mejor
    
    // Conectar el botón con la acción
    [self.validateButton addTarget:self 
                            action:@selector(checkKeyButtonTapped) 
                  forControlEvents:UIControlEventTouchUpInside];
                  
    [self.view addSubview:self.validateButton];
}

// 3. Acción al presionar el botón
- (void)checkKeyButtonTapped {
    NSString *enteredKey = self.keyTextField.text;
    
    if ([self validateLicenseKey:enteredKey]) {
        // Formato correcto
        [self showAlertWithTitle:@"Éxito" message:@"La llave es válida. Software desbloqueado."];
    } else {
        // Formato incorrecto
        [self showAlertWithTitle:@"Error" message:@"Formato inválido. Recuerda usar: xxx-xxxx-xxxx-xxxx"];
    }
}

// 4. Lógica de validación exacta
- (BOOL)validateLicenseKey:(NSString *)key {
    NSString *regexPattern = @"^[A-Za-z0-9]{3}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$";
    NSPredicate *keyTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regexPattern];
    return [keyTest evaluateWithObject:key];
}

// 5. Método auxiliar para mostrar alertas en pantalla
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
