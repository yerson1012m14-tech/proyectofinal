#import "SettingsViewController.h"
#import "Translations.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) NSLayoutConstraint *langOptionsHeight;
@property (nonatomic, strong) NSLayoutConstraint *protOptionsHeight;
@property (nonatomic, assign) BOOL langExpanded;
@property (nonatomic, assign) BOOL protExpanded;
@property (nonatomic, strong) UIButton *langChevron;
@property (nonatomic, strong) UIButton *protChevron;
@property (nonatomic, strong) UIView *langOptions;
@property (nonatomic, strong) UIView *protOptions;
@property (nonatomic, strong) UISwitch *protSwitch;
@property (nonatomic, strong) UILabel *langTitle;
@property (nonatomic, strong) UILabel *langSub;
@property (nonatomic, strong) UILabel *protTitle;
@property (nonatomic, strong) UILabel *protSub;
@property (nonatomic, strong) UILabel *header;
@property (nonatomic, strong) NSMutableArray *langLabels;
@property (nonatomic, strong) NSMutableArray *langSubLabels;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1.0];
    self.langExpanded = YES;
    self.protExpanded = YES;
    self.langLabels = [NSMutableArray array];
    self.langSubLabels = [NSMutableArray array];
    [self setupUI];
    [self updateTexts];
}

