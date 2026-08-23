#import "HomeViewController.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>
#import <string.h>


static UIColor *XITForgeAccentColor(void) {
    return [UIColor colorWithRed:0.95
                           green:0.10
                            blue:0.16
                           alpha:1.0];
}

static UIColor *XITForgeAccentDarkColor(void) {
    return [UIColor colorWithRed:0.16
                           green:0.035
                            blue:0.045
                           alpha:1.0];
}


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
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *route;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *fileUrl;
@property (nonatomic, copy) NSString *originalFileUrl;

@end

@implementation XITForgeOption
@end

@interface XITForgeOptionCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIView *radioOuter;
@property (nonatomic, strong) UIView *radioInner;

- (void)configureSelected:(BOOL)selected
                   accent:(UIColor *)accent;

@end

@implementation XITForgeOptionCell

- (instancetype)initWithStyle:
    (UITableViewCellStyle)style
              reuseIdentifier:
    (NSString *)reuseIdentifier {

    self =
        [super initWithStyle:style
             reuseIdentifier:reuseIdentifier];

    if (!self) {
        return nil;
    }

    self.backgroundColor =
        [UIColor clearColor];

    self.selectionStyle =
        UITableViewCellSelectionStyleNone;

    self.contentView.backgroundColor =
        [UIColor clearColor];


    self.cardView =
        [[UIView alloc] init];

    self.cardView.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.cardView.backgroundColor =
        [UIColor colorWithWhite:0.075
                          alpha:1.0];

    self.cardView.layer.cornerRadius =
        20.0;

    self.cardView.layer.borderWidth =
        1.0;

    self.cardView.layer.borderColor =
        [UIColor colorWithWhite:1.0
                          alpha:0.07].CGColor;

    self.cardView.layer.shadowColor =
        [UIColor blackColor].CGColor;

    self.cardView.layer.shadowOpacity =
        0.20;

    self.cardView.layer.shadowRadius =
        12.0;

    self.cardView.layer.shadowOffset =
        CGSizeMake(0.0, 7.0);

    [self.contentView addSubview:
        self.cardView];


    self.nameLabel =
        [[UILabel alloc] init];

    self.nameLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.nameLabel.textColor =
        [UIColor colorWithWhite:0.98
                          alpha:1.0];

    self.nameLabel.font =
        [UIFont systemFontOfSize:17.0
                          weight:UIFontWeightSemibold];

    self.nameLabel.numberOfLines =
        1;

    [self.cardView addSubview:
        self.nameLabel];


    self.descriptionLabel =
        [[UILabel alloc] init];

    self.descriptionLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.descriptionLabel.textColor =
        [UIColor colorWithWhite:0.56
                          alpha:1.0];

    self.descriptionLabel.font =
        [UIFont systemFontOfSize:13.5
                          weight:UIFontWeightRegular];

    self.descriptionLabel.numberOfLines =
        2;

    [self.cardView addSubview:
        self.descriptionLabel];


    self.radioOuter =
        [[UIView alloc] init];

    self.radioOuter.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.radioOuter.userInteractionEnabled =
        NO;

    self.radioOuter.backgroundColor =
        [UIColor colorWithWhite:0.10
                          alpha:1.0];

    self.radioOuter.layer.cornerRadius =
        14.0;

    self.radioOuter.layer.borderWidth =
        1.5;

    [self.cardView addSubview:
        self.radioOuter];


    self.radioInner =
        [[UIView alloc] init];

    self.radioInner.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.radioInner.userInteractionEnabled =
        NO;

    self.radioInner.layer.cornerRadius =
        7.0;

    self.radioInner.alpha =
        0.0;

    [self.radioOuter addSubview:
        self.radioInner];


    [NSLayoutConstraint activateConstraints:@[

        [self.cardView.topAnchor
            constraintEqualToAnchor:
                self.contentView.topAnchor
                constant:6.0],

        [self.cardView.bottomAnchor
            constraintEqualToAnchor:
                self.contentView.bottomAnchor
                constant:-6.0],

        [self.cardView.leadingAnchor
            constraintEqualToAnchor:
                self.contentView.leadingAnchor
                constant:20.0],

        [self.cardView.trailingAnchor
            constraintEqualToAnchor:
                self.contentView.trailingAnchor
                constant:-20.0],


        [self.radioOuter.trailingAnchor
            constraintEqualToAnchor:
                self.cardView.trailingAnchor
                constant:-18.0],

        [self.radioOuter.centerYAnchor
            constraintEqualToAnchor:
                self.cardView.centerYAnchor],

        [self.radioOuter.widthAnchor
            constraintEqualToConstant:28.0],

        [self.radioOuter.heightAnchor
            constraintEqualToConstant:28.0],


        [self.radioInner.centerXAnchor
            constraintEqualToAnchor:
                self.radioOuter.centerXAnchor],

        [self.radioInner.centerYAnchor
            constraintEqualToAnchor:
                self.radioOuter.centerYAnchor],

        [self.radioInner.widthAnchor
            constraintEqualToConstant:14.0],

        [self.radioInner.heightAnchor
            constraintEqualToConstant:14.0],


        [self.nameLabel.topAnchor
            constraintEqualToAnchor:
                self.cardView.topAnchor
                constant:17.0],

        [self.nameLabel.leadingAnchor
            constraintEqualToAnchor:
                self.cardView.leadingAnchor
                constant:18.0],

        [self.nameLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                self.radioOuter.leadingAnchor
                constant:-14.0],


        [self.descriptionLabel.topAnchor
            constraintEqualToAnchor:
                self.nameLabel.bottomAnchor
                constant:6.0],

        [self.descriptionLabel.leadingAnchor
            constraintEqualToAnchor:
                self.nameLabel.leadingAnchor],

        [self.descriptionLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                self.radioOuter.leadingAnchor
                constant:-14.0],

        [self.descriptionLabel.bottomAnchor
            constraintLessThanOrEqualToAnchor:
                self.cardView.bottomAnchor
                constant:-15.0]
    ]];

    return self;
}


- (void)configureSelected:
    (BOOL)selected
                   accent:
    (UIColor *)accent {

    UIColor *normalCard =
        [UIColor colorWithWhite:0.075
                          alpha:1.0];

    UIColor *selectedCard =
        XITForgeAccentDarkColor();

    self.cardView.backgroundColor =
        selected
        ? selectedCard
        : normalCard;

    self.cardView.layer.borderColor =
        (selected
            ? [accent colorWithAlphaComponent:0.62]
            : [UIColor colorWithWhite:1.0
                                alpha:0.07]).CGColor;

    self.radioOuter.layer.borderColor =
        (selected
            ? accent
            : [UIColor colorWithWhite:0.34
                                alpha:1.0]).CGColor;

    self.radioOuter.backgroundColor =
        selected
        ? [accent colorWithAlphaComponent:0.12]
        : [UIColor colorWithWhite:0.10
                            alpha:1.0];

    self.radioInner.backgroundColor =
        accent;

    self.radioInner.alpha =
        selected ? 1.0 : 0.0;

    self.cardView.layer.shadowOpacity =
        selected ? 0.34 : 0.20;

    self.cardView.layer.shadowRadius =
        selected ? 16.0 : 12.0;
}

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
@property (nonatomic, strong) UILabel *selectionHintLabel;

@property (nonatomic, strong) UIView *categoryTabsView;
@property (nonatomic, strong) UIButton *hologramTabButton;
@property (nonatomic, strong) UIButton *aimbotTabButton;
@property (nonatomic, strong) UIButton *fpsTabButton;
@property (nonatomic, copy) NSString *selectedCategory;

@property (nonatomic, strong) NSIndexPath *selectedOptionIndexPath;
@property (nonatomic, strong) NSIndexPath *selectedAimbotIndexPath;
@property (nonatomic, strong) NSIndexPath *selectedHologramIndexPath;
@property (nonatomic, strong) NSIndexPath *selectedFPSIndexPath;

@property (nonatomic, strong) NSArray<XITForgeOption *> *pendingActivationOptions;
@property (nonatomic, strong) NSMutableArray<XITForgeOption *> *activationSucceededOptions;
@property (nonatomic, assign) NSInteger currentActivationIndex;
@property (nonatomic, strong) XITForgeOption *currentActivationOption;

@property (nonatomic, strong) UIButton *activateButton;
@property (nonatomic, strong) UIActivityIndicatorView *activateSpinner;
@property (nonatomic, assign) BOOL activationInProgress;

@property (nonatomic, strong) UIButton *deactivateButton;
@property (nonatomic, assign) BOOL deactivationInProgress;

@property (nonatomic, strong) UIView *aimbotWarningOverlay;

@property (nonatomic, strong) NSMutableSet<NSString *> *activeOptionKeys;
@property (nonatomic, strong) AVAudioPlayer *activationAudioPlayer;

@property (nonatomic, strong) NSURLSession *downloadSession;

@end

@implementation XITForgeOptionsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor =
        [UIColor blackColor];

    [self loadPersistedActiveOptions];
    [self configureNavigationTitle];

    [self setupUI];
    [self loadOptions];
}

#pragma mark - Visual / Activation State

- (NSString *)activeOptionsDefaultsKey {
    NSString *gameKey = self.game.length > 0 ? self.game : @"unknown";
    return [NSString stringWithFormat:@"XITFORGE_ACTIVE_OPTIONS_%@", gameKey];
}

- (NSString *)activationKeyForOption:(XITForgeOption *)option {
    if (option.optionId != nil) {
        return [NSString stringWithFormat:@"id:%@", option.optionId.stringValue];
    }

    NSString *route = option.route ?: @"";
    NSString *fileName = option.fileName ?: @"";
    return [NSString stringWithFormat:@"file:%@|%@", route, fileName];
}

- (void)loadPersistedActiveOptions {
    NSArray *stored =
        [[NSUserDefaults standardUserDefaults]
            arrayForKey:[self activeOptionsDefaultsKey]];

    self.activeOptionKeys =
        [NSMutableSet setWithArray:stored ?: @[]];
}

