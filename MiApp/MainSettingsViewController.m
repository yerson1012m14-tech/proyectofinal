#import "MainSettingsViewController.h"
#import "Translations.h"
#import "ScreenProtectionManager.h"

@interface MainSettingsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSTimer *licenseTimer;
@property (nonatomic, assign) BOOL languageExpanded;

@end

@implementation MainSettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.languageExpanded = NO;

    self.view.backgroundColor =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.03
                        alpha:1.0];

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

    self.licenseTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(updateLicenseCard)
                                       userInfo:nil
                                        repeats:YES];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(languageDidChange:)
               name:TranslationsLanguageDidChangeNotification
             object:nil];

    /*
     * Aplicar el estado guardado al abrir ajustes.
     */
    if ([self screenProtectionEnabled]) {

        [[ScreenProtectionManager shared]
            enableProtection];

    } else {

        [[ScreenProtectionManager shared]
            disableProtection];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.title =
        [Translations tr:@"settings"];

    [self.tableView reloadData];

    [self updateLicenseCard];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.licenseTimer invalidate];
    self.licenseTimer = nil;
}

- (void)dealloc {

    [self.licenseTimer invalidate];

    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
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

- (void)languageDidChange:(NSNotification *)notification {

    self.title =
        [Translations tr:@"settings"];

    [self.tableView reloadData];

    [self updateLicenseCard];
}

- (void)selectLanguage:(NSInteger)language {

    [Translations setLanguage:language];

    self.languageExpanded = NO;

    [self.tableView reloadSections:
        [NSIndexSet indexSetWithIndex:1]
                   withRowAnimation:
                       UITableViewRowAnimationAutomatic];
}

#pragma mark - Protection

- (BOOL)screenProtectionEnabled {

    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"screenProtection"];
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

    [self.tableView reloadSections:
        [NSIndexSet indexSetWithIndex:1]
                   withRowAnimation:
                       UITableViewRowAnimationNone];
}

#pragma mark - License

- (NSDate *)licenseExpirationDate {

    NSString *expiresAt =
        [[NSUserDefaults standardUserDefaults]
            stringForKey:@"MiFilzaLicenseExpiresAt"];

    if (expiresAt.length == 0) {
        return nil;
    }

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.locale =
        [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

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

- (NSString *)licenseRemaining {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {
        return [Translations tr:@"no_expiration"];
    }

    NSTimeInterval remaining =
        [expiration timeIntervalSinceNow];

    if (remaining <= 0) {
        return [Translations tr:@"license_expired"];
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

- (BOOL)licenseExpired {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {
        return NO;
    }

    return [expiration timeIntervalSinceNow] <= 0;
}

#pragma mark - License Card

- (UITableViewCell *)licenseCell:
    (UITableView *)tableView {

    static NSString *identifier =
        @"LicenseCardCell";

    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:
            identifier];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:identifier];

        cell.backgroundColor =
            UIColor.clearColor;

        cell.selectionStyle =
            UITableViewCellSelectionStyleNone;
    }

    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }

    UIColor *accent =
        [self accentColor];

    UIView *card =
        [[UIView alloc] init];

    card.translatesAutoresizingMaskIntoConstraints = NO;

    card.backgroundColor =
        [self panelColor];

    card.layer.cornerRadius = 20.0;

    card.layer.borderWidth = 1.0;

    card.layer.borderColor =
        [accent colorWithAlphaComponent:0.25].CGColor;

    [cell.contentView addSubview:card];

    UILabel *title =
        [[UILabel alloc] init];

    title.translatesAutoresizingMaskIntoConstraints = NO;

    title.text =
        [self licenseExpired]
            ? [Translations tr:@"license_expired"]
            : [Translations tr:@"license_active"];

    title.textColor =
        [self licenseExpired]
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

    timer.translatesAutoresizingMaskIntoConstraints = NO;

    timer.tag = 8001;

    timer.text =
        [self licenseRemaining];

    timer.textColor =
        [self licenseExpired]
            ? [UIColor systemRedColor]
            : accent;

    timer.font =
        [UIFont monospacedSystemFontOfSize:26.0
                                    weight:UIFontWeightBold];

    timer.textAlignment =
        NSTextAlignmentCenter;

    timer.adjustsFontSizeToFitWidth = YES;
    timer.minimumScaleFactor = 0.55;

    [card addSubview:timer];

    UILabel *expires =
        [[UILabel alloc] init];

    expires.translatesAutoresizingMaskIntoConstraints = NO;

    expires.tag = 8002;

    expires.text =
        [self licenseExpirationText];

    expires.textColor =
        [UIColor colorWithWhite:0.52 alpha:1.0];

    expires.font =
        [UIFont monospacedSystemFontOfSize:12.0
                                    weight:UIFontWeightMedium];

    expires.textAlignment =
        NSTextAlignmentCenter;

    [card addSubview:expires];

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

        [title.topAnchor
            constraintEqualToAnchor:
                card.topAnchor
                constant:18.0],

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
                constant:5.0],

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
                constant:-16.0],

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
            [cell.contentView viewWithTag:8001];

    UILabel *expires =
        (UILabel *)
            [cell.contentView viewWithTag:8002];

    timer.text =
        [self licenseRemaining];

    expires.text =
        [self licenseExpirationText];
}

