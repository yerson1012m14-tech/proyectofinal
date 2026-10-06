#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>
#import <string.h>

#import "LicenseValidator.h"
#import "XITForgeFileEngine.h"
#import "XFTunnelV2Config.h"

#pragma mark - Interfaces existentes

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
@property (nonatomic, copy) NSArray<NSDictionary *> *fileItems;
@end

@interface XITForgeOptionsViewController : UIViewController
@property (nonatomic, copy) NSString *game;
@property (nonatomic, copy) NSString *bundleId;

- (NSString *)apiBaseURL;
- (NSURL *)absoluteServerURLForString:(NSString *)value;
- (NSURL *)destinationURLForOption:(XITForgeOption *)option
                            error:(NSString **)errorOut;
- (void)applyOption:(XITForgeOption *)option;
- (void)showResult:(NSString *)message
           success:(BOOL)success;
@end

#pragma mark - Copia y verificación local

static NSError *XF2Error(NSInteger code, NSString *message) {
    return
        [NSError
            errorWithDomain:@"XITFORGE_TWO_FILES"
            code:code
            userInfo:@{
                NSLocalizedDescriptionKey:
                    message ?: @"Error de archivo."
            }];
}

static BOOL XF2WriteExactFile(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSError **errorOut
) {
    NSString *sourcePath = sourceURL.path;
    NSString *destinationPath = destinationURL.path;

    if (!sourcePath.length || !destinationPath.length) {
        if (errorOut) {
            *errorOut =
                XF2Error(
                    3100,
                    @"Ruta de origen o destino vacía."
                );
        }
        return NO;
    }

    const char *src = sourcePath.fileSystemRepresentation;
    const char *dst = destinationPath.fileSystemRepresentation;

    struct stat dstInfo = {0};

    if (lstat(dst, &dstInfo) == 0) {
        if (!S_ISREG(dstInfo.st_mode) ||
            S_ISLNK(dstInfo.st_mode)) {
            if (errorOut) {
                *errorOut =
                    XF2Error(
                        3101,
                        @"El destino existente no es un archivo normal."
                    );
            }
            return NO;
        }
    } else if (errno != ENOENT) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:errno
                    userInfo:nil];
        }
        return NO;
    }

    int inFD = open(src, O_RDONLY | O_CLOEXEC);

    if (inFD < 0) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:errno
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

    int outFD = open(dst, flags, 0644);

    if (outFD < 0) {
        int saved = errno;
        close(inFD);

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:saved
                    userInfo:nil];
        }

        return NO;
    }

    BOOL ok = YES;
    int savedErrno = 0;
    unsigned char buffer[256 * 1024];

    for (;;) {
        ssize_t n = read(inFD, buffer, sizeof(buffer));

        if (n == 0) break;

        if (n < 0) {
            if (errno == EINTR) continue;
            ok = NO;
            savedErrno = errno;
            break;
        }

        ssize_t offset = 0;

        while (offset < n) {
            ssize_t written =
                write(
                    outFD,
                    buffer + offset,
                    (size_t)(n - offset)
                );

            if (written < 0) {
                if (errno == EINTR) continue;

                ok = NO;
                savedErrno = errno;
                break;
            }

            offset += written;
        }

        if (!ok) break;
    }

    if (ok && fsync(outFD) != 0) {
        ok = NO;
        savedErrno = errno;
    }

    close(outFD);
    close(inFD);

    if (!ok) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:savedErrno
                    userInfo:nil];
        }
        return NO;
    }

    return YES;
}

