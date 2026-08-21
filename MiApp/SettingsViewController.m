#import "SettingsViewController.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *languageSection;
@property (nonatomic, strong) UIView *protectionSection;
@property (nonatomic, strong) UIView *customizationSection;
@property (nonatomic, strong) UISwitch *protectionSwitch;
@property (nonatomic, assign) BOOL languageExpanded;
@property (nonatomic, assign) BOOL customizationExpanded;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1.0];
    self.languageExpanded = YES;
    self.customizationExpanded = NO;
    [self setupUI];
}

- (void)setupUI {
    // ScrollView
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];
    
    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];
    
    // Header
    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.text = @"Configuración";
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont boldSystemFontOfSize:20];
    header.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:header];
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    [closeButton setTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
    [closeButton addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeButton];
    
    // Sección Idioma
    [self setupLanguageSection];
    
    // Sección Protección
    [self setupProtectionSection];
    
    // Sección Personalización
    [self setupCustomizationSection];
    
    // Vista previa
    [self setupPreviewSection];
    
    // Constraints
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
        
        [header.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
        [header.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        
        [closeButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [closeButton.widthAnchor constraintEqualToConstant:28],
        [closeButton.heightAnchor constraintEqualToConstant:28],
    ]];
}

- (void)setupLanguageSection {
    self.languageSection = [[UIView alloc] init];
    self.languageSection.translatesAutoresizingMaskIntoConstraints = NO;
    self.languageSection.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    self.languageSection.layer.cornerRadius = 12;
    [self.contentView addSubview:self.languageSection];
    
    // Header de sección
    UIView *sectionHeader = [[UIView alloc] init];
    sectionHeader.translatesAutoresizingMaskIntoConstraints = NO;
    sectionHeader.backgroundColor = [UIColor clearColor];
    [self.languageSection addSubview:sectionHeader];
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    [sectionHeader addSubview:icon];
    
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"IDIOMA";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:14];
    [sectionHeader addSubview:title];
    
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Selecciona tu idioma";
    subtitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    subtitle.font = [UIFont systemFontOfSize:12];
    [sectionHeader addSubview:subtitle];
    
    UIButton *expandButton = [UIButton buttonWithType:UIButtonTypeCustom];
    expandButton.translatesAutoresizingMaskIntoConstraints = NO;
    [expandButton setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    [expandButton setTintColor:[UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0]];
    [expandButton addTarget:self action:@selector(toggleLanguage) forControlEvents:UIControlEventTouchUpInside];
    [sectionHeader addSubview:expandButton];
    
    // Opciones de idioma
    UIView *optionsContainer = [[UIView alloc] init];
    optionsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    optionsContainer.tag = 100;
    [self.languageSection addSubview:optionsContainer];
    
    NSArray *languages = @[@"Español", @"English", @"Português"];
    NSArray *subtitles = @[@"Spanish", @"English", @"Portuguese"];
    NSArray *flags = @[@"🇪", @"🇺🇸", @"🇷"];
    
    CGFloat yOffset = 0;
    for (int i = 0; i < 3; i++) {
        UIView *option = [[UIView alloc] init];
        option.translatesAutoresizingMaskIntoConstraints = NO;
        option.backgroundColor = [UIColor clearColor];
        option.tag = 200 + i;
        [optionsContainer addSubview:option];
        
        UILabel *flag = [[UILabel alloc] init];
        flag.translatesAutoresizingMaskIntoConstraints = NO;
        flag.text = flags[i];
        flag.font = [UIFont systemFontOfSize:20];
        [option addSubview:flag];
        
        UILabel *langTitle = [[UILabel alloc] init];
        langTitle.translatesAutoresizingMaskIntoConstraints = NO;
        langTitle.text = languages[i];
        langTitle.textColor = [UIColor whiteColor];
        langTitle.font = [UIFont systemFontOfSize:15];
        [option addSubview:langTitle];
        
        UILabel *langSubtitle = [[UILabel alloc] init];
        langSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
        langSubtitle.text = subtitles[i];
        langSubtitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        langSubtitle.font = [UIFont systemFontOfSize:12];
        [option addSubview:langSubtitle];
        
        UIButton *radioButton = [UIButton buttonWithType:UIButtonTypeCustom];
        radioButton.translatesAutoresizingMaskIntoConstraints = NO;
        radioButton.tag = 300 + i;
        [radioButton setImage:[UIImage systemImageNamed:(i == self.selectedLanguage ? @"largecircle.fill.circle" : @"circle")] forState:UIControlStateNormal];
        [radioButton setTintColor:(i == self.selectedLanguage ? [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0] : [UIColor colorWithWhite:0.4 alpha:1.0])];
        [radioButton addTarget:self action:@selector(selectLanguage:) forControlEvents:UIControlEventTouchUpInside];
        [option addSubview:radioButton];
        
        [NSLayoutConstraint activateConstraints:@[
            [option.topAnchor constraintEqualToAnchor:optionsContainer.topAnchor constant:yOffset],
            [option.leadingAnchor constraintEqualToAnchor:optionsContainer.leadingAnchor constant:16],
            [option.trailingAnchor constraintEqualToAnchor:optionsContainer.trailingAnchor constant:-16],
            [option.heightAnchor constraintEqualToConstant:50],
            
            [flag.leadingAnchor constraintEqualToAnchor:option.leadingAnchor],
            [flag.centerYAnchor constraintEqualToAnchor:option.centerYAnchor],
            [flag.widthAnchor constraintEqualToConstant:30],
            
            [langTitle.leadingAnchor constraintEqualToAnchor:flag.trailingAnchor constant:12],
            [langTitle.topAnchor constraintEqualToAnchor:option.topAnchor constant:8],
            
            [langSubtitle.leadingAnchor constraintEqualToAnchor:langTitle.leadingAnchor],
            [langSubtitle.topAnchor constraintEqualToAnchor:langTitle.bottomAnchor constant:2],
            
            [radioButton.trailingAnchor constraintEqualToAnchor:option.trailingAnchor],
            [radioButton.centerYAnchor constraintEqualToAnchor:option.centerYAnchor],
            [radioButton.widthAnchor constraintEqualToConstant:24],
            [radioButton.heightAnchor constraintEqualToConstant:24],
        ]];
        
        yOffset += 50;
    }
    
    [NSLayoutConstraint activateConstraints:@[
        [self.languageSection.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:80],
        [self.languageSection.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.languageSection.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [sectionHeader.topAnchor constraintEqualToAnchor:self.languageSection.topAnchor constant:16],
        [sectionHeader.leadingAnchor constraintEqualToAnchor:self.languageSection.leadingAnchor constant:16],
        [sectionHeader.trailingAnchor constraintEqualToAnchor:self.languageSection.trailingAnchor constant:-16],
        [sectionHeader.heightAnchor constraintEqualToConstant:50],
        
        [icon.leadingAnchor constraintEqualToAnchor:sectionHeader.leadingAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:sectionHeader.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:sectionHeader.topAnchor constant:8],
        
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        
        [expandButton.trailingAnchor constraintEqualToAnchor:sectionHeader.trailingAnchor],
        [expandButton.centerYAnchor constraintEqualToAnchor:sectionHeader.centerYAnchor],
        [expandButton.widthAnchor constraintEqualToConstant:24],
        [expandButton.heightAnchor constraintEqualToConstant:24],
        
        [optionsContainer.topAnchor constraintEqualToAnchor:sectionHeader.bottomAnchor constant:8],
        [optionsContainer.leadingAnchor constraintEqualToAnchor:self.languageSection.leadingAnchor],
        [optionsContainer.trailingAnchor constraintEqualToAnchor:self.languageSection.trailingAnchor],
        [optionsContainer.heightAnchor constraintEqualToConstant:(self.languageExpanded ? 150 : 0)],
        [optionsContainer.bottomAnchor constraintEqualToAnchor:self.languageSection.bottomAnchor constant:-16],
    ]];
}

- (void)setupProtectionSection {
    self.protectionSection = [[UIView alloc] init];
    self.protectionSection.translatesAutoresizingMaskIntoConstraints = NO;
    self.protectionSection.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    self.protectionSection.layer.cornerRadius = 12;
    [self.contentView addSubview:self.protectionSection];
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"eye.slash"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    [self.protectionSection addSubview:icon];
    
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"PROTECCIÓN DE PANTALLA";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:14];
    [self.protectionSection addSubview:title];
    
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Ocultar contenido al grabar o capturar pantalla";
    subtitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    subtitle.font = [UIFont systemFontOfSize:12];
    [self.protectionSection addSubview:subtitle];
    
    self.protectionSwitch = [[UISwitch alloc] init];
    self.protectionSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.protectionSwitch.on = self.screenProtection;
    self.protectionSwitch.onTintColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    [self.protectionSwitch addTarget:self action:@selector(toggleProtection) forControlEvents:UIControlEventValueChanged];
    [self.protectionSection addSubview:self.protectionSwitch];
    
    UILabel *description = [[UILabel alloc] init];
    description.translatesAutoresizingMaskIntoConstraints = NO;
    description.text = @"Cuando esta opción esté activada, la pantalla se volverá negra al detectar una captura o grabación.";
    description.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    description.font = [UIFont systemFontOfSize:11];
    description.numberOfLines = 0;
    [self.protectionSection addSubview:description];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.protectionSection.topAnchor constraintEqualToAnchor:self.languageSection.bottomAnchor constant:12],
        [self.protectionSection.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.protectionSection.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [icon.topAnchor constraintEqualToAnchor:self.protectionSection.topAnchor constant:16],
        [icon.leadingAnchor constraintEqualToAnchor:self.protectionSection.leadingAnchor constant:16],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        
        [title.topAnchor constraintEqualToAnchor:icon.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        
        [self.protectionSwitch.topAnchor constraintEqualToAnchor:icon.topAnchor],
        [self.protectionSwitch.trailingAnchor constraintEqualToAnchor:self.protectionSection.trailingAnchor constant:-16],
        
        [description.topAnchor constraintEqualToAnchor:self.protectionSwitch.bottomAnchor constant:12],
        [description.leadingAnchor constraintEqualToAnchor:self.protectionSection.leadingAnchor constant:16],
        [description.trailingAnchor constraintEqualToAnchor:self.protectionSection.trailingAnchor constant:-16],
        [description.bottomAnchor constraintEqualToAnchor:self.protectionSection.bottomAnchor constant:-16],
    ]];
}