- (void)persistActiveOptions {
    NSArray *values = self.activeOptionKeys.allObjects ?: @[];
    [[NSUserDefaults standardUserDefaults]
        setObject:values
        forKey:[self activeOptionsDefaultsKey]];
}

- (BOOL)isOptionActivated:(XITForgeOption *)option {
    if (!option) {
        return NO;
    }

    NSString *key = [self activationKeyForOption:option];
    return key.length > 0 && [self.activeOptionKeys containsObject:key];
}

- (void)markOptionActivated:(XITForgeOption *)option {
    if (!option) {
        return;
    }

    NSString *key = [self activationKeyForOption:option];
    if (key.length == 0) {
        return;
    }

    [self.activeOptionKeys addObject:key];
    [self persistActiveOptions];
}

- (void)clearActivatedOptions {
    [self.activeOptionKeys removeAllObjects];
    [self persistActiveOptions];
}

- (void)configureNavigationTitle {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text =
        [self.game isEqualToString:@"freefire_max"]
            ? @"FREE FIRE MAX"
            : @"FREE FIRE NORMAL";
    titleLabel.textColor = XITForgeAccentColor();
    titleLabel.font =
        [UIFont systemFontOfSize:17.0
                          weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleLabel sizeToFit];

    self.navigationItem.titleView = titleLabel;
    self.title = @"";
}

- (NSArray<XITForgeOption *> *)optionsForCategory:(NSString *)categoryName {
    NSString *normalized =
        categoryName.lowercaseString ?: @"";

    NSString *wantedCategory = @"holograma";

    if ([normalized isEqualToString:@"aimbot"]) {
        wantedCategory = @"aimbot";
    } else if ([normalized isEqualToString:@"fps"]) {
        wantedCategory = @"fps";
    }

    NSMutableArray<XITForgeOption *> *items =
        [NSMutableArray array];

    for (XITForgeOption *option in self.options) {
        NSString *category =
            option.category.lowercaseString ?: @"holograma";

        if ([category isEqualToString:wantedCategory]) {
            [items addObject:option];
        }
    }

    return [items copy];
}

- (NSArray<XITForgeOption *> *)optionsForSection:(NSInteger)section {
    (void)section;

    NSString *wantedCategory =
        self.selectedCategory.length > 0
            ? self.selectedCategory.lowercaseString
            : @"aimbot";

    return [self optionsForCategory:wantedCategory];
}

- (XITForgeOption *)optionAtIndexPath:(NSIndexPath *)indexPath
                         forCategory:(NSString *)category {
    if (!indexPath || indexPath.section != 0) {
        return nil;
    }

    NSArray<XITForgeOption *> *items =
        [self optionsForCategory:category];

    if (indexPath.row < 0 || indexPath.row >= items.count) {
        return nil;
    }

    return items[indexPath.row];
}

- (XITForgeOption *)optionAtIndexPath:(NSIndexPath *)indexPath {
    return [self optionAtIndexPath:indexPath
                      forCategory:self.selectedCategory ?: @"aimbot"];
}

- (NSArray<XITForgeOption *> *)selectedOptions {
    NSMutableArray<XITForgeOption *> *selected =
        [NSMutableArray arrayWithCapacity:3];

    XITForgeOption *aimbot =
        [self optionAtIndexPath:self.selectedAimbotIndexPath
                   forCategory:@"aimbot"];

    XITForgeOption *hologram =
        [self optionAtIndexPath:self.selectedHologramIndexPath
                   forCategory:@"holograma"];

    XITForgeOption *fps =
        [self optionAtIndexPath:self.selectedFPSIndexPath
                   forCategory:@"fps"];

    /*
     * Se puede elegir una opción por categoría y ACTIVAR
     * aplica todas las seleccionadas en el mismo proceso.
     */
    if (aimbot) {
        [selected addObject:aimbot];
    }

    if (hologram) {
        [selected addObject:hologram];
    }

    if (fps) {
        [selected addObject:fps];
    }

    return [selected copy];
}

- (NSString *)selectionHintText {
    NSInteger count =
        [self selectedOptions].count;

    if (count > 1) {
        return [NSString stringWithFormat:
            @"%ld OPCIONES SELECCIONADAS",
            (long)count];
    }

    return @"SELECCIONA UNA OPCIÓN";
}

- (void)updateCategoryTabAppearance {
    BOOL aimbotSelected =
        [self.selectedCategory isEqualToString:@"aimbot"];

    BOOL hologramSelected =
        [self.selectedCategory isEqualToString:@"holograma"];

    BOOL fpsSelected =
        [self.selectedCategory isEqualToString:@"fps"];

    UIColor *accent = XITForgeAccentColor();
    UIColor *inactive =
        [UIColor colorWithWhite:0.085 alpha:1.0];
    UIColor *inactiveBorder =
        [UIColor colorWithWhite:1.0 alpha:0.08];

    self.aimbotTabButton.backgroundColor =
        aimbotSelected ? accent : inactive;

    self.hologramTabButton.backgroundColor =
        hologramSelected ? accent : inactive;

    self.fpsTabButton.backgroundColor =
        fpsSelected ? accent : inactive;

    self.aimbotTabButton.layer.borderColor =
        (aimbotSelected
            ? [accent colorWithAlphaComponent:0.95]
            : inactiveBorder).CGColor;

    self.hologramTabButton.layer.borderColor =
        (hologramSelected
            ? [accent colorWithAlphaComponent:0.95]
            : inactiveBorder).CGColor;

    self.fpsTabButton.layer.borderColor =
        (fpsSelected
            ? [accent colorWithAlphaComponent:0.95]
            : inactiveBorder).CGColor;

    self.aimbotTabButton.alpha =
        aimbotSelected ? 1.0 : 0.72;

    self.hologramTabButton.alpha =
        hologramSelected ? 1.0 : 0.72;

    self.fpsTabButton.alpha =
        fpsSelected ? 1.0 : 0.72;
}

- (void)switchToCategory:(NSString *)category {
    NSString *lower =
        category.lowercaseString ?: @"";

    NSString *normalized = @"holograma";

    if ([lower isEqualToString:@"aimbot"]) {
        normalized = @"aimbot";
    } else if ([lower isEqualToString:@"fps"]) {
        normalized = @"fps";
    }

    if ([self.selectedCategory isEqualToString:normalized]) {
        return;
    }

    self.selectedCategory = normalized;

    /*
     * Conserva la selección de las otras pestañas.
     * Así se puede elegir AIMBOT + HOLOGRAMA + FPS.
     */
    if ([normalized isEqualToString:@"aimbot"]) {
        self.selectedOptionIndexPath =
            self.selectedAimbotIndexPath;
    } else if ([normalized isEqualToString:@"fps"]) {
        self.selectedOptionIndexPath =
            self.selectedFPSIndexPath;
    } else {
        self.selectedOptionIndexPath =
            self.selectedHologramIndexPath;
    }

    self.selectionHintLabel.text =
        [self selectionHintText];

    self.selectionHintLabel.textColor =
        [UIColor colorWithWhite:0.48 alpha:1.0];

    [self updateCategoryTabAppearance];
    [self updateActivateButtonForCurrentSelection];
    [self.tableView reloadData];

    if (!self.activityIndicator.isAnimating) {
        BOOL hasItems =
            [self optionsForSection:0].count > 0;

        self.statusLabel.text =
            hasItems
                ? @""
                : @"No hay opciones en esta categoría.";

        self.statusLabel.hidden = hasItems;
    }

    UISelectionFeedbackGenerator *feedback =
        [[UISelectionFeedbackGenerator alloc] init];
    [feedback selectionChanged];
}

- (void)hologramTabTapped {
    [self switchToCategory:@"holograma"];
}

- (void)aimbotTabTapped {
    [self switchToCategory:@"aimbot"];
}

- (void)fpsTabTapped {
    [self switchToCategory:@"fps"];
}