static BOOL XF2FilesAreIdentical(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSError **errorOut
) {
    int leftFD =
        open(
            sourceURL.path.fileSystemRepresentation,
            O_RDONLY | O_CLOEXEC
        );

    if (leftFD < 0) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:errno
                    userInfo:nil];
        }
        return NO;
    }

    int rightFD =
        open(
            destinationURL.path.fileSystemRepresentation,
            O_RDONLY | O_CLOEXEC
        );

    if (rightFD < 0) {
        int saved = errno;
        close(leftFD);

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:saved
                    userInfo:nil];
        }
        return NO;
    }

    struct stat leftInfo = {0};
    struct stat rightInfo = {0};

    if (fstat(leftFD, &leftInfo) != 0 ||
        fstat(rightFD, &rightInfo) != 0) {
        int saved = errno;
        close(leftFD);
        close(rightFD);

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:saved
                    userInfo:nil];
        }
        return NO;
    }

    if (!S_ISREG(leftInfo.st_mode) ||
        !S_ISREG(rightInfo.st_mode) ||
        leftInfo.st_size != rightInfo.st_size) {
        close(leftFD);
        close(rightFD);

        if (errorOut) {
            *errorOut =
                XF2Error(
                    3102,
                    @"El archivo escrito no coincide en tamaño con la descarga."
                );
        }

        return NO;
    }

    unsigned char left[256 * 1024];
    unsigned char right[256 * 1024];

    BOOL identical = YES;
    int savedErrno = 0;

    for (;;) {
        ssize_t a = -1;
        ssize_t b = -1;

        do {
            a = read(leftFD, left, sizeof(left));
        } while (a < 0 && errno == EINTR);

        if (a < 0) {
            identical = NO;
            savedErrno = errno;
            break;
        }

        do {
            b = read(rightFD, right, sizeof(right));
        } while (b < 0 && errno == EINTR);

        if (b < 0) {
            identical = NO;
            savedErrno = errno;
            break;
        }

        if (a != b) {
            identical = NO;
            break;
        }

        if (a == 0) break;

        if (memcmp(left, right, (size_t)a) != 0) {
            identical = NO;
            break;
        }
    }

    close(leftFD);
    close(rightFD);

    if (!identical && errorOut) {
        if (savedErrno) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:savedErrno
                    userInfo:nil];
        } else {
            *errorOut =
                XF2Error(
                    3103,
                    @"El contenido escrito no coincide con la descarga."
                );
        }
    }

    return identical;
}

#pragma mark - Tunnel V2

@interface XITForgeOptionsViewController (XITForgeTwoFiles)

- (void)xf2_applyOption:(XITForgeOption *)option;
- (void)xf2_viewDidLoad;

@end

@implementation XITForgeOptionsViewController (XITForgeTwoFiles)

+ (void)load {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        Class cls =
            NSClassFromString(
                @"XITForgeOptionsViewController"
            );

        if (!cls) return;

        Method originalApply =
            class_getInstanceMethod(
                cls,
                @selector(applyOption:)
            );

        Method replacementApply =
            class_getInstanceMethod(
                cls,
                @selector(xf2_applyOption:)
            );

        if (originalApply && replacementApply) {
            method_exchangeImplementations(
                originalApply,
                replacementApply
            );
        }

        Method originalViewDidLoad =
            class_getInstanceMethod(
                cls,
                @selector(viewDidLoad)
            );

        Method replacementViewDidLoad =
            class_getInstanceMethod(
                cls,
                @selector(xf2_viewDidLoad)
            );

        if (originalViewDidLoad &&
            replacementViewDidLoad) {
            method_exchangeImplementations(
                originalViewDidLoad,
                replacementViewDidLoad
            );
        }
    });
}

