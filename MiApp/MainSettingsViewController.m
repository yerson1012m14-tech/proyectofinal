#import "MainSettingsViewController.h"

@interface MainSettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation MainSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.03 alpha:1.0];
    self.title = @"Ajustes";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.03 alpha:1.0];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // Información
    if (section == 1) return 2; // Preferencias
    return 1;                   // Soporte
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"MainSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    
    UIColor *acento = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
    cell.textLabel.textColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.50 alpha:1.0];
    cell.imageView.tintColor = acento;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
            cell.textLabel.text = @"Versión de la App";
            cell.detailTextLabel.text = @"1.0.0";
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"shield.lefthalf.filled"];
            cell.textLabel.text = @"Estado de Licencia";
            cell.detailTextLabel.text = @"Activa";
            cell.detailTextLabel.textColor = acento;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"trash"];
            cell.textLabel.text = @"Borrar Caché";
            cell.detailTextLabel.text = @"0 MB";
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"lock.shield"];
            cell.textLabel.text = @"Privacidad";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"envelope"];
        cell.textLabel.text = @"Contactar Soporte";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"INFORMACIÓN";
    if (section == 1) return @"PREFERENCIAS";
    return @"SOPORTE";
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1 && indexPath.row == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Caché borrada" message:@"Se han liberado 0 MB de espacio." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
