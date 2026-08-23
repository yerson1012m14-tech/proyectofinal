#import "ViewController.h"
#import <dlfcn.h>

static void asegurarMotor(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        /*
         * TweakInit es constructor del dylib y ya fue ejecutado por el loader.
         * No se llama manualmente para evitar reinstalar hooks.
         */
        void (*start)(void) =
            (void (*)(void))dlsym(
                RTLD_DEFAULT,
                "MCMFilzaStart"
            );

        if (start) {
            start();
        }
    });
}

static NSString *mcmVirtualRoot(void) {
    asegurarMotor();

    NSString *(*virtualRoot)(void) =
        (NSString *(*)(void))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaVirtualRoot"
        );

    NSString *root = virtualRoot ? virtualRoot() : nil;
    return ([root isKindOfClass:[NSString class]] && root.length > 0)
        ? [root stringByStandardizingPath]
        : nil;
}

static NSString *containerPath(NSString *bid) {
    if (bid.length == 0) return nil;

    asegurarMotor();

    NSString *(*dataPath)(NSString *, NSString **) =
        (NSString *(*)(NSString *, NSString **))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaDataContainerPath"
        );

    NSString *detail = nil;
    NSString *path = dataPath ? dataPath(bid, &detail) : nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([path isKindOfClass:[NSString class]] && path.length > 0) {
        NSString *standard = [path stringByStandardizingPath];
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:standard isDirectory:&isDirectory] && isDirectory) {
            return standard;
        }
    }

    NSString *root = mcmVirtualRoot();
    if (root.length > 0) {
        NSString *fallback =
            [[root stringByAppendingPathComponent:@"[MHA-C2] App Data"]
                stringByAppendingPathComponent:bid];

        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:fallback isDirectory:&isDirectory] && isDirectory) {
            return fallback;
        }
    }

    NSLog(
        @"XITFORGE Explorer: contenedor no resuelto %@ detail=%@",
        bid,
        detail ?: @"sin detalle"
    );

    return nil;
}

static NSString *fmtSize(unsigned long long b) {
    if (b < 1024) return [NSString stringWithFormat:@"%llu B", b];
    if (b < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", b / 1024.0];
    if (b < 1024 * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", b / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", b / (1024.0 * 1024.0 * 1024.0)];
}

static void ponerIcono(UITableViewCell *c, NSString *nombre, UIColor *tinte) {
    c.imageView.image = [[UIImage systemImageNamed:nombre] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    c.imageView.tintColor = tinte;
}

static UIColor *colorFondo(void) { return [UIColor colorWithRed:0.02 green:0.02 blue:0.03 alpha:1.0]; }
static UIColor *colorCard(void) { return [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0]; }
static UIColor *acento(void) { return [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0]; }
static UIColor *textoBlanco(void) { return [UIColor colorWithWhite:0.96 alpha:1.0]; }
static UIColor *textoGris(void) { return [UIColor colorWithWhite:0.50 alpha:1.0]; }

#pragma mark - Visor de texto
@interface TextViewVC : UIViewController
@property (nonatomic, strong) NSString *ruta;
@end

@implementation TextViewVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = colorFondo();
    self.title = self.ruta.lastPathComponent;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.selectable = YES;
    tv.textColor = textoBlanco();
    tv.backgroundColor = colorFondo();
    tv.font = [UIFont fontWithName:@"Menlo" size:11];
    tv.contentInset = UIEdgeInsetsMake(10, 10, 10, 10);
    [self.view addSubview:tv];
    
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.ruta error:nil];
    unsigned long long size = [[attrs objectForKey:@"NSFileSize"] unsignedLongLongValue];
    
    if (size > 2 * 1024 * 1024) {
        tv.text = [NSString stringWithFormat:@"(archivo demasiado grande: %@)", fmtSize(size)];
        tv.textColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.10 alpha:1.0];
    } else {
        NSData *d = [NSData dataWithContentsOfFile:self.ruta];
        NSString *s = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
        tv.text = s ?: [NSString stringWithFormat:@"(binario, %@)", fmtSize(size)];
        if (!s) tv.textColor = textoGris();
    }
}

@end

#pragma mark - Navegador de carpetas
@interface FileBrowserVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSString *ruta;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UITableView *tv;
@end

@implementation FileBrowserVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = colorFondo();
    self.title = self.ruta.lastPathComponent;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.backgroundColor = colorFondo();
    self.tv.separatorColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.tv.separatorInset = UIEdgeInsetsMake(0, 15, 0, 15);
    self.tv.dataSource = self;
    self.tv.delegate = self;
    self.tv.contentInset = UIEdgeInsetsMake(0, 0, 60, 0);
    [self.view addSubview:self.tv];
