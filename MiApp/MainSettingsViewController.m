#import "MainSettingsViewController.h"

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

    [self.view addSubview:self.tableView];

    /*
     * Actualizamos el tiempo restante periódicamente
     * mientras esta pantalla está abierta.
     */
    self.licenseTimer =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(updateLicenseTime)
                                       userInfo:nil
                                        repeats:YES];
}

- (void)dealloc {

    [self.licenseTimer invalidate];
    self.licenseTimer = nil;
}

#pragma mark - License

- (NSString *)licenseRemainingText {

    NSUserDefaults *defaults =
        [NSUserDefaults standardUserDefaults];

    NSString *expiresAtString =
        [defaults stringForKey:@"MiFilzaLicenseExpiresAt"];

    /*
     * Si no existe fecha:
     * puede ser una licencia sin vencimiento.
     */
    if (expiresAtString.length == 0) {
        return @"Sin vencimiento";
    }

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.locale =
        [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    formatter.dateFormat =
        @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX";

    NSDate *expiresAt =
        [formatter dateFromString:expiresAtString];

    /*
     * Compatibilidad por si el servidor devuelve
     * una fecha sin milisegundos.
     */
    if (!expiresAt) {

        formatter.dateFormat =
            @"yyyy-MM-dd'T'HH:mm:ssXXXXX";

        expiresAt =
            [formatter dateFromString:expiresAtString];
    }

    if (!expiresAt) {
        return @"Fecha no disponible";
    }

    NSTimeInterval remaining =
        [expiresAt timeIntervalSinceNow];

    if (remaining <= 0) {
        return @"Expirada";
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

    if (days > 0) {

        if (hours > 0) {
            return [NSString stringWithFormat:
                @"%ldd %ldh restantes",
                (long)days,
                (long)hours];
        }

        return [NSString stringWithFormat:
            @"%ldd restantes",
            (long)days];
    }

    if (hours > 0) {

        if (minutes > 0) {
            return [NSString stringWithFormat:
                @"%ldh %ldm restantes",
                (long)hours,
                (long)minutes];
        }

        return [NSString stringWithFormat:
            @"%ldh restantes",
            (long)hours];
    }

    if (minutes > 0) {

        return [NSString stringWithFormat:
            @"%ldm %lds restantes",
            (long)minutes,
            (long)seconds];
    }

    return [NSString stringWithFormat:
        @"%lds restantes",
        (long)seconds];
}

- (BOOL)licenseIsActive {

    NSUserDefaults *defaults =
        [NSUserDefaults standardUserDefaults];

    NSString *expiresAtString =
        [defaults stringForKey:@"MiFilzaLicenseExpiresAt"];

    if (expiresAtString.length == 0) {
        return YES;
    }

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.locale =
        [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    formatter.dateFormat =
        @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX";

    NSDate *expiresAt =
        [formatter dateFromString:expiresAtString];

    if (!expiresAt) {

        formatter.dateFormat =
            @"yyyy-MM-dd'T'HH:mm:ssXXXXX";

        expiresAt =
            [formatter dateFromString:expiresAtString];
    }

    if (!expiresAt) {
        return NO;
    }

    return [expiresAt timeIntervalSinceNow] > 0;
}

- (void)updateLicenseTime {

    NSIndexPath *licenseIndexPath =
        [NSIndexPath indexPathForRow:1
                           inSection:0];

    UITableViewCell *cell =
        [self.tableView cellForRowAtIndexPath:
            licenseIndexPath];

    if (!cell) {
        return;
    }

    UIColor *acento =
        [UIColor colorWithRed:0.2
                        green:1.0
                         blue:0.5
                        alpha:1.0];

    if ([self licenseIsActive]) {

        cell.textLabel.text =
            @"Estado de Licencia";

        cell.detailTextLabel.text =
            [self licenseRemainingText];

        cell.detailTextLabel.textColor =
            acento;

        cell.imageView.image =
            [UIImage systemImageNamed:
                @"checkmark.shield.fill"];

    } else {

        cell.textLabel.text =
            @"Estado de Licencia";

        cell.detailTextLabel.text =
            @"Expirada";

        cell.detailTextLabel.textColor =
            [UIColor systemRedColor];

        cell.imageView.image =
            [UIImage systemImageNamed:
                @"xmark.shield.fill"];
    }
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

    if (section == 0) return 2;
    if (section == 1) return 2;

    return 1;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
    cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    static NSString *cellId =
        @"MainSettingsCell";

    UITableViewCell *cell =
        [tableView
            dequeueReusableCellWithIdentifier:cellId];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:UITableViewCellStyleValue1
                reuseIdentifier:cellId];

        cell.backgroundColor =
            [UIColor colorWithRed:0.08
                            green:0.08
                             blue:0.10
                            alpha:1.0];

        cell.selectionStyle =
            UITableViewCellSelectionStyleGray;
    }

    UIColor *acento =
        [UIColor colorWithRed:0.2
                        green:1.0
                         blue:0.5
                        alpha:1.0];

    cell.textLabel.textColor =
        [UIColor colorWithWhite:0.96
                          alpha:1.0];

    cell.detailTextLabel.textColor =
        [UIColor colorWithWhite:0.50
                          alpha:1.0];

    cell.imageView.tintColor =
        acento;

    /*
     * Reset para evitar que una celda reutilizada
     * conserve accesorios de otra sección.
     */
    cell.accessoryType =
        UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {

        if (indexPath.row == 0) {

            cell.imageView.image =
                [UIImage systemImageNamed:@"info.circle"];

            cell.textLabel.text =
                @"Versión de la App";

            cell.detailTextLabel.text =
                @"1.0.0";

        } else {

            cell.imageView.image =
                [UIImage systemImageNamed:
                    @"shield.lefthalf.filled"];

            cell.textLabel.text =
                @"Estado de Licencia";

            if ([self licenseIsActive]) {

                cell.detailTextLabel.text =
                    [self licenseRemainingText];

                cell.detailTextLabel.textColor =
                    acento;

            } else {

                cell.detailTextLabel.text =
                    @"Expirada";

                cell.detailTextLabel.textColor =
                    [UIColor systemRedColor];
            }
        }

    } else if (indexPath.section == 1) {

        if (indexPath.row == 0) {

            cell.imageView.image =
                [UIImage systemImageNamed:@"trash"];

            cell.textLabel.text =
                @"Borrar Caché";

            cell.detailTextLabel.text =
                @"0 MB";

        } else {

            cell.imageView.image =
                [UIImage systemImageNamed:
                    @"lock.shield"];

            cell.textLabel.text =
                @"Privacidad";

            cell.accessoryType =
                UITableViewCellAccessoryDisclosureIndicator;
        }

    } else {

        cell.imageView.image =
            [UIImage systemImageNamed:@"envelope"];

        cell.textLabel.text =
            @"Contactar Soporte";

        cell.accessoryType =
            UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (NSString *)tableView:
    (UITableView *)tableView
    titleForHeaderInSection:
    (NSInteger)section {

    if (section == 0)
        return @"INFORMACIÓN";

    if (section == 1)
        return @"PREFERENCIAS";

    return @"SOPORTE";
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

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:
                    @"Caché borrada"
                message:
                    @"Se han liberado 0 MB de espacio."
                preferredStyle:
                    UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [self presentViewController:alert
                           animated:YES
                         completion:nil];
    }
}

@end
