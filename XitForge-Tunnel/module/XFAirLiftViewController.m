#import "XFAirLiftViewController.h"
#import "XFAirLiftBackend.h"
#import "XFOnDevicePairing.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuickLook/QuickLook.h>
#import <math.h>
#import <arpa/inet.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

static const NSUInteger XFMaximumReplacementSize = 64 * 1024 * 1024;

static NSError *XFReplacementInputError(NSString *message) {
    return [NSError errorWithDomain:@"XitForge.ReplacementInput" code:1
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}

static NSString *XFReplacementRelativePath(NSString *path, NSError **error) {
    const char *bytes = [path isKindOfClass:NSString.class] ? path.UTF8String : NULL;
    if (!bytes || !path.length || [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096 ||
        strlen(bytes) != [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] ||
        [path hasPrefix:@"/"] || [path containsString:@"\\"]) {
        if (error) *error = XFReplacementInputError(@"Introduce la ruta relativa completa del archivo de la app."); return nil;
    }
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count > 128) {
        if (error) *error = XFReplacementInputError(@"La ruta contiene demasiadas carpetas."); return nil;
    }
    for (NSString *part in parts) if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."]) {
        if (error) *error = XFReplacementInputError(@"La ruta debe identificar un archivo dentro del contenedor de la app."); return nil;
    }
    return path;
}

@interface XFReplacementReadRequest : NSObject
@property (atomic, assign) BOOL cancelled;
@property (nonatomic, strong) NSFileCoordinator *coordinator;
@property (nonatomic, assign) NSTimeInterval deadline;
- (BOOL)shouldStop;
- (void)cancel;
@end

@implementation XFReplacementReadRequest
- (instancetype)init {
    if ((self = [super init])) {
        _coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        _deadline = NSProcessInfo.processInfo.systemUptime + 30;
    }
    return self;
}
- (BOOL)shouldStop { return self.cancelled || NSProcessInfo.processInfo.systemUptime >= self.deadline; }
- (void)cancel { self.cancelled = YES; [self.coordinator cancel]; }
@end

// At most one provider read may remain in flight after cancellation. Never
// accumulate stuck workers or block the device-operation queue on a provider.
static dispatch_semaphore_t XFReplacementReaderSlot(void) {
    static dispatch_semaphore_t slot;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ slot = dispatch_semaphore_create(1); });
    return slot;
}

// The worker owns the security scope until its finally block. Cancellation
// invalidates UI results immediately and cooperatively stops bounded reads.
static NSData *XFReadReplacementURL(NSURL *URL, XFReplacementReadRequest *request, NSError **error) {
    if (!URL.isFileURL) {
        if (error) *error = XFReplacementInputError(@"Elige un archivo desde el selector de Archivos."); return nil;
    }
    __block NSData *result = nil;
    __block NSError *readFailure = nil;
    NSError *coordinationFailure = nil;
    if (request.shouldStop) { if (error) *error = XFReplacementInputError(@"Se canceló la lectura del archivo elegido."); return nil; }
    [request.coordinator coordinateReadingItemAtURL:URL options:0 error:&coordinationFailure byAccessor:^(NSURL *coordinatedURL) {
        if (request.shouldStop) { readFailure = XFReplacementInputError(@"Se canceló la lectura del archivo elegido."); return; }
        const char *source = coordinatedURL.fileSystemRepresentation;
        NSString *sourcePath = coordinatedURL.path;
        NSString *nul = [NSString stringWithFormat:@"%C", (unichar)0];
        if (!source || [sourcePath rangeOfString:nul].location != NSNotFound) { readFailure = XFReplacementInputError(@"El archivo elegido no tiene una ubicación válida."); return; }
        int fd = open(source, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
        if (fd < 0) { readFailure = XFReplacementInputError(@"No se pudo abrir el archivo elegido. Comprueba que se haya descargado y vuelva a seleccionarlo."); return; }
        @try {
            struct stat before = {0};
            if (fstat(fd, &before) != 0 || !S_ISREG(before.st_mode) || before.st_size < 0) {
                readFailure = XFReplacementInputError(@"Elige un archivo regular, no una carpeta ni un enlace."); return;
            }
            if ((uint64_t)before.st_size > XFMaximumReplacementSize) {
                readFailure = XFReplacementInputError(@"El archivo elegido supera el límite de 64 MiB."); return;
            }
            NSMutableData *data = [NSMutableData dataWithCapacity:MIN((NSUInteger)before.st_size, (NSUInteger)(1024 * 1024))];
            uint8_t buffer[64 * 1024];
            while (YES) {
                if (request.shouldStop) { readFailure = XFReplacementInputError(@"La lectura se canceló o superó los 30 segundos. Descarga el archivo antes de seleccionarlo."); return; }
                ssize_t got = read(fd, buffer, sizeof(buffer));
                if (got < 0 && errno == EINTR) continue;
                if (got < 0) { readFailure = XFReplacementInputError(@"La lectura del archivo elegido quedó incompleta."); return; }
                if (!got) break;
                if ((NSUInteger)got > XFMaximumReplacementSize - data.length) {
                    readFailure = XFReplacementInputError(@"El archivo elegido supera el límite de 64 MiB."); return;
                }
                [data appendBytes:buffer length:(NSUInteger)got];
            }
            struct stat after = {0};
            if (fstat(fd, &after) != 0 || before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
                before.st_size != after.st_size || data.length != (NSUInteger)after.st_size ||
                before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec || before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec ||
                before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec) {
                readFailure = XFReplacementInputError(@"El archivo elegido cambió mientras se leía. Selecciónalo otra vez."); return;
            }
            result = [data copy];
        } @finally {
            if (close(fd) != 0 && result) {
                result = nil; readFailure = XFReplacementInputError(@"No se pudo completar la lectura del archivo elegido.");
            }
        }
    }];
    if (request.shouldStop) { result = nil; readFailure = XFReplacementInputError(@"La lectura se canceló o superó los 30 segundos."); }
    if (!result && error) *error = readFailure ?: coordinationFailure ?: XFReplacementInputError(@"No se pudo leer el archivo elegido.");
    return result;
}

static NSString *XFString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *XFErrorMessage(NSError *error) {
    return error.localizedDescription.length ? error.localizedDescription : @"El servicio no devolvió una respuesta válida.";
}

static void XFPresentError(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Entendido" style:UIAlertActionStyleCancel handler:nil]];
    void (^presentAlert)(void) = ^{ [controller presentViewController:alert animated:YES completion:nil]; };
    if ([controller.presentedViewController isKindOfClass:UIAlertController.class]) {
        [controller.presentedViewController dismissViewControllerAnimated:YES completion:presentAlert];
    } else presentAlert();
}

static UIBarButtonItem *XFSpinnerItem(void) {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    return [[UIBarButtonItem alloc] initWithCustomView:spinner];
}

static UILabel *XFLabel(NSString *text, UIFontTextStyle style, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

@interface XFConnectionStatusView : UIStackView
@property (nonatomic, strong) UILabel *tunnelLabel;
@property (nonatomic, strong) UILabel *pairingLabel;
- (void)showConnected:(BOOL)connected pairingAvailable:(BOOL)available;
- (void)showConnecting;
- (void)showPairingInProgress:(BOOL)inProgress available:(BOOL)available;
@end

@implementation XFConnectionStatusView
- (instancetype)init {
    if ((self = [super init])) {
        self.axis = UILayoutConstraintAxisVertical;
        self.spacing = 8;
        self.layoutMarginsRelativeArrangement = YES;
        self.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(12, 14, 12, 14);
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.layer.cornerRadius = 12;
        self.tunnelLabel = XFLabel(@"Túnel: comprobando…", UIFontTextStyleHeadline, UIColor.secondaryLabelColor);
        self.pairingLabel = XFLabel(@"Pairing: comprobando…", UIFontTextStyleHeadline, UIColor.secondaryLabelColor);
        self.tunnelLabel.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
        self.pairingLabel.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
        [self addArrangedSubview:self.tunnelLabel];
        [self addArrangedSubview:self.pairingLabel];
        [self addArrangedSubview:XFLabel(@"Último estado comprobado. Se actualiza al conectar o consultar archivos.", UIFontTextStyleCaption1, UIColor.secondaryLabelColor)];
    }
    return self;
}
- (void)showConnected:(BOOL)connected pairingAvailable:(BOOL)available {
    self.tunnelLabel.text = connected ? @"Túnel: conectado" : @"Túnel: desconectado";
    self.tunnelLabel.textColor = connected ? UIColor.systemGreenColor : UIColor.systemRedColor;
    [self showPairingInProgress:NO available:available];
}
- (void)showConnecting {
    self.tunnelLabel.text = @"Túnel: conectando…";
    self.tunnelLabel.textColor = UIColor.secondaryLabelColor;
}
- (void)showPairingInProgress:(BOOL)inProgress available:(BOOL)available {
    self.pairingLabel.text = inProgress ? @"Pairing: esperando aprobación…" :
        (available ? @"Pairing: guardado" : @"Pairing: pendiente");
    self.pairingLabel.textColor = inProgress || !available ? UIColor.systemOrangeColor : UIColor.systemGreenColor;
}
@end

static UIView *XFStatusHeader(XFConnectionStatusView *status, CGFloat width) {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 130)];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:status];
    [NSLayoutConstraint activateConstraints:@[
        [status.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [status.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [status.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
        [status.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12]
    ]];
    return header;
}

static void XFFitTableHeader(UITableView *table) {
    UIView *header = table.tableHeaderView;
    if (!header) return;
    CGFloat width = CGRectGetWidth(table.bounds);
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.height - size.height) > 1 || fabs(header.frame.size.width - width) > 1) {
        header.frame = CGRectMake(0, 0, width, size.height);
        table.tableHeaderView = header;
    }
}

