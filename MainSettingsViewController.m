#import "MainSettingsViewController.h"
#import "Translations.h"
#import "ScreenProtectionManager.h"
#import <UIKit/UIKit.h>

@interface MainSettingsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSTimer *licenseTimer;
@property (nonatomic, assign) BOOL languageExpanded;

@end

@implementation MainSettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    NSInteger savedLanguage =
        [[NSUserDefaults standardUserDefaults]
            integerForKey:@"selectedLanguage"];

    [Translations setLanguage:savedLanguage];

    self.languageExpanded = NO;

    self.view.backgroundColor =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.03
                        alpha:1.0];

    self.title =
        [Translations tr:@"settings"];

    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeAlways;

    self.tableView =
        [[UITableView alloc]
            initWithFrame:CGRectZero
                    style:UITableViewStyleGrouped];

    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

    self.tableView.backgroundColor =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.03
                        alpha:1.0];

    self.tableView.dataSource = self;
    self.tableView.delegate = self;

    self.tableView.separatorStyle =
        UITableViewCellSeparatorStyleNone;

    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.rowHeight =
        UITableViewAutomaticDimension;

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor
            constraintEqualToAnchor:self.view.topAnchor],

        [self.tableView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],

        [self.tableView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],

        [self.tableView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(languageDidChange:)
               name:TranslationsLanguageDidChangeNotification
             object:nil];

    /*
     * Aplicar la protección que el usuario dejó guardada.
     */
    [self applyScreenProtection];

    /*
     * Iniciar contador.
     */
    [self startLicenseTimer];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    NSInteger savedLanguage =
        [[NSUserDefaults standardUserDefaults]
            integerForKey:@"selectedLanguage"];

    [Translations setLanguage:savedLanguage];

    self.title =
        [Translations tr:@"settings"];

    [self applyScreenProtection];

    [self.tableView reloadData];

    [self startLicenseTimer];

    [self updateLicenseCard];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self stopLicenseTimer];
}

- (void)dealloc {

    [self stopLicenseTimer];

    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
}

#pragma mark - Timer

- (void)startLicenseTimer {

    [self stopLicenseTimer];

    self.licenseTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(updateLicenseCard)
                                       userInfo:nil
                                        repeats:YES];
}

- (void)stopLicenseTimer {

    [self.licenseTimer invalidate];
    self.licenseTimer = nil;
}

#pragma mark - Appearance

- (UIColor *)accentColor {

    return [UIColor colorWithRed:0.95
                           green:0.08
                            blue:0.10
                           alpha:1.0];
}

- (UIColor *)panelColor {

    return [UIColor colorWithRed:0.06
                           green:0.06
                            blue:0.08
                           alpha:1.0];
}

- (UIColor *)secondaryTextColor {

    return [UIColor colorWithWhite:0.52
                             alpha:1.0];
}

#pragma mark - Language

- (NSString *)currentLanguageName {

    switch ([Translations currentLanguage]) {

        case 1:
            return [Translations tr:@"english"];

        case 2:
            return [Translations tr:@"portuguese"];

        default:
            return [Translations tr:@"spanish"];
    }
}

- (void)languageDidChange:
    (NSNotification *)notification {

    self.title =
        [Translations tr:@"settings"];

    [self.tableView reloadData];

    [self updateLicenseCard];
}

- (void)selectLanguage:(NSInteger)language {

    if (language < 0 || language > 2) {
        language = 0;
    }

    [[NSUserDefaults standardUserDefaults]
        setInteger:language
        forKey:@"selectedLanguage"];

    [[NSUserDefaults standardUserDefaults]
        synchronize];

    [Translations setLanguage:language];

    self.languageExpanded = NO;

    [self.tableView
        reloadSections:
            [NSIndexSet indexSetWithIndex:1]
        withRowAnimation:
            UITableViewRowAnimationAutomatic];
}

#pragma mark - Screen Protection

- (BOOL)screenProtectionEnabled {

    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"screenProtection"];
}

- (void)applyScreenProtection {

    if ([self screenProtectionEnabled]) {

        [[ScreenProtectionManager shared]
            enableProtection];

    } else {

        [[ScreenProtectionManager shared]
            disableProtection];
    }
}

