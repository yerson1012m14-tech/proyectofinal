#import "HomeViewController.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#pragma mark - XITFORGE Filesystem Engine

static void XITForgeEnsureEngine(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void (*tweakInit)(void) =
            (void (*)(void))dlsym(RTLD_DEFAULT, "TweakInit");

        int (*start)(void) =
            (int (*)(void))dlsym(RTLD_DEFAULT, "MCMFilzaStart");

        void (*setUnrestricted)(int) =
            (void (*)(int))dlsym(
                RTLD_DEFAULT,
                "MCMFilzaSetUnrestrictedFilesystem"
            );

        if (tweakInit) {
            tweakInit();
        }

        if (start) {
            int result = start();
            NSLog(@"XITFORGE MCMFilzaStart -> %d", result);
        }

        if (setUnrestricted) {
            setUnrestricted(1);
        }
    });
}

static NSString *XITForgeDataContainerPath(NSString *bundleId) {
    if (bundleId.length == 0) {
        return nil;
    }

    XITForgeEnsureEngine();

    NSString *(*dataPath)(NSString *) =
        (NSString *(*)(NSString *))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaDataContainerPath"
        );

    if (!dataPath) {
        NSLog(@"XITFORGE: MCMFilzaDataContainerPath no disponible");
        return nil;
    }

    NSString *path = dataPath(bundleId);

    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        NSLog(@"XITFORGE: contenedor no resuelto para %@", bundleId);
        return nil;
    }

    return [path stringByStandardizingPath];
}

#pragma mark - XITFORGE Option Model

@interface XITForgeOption : NSObject

@property (nonatomic, strong) NSNumber *optionId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *optionDescription;
@property (nonatomic, copy) NSString *game;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *route;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *fileUrl;

@end

@implementation XITForgeOption
@end

#pragma mark - Options View Controller

@interface XITForgeOptionsViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic, copy) NSString *game;
@property (nonatomic, copy) NSString *bundleId;

@property (nonatomic, strong) NSArray<XITForgeOption *> *options;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) NSURLSession *downloadSession;

@end

@implementation XITForgeOptionsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor =
        [UIColor blackColor];

    if ([self.game isEqualToString:@"freefire_max"]) {
        self.title = @"FREE FIRE MAX";
    } else {
        self.title = @"FREE FIRE NORMAL";
    }

    [self setupUI];
    [self loadOptions];
}

#pragma mark - UI

- (void)setupUI {

    UIColor *background =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.03
                        alpha:1.0];

    self.view.backgroundColor =
        background;

    self.tableView =
        [[UITableView alloc]
            initWithFrame:CGRectZero
                    style:UITableViewStyleInsetGrouped];

    self.tableView.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.tableView.backgroundColor =
        background;

    self.tableView.dataSource =
        self;

    self.tableView.delegate =
        self;

    self.tableView.separatorStyle =
        UITableViewCellSeparatorStyleNone;

    self.tableView.estimatedRowHeight =
        92.0;

    [self.view addSubview:self.tableView];


    self.activityIndicator =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleLarge];

    self.activityIndicator.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.activityIndicator.color =
        [UIColor colorWithRed:0.95
                        green:0.08
                         blue:0.10
                        alpha:1.0];

    [self.view addSubview:
        self.activityIndicator];


    self.statusLabel =
        [[UILabel alloc] init];

    self.statusLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.statusLabel.textColor =
        [UIColor colorWithWhite:0.55
                          alpha:1.0];

    self.statusLabel.font =
        [UIFont systemFontOfSize:14.0];

    self.statusLabel.textAlignment =
        NSTextAlignmentCenter;

    self.statusLabel.numberOfLines =
        0;

    [self.view addSubview:
        self.statusLabel];


    [NSLayoutConstraint activateConstraints:@[

        [self.tableView.topAnchor
            constraintEqualToAnchor:
                self.view.topAnchor],

        [self.tableView.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor],

        [self.tableView.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor],

        [self.tableView.bottomAnchor
            constraintEqualToAnchor:
                self.view.bottomAnchor],


        [self.activityIndicator.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [self.activityIndicator.centerYAnchor
            constraintEqualToAnchor:
                self.view.centerYAnchor],


        [self.statusLabel.topAnchor
            constraintEqualToAnchor:
                self.activityIndicator.bottomAnchor
                constant:14.0],

        [self.statusLabel.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                self.view.leadingAnchor
                constant:30.0],

        [self.statusLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                self.view.trailingAnchor
                constant:-30.0],

        [self.statusLabel.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor]
    ]];
}