- (void)updateActivateButtonForCurrentSelection {
    if (!self.activateButton) {
        return;
    }

    NSArray<XITForgeOption *> *selected =
        [self selectedOptions];

    BOOL hasSelection =
        selected.count > 0;

    NSInteger pendingCount = 0;

    for (XITForgeOption *option in selected) {
        if (![self isOptionActivated:option]) {
            pendingCount++;
        }
    }

    BOOL allSelectedAlreadyActive =
        hasSelection && pendingCount == 0;

    UIColor *accent = XITForgeAccentColor();

    if (!hasSelection) {
        [self.activateButton setTitle:@"ACTIVAR" forState:UIControlStateNormal];
        self.activateButton.enabled = NO;
        self.activateButton.alpha = 0.48;
        self.activateButton.backgroundColor =
            [UIColor colorWithWhite:0.105 alpha:1.0];
        self.activateButton.layer.borderColor =
            [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
        self.activateButton.layer.shadowOpacity = 0.0;
        return;
    }

    if (allSelectedAlreadyActive) {
        [self.activateButton setTitle:@"ACTIVADO" forState:UIControlStateNormal];
        self.activateButton.enabled = NO;
        self.activateButton.alpha = 0.78;
        self.activateButton.backgroundColor = XITForgeAccentDarkColor();
        self.activateButton.layer.borderColor =
            [accent colorWithAlphaComponent:0.45].CGColor;
        self.activateButton.layer.shadowColor = accent.CGColor;
        self.activateButton.layer.shadowOpacity = 0.08;
        return;
    }

    [self.activateButton setTitle:@"ACTIVAR" forState:UIControlStateNormal];
    self.activateButton.enabled = YES;
    self.activateButton.alpha = 1.0;
    self.activateButton.backgroundColor = accent;
    self.activateButton.layer.borderColor =
        [accent colorWithAlphaComponent:0.90].CGColor;
    self.activateButton.layer.shadowColor = accent.CGColor;
    self.activateButton.layer.shadowOpacity = 0.22;
}

- (void)playActivationAudio {
    NSUserDefaults *defaults =
        [NSUserDefaults standardUserDefaults];

    id savedPreference =
        [defaults objectForKey:@"xitforgeActivationVoiceEnabled"];

    /*
     * Sin preferencia guardada = activada por defecto.
     * Si el usuario la apaga desde Ajustes, no reproducimos nada.
     */
    if (savedPreference != nil &&
        ![defaults boolForKey:@"xitforgeActivationVoiceEnabled"]) {
        return;
    }

    NSURL *soundURL =
        [[NSBundle mainBundle]
            URLForResource:@"xitforge_activar"
            withExtension:@"m4a"];

    if (!soundURL) {
        return;
    }

    NSError *audioError = nil;
    self.activationAudioPlayer =
        [[AVAudioPlayer alloc]
            initWithContentsOfURL:soundURL
            error:&audioError];

    if (!self.activationAudioPlayer || audioError) {
        return;
    }

    self.activationAudioPlayer.volume = 1.0;
    [self.activationAudioPlayer prepareToPlay];
    [self.activationAudioPlayer play];
}

- (void)showActivationBannerForOptions:(NSArray<XITForgeOption *> *)options {
    UIView *host = self.navigationController.view ?: self.view;
    if (!host) {
        return;
    }

    UIView *banner = [[UIView alloc] init];
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    banner.backgroundColor =
        [UIColor colorWithWhite:0.055 alpha:0.98];
    banner.layer.cornerRadius = 18.0;
    banner.layer.borderWidth = 1.0;
    banner.layer.borderColor =
        [XITForgeAccentColor() colorWithAlphaComponent:0.72].CGColor;
    banner.layer.shadowColor = [UIColor blackColor].CGColor;
    banner.layer.shadowOpacity = 0.35;
    banner.layer.shadowRadius = 18.0;
    banner.layer.shadowOffset = CGSizeMake(0.0, 8.0);

    UIView *accentBar = [[UIView alloc] init];
    accentBar.translatesAutoresizingMaskIntoConstraints = NO;
    accentBar.backgroundColor = XITForgeAccentColor();
    accentBar.layer.cornerRadius = 2.0;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text =
        options.count > 1
            ? @"OPCIONES ACTIVADAS"
            : @"OPCIÓN ACTIVADA";
    title.textColor = [UIColor whiteColor];
    title.font =
        [UIFont systemFontOfSize:13.0
                          weight:UIFontWeightBold];

    UILabel *detail = [[UILabel alloc] init];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (XITForgeOption *option in options) {
        if (option.name.length > 0) {
            [names addObject:option.name];
        }
    }
    detail.text =
        names.count > 0
            ? [names componentsJoinedByString:@" + "]
            : @"XITFORGE";
    detail.textColor =
        [UIColor colorWithWhite:0.70 alpha:1.0];
    detail.font =
        [UIFont systemFontOfSize:12.0
                          weight:UIFontWeightMedium];

    [banner addSubview:accentBar];
    [banner addSubview:title];
    [banner addSubview:detail];
    [host addSubview:banner];

    [NSLayoutConstraint activateConstraints:@[
        [banner.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:14.0],
        [banner.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-14.0],
        [banner.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:8.0],
        [banner.heightAnchor constraintGreaterThanOrEqualToConstant:70.0],

        [accentBar.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:14.0],
        [accentBar.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [accentBar.widthAnchor constraintEqualToConstant:4.0],
        [accentBar.heightAnchor constraintEqualToConstant:34.0],

        [title.leadingAnchor constraintEqualToAnchor:accentBar.trailingAnchor constant:12.0],
        [title.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-16.0],
        [title.topAnchor constraintEqualToAnchor:banner.topAnchor constant:14.0],

        [detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [detail.bottomAnchor constraintLessThanOrEqualToAnchor:banner.bottomAnchor constant:-12.0]
    ]];

    [host layoutIfNeeded];
    banner.transform = CGAffineTransformMakeTranslation(0.0, -100.0);
    banner.alpha = 0.0;

    [UIView animateWithDuration:0.30
                          delay:0.0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        banner.transform = CGAffineTransformIdentity;
        banner.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.24
                              delay:1.65
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            banner.transform = CGAffineTransformMakeTranslation(0.0, -100.0);
            banner.alpha = 0.0;
        } completion:^(BOOL finishedOut) {
            [banner removeFromSuperview];
        }];
    }];
}

- (void)dismissAimbotWarning {

    UIView *overlay =
        self.aimbotWarningOverlay;

    if (!overlay) {
        return;
    }

    UIView *card =
        [overlay viewWithTag:9917];

    [UIView
        animateWithDuration:0.20
        animations:^{

            overlay.alpha = 0.0;

            if (card) {
                card.transform =
                    CGAffineTransformMakeScale(
                        0.97,
                        0.97
                    );
            }

        }
        completion:^(BOOL finished) {

            [overlay removeFromSuperview];

            if (self.aimbotWarningOverlay == overlay) {
                self.aimbotWarningOverlay = nil;
            }
        }];
}


- (void)showAimbotWarning {

    UIView *host =
        self.navigationController.view ?: self.view;

    if (!host) {
        return;
    }

    if (self.aimbotWarningOverlay) {
        [self.aimbotWarningOverlay removeFromSuperview];
        self.aimbotWarningOverlay = nil;
    }

    UIView *overlay =
        [[UIView alloc] init];

    overlay.translatesAutoresizingMaskIntoConstraints =
        NO;

    overlay.backgroundColor =
        [UIColor colorWithWhite:0.0
                          alpha:0.72];

    self.aimbotWarningOverlay =
        overlay;


    UIView *card =
        [[UIView alloc] init];

    card.tag = 9917;

    card.translatesAutoresizingMaskIntoConstraints =
        NO;

    card.backgroundColor =
        [UIColor colorWithWhite:0.055
                          alpha:1.0];

    card.layer.cornerRadius =
        24.0;

    card.layer.borderWidth =
        1.0;

    card.layer.borderColor =
        [UIColor colorWithWhite:1.0
                          alpha:0.10].CGColor;

    card.layer.shadowColor =
        [UIColor blackColor].CGColor;

    card.layer.shadowOpacity =
        0.50;

    card.layer.shadowRadius =
        24.0;

    card.layer.shadowOffset =
        CGSizeMake(0.0, 12.0);


    UILabel *warningIcon =
        [[UILabel alloc] init];

    warningIcon.translatesAutoresizingMaskIntoConstraints =
        NO;

    warningIcon.text =
        @"⚠️";

    warningIcon.textAlignment =
        NSTextAlignmentCenter;

    warningIcon.font =
        [UIFont systemFontOfSize:38.0
                          weight:UIFontWeightRegular];


    UILabel *title =
        [[UILabel alloc] init];

    title.translatesAutoresizingMaskIntoConstraints =
        NO;

    title.text =
        @"ADVERTENCIA PARA EL AIMBOT";

    title.textAlignment =
        NSTextAlignmentCenter;

    title.textColor =
        [UIColor whiteColor];

    title.font =
        [UIFont systemFontOfSize:17.0
                          weight:UIFontWeightBold];

    title.numberOfLines =
        0;


    UIView *messageBox =
        [[UIView alloc] init];

    messageBox.translatesAutoresizingMaskIntoConstraints =
        NO;

    messageBox.backgroundColor =
        [UIColor colorWithWhite:0.085
                          alpha:1.0];

    messageBox.layer.cornerRadius =
        14.0;

    messageBox.layer.borderWidth =
        1.0;

    messageBox.layer.borderColor =
        [UIColor colorWithWhite:1.0
                          alpha:0.07].CGColor;


    UILabel *message =
        [[UILabel alloc] init];

    message.translatesAutoresizingMaskIntoConstraints =
        NO;

    message.text =
        @"ANTES DE ENTRAR A LA CUENTA DARLE A DESACTIVAR";

    message.textAlignment =
        NSTextAlignmentCenter;

    message.textColor =
        [UIColor colorWithWhite:0.80
                          alpha:1.0];

    message.font =
        [UIFont systemFontOfSize:14.0
                          weight:UIFontWeightMedium];

    message.numberOfLines =
        0;


    UIButton *understoodButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    understoodButton.translatesAutoresizingMaskIntoConstraints =
        NO;

    [understoodButton
        setTitle:@"ENTENDIDO"
        forState:UIControlStateNormal];

    [understoodButton
        setTitleColor:[UIColor whiteColor]
        forState:UIControlStateNormal];

    understoodButton.titleLabel.font =
        [UIFont systemFontOfSize:15.0
                          weight:UIFontWeightBold];

    understoodButton.backgroundColor =
        XITForgeAccentColor();

    understoodButton.layer.cornerRadius =
        14.0;

    understoodButton.layer.shadowColor =
        XITForgeAccentColor().CGColor;

    understoodButton.layer.shadowOpacity =
        0.20;

    understoodButton.layer.shadowRadius =
        10.0;

    understoodButton.layer.shadowOffset =
        CGSizeMake(0.0, 5.0);

    [understoodButton
        addTarget:self
        action:@selector(dismissAimbotWarning)
        forControlEvents:UIControlEventTouchUpInside];


    [host addSubview:overlay];
    [overlay addSubview:card];

    [card addSubview:warningIcon];
    [card addSubview:title];
    [card addSubview:messageBox];
    [messageBox addSubview:message];
    [card addSubview:understoodButton];


    [NSLayoutConstraint activateConstraints:@[

        [overlay.leadingAnchor
            constraintEqualToAnchor:
                host.leadingAnchor],

        [overlay.trailingAnchor
            constraintEqualToAnchor:
                host.trailingAnchor],

        [overlay.topAnchor
            constraintEqualToAnchor:
                host.topAnchor],

        [overlay.bottomAnchor
            constraintEqualToAnchor:
                host.bottomAnchor],


        [card.centerXAnchor
            constraintEqualToAnchor:
                overlay.centerXAnchor],

        [card.centerYAnchor
            constraintEqualToAnchor:
                overlay.centerYAnchor
                constant:-8.0],

        [card.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                overlay.leadingAnchor
                constant:24.0],

        [card.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                overlay.trailingAnchor
                constant:-24.0],

        [card.widthAnchor
            constraintLessThanOrEqualToConstant:
                360.0],


        [warningIcon.topAnchor
            constraintEqualToAnchor:
                card.topAnchor
                constant:24.0],

        [warningIcon.centerXAnchor
            constraintEqualToAnchor:
                card.centerXAnchor],


        [title.topAnchor
            constraintEqualToAnchor:
                warningIcon.bottomAnchor
                constant:12.0],

        [title.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:22.0],

        [title.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-22.0],


        [messageBox.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:20.0],

        [messageBox.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-20.0],

        [messageBox.topAnchor
            constraintEqualToAnchor:
                title.bottomAnchor
                constant:18.0],


        [message.leadingAnchor
            constraintEqualToAnchor:
                messageBox.leadingAnchor
                constant:18.0],

        [message.trailingAnchor
            constraintEqualToAnchor:
                messageBox.trailingAnchor
                constant:-18.0],

        [message.topAnchor
            constraintEqualToAnchor:
                messageBox.topAnchor
                constant:16.0],

        [message.bottomAnchor
            constraintEqualToAnchor:
                messageBox.bottomAnchor
                constant:-16.0],


        [understoodButton.leadingAnchor
            constraintEqualToAnchor:
                card.leadingAnchor
                constant:20.0],

        [understoodButton.trailingAnchor
            constraintEqualToAnchor:
                card.trailingAnchor
                constant:-20.0],

        [understoodButton.topAnchor
            constraintEqualToAnchor:
                messageBox.bottomAnchor
                constant:18.0],

        [understoodButton.heightAnchor
            constraintEqualToConstant:
                50.0],

        [understoodButton.bottomAnchor
            constraintEqualToAnchor:
                card.bottomAnchor
                constant:-20.0]
    ]];


    [host layoutIfNeeded];

    overlay.alpha =
        0.0;

    card.transform =
        CGAffineTransformMakeScale(
            0.94,
            0.94
        );


    [UIView
        animateWithDuration:0.28
        delay:0.0
        usingSpringWithDamping:0.86
        initialSpringVelocity:0.45
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{

            overlay.alpha = 1.0;
            card.transform =
                CGAffineTransformIdentity;
        }
        completion:nil];


    UINotificationFeedbackGenerator *feedback =
        [[UINotificationFeedbackGenerator alloc] init];

    [feedback
        notificationOccurred:
            UINotificationFeedbackTypeWarning];
}