static NSString *XFChildPath(NSString *parent, NSString *name) {
    return parent.length ? [parent stringByAppendingPathComponent:name] : name;
}

@interface XFAirLiftPreviewController : QLPreviewController <QLPreviewControllerDataSource>
@property (nonatomic, strong) NSURL *fileURL;
- (instancetype)initWithFileURL:(NSURL *)fileURL;
@end

@implementation XFAirLiftPreviewController
- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _fileURL = fileURL;
        self.dataSource = self;
    }
    return self;
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller { return 1; }
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index { return self.fileURL; }
@end

@interface XFAirLiftDirectoryController : UITableViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) XFAirLiftBackend *backend;
@property (nonatomic, strong) dispatch_queue_t operationQueue;
@property (nonatomic, copy) NSString *applicationID;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, copy) NSString *directoryWarning;
@property (nonatomic, strong) XFConnectionStatusView *connectionStatus;
@property (nonatomic, copy, nullable) NSString *pendingReplacementPath;
@property (nonatomic, strong, nullable) UIDocumentPickerViewController *replacementPicker;
@property (nonatomic, strong, nullable) XFReplacementReadRequest *replacementRead;
- (instancetype)initWithBackend:(XFAirLiftBackend *)backend queue:(dispatch_queue_t)queue
                  applicationID:(NSString *)applicationID relativePath:(NSString *)relativePath;
@end

@implementation XFAirLiftDirectoryController
- (instancetype)initWithBackend:(XFAirLiftBackend *)backend queue:(dispatch_queue_t)queue
                  applicationID:(NSString *)applicationID relativePath:(NSString *)relativePath {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _backend = backend;
        _operationQueue = queue;
        _applicationID = [applicationID copy];
        _relativePath = [relativePath copy];
        _entries = @[];
        self.title = relativePath.length ? relativePath.lastPathComponent : @"Archivos";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.connectionStatus = [[XFConnectionStatusView alloc] init];
    self.tableView.tableHeaderView = XFStatusHeader(self.connectionStatus, CGRectGetWidth(self.view.bounds));
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reloadDirectory) forControlEvents:UIControlEventValueChanged];
    [self reloadDirectory];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    XFFitTableHeader(self.tableView);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        [self cancelReplacementRead];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.busy) return;
    dispatch_async(self.operationQueue, ^{
        BOOL connected = self.backend.connected;
        BOOL paired = self.backend.hasPairingRecord;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.busy) return;
            [self.connectionStatus showConnected:connected pairingAvailable:paired];
            [self.view setNeedsLayout];
        });
    });
}

- (void)setBusyUI:(BOOL)busy {
    self.busy = busy;
    self.navigationItem.rightBarButtonItem = busy ? XFSpinnerItem() :
        [[UIBarButtonItem alloc] initWithTitle:@"Abrir ruta" style:UIBarButtonItemStylePlain target:self action:@selector(openKnownPath)];
    if (!busy) [self.refreshControl endRefreshing];
}

- (void)showDirectoryMessage:(NSString *)message {
    UILabel *label = XFLabel(message, UIFontTextStyleBody, UIColor.secondaryLabelColor);
    label.textAlignment = NSTextAlignmentCenter;
    UIView *container = [[UIView alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-24],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]
    ]];
    self.tableView.backgroundView = container;
}

