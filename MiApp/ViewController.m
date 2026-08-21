#import "ViewController.h"
#import <dlfcn.h>

static void asegurarMotor(void) {
    static BOOL on = NO;
    if (on) return;
    on = YES;
    void (*tweakInit)(void) = dlsym(RTLD_DEFAULT, "TweakInit");
    int (*start)(void) = dlsym(RTLD_DEFAULT, "MCMFilzaStart");
    void (*setUnres)(int) = dlsym(RTLD_DEFAULT, "MCMFilzaSetUnrestrictedFilesystem");
    if (tweakInit) tweakInit();
    if (start) start();
    if (setUnres) setUnres(1);
}

static NSString *containerPath(NSString *bid) {
    NSString *(*dataPath)(NSString *) = dlsym(RTLD_DEFAULT, "MCMFilzaDataContainerPath");
    return dataPath ? dataPath(bid) : nil;
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

static UIColor *colorFondo(void) { return [UIColor colorWithWhite:0.05 alpha:1.0]; }
static UIColor *acento(void) { return [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0]; }

#pragma mark - Visor de texto
@interface TextViewVC : UIViewController
@property (nonatomic, strong) NSString *ruta;
@end
@implementation TextViewVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = self.ruta.lastPathComponent;
    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.textColor = acento();
    tv.backgroundColor = [UIColor blackColor];
    tv.font = [UIFont fontWithName:@"Menlo" size:11];
    tv.contentInset = UIEdgeInsetsMake(10, 10, 10, 10);
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.ruta error:nil];
    unsigned long long size = [[attrs objectForKey:@"NSFileSize"] unsignedLongLongValue];
    if (size > 2 * 1024 * 1024) {
        tv.text = [NSString stringWithFormat:@"(archivo demasiado grande: %@)", fmtSize(size)];
    } else {
        NSData *d = [NSData dataWithContentsOfFile:self.ruta];
        NSString *s = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
        tv.text = s ?: [NSString stringWithFormat:@"(binario, %@)", fmtSize(size)];
    }
    [self.view addSubview:tv];
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
    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.backgroundColor = colorFondo();
    self.tv.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.tv.dataSource = self;
    self.tv.delegate = self;
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
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    c.backgroundColor = colorFondo();
    c.selectedBackgroundView = [UIView new];
    c.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    NSString *n = self.items[ip.row];
    c.textLabel.text = n;
    c.textLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    c.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
    c.detailTextLabel.textColor = [UIColor grayColor];
    if ([n isEqualToString:@".."]) {
        ponerIcono(c, @"arrow.uturn.left", [UIColor grayColor]);
        c.textLabel.textColor = [UIColor grayColor];
        c.detailTextLabel.text = @"subir";
        c.accessoryType = UITableViewCellAccessoryNone;
    } else if ([self esDir:n]) {
        ponerIcono(c, @"folder.fill", [UIColor cyanColor]);
        c.textLabel.textColor = [UIColor cyanColor];
        c.detailTextLabel.text = @"carpeta";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        ponerIcono(c, @"doc.fill", [UIColor lightGrayColor]);
        c.textLabel.textColor = [UIColor whiteColor];
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
@end

#pragma mark - Pantalla principal
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
    self.title = @"MiFilza";

    self.apps = [NSMutableArray new];
    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.backgroundColor = colorFondo();
    self.tv.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.tv.dataSource = self;
    self.tv.delegate = self;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    header.backgroundColor = colorFondo();
    self.campo = [[UITextField alloc] initWithFrame:CGRectMake(12, 7, header.bounds.size.width - 24, 36)];
    self.campo.placeholder = @"bundle id manual + return";
    self.campo.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.campo.layer.cornerRadius = 10;
    self.campo.layer.borderWidth = 1;
    self.campo.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    self.campo.textColor = [UIColor whiteColor];
    self.campo.font = [UIFont fontWithName:@"Menlo" size:12];
    self.campo.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.campo.autocorrectionType = UITextAutocorrectionTypeNo;
    self.campo.returnKeyType = UIReturnKeyDone;
    self.campo.delegate = self;
    UIImageView *lupa = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 24, 20)];
    lupa.image = [[UIImage systemImageNamed:@"magnifyingglass"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    lupa.tintColor = [UIColor grayColor];
    lupa.contentMode = UIViewContentModeCenter;
    self.campo.leftView = lupa;
    self.campo.leftViewMode = UITextFieldViewModeAlways;
    [header addSubview:self.campo];
    self.tv.tableHeaderView = header;
    [self.view addSubview:self.tv];

    self.vacioLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 120, self.view.bounds.size.width - 60, 90)];
    self.vacioLabel.numberOfLines = 0;
    self.vacioLabel.textAlignment = NSTextAlignmentCenter;
    self.vacioLabel.textColor = [UIColor grayColor];
    self.vacioLabel.font = [UIFont fontWithName:@"Menlo" size:12];
    self.vacioLabel.text = @"No se detectaron apps.\nEscribe arriba el bundle ID\nde una app INSTALADA.";
    self.vacioLabel.hidden = YES;
    [self.view addSubview:self.vacioLabel];

    [self cargarApps];
}

- (void)cargarApps {
    NSMutableOrderedSet *set = [NSMutableOrderedSet new];
    @try {
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
    } @catch (NSException *e) {}

    [self.apps addObjectsFromArray:[set array]];
    [self.apps sortUsingSelector:@selector(localizedStandardCompare:)];
    self.title = [NSString stringWithFormat:@"MiFilza (%lu)", (unsigned long)self.apps.count];
    self.vacioLabel.hidden = (self.apps.count != 0);
    [self.tv reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    [self abrirContenedor:tf.text];
    return YES;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.apps.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"a"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"a"];
    c.backgroundColor = colorFondo();
    c.selectedBackgroundView = [UIView new];
    c.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    c.textLabel.text = self.apps[ip.row];
    c.textLabel.textColor = acento();
    c.textLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    c.detailTextLabel.text = @"toca para explorar";
    c.detailTextLabel.textColor = [UIColor grayColor];
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
    bid = [bid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!bid.length) return;
    asegurarMotor();
    NSString *p = nil;
    @try { p = containerPath(bid); } @catch (NSException *e) { p = nil; }
    if (!p) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sin contenedor"
            message:[NSString stringWithFormat:@"%@ no devolvio ruta (no instalada?)", bid]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    FileBrowserVC *fb = [FileBrowserVC new];
    fb.ruta = p;
    [self.navigationController pushViewController:fb animated:YES];
}

@end
