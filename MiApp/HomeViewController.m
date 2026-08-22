#import "HomeViewController.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>
#import <string.h>


#pragma mark - XITFORGE Exact File Writer

/*
 * Escribe SOLAMENTE el archivo exacto indicado por destinationURL.
 *
 * - No borra carpetas.
 * - No enumera ni elimina archivos hermanos.
 * - Si el archivo no existe, lo crea.
 * - Si existe un archivo normal con el mismo nombre, lo sobrescribe.
 * - Si el destino es una carpeta o un symlink, cancela.
 */
static BOOL XITForgeWriteExactFile(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSError **errorOut
) {
    NSString *sourcePath = sourceURL.path;
    NSString *destinationPath = destinationURL.path;

    if (sourcePath.length == 0 || destinationPath.length == 0) {
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"XITFORGE"
                                             code:2001
                                         userInfo:@{
                NSLocalizedDescriptionKey:
                    @"Ruta de origen o destino vacía."
            }];
        }
        return NO;
    }

    const char *src =
        sourcePath.fileSystemRepresentation;

    const char *dst =
        destinationPath.fileSystemRepresentation;

    struct stat dstInfo;

    if (lstat(dst, &dstInfo) == 0) {

        if (S_ISDIR(dstInfo.st_mode)) {
            if (errorOut) {
                *errorOut = [NSError errorWithDomain:@"XITFORGE"
                                                 code:2002
                                             userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"El destino es una carpeta; no se modificó."
                }];
            }
            return NO;
        }

        if (S_ISLNK(dstInfo.st_mode)) {
            if (errorOut) {
                *errorOut = [NSError errorWithDomain:@"XITFORGE"
                                                 code:2003
                                             userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"El destino es un enlace simbólico; no se modificó."
                }];
            }
            return NO;
        }

        if (!S_ISREG(dstInfo.st_mode)) {
            if (errorOut) {
                *errorOut = [NSError errorWithDomain:@"XITFORGE"
                                                 code:2004
                                             userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"El destino existente no es un archivo normal."
                }];
            }
            return NO;
        }

    } else if (errno != ENOENT) {

        int e = errno;

        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:e
                                         userInfo:nil];
        }

        return NO;
    }

    int inFD =
        open(src, O_RDONLY | O_CLOEXEC);

    if (inFD < 0) {

        int e = errno;

        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:e
                                         userInfo:nil];
        }

        return NO;
    }

    int flags =
        O_WRONLY |
        O_CREAT |
        O_TRUNC |
        O_CLOEXEC;

#ifdef O_NOFOLLOW
    flags |= O_NOFOLLOW;
#endif

    int outFD =
        open(dst, flags, 0644);

    if (outFD < 0) {

        int e = errno;

        close(inFD);

        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:e
                                         userInfo:nil];
        }

        return NO;
    }

    BOOL ok = YES;
    int savedErrno = 0;
    unsigned char buffer[256 * 1024];

    for (;;) {

        ssize_t bytesRead =
            read(inFD, buffer, sizeof(buffer));

        if (bytesRead == 0) {
            break;
        }

        if (bytesRead < 0) {

            if (errno == EINTR) {
                continue;
            }

            ok = NO;
            savedErrno = errno;
            break;
        }

        ssize_t writtenTotal = 0;

        while (writtenTotal < bytesRead) {

            ssize_t bytesWritten =
                write(
                    outFD,
                    buffer + writtenTotal,
                    (size_t)(bytesRead - writtenTotal)
                );

            if (bytesWritten < 0) {

                if (errno == EINTR) {
                    continue;
                }

                ok = NO;
                savedErrno = errno;
                break;
            }

            writtenTotal += bytesWritten;
        }

        if (!ok) {
            break;
        }
    }

    if (ok && fsync(outFD) != 0) {
        ok = NO;
        savedErrno = errno;
    }

    close(outFD);
    close(inFD);

    if (!ok) {

        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:savedErrno
                                         userInfo:nil];
        }

        return NO;
    }

    return YES;
}


#pragma mark - XITFORGE Exact File Verification

