#import "HomeViewController.h"

@interface HomeViewController ()
@property (nonatomic, strong) UIButton *btnNormal;
@property (nonatomic, strong) UIButton *btnMax;
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
    
    UILabel *pregunta = [[UILabel alloc] init];
    pregunta.translatesAutoresizingMaskIntoConstraints = NO;
    pregunta.text = @"¿EN CUAL JUEGAS?";
    pregunta.textColor = white;
    pregunta.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    pregunta.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:pregunta];
    
    self.btnNormal = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btnNormal.translatesAutoresizingMaskIntoConstraints = NO;
    self.btnNormal.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
    self.btnNormal.layer.cornerRadius = 14.0;
    self.btnNormal.layer.borderWidth = 1.5;
    self.btnNormal.layer.borderColor = red.CGColor;
    self.btnNormal.layer.shadowColor = red.CGColor;
    self.btnNormal.layer.shadowOpacity = 0.25;
    self.btnNormal.layer.shadowRadius = 10.0;
    self.btnNormal.layer.shadowOffset = CGSizeZero;
    [self.btnNormal setTitle:@"FREE FIRE\nNORMAL" forState:UIControlStateNormal];
    [self.btnNormal.titleLabel setFont:[UIFont boldSystemFontOfSize:14]];
    [self.btnNormal setTitleColor:white forState:UIControlStateNormal];
    [self.btnNormal.titleLabel setNumberOfLines:2];
    [self.btnNormal.titleLabel setTextAlignment:NSTextAlignmentCenter];
    [self.btnNormal addTarget:self action:@selector(btnNormalTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btnNormal];
    
    self.btnMax = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btnMax.translatesAutoresizingMaskIntoConstraints = NO;
    self.btnMax.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
    self.btnMax.layer.cornerRadius = 14.0;
    self.btnMax.layer.borderWidth = 1.5;
    self.btnMax.layer.borderColor = green.CGColor;
    self.btnMax.layer.shadowColor = green.CGColor;
    self.btnMax.layer.shadowOpacity = 0.25;
    self.btnMax.layer.shadowRadius = 10.0;
    self.btnMax.layer.shadowOffset = CGSizeZero;
    [self.btnMax setTitle:@"FREE FIRE\nMAX" forState:UIControlStateNormal];
    [self.btnMax.titleLabel setFont:[UIFont boldSystemFontOfSize:14]];
    [self.btnMax setTitleColor:white forState:UIControlStateNormal];
    [self.btnMax.titleLabel setNumberOfLines:2];
    [self.btnMax.titleLabel setTextAlignment:NSTextAlignmentCenter];
    [self.btnMax addTarget:self action:@selector(btnMaxTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btnMax];
    
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
        
        [pregunta.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [pregunta.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:50],
        [pregunta.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
        [pregunta.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.btnNormal.topAnchor constraintEqualToAnchor:pregunta.bottomAnchor constant:40],
        [self.btnNormal.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-8],
        [self.btnNormal.widthAnchor constraintEqualToConstant:140],
        [self.btnNormal.heightAnchor constraintEqualToConstant:80],
        
        [self.btnMax.topAnchor constraintEqualToAnchor:pregunta.bottomAnchor constant:40],
        [self.btnMax.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:8],
        [self.btnMax.widthAnchor constraintEqualToConstant:140],
        [self.btnMax.heightAnchor constraintEqualToConstant:80],
    ]];
}

#pragma mark - Acciones de botones

- (void)btnNormalTapped {
    // Guardar el bundle ID y cambiar a la pestaña Explorar
    [[NSUserDefaults standardUserDefaults] setObject:@"com.dts.freefireth" forKey:@"AutoOpenBundleID"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.tabBarController.selectedIndex = 1;
}

- (void)btnMaxTapped {
    // Guardar el bundle ID y cambiar a la pestaña Explorar
    [[NSUserDefaults standardUserDefaults] setObject:@"com.dts.freefiremax" forKey:@"AutoOpenBundleID"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.tabBarController.selectedIndex = 1;
}

@end
