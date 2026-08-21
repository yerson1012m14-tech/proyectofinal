#import "HomeViewController.h"

@interface HomeViewController ()
@end

@implementation HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"XITFORGE";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self setupUI];
}

- (void)setupUI {
    UIColor *white = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *muted = [UIColor colorWithWhite:0.50 alpha:1.0];
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    UIColor *green = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
    
    UIView *topGlow = [[UIView alloc] init];
    topGlow.translatesAutoresizingMaskIntoConstraints = NO;
    topGlow.backgroundColor = [red colorWithAlphaComponent:0.055];
    topGlow.layer.cornerRadius = 170.0;
    topGlow.layer.masksToBounds = YES;
    topGlow.userInteractionEnabled = NO;
    [self.view addSubview:topGlow];
    
    UIView *bottomGlow = [[UIView alloc] init];
    bottomGlow.translatesAutoresizingMaskIntoConstraints = NO;
    bottomGlow.backgroundColor = [green colorWithAlphaComponent:0.045];
    bottomGlow.layer.cornerRadius = 150.0;
    bottomGlow.layer.masksToBounds = YES;
    bottomGlow.userInteractionEnabled = NO;
    [self.view addSubview:bottomGlow];
    
    UILabel *logo = [[UILabel alloc] init];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.text = @"XITFORGE";
    logo.textColor = white;
    logo.font = [UIFont systemFontOfSize:36.0 weight:UIFontWeightBold];
    logo.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:logo];
    
    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = red;
    line.layer.cornerRadius = 1.0;
    line.layer.shadowColor = red.CGColor;
    line.layer.shadowOpacity = 0.30;
    line.layer.shadowRadius = 5.0;
    line.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:line];
    
    UILabel *welcome = [[UILabel alloc] init];
    welcome.translatesAutoresizingMaskIntoConstraints = NO;
    welcome.text = @"Bienvenido";
    welcome.textColor = white;
    welcome.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightSemibold];
    welcome.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:welcome];
    
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Explorador de archivos para iOS";
    subtitle.textColor = muted;
    subtitle.font = [UIFont systemFontOfSize:14.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:subtitle];
    
    UIView *infoCard = [[UIView alloc] init];
    infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    infoCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
    infoCard.layer.cornerRadius = 16;
    infoCard.clipsToBounds = YES;
    [self.view addSubview:infoCard];
    
    UIImageView *infoIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
    infoIcon.translatesAutoresizingMaskIntoConstraints = NO;
    infoIcon.tintColor = green;
    [infoCard addSubview:infoIcon];
    
    UILabel *infoTitle = [[UILabel alloc] init];
    infoTitle.translatesAutoresizingMaskIntoConstraints = NO;
    infoTitle.text = @"CARACTERÍSTICAS";
    infoTitle.textColor = white;
    infoTitle.font = [UIFont boldSystemFontOfSize:13];
    [infoCard addSubview:infoTitle];
    
    UILabel *infoText = [[UILabel alloc] init];
    infoText.translatesAutoresizingMaskIntoConstraints = NO;
    infoText.text = @"• Explora el sistema de archivos\n• Accede a contenedores de apps\n• Edita archivos de configuración\n• Crea y elimina carpetas";
    infoText.textColor = muted;
    infoText.font = [UIFont systemFontOfSize:12];
    infoText.numberOfLines = 0;
    [infoCard addSubview:infoText];
    
    UILabel *version = [[UILabel alloc] init];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.text = @"v1.0.0";
    version.textColor = [UIColor colorWithWhite:0.30 alpha:1.0];
    version.font = [UIFont fontWithName:@"Menlo" size:11];
    version.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:version];
    
    [NSLayoutConstraint activateConstraints:@[
        [topGlow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [topGlow.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:-220],
        [topGlow.widthAnchor constraintEqualToConstant:340],
        [topGlow.heightAnchor constraintEqualToConstant:340],
        
        [bottomGlow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [bottomGlow.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:170],
        [bottomGlow.widthAnchor constraintEqualToConstant:300],
        [bottomGlow.heightAnchor constraintEqualToConstant:300],
        
        [logo.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [logo.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
        
        [line.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [line.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:12],
        [line.widthAnchor constraintEqualToConstant:60],
        [line.heightAnchor constraintEqualToConstant:2],
        
        [welcome.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [welcome.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:40],
        
        [subtitle.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:welcome.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [infoCard.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [infoCard.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:40],
        [infoCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [infoCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [infoIcon.topAnchor constraintEqualToAnchor:infoCard.topAnchor constant:16],
        [infoIcon.leadingAnchor constraintEqualToAnchor:infoCard.leadingAnchor constant:16],
        [infoIcon.widthAnchor constraintEqualToConstant:22],
        [infoIcon.heightAnchor constraintEqualToConstant:22],
        
        [infoTitle.leadingAnchor constraintEqualToAnchor:infoIcon.trailingAnchor constant:10],
        [infoTitle.topAnchor constraintEqualToAnchor:infoIcon.topAnchor],
        
        [infoText.topAnchor constraintEqualToAnchor:infoIcon.bottomAnchor constant:12],
        [infoText.leadingAnchor constraintEqualToAnchor:infoCard.leadingAnchor constant:16],
        [infoText.trailingAnchor constraintEqualToAnchor:infoCard.trailingAnchor constant:-16],
        [infoText.bottomAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:-16],
        
        [version.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [version.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
    ]];
}

@end