/*
 * Verifica byte por byte que el archivo escrito sea exactamente
 * igual al archivo descargado antes de mostrar "Aplicado correctamente".
 */
static BOOL XITForgeFilesAreIdentical(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSError **errorOut
) {
    const char *src = sourceURL.path.fileSystemRepresentation;
    const char *dst = destinationURL.path.fileSystemRepresentation;

    int inFD = open(src, O_RDONLY | O_CLOEXEC);
    if (inFD < 0) {
        int e = errno;
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:e
                                         userInfo:nil];
        }
        return NO;
    }

    int outFD = open(dst, O_RDONLY | O_CLOEXEC);
    if (outFD < 0) {
        int e = errno;
        close(inFD);
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:e
                                         userInfo:nil];
        }
        return NO;
    }

    struct stat srcInfo = {0};
    struct stat dstInfo = {0};

    if (fstat(inFD, &srcInfo) != 0 || fstat(outFD, &dstInfo) != 0) {
        int e = errno;
        close(inFD);
        close(outFD);
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:e
                                         userInfo:nil];
        }
        return NO;
    }

    if (!S_ISREG(srcInfo.st_mode) ||
        !S_ISREG(dstInfo.st_mode) ||
        srcInfo.st_size != dstInfo.st_size) {

        close(inFD);
        close(outFD);

        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"XITFORGE"
                                             code:2101
                                         userInfo:@{
                NSLocalizedDescriptionKey:
                    @"El archivo escrito no coincide en tamaño con la descarga."
            }];
        }

        return NO;
    }

    unsigned char left[256 * 1024];
    unsigned char right[256 * 1024];

    BOOL identical = YES;
    int savedErrno = 0;

    for (;;) {
        ssize_t l = -1;
        ssize_t r = -1;

        do {
            l = read(inFD, left, sizeof(left));
        } while (l < 0 && errno == EINTR);

        if (l < 0) {
            identical = NO;
            savedErrno = errno;
            break;
        }

        do {
            r = read(outFD, right, sizeof(right));
        } while (r < 0 && errno == EINTR);

        if (r < 0) {
            identical = NO;
            savedErrno = errno;
            break;
        }

        if (l != r) {
            identical = NO;
            break;
        }

        if (l == 0) {
            break;
        }

        if (memcmp(left, right, (size_t)l) != 0) {
            identical = NO;
            break;
        }
    }

    close(inFD);
    close(outFD);

    if (!identical && errorOut) {
        if (savedErrno != 0) {
            *errorOut = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:savedErrno
                                         userInfo:nil];
        } else {
            *errorOut = [NSError errorWithDomain:@"XITFORGE"
                                             code:2102
                                         userInfo:@{
                NSLocalizedDescriptionKey:
                    @"El contenido escrito no coincide con la descarga."
            }];
        }
    }

    return identical;
}

#pragma mark - XITFORGE Filesystem Engine

/*
 * FilzaSlop exporta TweakInit como constructor del dylib.
 * El loader ya lo ejecuta automáticamente.
 *
 * NO llamar TweakInit manualmente:
 * volvería a instalar hooks ya instalados y puede provocar recursión/crash,
 * especialmente en LSApplicationWorkspace/allApplications al abrir Explorar.
 *
 * Tampoco se activa MCMFilzaSetUnrestrictedFilesystem(1).
 */
static void XITForgeEnsureEngine(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        void (*start)(void) =
            (void (*)(void))dlsym(
                RTLD_DEFAULT,
                "MCMFilzaStart"
            );

        if (start) {
            start();
            NSLog(@"XITFORGE: MCMFilzaStart listo");
        } else {
            NSLog(@"XITFORGE: MCMFilzaStart no disponible");
        }
    });
}

