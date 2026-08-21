#import "MainSettingsViewController.h"
#import "Translations.h"

@interface MainSettingsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSTimer *licenseTimer;

@end

@implementation MainSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.03
                        alpha:1.0];

    self.title = @"Ajustes";

    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeAlways;

    self.tableView =
        [[UITableView alloc]
            initWithFrame:self.view.bounds
                    style:UITableViewStyleGrouped];

    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

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

    self.licenseTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(updateLicenseCard)
                                       userInfo:nil
                                        repeats:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

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
}

#pragma mark - Helpers

- (UIColor *)accentColor {
    return [UIColor colorWithRed:0.20
                           green:1.00
                            blue:0.50
                           alpha:1.0];
}

- (NSString *)currentLanguageName {

    NSInteger language =
        [[NSUserDefaults standardUserDefaults]
            integerForKey:@"selectedLanguage"];

    switch (language) {

        case 1:
            return @"English";

        case 2:
            return @"Português";

        default:
            return @"Español";
    }
}

- (BOOL)screenProtectionEnabled {

    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"screenProtection"];
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

- (BOOL)licenseIsExpired {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {
        return NO;
    }

    return [expiration timeIntervalSinceNow] <= 0;
}

- (NSString *)licenseTimeRemaining {

    NSDate *expiration =
        [self licenseExpirationDate];

    if (!expiration) {
        return @"SIN VENCIMIENTO";
    }

    NSTimeInterval remaining =
        [expiration timeIntervalSinceNow];

    if (remaining <= 0) {
        return @"EXPIRADA";
    }

    NSInteger totalSeconds =
        (NSInteger)remaining;

    NSInteger days =
        totalSeconds / 86400;

    totalSeconds %= 86400;

    NSInteger hours =
        totalSeconds / 3600;

    totalSeconds %= 3600;

    NSInteger minutes =
        totalSeconds / 60;

    NSInteger seconds =
        totalSeconds % 60;

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
        return @"Sin fecha de vencimiento";
    }

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.locale =
        [NSLocale currentLocale];

    formatter.dateFormat =
        @"dd/MM/yyyy · HH:mm:ss";

    return [NSString stringWithFormat:
        @"Vence: %@",
        [formatter stringFromDate:expiration]];
}

#pragma mark - License Card