- (void)reloadDirectory {
    if (self.busy) { [self.refreshControl endRefreshing]; return; }
    [self setBusyUI:YES];
    [self showDirectoryMessage:@"Consultando esta carpeta…"];
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        NSArray<NSDictionary *> *entries = [self.backend listDirectoryForApplication:self.applicationID
                                                                       relativePath:self.relativePath error:&error];
        NSString *warning = self.backend.lastDirectoryWarning;
        BOOL connected = self.backend.connected;
        BOOL paired = self.backend.hasPairingRecord;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusyUI:NO];
            [self.connectionStatus showConnected:connected pairingAvailable:paired];
            [self.view setNeedsLayout];
            self.directoryWarning = warning;
            if (!entries) {
                self.entries = @[];
                [self.tableView reloadData];
                [self showDirectoryMessage:@"El servicio no permitió explorar esta carpeta. No se ha confirmado que esté vacía."];
                XFPresentError(self, @"No se pudo explorar", XFErrorMessage(error));
                return;
            }
            self.entries = [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [XFString(a[@"name"]) localizedStandardCompare:XFString(b[@"name"])];
            }];
            self.tableView.backgroundView = nil;
            [self.tableView reloadData];
            if (!self.entries.count) [self showDirectoryMessage:@"La carpeta no contiene entradas visibles para este servicio."];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.entries.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.relativePath.length ? self.relativePath : self.applicationID;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.directoryWarning.length) return self.directoryWarning;
    return @"Cuando el servicio no informa el tipo, puedes elegir explorar como carpeta o abrir como archivo. El acceso puede variar según la app y la versión de iOS.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"entry"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"entry"];
    NSDictionary *entry = self.entries[indexPath.row];
    BOOL typeKnown = [entry[@"typeKnown"] boolValue];
    BOOL directory = [entry[@"isDirectory"] boolValue];
    cell.textLabel.text = XFString(entry[@"name"]);
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = typeKnown ? (directory ? @"Carpeta" : @"Archivo") : @"Tipo no disponible";
    cell.imageView.image = [UIImage systemImageNamed:typeKnown ? (directory ? @"folder" : @"doc") : @"questionmark.folder"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)openDirectory:(NSString *)name {
    [self openRelativeDirectoryPath:XFChildPath(self.relativePath, name)];
}

- (void)openRelativeDirectoryPath:(NSString *)path {
    XFAirLiftDirectoryController *controller = [[XFAirLiftDirectoryController alloc]
        initWithBackend:self.backend queue:self.operationQueue applicationID:self.applicationID
        relativePath:path];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)readFile:(NSString *)name export:(BOOL)exportFile {
    [self readRelativeFilePath:XFChildPath(self.relativePath, name) export:exportFile];
}

- (void)readRelativeFilePath:(NSString *)path export:(BOOL)exportFile {
    if (self.busy) return;
    NSError *validationError = nil;
    NSString *target = XFReplacementRelativePath(path, &validationError);
    if (!target) { XFPresentError(self, @"Ruta de archivo no válida", XFErrorMessage(validationError)); return; }
    NSString *application = [self.applicationID copy];
    [self setBusyUI:YES];
    NSString *message = [NSString stringWithFormat:@"App: %@\nArchivo: %@\n\nSi se necesita AirLift, el archivo se moverá temporalmente para leerlo y se intentará devolver a su ubicación. Cierra la app de destino durante la operación.\n\nSi se interrumpe, vuelve a conectar para recuperar el original. No desinstales XitForge mientras haya una recuperación pendiente.", application, target];
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:exportFile ? @"Confirmar exportación" : @"Confirmar lectura" message:message preferredStyle:UIAlertControllerStyleAlert];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self setBusyUI:NO]; }]];
    [confirmation addAction:[UIAlertAction actionWithTitle:exportFile ? @"Leer y exportar" : @"Leer archivo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self performReadRelativeFilePath:target application:application export:exportFile];
    }]];
    void (^showConfirmation)(void) = ^{ [self presentViewController:confirmation animated:YES completion:nil]; };
    if ([self.presentedViewController isKindOfClass:UIAlertController.class]) [self.presentedViewController dismissViewControllerAnimated:YES completion:showConfirmation];
    else showConfirmation();
}

- (void)performReadRelativeFilePath:(NSString *)path application:(NSString *)application export:(BOOL)exportFile {
    [self setBusyUI:YES];
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        NSData *data = [self.backend readFileForApplication:application relativePath:path error:&error];
        NSString *warning = self.backend.lastDirectoryWarning;
        BOOL connected = self.backend.connected;
        BOOL paired = self.backend.hasPairingRecord;
        NSURL *fileURL = nil;
        if (data) {
            NSString *safeName = path.lastPathComponent;
            if (!safeName.length || [safeName isEqualToString:@"."] || [safeName isEqualToString:@".."]) safeName = @"archivo";
            NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent:[@"XitForge-AirLift/" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
            if ([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
                fileURL = [directory URLByAppendingPathComponent:safeName isDirectory:NO];
                if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&error]) fileURL = nil;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusyUI:NO];
            [self.connectionStatus showConnected:connected pairingAvailable:paired];
            self.directoryWarning = warning;
            [self.view setNeedsLayout];
            if (!fileURL) {
                NSString *message = XFErrorMessage(error);
                if (warning.length && [message rangeOfString:warning].location == NSNotFound) message = [message stringByAppendingFormat:@"\n\n%@", warning];
                XFPresentError(self, @"No se pudo leer el archivo", message);
                return;
            }
            if (exportFile) {
                UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
                share.popoverPresentationController.sourceView = self.view;
                share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
                [self presentViewController:share animated:YES completion:nil];
            } else {
                XFAirLiftPreviewController *preview = [[XFAirLiftPreviewController alloc] initWithFileURL:fileURL];
                [self.navigationController pushViewController:preview animated:YES];
            }
        });
    });
}