- (void)setupUI {
    UIColor *cardBg = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    UIColor *white = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *muted = [UIColor colorWithWhite:0.50 alpha:1.0];
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];
    
    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];
    
    self.header = [[UILabel alloc] init];
    self.header.translatesAutoresizingMaskIntoConstraints = NO;
    self.header.textColor = muted;
    self.header.font = [UIFont systemFontOfSize:13];
    self.header.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.header];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [closeBtn setTintColor:muted];
    [closeBtn addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeBtn];
    
    // SECCIÓN IDIOMA
    UIView *langCard = [[UIView alloc] init];
    langCard.translatesAutoresizingMaskIntoConstraints = NO;
    langCard.backgroundColor = cardBg;
    langCard.layer.cornerRadius = 16;
    langCard.clipsToBounds = YES;
    [self.contentView addSubview:langCard];
    
    UIImageView *langIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    langIcon.translatesAutoresizingMaskIntoConstraints = NO;
    langIcon.tintColor = red;
    [langCard addSubview:langIcon];
    
    self.langTitle = [[UILabel alloc] init];
    self.langTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.langTitle.textColor = white;
    self.langTitle.font = [UIFont boldSystemFontOfSize:14];
    [langCard addSubview:self.langTitle];
    
    self.langSub = [[UILabel alloc] init];
    self.langSub.translatesAutoresizingMaskIntoConstraints = NO;
    self.langSub.textColor = muted;
    self.langSub.font = [UIFont systemFontOfSize:12];
    [langCard addSubview:self.langSub];
    
    self.langChevron = [UIButton buttonWithType:UIButtonTypeCustom];
    self.langChevron.translatesAutoresizingMaskIntoConstraints = NO;
    [self.langChevron setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    [self.langChevron setTintColor:red];
    [self.langChevron addTarget:self action:@selector(toggleLang) forControlEvents:UIControlEventTouchUpInside];
    [langCard addSubview:self.langChevron];
    
    self.langOptions = [[UIView alloc] init];
    self.langOptions.translatesAutoresizingMaskIntoConstraints = NO;
    self.langOptions.clipsToBounds = YES;
    self.langOptions.layer.masksToBounds = YES;
    [langCard addSubview:self.langOptions];
    
    NSArray *countryCodes = @[@"ES", @"EN", @"PT"];
    NSArray *flagColors = @[
        [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0],
        [UIColor colorWithRed:0.10 green:0.30 blue:0.70 alpha:1.0],
        [UIColor colorWithRed:0.10 green:0.70 blue:0.30 alpha:1.0]
    ];
    
    for (int i = 0; i < 3; i++) {
        UIButton *rowBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        rowBtn.translatesAutoresizingMaskIntoConstraints = NO;
        rowBtn.tag = 200 + i;
        [rowBtn addTarget:self action:@selector(selectLang:) forControlEvents:UIControlEventTouchUpInside];
        [self.langOptions addSubview:rowBtn];
        
        UIView *flagCircle = [[UIView alloc] init];
        flagCircle.translatesAutoresizingMaskIntoConstraints = NO;
        flagCircle.backgroundColor = flagColors[i];
        flagCircle.layer.cornerRadius = 14;
        [rowBtn addSubview:flagCircle];
        
        UILabel *flagLabel = [[UILabel alloc] init];
        flagLabel.translatesAutoresizingMaskIntoConstraints = NO;
        flagLabel.text = countryCodes[i];
        flagLabel.textColor = white;
        flagLabel.font = [UIFont boldSystemFontOfSize:11];
        flagLabel.textAlignment = NSTextAlignmentCenter;
        [flagCircle addSubview:flagLabel];
        
        UILabel *lt = [[UILabel alloc] init];
        lt.translatesAutoresizingMaskIntoConstraints = NO;
        lt.textColor = white;
        lt.font = [UIFont systemFontOfSize:15];
        [rowBtn addSubview:lt];
        [self.langLabels addObject:lt];
        
        UIButton *radio = [UIButton buttonWithType:UIButtonTypeCustom];
        radio.translatesAutoresizingMaskIntoConstraints = NO;
        radio.tag = 300 + i;
        radio.userInteractionEnabled = NO;
        [radio setImage:[UIImage systemImageNamed:(i == self.selectedLanguage ? @"largecircle.fill.circle" : @"circle")] forState:UIControlStateNormal];
        [radio setTintColor:(i == self.selectedLanguage ? red : muted)];
        [rowBtn addSubview:radio];
        
        [NSLayoutConstraint activateConstraints:@[
            [rowBtn.topAnchor constraintEqualToAnchor:self.langOptions.topAnchor constant:(i * 52)],
            [rowBtn.leadingAnchor constraintEqualToAnchor:self.langOptions.leadingAnchor],
            [rowBtn.trailingAnchor constraintEqualToAnchor:self.langOptions.trailingAnchor],
            [rowBtn.heightAnchor constraintEqualToConstant:52],
            [flagCircle.leadingAnchor constraintEqualToAnchor:rowBtn.leadingAnchor constant:16],
            [flagCircle.centerYAnchor constraintEqualToAnchor:rowBtn.centerYAnchor],
            [flagCircle.widthAnchor constraintEqualToConstant:28],
            [flagCircle.heightAnchor constraintEqualToConstant:28],
            [flagLabel.centerXAnchor constraintEqualToAnchor:flagCircle.centerXAnchor],
            [flagLabel.centerYAnchor constraintEqualToAnchor:flagCircle.centerYAnchor],
            [lt.leadingAnchor constraintEqualToAnchor:flagCircle.trailingAnchor constant:12],
            [lt.centerYAnchor constraintEqualToAnchor:rowBtn.centerYAnchor],
            [radio.trailingAnchor constraintEqualToAnchor:rowBtn.trailingAnchor constant:-16],
            [radio.centerYAnchor constraintEqualToAnchor:rowBtn.centerYAnchor],
            [radio.widthAnchor constraintEqualToConstant:22],
            [radio.heightAnchor constraintEqualToConstant:22],
        ]];
    }
    
    // SECCIÓN PROTECCIÓN
    UIView *protCard = [[UIView alloc] init];
    protCard.translatesAutoresizingMaskIntoConstraints = NO;
    protCard.backgroundColor = cardBg;
    protCard.layer.cornerRadius = 16;
    protCard.clipsToBounds = YES;
    [self.contentView addSubview:protCard];
    
    UIImageView *protIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"eye.slash"]];
    protIcon.translatesAutoresizingMaskIntoConstraints = NO;
    protIcon.tintColor = red;
    [protCard addSubview:protIcon];
    
    self.protTitle = [[UILabel alloc] init];
    self.protTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.protTitle.textColor = white;
    self.protTitle.font = [UIFont boldSystemFontOfSize:14];
    [protCard addSubview:self.protTitle];
    
    self.protSub = [[UILabel alloc] init];
    self.protSub.translatesAutoresizingMaskIntoConstraints = NO;
    self.protSub.textColor = muted;
    self.protSub.font = [UIFont systemFontOfSize:12];
    [protCard addSubview:self.protSub];
    
    self.protChevron = [UIButton buttonWithType:UIButtonTypeCustom];
    self.protChevron.translatesAutoresizingMaskIntoConstraints = NO;
    [self.protChevron setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    [self.protChevron setTintColor:red];
    [self.protChevron addTarget:self action:@selector(toggleProt) forControlEvents:UIControlEventTouchUpInside];
    [protCard addSubview:self.protChevron];
    
    self.protOptions = [[UIView alloc] init];
    self.protOptions.translatesAutoresizingMaskIntoConstraints = NO;
    self.protOptions.clipsToBounds = YES;
    self.protOptions.layer.masksToBounds = YES;
    [protCard addSubview:self.protOptions];
    
    self.protSwitch = [[UISwitch alloc] init];
    self.protSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.protSwitch.on = self.screenProtection;
    self.protSwitch.onTintColor = red;
    [self.protSwitch addTarget:self action:@selector(toggleProtSwitch:) forControlEvents:UIControlEventValueChanged];
    [self.protOptions addSubview:self.protSwitch];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.protOptions.topAnchor constraintEqualToAnchor:protIcon.bottomAnchor constant:12],
        [self.protOptions.leadingAnchor constraintEqualToAnchor:protCard.leadingAnchor],
        [self.protOptions.trailingAnchor constraintEqualToAnchor:protCard.trailingAnchor],
        [self.protOptions.bottomAnchor constraintEqualToAnchor:protCard.bottomAnchor constant:-16],
        [self.protSwitch.centerXAnchor constraintEqualToAnchor:self.protOptions.centerXAnchor],
        [self.protSwitch.topAnchor constraintEqualToAnchor:self.protOptions.topAnchor constant:16],
        [self.protSwitch.bottomAnchor constraintEqualToAnchor:self.protOptions.bottomAnchor constant:-16],
    ]];
    
    // CONSTRAINTS PRINCIPALES
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        
        [self.header.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.header.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        [closeBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:24],
        [closeBtn.heightAnchor constraintEqualToConstant:24],
        
        [langCard.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:16],
        [langCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [langCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [langIcon.topAnchor constraintEqualToAnchor:langCard.topAnchor constant:16],
        [langIcon.leadingAnchor constraintEqualToAnchor:langCard.leadingAnchor constant:16],
        [langIcon.widthAnchor constraintEqualToConstant:22],
        [langIcon.heightAnchor constraintEqualToConstant:22],
        
        [self.langTitle.leadingAnchor constraintEqualToAnchor:langIcon.trailingAnchor constant:10],
        [self.langTitle.topAnchor constraintEqualToAnchor:langIcon.topAnchor],
        
        [self.langSub.leadingAnchor constraintEqualToAnchor:self.langTitle.leadingAnchor],
        [self.langSub.topAnchor constraintEqualToAnchor:self.langTitle.bottomAnchor constant:2],
        
        [self.langChevron.trailingAnchor constraintEqualToAnchor:langCard.trailingAnchor constant:-16],
        [self.langChevron.centerYAnchor constraintEqualToAnchor:langIcon.centerYAnchor],
        [self.langChevron.widthAnchor constraintEqualToConstant:20],
        [self.langChevron.heightAnchor constraintEqualToConstant:20],
        
        [self.langOptions.topAnchor constraintEqualToAnchor:langIcon.bottomAnchor constant:12],
        [self.langOptions.leadingAnchor constraintEqualToAnchor:langCard.leadingAnchor],
        [self.langOptions.trailingAnchor constraintEqualToAnchor:langCard.trailingAnchor],
        [self.langOptions.bottomAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:-16],
        
        [protCard.topAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:12],
        [protCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [protCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [protCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-20],
        
        [protIcon.topAnchor constraintEqualToAnchor:protCard.topAnchor constant:16],
        [protIcon.leadingAnchor constraintEqualToAnchor:protCard.leadingAnchor constant:16],
        [protIcon.widthAnchor constraintEqualToConstant:22],
        [protIcon.heightAnchor constraintEqualToConstant:22],
        
        [self.protTitle.leadingAnchor constraintEqualToAnchor:protIcon.trailingAnchor constant:10],
        [self.protTitle.topAnchor constraintEqualToAnchor:protIcon.topAnchor],
        
        [self.protSub.leadingAnchor constraintEqualToAnchor:self.protTitle.leadingAnchor],
        [self.protSub.topAnchor constraintEqualToAnchor:self.protTitle.bottomAnchor constant:2],
        
        [self.protChevron.trailingAnchor constraintEqualToAnchor:protCard.trailingAnchor constant:-16],
        [self.protChevron.centerYAnchor constraintEqualToAnchor:protIcon.centerYAnchor],
        [self.protChevron.widthAnchor constraintEqualToConstant:20],
        [self.protChevron.heightAnchor constraintEqualToConstant:20],
    ]];
    
    self.langOptionsHeight = [self.langOptions.heightAnchor constraintEqualToConstant:(self.langExpanded ? 156 : 0)];
    self.langOptionsHeight.active = YES;
    
    self.protOptionsHeight = [self.protOptions.heightAnchor constraintEqualToConstant:(self.protExpanded ? 70 : 0)];
    self.protOptionsHeight.active = YES;
}

- (void)updateTexts {
    self.header.text = [Translations tr:@"settings"];
    self.langTitle.text = [Translations tr:@"language"];
    self.langSub.text = [Translations tr:@"select_language"];
    self.protTitle.text = [Translations tr:@"protection"];
    self.protSub.text = [Translations tr:@"protection_desc"];
    
    NSArray *langKeys = @[@"spanish", @"english", @"portuguese"];
    
    for (int i = 0; i < 3; i++) {
        UILabel *lt = self.langLabels[i];
        lt.text = [Translations tr:langKeys[i]];
    }
}

#pragma mark - Actions

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleLang {
    self.langExpanded = !self.langExpanded;
    [UIView animateWithDuration:0.3 animations:^{
        self.langOptionsHeight.constant = self.langExpanded ? 156 : 0;
        [self.view layoutIfNeeded];
    }];
    [self.langChevron setImage:[UIImage systemImageNamed:(self.langExpanded ? @"chevron.up" : @"chevron.down")] forState:UIControlStateNormal];
}

- (void)toggleProt {
    self.protExpanded = !self.protExpanded;
    [UIView animateWithDuration:0.3 animations:^{
        self.protOptionsHeight.constant = self.protExpanded ? 70 : 0;
        [self.view layoutIfNeeded];
    }];
    [self.protChevron setImage:[UIImage systemImageNamed:(self.protExpanded ? @"chevron.up" : @"chevron.down")] forState:UIControlStateNormal];
}

- (void)selectLang:(UIButton *)btn {
    NSInteger idx = btn.tag - 200;
    self.selectedLanguage = idx;
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    UIColor *muted = [UIColor colorWithWhite:0.50 alpha:1.0];
    for (int i = 0; i < 3; i++) {
        UIButton *r = [self.view viewWithTag:300 + i];
        [r setImage:[UIImage systemImageNamed:(i == idx ? @"largecircle.fill.circle" : @"circle")] forState:UIControlStateNormal];
        [r setTintColor:(i == idx ? red : muted)];
    }
    [Translations setLanguage:self.selectedLanguage];
    [self updateTexts];
    [self saveAndNotify];
}

- (void)toggleProtSwitch:(UISwitch *)sw {
    self.screenProtection = sw.isOn;
    [self saveAndNotify];
}

- (void)saveAndNotify {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:self.selectedLanguage forKey:@"selectedLanguage"];
    [d setBool:self.screenProtection forKey:@"screenProtection"];
    [d synchronize];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ProtectionChanged" object:nil];
    
    if (self.onSettingsChanged) self.onSettingsChanged();
}

@end