- (void)xf2_viewDidLoad {
    // Después del swizzle llama al viewDidLoad original.
    [self xf2_viewDidLoad];

    // Precarga el mapa legacy -> Tunnel V2 para que DESACTIVAR
    // también funcione después de volver a abrir la app.
    [self xf2_fetchManifestWithCompletion:
        ^(NSDictionary *dictionary, NSError *error) {
            (void)error;

            NSArray *rawOptions =
                [dictionary[@"options"]
                    isKindOfClass:NSArray.class]
                    ? dictionary[@"options"]
                    : nil;

            NSString *topTunnel =
                [XFTunnelV2Config
                    tunnelBundleIdFromOptionDictionary:
                        dictionary];

            for (id value in rawOptions ?: @[]) {
                if (![value
                        isKindOfClass:NSDictionary.class]) {
                    continue;
                }

                NSDictionary *raw =
                    (NSDictionary *)value;

                NSString *legacy =
                    [raw[@"bundleId"]
                        isKindOfClass:NSString.class]
                        ? raw[@"bundleId"]
                        : self.bundleId;

                NSString *tunnel =
                    [XFTunnelV2Config
                        tunnelBundleIdFromOptionDictionary:
                            raw];

                if (!tunnel.length) tunnel = topTunnel;

                if (legacy.length && tunnel.length) {
                    [XFTunnelV2Config
                        rememberTunnelBundleId:tunnel
                        forLegacyBundleId:legacy];
                }
            }
        }];
}

- (void)xf2_fetchManifestWithCompletion:
    (void (^)(NSDictionary *dictionary, NSError *error))completion {

    if (!self.game.length) {
        if (completion) {
            completion(
                nil,
                XF2Error(
                    3110,
                    @"No se pudo determinar el juego."
                )
            );
        }
        return;
    }

    NSString *encodedGame =
        [self.game
            stringByAddingPercentEncodingWithAllowedCharacters:
                NSCharacterSet.URLQueryAllowedCharacterSet];

    NSString *base = [self apiBaseURL] ?: @"";

    NSString *urlString =
        [NSString
            stringWithFormat:
                @"%@/api/app/options?game=%@",
                base,
                encodedGame ?: @""];

    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        if (completion) {
            completion(
                nil,
                XF2Error(
                    3111,
                    @"La URL del manifiesto no es válida."
                )
            );
        }
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20.0;

    [LicenseValidator
        authorizeRequest:request
        completion:^(BOOL authorized) {
            if (!authorized) {
                if (completion) {
                    completion(
                        nil,
                        XF2Error(
                            3112,
                            @"Licencia no autorizada."
                        )
                    );
                }
                return;
            }

            NSURLSessionDataTask *task =
                [NSURLSession.sharedSession
                    dataTaskWithRequest:request
                    completionHandler:^(
                        NSData *data,
                        NSURLResponse *response,
                        NSError *error
                    ) {
                        [LicenseValidator
                            handleProtectedHTTPResponse:
                                response];

                        NSHTTPURLResponse *http =
                            [response
                                isKindOfClass:
                                    NSHTTPURLResponse.class]
                                ? (NSHTTPURLResponse *)response
                                : nil;

                        if (error ||
                            !data.length ||
                            !http ||
                            http.statusCode < 200 ||
                            http.statusCode > 299) {
                            if (completion) {
                                completion(
                                    nil,
                                    error ?:
                                    XF2Error(
                                        3113,
                                        @"No se pudo cargar el manifiesto."
                                    )
                                );
                            }
                            return;
                        }

                        NSError *jsonError = nil;

                        id json =
                            [NSJSONSerialization
                                JSONObjectWithData:data
                                options:0
                                error:&jsonError];

                        if (jsonError ||
                            ![json
                                isKindOfClass:
                                    NSDictionary.class]) {
                            if (completion) {
                                completion(
                                    nil,
                                    jsonError ?:
                                    XF2Error(
                                        3114,
                                        @"El manifiesto no es válido."
                                    )
                                );
                            }
                            return;
                        }

                        NSDictionary *dictionary =
                            (NSDictionary *)json;

                        NSNumber *ok =
                            [dictionary[@"ok"]
                                isKindOfClass:
                                    NSNumber.class]
                                ? dictionary[@"ok"]
                                : nil;

                        if (!ok.boolValue) {
                            if (completion) {
                                completion(
                                    nil,
                                    XF2Error(
                                        3115,
                                        @"El servidor rechazó el manifiesto."
                                    )
                                );
                            }
                            return;
                        }

                        if (completion) {
                            completion(
                                dictionary,
                                nil
                            );
                        }
                    }];

            [task resume];
        }];
}

