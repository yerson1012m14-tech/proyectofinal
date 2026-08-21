#import "SettingsViewController.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) NSLayoutConstraint *langOptionsHeight;
@property (nonatomic, strong) NSLayoutConstraint *customOptionsHeight;
@property (nonatomic, assign) BOOL langExpanded;
@property (nonatomic, assign) BOOL customExpanded;
@property (nonatomic, strong) UIButton *langChevron;
@property (nonatomic, strong) UIButton *customChevron;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1.0];
    self.langExpanded = YES;
    self.customExpanded = NO;
    [self setupUI];
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
    
    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.text = @"Configuración";
    header.textColor = muted;
    header.font = [UIFont systemFontOfSize:13];
    header.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:header];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [closeBtn setTintColor:muted];
    [closeBtn addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeBtn];
    
    // ===== SECCIÓN IDIOMA =====
    UIView *langCard = [[UIView alloc] init];
    langCard.translatesAutoresizingMaskIntoConstraints = NO;
    langCard.backgroundColor = cardBg;
    langCard.layer.cornerRadius = 16;
    [self.contentView addSubview:langCard];
    
    UIImageView *langIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    langIcon.translatesAutoresizingMaskIntoConstraints = NO;
    langIcon.tintColor = red;
    [langCard addSubview:langIcon];
    
    UILabel *langTitle = [[UILabel alloc] init];
    langTitle.translatesAutoresizingMaskIntoConstraints = NO;
    langTitle.text = @"IDIOMA";
    langTitle.textColor = white;
    langTitle.font = [UIFont boldSystemFontOfSize:14];
    [langCard addSubview:langTitle];
    
    UILabel *langSub = [[UILabel alloc] init];
    langSub.translatesAutoresizingMaskIntoConstraints = NO;
    langSub.text = @"Selecciona tu idioma";
    langSub.textColor = muted;
    langSub.font = [UIFont systemFontOfSize:12];
    [langCard addSubview:langSub];
    
    self.langChevron = [UIButton buttonWithType:UIButtonTypeCustom];
    self.langChevron.translatesAutoresizingMaskIntoConstraints = NO;
    [self.langChevron setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    [self.langChevron setTintColor:red];
    [self.langChevron addTarget:self action:@selector(toggleLang) forControlEvents:UIControlEventTouchUpInside];
    [langCard addSubview:self.langChevron];
    
    UIView *langOptions = [[UIView alloc] init];
    langOptions.translatesAutoresizingMaskIntoConstraints = NO;
    [langCard addSubview:langOptions];
    
    NSArray *langs = @[@"Español", @"English", @"Português"];
    NSArray *langSubs = @[@"Spanish", @"English", @"Portuguese"];
    NSArray *flags = @[@"🇸", @"🇺", @"🇧🇷"];
    
    for (int i = 0; i < 3; i++) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.tag = 200 + i;
        [langOptions addSubview:row];
        
        UILabel *flag = [[UILabel alloc] init];
        flag.translatesAutoresizingMaskIntoConstraints = NO;
        flag.text = flags[i];
        flag.font = [UIFont systemFontOfSize:18];
        [row addSubview:flag];
        
        UILabel *lt = [[UILabel alloc] init];
        lt.translatesAutoresizingMaskIntoConstraints = NO;
        lt.text = langs[i];
        lt.textColor = white;
        lt.font = [UIFont systemFontOfSize:15];
        [row addSubview:lt];
        
        UILabel *ls = [[UILabel alloc] init];
        ls.translatesAutoresizingMaskIntoConstraints = NO;
        ls.text = langSubs[i];
        ls.textColor = muted;
        ls.font = [UIFont systemFontOfSize:11];
        [row addSubview:ls];
        
        UIButton *radio = [UIButton buttonWithType:UIButtonTypeCustom];
        radio.translatesAutoresizingMaskIntoConstraints = NO;
        radio.tag = 300 + i;
        [radio setImage:[UIImage systemImageNamed:(i == self.selectedLanguage ? @"largecircle.fill.circle" : @"circle")] forState:UIControlStateNormal];
        [radio setTintColor:(i == self.selectedLanguage ? red : muted)];
        [radio addTarget:self action:@selector(selectLang:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:radio];
        
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:langOptions.topAnchor constant:(i * 52)],
            [row.leadingAnchor constraintEqualToAnchor:langOptions.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:langOptions.trailingAnchor],
            [row.heightAnchor constraintEqualToConstant:52],
            [flag.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [flag.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [lt.leadingAnchor constraintEqualToAnchor:flag.trailingAnchor constant:12],
            [lt.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
            [ls.leadingAnchor constraintEqualToAnchor:lt.leadingAnchor],
            [ls.topAnchor constraintEqualToAnchor:lt.bottomAnchor constant:2],
            [radio.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
            [radio.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [radio.widthAnchor constraintEqualToConstant:22],
            [radio.heightAnchor constraintEqualToConstant:22],
        ]];
    }
    
    // ===== SECCIÓN PROTECCIÓN =====
    UIView *protCard = [[UIView alloc] init];
    protCard.translatesAutoresizingMaskIntoConstraints = NO;
    protCard.backgroundColor = cardBg;
    protCard.layer.cornerRadius = 16;
    [self.contentView addSubview:protCard];
    
    UIImageView *protIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"eye.slash"]];
    protIcon.translatesAutoresizingMaskIntoConstraints = NO;
    protIcon.tintColor = red;
    [protCard addSubview:protIcon];
    
    UILabel *protTitle = [[UILabel alloc] init];
    protTitle.translatesAutoresizingMaskIntoConstraints = NO;
    protTitle.text = @"PROTECCIÓN DE PANTALLA";
    protTitle.textColor = white;
    protTitle.font = [UIFont boldSystemFontOfSize:14];
    [protCard addSubview:protTitle];
    
    UILabel *protSub = [[UILabel alloc] init];
    protSub.translatesAutoresizingMaskIntoConstraints = NO;
    protSub.text = @"Ocultar contenido al grabar o capturar pantalla";
    protSub.textColor = muted;
    protSub.font = [UIFont systemFontOfSize:12];
    [protCard addSubview:protSub];
    
    UISwitch *protSwitch = [[UISwitch alloc] init];
    protSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    protSwitch.on = self.screenProtection;
    protSwitch.onTintColor = red;
    [protSwitch addTarget:self action:@selector(toggleProt:) forControlEvents:UIControlEventValueChanged];
    [protCard addSubview:protSwitch];
    
    UILabel *protDesc = [[UILabel alloc] init];
    protDesc.translatesAutoresizingMaskIntoConstraints = NO;
    protDesc.text = @"Cuando esta opción esté activada, la pantalla se volverá negra al detectar una captura o grabación.";
    protDesc.textColor = muted;
    protDesc.font = [UIFont systemFontOfSize:11];
    protDesc.numberOfLines = 0;
    [protCard addSubview:protDesc];
    
    // ===== SECCIÓN PERSONALIZACIÓN =====
    UIView *customCard = [[UIView alloc] init];
    customCard.translatesAutoresizingMaskIntoConstraints = NO;
    customCard.backgroundColor = cardBg;
    customCard.layer.cornerRadius = 16;
    [self.contentView addSubview:customCard];
    
    UIImageView *customIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"paintbrush"]];
    customIcon.translatesAutoresizingMaskIntoConstraints = NO;
    customIcon.tintColor = red;
    [customCard addSubview:customIcon];
    
    UILabel *customTitle = [[UILabel alloc] init];
    customTitle.translatesAutoresizingMaskIntoConstraints = NO;
    customTitle.text = @"PERSONALIZACIÓN";
    customTitle.textColor = white;
    customTitle.font = [UIFont boldSystemFontOfSize:14];
    [customCard addSubview:customTitle];
    
    UILabel *customSub = [[UILabel alloc] init];
    customSub.translatesAutoresizingMaskIntoConstraints = NO;
    customSub.text = @"Ajusta el estilo de la aplicación";
    customSub.textColor = muted;
    customSub.font = [UIFont systemFontOfSize:12];
    [customCard addSubview:customSub];
    
    self.customChevron = [UIButton buttonWithType:UIButtonTypeCustom];
    self.customChevron.translatesAutoresizingMaskIntoConstraints = NO;
    [self.customChevron setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    [self.customChevron setTintColor:red];
    [self.customChevron addTarget:self action:@selector(toggleCustom) forControlEvents:UIControlEventTouchUpInside];
    [customCard addSubview:self.customChevron];
    
    UIView *customOptions = [[UIView alloc] init];
    customOptions.translatesAutoresizingMaskIntoConstraints = NO;
    [customCard addSubview:customOptions];
    
    UILabel *bgLabel = [[UILabel alloc] init];
    bgLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bgLabel.text = @"Color del fondo";
    bgLabel.textColor = white;
    bgLabel.font = [UIFont systemFontOfSize:14];
    [customOptions addSubview:bgLabel];
    
    UILabel *bgSubLabel = [[UILabel alloc] init];
    bgSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bgSubLabel.text = @"Selecciona el color del fondo";
    bgSubLabel.textColor = muted;
    bgSubLabel.font = [UIFont systemFontOfSize:11];
    [customOptions addSubview:bgSubLabel];
    
    NSArray *bgColors = @[
        [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0],
        [UIColor colorWithWhite:0.20 alpha:1.0],
        [UIColor colorWithRed:0.10 green:0.30 blue:0.70 alpha:1.0],
        [UIColor colorWithRed:0.50 green:0.10 blue:0.70 alpha:1.0]
    ];
    
    for (int i = 0; i < 4; i++) {
        UIButton *colorBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        colorBtn.translatesAutoresizingMaskIntoConstraints = NO;
        colorBtn.tag = 400 + i;
        colorBtn.backgroundColor = bgColors[i];
        colorBtn.layer.cornerRadius = 14;
        colorBtn.layer.borderWidth = (i == self.selectedBgColor) ? 2.5 : 0;
        colorBtn.layer.borderColor = white.CGColor;
        [colorBtn addTarget:self action:@selector(selectBg:) forControlEvents:UIControlEventTouchUpInside];
        [customOptions addSubview:colorBtn];
        
        // Constraint individual (no en array con loop)
        [colorBtn.topAnchor constraintEqualToAnchor:bgSubLabel.bottomAnchor constant:10].active = YES;
        [colorBtn.leadingAnchor constraintEqualToAnchor:customOptions.leadingAnchor constant:(i * 44)].active = YES;
        [colorBtn.widthAnchor constraintEqualToConstant:28].active = YES;
        [colorBtn.heightAnchor constraintEqualToConstant:28].active = YES;
    }
    
    UILabel *txtLabel = [[UILabel alloc] init];
    txtLabel.translatesAutoresizingMaskIntoConstraints = NO;
    txtLabel.text = @"Color del texto";
    txtLabel.textColor = white;
    txtLabel.font = [UIFont systemFontOfSize:14];
    [customOptions addSubview:txtLabel];
    
    UILabel *txtSubLabel = [[UILabel alloc] init];
    txtSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    txtSubLabel.text = @"Selecciona el color del texto";
    txtSubLabel.textColor = muted;
    txtSubLabel.font = [UIFont systemFontOfSize:11];
    [customOptions addSubview:txtSubLabel];
    
    NSArray *txtColors = @[
        [UIColor whiteColor],
        [UIColor colorWithWhite:0.60 alpha:1.0],
        [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0],
        [UIColor colorWithRed:0.20 green:0.90 blue:0.30 alpha:1.0]
    ];
    
    for (int i = 0; i < 4; i++) {
        UIButton *colorBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        colorBtn.translatesAutoresizingMaskIntoConstraints = NO;
        colorBtn.tag = 500 + i;
        colorBtn.backgroundColor = txtColors[i];
        colorBtn.layer.cornerRadius = 14;
        colorBtn.layer.borderWidth = (i == self.selectedTextColor) ? 2.5 : 0;
        colorBtn.layer.borderColor = [UIColor colorWithWhite:0.30 alpha:1.0].CGColor;
        [colorBtn addTarget:self action:@selector(selectTxt:) forControlEvents:UIControlEventTouchUpInside];
        [customOptions addSubview:colorBtn];
        
        [colorBtn.topAnchor constraintEqualToAnchor:txtSubLabel.bottomAnchor constant:10].active = YES;
        [colorBtn.leadingAnchor constraintEqualToAnchor:customOptions.leadingAnchor constant:(i * 44)].active = YES;
        [colorBtn.widthAnchor constraintEqualToConstant:28].active = YES;
        [colorBtn.heightAnchor constraintEqualToConstant:28].active = YES;
    }
    
    // Vista previa
    UIView *previewCard = [[UIView alloc] init];
    previewCard.translatesAutoresizingMaskIntoConstraints = NO;
    previewCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
    previewCard.layer.cornerRadius = 16;
    [self.contentView addSubview:previewCard];
    
    UILabel *prevTitle = [[UILabel alloc] init];
    prevTitle.translatesAutoresizingMaskIntoConstraints = NO;
    prevTitle.text = @"VISTA PREVIA";
    prevTitle.textColor = muted;
    prevTitle.font = [UIFont boldSystemFontOfSize:10];
    [previewCard addSubview:prevTitle];
    
    UILabel *prevLogo = [[UILabel alloc] init];
    prevLogo.translatesAutoresizingMaskIntoConstraints = NO;
    prevLogo.text = @"XITFORGE";
    prevLogo.textColor = white;
    prevLogo.font = [UIFont boldSystemFontOfSize:26];
    prevLogo.textAlignment = NSTextAlignmentCenter;
    [previewCard addSubview:prevLogo];
    
    UILabel *prevSample = [[UILabel alloc] init];
    prevSample.translatesAutoresizingMaskIntoConstraints = NO;
    prevSample.text = @"Este es el texto de ejemplo";
    prevSample.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    prevSample.font = [UIFont systemFontOfSize:13];
    prevSample.textAlignment = NSTextAlignmentCenter;
    [previewCard addSubview:prevSample];
    
    // ===== CONSTRAINTS PRINCIPALES =====
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
        
        [header.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [header.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        [closeBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:24],
        [closeBtn.heightAnchor constraintEqualToConstant:24],
        
        [langCard.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:16],
        [langCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [langCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [langIcon.topAnchor constraintEqualToAnchor:langCard.topAnchor constant:16],
        [langIcon.leadingAnchor constraintEqualToAnchor:langCard.leadingAnchor constant:16],
        [langIcon.widthAnchor constraintEqualToConstant:22],
        [langIcon.heightAnchor constraintEqualToConstant:22],
        
        [langTitle.leadingAnchor constraintEqualToAnchor:langIcon.trailingAnchor constant:10],
        [langTitle.topAnchor constraintEqualToAnchor:langIcon.topAnchor],
        
        [langSub.leadingAnchor constraintEqualToAnchor:langTitle.leadingAnchor],
        [langSub.topAnchor constraintEqualToAnchor:langTitle.bottomAnchor constant:2],
        
        [self.langChevron.trailingAnchor constraintEqualToAnchor:langCard.trailingAnchor constant:-16],
        [self.langChevron.centerYAnchor constraintEqualToAnchor:langIcon.centerYAnchor],
        [self.langChevron.widthAnchor constraintEqualToConstant:20],
        [self.langChevron.heightAnchor constraintEqualToConstant:20],
        
        [langOptions.topAnchor constraintEqualToAnchor:langIcon.bottomAnchor constant:12],
        [langOptions.leadingAnchor constraintEqualToAnchor:langCard.leadingAnchor],
        [langOptions.trailingAnchor constraintEqualToAnchor:langCard.trailingAnchor],
        [langOptions.bottomAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:-16],
        
        [protCard.topAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:12],
        [protCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [protCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [protIcon.topAnchor constraintEqualToAnchor:protCard.topAnchor constant:16],
        [protIcon.leadingAnchor constraintEqualToAnchor:protCard.leadingAnchor constant:16],
        [protIcon.widthAnchor constraintEqualToConstant:22],
        [protIcon.heightAnchor constraintEqualToConstant:22],
        
        [protTitle.leadingAnchor constraintEqualToAnchor:protIcon.trailingAnchor constant:10],
        [protTitle.topAnchor constraintEqualToAnchor:protIcon.topAnchor],
        
        [protSub.leadingAnchor constraintEqualToAnchor:protTitle.leadingAnchor],
        [protSub.topAnchor constraintEqualToAnchor:protTitle.bottomAnchor constant:2],
        
        [protSwitch.trailingAnchor constraintEqualToAnchor:protCard.trailingAnchor constant:-16],
        [protSwitch.centerYAnchor constraintEqualToAnchor:protIcon.centerYAnchor],
        
        [protDesc.topAnchor constraintEqualToAnchor:protSwitch.bottomAnchor constant:12],
        [protDesc.leadingAnchor constraintEqualToAnchor:protCard.leadingAnchor constant:16],
        [protDesc.trailingAnchor constraintEqualToAnchor:protCard.trailingAnchor constant:-16],
        [protDesc.bottomAnchor constraintEqualToAnchor:protCard.bottomAnchor constant:-16],
        
        [customCard.topAnchor constraintEqualToAnchor:protCard.bottomAnchor constant:12],
        [customCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [customCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [customIcon.topAnchor constraintEqualToAnchor:customCard.topAnchor constant:16],
        [customIcon.leadingAnchor constraintEqualToAnchor:customCard.leadingAnchor constant:16],
        [customIcon.widthAnchor constraintEqualToConstant:22],
        [customIcon.heightAnchor constraintEqualToConstant:22],
        
        [customTitle.leadingAnchor constraintEqualToAnchor:customIcon.trailingAnchor constant:10],
        [customTitle.topAnchor constraintEqualToAnchor:customIcon.topAnchor],
        
        [customSub.leadingAnchor constraintEqualToAnchor:customTitle.leadingAnchor],
        [customSub.topAnchor constraintEqualToAnchor:customTitle.bottomAnchor constant:2],
        
        [self.customChevron.trailingAnchor constraintEqualToAnchor:customCard.trailingAnchor constant:-16],
        [self.customChevron.centerYAnchor constraintEqualToAnchor:customIcon.centerYAnchor],
        [self.customChevron.widthAnchor constraintEqualToConstant:20],
        [self.customChevron.heightAnchor constraintEqualToConstant:20],
        
        [customOptions.topAnchor constraintEqualToAnchor:customIcon.bottomAnchor constant:12],
        [customOptions.leadingAnchor constraintEqualToAnchor:customCard.leadingAnchor constant:16],
        [customOptions.trailingAnchor constraintEqualToAnchor:customCard.trailingAnchor constant:-16],
        [customOptions.bottomAnchor constraintEqualToAnchor:customCard.bottomAnchor constant:-16],
        
        [bgLabel.topAnchor constraintEqualToAnchor:customOptions.topAnchor],
        [bgLabel.leadingAnchor constraintEqualToAnchor:customOptions.leadingAnchor],
        
        [bgSubLabel.topAnchor constraintEqualToAnchor:bgLabel.bottomAnchor constant:2],
        [bgSubLabel.leadingAnchor constraintEqualToAnchor:bgLabel.leadingAnchor],
        
        [txtLabel.topAnchor constraintEqualToAnchor:bgSubLabel.bottomAnchor constant:16],
        [txtLabel.leadingAnchor constraintEqualToAnchor:customOptions.leadingAnchor],
        
        [txtSubLabel.topAnchor constraintEqualToAnchor:txtLabel.bottomAnchor constant:2],
        [txtSubLabel.leadingAnchor constraintEqualToAnchor:txtLabel.leadingAnchor],
        
        [previewCard.topAnchor constraintEqualToAnchor:customCard.bottomAnchor constant:12],
        [previewCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [previewCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [previewCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-20],
        [previewCard.heightAnchor constraintEqualToConstant:110],
        
        [prevTitle.topAnchor constraintEqualToAnchor:previewCard.topAnchor constant:12],
        [prevTitle.leadingAnchor constraintEqualToAnchor:previewCard.leadingAnchor constant:16],
        
        [prevLogo.centerXAnchor constraintEqualToAnchor:previewCard.centerXAnchor],
        [prevLogo.centerYAnchor constraintEqualToAnchor:previewCard.centerYAnchor constant:-8],
        
        [prevSample.centerXAnchor constraintEqualToAnchor:previewCard.centerXAnchor],
        [prevSample.topAnchor constraintEqualToAnchor:prevLogo.bottomAnchor constant:6],
    ]];
    
    // Alturas dinámicas
    self.langOptionsHeight = [langOptions.heightAnchor constraintEqualToConstant:(self.langExpanded ? 156 : 0)];
    self.langOptionsHeight.active = YES;
    
    self.customOptionsHeight = [customOptions.heightAnchor constraintEqualToConstant:(self.customExpanded ? 140 : 0)];
    self.customOptionsHeight.active = YES;
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

- (void)toggleCustom {
    self.customExpanded = !self.customExpanded;
    [UIView animateWithDuration:0.3 animations:^{
        self.customOptionsHeight.constant = self.customExpanded ? 140 : 0;
        [self.view layoutIfNeeded];
    }];
    [self.customChevron setImage:[UIImage systemImageNamed:(self.customExpanded ? @"chevron.up" : @"chevron.down")] forState:UIControlStateNormal];
}

- (void)selectLang:(UIButton *)btn {
    NSInteger idx = btn.tag - 300;
    self.selectedLanguage = idx;
    UIColor *red = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    UIColor *muted = [UIColor colorWithWhite:0.50 alpha:1.0];
    for (int i = 0; i < 3; i++) {
        UIButton *r = [self.view viewWithTag:300 + i];
        [r setImage:[UIImage systemImageNamed:(i == idx ? @"largecircle.fill.circle" : @"circle")] forState:UIControlStateNormal];
        [r setTintColor:(i == idx ? red : muted)];
    }
    [self saveAndNotify];
}

- (void)toggleProt:(UISwitch *)sw {
    self.screenProtection = sw.isOn;
    [self saveAndNotify];
}

- (void)selectBg:(UIButton *)btn {
    NSInteger idx = btn.tag - 400;
    self.selectedBgColor = idx;
    for (int i = 0; i < 4; i++) {
        UIButton *b = [self.view viewWithTag:400 + i];
        b.layer.borderWidth = (i == idx) ? 2.5 : 0;
    }
    [self saveAndNotify];
}

- (void)selectTxt:(UIButton *)btn {
    NSInteger idx = btn.tag - 500;
    self.selectedTextColor = idx;
    for (int i = 0; i < 4; i++) {
        UIButton *b = [self.view viewWithTag:500 + i];
        b.layer.borderWidth = (i == idx) ? 2.5 : 0;
    }
    [self saveAndNotify];
}

- (void)saveAndNotify {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:self.selectedLanguage forKey:@"selectedLanguage"];
    [d setBool:self.screenProtection forKey:@"screenProtection"];
    [d setInteger:self.selectedBgColor forKey:@"selectedBgColor"];
    [d setInteger:self.selectedTextColor forKey:@"selectedTextColor"];
    [d synchronize];
    if (self.onSettingsChanged) self.onSettingsChanged();
}

@end