- (void)openKnownPath {
    if (self.busy) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Abrir por ruta"
        message:@"Introduce una ruta relativa al contenedor de la app. Puedes intentar leer un archivo conocido aunque no se permita listar su carpeta."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Documents/archivo.ext";
        field.text = self.relativePath.length ? [self.relativePath stringByAppendingString:@"/"] : @"";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak UIAlertController *weakAlert = alert;
    NSString *(^enteredPath)(void) = ^{
        return [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"Explorar carpeta" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openRelativeDirectoryPath:enteredPath()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Previsualizar archivo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *path = enteredPath();
        if (!path.length) { XFPresentError(self, @"Falta la ruta", @"Introduce el nombre y la ruta del archivo."); return; }
        [self readRelativeFilePath:path export:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Exportar archivo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *path = enteredPath();
        if (!path.length) { XFPresentError(self, @"Falta la ruta", @"Introduce el nombre y la ruta del archivo."); return; }
        [self readRelativeFilePath:path export:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reemplazar archivo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self chooseReplacementForPath:enteredPath()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Eliminar archivo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self confirmDeleteForPath:enteredPath()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restaurar original pendiente" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self confirmRestoreForPath:enteredPath()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseReplacementForPath:(NSString *)path {
    if (self.busy) return;
    NSError *error = nil;
    NSString *target = XFReplacementRelativePath(path, &error);
    if (!target) { XFPresentError(self, @"Ruta de reemplazo no válida", XFErrorMessage(error)); return; }
    self.pendingReplacementPath = [target copy];
    [self setBusyUI:YES];
    // Import a copy and accept unfamiliar extensions. The reader still rejects
    // directories, symbolic links and files larger than 64 MiB.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self; picker.allowsMultipleSelection = NO;
    picker.title = @"Elige el archivo nuevo";
    picker.shouldShowFileExtensions = YES;
    self.replacementPicker = picker;
    void (^presentPicker)(void) = ^{ [self presentViewController:picker animated:YES completion:nil]; };
    if ([self.presentedViewController isKindOfClass:UIAlertController.class]) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:presentPicker];
    } else presentPicker();
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller != self.replacementPicker) return;
    self.replacementPicker = nil;
    self.pendingReplacementPath = nil;
    [self setBusyUI:NO];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (controller != self.replacementPicker) return;
    self.replacementPicker = nil;
    NSURL *URL = urls.firstObject;
    NSString *target = [self.pendingReplacementPath copy];
    NSString *application = [self.applicationID copy];
    self.pendingReplacementPath = nil;
    if (!URL || !target.length) { [self setBusyUI:NO]; [controller dismissViewControllerAnimated:YES completion:nil]; return; }
    __weak typeof(self) weakSelf = self;
    void (^startRead)(void) = ^{
        typeof(self) owner = weakSelf;
        if (!owner) return;
        if (!owner.view.window || owner.navigationController.topViewController != owner) { [owner setBusyUI:NO]; return; }
        [owner beginReplacementRead:URL target:target application:application];
    };
    // Close Files before coordinating or reading any bytes. Some providers
    // dismiss themselves; wait for their transition before showing app UI.
    if (controller.isBeingDismissed && controller.transitionCoordinator) {
        [controller.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { startRead(); }];
    } else if (controller.presentingViewController) {
        [controller dismissViewControllerAnimated:YES completion:startRead];
    } else dispatch_async(dispatch_get_main_queue(), startRead);
}

- (void)cancelReplacementRead {
    XFReplacementReadRequest *request = self.replacementRead;
    if (!request) return;
    self.replacementRead = nil;
    [request cancel];
    self.navigationItem.prompt = nil;
    [self setBusyUI:NO];
}

- (void)beginReplacementRead:(NSURL *)URL target:(NSString *)target application:(NSString *)application {
    if (dispatch_semaphore_wait(XFReplacementReaderSlot(), DISPATCH_TIME_NOW) != 0) {
        [self setBusyUI:NO];
        XFPresentError(self, @"Lectura anterior pendiente", @"El proveedor todavía no terminó de cerrar el archivo anterior. Espera un momento antes de elegir otro archivo.");
        return;
    }
    XFReplacementReadRequest *request = [[XFReplacementReadRequest alloc] init];
    self.replacementRead = request;
    self.navigationItem.prompt = @"Leyendo el archivo elegido…";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancelar lectura" style:UIBarButtonItemStylePlain target:self action:@selector(cancelReplacementRead)];
    NSString *sourceName = URL.lastPathComponent ?: @"archivo";
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) owner = weakSelf;
        if (!owner || owner.replacementRead != request) return;
        [owner cancelReplacementRead];
        XFPresentError(owner, @"La lectura tardó demasiado", @"No se modificó el archivo de la app. Descarga el archivo nuevo en Archivos y selecciónalo otra vez.");
    });
    // Provider waits cannot hold the serial queue used by the tunnel/recovery.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil; NSData *payload = nil;
        BOOL scoped = [URL startAccessingSecurityScopedResource];
        @try { payload = XFReadReplacementURL(URL, request, &error); }
        @finally {
            if (scoped) [URL stopAccessingSecurityScopedResource];
            dispatch_semaphore_signal(XFReplacementReaderSlot());
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner = weakSelf;
            if (!owner || owner.replacementRead != request) return;
            owner.replacementRead = nil;
            owner.navigationItem.prompt = nil;
            if (!owner.view.window || owner.navigationController.topViewController != owner) { [owner setBusyUI:NO]; return; }
            if (request.shouldStop || !payload) {
                [owner setBusyUI:NO];
                XFPresentError(owner, @"Archivo elegido no válido", request.shouldStop ? @"La lectura superó los 30 segundos. Descarga el archivo y vuelve a seleccionarlo." : XFErrorMessage(error));
                return;
            }
            [owner setBusyUI:YES];
            NSString *message = [NSString stringWithFormat:@"App: %@\nDestino: %@\nArchivo nuevo: %@\nTamaño: %lu bytes\n\nEl archivo elegido sustituirá el contenido del destino. Se conservará el original hasta verificar el reemplazo. Cierra la app de destino durante la operación.\n\nSi se interrumpe, vuelve a conectar para recuperar el original. No desinstales XitForge mientras haya una recuperación pendiente.", application, target, sourceName, (unsigned long)payload.length];
            UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:@"Confirmar reemplazo" message:message preferredStyle:UIAlertControllerStyleAlert];
            [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [owner setBusyUI:NO]; }]];
            [confirmation addAction:[UIAlertAction actionWithTitle:@"Reemplazar" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                [owner replaceKnownFileAtPath:target application:application data:payload];
            }]];
            [owner presentViewController:confirmation animated:YES completion:nil];
        });
    });
}

- (void)replaceKnownFileAtPath:(NSString *)path application:(NSString *)application data:(NSData *)payload {
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        BOOL replaced = [self.backend replaceFileForApplication:application relativePath:path data:payload error:&error];
        NSString *warning = self.backend.lastDirectoryWarning;
        BOOL connected = self.backend.connected; BOOL paired = self.backend.hasPairingRecord;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusyUI:NO];
            [self.connectionStatus showConnected:connected pairingAvailable:paired];
            self.directoryWarning = warning;
            [self.view setNeedsLayout];
            NSString *detail = replaced ? [NSString stringWithFormat:@"App: %@\nArchivo: %@", application, path] : XFErrorMessage(error);
            if (warning.length && [detail rangeOfString:warning].location == NSNotFound) detail = [detail stringByAppendingFormat:@"\n\n%@", warning];
            XFPresentError(self, replaced ? @"Archivo reemplazado" : @"No se pudo reemplazar", detail);
            // Do not refresh LIST here: a denied listing must not replace the
            // write/recovery result or erase the operation diagnostics.
        });
    });
}