- (void)setupCustomizationSection {
    self.customizationSection = [[UIView alloc] init];
    self.customizationSection.translatesAutoresizingMaskIntoConstraints = NO;
    self.customizationSection.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    self.customizationSection.layer.cornerRadius = 12;
    [self.contentView addSubview:self.customizationSection];
    
    UIView *sectionHeader = [[UIView alloc] init];
    sectionHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.customizationSection addSubview:sectionHeader];
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"paintbrush"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    [sectionHeader addSubview:icon];
    
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"PERSONALIZACIÓN";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:14];
    [sectionHeader addSubview:title];
    
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Ajusta el estilo de la aplicación";
    subtitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    subtitle.font = [UIFont systemFontOfSize:12];
    [sectionHeader addSubview:subtitle];
    
    UIButton *expandButton = [UIButton buttonWithType:UIButtonTypeCustom];
    expandButton.translatesAutoresizingMaskIntoConstraints = NO;
    [expandButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    [expandButton setTintColor:[UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0]];
    [expandButton addTarget:self action:@selector(toggleCustomization) forControlEvents:UIControlEventTouchUpInside];
    [sectionHeader addSubview:expandButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.customizationSection.topAnchor constraintEqualToAnchor:self.protectionSection.bottomAnchor constant:12],
        [self.customizationSection.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.customizationSection.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        
        [sectionHeader.topAnchor constraintEqualToAnchor:self.customizationSection.topAnchor constant:16],
        [sectionHeader.leadingAnchor constraintEqualToAnchor:self.customizationSection.leadingAnchor constant:16],
        [sectionHeader.trailingAnchor constraintEqualToAnchor:self.customizationSection.trailingAnchor constant:-16],
        [sectionHeader.heightAnchor constraintEqualToConstant:50],
        
        [icon.leadingAnchor constraintEqualToAnchor:sectionHeader.leadingAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:sectionHeader.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:sectionHeader.topAnchor constant:8],
        
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        
        [expandButton.trailingAnchor constraintEqualToAnchor:sectionHeader.trailingAnchor],
        [expandButton.centerYAnchor constraintEqualToAnchor:sectionHeader.centerYAnchor],
        [expandButton.widthAnchor constraintEqualToConstant:24],
        [expandButton.heightAnchor constraintEqualToConstant:24],
    ]];
}