#pragma mark - API

- (NSString *)apiBaseURL {
    return @"https://xitforge-license-server.onrender.com";
}

- (void)loadOptions {

    [self.activityIndicator startAnimating];

    self.statusLabel.text =
        @"Cargando opciones...";

    self.statusLabel.hidden =
        NO;

    NSString *encodedGame =
        [self.game
            stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet URLQueryAllowedCharacterSet]];

    NSString *urlString =
        [NSString stringWithFormat:
            @"%@/api/app/options?game=%@",
            [self apiBaseURL],
            encodedGame];

    NSURL *url =
        [NSURL URLWithString:urlString];

    if (!url) {

        [self showError:
            @"No se pudo crear la dirección del servidor."];

        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod =
        @"GET";

    request.timeoutInterval =
        20.0;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:
        ^(NSData * _Nullable data,
          NSURLResponse * _Nullable response,
          NSError * _Nullable error) {

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                [self.activityIndicator
                    stopAnimating];

                if (error) {

                    NSLog(
                        @"XITFORGE options error: %@",
                        error
                    );

                    [self showError:
                        @"No se pudieron cargar las opciones."];

                    return;
                }

                if (!data) {

                    [self showError:
                        @"El servidor no devolvió datos."];

                    return;
                }

                NSError *jsonError =
                    nil;

                id json =
                    [NSJSONSerialization
                        JSONObjectWithData:data
                        options:0
                        error:&jsonError];

                if (
                    jsonError ||
                    ![json isKindOfClass:
                        [NSDictionary class]]
                ) {

                    NSLog(
                        @"XITFORGE invalid JSON: %@",
                        jsonError
                    );

                    [self showError:
                        @"La respuesta del servidor no es válida."];

                    return;
                }

                NSDictionary *dictionary =
                    (NSDictionary *)json;

                NSNumber *ok =
                    dictionary[@"ok"];

                if (
                    ![ok isKindOfClass:
                        [NSNumber class]] ||
                    !ok.boolValue
                ) {

                    NSString *serverError =
                        [dictionary[@"error"]
                            isKindOfClass:
                                [NSString class]]
                        ? dictionary[@"error"]
                        : @"No se pudieron cargar las opciones.";

                    [self showError:
                        serverError];

                    return;
                }

                NSArray *rawOptions =
                    dictionary[@"options"];

                if (
                    ![rawOptions isKindOfClass:
                        [NSArray class]]
                ) {

                    [self showError:
                        @"No hay opciones disponibles."];

                    return;
                }

                NSMutableArray *parsed =
                    [NSMutableArray array];

                for (id rawItem in rawOptions) {

                    if (
                        ![rawItem isKindOfClass:
                            [NSDictionary class]]
                    ) {
                        continue;
                    }

                    NSDictionary *raw =
                        (NSDictionary *)rawItem;

                    XITForgeOption *option =
                        [[XITForgeOption alloc] init];

                    if (
                        [raw[@"id"] isKindOfClass:
                            [NSNumber class]]
                    ) {
                        option.optionId =
                            raw[@"id"];
                    }

                    if (
                        [raw[@"name"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.name =
                            raw[@"name"];
                    }

                    if (
                        [raw[@"description"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.optionDescription =
                            raw[@"description"];
                    }

                    if (
                        [raw[@"game"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.game =
                            raw[@"game"];
                    }

                    if (
                        [raw[@"bundleId"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.bundleId =
                            raw[@"bundleId"];
                    } else if (
                        [dictionary[@"bundleId"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.bundleId =
                            dictionary[@"bundleId"];
                    } else {
                        option.bundleId =
                            self.bundleId;
                    }

                    if (
                        [raw[@"route"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.route =
                            raw[@"route"];
                    }

                    if (
                        [raw[@"fileName"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.fileName =
                            raw[@"fileName"];
                    } else if (
                        [raw[@"file"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.fileName =
                            raw[@"file"];
                    }

                    if (
                        [raw[@"fileUrl"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.fileUrl =
                            raw[@"fileUrl"];
                    }

                    [parsed addObject:
                        option];
                }

                self.options =
                    [parsed copy];

                [self.tableView
                    reloadData];

                if (self.options.count == 0) {

                    self.statusLabel.text =
                        @"No hay opciones disponibles.";

                    self.statusLabel.hidden =
                        NO;

                } else {

                    self.statusLabel.hidden =
                        YES;
                }
            });
    }];

    [task resume];
}

#pragma mark - Error

- (void)showError:
    (NSString *)message {

    [self.activityIndicator
        stopAnimating];

    self.statusLabel.text =
        message;

    self.statusLabel.hidden =
        NO;

    [self.tableView
        reloadData];
}

#pragma mark - TableView

- (NSInteger)tableView:
    (UITableView *)tableView
 numberOfRowsInSection:
    (NSInteger)section {

    return self.options.count;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
 cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    static NSString *identifier =
        @"XITForgeOptionCell";

    UITableViewCell *cell =
        [tableView
            dequeueReusableCellWithIdentifier:
                identifier];

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:
                    UITableViewCellStyleSubtitle
                reuseIdentifier:
                    identifier];

        cell.backgroundColor =
            [UIColor colorWithRed:0.07
                            green:0.07
                             blue:0.09
                            alpha:1.0];

        cell.layer.cornerRadius =
            16.0;

        cell.layer.masksToBounds =
            YES;

        cell.selectionStyle =
            UITableViewCellSelectionStyleDefault;
    }

    XITForgeOption *option =
        self.options[indexPath.row];

    cell.textLabel.text =
        option.name ?: @"Opción";

    cell.textLabel.textColor =
        [UIColor colorWithWhite:0.96
                          alpha:1.0];

    cell.textLabel.font =
        [UIFont systemFontOfSize:17.0
                          weight:UIFontWeightSemibold];

    cell.detailTextLabel.text =
        option.optionDescription ?: @"";

    cell.detailTextLabel.textColor =
        [UIColor colorWithWhite:0.56
                          alpha:1.0];

    cell.detailTextLabel.font =
        [UIFont systemFontOfSize:13.0];

    cell.detailTextLabel.numberOfLines =
        2;

    cell.imageView.image =
        [UIImage systemImageNamed:
            @"slider.horizontal.3"];

    cell.imageView.tintColor =
        [UIColor colorWithRed:0.95
                        green:0.08
                         blue:0.10
                        alpha:1.0];

    cell.accessoryType =
        UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

- (CGFloat)tableView:
    (UITableView *)tableView
heightForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    return 88.0;
}

#pragma mark - Option Selection

- (void)tableView:
    (UITableView *)tableView
 didSelectRowAtIndexPath:
    (NSIndexPath *)indexPath {

    [tableView
        deselectRowAtIndexPath:
            indexPath
        animated:YES];

    if (
        indexPath.row >=
        self.options.count
    ) {
        return;
    }

    XITForgeOption *option =
        self.options[indexPath.row];

    [self applyOption:
        option];
}

#pragma mark - File Application

- (NSString *)safePathComponent:
    (NSString *)value {

    if (value.length == 0) {
        return nil;
    }

    if (
        [value isEqualToString:@"."] ||
        [value isEqualToString:@".."] ||
        [value containsString:@"/"] ||
        [value containsString:@"\\"] ||
        [value containsString:@"\0"]
    ) {
        return nil;
    }

    return value;
}

- (NSString *)normalizedRouteComponent:
    (NSString *)component
    index:(NSUInteger)index {

    if (index != 0) {
        return component;
    }

    NSString *lower =
        component.lowercaseString;

    if ([lower isEqualToString:@"documents"]) {
        return @"Documents";
    }

    if ([lower isEqualToString:@"library"]) {
        return @"Library";
    }

    if ([lower isEqualToString:@"tmp"]) {
        return @"tmp";
    }

    return component;
}

- (NSURL *)destinationURLForOption:
    (XITForgeOption *)option {

    NSString *bundleId =
        option.bundleId.length > 0
            ? option.bundleId
            : self.bundleId;

    NSString *container =
        XITForgeDataContainerPath(bundleId);

    if (container.length == 0) {
        NSLog(
            @"XITFORGE: no se pudo resolver el contenedor de %@",
            bundleId
        );
        return nil;
    }

    NSString *fileName =
        [self safePathComponent:
            option.fileName];

    if (fileName.length == 0) {
        NSLog(@"XITFORGE: fileName invalido");
        return nil;
    }

    NSString *route =
        [option.route
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (route.length == 0) {
        NSLog(@"XITFORGE: route vacio");
        return nil;
    }

    route =
        [route stringByReplacingOccurrencesOfString:@"\\"
                                         withString:@"/"];

    while ([route hasPrefix:@"/"]) {
        route =
            [route substringFromIndex:1];
    }

    NSURL *destinationFolder =
        [NSURL fileURLWithPath:container
                   isDirectory:YES];

    NSArray<NSString *> *components =
        [route componentsSeparatedByString:@"/"];

    NSUInteger validIndex = 0;

    for (NSString *rawComponent in components) {

        NSString *component =
            [rawComponent
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (component.length == 0) {
            continue;
        }

        component =
            [self normalizedRouteComponent:
                component
                index:validIndex];

        if (![self safePathComponent:component]) {
            NSLog(
                @"XITFORGE: componente de route invalido: %@",
                component
            );
            return nil;
        }

        destinationFolder =
            [destinationFolder
                URLByAppendingPathComponent:
                    component
                isDirectory:YES];

        validIndex++;
    }

    if (validIndex == 0) {
        return nil;
    }

    NSString *standardContainer =
        [container stringByStandardizingPath];

    NSString *standardFolder =
        [destinationFolder.path stringByStandardizingPath];

    NSString *containerPrefix =
        [standardContainer stringByAppendingString:@"/"];

    if (
        ![standardFolder isEqualToString:standardContainer] &&
        ![standardFolder hasPrefix:containerPrefix]
    ) {
        NSLog(@"XITFORGE: route intento salir del contenedor");
        return nil;
    }

    NSError *directoryError = nil;

    BOOL created =
        [[NSFileManager defaultManager]
            createDirectoryAtURL:
                destinationFolder
            withIntermediateDirectories:YES
            attributes:nil
            error:&directoryError];

    if (!created) {
        NSLog(
            @"XITFORGE destination directory error: %@",
            directoryError
        );
        return nil;
    }

    NSURL *destinationURL =
        [destinationFolder
            URLByAppendingPathComponent:
                fileName
            isDirectory:NO];

    NSLog(
        @"XITFORGE resolved destination: bundleId=%@ route=%@ file=%@ -> %@",
        bundleId,
        option.route,
        fileName,
        destinationURL.path
    );

    return destinationURL;
}

- (void)applyOption:
    (XITForgeOption *)option {

    if (option.fileUrl.length == 0) {
        [self showResult:
            @"Esta opción no tiene un archivo configurado."
            success:NO];
        return;
    }

    if (option.route.length == 0) {
        [self showResult:
            @"Esta opción no tiene una ruta configurada."
            success:NO];
        return;
    }

    if (option.fileName.length == 0) {
        [self showResult:
            @"Esta opción no tiene un nombre de archivo configurado."
            success:NO];
        return;
    }

    NSURL *destinationURL =
        [self destinationURLForOption:
            option];

    if (!destinationURL) {
        [self showResult:
            @"No se pudo resolver el contenedor del juego o la ruta configurada."
            success:NO];
        return;
    }

    NSURL *downloadURL =
        [NSURL URLWithString:
            option.fileUrl];

    if (!downloadURL) {
        [self showResult:
            @"La URL del archivo no es válida."
            success:NO];
        return;
    }

    [self startDownload:
        downloadURL
        option:option
        destinationURL:destinationURL];
}

#pragma mark - Download

- (void)startDownload:
    (NSURL *)url
    option:(XITForgeOption *)option
    destinationURL:(NSURL *)destinationURL {

    [self.activityIndicator
        startAnimating];

    self.statusLabel.text =
        [NSString stringWithFormat:
            @"Descargando %@...",
            option.name ?: @"archivo"];

    self.statusLabel.hidden =
        NO;

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration
            defaultSessionConfiguration];

    configuration.timeoutIntervalForRequest =
        30.0;

    configuration.timeoutIntervalForResource =
        60.0;

    self.downloadSession =
        [NSURLSession
            sessionWithConfiguration:
                configuration
            delegate:self
            delegateQueue:
                [NSOperationQueue mainQueue]];

    NSURLSessionDownloadTask *task =
        [self.downloadSession
            downloadTaskWithURL:url];

    task.taskDescription =
        [NSString stringWithFormat:
            @"%ld|%@",
            (long)option.optionId.integerValue,
            destinationURL.path];

    [task resume];
}

#pragma mark - Download Delegate

- (void)URLSession:
    (NSURLSession *)session
downloadTask:
    (NSURLSessionDownloadTask *)downloadTask
 didFinishDownloadingToURL:
    (NSURL *)location {

    NSString *description =
        downloadTask.taskDescription;

    NSArray *parts =
        [description componentsSeparatedByString:@"|"];

    if (parts.count < 2) {

        [self showResult:
            @"No se pudo determinar el destino del archivo."
            success:NO];

        return;
    }

    NSString *destinationPath =
        parts[1];

    NSURL *destinationURL =
        [NSURL fileURLWithPath:
            destinationPath];

    NSFileManager *fm =
        [NSFileManager defaultManager];

    /*
     * SEGURIDAD:
     * Nunca eliminar una carpeta.
     *
     * removeItemAtURL: elimina directorios de forma recursiva.
     * Por eso primero comprobamos que el destino existente sea
     * realmente un archivo. Los demás archivos de la carpeta
     * deben permanecer intactos.
     */

    BOOL isDirectory =
        NO;

    BOOL destinationExists =
        [fm fileExistsAtPath:
            destinationURL.path
                    isDirectory:
            &isDirectory];

    if (destinationExists && isDirectory) {

        NSLog(
            @"XITFORGE SAFETY: el destino apunta a una carpeta, se cancela: %@",
            destinationURL.path
        );

        [self showResult:
            @"La ruta final apunta a una carpeta. Por seguridad no se eliminó ni modificó ningún archivo."
            success:NO];

        return;
    }

    /*
     * Si ya existe un archivo con exactamente el mismo nombre,
     * solo se elimina ESE archivo antes de colocar el nuevo.
     */

    if (destinationExists) {

        NSError *removeError =
            nil;

        BOOL removed =
            [fm removeItemAtURL:
                destinationURL
                         error:
                &removeError];

        if (!removed) {

            NSLog(
                @"XITFORGE remove previous file error: %@",
                removeError
            );

            [self showResult:
                @"No se pudo reemplazar el archivo anterior."
                success:NO];

            return;
        }
    }

    NSError *copyError =
        nil;

    BOOL copied =
        [fm copyItemAtURL:
            location
                   toURL:
            destinationURL
                  error:
            &copyError];

    if (!copied) {

        NSLog(
            @"XITFORGE copy file error: %@",
            copyError
        );

        [self showResult:
            @"No se pudo guardar el archivo en la ruta configurada."
            success:NO];

        return;
    }

    [self showResult:
        @"La opción se aplicó correctamente."
        success:YES];
}

- (void)URLSession:
    (NSURLSession *)session
  task:
    (NSURLSessionTask *)task
didCompleteWithError:
    (NSError *)error {

    [self.activityIndicator
        stopAnimating];

    if (error) {

        NSLog(
            @"XITFORGE download error: %@",
            error
        );

        [self showResult:
            @"No se pudo descargar el archivo."
            success:NO];
    }

    [session finishTasksAndInvalidate];

    self.downloadSession =
        nil;
}

#pragma mark - Result

- (void)showResult:
    (NSString *)message
    success:(BOOL)success {

    [self.activityIndicator
        stopAnimating];

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:
                success
                    ? @"Aplicado correctamente"
                    : @"No se pudo aplicar"
            message:message
            preferredStyle:
                UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"OK"
            style:
                UIAlertActionStyleDefault
            handler:nil]];

    [self presentViewController:
        alert
        animated:YES
        completion:nil];
}

@end

#pragma mark - HomeViewController

@interface HomeViewController ()

@property (nonatomic, strong) UIButton *btnNormal;
@property (nonatomic, strong) UIButton *btnMax;

@end

@implementation HomeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {

    [super viewDidLoad];

    self.view.backgroundColor =
        [UIColor blackColor];

    self.title =
        @"XITFORGE";

    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeAlways;

    [self setupUI];
}

#pragma mark - UI

- (void)setupUI {

    UIColor *white =
        [UIColor colorWithWhite:0.96
                          alpha:1.0];

    UIColor *red =
        [UIColor colorWithRed:0.95
                        green:0.08
                         blue:0.10
                        alpha:1.0];

    UIColor *green =
        [UIColor colorWithRed:0.2
                        green:1.0
                         blue:0.5
                        alpha:1.0];

    UIView *topGlow =
        [[UIView alloc] init];

    topGlow.translatesAutoresizingMaskIntoConstraints =
        NO;

    topGlow.backgroundColor =
        [red colorWithAlphaComponent:0.055];

    topGlow.layer.cornerRadius =
        170.0;

    topGlow.layer.masksToBounds =
        YES;

    topGlow.userInteractionEnabled =
        NO;

    [self.view addSubview:
        topGlow];


    UIView *bottomGlow =
        [[UIView alloc] init];

    bottomGlow.translatesAutoresizingMaskIntoConstraints =
        NO;

    bottomGlow.backgroundColor =
        [green colorWithAlphaComponent:0.045];

    bottomGlow.layer.cornerRadius =
        150.0;

    bottomGlow.layer.masksToBounds =
        YES;

    bottomGlow.userInteractionEnabled =
        NO;

    [self.view addSubview:
        bottomGlow];


    UILabel *logo =
        [[UILabel alloc] init];

    logo.translatesAutoresizingMaskIntoConstraints =
        NO;

    logo.text =
        @"XITFORGE";

    logo.textColor =
        white;

    logo.font =
        [UIFont systemFontOfSize:36.0
                          weight:UIFontWeightBold];

    logo.textAlignment =
        NSTextAlignmentCenter;

    [self.view addSubview:
        logo];


    UIView *line =
        [[UIView alloc] init];

    line.translatesAutoresizingMaskIntoConstraints =
        NO;

    line.backgroundColor =
        red;

    line.layer.cornerRadius =
        1.0;

    line.layer.shadowColor =
        red.CGColor;

    line.layer.shadowOpacity =
        0.30;

    line.layer.shadowRadius =
        5.0;

    line.layer.shadowOffset =
        CGSizeZero;

    [self.view addSubview:
        line];


    UILabel *pregunta =
        [[UILabel alloc] init];

    pregunta.translatesAutoresizingMaskIntoConstraints =
        NO;

    pregunta.text =
        @"¿EN CUAL JUEGAS?";

    pregunta.textColor =
        white;

    pregunta.font =
        [UIFont systemFontOfSize:20.0
                          weight:UIFontWeightBold];

    pregunta.textAlignment =
        NSTextAlignmentCenter;

    [self.view addSubview:
        pregunta];


    /*
     * ========================================================
     * NORMAL
     * ========================================================
     */

    self.btnNormal =
        [UIButton buttonWithType:
            UIButtonTypeCustom];

    self.btnNormal.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.btnNormal.backgroundColor =
        [UIColor colorWithRed:0.12
                        green:0.12
                         blue:0.14
                        alpha:1.0];

    self.btnNormal.layer.cornerRadius =
        14.0;

    self.btnNormal.layer.borderWidth =
        1.5;

    self.btnNormal.layer.borderColor =
        red.CGColor;

    self.btnNormal.layer.shadowColor =
        red.CGColor;

    self.btnNormal.layer.shadowOpacity =
        0.25;

    self.btnNormal.layer.shadowRadius =
        10.0;

    self.btnNormal.layer.shadowOffset =
        CGSizeZero;

    [self.btnNormal
        setTitle:
            @"FREE FIRE\nNORMAL"
        forState:
            UIControlStateNormal];

    self.btnNormal.titleLabel.font =
        [UIFont boldSystemFontOfSize:14.0];

    [self.btnNormal
        setTitleColor:
            white
        forState:
            UIControlStateNormal];

    self.btnNormal.titleLabel.numberOfLines =
        2;

    self.btnNormal.titleLabel.textAlignment =
        NSTextAlignmentCenter;

    [self.btnNormal
        addTarget:self
        action:@selector(btnNormalTapped)
        forControlEvents:
            UIControlEventTouchUpInside];

    [self.view addSubview:
        self.btnNormal];


    /*
     * ========================================================
     * MAX
     * ========================================================
     */

    self.btnMax =
        [UIButton buttonWithType:
            UIButtonTypeCustom];

    self.btnMax.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.btnMax.backgroundColor =
        [UIColor colorWithRed:0.12
                        green:0.12
                         blue:0.14
                        alpha:1.0];

    self.btnMax.layer.cornerRadius =
        14.0;

    self.btnMax.layer.borderWidth =
        1.5;

    self.btnMax.layer.borderColor =
        green.CGColor;

    self.btnMax.layer.shadowColor =
        green.CGColor;

    self.btnMax.layer.shadowOpacity =
        0.25;

    self.btnMax.layer.shadowRadius =
        10.0;

    self.btnMax.layer.shadowOffset =
        CGSizeZero;

    [self.btnMax
        setTitle:
            @"FREE FIRE\nMAX"
        forState:
            UIControlStateNormal];

    self.btnMax.titleLabel.font =
        [UIFont boldSystemFontOfSize:14.0];

    [self.btnMax
        setTitleColor:
            white
        forState:
            UIControlStateNormal];

    self.btnMax.titleLabel.numberOfLines =
        2;

    self.btnMax.titleLabel.textAlignment =
        NSTextAlignmentCenter;

    [self.btnMax
        addTarget:self
        action:@selector(btnMaxTapped)
        forControlEvents:
            UIControlEventTouchUpInside];

    [self.view addSubview:
        self.btnMax];


    /*
     * ========================================================
     * CONSTRAINTS
     * ========================================================
     */

    [NSLayoutConstraint activateConstraints:@[

        [topGlow.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [topGlow.topAnchor
            constraintEqualToAnchor:
                self.view.topAnchor
                constant:-220.0],

        [topGlow.widthAnchor
            constraintEqualToConstant:340.0],

        [topGlow.heightAnchor
            constraintEqualToConstant:340.0],


        [bottomGlow.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [bottomGlow.bottomAnchor
            constraintEqualToAnchor:
                self.view.bottomAnchor
                constant:170.0],

        [bottomGlow.widthAnchor
            constraintEqualToConstant:300.0],

        [bottomGlow.heightAnchor
            constraintEqualToConstant:300.0],


        [logo.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [logo.topAnchor
            constraintEqualToAnchor:
                self.view.safeAreaLayoutGuide.topAnchor
                constant:40.0],


        [line.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [line.topAnchor
            constraintEqualToAnchor:
                logo.bottomAnchor
                constant:12.0],

        [line.widthAnchor
            constraintEqualToConstant:60.0],

        [line.heightAnchor
            constraintEqualToConstant:2.0],


        [pregunta.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [pregunta.topAnchor
            constraintEqualToAnchor:
                line.bottomAnchor
                constant:50.0],

        [pregunta.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                self.view.leadingAnchor
                constant:20.0],

        [pregunta.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                self.view.trailingAnchor
                constant:-20.0],


        [self.btnNormal.topAnchor
            constraintEqualToAnchor:
                pregunta.bottomAnchor
                constant:40.0],

        [self.btnNormal.trailingAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor
                constant:-8.0],

        [self.btnNormal.widthAnchor
            constraintEqualToConstant:140.0],

        [self.btnNormal.heightAnchor
            constraintEqualToConstant:80.0],


        [self.btnMax.topAnchor
            constraintEqualToAnchor:
                pregunta.bottomAnchor
                constant:40.0],

        [self.btnMax.leadingAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor
                constant:8.0],

        [self.btnMax.widthAnchor
            constraintEqualToConstant:140.0],

        [self.btnMax.heightAnchor
            constraintEqualToConstant:80.0]
    ]];
}

#pragma mark - Buttons

- (void)btnNormalTapped {

    [self openOptionsForGame:
        @"freefire_normal"
        bundleID:
            @"com.dts.freefireth"];
}

- (void)btnMaxTapped {

    [self openOptionsForGame:
        @"freefire_max"
        bundleID:
            @"com.dts.freefiremax"];
}

#pragma mark - Open Options

- (void)openOptionsForGame:
    (NSString *)game
    bundleID:(NSString *)bundleID {

    XITForgeOptionsViewController *optionsVC =
        [[XITForgeOptionsViewController alloc] init];

    optionsVC.game =
        game;

    optionsVC.bundleId =
        bundleID;

    [self.navigationController
        pushViewController:
            optionsVC
        animated:YES];
}

@end