- (void)confirmDeleteForPath:(NSString *)path {
    if (self.busy) return;
    NSError *error = nil;
    NSString *target = XFReplacementRelativePath(path, &error);
    if (!target) { XFPresentError(self, @"Ruta de eliminación no válida", XFErrorMessage(error)); return; }
    NSString *application = [self.applicationID copy];
    [self setBusyUI:YES];
    NSString *message = [NSString stringWithFormat:@"App: %@\nArchivo: %@\n\nSe retirará este archivo de su ubicación y se conservará una copia original en XitForge. Solo admite archivos de hasta 64 MiB, no carpetas.\n\nCierra la app de destino. Si la operación se interrumpe, usa Restaurar original pendiente para esta misma ruta. Guarda la copia antes de desinstalar XitForge.", application, target];
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:@"¿Eliminar este archivo?" message:message preferredStyle:UIAlertControllerStyleAlert];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self setBusyUI:NO]; }]];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Eliminar archivo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteKnownFileAtPath:target application:application];
    }]];
    void (^showConfirmation)(void) = ^{ [self presentViewController:confirmation animated:YES completion:nil]; };
    if ([self.presentedViewController isKindOfClass:UIAlertController.class]) [self.presentedViewController dismissViewControllerAnimated:YES completion:showConfirmation];
    else showConfirmation();
}

- (void)deleteKnownFileAtPath:(NSString *)path application:(NSString *)application {
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        BOOL removed = [self.backend deleteFileForApplication:application relativePath:path error:&error];
        BOOL absent = self.backend.lastDeletionAbsenceConfirmed;
        NSURL *backup = self.backend.lastDeletedFileBackupURL;
        NSString *warning = self.backend.lastDirectoryWarning;
        BOOL connected = self.backend.connected; BOOL paired = self.backend.hasPairingRecord;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusyUI:NO];
            [self.connectionStatus showConnected:connected pairingAvailable:paired];
            self.directoryWarning = warning;
            [self.view setNeedsLayout];
            NSString *title = !removed ? @"No se completó la eliminación" : (absent ? @"Archivo eliminado" : @"Archivo trasladado al respaldo");
            NSString *detail = removed ? [NSString stringWithFormat:@"App: %@\nArchivo: %@\n\n%@", application, path,
                absent ? @"Se confirmó que la ruta ya no contiene el archivo. La copia original se conserva en XitForge." : @"El original se recuperó en el respaldo. iOS no permitió confirmar si la ruta de la app ya está ausente."] : XFErrorMessage(error);
            if (warning.length && [detail rangeOfString:warning].location == NSNotFound) detail = [detail stringByAppendingFormat:@"\n\n%@", warning];
            UIAlertController *result = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
            if (backup) [result addAction:[UIAlertAction actionWithTitle:@"Guardar copia original" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self exportDeletedBackup:backup filename:path.lastPathComponent];
            }]];
            [result addAction:[UIAlertAction actionWithTitle:@"Entendido" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:result animated:YES completion:nil];
            // Keep this result visible even where LIST is denied.
        });
    });
}

- (void)exportDeletedBackup:(NSURL *)backup filename:(NSString *)filename {
    [self setBusyUI:YES];
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[@"XitForge-Backups/" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSURL *fileURL = nil;
        if ([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES
            attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error]) {
            fileURL = [directory URLByAppendingPathComponent:filename isDirectory:NO];
            if (![NSFileManager.defaultManager copyItemAtURL:backup toURL:fileURL error:&error]) fileURL = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusyUI:NO];
            if (!fileURL) { XFPresentError(self, @"No se pudo exportar la copia", XFErrorMessage(error)); return; }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
            share.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *items, NSError *activityError) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    // Remove only this share's temporary copy. The durable
                    // original supplied by the backend is never handed off.
                    [NSFileManager.defaultManager removeItemAtURL:fileURL error:NULL];
                    NSArray *remaining = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL];
                    if (remaining && !remaining.count) [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
                });
            };
            share.popoverPresentationController.sourceView = self.view;
            share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
            void (^presentShare)(void) = ^{ [self presentViewController:share animated:YES completion:nil]; };
            if ([self.presentedViewController isKindOfClass:UIAlertController.class]) [self.presentedViewController dismissViewControllerAnimated:YES completion:presentShare];
            else presentShare();
        });
    });
}

- (void)confirmRestoreForPath:(NSString *)path {
    if (self.busy) return;
    NSError *error = nil;
    NSString *target = XFReplacementRelativePath(path, &error);
    if (!target) { XFPresentError(self, @"Ruta de recuperación no válida", XFErrorMessage(error)); return; }
    NSString *application = [self.applicationID copy];
    [self setBusyUI:YES];
    NSString *message = [NSString stringWithFormat:@"App: %@\nDestino: %@\n\nEsta acción restaura el original conservado para esta ruta y puede reemplazar el contenido actual del archivo. Cierra la app de destino durante la operación.\n\nSi se interrumpe, vuelve a conectar y recupera esta misma ruta. No desinstales XitForge mientras haya una recuperación pendiente.", application, target];
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:@"Restaurar original pendiente" message:message preferredStyle:UIAlertControllerStyleAlert];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self setBusyUI:NO]; }]];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Restaurar original" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(self.operationQueue, ^{
            NSError *failure = nil;
            BOOL restored = [self.backend restorePendingFileForApplication:application relativePath:target error:&failure];
            NSString *warning = self.backend.lastDirectoryWarning;
            BOOL connected = self.backend.connected; BOOL paired = self.backend.hasPairingRecord;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setBusyUI:NO];
                [self.connectionStatus showConnected:connected pairingAvailable:paired];
                self.directoryWarning = warning;
                [self.view setNeedsLayout];
                NSString *detail = restored ? [NSString stringWithFormat:@"App: %@\nArchivo: %@", application, target] : XFErrorMessage(failure);
                if (warning.length && [detail rangeOfString:warning].location == NSNotFound) detail = [detail stringByAppendingFormat:@"\n\n%@", warning];
                XFPresentError(self, restored ? @"Original restaurado" : @"Recuperación no completada", detail);
            });
        });
    }]];
    void (^showConfirmation)(void) = ^{ [self presentViewController:confirmation animated:YES completion:nil]; };
    if ([self.presentedViewController isKindOfClass:UIAlertController.class]) [self.presentedViewController dismissViewControllerAnimated:YES completion:showConfirmation];
    else showConfirmation();
}