#pragma mark - UI

- (void)setupUI {

    UIColor *background =
        [UIColor colorWithRed:0.018
                        green:0.018
                         blue:0.025
                        alpha:1.0];

    UIColor *accent = XITForgeAccentColor();

    self.view.backgroundColor =
        background;

    self.selectedOptionIndexPath =
        nil;

    self.selectedAimbotIndexPath =
        nil;

    self.selectedHologramIndexPath =
        nil;

    self.selectedFPSIndexPath =
        nil;

    self.selectedCategory =
        @"aimbot";


    self.categoryTabsView =
        [[UIView alloc] init];

    self.categoryTabsView.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.categoryTabsView.backgroundColor =
        [UIColor colorWithWhite:0.055 alpha:1.0];

    self.categoryTabsView.layer.cornerRadius =
        18.0;

    self.categoryTabsView.layer.borderWidth =
        1.0;

    self.categoryTabsView.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;

    [self.view addSubview:self.categoryTabsView];


    self.hologramTabButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.hologramTabButton.translatesAutoresizingMaskIntoConstraints =
        NO;

    [self.hologramTabButton
        setTitle:@"HOLOGRAMAS"
        forState:UIControlStateNormal];

    [self.hologramTabButton
        setTitleColor:[UIColor whiteColor]
        forState:UIControlStateNormal];

    self.hologramTabButton.titleLabel.font =
        [UIFont systemFontOfSize:13.0
                          weight:UIFontWeightBold];

    self.hologramTabButton.layer.cornerRadius =
        15.0;

    self.hologramTabButton.layer.borderWidth =
        1.0;

    [self.hologramTabButton
        addTarget:self
        action:@selector(hologramTabTapped)
        forControlEvents:UIControlEventTouchUpInside];

    [self.categoryTabsView addSubview:self.hologramTabButton];


    self.aimbotTabButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.aimbotTabButton.translatesAutoresizingMaskIntoConstraints =
        NO;

    [self.aimbotTabButton
        setTitle:@"AIMBOTS"
        forState:UIControlStateNormal];

    [self.aimbotTabButton
        setTitleColor:[UIColor whiteColor]
        forState:UIControlStateNormal];

    self.aimbotTabButton.titleLabel.font =
        [UIFont systemFontOfSize:13.0
                          weight:UIFontWeightBold];

    self.aimbotTabButton.layer.cornerRadius =
        15.0;

    self.aimbotTabButton.layer.borderWidth =
        1.0;

    [self.aimbotTabButton
        addTarget:self
        action:@selector(aimbotTabTapped)
        forControlEvents:UIControlEventTouchUpInside];

    [self.categoryTabsView addSubview:self.aimbotTabButton];


    self.fpsTabButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.fpsTabButton.translatesAutoresizingMaskIntoConstraints =
        NO;

    [self.fpsTabButton
        setTitle:@"FPS"
        forState:UIControlStateNormal];

    [self.fpsTabButton
        setTitleColor:[UIColor whiteColor]
        forState:UIControlStateNormal];

    self.fpsTabButton.titleLabel.font =
        [UIFont systemFontOfSize:13.0
                          weight:UIFontWeightBold];

    self.fpsTabButton.layer.cornerRadius =
        15.0;

    self.fpsTabButton.layer.borderWidth =
        1.0;

    [self.fpsTabButton
        addTarget:self
        action:@selector(fpsTabTapped)
        forControlEvents:UIControlEventTouchUpInside];

    [self.categoryTabsView addSubview:self.fpsTabButton];

    [self updateCategoryTabAppearance];


    self.selectionHintLabel =
        [[UILabel alloc] init];

    self.selectionHintLabel.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.selectionHintLabel.text =
        @"SELECCIONA UNA OPCIÓN";

    self.selectionHintLabel.textColor =
        [UIColor colorWithWhite:0.48
                          alpha:1.0];

    self.selectionHintLabel.font =
        [UIFont systemFontOfSize:11.0
                          weight:UIFontWeightSemibold];

    self.selectionHintLabel.textAlignment =
        NSTextAlignmentLeft;

    [self.view addSubview:
        self.selectionHintLabel];


    self.tableView =
        [[UITableView alloc]
            initWithFrame:CGRectZero
                    style:UITableViewStylePlain];

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

    self.tableView.showsVerticalScrollIndicator =
        NO;

    self.tableView.estimatedRowHeight =
        94.0;

    self.tableView.contentInset =
        UIEdgeInsetsMake(2.0, 0.0, 12.0, 0.0);

    [self.view addSubview:
        self.tableView];


    self.activateButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.activateButton.translatesAutoresizingMaskIntoConstraints =
        NO;

    [self.activateButton
        setTitle:@"ACTIVAR"
        forState:UIControlStateNormal];

    [self.activateButton
        setTitleColor:[UIColor whiteColor]
        forState:UIControlStateNormal];

    self.activateButton.titleLabel.font =
        [UIFont systemFontOfSize:16.0
                          weight:UIFontWeightBold];

    self.activateButton.backgroundColor =
        [UIColor colorWithWhite:0.105
                          alpha:1.0];

    self.activateButton.layer.cornerRadius =
        19.0;

    self.activateButton.layer.borderWidth =
        1.0;

    self.activateButton.layer.borderColor =
        [UIColor colorWithWhite:1.0
                          alpha:0.08].CGColor;

    self.activateButton.layer.shadowColor =
        [UIColor blackColor].CGColor;

    self.activateButton.layer.shadowOpacity =
        0.26;

    self.activateButton.layer.shadowRadius =
        14.0;

    self.activateButton.layer.shadowOffset =
        CGSizeMake(0.0, 8.0);

    self.activateButton.enabled =
        NO;

    self.activateButton.alpha =
        0.48;

    [self.activateButton
        addTarget:self
        action:@selector(activateSelectedOption)
        forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:
        self.activateButton];


    /*
     * Indicador del botón ACTIVAR conservado por compatibilidad,
     * pero se mantiene detenido y oculto. Durante la aplicación
     * el usuario solo ve el texto "ACTIVANDO...".
     */
    self.activateSpinner =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleMedium];

    self.activateSpinner.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.activateSpinner.color =
        [UIColor whiteColor];

    self.activateSpinner.hidesWhenStopped =
        YES;

    [self.activateButton addSubview:
        self.activateSpinner];


    /*
     * DESACTIVAR restaura desde el servidor todos los archivos
     * originales configurados para el juego actual.
     */
    self.deactivateButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.deactivateButton.translatesAutoresizingMaskIntoConstraints =
        NO;

    [self.deactivateButton
        setTitle:@"DESACTIVAR"
        forState:UIControlStateNormal];

    [self.deactivateButton
        setTitleColor:XITForgeAccentColor()
        forState:UIControlStateNormal];

    self.deactivateButton.titleLabel.font =
        [UIFont systemFontOfSize:14.0
                          weight:UIFontWeightBold];

    self.deactivateButton.backgroundColor =
        [UIColor colorWithWhite:0.075
                          alpha:1.0];

    self.deactivateButton.layer.cornerRadius =
        17.0;

    self.deactivateButton.layer.borderWidth =
        1.0;

    self.deactivateButton.layer.borderColor =
        [XITForgeAccentColor() colorWithAlphaComponent:0.34].CGColor;

    [self.deactivateButton
        addTarget:self
        action:@selector(deactivateAllOptions)
        forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:
        self.deactivateButton];


    self.activityIndicator =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleLarge];

    self.activityIndicator.translatesAutoresizingMaskIntoConstraints =
        NO;

    self.activityIndicator.color =
        accent;

    [self.view addSubview:self.activityIndicator];


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

    [self.view addSubview:self.statusLabel];


    [NSLayoutConstraint activateConstraints:@[

        [self.categoryTabsView.topAnchor
            constraintEqualToAnchor:
                self.view.safeAreaLayoutGuide.topAnchor
                constant:12.0],

        [self.categoryTabsView.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor
                constant:20.0],

        [self.categoryTabsView.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor
                constant:-20.0],

        [self.categoryTabsView.heightAnchor
            constraintEqualToConstant:52.0],

        [self.aimbotTabButton.leadingAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.leadingAnchor
                constant:4.0],

        [self.aimbotTabButton.topAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.topAnchor
                constant:4.0],

        [self.aimbotTabButton.bottomAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.bottomAnchor
                constant:-4.0],

        [self.hologramTabButton.leadingAnchor
            constraintEqualToAnchor:
                self.aimbotTabButton.trailingAnchor
                constant:4.0],

        [self.hologramTabButton.topAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.topAnchor
                constant:4.0],

        [self.hologramTabButton.bottomAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.bottomAnchor
                constant:-4.0],

        [self.fpsTabButton.leadingAnchor
            constraintEqualToAnchor:
                self.hologramTabButton.trailingAnchor
                constant:4.0],

        [self.fpsTabButton.trailingAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.trailingAnchor
                constant:-4.0],

        [self.fpsTabButton.topAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.topAnchor
                constant:4.0],

        [self.fpsTabButton.bottomAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.bottomAnchor
                constant:-4.0],

        [self.aimbotTabButton.widthAnchor
            constraintEqualToAnchor:
                self.hologramTabButton.widthAnchor],

        [self.hologramTabButton.widthAnchor
            constraintEqualToAnchor:
                self.fpsTabButton.widthAnchor],


        [self.selectionHintLabel.topAnchor
            constraintEqualToAnchor:
                self.categoryTabsView.bottomAnchor
                constant:14.0],

        [self.selectionHintLabel.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor
                constant:24.0],

        [self.selectionHintLabel.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor
                constant:-24.0],


        [self.activateButton.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor
                constant:22.0],

        [self.activateButton.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor
                constant:-22.0],

        [self.activateButton.bottomAnchor
            constraintEqualToAnchor:
                self.deactivateButton.topAnchor
                constant:-10.0],

        [self.activateButton.heightAnchor
            constraintEqualToConstant:58.0],

        [self.activateSpinner.centerYAnchor
            constraintEqualToAnchor:
                self.activateButton.centerYAnchor],

        [self.activateSpinner.trailingAnchor
            constraintEqualToAnchor:
                self.activateButton.centerXAnchor
                constant:-54.0],


        [self.deactivateButton.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor
                constant:22.0],

        [self.deactivateButton.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor
                constant:-22.0],

        [self.deactivateButton.bottomAnchor
            constraintEqualToAnchor:
                self.view.safeAreaLayoutGuide.bottomAnchor
                constant:-14.0],

        [self.deactivateButton.heightAnchor
            constraintEqualToConstant:50.0],

        [self.tableView.topAnchor
            constraintEqualToAnchor:
                self.selectionHintLabel.bottomAnchor
                constant:10.0],

        [self.tableView.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor],

        [self.tableView.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor],

        [self.tableView.bottomAnchor
            constraintEqualToAnchor:
                self.activateButton.topAnchor
                constant:-12.0],


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

- (NSURL *)absoluteServerURLForString:
    (NSString *)value {

    NSString *trimmed =
        [value stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (trimmed.length == 0) {
        return nil;
    }

    NSURL *direct =
        [NSURL URLWithString:trimmed];

    if (direct.scheme.length > 0) {

        /*
         * Si el backend construyó una URL absoluta usando localhost
         * (por ejemplo PUBLIC_BASE_URL=http://localhost:3000), esa URL
         * no sirve dentro del iPhone. Conservamos la ruta y la apuntamos
         * al servidor público de XITFORGE.
         */
        NSString *host =
            direct.host.lowercaseString;

        BOOL localHost =
            [host isEqualToString:@"localhost"] ||
            [host isEqualToString:@"127.0.0.1"] ||
            [host isEqualToString:@"0.0.0.0"];

        if (!localHost) {
            return direct;
        }

        NSString *relative =
            direct.path.length > 0
                ? direct.path
                : @"/";

        if (direct.query.length > 0) {
            relative =
                [relative stringByAppendingFormat:
                    @"?%@",
                    direct.query];
        }

        trimmed = relative;
    }

    NSString *base =
        [self apiBaseURL];

    NSString *absolute =
        [trimmed hasPrefix:@"/"]
            ? [NSString stringWithFormat:@"%@%@", base, trimmed]
            : [NSString stringWithFormat:@"%@/%@", base, trimmed];

    return [NSURL URLWithString:absolute];
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
                        [raw[@"category"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.category =
                            [raw[@"category"] lowercaseString];
                    } else {
                        NSString *lowerName =
                            option.name.lowercaseString ?: @"";

                        if ([lowerName containsString:@"aimbot"]) {
                            option.category = @"aimbot";
                        } else if ([lowerName containsString:@"fps"]) {
                            option.category = @"fps";
                        } else {
                            option.category = @"holograma";
                        }
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

                    if (
                        [raw[@"originalFileUrl"] isKindOfClass:
                            [NSString class]]
                    ) {
                        option.originalFileUrl =
                            raw[@"originalFileUrl"];
                    }

                    [parsed addObject:
                        option];
                }

                self.options =
                    [parsed copy];

                self.selectedOptionIndexPath =
                    nil;

                self.selectedAimbotIndexPath =
                    nil;

                self.selectedHologramIndexPath =
                    nil;

                self.selectedFPSIndexPath =
                    nil;

                self.activationInProgress =
                    NO;

                [self.activateSpinner
                    stopAnimating];

                [self.activateButton
                    setTitle:@"ACTIVAR"
                    forState:UIControlStateNormal];

                self.activateButton.enabled =
                    NO;

                self.activateButton.alpha =
                    0.45;

                self.deactivationInProgress =
                    NO;

                [self.deactivateButton
                    setTitle:@"DESACTIVAR"
                    forState:UIControlStateNormal];

                self.deactivateButton.enabled =
                    YES;

                self.deactivateButton.alpha =
                    1.0;

                [self.tableView
                    reloadData];

                if (self.options.count == 0) {

                    self.statusLabel.text =
                        @"No hay opciones disponibles.";

                    self.statusLabel.hidden =
                        NO;

                } else if ([self optionsForSection:0].count == 0) {

                    self.statusLabel.text =
                        @"No hay opciones en esta categoría.";

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

- (NSInteger)numberOfSectionsInTableView:
    (UITableView *)tableView {

    return 1;
}

- (NSInteger)tableView:
    (UITableView *)tableView
 numberOfRowsInSection:
    (NSInteger)section {

    return [self optionsForSection:0].count;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
 cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    static NSString *identifier =
        @"XITForgeProfessionalOptionCell";

    XITForgeOptionCell *cell =
        (XITForgeOptionCell *)
        [tableView
            dequeueReusableCellWithIdentifier:
                identifier];

    if (!cell) {

        cell =
            [[XITForgeOptionCell alloc]
                initWithStyle:
                    UITableViewCellStyleDefault
                reuseIdentifier:
                    identifier];
    }

    XITForgeOption *option =
        [self optionAtIndexPath:indexPath];

    if (!option) {
        return cell;
    }

    BOOL selected =
        self.selectedOptionIndexPath &&
        [self.selectedOptionIndexPath
            isEqual:indexPath];

    cell.nameLabel.text =
        option.name ?: @"Opción";

    cell.descriptionLabel.text =
        option.optionDescription ?: @"";

    UIColor *accent = XITForgeAccentColor();

    [cell
        configureSelected:selected
                   accent:accent];

    return cell;
}


- (CGFloat)tableView:
    (UITableView *)tableView
heightForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    return 94.0;
}

#pragma mark - Option Selection

- (void)tableView:
    (UITableView *)tableView
 didSelectRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (![self optionAtIndexPath:indexPath]) {
        return;
    }

    NSIndexPath *previous =
        self.selectedOptionIndexPath;

    BOOL tappedSelectedOption =
        previous &&
        [previous isEqual:indexPath];

    if (tappedSelectedOption) {

        /*
         * Tocar nuevamente la opción ya seleccionada la deselecciona.
         * La selección de las otras categorías se conserva.
         */
        self.selectedOptionIndexPath = nil;

        if ([self.selectedCategory isEqualToString:@"aimbot"]) {
            self.selectedAimbotIndexPath = nil;
        } else if ([self.selectedCategory isEqualToString:@"fps"]) {
            self.selectedFPSIndexPath = nil;
        } else {
            self.selectedHologramIndexPath = nil;
        }

    } else {

        self.selectedOptionIndexPath =
            indexPath;

        if ([self.selectedCategory isEqualToString:@"aimbot"]) {
            self.selectedAimbotIndexPath = indexPath;
        } else if ([self.selectedCategory isEqualToString:@"fps"]) {
            self.selectedFPSIndexPath = indexPath;
        } else {
            self.selectedHologramIndexPath = indexPath;
        }
    }

    if (!self.activationInProgress) {

        self.selectionHintLabel.text =
            [self selectionHintText];

        self.selectionHintLabel.textColor =
            [UIColor colorWithWhite:0.48
                              alpha:1.0];
    }

    [self updateActivateButtonForCurrentSelection];

    NSArray *rowsToReload =
        previous &&
        ![previous isEqual:indexPath]
        ? @[previous, indexPath]
        : @[indexPath];

    [tableView
        reloadRowsAtIndexPaths:rowsToReload
        withRowAnimation:UITableViewRowAnimationFade];

    UISelectionFeedbackGenerator *feedback =
        [[UISelectionFeedbackGenerator alloc] init];

    [feedback selectionChanged];
}

- (void)beginActivationUI {

    if (
        self.activationInProgress ||
        self.deactivationInProgress
    ) {
        return;
    }

    self.activationInProgress =
        YES;

    self.tableView.userInteractionEnabled =
        NO;

    self.activateButton.enabled =
        NO;

    self.activateButton.alpha =
        1.0;

    self.deactivateButton.enabled =
        NO;

    self.deactivateButton.alpha =
        0.42;

    [self.activateButton
        setTitle:@"ACTIVANDO..."
        forState:UIControlStateNormal];

    /*
     * ACTIVAR muestra únicamente el texto "ACTIVANDO...".
     * El indicador circular permanece oculto.
     */
    [self.activateSpinner
        stopAnimating];

    /*
     * Ocultamos cualquier mensaje central anterior.
     * Durante la descarga/escritura no mostramos
     * "Descargando..." ni ningún modal.
     */
    self.statusLabel.hidden =
        YES;

    [self.activityIndicator
        stopAnimating];

    self.selectionHintLabel.text =
        @"APLICANDO OPCIÓN";

    self.selectionHintLabel.textColor =
        [UIColor colorWithWhite:0.50
                          alpha:1.0];
}


- (void)finishActivationUIWithSuccess:
    (BOOL)success
    message:(NSString *)message {

    self.activationInProgress =
        NO;

    self.tableView.userInteractionEnabled =
        YES;

    [self.activateSpinner
        stopAnimating];

    if (!self.deactivationInProgress) {
        self.deactivateButton.enabled =
            YES;

        self.deactivateButton.alpha =
            1.0;
    }

    NSArray<XITForgeOption *> *activatedOptions =
        [self.activationSucceededOptions copy] ?: @[];

    if (success) {

        self.selectionHintLabel.text =
            [self selectionHintText];

        self.selectionHintLabel.textColor =
            [UIColor colorWithWhite:0.48
                              alpha:1.0];

        [self showActivationBannerForOptions:activatedOptions];
        [self playActivationAudio];

        BOOL activatedAimbot = NO;

        for (XITForgeOption *option in activatedOptions) {
            NSString *category =
                option.category.lowercaseString ?: @"";

            if ([category isEqualToString:@"aimbot"]) {
                activatedAimbot = YES;
                break;
            }
        }

        if (activatedAimbot) {
            [self showAimbotWarning];
        }

        UINotificationFeedbackGenerator *feedback =
            [[UINotificationFeedbackGenerator alloc] init];

        [feedback
            notificationOccurred:
                UINotificationFeedbackTypeSuccess];

    } else {

        self.selectionHintLabel.text =
            message.length > 0
                ? @"NO SE PUDO ACTIVAR"
                : @"ERROR AL ACTIVAR";

        self.selectionHintLabel.textColor =
            XITForgeAccentColor();

        UINotificationFeedbackGenerator *feedback =
            [[UINotificationFeedbackGenerator alloc] init];

        [feedback
            notificationOccurred:
                UINotificationFeedbackTypeError];
    }

    [self.tableView reloadData];
    [self updateActivateButtonForCurrentSelection];
}


- (void)activateNextPendingOption {
    if (self.currentActivationIndex >= self.pendingActivationOptions.count) {
        [self finishActivationUIWithSuccess:YES
                                     message:@"Opciones activadas correctamente."];

        self.pendingActivationOptions = nil;
        self.currentActivationOption = nil;
        self.currentActivationIndex = 0;
        self.activationSucceededOptions = nil;
        return;
    }

    self.currentActivationOption =
        self.pendingActivationOptions[self.currentActivationIndex];

    [self applyOption:self.currentActivationOption];
}

- (void)activateSelectedOption {

    if (
        self.activationInProgress ||
        self.deactivationInProgress
    ) {
        return;
    }

    NSArray<XITForgeOption *> *selected =
        [self selectedOptions];

    NSMutableArray<XITForgeOption *> *pending =
        [NSMutableArray arrayWithCapacity:selected.count];

    for (XITForgeOption *option in selected) {
        if (![self isOptionActivated:option]) {
            [pending addObject:option];
        }
    }

    if (pending.count == 0) {
        [self updateActivateButtonForCurrentSelection];
        return;
    }

    [self beginActivationUI];

    self.pendingActivationOptions =
        [pending copy];

    self.activationSucceededOptions =
        [NSMutableArray arrayWithCapacity:pending.count];

    self.currentActivationIndex = 0;
    self.currentActivationOption = nil;

    [self activateNextPendingOption];
}


#pragma mark - Deactivate From Server

- (void)beginDeactivationUI {

    if (
        self.activationInProgress ||
        self.deactivationInProgress
    ) {
        return;
    }

    self.deactivationInProgress =
        YES;

    self.tableView.userInteractionEnabled =
        NO;

    self.activateButton.enabled =
        NO;

    self.activateButton.alpha =
        0.45;

    /*
     * Bloqueamos el botón para evitar toques dobles,
     * pero visualmente permanece exactamente como "DESACTIVAR".
     * No mostramos spinner ni texto de carga.
     */
    self.deactivateButton.enabled =
        NO;

    self.deactivateButton.alpha =
        1.0;

    [self.deactivateButton
        setTitle:@"DESACTIVAR"
        forState:UIControlStateNormal];

    self.statusLabel.hidden =
        YES;

    [self.activityIndicator
        stopAnimating];
}


- (void)finishDeactivationUIWithSuccess:
    (BOOL)success
    noOriginals:(BOOL)noOriginals {

    self.deactivationInProgress =
        NO;

    self.tableView.userInteractionEnabled =
        YES;

    [self.deactivateButton
        setTitle:@"DESACTIVAR"
        forState:UIControlStateNormal];

    self.deactivateButton.enabled =
        YES;

    self.deactivateButton.alpha =
        1.0;

    if (noOriginals) {

        [self updateActivateButtonForCurrentSelection];

        self.selectionHintLabel.text =
            @"SIN ORIGINALES CONFIGURADOS";

        self.selectionHintLabel.textColor =
            [UIColor colorWithWhite:0.52
                              alpha:1.0];

        return;
    }

    if (success) {

        [self clearActivatedOptions];

        self.selectionHintLabel.text =
            @"✓  DESACTIVADO";

        self.selectionHintLabel.textColor =
            [UIColor colorWithWhite:0.92 alpha:1.0];

        UINotificationFeedbackGenerator *feedback =
            [[UINotificationFeedbackGenerator alloc] init];

        [feedback
            notificationOccurred:
                UINotificationFeedbackTypeSuccess];

    } else {

        self.selectionHintLabel.text =
            @"NO SE PUDO DESACTIVAR";

        self.selectionHintLabel.textColor =
            XITForgeAccentColor();

        UINotificationFeedbackGenerator *feedback =
            [[UINotificationFeedbackGenerator alloc] init];

        [feedback
            notificationOccurred:
                UINotificationFeedbackTypeError];
    }

    [self updateActivateButtonForCurrentSelection];
}


- (void)processOriginalManifestDictionary:
    (NSDictionary *)dictionary
    originals:(NSArray *)rawOriginals
    legacy:(BOOL)legacy {

    if (rawOriginals.count == 0) {
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                [self
                    finishDeactivationUIWithSuccess:YES
                    noOriginals:YES];
            });
        return;
    }

    /*
     * Resolver el contenedor/rutas del juego se hace en main,
     * igual que ACTIVAR, para no invocar el motor MCM desde
     * una cola de red en segundo plano.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
        NSString *responseBundleId =
            [dictionary[@"bundleId"] isKindOfClass:[NSString class]]
                ? dictionary[@"bundleId"]
                : self.bundleId;

        NSMutableArray *items =
            [NSMutableArray array];

        for (id rawItem in rawOriginals) {

            if (![rawItem isKindOfClass:[NSDictionary class]]) {
                NSLog(@"XITFORGE original manifest: item inválido");
                [self
                    finishDeactivationUIWithSuccess:NO
                    noOriginals:NO];
                return;
            }

            NSDictionary *raw =
                (NSDictionary *)rawItem;

            XITForgeOption *option =
                [[XITForgeOption alloc] init];

            option.bundleId =
                [raw[@"bundleId"] isKindOfClass:[NSString class]]
                    ? raw[@"bundleId"]
                    : responseBundleId;

            option.route =
                [raw[@"route"] isKindOfClass:[NSString class]]
                    ? raw[@"route"]
                    : nil;

            option.fileName =
                [raw[@"fileName"] isKindOfClass:[NSString class]]
                    ? raw[@"fileName"]
                    : nil;

            option.originalFileUrl =
                [raw[@"originalFileUrl"] isKindOfClass:[NSString class]]
                    ? raw[@"originalFileUrl"]
                    : nil;

            /*
             * Compatibilidad extra:
             * - API nueva: /api/app/originals/:id/file
             * - API anterior: /api/app/options/:id/original-file
             *
             * Si el servidor no envía originalFileUrl pero sí el ID,
             * la IPA puede construir la dirección correcta por sí sola.
             */
            if (option.originalFileUrl.length == 0) {
                NSNumber *itemId =
                    [raw[@"id"] isKindOfClass:[NSNumber class]]
                        ? raw[@"id"]
                        : nil;

                if (itemId.longLongValue > 0) {
                    option.originalFileUrl =
                        legacy
                            ? [NSString stringWithFormat:
                                @"/api/app/options/%@/original-file",
                                itemId]
                            : [NSString stringWithFormat:
                                @"/api/app/originals/%@/file",
                                itemId];
                }
            }

            if (
                option.route.length == 0 ||
                option.fileName.length == 0 ||
                option.originalFileUrl.length == 0
            ) {
                NSLog(
                    @"XITFORGE original manifest incompleto: id=%@ route=%@ file=%@ url=%@ legacy=%d",
                    raw[@"id"],
                    option.route,
                    option.fileName,
                    option.originalFileUrl,
                    legacy
                );

                [self
                    finishDeactivationUIWithSuccess:NO
                    noOriginals:NO];
                return;
            }

            NSString *resolveError =
                nil;

            NSURL *destinationURL =
                [self
                    destinationURLForOption:option
                    error:&resolveError];

            NSURL *downloadURL =
                [self absoluteServerURLForString:
                    option.originalFileUrl];

            if (
                !destinationURL ||
                !downloadURL
            ) {

                NSLog(
                    @"XITFORGE original resolve error: %@ | route=%@ file=%@ url=%@",
                    resolveError,
                    option.route,
                    option.fileName,
                    option.originalFileUrl
                );

                [self
                    finishDeactivationUIWithSuccess:NO
                    noOriginals:NO];
                return;
            }

            [items addObject:@{
                @"downloadURL": downloadURL,
                @"destinationURL": destinationURL
            }];
        }

        [self
            restoreOriginalItems:items
            index:0];

        });
}