static NSString *XITForgeDataContainerPath(
    NSString *bundleId,
    NSString **errorOut
) {
    if (errorOut) *errorOut = nil;

    if (bundleId.length == 0) {
        if (errorOut) *errorOut = @"bundleId vacío";
        return nil;
    }

    XITForgeEnsureEngine();

    NSString *(*dataPath)(NSString *, NSString **) =
        (NSString *(*)(NSString *, NSString **))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaDataContainerPath"
        );

    NSString *directDetail = nil;
    NSString *directPath = nil;

    if (dataPath) {
        directPath = dataPath(bundleId, &directDetail);
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    if ([directPath isKindOfClass:[NSString class]] && directPath.length > 0) {
        NSString *standard = [directPath stringByStandardizingPath];
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:standard isDirectory:&isDirectory] && isDirectory) {
            return standard;
        }
    }

    /*
     * Respaldo seguro: FilzaSlop crea enlaces de los contenedores activados en
     * Documents/Device Storage/[MHA-C2] App Data/<bundleId>.
     * Si el lookup directo no devuelve una ruta utilizable, usamos ese enlace
     * existente. No se crea ni se borra nada aquí.
     */
    NSString *(*virtualRoot)(void) =
        (NSString *(*)(void))dlsym(
            RTLD_DEFAULT,
            "MCMFilzaVirtualRoot"
        );

    if (virtualRoot) {
        NSString *root = virtualRoot();
        if ([root isKindOfClass:[NSString class]] && root.length > 0) {
            NSString *linkPath =
                [[[root stringByAppendingPathComponent:@"[MHA-C2] App Data"]
                    stringByAppendingPathComponent:bundleId]
                    stringByStandardizingPath];

            BOOL isDirectory = NO;
            if ([fm fileExistsAtPath:linkPath isDirectory:&isDirectory] && isDirectory) {
                NSLog(
                    @"XITFORGE: usando enlace MCM para %@ -> %@",
                    bundleId,
                    linkPath
                );
                return linkPath;
            }
        }
    }

    NSString *reason = nil;
    if (!dataPath) {
        reason = @"MCMFilzaDataContainerPath no está disponible";
    } else if (directDetail.length > 0) {
        reason = directDetail;
    } else if (directPath.length > 0) {
        reason = [NSString stringWithFormat:
            @"el motor devolvió una ruta no accesible: %@",
            directPath];
    } else {
        reason = @"el motor no devolvió una ruta para ese bundleId";
    }

    NSLog(
        @"XITFORGE: contenedor no resuelto para %@: %@",
        bundleId,
        reason
    );

    if (errorOut) *errorOut = reason;
    return nil;
}

