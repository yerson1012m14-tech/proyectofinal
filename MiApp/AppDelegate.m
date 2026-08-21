#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate () <UITextFieldDelegate>
@property (nonatomic, strong) UIWindow *lockWindow;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIColor *acento = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];

    UINavigationBarAppearance *ap = [[UINavigationBarAppearance alloc] init];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = [UIColor blackColor];
    ap.shadowColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    ap.titleTextAttributes = @{
        NSForegroundColorAttributeName: acento,
        NSFontAttributeName: [UIFont fontWithName:@"Menlo-Bold" size:17]
    };
    [[UINavigationBar appearance] setStandardAppearance:ap];
    [[UINavigationBar appearance] setScrollEdgeAppearance:ap];
    [[UINavigationBar appearance] setTintColor:acento];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ViewController *vc = [[ViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    // --- SISTEMA DE LICENCIA (XXXX-XXXX-XXXX-XXXX) ---
    [self mostrarPantallaLicencia];
    
    return YES;
}

- (void)mostrarPantallaLicencia {
    NSString *licenciaGuardada = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiFilzaLicenseKey"];
    
    // Si ya hay una licencia guardada, desbloquear directamente
    if (licenciaGuardada && [self validarFormatoLicencia:licenciaGuardada]) {
        self.lockWindow.hidden = YES;
        self.lockWindow = nil;
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔐 Licencia requerida"
                                                                   message:@"Ingresa tu clave de licencia con el formato:\nXXXX-XXXX-XXXX-XXXX"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = NO;
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.keyboardType = UIKeyboardTypeASCIICapable;
        tf.placeholder = @"XXXX-XXXX-XXXX-XXXX";
        tf.delegate = self;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Verificar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = [alert.textFields.firstObject.text uppercaseString];
        if ([self validarFormatoLicencia:input]) {
            [[NSUserDefaults standardUserDefaults] setObject:input forKey:@"MiFilzaLicenseKey"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            self.lockWindow.hidden = YES;
            self.lockWindow = nil;
        } else {
            UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                              message:@"El formato debe ser exactamente XXXX-XXXX-XXXX-XXXX (letras y números)."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [errAlert addAction:[UIAlertAction actionWithTitle:@"Reintentar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [self mostrarPantallaLicencia];
            }]];
            [self.lockWindow.rootViewController presentViewController:errAlert animated:YES completion:nil];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Salir" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }]];
    
    self.lockWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.lockWindow.rootViewController = [[UIViewController alloc] init];
    self.lockWindow.windowLevel = UIWindowLevelAlert + 1;
    [self.lockWindow makeKeyAndVisible];
    [self.lockWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (BOOL)validarFormatoLicencia:(NSString *)licencia {
    // Valida el formato XXXX-XXXX-XXXX-XXXX (4 bloques de 4 caracteres alfanuméricos)
    NSString *regex = @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";
    NSPredicate *predicado = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
    return [predicado evaluateWithObject:licencia];
}

@end