- (void)deactivateUsingLegacyOptionsFallback {

    NSString *encodedGame =
        [self.game
            stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet URLQueryAllowedCharacterSet]];

    NSString *urlString =
        [NSString stringWithFormat:
            @"%@/api/app/options?game=%@",
            [self apiBaseURL],
            encodedGame ?: @""];

    NSURL *url =
        [NSURL URLWithString:urlString];

    if (!url) {
        [self
            finishDeactivationUIWithSuccess:NO
            noOriginals:NO];
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20.0;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:
        ^(NSData * _Nullable data,
          NSURLResponse * _Nullable response,
          NSError * _Nullable error) {

        NSHTTPURLResponse *http =
            [response isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSHTTPURLResponse *)response
                : nil;

        if (
            error ||
            !data ||
            (http && (http.statusCode < 200 || http.statusCode > 299))
        ) {
            NSLog(
                @"XITFORGE legacy originals fallback failed: %@ HTTP=%ld",
                error,
                (long)http.statusCode
            );

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        finishDeactivationUIWithSuccess:NO
                        noOriginals:NO];
                });
            return;
        }

        NSError *jsonError = nil;
        id json =
            [NSJSONSerialization
                JSONObjectWithData:data
                options:0
                error:&jsonError];

        if (
            jsonError ||
            ![json isKindOfClass:[NSDictionary class]]
        ) {
            NSLog(@"XITFORGE legacy originals JSON error: %@", jsonError);
            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        finishDeactivationUIWithSuccess:NO
                        noOriginals:NO];
                });
            return;
        }

        NSDictionary *dictionary =
            (NSDictionary *)json;

        NSNumber *ok =
            dictionary[@"ok"];

        NSArray *rawOptions =
            dictionary[@"options"];

        if (
            ![ok isKindOfClass:[NSNumber class]] ||
            !ok.boolValue ||
            ![rawOptions isKindOfClass:[NSArray class]]
        ) {
            NSLog(
                @"XITFORGE legacy originals response inválida: %@",
                dictionary[@"error"]
            );
            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        finishDeactivationUIWithSuccess:NO
                        noOriginals:NO];
                });
            return;
        }

        NSMutableArray *legacyOriginals =
            [NSMutableArray array];

        for (id item in rawOptions) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;

            NSDictionary *raw =
                (NSDictionary *)item;

            NSString *originalURL =
                [raw[@"originalFileUrl"] isKindOfClass:[NSString class]]
                    ? raw[@"originalFileUrl"]
                    : nil;

            BOOL hasOriginal =
                [raw[@"hasOriginalFile"] isKindOfClass:[NSNumber class]]
                    ? [raw[@"hasOriginalFile"] boolValue]
                    : (originalURL.length > 0);

            if (!hasOriginal && originalURL.length == 0) {
                continue;
            }

            [legacyOriginals addObject:raw];
        }

        [self
            processOriginalManifestDictionary:dictionary
            originals:legacyOriginals
            legacy:YES];
    }];

    [task resume];
}