- (void)screenProtectionChanged:
    (UISwitch *)sender {

    BOOL enabled =
        sender.isOn;

    [[NSUserDefaults standardUserDefaults]
        setBool:enabled
        forKey:@"screenProtection"];

    [[NSUserDefaults standardUserDefaults]
        synchronize];

    if (enabled) {

        [[ScreenProtectionManager shared]
            enableProtection];

    } else {

        [[ScreenProtectionManager shared]
            disableProtection];
    }

    [self.tableView
        reloadSections:
            [NSIndexSet indexSetWithIndex:1]
        withRowAnimation:
            UITableViewRowAnimationNone];
}

#pragma mark - Activation Voice

- (BOOL)activationVoiceEnabled {

    NSUserDefaults *defaults =
        [NSUserDefaults standardUserDefaults];

    /*
     * Si el usuario nunca cambió este ajuste, la voz queda
     * activada por defecto para conservar el comportamiento actual.
     */
    if ([defaults objectForKey:@"xitforgeActivationVoiceEnabled"] == nil) {
        return YES;
    }

    return [defaults boolForKey:@"xitforgeActivationVoiceEnabled"];
}

- (void)activationVoiceChanged:(UISwitch *)sender {

    [[NSUserDefaults standardUserDefaults]
        setBool:sender.isOn
        forKey:@"xitforgeActivationVoiceEnabled"];

    [[NSUserDefaults standardUserDefaults]
        synchronize];
}

- (NSString *)activationVoiceTitle {

    switch ([Translations currentLanguage]) {
        case 1:
            return @"Activation voice";
        case 2:
            return @"Voz de ativação";
        default:
            return @"Voz de activación";
    }
}

- (NSString *)activationVoiceDescription {

    switch ([Translations currentLanguage]) {
        case 1:
            return @"Play the confirmation voice after a successful activation.";
        case 2:
            return @"Reproduz a voz de confirmação após uma ativação bem-sucedida.";
        default:
            return @"Reproduce la voz de confirmación después de activar correctamente.";
    }
}

#pragma mark - License

- (NSDate *)licenseExpirationDate {

    NSString *expiresAt =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:
                @"MiFilzaLicenseExpiresAt"];

    if (expiresAt.length == 0) {
        return nil;
    }

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.locale =
        [NSLocale localeWithLocaleIdentifier:
            @"en_US_POSIX"];

    formatter.dateFormat =
        @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX";

    NSDate *date =
        [formatter dateFromString:expiresAt];

    if (!date) {

        formatter.dateFormat =
            @"yyyy-MM-dd'T'HH:mm:ssXXXXX";

        date =
            [formatter dateFromString:expiresAt];
    }

    return date;
}

- (BOOL)licenseExpired {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {
        return NO;
    }

    return
        [expiration timeIntervalSinceNow] <= 0;
}

- (NSString *)licenseRemaining {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {

        return [Translations tr:
            @"no_expiration"];
    }

    NSTimeInterval remaining =
        [expiration timeIntervalSinceNow];

    if (remaining <= 0) {

        return [Translations tr:
            @"license_expired"];
    }

    NSInteger total =
        (NSInteger)remaining;

    NSInteger days =
        total / 86400;

    total %= 86400;

    NSInteger hours =
        total / 3600;

    total %= 3600;

    NSInteger minutes =
        total / 60;

    NSInteger seconds =
        total % 60;

    return [NSString stringWithFormat:
        @"%02ldd %02ldh %02ldm %02lds",
        (long)days,
        (long)hours,
        (long)minutes,
        (long)seconds];
}

- (NSString *)licenseExpirationText {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {
        return @"";
    }

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.locale =
        [NSLocale currentLocale];

    formatter.dateFormat =
        @"dd/MM/yyyy · HH:mm:ss";

    return [NSString stringWithFormat:
        @"%@: %@",
        [Translations tr:@"expires"],
        [formatter stringFromDate:expiration]];
}

#pragma mark - Masked Key

