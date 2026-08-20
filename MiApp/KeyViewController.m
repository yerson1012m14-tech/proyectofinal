#import "KeyViewController.h"
#import "KeyManager.h"
#import "ViewController.h"

@interface KeyViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation KeyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
}

- (void)setupUI {
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = CGRectMake(20, (self.view.bounds.size.height - 300)/2, self.view.bounds.size.width - 40, 300);
    blur.layer.cornerRadius = 20;
    blur.clipsToBounds = YES;
    blur.layer.borderColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:0.3].CGColor;
    blur.layer.borderWidth = 1;
    [self.view addSubview:blur];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 30, blur.bounds.size.width - 40, 30)];
    titleLabel.text = @"ACTIVACIÓN DE LICENCIA";
    titleLabel.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
    titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [blur.contentView addSubview:titleLabel];
    
    self.keyField = [[UITextField alloc] initWithFrame:CGRectMake(20, 100, blur.bounds.size.width - 40, 50)];
    self.keyField.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
    self.keyField.layer.cornerRadius = 12;
    self.keyField.layer.borderWidth = 1;
    self.keyField.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.5].CGColor;
    self.keyField.textColor = [UIColor whiteColor];
    self.keyField.font = [UIFont fontWithName:@"Menlo-Bold" size:14];
    self.keyField.textAlignment = NSTextAlignmentCenter;
    self.keyField.placeholder = @"XXXX-XXXX-XXXX-XXXX";
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.keyField.delegate = self;
    [blur.contentView addSubview:self.keyField];
    
    self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.actionButton.frame = CGRectMake(20, 180, blur.bounds.size.width - 40, 50);
    self.actionButton.backgroundColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
    self.actionButton.layer.cornerRadius = 12;
    [self.actionButton setTitle:@"VERIFICAR CLAVE" forState:UIControlStateNormal];
    [self.actionButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.actionButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14];
    [self.actionButton addTarget:self action:@selector(verificarClave) forControlEvents:UIControlEventTouchUpInside];
    [blur.contentView addSubview:self.actionButton];
}

- (void)verificarClave {
    [self.keyField resignFirstResponder];
    [self.actionButton setTitle:@"VERIFICANDO..." forState:UIControlStateNormal];
    
    [[KeyManager sharedManager] validateKey:self.keyField.text completion:^(BOOL success, NSString *message) {
        if (success) {
            ViewController *mainVC = [[ViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:mainVC];
            nav.modalPresentationStyle = UIModalPresentationCustom;
            nav.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
            [self presentViewController:nav animated:YES completion:nil];
        } else {
            [self.actionButton setTitle:@"VERIFICAR CLAVE" forState:UIControlStateNormal];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *text = [textField.text stringByReplacingCharactersInRange:range withString:string];
    text = [[text componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
    
    if (text.length > 16) return NO;
    
    NSMutableString *formatted = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        if (i > 0 && i % 4 == 0) [formatted appendString:@"-"];
        [formatted appendFormat:@"%C", [text characterAtIndex:i]];
    }
    
    textField.text = [formatted uppercaseString];
    return NO;
}

@end