- (void)presentActionsForEntry:(NSDictionary *)entry atIndexPath:(NSIndexPath *)indexPath {
    NSString *name = XFString(entry[@"name"]);
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (![entry[@"typeKnown"] boolValue] || [entry[@"isDirectory"] boolValue]) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Explorar carpeta" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self openDirectory:name]; }]];
    }
    if (![entry[@"typeKnown"] boolValue] || ![entry[@"isDirectory"] boolValue]) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Previsualizar archivo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self readFile:name export:NO]; }]];
        [menu addAction:[UIAlertAction actionWithTitle:@"Exportar archivo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self readFile:name export:YES]; }]];
        [menu addAction:[UIAlertAction actionWithTitle:@"Reemplazar archivo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self chooseReplacementForPath:XFChildPath(self.relativePath, name)]; }]];
        [menu addAction:[UIAlertAction actionWithTitle:@"Eliminar archivo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self confirmDeleteForPath:XFChildPath(self.relativePath, name)]; }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.tableView;
    menu.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.busy) return;
    NSDictionary *entry = self.entries[indexPath.row];
    if ([entry[@"typeKnown"] boolValue] && [entry[@"isDirectory"] boolValue]) {
        [self openDirectory:XFString(entry[@"name"])];
    } else {
        [self presentActionsForEntry:entry atIndexPath:indexPath];
    }
}
@end

@interface XFAirLiftViewController () <UIDocumentPickerDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) XFAirLiftBackend *backend;
@property (nonatomic, strong) dispatch_queue_t operationQueue;
@property (nonatomic, copy) NSArray<NSDictionary *> *applications;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleApplications;
@property (nonatomic, strong) UISearchController *appSearch;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) XFConnectionStatusView *connectionStatus;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *pairButton;
@property (nonatomic, strong) UIButton *cancelPairButton;
@property (nonatomic, strong) UIButton *pinCopyButton;
@property (nonatomic, strong) UILabel *pairingPINLabel;
@property (nonatomic, strong) UILabel *pairingGuideLabel;
@property (nonatomic, strong) XFOnDevicePairing *pairingService;
@property (nonatomic, copy) NSString *currentPairingPIN;
@property (nonatomic, assign) NSUInteger pairingAttempt;
@property (nonatomic, assign) BOOL pairingInProgress;
@property (nonatomic, assign) BOOL pairingCancelling;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL pairingAvailable;
@property (nonatomic, assign) BOOL tunnelConnected;
@property (nonatomic, assign) BOOL applicationFileAccessAvailable;
@property (nonatomic, copy) NSString *capabilitiesText;
@property (nonatomic, copy) NSString *recoveryWarning;
@end

@implementation XFAirLiftViewController
- (instancetype)init { return [self initWithBackend:[XFAirLiftBackend sharedBackend]]; }
- (instancetype)initWithBackend:(XFAirLiftBackend *)backend {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _backend = backend;
        _operationQueue = dispatch_queue_create("com.xitforge.airlift.ui.operations", DISPATCH_QUEUE_SERIAL);
        _applications = @[];
        _visibleApplications = @[];
        self.title = @"Túnel";
    }
    return self;
}

- (UIButton *)buttonWithTitle:(NSString *)title selector:(SEL)selector prominent:(BOOL)prominent {
    UIButtonConfiguration *configuration = prominent ? UIButtonConfiguration.filledButtonConfiguration : UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 14, 12, 14);
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;
    self.view.tintColor = [UIColor colorWithRed:0.93 green:0.12 blue:0.19 alpha:1];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.headerStack = [[UIStackView alloc] init];
    self.headerStack.axis = UILayoutConstraintAxisVertical;
    self.headerStack.spacing = 12;
    self.headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerStack addArrangedSubview:XFLabel(@"Conecta tu iPhone", UIFontTextStyleTitle2, UIColor.labelColor)];
    self.connectionStatus = [[XFConnectionStatusView alloc] init];
    [self.headerStack addArrangedSubview:self.connectionStatus];
    [self.headerStack addArrangedSubview:XFLabel(@"1. Con el Wi-Fi encendido, empareja este iPhone o importa su registro.\n2. Activa LocalDevVPN.\n3. Conecta el túnel y usa Activar o Desactivar desde Home.", UIFontTextStyleSubheadline, UIColor.secondaryLabelColor)];
    self.statusLabel = XFLabel(@"Comprobando el emparejamiento…", UIFontTextStyleFootnote, UIColor.secondaryLabelColor);
    self.statusLabel.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
    [self.headerStack addArrangedSubview:self.statusLabel];
    self.pairingGuideLabel = XFLabel(@"", UIFontTextStyleSubheadline, UIColor.labelColor);
    self.pairingGuideLabel.hidden = YES;
    [self.headerStack addArrangedSubview:self.pairingGuideLabel];
    self.pairingPINLabel = XFLabel(@"", UIFontTextStyleTitle1, UIColor.labelColor);
    self.pairingPINLabel.font = [UIFont monospacedDigitSystemFontOfSize:30 weight:UIFontWeightSemibold];
    self.pairingPINLabel.textAlignment = NSTextAlignmentCenter;
    self.pairingPINLabel.accessibilityLabel = @"PIN de emparejamiento";
    self.pairingPINLabel.hidden = YES;
    [self.headerStack addArrangedSubview:self.pairingPINLabel];
    self.pinCopyButton = [self buttonWithTitle:@"Copiar PIN" selector:@selector(copyPairingPIN) prominent:NO];
    self.pinCopyButton.hidden = YES;

    self.pairButton = [self buttonWithTitle:@"Emparejar" selector:@selector(pairingAction) prominent:NO];
    [self.headerStack addArrangedSubview:self.pairButton];
    self.cancelPairButton = [self buttonWithTitle:@"Cancelar emparejamiento" selector:@selector(cancelOnDevicePairing) prominent:NO];
    self.cancelPairButton.hidden = YES;

    [self.headerStack addArrangedSubview:XFLabel(@"Emparejar desde este iPhone requiere iOS 27. En otras versiones puedes importar un registro válido.", UIFontTextStyleFootnote, UIColor.secondaryLabelColor)];
    self.importButton = [self buttonWithTitle:@"Importar" selector:@selector(importPairing) prominent:NO];
    [self.headerStack addArrangedSubview:self.importButton];

    self.connectButton = [self buttonWithTitle:@"Conectar túnel" selector:@selector(connectAndLoad) prominent:YES];
    self.connectButton.enabled = NO;
    [self.headerStack addArrangedSubview:self.connectButton];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 340)];
    [header addSubview:self.headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [self.headerStack.topAnchor constraintEqualToAnchor:header.topAnchor constant:20],
        [self.headerStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-20]
    ]];
    self.tableView.tableHeaderView = header;
    self.navigationItem.searchController = nil;
    dispatch_async(self.operationQueue, ^{
        BOOL available = self.backend.hasPairingRecord;
        BOOL connected = self.backend.connected;
        BOOL fileAccess = self.backend.applicationFileAccessAvailable;
        NSString *capabilities = self.backend.fileAccessSummary;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.pairingAvailable = available;
            self.tunnelConnected = connected;
            self.applicationFileAccessAvailable = fileAccess;
            self.capabilitiesText = capabilities;
            if (!self.busy) self.statusLabel.text = available ? @"Emparejamiento disponible. Falta comprobar la conexión." : @"Empareja este iPhone o importa su registro.";
            [self updateButtons];
            [self.view setNeedsLayout];
        });
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    XFFitTableHeader(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.busy) return;
    dispatch_async(self.operationQueue, ^{
        BOOL connected = self.backend.connected;
        BOOL paired = self.backend.hasPairingRecord;
        BOOL fileAccess = self.backend.applicationFileAccessAvailable;
        NSString *capabilities = self.backend.fileAccessSummary;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.busy) return;
            if (self.tunnelConnected && !connected)
                self.statusLabel.text = @"Se perdió la conexión. Pulsa «Conectar túnel» para comprobar el túnel de nuevo.";
            self.tunnelConnected = connected;
            self.pairingAvailable = paired;
            self.applicationFileAccessAvailable = fileAccess;
            self.capabilitiesText = capabilities;
            [self updateButtons];
            [self.view setNeedsLayout];
        });
    });
}