- (NSString *)maskedLicenseKey {

    NSString *key =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:
                @"MiFilzaLicenseKey"];

    if (key.length == 0) {
        return @"Sin licencia";
    }

    NSString *normalized =
        [[key
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            uppercaseString];

    NSArray<NSString *> *parts =
        [normalized componentsSeparatedByString:@"-"];

    if (parts.count == 4) {

        return [NSString stringWithFormat:
            @"%@-%@-••••-••••",
            parts[0],
            parts[1]];
    }

    if (normalized.length > 8) {

        return [NSString stringWithFormat:
            @"%@-••••",
            [normalized substringToIndex:8]];
    }

    return @"••••••••";
}

#pragma mark - Logout

- (NSString *)logoutTitle {

    switch ([Translations currentLanguage]) {

        case 1:
            return @"Sign Out License";

        case 2:
            return @"Sair da licença";

        default:
            return @"Cerrar sesión de la key";
    }
}

- (NSString *)logoutMessage {

    switch ([Translations currentLanguage]) {

        case 1:
            return
                @"Are you sure you want to sign out? "
                 "The key will be removed from this device.";

        case 2:
            return
                @"Tem certeza que deseja sair? "
                 "A chave será removida deste dispositivo.";

        default:
            return
                @"¿Seguro que quieres cerrar la sesión? "
                 "La key se eliminará de este dispositivo.";
    }
}

- (NSString *)cancelText {

    switch ([Translations currentLanguage]) {

        case 1:
            return @"Cancel";

        case 2:
            return @"Cancelar";

        default:
            return @"Cancelar";
    }
}

- (NSString *)logoutConfirmText {

    switch ([Translations currentLanguage]) {

        case 1:
            return @"Sign Out";

        case 2:
            return @"Sair";

        default:
            return @"Cerrar sesión";
    }
}

- (void)confirmLogout {

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:
                [self logoutTitle]
            message:
                [self logoutMessage]
            preferredStyle:
                UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:
                [self cancelText]
            style:
                UIAlertActionStyleCancel
            handler:nil]];

    __weak typeof(self) weakSelf =
        self;

    [alert addAction:
        [UIAlertAction
            actionWithTitle:
                [self logoutConfirmText]
            style:
                UIAlertActionStyleDestructive
            handler:^(UIAlertAction *action) {

                __strong typeof(weakSelf) strongSelf =
                    weakSelf;

                if (!strongSelf) {
                    return;
                }

                [strongSelf logoutLicense];
            }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)logoutLicense {

    NSUserDefaults *defaults =
        [NSUserDefaults standardUserDefaults];

    /*
     * Solo elimina la sesión LOCAL.
     * No revoca la licencia en el servidor.
     */
    [defaults removeObjectForKey:
        @"MiFilzaLicenseKey"];

    [defaults removeObjectForKey:
        @"MiFilzaLicenseExpiresAt"];

    [defaults setBool:NO
               forKey:@"screenProtection"];

    [defaults synchronize];

    [[ScreenProtectionManager shared]
        disableProtection];

    /*
     * Pedir al AppDelegate que vuelva a mostrar
     * la ventana de licencia.
     */
    id delegate =
        [UIApplication sharedApplication].delegate;

    SEL selector =
        NSSelectorFromString(
            @"mostrarPantallaLicencia");

    if ([delegate respondsToSelector:selector]) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

        [delegate performSelector:selector];

#pragma clang diagnostic pop
    }
}

#pragma mark - License Card