- (void)deactivateAllOptions {

    if (
        self.activationInProgress ||
        self.deactivationInProgress
    ) {
        return;
    }

    [self beginDeactivationUI];

    NSString *encodedGame =
        [self.game
            stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet URLQueryAllowedCharacterSet]];

    NSString *urlString =
        [NSString stringWithFormat:
            @"%@/api/app/originals?game=%@",
            [self apiBaseURL],
            encodedGame ?: @""];

    NSURL *url =
        [NSURL URLWithString:urlString];

    if (!url) {
        [self deactivateUsingLegacyOptionsFallback];
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20.0;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:
        ^(NSData * _Nullable data,
          NSURLResponse * _Nullable response,
          NSError * _Nullable error) {

        NSHTTPURLResponse *http =
            [response isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSHTTPURLResponse *)response
                : nil;

        if (
            error ||
            !data ||
            (http && (http.statusCode < 200 || http.statusCode > 299))
        ) {
            NSLog(
                @"XITFORGE originals list failed: %@ HTTP=%ld; intentando API anterior",
                error,
                (long)http.statusCode
            );
            [self deactivateUsingLegacyOptionsFallback];
            return;
        }

        NSError *jsonError = nil;
        id json =
            [NSJSONSerialization
                JSONObjectWithData:data
                options:0
                error:&jsonError];

        if (
            jsonError ||
            ![json isKindOfClass:[NSDictionary class]]
        ) {
            NSLog(
                @"XITFORGE originals JSON inválido: %@; intentando API anterior",
                jsonError
            );
            [self deactivateUsingLegacyOptionsFallback];
            return;
        }

        NSDictionary *dictionary =
            (NSDictionary *)json;

        NSNumber *ok =
            dictionary[@"ok"];

        NSArray *rawOriginals =
            dictionary[@"originals"];

        if (
            ![ok isKindOfClass:[NSNumber class]] ||
            !ok.boolValue ||
            ![rawOriginals isKindOfClass:[NSArray class]]
        ) {
            NSLog(
                @"XITFORGE originals response inválida: %@; intentando API anterior",
                dictionary[@"error"]
            );
            [self deactivateUsingLegacyOptionsFallback];
            return;
        }

        [self
            processOriginalManifestDictionary:dictionary
            originals:rawOriginals
            legacy:NO];
    }];

    [task resume];
}