[self recargar];
}
- (void)recargar {
    NSMutableArray *dirs = [NSMutableArray new], *files = [NSMutableArray new];
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.ruta error:nil];
    for (NSString *n in [all sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:[self.ruta stringByAppendingPathComponent:n] isDirectory:&isDir];
        if (isDir) { [dirs addObject:n]; } else { [files addObject:n]; }
    }
    NSMutableArray *fin = [NSMutableArray new];
    if (![self.ruta isEqualToString:@"/"]) [fin addObject:@".."];
    [fin addObjectsFromArray:dirs];
    [fin addObjectsFromArray:files];
    self.items = fin;
    [self.tv reloadData];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
        c.backgroundColor = [UIColor clearColor];
        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        c.selectedBackgroundView = bg;
    }
    NSString *n = self.items[ip.row];
    c.textLabel.text = n;
    c.textLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    c.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
    c.detailTextLabel.textColor = textoGris();
    
    if ([n isEqualToString:@".."]) {
        ponerIcono(c, @"arrow.uturn.left", textoGris());
        c.textLabel.textColor = textoGris();
        c.detailTextLabel.text = @"subir";
        c.accessoryType = UITableViewCellAccessoryNone;
    } else if ([self esDir:n]) {
        ponerIcono(c, @"folder.fill", [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0]);
        c.textLabel.textColor = textoBlanco();
        c.detailTextLabel.text = @"carpeta";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        ponerIcono(c, @"doc.fill", textoGris());
        c.textLabel.textColor = textoBlanco();
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:[self.ruta stringByAppendingPathComponent:n] error:nil];
        c.detailTextLabel.text = fmtSize([[a objectForKey:@"NSFileSize"] unsignedLongLongValue]);
        c.accessoryType = UITableViewCellAccessoryNone;
    }
    return c;
}

- (BOOL)esDir:(NSString *)n {
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:[self.ruta stringByAppendingPathComponent:n] isDirectory:&isDir];
    return isDir;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSString *n = self.items[ip.row];
    if ([n isEqualToString:@".."]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSString *full = [self.ruta stringByAppendingPathComponent:n];
    if ([self esDir:n]) {
        FileBrowserVC *fb = [FileBrowserVC new];
        fb.ruta = full;
        [self.navigationController pushViewController:fb animated:YES];
    } else {
        TextViewVC *tv = [TextViewVC new];
        tv.ruta = full;
        [self.navigationController pushViewController:tv animated:YES];
    }
}

- (BOOL)tableView:(UITableView *)tableView
canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    /*
     * Explorador de solo lectura:
     * no hay swipe-to-delete ni borrado de archivos/carpetas.
     */
    return NO;
}

@end

#pragma mark - Pantalla principal (Explorador)
@interface ViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tv;
@property (nonatomic, strong) UITextField *campo;
@property (nonatomic, strong) NSMutableArray *apps;
@property (nonatomic, strong) UILabel *vacioLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = colorFondo();
    self.title = @"Explorar";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(cargarApps)];
    refreshBtn.tintColor = acento();
    
    UIBarButtonItem *rootBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(irARaiz)];
    rootBtn.tintColor = acento();
    
    self.navigationItem.rightBarButtonItems = @[refreshBtn, rootBtn];
    
    self.apps = [NSMutableArray new];
    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.backgroundColor = colorFondo();
    self.tv.separatorColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.tv.separatorInset = UIEdgeInsetsMake(0, 15, 0, 15);
    self.tv.dataSource = self;
    self.tv.delegate = self;
    
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    header.backgroundColor = colorFondo();
    
    self.campo = [[UITextField alloc] initWithFrame:CGRectMake(12, 10, header.bounds.size.width - 24, 40)];
    self.campo.placeholder = @"bundle id + return";
    self.campo.backgroundColor = colorCard();
    self.campo.layer.cornerRadius = 12;
    self.campo.layer.borderWidth = 1;
    self.campo.layer.borderColor = [UIColor colorWithWhite:0.20 alpha:1.0].CGColor;
    self.campo.textColor = textoBlanco();
    self.campo.font = [UIFont fontWithName:@"Menlo" size:12];
    self.campo.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.campo.autocorrectionType = UITextAutocorrectionTypeNo;
    self.campo.returnKeyType = UIReturnKeyDone;
    self.campo.delegate = self;
    
    UIImageView *lupa = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 24, 20)];
    lupa.image = [[UIImage systemImageNamed:@"magnifyingglass"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    lupa.tintColor = textoGris();
    lupa.contentMode = UIViewContentModeCenter;
    self.campo.leftView = lupa;
    self.campo.leftViewMode = UITextFieldViewModeAlways;
    [header addSubview:self.campo];
    self.tv.tableHeaderView = header;
    [self.view addSubview:self.tv];
    
    self.vacioLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 150, self.view.bounds.size.width - 60, 120)];
    self.vacioLabel.numberOfLines = 0;
    self.vacioLabel.textAlignment = NSTextAlignmentCenter;
    self.vacioLabel.textColor = textoGris();
    self.vacioLabel.font = [UIFont fontWithName:@"Menlo" size:12];
    self.vacioLabel.text = @"No se detectaron apps.\nEscribe arriba el bundle ID\nde una app instalada.";
    self.vacioLabel.hidden = YES;
    [self.view addSubview:self.vacioLabel];
    
    [self cargarApps];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self cargarApps];
}