- (UITableViewCell *)licenseCardCellForTableView:
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

    for (UIView *subview in
         cell.contentView.subviews) {

        [subview removeFromSuperview];
    }

    UIColor *accent =
        [self accentColor];

    UIView *card =
        [[UIView alloc] init];

    card.translatesAutoresizingMaskIntoConstraints =
        NO;

    card.backgroundColor =
        [UIColor colorWithRed:0.055
                        green:0.055
                         blue:0.075
                        alpha:1.0];

    card.layer.cornerRadius = 20.0;

    card.layer.borderWidth = 1.0;

    card.layer.borderColor =
        [accent colorWithAlphaComponent:0.18].CGColor;

    card.layer.shadowColor =
        UIColor.blackColor.CGColor;

    card.layer.shadowOpacity = 0.25;
    card.layer.shadowRadius = 14.0;
    card.layer.shadowOffset =
        CGSizeMake(0, 8);

    [cell.contentView addSubview:card];

    UIImageView *iconView =
        [[UIImageView alloc]
            initWithImage:
                [UIImage systemImageNamed:
                    @"checkmark.shield.fill"]];

    iconView.translatesAutoresizingMaskIntoConstraints =
        NO;

    iconView.tintColor =
        accent;

    iconView.contentMode =
        UIViewContentModeScaleAspectFit;

    [card addSubview:iconView];

    UILabel *titleLabel =
        [[UILabel alloc] init];

    titleLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    titleLabel.text =
        @"LICENCIA ACTIVA";

    titleLabel.textColor =
        UIColor.whiteColor;

    titleLabel.font =
        [UIFont systemFontOfSize:15.0
                          weight:UIFontWeightBold];

    titleLabel.textAlignment =
        NSTextAlignmentCenter;

    [card addSubview:titleLabel];

    UILabel *timerLabel =
        [[UILabel alloc] init];

    timerLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    timerLabel.tag = 8001;

    timerLabel.text =
        [self licenseTimeRemaining];

    timerLabel.textColor =
        accent;

    timerLabel.font =
        [UIFont monospacedSystemFontOfSize:29.0
                                    weight:UIFontWeightBold];

    timerLabel.textAlignment =
        NSTextAlignmentCenter;

    timerLabel.adjustsFontSizeToFitWidth =
        YES;

    timerLabel.minimumScaleFactor = 0.60;

    [card addSubview:timerLabel];

    UILabel *expiresLabel =
        [[UILabel alloc] init];

    expiresLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    expiresLabel.tag = 8002;

    expiresLabel.text =
        [self licenseExpirationText];

    expiresLabel.textColor =
        [UIColor colorWithWhite:0.55
                          alpha:1.0];

    expiresLabel.font =
        [UIFont monospacedSystemFontOfSize:12.0
                                    weight:UIFontWeightMedium];

    expiresLabel.textAlignment =
        NSTextAlignmentCenter;

    [card addSubview:expiresLabel];

    BOOL expired =
        [self licenseIsExpired];

    if (expired) {

        titleLabel.text =
            @"LICENCIA EXPIRADA";

        titleLabel.textColor =
            [UIColor systemRedColor];

        timerLabel.textColor =
            [UIColor systemRedColor];

        iconView.image =
            [UIImage systemImageNamed:
                @"xmark.shield.fill"];

        iconView.tintColor =
            [UIColor systemRedColor];
    }

    if (!expired &&
        [self licenseExpirationDate] == nil) {

        titleLabel.text =
            @"LICENCIA ACTIVA";

        timerLabel.text =
            @"SIN VENCIMIENTO";

        timerLabel.font =
            [UIFont systemFontOfSize:21.0
                              weight:UIFontWeightBold];
    }

    [NSLayoutConstraint activateConstraints:@[

        [card.topAnchor
            constraintEqualToAnchor:
                cell.contentView.topAnchor
                constant:4.0],

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

        [iconView.topAnchor
            constraintEqualToAnchor:
                card.topAnchor
                constant:18.0],

        [iconView.centerXAnchor
            constraintEqualToAnchor:
                card.centerXAnchor],

        [iconView.widthAnchor
            constraintEqualToConstant:24.0],

        [iconView.heightAnchor
            constraintEqualToConstant:24.0],

        [titleLabel.topAnchor
            constraintEqualToAnchor:
                iconView.bottomAnchor
                constant:7.0],

        [titleLabel.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:20.0],

        [titleLabel.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-20.0],

        [titleLabel.heightAnchor
            constraintEqualToConstant:20.0],

        [timerLabel.topAnchor
            constraintEqualToAnchor:
                titleLabel.bottomAnchor
                constant:7.0],

        [timerLabel.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:12.0],

        [timerLabel.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-12.0],

        [timerLabel.heightAnchor
            constraintEqualToConstant:38.0],

        [expiresLabel.topAnchor
            constraintEqualToAnchor:
                timerLabel.bottomAnchor
                constant:2.0],

        [expiresLabel.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:20.0],

        [expiresLabel.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-20.0],

        [expiresLabel.bottomAnchor
            constraintEqualToAnchor:
                card.bottomAnchor
                constant:-18.0],

        [expiresLabel.heightAnchor
            constraintEqualToConstant:18.0]
    ]];

    return cell;
}

- (void)updateLicenseCard {

    NSIndexPath *indexPath =
        [NSIndexPath indexPathForRow:0
                           inSection:0];

    UITableViewCell *cell =
        [self.tableView
            cellForRowAtIndexPath:indexPath];

    if (!cell) {
        return;
    }

    UILabel *timerLabel =
        (UILabel *)
            [cell.contentView
                viewWithTag:8001];

    UILabel *expiresLabel =
        (UILabel *)
            [cell.contentView
                viewWithTag:8002];

    if ([timerLabel isKindOfClass:[UILabel class]]) {

        timerLabel.text =
            [self licenseTimeRemaining];

        if ([self licenseIsExpired]) {

            timerLabel.textColor =
                [UIColor systemRedColor];

        } else {

            timerLabel.textColor =
                [self accentColor];
        }
    }

    if ([expiresLabel isKindOfClass:[UILabel class]]) {

        expiresLabel.text =
            [self licenseExpirationText];
    }
}

#pragma mark - Language

- (void)showLanguagePicker {

    NSString *current =
        [self currentLanguageName];

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"Idioma"
            message:
                [NSString stringWithFormat:
                    @"Actual: %@",
                    current]
            preferredStyle:
                UIAlertControllerStyleActionSheet];

    NSArray<NSString *> *languages = @[
        @"Español",
        @"English",
        @"Português"
    ];

    for (NSInteger i = 0;
         i < languages.count;
         i++) {

        NSString *language =
            languages[i];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:language
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {

                    [[NSUserDefaults standardUserDefaults]
                        setInteger:i
                        forKey:@"selectedLanguage"];

                    [[NSUserDefaults standardUserDefaults]
                        synchronize];

                    [Translations setLanguage:i];

                    [self.tableView reloadData];

                    [self updateLicenseCard];
                }]];
    }

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"Cancelar"
            style:UIAlertActionStyleCancel
            handler:nil]];

    if (alert.popoverPresentationController) {

        alert.popoverPresentationController.sourceView =
            self.view;

        alert.popoverPresentationController.sourceRect =
            CGRectMake(CGRectGetMidX(self.view.bounds),
                       CGRectGetMidY(self.view.bounds),
                       1.0,
                       1.0);
    }

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