- (void)restoreOriginalItems:
    (NSArray<NSDictionary *> *)items
    index:(NSUInteger)index {

    if (index >= items.count) {

        [self
            finishDeactivationUIWithSuccess:YES
            noOriginals:NO];

        return;
    }

    NSDictionary *item =
        items[index];

    NSURL *downloadURL =
        item[@"downloadURL"];

    NSURL *destinationURL =
        item[@"destinationURL"];

    if (!downloadURL || !destinationURL) {
        [self
            finishDeactivationUIWithSuccess:NO
            noOriginals:NO];
        return;
    }

    NSURLSessionDownloadTask *task =
        [[NSURLSession sharedSession]
            downloadTaskWithURL:downloadURL
              completionHandler:
        ^(NSURL * _Nullable location,
          NSURLResponse * _Nullable response,
          NSError * _Nullable error) {

        NSHTTPURLResponse *http =
            [response isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSHTTPURLResponse *)response
                : nil;

        BOOL httpOK =
            !http ||
            (http.statusCode >= 200 &&
             http.statusCode <= 299);

        if (
            error ||
            !location ||
            !httpOK
        ) {

            NSLog(
                @"XITFORGE original download failed: %@ HTTP=%ld",
                error,
                (long)http.statusCode
            );

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        finishDeactivationUIWithSuccess:NO
                        noOriginals:NO];
                });

            return;
        }

        NSError *writeError =
            nil;

        BOOL written =
            XITForgeWriteExactFile(
                location,
                destinationURL,
                &writeError
            );

        if (!written) {

            NSLog(
                @"XITFORGE original write failed: %@ destination=%@",
                writeError,
                destinationURL.path
            );

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        finishDeactivationUIWithSuccess:NO
                        noOriginals:NO];
                });

            return;
        }

        NSError *verifyError =
            nil;

        BOOL verified =
            XITForgeFilesAreIdentical(
                location,
                destinationURL,
                &verifyError
            );

        if (!verified) {

            NSLog(
                @"XITFORGE original verify failed: %@ destination=%@",
                verifyError,
                destinationURL.path
            );

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        finishDeactivationUIWithSuccess:NO
                        noOriginals:NO];
                });

            return;
        }

        NSLog(
            @"XITFORGE ORIGINAL RESTORED destination=%@",
            destinationURL.path
        );

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                [self
                    restoreOriginalItems:items
                    index:(index + 1)];
            });
    }];

    [task resume];
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
        [self absoluteServerURLForString:
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

    /*
     * No mostramos estado de descarga en pantalla.
     * El botón ya permanece en ACTIVANDO... sin indicador circular.
     */
    self.statusLabel.hidden =
        YES;

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

    if (self.downloadSession == session) {
        self.downloadSession = nil;
    }
}

#pragma mark - Result

- (void)showResult:
    (NSString *)message
    success:(BOOL)success {

    [self.activityIndicator
        stopAnimating];

    /*
     * Una pulsación de ACTIVAR puede aplicar hasta dos opciones:
     * primero AIMBOT y después HOLOGRAMA. El audio/banner se
     * muestran una sola vez al terminar todo el lote.
     */
    if (self.activationInProgress &&
        self.pendingActivationOptions.count > 0) {

        if (!success) {
            [self finishActivationUIWithSuccess:NO
                                         message:message];

            self.pendingActivationOptions = nil;
            self.currentActivationOption = nil;
            self.currentActivationIndex = 0;
            self.activationSucceededOptions = nil;
            return;
        }

        if (self.currentActivationOption) {
            [self markOptionActivated:self.currentActivationOption];
            [self.activationSucceededOptions addObject:self.currentActivationOption];
        }

        self.currentActivationIndex += 1;

        if (self.currentActivationIndex < self.pendingActivationOptions.count) {
            [self activateNextPendingOption];
            return;
        }

        [self finishActivationUIWithSuccess:YES
                                     message:message];

        self.pendingActivationOptions = nil;
        self.currentActivationOption = nil;
        self.currentActivationIndex = 0;
        self.activationSucceededOptions = nil;
        return;
    }

    [self finishActivationUIWithSuccess:success
                                 message:message];
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

    self.title = @"";
    self.navigationItem.title = @"";
    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeNever;

    [self setupUI];
}

#pragma mark - UI