- (NSDictionary *)xf2_findRawOption:
    (NSArray *)rawOptions
    optionId:
    (NSNumber *)optionId {

    if (!optionId) return nil;

    for (id value in rawOptions) {
        if (![value
                isKindOfClass:
                    NSDictionary.class]) {
            continue;
        }

        NSDictionary *raw =
            (NSDictionary *)value;

        NSNumber *rawId =
            [raw[@"id"]
                isKindOfClass:NSNumber.class]
                ? raw[@"id"]
                : nil;

        if (rawId &&
            rawId.longLongValue ==
                optionId.longLongValue) {
            return raw;
        }
    }

    return nil;
}

- (NSArray<NSDictionary *> *)xf2_fileItemsFromRawOption:
    (NSDictionary *)raw
    fallbackRoute:
    (NSString *)fallbackRoute {

    NSMutableArray<NSDictionary *> *items =
        [NSMutableArray array];

    NSString *baseRoute =
        [raw[@"route"]
            isKindOfClass:NSString.class]
            ? raw[@"route"]
            : fallbackRoute;

    NSArray *serverFiles =
        [raw[@"files"]
            isKindOfClass:NSArray.class]
            ? raw[@"files"]
            : nil;

    for (id value in serverFiles ?: @[]) {
        if (![value
                isKindOfClass:
                    NSDictionary.class]) {
            continue;
        }

        NSDictionary *row =
            (NSDictionary *)value;

        NSString *name =
            [row[@"fileName"]
                isKindOfClass:NSString.class]
                ? row[@"fileName"]
                : nil;

        NSString *url =
            [row[@"fileUrl"]
                isKindOfClass:NSString.class]
                ? row[@"fileUrl"]
                : nil;

        NSString *route =
            [row[@"route"]
                isKindOfClass:NSString.class]
                ? row[@"route"]
                : baseRoute;

        if (name.length &&
            url.length &&
            route.length) {
            [items
                addObject:@{
                    @"fileName": name,
                    @"fileUrl": url,
                    @"route": route
                }];
        }
    }

    if (items.count) return [items copy];

    NSString *name1 =
        [raw[@"fileName"]
            isKindOfClass:NSString.class]
            ? raw[@"fileName"]
            : nil;

    NSString *url1 =
        [raw[@"fileUrl"]
            isKindOfClass:NSString.class]
            ? raw[@"fileUrl"]
            : nil;

    if (name1.length &&
        url1.length &&
        baseRoute.length) {
        [items
            addObject:@{
                @"fileName": name1,
                @"fileUrl": url1,
                @"route": baseRoute
            }];
    }

    NSString *name2 =
        [raw[@"file2Name"]
            isKindOfClass:NSString.class]
            ? raw[@"file2Name"]
            : nil;

    NSString *url2 =
        [raw[@"file2Url"]
            isKindOfClass:NSString.class]
            ? raw[@"file2Url"]
            : nil;

    NSString *route2 =
        [raw[@"file2Route"]
            isKindOfClass:NSString.class]
            ? raw[@"file2Route"]
            : baseRoute;

    if (name2.length &&
        url2.length &&
        route2.length) {
        [items
            addObject:@{
                @"fileName": name2,
                @"fileUrl": url2,
                @"route": route2
            }];
    }

    return [items copy];
}

- (void)xf2_fail:(NSString *)message {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            [self
                showResult:
                    message ?:
                    @"No se pudieron aplicar los archivos."
                success:NO];
        });
}