#pragma mark - Data Source

- (NSInteger)numberOfSectionsInTableView:
    (UITableView *)tableView {

    return 3;
}

- (NSInteger)tableView:
    (UITableView *)tableView
numberOfRowsInSection:
    (NSInteger)section {

    if (section == 0) {
        return 1;
    }

    if (section == 1) {
        return self.languageExpanded ? 5 : 2;
    }

    return 1;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
    cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (indexPath.section == 0) {
        return [self licenseCell:tableView];
    }

    static NSString *cellID =
        @"SettingsCell";

    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:
            cellID];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:UITableViewCellStyleSubtitle
                reuseIdentifier:cellID];

        cell.backgroundColor =
            [self panelColor];

        cell.selectionStyle =
            UITableViewCellSelectionStyleDefault;
    }

    cell.accessoryType =
        UITableViewCellAccessoryNone;

    cell.accessoryView = nil;

    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;

    cell.textLabel.textColor =
        UIColor.whiteColor;

    cell.detailTextLabel.textColor =
        [UIColor colorWithWhite:0.55 alpha:1.0];

    cell.imageView.tintColor =
        [self accentColor];

    /*
     * PREFERENCIAS
     */
    if (indexPath.section == 1) {

        if (indexPath.row == 0) {

            cell.imageView.image =
                [UIImage systemImageNamed:@"globe"];

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
        if (self.languageExpanded &&
            indexPath.row >= 1 &&
            indexPath.row <= 3) {

            NSInteger language =
                indexPath.row - 1;

            NSString *name = nil;

            if (language == 0) {
                name = [Translations tr:@"spanish"];
            } else if (language == 1) {
                name = [Translations tr:@"english"];
            } else {
                name = [Translations tr:@"portuguese"];
            }

            cell.imageView.image =
                [UIImage systemImageNamed:@"globe"];

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
         * Protección
         */
        BOOL protectionRow =
            (!self.languageExpanded &&
             indexPath.row == 1) ||
            (self.languageExpanded &&
             indexPath.row == 4);

        if (protectionRow) {

            cell.imageView.image =
                [UIImage systemImageNamed:
                    @"shield.lefthalf.filled"];

            cell.textLabel.text =
                [Translations tr:@"protection"];

            cell.detailTextLabel.text =
                [Translations tr:@"protection_desc"];

            cell.detailTextLabel.numberOfLines = 2;

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
    }

    /*
     * INFORMACIÓN
     */
    if (indexPath.section == 2) {

        cell.imageView.image =
            [UIImage systemImageNamed:@"info.circle"];

        cell.textLabel.text =
            [Translations tr:@"app_version"];

        cell.detailTextLabel.text =
            @"1.0.0";

        return cell;
    }

    return cell;
}

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

- (CGFloat)tableView:
    (UITableView *)tableView
heightForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (indexPath.section == 0) {
        return 165.0;
    }

    if (indexPath.section == 1 &&
        self.languageExpanded &&
        indexPath.row == 4) {

        return 86.0;
    }

    return 64.0;
}

#pragma mark - Delegate

- (void)tableView:
    (UITableView *)tableView
    didSelectRowAtIndexPath:
    (NSIndexPath *)indexPath {

    [tableView deselectRowAtIndexPath:indexPath
                             animated:YES];

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

    if (indexPath.section == 1 &&
        self.languageExpanded &&
        indexPath.row >= 1 &&
        indexPath.row <= 3) {

        [self selectLanguage:indexPath.row - 1];
    }
}

@end
