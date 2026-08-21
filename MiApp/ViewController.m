//
//  ViewController.m
//  MiApp
//
//  Explorador de archivos con diseño moderno y sistema de clave.
//

#import "ViewController.h"
#import <UniformTypeIdentifiers/UTCoreTypes.h>  // Para iOS 14+

@interface ViewController ()
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, assign) BOOL unlocked;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Comprobar si está desbloqueado
    _unlocked = [[NSUserDefaults standardUserDefaults] boolForKey:@"IsUnlocked"];
    if (!_unlocked) {
        [self showKeyActivation];
    }
    
    // 2. Configurar la vista con degradado
    [self setupGradientBackground];
    
    // 3. Configurar SearchBar (moderna)
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    _searchBar.delegate = self;
    _searchBar.placeholder = @"Buscar archivos...";
    _searchBar.barStyle = UIBarStyleBlack;
    _searchBar.tintColor = [UIColor whiteColor];
    _searchBar.searchTextField.textColor = [UIColor whiteColor];
    _searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    [self.view addSubview:_searchBar];
    
    // 4. Configurar TableView
    CGFloat tabY = CGRectGetMaxY(_searchBar.frame);
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tabY, self.view.bounds.size.width, self.view.bounds.size.height - tabY) style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.contentInset = UIEdgeInsetsMake(10, 15, 10, 15);
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:_tableView];
    
    // 5. Cargar archivos desde la raíz (o desde Documents)
    _currentPath = NSHomeDirectory(); // O puedes poner @"/var/mobile" para jailbreak
    _fileList = [[NSMutableArray alloc] init];
    _filteredFiles = @[];
    [self loadFilesAtPath:_currentPath];
}

- (void)setupGradientBackground {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.view.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.07 green:0.07 blue:0.15 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.15 green:0.02 blue:0.25 alpha:1].CGColor
    ];
    [self.view.layer insertSublayer:gradient atIndex:0];
}

#pragma mark - Carga de archivos

- (void)loadFilesAtPath:(NSString *)path {
    NSError *error;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (error) {
        // Mostrar error (opcional)
        return;
    }
    [_fileList removeAllObjects];
    for (NSString *item in contents) {
        // Ocultar archivos que empiecen por "." (opcional)
        if ([item hasPrefix:@"."]) continue;
        NSString *fullPath = [path stringByAppendingPathComponent:item];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil];
        BOOL isDir = [[attrs objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory];
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"name"] = item;
        dict[@"path"] = fullPath;
        dict[@"isDir"] = @(isDir);
        dict[@"size"] = attrs[NSFileSize] ? attrs[NSFileSize] : @0;
        dict[@"modDate"] = attrs[NSFileModificationDate] ? attrs[NSFileModificationDate] : [NSDate date];
        [_fileList addObject:dict];
    }
    // Ordenar: carpetas primero, luego archivos
    [_fileList sortUsingComparator:^NSComparisonResult(id a, id b) {
        BOOL dirA = [[a objectForKey:@"isDir"] boolValue];
        BOOL dirB = [[b objectForKey:@"isDir"] boolValue];
        if (dirA && !dirB) return NSOrderedAscending;
        if (!dirA && dirB) return NSOrderedDescending;
        return [[a objectForKey:@"name"] compare:[b objectForKey:@"name"]];
    }];
    _filteredFiles = [_fileList copy];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _filteredFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"ModernCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        cell.layer.cornerRadius = 15;
        cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        
        // Flecha de acceso
        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        arrow.tintColor = [UIColor colorWithWhite:1 alpha:0.3];
        cell.accessoryView = arrow;
    }
    
    NSDictionary *item = _filteredFiles[indexPath.row];
    NSString *name = item[@"name"];
    BOOL isDir = [item[@"isDir"] boolValue];
    NSNumber *size = item[@"size"];
    NSDate *modDate = item[@"modDate"];
    
    cell.textLabel.text = name;
    
    // Detalle: tamaño y fecha
    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:[size longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateStyle = NSDateFormatterShortStyle;
    df.timeStyle = NSDateFormatterShortStyle;
    NSString *dateStr = [df stringFromDate:modDate];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %@", sizeStr, dateStr];
    
    // Icono según tipo
    UIImage *icon;
    UIColor *color;
    if (isDir) {
        icon = [UIImage systemImageNamed:@"folder.fill"];
        color = [UIColor systemYellowColor];
    } else {
        // Detectar tipo por extensión
        NSString *ext = [name pathExtension];
        if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"png"] || [ext isEqualToString:@"gif"]) {
            icon = [UIImage systemImageNamed:@"photo.fill"];
            color = [UIColor systemGreenColor];
        } else if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
            icon = [UIImage systemImageNamed:@"video.fill"];
            color = [UIColor systemRedColor];
        } else if ([ext isEqualToString:@"mp3"] || [ext isEqualToString:@"wav"]) {
            icon = [UIImage systemImageNamed:@"music.note"];
            color = [UIColor systemPinkColor];
        } else if ([ext isEqualToString:@"plist"] || [ext isEqualToString:@"strings"]) {
            icon = [UIImage systemImageNamed:@"doc.plaintext.fill"];
            color = [UIColor systemBlueColor];
        } else {
            icon = [UIImage systemImageNamed:@"doc.fill"];
            color = [UIColor systemGrayColor];
        }
    }
    cell.imageView.image = icon;
    cell.imageView.tintColor = color;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 70;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_unlocked) {
        [self showKeyActivation];
        return;
    }
    NSDictionary *item = _filteredFiles[indexPath.row];
    BOOL isDir = [item[@"isDir"] boolValue];
    if (isDir) {
        // Navegar a la carpeta
        _currentPath = item[@"path"];
        [self loadFilesAtPath:_currentPath];
        // Scroll arriba
        [self.tableView setContentOffset:CGPointZero animated:YES];
    } else {
        // Archivo: mostrar opciones (compartir, etc.)
        [self showFileActions:item];
    }
}

- (void)showFileActions:(NSDictionary *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"name"]
                                                                   message:@"¿Qué deseas hacer?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Compartir" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // Lógica para compartir archivo
        NSURL *url = [NSURL fileURLWithPath:item[@"path"]];
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        [self presentViewController:share animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        _filteredFiles = [_fileList copy];
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", searchText];
        _filteredFiles = [_fileList filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Sistema de Clave

- (void)showKeyActivation {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔐 Activación requerida"
                                                                   message:@"Introduce la clave para acceder al explorador"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Clave (8 caracteres)";
        textField.secureTextEntry = YES;
        textField.textColor = [UIColor whiteColor];
        textField.backgroundColor = [UIColor darkGrayColor];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Desbloquear" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = alert.textFields.firstObject.text;
        if ([self validateKey:key]) {
            _unlocked = YES;
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IsUnlocked"];
            [[NSUserDefaults standardUserDefaults] setObject:key forKey:@"AppKey"];
            [self.tableView reloadData];
        } else {
            [self showKeyActivation]; // Volver a pedir
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salir" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)validateKey:(NSString *)key {
    // Cambia esta condición por la clave que quieras
    // Ejemplo: clave fija "PROKEY23"
    if ([key isEqualToString:@"PROKEY23"]) return YES;
    // O validar longitud y suma (para ejemplo)
    if (key.length == 8) {
        int sum = 0;
        for (int i = 0; i < key.length; i++) {
            unichar c = [key characterAtIndex:i];
            if (c >= '0' && c <= '9') sum += (c - '0');
        }
        if (sum == 20) return YES;
    }
    return NO;
}

- (BOOL)isUnlocked {
    return _unlocked;
}

@end