- (void)xf2_applyItems:
    (NSArray<NSDictionary *> *)items
    index:
    (NSUInteger)index
    legacyBundleID:
    (NSString *)legacyBundleID {

    if (index >= items.count) {
        NSString *message =
            items.count > 1
                ? @"Los archivos fueron agregados y verificados correctamente."
                : @"Archivo agregado y verificado correctamente.";

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                [self
                    showResult:message
                    success:YES];
            });

        return;
    }

    NSDictionary *item = items[index];

    NSString *fileName =
        [item[@"fileName"]
            isKindOfClass:NSString.class]
            ? item[@"fileName"]
            : nil;

    NSString *fileUrl =
        [item[@"fileUrl"]
            isKindOfClass:NSString.class]
            ? item[@"fileUrl"]
            : nil;

    NSString *route =
        [item[@"route"]
            isKindOfClass:NSString.class]
            ? item[@"route"]
            : nil;

    if (!fileName.length ||
        !fileUrl.length ||
        !route.length) {
        [self
            xf2_fail:
                @"Uno de los archivos tiene una configuración incompleta."];
        return;
    }

    XITForgeOption *destinationOption =
        [[XITForgeOption alloc] init];

    destinationOption.bundleId = legacyBundleID;
    destinationOption.route = route;
    destinationOption.fileName = fileName;

    NSString *resolveError = nil;

    NSURL *destinationURL =
        [self
            destinationURLForOption:
                destinationOption
            error:&resolveError];

    NSURL *downloadURL =
        [self
            absoluteServerURLForString:
                fileUrl];

    if (!downloadURL) {
        [self
            xf2_fail:
                @"La URL de uno de los archivos no es válida."];
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                downloadURL];

    request.HTTPMethod = @"GET";
    request.timeoutInterval = 60.0;

    __weak typeof(self) weakSelf = self;

    [LicenseValidator
        authorizeRequest:request
        completion:^(BOOL authorized) {
            if (!authorized) {
                [self
                    xf2_fail:
                        @"Licencia no autorizada. Inicia sesión nuevamente."];
                return;
            }

            NSURLSessionDownloadTask *task =
                [NSURLSession.sharedSession
                    downloadTaskWithRequest:request
                    completionHandler:^(
                        NSURL *location,
                        NSURLResponse *response,
                        NSError *error
                    ) {
                        __strong typeof(weakSelf) strongSelf =
                            weakSelf;

                        if (!strongSelf) return;

                        [LicenseValidator
                            handleProtectedHTTPResponse:
                                response];

                        NSHTTPURLResponse *http =
                            [response
                                isKindOfClass:
                                    NSHTTPURLResponse.class]
                                ? (NSHTTPURLResponse *)response
                                : nil;

                        if (error ||
                            !location ||
                            !http ||
                            http.statusCode < 200 ||
                            http.statusCode > 299) {
                            [strongSelf
                                xf2_fail:
                                    @"No se pudo descargar uno de los archivos."];
                            return;
                        }

                        NSString *localFailure =
                            resolveError;

                        if (destinationURL && ![XITForgeFileEngine tunnelReadyForHome]) {
                            NSError *writeError = nil;

                            BOOL written =
                                XF2WriteExactFile(
                                    location,
                                    destinationURL,
                                    &writeError
                                );

                            if (written) {
                                NSError *verifyError = nil;

                                BOOL verified =
                                    XF2FilesAreIdentical(
                                        location,
                                        destinationURL,
                                        &verifyError
                                    );

                                if (verified) {
                                    NSLog(
                                        @"XITFORGE TWO FILES: local %@ -> %@",
                                        fileName,
                                        destinationURL.path
                                    );

                                    dispatch_async(
                                        dispatch_get_main_queue(),
                                        ^{
                                            [strongSelf
                                                xf2_applyItems:
                                                    items
                                                index:
                                                    index + 1
                                                legacyBundleID:
                                                    legacyBundleID];
                                        });

                                    return;
                                }

                                localFailure =
                                    verifyError.localizedDescription ?:
                                    @"La escritura local no quedó verificada.";
                            } else {
                                localFailure =
                                    writeError.localizedDescription ?:
                                    @"El acceso local no pudo escribir el archivo.";
                            }
                        }

                        if (![XITForgeFileEngine
                                tunnelFallbackConfigured]) {
                            [strongSelf
                                xf2_fail:
                                    localFailure.length
                                        ? [NSString
                                            stringWithFormat:
                                                @"%@ El Túnel no está disponible.",
                                                localFailure]
                                        : @"No se pudo aplicar el archivo y el Túnel no está disponible."];
                            return;
                        }

                        [XITForgeFileEngine
                            replaceFileViaTunnelFromURL:
                                location
                            bundleID:
                                legacyBundleID
                            route:
                                route
                            fileName:
                                fileName
                            completion:
                                ^(
                                    BOOL success,
                                    NSString *message
                                ) {
                                    if (!success) {
                                        [strongSelf
                                            xf2_fail:
                                                message ?:
                                                @"El Túnel no pudo aplicar el archivo."];
                                        return;
                                    }

                                    NSLog(
                                        @"XITFORGE TWO FILES: Tunnel V2 %@",
                                        fileName
                                    );

                                    [strongSelf
                                        xf2_applyItems:
                                            items
                                        index:
                                            index + 1
                                        legacyBundleID:
                                            legacyBundleID];
                                }];
                    }];

            [task resume];
        }];
}