- (void)irARaiz {
    @try {
        NSString *root = mcmVirtualRoot();
        if (!root.length) return;
        FileBrowserVC *fb = [FileBrowserVC new];
        fb.ruta = root;
        [self.navigationController pushViewController:fb animated:YES];
    } @catch (NSException *exception) {
        NSLog(@"Error al ir a raíz: %@", exception);
    }
}

- (void)cargarApps {
    @try {
        NSMutableOrderedSet *set = [NSMutableOrderedSet new];
        Class ws = NSClassFromString(@"LSApplicationWorkspace");
        if (ws && [ws respondsToSelector:@selector(defaultWorkspace)]) {
            id workspace = [ws performSelector:@selector(defaultWorkspace)];
            if (workspace && [workspace respondsToSelector:@selector(allApplications)]) {
                NSArray *all = [workspace performSelector:@selector(allApplications)];
                for (id proxy in all) {
                    @try {
                        if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
                            NSString *bid = [proxy performSelector:@selector(applicationIdentifier)];
                            if (bid && ![bid hasPrefix:@"com.apple."]) [set addObject:bid];
                        }
                    } @catch (NSException *e) {}
                }
            }
        }
        
        NSString *root = mcmVirtualRoot();
        if (root.length > 0) {
            NSString *appData =
                [root stringByAppendingPathComponent:@"[MHA-C2] App Data"];
            NSArray<NSString *> *entries =
                [[NSFileManager defaultManager]
                    contentsOfDirectoryAtPath:appData
                    error:nil];
            for (NSString *bid in entries ?: @[]) {
                if (bid.length > 0 && ![bid hasPrefix:@"."]) {
                    [set addObject:bid];
                }
            }
        }

        [self.apps removeAllObjects];
        [self.apps addObjectsFromArray:[set array]];
        [self.apps sortUsingSelector:@selector(localizedStandardCompare:)];
        self.title = [NSString stringWithFormat:@"Explorar (%lu)", (unsigned long)self.apps.count];
        self.vacioLabel.hidden = (self.apps.count != 0);
        [self.tv reloadData];
    } @catch (NSException *exception) {
        NSLog(@"Error al cargar apps: %@", exception);
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    [self abrirContenedor:tf.text];
    return YES;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.apps.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"a"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"a"];
        c.backgroundColor = [UIColor clearColor];
        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        c.selectedBackgroundView = bg;
    }
    c.textLabel.text = self.apps[ip.row];
    c.textLabel.textColor = acento();
    c.textLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    c.detailTextLabel.text = @"solo lectura";
    c.detailTextLabel.textColor = textoGris();
    c.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
    ponerIcono(c, @"app.fill", acento());
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    [self abrirContenedor:self.apps[ip.row]];
}

- (void)abrirContenedor:(NSString *)bid {
    @try {
        bid = [bid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!bid.length) return;
        
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            [self.navigationController popToRootViewControllerAnimated:NO];
        }
        NSString *p = nil;
        @try { p = containerPath(bid); } @catch (NSException *e) { p = nil; }
        
        if (!p) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sin contenedor"
                message:[NSString stringWithFormat:@"%@ no devolvió ruta (no instalada?)", bid]
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
            return;
        }
        
        FileBrowserVC *fb = [FileBrowserVC new];
        fb.ruta = p;
        [self.navigationController pushViewController:fb animated:YES];
    } @catch (NSException *exception) {
        NSLog(@"Error al abrir contenedor: %@", exception);
    }
}

@end