#pragma mark - UITableViewDataSource

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
        return 2;
    }

    return 1;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
    cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (indexPath.section == 0) {

        return [self
            licenseCardCellForTableView:
                tableView];
    }

    static NSString *cellId =
        @"MainSettingsCell";

    UITableViewCell *cell =
        [tableView
            dequeueReusableCellWithIdentifier:
                cellId];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:
                    UITableViewCellStyleValue1
                reuseIdentifier:
                    cellId];

        cell.backgroundColor =
            [UIColor colorWithRed:0.08
                            green:0.08
                             blue:0.10
                            alpha:1.0];

        cell.layer.cornerRadius = 12.0;

        cell.selectionStyle =
            UITableViewCellSelectionStyleDefault;
    }

    UIColor *accent =
        [self accentColor];

    cell.textLabel.textColor =
        UIColor.whiteColor;

    cell.detailTextLabel.textColor =
        [UIColor colorWithWhite:0.55
                          alpha:1.0];

    cell.imageView.tintColor =
        accent;

    cell.accessoryType =
        UITableViewCellAccessoryNone;

    cell.accessoryView = nil;

    if (indexPath.section == 1) {

        if (indexPath.row == 0) {

            cell.imageView.image =
                [UIImage systemImageNamed:
                    @"globe"];

            cell.textLabel.text =
                @"Idioma";

            cell.detailTextLabel.text =
                [self currentLanguageName];

            cell.accessoryType =
                UITableViewCellAccessoryDisclosureIndicator;

        } else {

            cell.imageView.image =
                [UIImage systemImageNamed:
                    @"record.circle"];

            cell.textLabel.text =
                @"Ocultar al grabar";

            BOOL enabled =
                [self screenProtectionEnabled];

            cell.detailTextLabel.text =
                enabled
                    ? @"Activado"
                    : @"Desactivado";

            cell.detailTextLabel.textColor =
                enabled
                    ? accent
                    : [UIColor colorWithWhite:0.45
                                        alpha:1.0];

            UISwitch *toggle =
                [[UISwitch alloc] init];

            toggle.on = enabled;

            toggle.onTintColor =
                accent;

            toggle.tag = 9001;

            [toggle addTarget:self
                       action:@selector(
                           screenProtectionChanged:)
             forControlEvents:
                 UIControlEventValueChanged];

            cell.accessoryView =
                toggle;
        }

    } else {

        cell.imageView.image =
            [UIImage systemImageNamed:
                @"info.circle"];

        cell.textLabel.text =
            @"Versión de la App";

        cell.detailTextLabel.text =
            @"1.0.0";
    }

    return cell;
}

- (NSString *)tableView:
    (UITableView *)tableView
    titleForHeaderInSection:
    (NSInteger)section {

    if (section == 0) {
        return @"LICENCIA";
    }

    if (section == 1) {
        return @"PREFERENCIAS";
    }

    return @"INFORMACIÓN";
}

- (CGFloat)tableView:
    (UITableView *)tableView
heightForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (indexPath.section == 0) {
        return 168.0;
    }

    return 56.0;
}

- (CGFloat)tableView:
    (UITableView *)tableView
heightForHeaderInSection:
    (NSInteger)section {

    return 34.0;
}

#pragma mark - Protection

- (void)screenProtectionChanged:
    (UISwitch *)sender {

    [[NSUserDefaults standardUserDefaults]
        setBool:sender.isOn
        forKey:@"screenProtection"];

    [[NSUserDefaults standardUserDefaults]
        synchronize];

    [self.tableView reloadRowsAtIndexPaths:@[
        [NSIndexPath indexPathForRow:1
                           inSection:1]
    ]
                          withRowAnimation:
                              UITableViewRowAnimationNone];
}

#pragma mark - UITableViewDelegate

- (void)tableView:
    (UITableView *)tableView
    didSelectRowAtIndexPath:
    (NSIndexPath *)indexPath {

    [tableView deselectRowAtIndexPath:indexPath
                             animated:YES];

    if (indexPath.section == 1 &&
        indexPath.row == 0) {

        [self showLanguagePicker];
    }
}

@end