- (void)setupPreviewSection {
    UIView *previewSection = [[UIView alloc] init];
    previewSection.translatesAutoresizingMaskIntoConstraints = NO;
    previewSection.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    previewSection.layer.cornerRadius = 12;
    [self.contentView addSubview:previewSection];
    
    UILabel *previewTitle = [[UILabel alloc] init];
    previewTitle.translatesAutoresizingMaskIntoConstraints = NO;
    previewTitle.text = @"VISTA PREVIA";
    previewTitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    previewTitle.font = [UIFont boldSystemFontOfSize:11];
    [previewSection addSubview:previewTitle];
    
    UILabel *logo = [[UILabel alloc] init];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.text = @"XITFORGE";
    logo.textColor = [UIColor whiteColor];
    logo.font = [UIFont boldSystemFontOfSize:28];
    logo.textAlignment = NSTextAlignmentCenter;
    [previewSection addSubview:logo];
    
    UILabel *sampleText = [[UILabel alloc] init];
    sampleText.translatesAutoresizingMaskIntoConstraints = NO;
    sampleText.text = @"Este es el texto de ejemplo";
    sampleText.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    sampleText.font = [UIFont systemFontOfSize:14];
    sampleText.textAlignment = NSTextAlignmentCenter;
    [previewSection addSubview:sampleText];
    
    [NSLayoutConstraint activateConstraints:@[
        [previewSection.topAnchor constraintEqualToAnchor:self.customizationSection.bottomAnchor constant:12],
        [previewSection.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [previewSection.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [previewSection.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-20],
        
        [previewTitle.topAnchor constraintEqualToAnchor:previewSection.topAnchor constant:16],
        [previewTitle.leadingAnchor constraintEqualToAnchor:previewSection.leadingAnchor constant:16],
        
        [logo.topAnchor constraintEqualToAnchor:previewTitle.bottomAnchor constant:12],
        [logo.centerXAnchor constraintEqualToAnchor:previewSection.centerXAnchor],
        
        [sampleText.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:8],
        [sampleText.centerXAnchor constraintEqualToAnchor:previewSection.centerXAnchor],
        [sampleText.bottomAnchor constraintEqualToAnchor:previewSection.bottomAnchor constant:-16],
    ]];
}

#pragma mark - Actions

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleLanguage {
    self.languageExpanded = !self.languageExpanded;
    UIView *options = [self.languageSection viewWithTag:100];
    [UIView animateWithDuration:0.3 animations:^{
        options.heightAnchor.constant = self.languageExpanded ? 150 : 0;
        [self.view layoutIfNeeded];
    }];
}

- (void)selectLanguage:(UIButton *)button {
    NSInteger index = button.tag - 300;
    self.selectedLanguage = index;
    
    for (int i = 0; i < 3; i++) {
        UIButton *radio = [self.view viewWithTag:300 + i];
        [radio setImage:[UIImage systemImageNamed:(i == index ? @"largecircle.fill.circle" : @"circle")] forState:UIControlStateNormal];
        [radio setTintColor:(i == index ? [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0] : [UIColor colorWithWhite:0.4 alpha:1.0])];
    }
    
    [self saveSettings];
    if (self.onSettingsChanged) self.onSettingsChanged();
}

- (void)toggleProtection {
    self.screenProtection = self.protectionSwitch.isOn;
    [self saveSettings];
    if (self.onSettingsChanged) self.onSettingsChanged();
}

- (void)toggleCustomization {
    self.customizationExpanded = !self.customizationExpanded;
    // Aquí puedes agregar la lógica para expandir/colapsar
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.selectedLanguage forKey:@"selectedLanguage"];
    [defaults setBool:self.screenProtection forKey:@"screenProtection"];
    [defaults setInteger:self.selectedBgColor forKey:@"selectedBgColor"];
    [defaults setInteger:self.selectedTextColor forKey:@"selectedTextColor"];
    [defaults synchronize];
}

@end