- (void)xf2_applyOption:(XITForgeOption *)option {
    if (!option ||
        !option.optionId ||
        !self.game.length) {
        // Después del swizzle llama al applyOption: original.
        [self xf2_applyOption:option];
        return;
    }

    __weak typeof(self) weakSelf = self;

    [self
        xf2_fetchManifestWithCompletion:
            ^(
                NSDictionary *dictionary,
                NSError *error
            ) {
                __strong typeof(weakSelf) strongSelf =
                    weakSelf;

                if (!strongSelf) return;

                if (error || !dictionary) {
                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            [strongSelf
                                xf2_applyOption:
                                    option];
                        });
                    return;
                }

                NSArray *rawOptions =
                    [dictionary[@"options"]
                        isKindOfClass:NSArray.class]
                        ? dictionary[@"options"]
                        : nil;

                NSDictionary *raw =
                    [strongSelf
                        xf2_findRawOption:
                            rawOptions
                        optionId:
                            option.optionId];

                if (!raw) {
                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            [strongSelf
                                xf2_applyOption:
                                    option];
                        });
                    return;
                }

                NSString *legacyBundleID =
                    [raw[@"bundleId"]
                        isKindOfClass:NSString.class]
                        ? raw[@"bundleId"]
                        : (option.bundleId.length
                            ? option.bundleId
                            : strongSelf.bundleId);

                NSString *tunnelBundleID =
                    [XFTunnelV2Config
                        tunnelBundleIdFromOptionDictionary:
                            raw];

                if (!tunnelBundleID.length) {
                    tunnelBundleID =
                        [XFTunnelV2Config
                            tunnelBundleIdFromOptionDictionary:
                                dictionary];
                }

                if (legacyBundleID.length &&
                    tunnelBundleID.length) {
                    [XFTunnelV2Config
                        rememberTunnelBundleId:
                            tunnelBundleID
                        forLegacyBundleId:
                            legacyBundleID];
                }

                NSString *fallbackRoute =
                    [raw[@"route"]
                        isKindOfClass:NSString.class]
                        ? raw[@"route"]
                        : option.route;

                NSArray<NSDictionary *> *items =
                    [strongSelf
                        xf2_fileItemsFromRawOption:
                            raw
                        fallbackRoute:
                            fallbackRoute];

                if (!items.count) {
                    [strongSelf
                        xf2_fail:
                            @"Esta opción no tiene archivos configurados."];
                    return;
                }

                if (!legacyBundleID.length) {
                    [strongSelf
                        xf2_fail:
                            @"No se pudo determinar el bundleId legacy de la opción."];
                    return;
                }

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        [strongSelf
                            xf2_applyItems:
                                items
                            index:0
                            legacyBundleID:
                                legacyBundleID];
                    });
            }];
}

@end