- (void)setupUI {

    UIColor *primaryText =
        [UIColor colorWithWhite:0.97
                          alpha:1.0];

    UIColor *secondaryText =
        [UIColor colorWithWhite:0.58
                          alpha:1.0];

    UIColor *cardColor =
        [UIColor colorWithWhite:0.075
                          alpha:1.0];

    UIColor *cardStroke =
        [UIColor colorWithWhite:1.0
                          alpha:0.075];

    UIColor *accent = XITForgeAccentColor();

    /*
     * Un único brillo ambiental detrás de las dos tarjetas.
     * No hay borde rojo/verde ni colores distintos por versión.
     */
    UIView *ambientGlow =
        [[UIView alloc] init];

    ambientGlow.translatesAutoresizingMaskIntoConstraints =
        NO;

    ambientGlow.backgroundColor =
        [accent colorWithAlphaComponent:0.075];

    ambientGlow.layer.cornerRadius =
        155.0;

    ambientGlow.layer.masksToBounds =
        YES;

    ambientGlow.userInteractionEnabled =
        NO;

    [self.view addSubview:
        ambientGlow];


    UILabel *prompt =
        [[UILabel alloc] init];

    prompt.translatesAutoresizingMaskIntoConstraints =
        NO;

    prompt.text =
        @"ELIGE TU VERSIÓN";

    prompt.textColor =
        secondaryText;

    prompt.font =
        [UIFont systemFontOfSize:12.0
                          weight:UIFontWeightSemibold];

    prompt.textAlignment =
        NSTextAlignmentCenter;

    [self.view addSubview:
        prompt];


    UIStackView *gameRow =
        [[UIStackView alloc] init];

    gameRow.translatesAutoresizingMaskIntoConstraints =
        NO;

    gameRow.axis =
        UILayoutConstraintAxisHorizontal;

    gameRow.alignment =
        UIStackViewAlignmentFill;

    gameRow.distribution =
        UIStackViewDistributionFillEqually;

    gameRow.spacing =
        14.0;

    [self.view addSubview:
        gameRow];


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
        cardColor;

    self.btnNormal.layer.cornerRadius =
        24.0;

    self.btnNormal.layer.borderWidth =
        1.0;

    self.btnNormal.layer.borderColor =
        cardStroke.CGColor;

    self.btnNormal.layer.shadowColor =
        [UIColor blackColor].CGColor;

    self.btnNormal.layer.shadowOpacity =
        0.42;

    self.btnNormal.layer.shadowRadius =
        18.0;

    self.btnNormal.layer.shadowOffset =
        CGSizeMake(0.0, 10.0);

    [self.btnNormal
        addTarget:self
        action:@selector(btnNormalTapped)
        forControlEvents:
            UIControlEventTouchUpInside];

    [gameRow addArrangedSubview:
        self.btnNormal];


    UIImageView *normalIcon =
        [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:
                @"gamecontroller.fill"]];

    normalIcon.translatesAutoresizingMaskIntoConstraints =
        NO;

    normalIcon.tintColor =
        primaryText;

    normalIcon.contentMode =
        UIViewContentModeScaleAspectFit;

    normalIcon.userInteractionEnabled =
        NO;

    [self.btnNormal addSubview:
        normalIcon];


    UILabel *normalBrand =
        [[UILabel alloc] init];

    normalBrand.translatesAutoresizingMaskIntoConstraints =
        NO;

    normalBrand.text =
        @"FREE FIRE";

    normalBrand.textColor =
        secondaryText;

    normalBrand.font =
        [UIFont systemFontOfSize:10.0
                          weight:UIFontWeightSemibold];

    normalBrand.textAlignment =
        NSTextAlignmentCenter;

    normalBrand.userInteractionEnabled =
        NO;

    [self.btnNormal addSubview:
        normalBrand];


    UILabel *normalTitle =
        [[UILabel alloc] init];

    normalTitle.translatesAutoresizingMaskIntoConstraints =
        NO;

    normalTitle.text =
        @"NORMAL";

    normalTitle.textColor =
        primaryText;

    normalTitle.font =
        [UIFont systemFontOfSize:20.0
                          weight:UIFontWeightBold];

    normalTitle.textAlignment =
        NSTextAlignmentCenter;

    normalTitle.adjustsFontSizeToFitWidth =
        YES;

    normalTitle.minimumScaleFactor =
        0.78;

    normalTitle.userInteractionEnabled =
        NO;

    [self.btnNormal addSubview:
        normalTitle];


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
        cardColor;

    self.btnMax.layer.cornerRadius =
        24.0;

    self.btnMax.layer.borderWidth =
        1.0;

    self.btnMax.layer.borderColor =
        cardStroke.CGColor;

    self.btnMax.layer.shadowColor =
        [UIColor blackColor].CGColor;

    self.btnMax.layer.shadowOpacity =
        0.42;

    self.btnMax.layer.shadowRadius =
        18.0;

    self.btnMax.layer.shadowOffset =
        CGSizeMake(0.0, 10.0);

    [self.btnMax
        addTarget:self
        action:@selector(btnMaxTapped)
        forControlEvents:
            UIControlEventTouchUpInside];

    [gameRow addArrangedSubview:
        self.btnMax];


    UIImageView *maxIcon =
        [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:
                @"bolt.horizontal.circle.fill"]];

    maxIcon.translatesAutoresizingMaskIntoConstraints =
        NO;

    maxIcon.tintColor =
        primaryText;

    maxIcon.contentMode =
        UIViewContentModeScaleAspectFit;

    maxIcon.userInteractionEnabled =
        NO;

    [self.btnMax addSubview:
        maxIcon];


    UILabel *maxBrand =
        [[UILabel alloc] init];

    maxBrand.translatesAutoresizingMaskIntoConstraints =
        NO;

    maxBrand.text =
        @"FREE FIRE";

    maxBrand.textColor =
        secondaryText;

    maxBrand.font =
        [UIFont systemFontOfSize:10.0
                          weight:UIFontWeightSemibold];

    maxBrand.textAlignment =
        NSTextAlignmentCenter;

    maxBrand.userInteractionEnabled =
        NO;

    [self.btnMax addSubview:
        maxBrand];


    UILabel *maxTitle =
        [[UILabel alloc] init];

    maxTitle.translatesAutoresizingMaskIntoConstraints =
        NO;

    maxTitle.text =
        @"MAX";

    maxTitle.textColor =
        primaryText;

    maxTitle.font =
        [UIFont systemFontOfSize:20.0
                          weight:UIFontWeightBold];

    maxTitle.textAlignment =
        NSTextAlignmentCenter;

    maxTitle.userInteractionEnabled =
        NO;

    [self.btnMax addSubview:
        maxTitle];


    /*
     * ========================================================
     * CONSTRAINTS
     * ========================================================
     */

    [NSLayoutConstraint activateConstraints:@[

        /*
         * Las dos tarjetas quedan juntas y centradas.
         */
        [gameRow.centerXAnchor
            constraintEqualToAnchor:
                self.view.centerXAnchor],

        [gameRow.centerYAnchor
            constraintEqualToAnchor:
                self.view.centerYAnchor
                constant:-10.0],

        [gameRow.leadingAnchor
            constraintEqualToAnchor:
                self.view.leadingAnchor
                constant:22.0],

        [gameRow.trailingAnchor
            constraintEqualToAnchor:
                self.view.trailingAnchor
                constant:-22.0],

        [gameRow.heightAnchor
            constraintEqualToConstant:154.0],


        /*
         * Texto justo encima del conjunto, no arriba de la pantalla.
         */
        [prompt.centerXAnchor
            constraintEqualToAnchor:
                gameRow.centerXAnchor],

        [prompt.bottomAnchor
            constraintEqualToAnchor:
                gameRow.topAnchor
                constant:-20.0],


        /*
         * Brillo ambiental centrado detrás de ambas tarjetas.
         */
        [ambientGlow.centerXAnchor
            constraintEqualToAnchor:
                gameRow.centerXAnchor],

        [ambientGlow.centerYAnchor
            constraintEqualToAnchor:
                gameRow.centerYAnchor],

        [ambientGlow.widthAnchor
            constraintEqualToConstant:310.0],

        [ambientGlow.heightAnchor
            constraintEqualToConstant:310.0],


        /*
         * Contenido NORMAL.
         */
        [normalIcon.centerXAnchor
            constraintEqualToAnchor:
                self.btnNormal.centerXAnchor],

        [normalIcon.topAnchor
            constraintEqualToAnchor:
                self.btnNormal.topAnchor
                constant:28.0],

        [normalIcon.widthAnchor
            constraintEqualToConstant:30.0],

        [normalIcon.heightAnchor
            constraintEqualToConstant:30.0],

        [normalBrand.centerXAnchor
            constraintEqualToAnchor:
                self.btnNormal.centerXAnchor],

        [normalBrand.topAnchor
            constraintEqualToAnchor:
                normalIcon.bottomAnchor
                constant:18.0],

        [normalTitle.leadingAnchor
            constraintEqualToAnchor:
                self.btnNormal.leadingAnchor
                constant:10.0],

        [normalTitle.trailingAnchor
            constraintEqualToAnchor:
                self.btnNormal.trailingAnchor
                constant:-10.0],

        [normalTitle.topAnchor
            constraintEqualToAnchor:
                normalBrand.bottomAnchor
                constant:4.0],


        /*
         * Contenido MAX.
         */
        [maxIcon.centerXAnchor
            constraintEqualToAnchor:
                self.btnMax.centerXAnchor],

        [maxIcon.topAnchor
            constraintEqualToAnchor:
                self.btnMax.topAnchor
                constant:28.0],

        [maxIcon.widthAnchor
            constraintEqualToConstant:30.0],

        [maxIcon.heightAnchor
            constraintEqualToConstant:30.0],

        [maxBrand.centerXAnchor
            constraintEqualToAnchor:
                self.btnMax.centerXAnchor],

        [maxBrand.topAnchor
            constraintEqualToAnchor:
                maxIcon.bottomAnchor
                constant:18.0],

        [maxTitle.leadingAnchor
            constraintEqualToAnchor:
                self.btnMax.leadingAnchor
                constant:10.0],

        [maxTitle.trailingAnchor
            constraintEqualToAnchor:
                self.btnMax.trailingAnchor
                constant:-10.0],

        [maxTitle.topAnchor
            constraintEqualToAnchor:
                maxBrand.bottomAnchor
                constant:4.0]
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