- (UITableViewCell *)licenseCell:
    (UITableView *)tableView {

    static NSString *identifier =
        @"LicenseCardCell";

    UITableViewCell *cell =
        [tableView
            dequeueReusableCellWithIdentifier:
                identifier];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:
                    UITableViewCellStyleDefault
                reuseIdentifier:
                    identifier];

        cell.backgroundColor =
            UIColor.clearColor;

        cell.selectionStyle =
            UITableViewCellSelectionStyleNone;
    }

    for (UIView *view
         in cell.contentView.subviews) {

        [view removeFromSuperview];
    }

    UIColor *accent =
        [self accentColor];

    BOOL expired =
        [self licenseExpired];

    UIView *card =
        [[UIView alloc] init];

    card.translatesAutoresizingMaskIntoConstraints =
        NO;

    card.backgroundColor =
        [self panelColor];

    card.layer.cornerRadius =
        20.0;

    card.layer.borderWidth =
        1.0;

    card.layer.borderColor =
        [accent
            colorWithAlphaComponent:0.25].CGColor;

    card.layer.shadowColor =
        UIColor.blackColor.CGColor;

    card.layer.shadowOpacity =
        0.25;

    card.layer.shadowRadius =
        12.0;

    card.layer.shadowOffset =
        CGSizeMake(0, 5);

    [cell.contentView addSubview:card];

    UIImageView *icon =
        [[UIImageView alloc]
            initWithImage:
                [UIImage
                    systemImageNamed:
                        expired
                            ? @"xmark.shield.fill"
                            : @"checkmark.shield.fill"]];

    icon.translatesAutoresizingMaskIntoConstraints =
        NO;

    icon.tintColor =
        expired
            ? [UIColor systemRedColor]
            : accent;

    icon.contentMode =
        UIViewContentModeScaleAspectFit;

    [card addSubview:icon];

    UILabel *title =
        [[UILabel alloc] init];

    title.translatesAutoresizingMaskIntoConstraints =
        NO;

    title.text =
        expired
            ? [Translations tr:@"license_expired"]
            : [Translations tr:@"license_active"];

    title.textColor =
        expired
            ? [UIColor systemRedColor]
            : UIColor.whiteColor;

    title.font =
        [UIFont systemFontOfSize:14.0
                          weight:UIFontWeightBold];

    title.textAlignment =
        NSTextAlignmentCenter;

    [card addSubview:title];

    UILabel *timer =
        [[UILabel alloc] init];

    timer.translatesAutoresizingMaskIntoConstraints =
        NO;

    timer.tag = 8001;

    timer.text =
        [self licenseRemaining];

    timer.textColor =
        expired
            ? [UIColor systemRedColor]
            : accent;

    timer.font =
        [UIFont monospacedSystemFontOfSize:26.0
                                    weight:UIFontWeightBold];

    timer.textAlignment =
        NSTextAlignmentCenter;

    timer.adjustsFontSizeToFitWidth =
        YES;

    timer.minimumScaleFactor =
        0.55;

    [card addSubview:timer];

    UILabel *expires =
        [[UILabel alloc] init];

    expires.translatesAutoresizingMaskIntoConstraints =
        NO;

    expires.tag = 8002;

    expires.text =
        [self licenseExpirationText];

    expires.textColor =
        [self secondaryTextColor];

    expires.font =
        [UIFont monospacedSystemFontOfSize:12.0
                                    weight:UIFontWeightMedium];

    expires.textAlignment =
        NSTextAlignmentCenter;

    [card addSubview:expires];

    if ([self licenseExpirationDate] == nil) {

        timer.text =
            [Translations tr:@"no_expiration"];

        timer.font =
            [UIFont systemFontOfSize:20.0
                              weight:UIFontWeightBold];
    }

    [NSLayoutConstraint activateConstraints:@[

        [card.topAnchor
            constraintEqualToAnchor:
                cell.contentView.topAnchor
                constant:5.0],

        [card.leadingAnchor
            constraintEqualToAnchor:
                cell.contentView.leadingAnchor
                constant:16.0],

        [card.trailingAnchor
            constraintEqualToAnchor:
                cell.contentView.trailingAnchor
                constant:-16.0],

        [card.bottomAnchor
            constraintEqualToAnchor:
                cell.contentView.bottomAnchor
                constant:-8.0],

        [icon.topAnchor
            constraintEqualToAnchor:
                card.topAnchor
                constant:15.0],

        [icon.centerXAnchor
            constraintEqualToAnchor:
                card.centerXAnchor],

        [icon.widthAnchor
            constraintEqualToConstant:24.0],

        [icon.heightAnchor
            constraintEqualToConstant:24.0],

        [title.topAnchor
            constraintEqualToAnchor:
                icon.bottomAnchor
                constant:6.0],

        [title.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:15.0],

        [title.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-15.0],

        [title.heightAnchor
            constraintEqualToConstant:20.0],

        [timer.topAnchor
            constraintEqualToAnchor:
                title.bottomAnchor
                constant:4.0],

        [timer.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:10.0],

        [timer.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-10.0],

        [timer.heightAnchor
            constraintEqualToConstant:40.0],

        [expires.topAnchor
            constraintEqualToAnchor:
                timer.bottomAnchor
                constant:0.0],

        [expires.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:15.0],

        [expires.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-15.0],

        [expires.bottomAnchor
            constraintEqualToAnchor:
                card.bottomAnchor
                constant:-15.0],

        [expires.heightAnchor
            constraintEqualToConstant:18.0]
    ]];

    return cell;
}