- (void)updateButtons {
    [self.connectionStatus showConnected:self.tunnelConnected pairingAvailable:self.pairingAvailable];
    [self.connectionStatus showPairingInProgress:self.pairingInProgress available:self.pairingAvailable];
    self.importButton.enabled = !self.busy;
    self.pairButton.enabled = !self.busy || self.pairingInProgress;
    UIButtonConfiguration *pairConfig = [self.pairButton.configuration copy];
    pairConfig.title = self.pairingInProgress ? @"Cancelar emparejamiento" : @"Emparejar";
    self.pairButton.configuration = pairConfig;
    self.connectButton.enabled = !self.busy && self.pairingAvailable;
    self.cancelPairButton.hidden = !self.pairingInProgress;
    self.cancelPairButton.enabled = self.pairingInProgress;
    self.navigationItem.rightBarButtonItem = self.busy ? XFSpinnerItem() : nil;
    if (!self.busy) [self.refreshControl endRefreshing];
}

- (void)clearPairingPIN {
    self.currentPairingPIN = nil;
    self.pairingPINLabel.text = @"";
    self.pairingPINLabel.accessibilityValue = nil;
    self.pairingPINLabel.hidden = YES;
    self.pinCopyButton.hidden = YES;
}

- (void)copyPairingPIN {
    if (!self.pairingInProgress || self.currentPairingPIN.length != 6) return;
    [UIPasteboard.generalPasteboard setItems:@[@{@"public.utf8-plain-text":self.currentPairingPIN}]
        options:@{UIPasteboardOptionLocalOnly:@YES, UIPasteboardOptionExpirationDate:[NSDate dateWithTimeIntervalSinceNow:120]}];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"PIN copiado");
}

- (void)startOnDevicePairing {
    if (self.busy) return;
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27) {
        XFPresentError(self, @"Se requiere iOS 27", @"Esta forma de emparejar necesita iOS 27 y su opción de emparejamiento en Modo de desarrollador. Puedes seguir usando «Importar emparejamiento» con un registro válido.");
        return;
    }
    self.busy = YES;
    self.pairingInProgress = YES;
    self.pairingCancelling = NO;
    NSUInteger attempt = ++self.pairingAttempt;
    [self clearPairingPIN];
    self.pairingGuideLabel.hidden = NO;
    self.pairingGuideLabel.text = @"Preparando el emparejamiento. Puedes volver a XitForge sin cancelar; para detenerlo usa «Cancelar emparejamiento».";
    self.statusLabel.text = @"Preparando el servicio de emparejamiento…";
    [self updateButtons];
    [self.view setNeedsLayout];

    XFOnDevicePairing *service = [[XFOnDevicePairing alloc] init];
    self.pairingService = service;
    __weak typeof(self) weakSelf = self;
    service.readyHandler = ^(NSString *hostName) {
        typeof(self) self = weakSelf;
        if (!self || self.pairingAttempt != attempt || !self.pairingInProgress) return;
        self.statusLabel.text = @"Servicio listo. Abre Ajustes para iniciar el emparejamiento.";
        self.pairingGuideLabel.text = @"Ajustes > Privacidad y seguridad > Modo de desarrollador > Emparejar con XitForge.\n\nCuando el iPhone se conecte, el PIN aparecerá aquí. Vuelve a XitForge para verlo y después introdúcelo en Ajustes.";
        [self.view setNeedsLayout];
    };
    service.pinHandler = ^(NSString *PIN) {
        typeof(self) self = weakSelf;
        if (!self || self.pairingAttempt != attempt || !self.pairingInProgress) return;
        NSCharacterSet *nonDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
        if (PIN.length != 6 || [PIN rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            [self cancelOnDevicePairing];
            self.statusLabel.text = @"El servicio no proporcionó un PIN válido. Emparejamiento cancelado.";
            [self.view setNeedsLayout];
            return;
        }
        self.currentPairingPIN = PIN;
        self.pairingPINLabel.text = PIN;
        self.pairingPINLabel.accessibilityValue = PIN;
        self.pairingPINLabel.hidden = NO;
        self.pinCopyButton.hidden = NO;
        self.statusLabel.text = @"PIN recibido. Falta aprobar el emparejamiento en Ajustes.";
        self.pairingGuideLabel.text = @"Introduce este PIN en Ajustes > Privacidad y seguridad > Modo de desarrollador > Emparejar con XitForge. El proceso seguirá activo mientras cambias de app.";
        [self.view setNeedsLayout];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"PIN de emparejamiento disponible");
    };
    service.completionHandler = ^(NSURL *recordURL, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.pairingAttempt != attempt) return;
        if (self.pairingCancelling) {
            self.pairingCancelling = NO;
            self.pairingService = nil;
            self.busy = NO;
            self.statusLabel.text = @"Emparejamiento cancelado. Puedes intentarlo de nuevo o importar un registro.";
            [self updateButtons];
            [self.view setNeedsLayout];
            return;
        }
        if (!self.pairingInProgress) return;
        self.pairingInProgress = NO;
        self.pairingService = nil;
        [self clearPairingPIN];
        self.pairingGuideLabel.hidden = YES;
        if (!recordURL || error) {
            self.busy = NO;
            self.statusLabel.text = [NSString stringWithFormat:@"No se completó el emparejamiento. %@", XFErrorMessage(error)];
            [self updateButtons];
            [self.view setNeedsLayout];
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive && self.view.window && !self.presentedViewController) {
                XFPresentError(self, @"No se pudo emparejar", XFErrorMessage(error));
            }
            return;
        }
        self.statusLabel.text = @"Registro de emparejamiento recibido. Guardando…";
        [self updateButtons];
        [self.view setNeedsLayout];
        dispatch_async(self.operationQueue, ^{
            NSError *importError = nil;
            BOOL imported = [self.backend importPairingRecordURL:recordURL error:&importError];
            BOOL available = self.backend.hasPairingRecord;
            BOOL connected = self.backend.connected;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                self.pairingAvailable = available;
                self.tunnelConnected = connected;
                if (imported) {
                    self.applications = @[];
                    [self updateSearchResultsForSearchController:self.appSearch];
                    self.statusLabel.text = @"Emparejamiento guardado. Activa LocalDevVPN y pulsa «Conectar túnel».";
                } else {
                    self.statusLabel.text = [NSString stringWithFormat:@"Se recibió un registro, pero no se pudo importar. %@", XFErrorMessage(importError)];
                    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive && self.view.window && !self.presentedViewController) {
                        XFPresentError(self, @"No se pudo guardar el registro", XFErrorMessage(importError));
                    }
                }
                [self updateButtons];
                [self.view setNeedsLayout];
            });
        });
    };
    [service start];
}