static NSURL *XITForgeExistingDirectoryChild(
    NSURL *parent,
    NSString *requestedName,
    NSString **errorOut
) {
    if (errorOut) *errorOut = nil;

    if (!parent || requestedName.length == 0) {
        if (errorOut) *errorOut = @"componente de ruta vacío";
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    /* Primero intentar el nombre exacto. */
    NSURL *exact =
        [parent URLByAppendingPathComponent:requestedName
                               isDirectory:YES];

    struct stat info = {0};
    if (lstat(exact.path.fileSystemRepresentation, &info) == 0) {
        if (S_ISDIR(info.st_mode) && !S_ISLNK(info.st_mode)) {
            return exact;
        }
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:
                @"%@ existe pero no es una carpeta normal",
                exact.path];
        }
        return nil;
    }

    /*
     * Si solo cambia el casing, usar el nombre REAL que existe en el disco.
     * Esto evita rechazar contentcache/ContentCache, etc.
     */
    NSError *listError = nil;
    NSArray<NSString *> *children =
        [fm contentsOfDirectoryAtPath:parent.path error:&listError];

    if (!children) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:
                @"no se pudo leer %@: %@",
                parent.path,
                listError.localizedDescription ?: @"error desconocido"];
        }
        return nil;
    }

    NSString *actualName = nil;
    for (NSString *candidate in children) {
        if ([candidate caseInsensitiveCompare:requestedName] == NSOrderedSame) {
            actualName = candidate;
            break;
        }
    }

    if (!actualName) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:
                @"no existe la carpeta '%@' dentro de %@",
                requestedName,
                parent.path];
        }
        return nil;
    }

    NSURL *resolved =
        [parent URLByAppendingPathComponent:actualName
                               isDirectory:YES];

    memset(&info, 0, sizeof(info));
    if (lstat(resolved.path.fileSystemRepresentation, &info) != 0 ||
        !S_ISDIR(info.st_mode) ||
        S_ISLNK(info.st_mode)) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:
                @"%@ no es una carpeta válida",
                resolved.path];
        }
        return nil;
    }

    return resolved;
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
    (XITForgeOption *)option
    error:(NSString **)errorOut {

    if (errorOut) *errorOut = nil;

    NSString *bundleId =
        option.bundleId.length > 0
            ? option.bundleId
            : self.bundleId;

    NSString *containerError = nil;
    NSString *container =
        XITForgeDataContainerPath(
            bundleId,
            &containerError
        );

    if (container.length == 0) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:
                @"No se pudo abrir el contenedor de %@. %@",
                bundleId ?: @"(sin bundleId)",
                containerError ?: @"Sin detalle del motor."];
        }
        return nil;
    }

    NSString *fileName =
        [self safePathComponent:option.fileName];

    if (fileName.length == 0) {
        if (errorOut) *errorOut = @"El nombre del archivo no es válido.";
        return nil;
    }

    NSString *route =
        [option.route stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (route.length == 0) {
        if (errorOut) *errorOut = @"La ruta configurada está vacía.";
        return nil;
    }

    route =
        [route stringByReplacingOccurrencesOfString:@"\\"
                                         withString:@"/"];

    while ([route hasPrefix:@"/"]) {
        route = [route substringFromIndex:1];
    }

    NSURL *destinationFolder =
        [NSURL fileURLWithPath:container isDirectory:YES];

    NSArray<NSString *> *components =
        [route componentsSeparatedByString:@"/"];

    NSUInteger validIndex = 0;

    for (NSString *rawComponent in components) {
        NSString *component =
            [rawComponent stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (component.length == 0) continue;

        component =
            [self normalizedRouteComponent:component index:validIndex];

        if (![self safePathComponent:component]) {
            if (errorOut) {
                *errorOut = [NSString stringWithFormat:
                    @"La ruta contiene un componente inválido: %@",
                    component];
            }
            return nil;
        }

        NSString *componentError = nil;
        NSURL *next =
            XITForgeExistingDirectoryChild(
                destinationFolder,
                component,
                &componentError
            );

        if (!next) {
            if (errorOut) {
                *errorOut = [NSString stringWithFormat:
                    @"La ruta del panel no existe en el juego. %@",
                    componentError ?: @""];
            }
            return nil;
        }

        destinationFolder = next;
        validIndex++;
    }

    if (validIndex == 0) {
        if (errorOut) *errorOut = @"La ruta no contiene ninguna carpeta válida.";
        return nil;
    }

    NSURL *destinationURL =
        [destinationFolder URLByAppendingPathComponent:fileName
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

    NSString *resolveError = nil;

    NSURL *destinationURL =
        [self destinationURLForOption:
            option
            error:&resolveError];

    if (!destinationURL) {
        [self showResult:
            resolveError ?: @"No se pudo resolver el contenedor o la ruta."
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

    /*
     * IMPORTANTE:
     * Aquí NO se borra ninguna carpeta ni ningún archivo hermano.
     * Solo se crea/sobrescribe destinationURL, que ya incluye:
     *
     *   contenedor + option.route + option.fileName
     */

    NSError *writeError = nil;

    BOOL written =
        XITForgeWriteExactFile(
            location,
            destinationURL,
            &writeError
        );

    if (!written) {

        NSLog(
            @"XITFORGE exact file write error: %@ | destination=%@",
            writeError,
            destinationURL.path
        );

        [self showResult:
            @"No se pudo agregar o reemplazar el archivo."
            success:NO];

        return;
    }

    NSError *verifyError = nil;

    BOOL verified =
        XITForgeFilesAreIdentical(
            location,
            destinationURL,
            &verifyError
        );

    if (!verified) {
        NSLog(
            @"XITFORGE verification failed: %@ | destination=%@",
            verifyError,
            destinationURL.path
        );

        [self showResult:
            @"El archivo se descargó, pero no quedó verificado en la ruta final."
            success:NO];

        return;
    }

    NSLog(
        @"XITFORGE VERIFIED destination=%@",
        destinationURL.path
    );

    [self showResult:
        @"Archivo agregado y verificado correctamente."
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