- (void)updateLicenseCard {

    NSIndexPath *path =
        [NSIndexPath indexPathForRow:0
                           inSection:0];

    UITableViewCell *cell =
        [self.tableView
            cellForRowAtIndexPath:path];

    if (!cell) {
        return;
    }

    UILabel *timer =
        (UILabel *)
            [cell.contentView
                viewWithTag:8001];

    UILabel *expires =
        (UILabel *)
            [cell.contentView
                viewWithTag:8002];

    if ([timer isKindOfClass:[UILabel class]]) {

        timer.text =
            [self licenseRemaining];

        timer.textColor =
            [self licenseExpired]
                ? [UIColor systemRedColor]
                : [self accentColor];
    }

    if ([expires isKindOfClass:[UILabel class]]) {

        expires.text =
            [self licenseExpirationText];
    }
}

#pragma mark - TableView Data Source

- (NSInteger)numberOfSectionsInTableView:
    (UITableView *)tableView {

    return 3;
}

- (NSInteger)tableView:
    (UITableView *)tableView
numberOfRowsInSection:
    (NSInteger)section {

    /*
     * LICENCIA:
     * 0 = tarjeta
     * 1 = key
     * 2 = cerrar sesión
     */
    if (section == 0) {
        return 3;
    }

    /*
     * PREFERENCIAS:
     * idioma + protección + voz de activación
     */
    if (section == 1) {
        return self.languageExpanded ? 6 : 3;
    }

    /*
     * INFORMACIÓN:
     * versión
     */
    return 1;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
    cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    /*
     * =========================================================
     * LICENCIA
     * =========================================================
     */

    if (indexPath.section == 0) {

        /*
         * Tarjeta
         */
        if (indexPath.row == 0) {

            return [self licenseCell:tableView];
        }

        /*
         * Key parcialmente oculta
         */
        if (indexPath.row == 1) {

            static NSString *keyID =
                @"LicenseKeyCell";

            UITableViewCell *cell =
                [tableView
                    dequeueReusableCellWithIdentifier:
                        keyID];

            if (!cell) {

                cell =
                    [[UITableViewCell alloc]
                        initWithStyle:
                            UITableViewCellStyleValue1
                        reuseIdentifier:keyID];

                cell.backgroundColor =
                    [self panelColor];

                cell.selectionStyle =
                    UITableViewCellSelectionStyleNone;
            }

            cell.imageView.image =
                [UIImage
                    systemImageNamed:@"key.fill"];

            cell.imageView.tintColor =
                [self accentColor];

            cell.textLabel.text =
                @"Key";

            cell.textLabel.textColor =
                UIColor.whiteColor;

            cell.textLabel.font =
                [UIFont systemFontOfSize:15.0
                                  weight:UIFontWeightSemibold];

            cell.detailTextLabel.text =
                [self maskedLicenseKey];

            cell.detailTextLabel.textColor =
                [self secondaryTextColor];

            cell.detailTextLabel.font =
                [UIFont monospacedSystemFontOfSize:13.0
                                            weight:UIFontWeightMedium];

            cell.accessoryType =
                UITableViewCellAccessoryNone;

            return cell;
        }

        /*
         * Cerrar sesión
         */
        static NSString *logoutID =
            @"LogoutLicenseCell";

        UITableViewCell *cell =
            [tableView
                dequeueReusableCellWithIdentifier:
                    logoutID];

        if (!cell) {

            cell =
                [[UITableViewCell alloc]
                    initWithStyle:
                        UITableViewCellStyleDefault
                    reuseIdentifier:
                        logoutID];

            cell.backgroundColor =
                [self panelColor];

            cell.selectionStyle =
                UITableViewCellSelectionStyleDefault;
        }

        cell.imageView.image =
            [UIImage
                systemImageNamed:
                    @"rectangle.portrait.and.arrow.right"];

        cell.imageView.tintColor =
            [UIColor systemRedColor];

        cell.textLabel.text =
            [self logoutTitle];

        cell.textLabel.textColor =
            [UIColor systemRedColor];

        cell.textLabel.font =
            [UIFont systemFontOfSize:15.0
                              weight:UIFontWeightSemibold];

        cell.accessoryType =
            UITableViewCellAccessoryDisclosureIndicator;

        return cell;
    }

    /*
     * =========================================================
     * PREFERENCIAS
     * =========================================================
     */

    static NSString *cellID =
        @"SettingsCell";

    UITableViewCell *cell =
        [tableView
            dequeueReusableCellWithIdentifier:
                cellID];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:
                    UITableViewCellStyleSubtitle
                reuseIdentifier:
                    cellID];

        cell.backgroundColor =
            [self panelColor];

        cell.selectionStyle =
            UITableViewCellSelectionStyleDefault;
    }

    cell.accessoryType =
        UITableViewCellAccessoryNone;

    cell.accessoryView =
        nil;

    cell.textLabel.text =
        nil;

    cell.detailTextLabel.text =
        nil;

    cell.imageView.image =
        nil;

    cell.textLabel.textColor =
        UIColor.whiteColor;

    cell.detailTextLabel.textColor =
        [self secondaryTextColor];

    cell.imageView.tintColor =
        [self accentColor];

    /*
     * Idioma
     */
    if (indexPath.section == 1 &&
        indexPath.row == 0) {

        cell.imageView.image =
            [UIImage
                systemImageNamed:@"globe"];

        cell.textLabel.text =
            [Translations tr:@"language"];

        cell.detailTextLabel.text =
            [self currentLanguageName];

        cell.accessoryType =
            self.languageExpanded
                ? UITableViewCellAccessoryNone
                : UITableViewCellAccessoryDisclosureIndicator;

        return cell;
    }

    /*
     * Idiomas expandidos
     */
    if (indexPath.section == 1 &&
        self.languageExpanded &&
        indexPath.row >= 1 &&
        indexPath.row <= 3) {

        NSInteger language =
            indexPath.row - 1;

        NSString *name = nil;

        if (language == 0) {

            name =
                [Translations tr:@"spanish"];

        } else if (language == 1) {

            name =
                [Translations tr:@"english"];

        } else {

            name =
                [Translations tr:@"portuguese"];
        }

        cell.imageView.image =
            [UIImage
                systemImageNamed:@"globe"];

        cell.textLabel.text =
            name;

        cell.detailTextLabel.text =
            nil;

        cell.accessoryType =
            ([Translations currentLanguage] == language)
                ? UITableViewCellAccessoryCheckmark
                : UITableViewCellAccessoryNone;

        return cell;
    }

    /*
     * Protección para revisión
     */
    BOOL protectionRow =
        (!self.languageExpanded &&
         indexPath.row == 1) ||
        (self.languageExpanded &&
         indexPath.row == 4);

    if (indexPath.section == 1 &&
        protectionRow) {

        cell.imageView.image =
            [UIImage
                systemImageNamed:
                    @"shield.lefthalf.filled"];

        cell.textLabel.text =
            [Translations tr:@"protection"];

        cell.detailTextLabel.text =
            [Translations tr:@"protection_desc"];

        cell.detailTextLabel.numberOfLines =
            2;

        UISwitch *toggle =
            [[UISwitch alloc] init];

        toggle.on =
            [self screenProtectionEnabled];

        toggle.onTintColor =
            [self accentColor];

        [toggle addTarget:self
                   action:@selector(
                       screenProtectionChanged:)
         forControlEvents:
             UIControlEventValueChanged];

        cell.accessoryView =
            toggle;

        return cell;
    }

    /*
     * Voz de activación
     */
    BOOL activationVoiceRow =
        (!self.languageExpanded &&
         indexPath.row == 2) ||
        (self.languageExpanded &&
         indexPath.row == 5);

    if (indexPath.section == 1 &&
        activationVoiceRow) {

        cell.imageView.image =
            [UIImage
                systemImageNamed:@"speaker.wave.2.fill"];

        cell.textLabel.text =
            [self activationVoiceTitle];

        cell.detailTextLabel.text =
            [self activationVoiceDescription];

        cell.detailTextLabel.numberOfLines =
            2;

        UISwitch *toggle =
            [[UISwitch alloc] init];

        toggle.on =
            [self activationVoiceEnabled];

        toggle.onTintColor =
            [self accentColor];

        [toggle addTarget:self
                   action:@selector(
                       activationVoiceChanged:)
         forControlEvents:
             UIControlEventValueChanged];

        cell.accessoryView =
            toggle;

        return cell;
    }

    /*
     * =========================================================
     * INFORMACIÓN
     * =========================================================
     */

    if (indexPath.section == 2) {

        cell.imageView.image =
            [UIImage
                systemImageNamed:
                    @"info.circle"];

        cell.textLabel.text =
            [Translations tr:@"app_version"];

        NSString *appVersion =
            [[NSBundle mainBundle]
                objectForInfoDictionaryKey:
                    @"CFBundleShortVersionString"];

        cell.detailTextLabel.text =
            appVersion.length > 0
                ? appVersion
                : @"-";

        return cell;
    }

    return cell;
}