- (void)cancelOnDevicePairing {
    if (!self.pairingInProgress) return;
    self.pairingInProgress = NO;
    self.pairingCancelling = YES;
    // Wait for cleanup before allowing a new session: the previous audio
    // session must not deactivate the keepalive of a new attempt.
    [self.pairingService cancel];
    [self clearPairingPIN];
    self.pairingGuideLabel.hidden = YES;
    self.statusLabel.text = @"Cancelando el emparejamiento…";
    [self updateButtons];
    [self.view setNeedsLayout];
}

- (void)configureEndpoint {
    if (self.busy) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Dirección del túnel"
        message:@"Usa la dirección y el puerto de LocalDevVPN. Los valores iniciales son 10.7.0.1 y 49152."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Dirección IPv4";
        field.text = self.backend.deviceAddress;
        field.keyboardType = UIKeyboardTypeDecimalPad;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Puerto";
        field.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.backend.remotePairingPort];
        field.keyboardType = UIKeyboardTypeNumberPad;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Guardar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *address = [weakAlert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *portText = [weakAlert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        NSUInteger port = (NSUInteger)portText.integerValue;
        struct in_addr parsedAddress;
        BOOL validAddress = address.length && inet_pton(AF_INET, address.UTF8String, &parsedAddress) == 1;
        if (!validAddress || !portText.length || [portText rangeOfCharacterFromSet:nonDigits].location != NSNotFound || port < 1 || port > 65535) {
            XFPresentError(self, @"Dirección no válida", @"Indica una dirección IPv4 y un puerto entre 1 y 65535.");
            return;
        }
        self.busy = YES;
        [self updateButtons];
        dispatch_async(self.operationQueue, ^{
            [self.backend disconnect];
            self.backend.deviceAddress = address;
            self.backend.remotePairingPort = port;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                self.tunnelConnected = NO;
                self.applications = @[];
                [self updateSearchResultsForSearchController:self.appSearch];
                self.statusLabel.text = @"Dirección guardada. Pulsa «Conectar túnel» para comprobarla.";
                [self updateButtons];
                [self.view setNeedsLayout];
            });
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showTunnelHelp {
    XFPresentError(self, @"Activar el túnel", @"Abre LocalDevVPN y activa su conexión VPN. Vuelve a XitForge con el Wi-Fi encendido y pulsa «Conectar túnel».\n\nLa conexión solo se mostrará como establecida cuando el dispositivo responda correctamente.");
}
- (void)showConnectionDiagnostics {
    if (self.busy || self.pairingInProgress) return;
    self.busy = YES; [self updateButtons];
    dispatch_async(self.operationQueue, ^{
        NSString *report = self.backend.connectionDiagnostics;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO; [self updateButtons];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Diagnóstico del túnel"
                message:report preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Copiar diagnóstico" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UIPasteboard.generalPasteboard.string = report;
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cerrar" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)importPairing {
    if (self.busy) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *URL = urls.firstObject;
    if (!URL || self.busy) return;
    BOOL scopedAccess = [URL startAccessingSecurityScopedResource];
    self.busy = YES;
    self.statusLabel.text = @"Validando el emparejamiento…";
    [self updateButtons];
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        BOOL imported = [self.backend importPairingRecordURL:URL error:&error];
        BOOL available = self.backend.hasPairingRecord;
        BOOL connected = self.backend.connected;
        if (scopedAccess) [URL stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.pairingAvailable = available;
            self.tunnelConnected = connected;
            if (imported) {
                self.applications = @[];
                [self updateSearchResultsForSearchController:self.appSearch];
                self.statusLabel.text = @"Emparejamiento importado. Activa el túnel y conecta.";
            } else {
                self.statusLabel.text = @"No se pudo importar ese registro.";
                XFPresentError(self, @"Emparejamiento no válido", XFErrorMessage(error));
            }
            [self updateButtons];
            [self.view setNeedsLayout];
        });
    });
}

- (void)pairingAction {
    if (self.pairingInProgress) [self cancelOnDevicePairing];
    else [self startOnDevicePairing];
}

- (void)connectAndLoad {
    if (self.busy) return;
    if (!self.pairingAvailable) {
        XFPresentError(self, @"Emparejamiento necesario", @"Empareja este iPhone o importa su registro.");
        return;
    }
    self.busy = YES;
    self.statusLabel.text = @"Conectando…";
    [self updateButtons];
    [self.connectionStatus showConnecting];
    dispatch_async(self.operationQueue, ^{
        NSError *error = nil;
        BOOL connected = [self.backend connectWithError:&error];
        BOOL paired = self.backend.hasPairingRecord;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.tunnelConnected = connected;
            self.pairingAvailable = paired;
            self.statusLabel.text = connected ? @"Túnel listo. Activa o desactiva las opciones desde Home." : @"No se pudo conectar. Comprueba LocalDevVPN y Wi-Fi.";
            if (!connected) XFPresentError(self, @"No se pudo conectar", XFErrorMessage(error));
            [self updateButtons];
            [self.view setNeedsLayout];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) {
        self.visibleApplications = self.applications;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *application, NSDictionary *bindings) {
            return [XFString(application[@"name"]) localizedCaseInsensitiveContainsString:query] ||
                   [XFString(application[@"bundleIdentifier"]) localizedCaseInsensitiveContainsString:query];
        }];
        self.visibleApplications = [self.applications filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 0; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return nil; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return nil; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"application"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"application"];
    NSDictionary *application = self.visibleApplications[indexPath.row];
    NSString *identifier = XFString(application[@"bundleIdentifier"]);
    NSString *name = XFString(application[@"name"]);
    cell.textLabel.text = name.length ? name : identifier;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = identifier;
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:@"app"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.busy) return;
    NSString *identifier = XFString(self.visibleApplications[indexPath.row][@"bundleIdentifier"]);
    if (!identifier.length) { XFPresentError(self, @"App sin identificador", @"No se puede abrir el contenedor de esta entrada."); return; }
    XFAirLiftDirectoryController *controller = [[XFAirLiftDirectoryController alloc]
        initWithBackend:self.backend queue:self.operationQueue applicationID:identifier relativePath:@""];
    [self.navigationController pushViewController:controller animated:YES];
}
@end