#pragma mark - Headers

- (NSString *)tableView:
    (UITableView *)tableView
    titleForHeaderInSection:
    (NSInteger)section {

    if (section == 0) {

        return [Translations tr:@"license"];
    }

    if (section == 1) {

        return [Translations tr:@"preferences"];
    }

    return [Translations tr:@"information"];
}

#pragma mark - Heights

- (CGFloat)tableView:
    (UITableView *)tableView
heightForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (indexPath.section == 0 &&
        indexPath.row == 0) {

        return 165.0;
    }

    if (indexPath.section == 0 &&
        indexPath.row == 1) {

        return 58.0;
    }

    if (indexPath.section == 0 &&
        indexPath.row == 2) {

        return 58.0;
    }

    if (indexPath.section == 1) {

        BOOL protectionRow =
            (!self.languageExpanded && indexPath.row == 1) ||
            (self.languageExpanded && indexPath.row == 4);

        BOOL activationVoiceRow =
            (!self.languageExpanded && indexPath.row == 2) ||
            (self.languageExpanded && indexPath.row == 5);

        if (protectionRow || activationVoiceRow) {
            return 86.0;
        }
    }

    return 64.0;
}

#pragma mark - Delegate

- (void)tableView:
    (UITableView *)tableView
    didSelectRowAtIndexPath:
    (NSIndexPath *)indexPath {

    [tableView
        deselectRowAtIndexPath:indexPath
                      animated:YES];

    /*
     * Cerrar sesión
     */
    if (indexPath.section == 0 &&
        indexPath.row == 2) {

        [self confirmLogout];

        return;
    }

    /*
     * Abrir/cerrar idiomas
     */
    if (indexPath.section == 1 &&
        indexPath.row == 0) {

        self.languageExpanded =
            !self.languageExpanded;

        [tableView reloadSections:
            [NSIndexSet indexSetWithIndex:1]
                 withRowAnimation:
                     UITableViewRowAnimationAutomatic];

        return;
    }

    /*
     * Seleccionar idioma
     */
    if (indexPath.section == 1 &&
        self.languageExpanded &&
        indexPath.row >= 1 &&
        indexPath.row <= 3) {

        NSInteger language =
            indexPath.row - 1;

        [self selectLanguage:language];

        return;
    }
}

@end
