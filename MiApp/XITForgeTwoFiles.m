#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>
#import <string.h>

/*
 * XITFORGE - SOPORTE DE DOS ARCHIVOS POR OPCIÓN
 *
 * Este archivo se AGREGA a MiApp/.
 * No reemplaza HomeViewController.m.
 *
 * Objetivo:
 * - Mantener intacta toda la lógica actual.
 * - Cuando ACTIVAR reciba 2 archivos para una opción,
 *   descargar, escribir y verificar ambos.
 * - Marcar la opción como activada solamente después
 *   de que todos sus archivos terminen correctamente.
 */


#pragma mark - Clases existentes

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


#pragma mark - Escritura exacta

static BOOL XF2WriteExactFile(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSError **errorOut
) {
    NSString *sourcePath =
        sourceURL.path;

    NSString *destinationPath =
        destinationURL.path;

    if (
        sourcePath.length == 0 ||
        destinationPath.length == 0
    ) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:@"XITFORGE_TWO_FILES"
                    code:3001
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"Ruta de origen o destino vacía."
                    }
                ];
        }

        return NO;
    }


    const char *src =
        sourcePath.fileSystemRepresentation;

    const char *dst =
        destinationPath.fileSystemRepresentation;


    struct stat dstInfo;

    if (
        lstat(
            dst,
            &dstInfo
        ) == 0
    ) {

        if (
            S_ISDIR(
                dstInfo.st_mode
            )
        ) {
            if (errorOut) {
                *errorOut =
                    [NSError
                        errorWithDomain:@"XITFORGE_TWO_FILES"
                        code:3002
                        userInfo:@{
                            NSLocalizedDescriptionKey:
                                @"El destino es una carpeta."
                        }
                    ];
            }

            return NO;
        }


        if (
            S_ISLNK(
                dstInfo.st_mode
            )
        ) {
            if (errorOut) {
                *errorOut =
                    [NSError
                        errorWithDomain:@"XITFORGE_TWO_FILES"
                        code:3003
                        userInfo:@{
                            NSLocalizedDescriptionKey:
                                @"El destino es un enlace simbólico."
                        }
                    ];
            }

            return NO;
        }


        if (
            !S_ISREG(
                dstInfo.st_mode
            )
        ) {
            if (errorOut) {
                *errorOut =
                    [NSError
                        errorWithDomain:@"XITFORGE_TWO_FILES"
                        code:3004
                        userInfo:@{
                            NSLocalizedDescriptionKey:
                                @"El destino no es un archivo normal."
                        }
                    ];
            }

            return NO;
        }

    } else if (
        errno != ENOENT
    ) {

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:errno
                    userInfo:nil
                ];
        }

        return NO;
    }


    int inFD =
        open(
            src,
            O_RDONLY |
            O_CLOEXEC
        );


    if (
        inFD < 0
    ) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:errno
                    userInfo:nil
                ];
        }

        return NO;
    }


    int flags =
        O_WRONLY |
        O_CREAT |
        O_TRUNC |
        O_CLOEXEC;

#ifdef O_NOFOLLOW
    flags |=
        O_NOFOLLOW;
#endif


    int outFD =
        open(
            dst,
            flags,
            0644
        );


    if (
        outFD < 0
    ) {

        int saved =
            errno;

        close(
            inFD
        );

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:saved
                    userInfo:nil
                ];
        }

        return NO;
    }


    BOOL ok =
        YES;

    int savedErrno =
        0;

    unsigned char buffer[
        256 * 1024
    ];


    for (;;) {

        ssize_t bytesRead =
            read(
                inFD,
                buffer,
                sizeof(buffer)
            );


        if (
            bytesRead == 0
        ) {
            break;
        }


        if (
            bytesRead < 0
        ) {

            if (
                errno == EINTR
            ) {
                continue;
            }

            ok =
                NO;

            savedErrno =
                errno;

            break;
        }


        ssize_t writtenTotal =
            0;


        while (
            writtenTotal <
            bytesRead
        ) {

            ssize_t bytesWritten =
                write(
                    outFD,
                    buffer +
                        writtenTotal,
                    (size_t)(
                        bytesRead -
                        writtenTotal
                    )
                );


            if (
                bytesWritten < 0
            ) {

                if (
                    errno == EINTR
                ) {
                    continue;
                }

                ok =
                    NO;

                savedErrno =
                    errno;

                break;
            }


            writtenTotal +=
                bytesWritten;
        }


        if (!ok) {
            break;
        }
    }


    if (
        ok &&
        fsync(
            outFD
        ) != 0
    ) {
        ok =
            NO;

        savedErrno =
            errno;
    }


    close(
        outFD
    );

    close(
        inFD
    );


    if (!ok) {

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:savedErrno
                    userInfo:nil
                ];
        }

        return NO;
    }


    return YES;
}


#pragma mark - Verificación exacta

static BOOL XF2FilesAreIdentical(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSError **errorOut
) {

    const char *src =
        sourceURL.path
            .fileSystemRepresentation;

    const char *dst =
        destinationURL.path
            .fileSystemRepresentation;


    int inFD =
        open(
            src,
            O_RDONLY |
            O_CLOEXEC
        );


    if (
        inFD < 0
    ) {

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:errno
                    userInfo:nil
                ];
        }

        return NO;
    }


    int outFD =
        open(
            dst,
            O_RDONLY |
            O_CLOEXEC
        );


    if (
        outFD < 0
    ) {

        int saved =
            errno;

        close(
            inFD
        );

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:saved
                    userInfo:nil
                ];
        }

        return NO;
    }


    struct stat srcInfo = {0};
    struct stat dstInfo = {0};


    if (
        fstat(
            inFD,
            &srcInfo
        ) != 0 ||
        fstat(
            outFD,
            &dstInfo
        ) != 0
    ) {

        int saved =
            errno;

        close(
            inFD
        );

        close(
            outFD
        );

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:saved
                    userInfo:nil
                ];
        }

        return NO;
    }


    if (
        !S_ISREG(
            srcInfo.st_mode
        ) ||
        !S_ISREG(
            dstInfo.st_mode
        ) ||
        srcInfo.st_size !=
            dstInfo.st_size
    ) {

        close(
            inFD
        );

        close(
            outFD
        );

        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:@"XITFORGE_TWO_FILES"
                    code:3101
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"El archivo final no coincide en tamaño."
                    }
                ];
        }

        return NO;
    }


    unsigned char left[
        256 * 1024
    ];

    unsigned char right[
        256 * 1024
    ];

    BOOL identical =
        YES;

    int savedErrno =
        0;


    for (;;) {

        ssize_t l =
            -1;

        ssize_t r =
            -1;


        do {
            l =
                read(
                    inFD,
                    left,
                    sizeof(left)
                );
        } while (
            l < 0 &&
            errno == EINTR
        );


        if (
            l < 0
        ) {
            identical =
                NO;

            savedErrno =
                errno;

            break;
        }


        do {
            r =
                read(
                    outFD,
                    right,
                    sizeof(right)
                );
        } while (
            r < 0 &&
            errno == EINTR
        );


        if (
            r < 0
        ) {
            identical =
                NO;

            savedErrno =
                errno;

            break;
        }


        if (
            l != r
        ) {
            identical =
                NO;

            break;
        }


        if (
            l == 0
        ) {
            break;
        }


        if (
            memcmp(
                left,
                right,
                (size_t)l
            ) != 0
        ) {

            identical =
                NO;

            break;
        }
    }


    close(
        inFD
    );

    close(
        outFD
    );


    if (
        !identical &&
        errorOut
    ) {

        if (
            savedErrno != 0
        ) {
            *errorOut =
                [NSError
                    errorWithDomain:NSPOSIXErrorDomain
                    code:savedErrno
                    userInfo:nil
                ];
        } else {
            *errorOut =
                [NSError
                    errorWithDomain:@"XITFORGE_TWO_FILES"
                    code:3102
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"El contenido escrito no coincide con la descarga."
                    }
                ];
        }
    }


    return identical;
}


#pragma mark - Addon

@interface XITForgeOptionsViewController (XITForgeTwoFiles)

- (void)xf2_applyOption:
    (XITForgeOption *)option;

@end


@implementation XITForgeOptionsViewController (XITForgeTwoFiles)


+ (void)load {

    static dispatch_once_t onceToken;


    dispatch_once(
        &onceToken,
        ^{

            Class cls =
                NSClassFromString(
                    @"XITForgeOptionsViewController"
                );


            if (!cls) {
                return;
            }


            Method original =
                class_getInstanceMethod(
                    cls,
                    @selector(
                        applyOption:
                    )
                );


            Method replacement =
                class_getInstanceMethod(
                    cls,
                    @selector(
                        xf2_applyOption:
                    )
                );


            if (
                original &&
                replacement
            ) {
                method_exchangeImplementations(
                    original,
                    replacement
                );
            }
        }
    );
}


#pragma mark - Helpers

- (NSArray<NSDictionary *> *)xf2_fileItemsFromRawOption:
    (NSDictionary *)raw {

    NSMutableArray<NSDictionary *> *items =
        [NSMutableArray
            arrayWithCapacity:
                2
        ];


    NSArray *serverFiles =
        [raw[@"files"]
            isKindOfClass:
                [NSArray class]
        ]
            ? raw[@"files"]
            : nil;


    if (
        serverFiles.count > 0
    ) {

        for (
            id value
            in serverFiles
        ) {

            if (
                ![value
                    isKindOfClass:
                        [NSDictionary class]
                ]
            ) {
                continue;
            }


            NSDictionary *item =
                (NSDictionary *)value;


            NSString *fileName =
                [item[@"fileName"]
                    isKindOfClass:
                        [NSString class]
                ]
                    ? item[@"fileName"]
                    : nil;


            NSString *fileUrl =
                [item[@"fileUrl"]
                    isKindOfClass:
                        [NSString class]
                ]
                    ? item[@"fileUrl"]
                    : nil;


            if (
                fileName.length > 0 &&
                fileUrl.length > 0
            ) {

                [items
                    addObject:@{
                        @"fileName":
                            fileName,

                        @"fileUrl":
                            fileUrl
                    }
                ];
            }
        }


        if (
            items.count > 0
        ) {
            return
                [items copy];
        }
    }


    NSString *file1Name =
        [raw[@"fileName"]
            isKindOfClass:
                [NSString class]
        ]
            ? raw[@"fileName"]
            : nil;


    NSString *file1Url =
        [raw[@"fileUrl"]
            isKindOfClass:
                [NSString class]
        ]
            ? raw[@"fileUrl"]
            : nil;


    if (
        file1Name.length > 0 &&
        file1Url.length > 0
    ) {

        [items
            addObject:@{
                @"fileName":
                    file1Name,

                @"fileUrl":
                    file1Url
            }
        ];
    }


    NSString *file2Name =
        [raw[@"file2Name"]
            isKindOfClass:
                [NSString class]
        ]
            ? raw[@"file2Name"]
            : nil;


    NSString *file2Url =
        [raw[@"file2Url"]
            isKindOfClass:
                [NSString class]
        ]
            ? raw[@"file2Url"]
            : nil;


    if (
        file2Name.length > 0 &&
        file2Url.length > 0
    ) {

        [items
            addObject:@{
                @"fileName":
                    file2Name,

                @"fileUrl":
                    file2Url
            }
        ];
    }


    return
        [items copy];
}


- (NSDictionary *)xf2_findRawOption:
    (NSArray *)rawOptions
    optionId:
    (NSNumber *)optionId {

    if (
        optionId == nil
    ) {
        return nil;
    }


    for (
        id value
        in rawOptions
    ) {

        if (
            ![value
                isKindOfClass:
                    [NSDictionary class]
            ]
        ) {
            continue;
        }


        NSDictionary *raw =
            (NSDictionary *)value;


        NSNumber *rawId =
            [raw[@"id"]
                isKindOfClass:
                    [NSNumber class]
            ]
                ? raw[@"id"]
                : nil;


        if (
            rawId != nil &&
            rawId.longLongValue ==
                optionId.longLongValue
        ) {
            return raw;
        }
    }


    return nil;
}


- (void)xf2_fail:
    (NSString *)message {

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            [self
                showResult:
                    message ?:
                    @"No se pudieron aplicar los archivos."
                success:
                    NO
            ];
        }
    );
}


#pragma mark - Aplicar secuencia

- (void)xf2_applyItems:
    (NSArray<NSDictionary *> *)items
    index:
    (NSUInteger)index
    option:
    (XITForgeOption *)option {

    if (
        index >=
        items.count
    ) {

        NSString *message =
            items.count > 1
                ? @"Los 2 archivos fueron agregados y verificados correctamente."
                : @"Archivo agregado y verificado correctamente.";


        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                [self
                    showResult:
                        message
                    success:
                        YES
                ];
            }
        );

        return;
    }


    NSDictionary *item =
        items[index];


    NSString *fileName =
        [item[@"fileName"]
            isKindOfClass:
                [NSString class]
        ]
            ? item[@"fileName"]
            : nil;


    NSString *fileUrl =
        [item[@"fileUrl"]
            isKindOfClass:
                [NSString class]
        ]
            ? item[@"fileUrl"]
            : nil;


    if (
        fileName.length == 0 ||
        fileUrl.length == 0
    ) {

        [self
            xf2_fail:
                @"Uno de los archivos de esta opción está incompleto."
        ];

        return;
    }


    XITForgeOption *destinationOption =
        [[XITForgeOption alloc]
            init
        ];


    destinationOption.bundleId =
        option.bundleId;

    destinationOption.route =
        option.route;

    destinationOption.fileName =
        fileName;


    NSString *resolveError =
        nil;


    NSURL *destinationURL =
        [self
            destinationURLForOption:
                destinationOption
            error:
                &resolveError
        ];


    if (!destinationURL) {

        [self
            xf2_fail:
                resolveError ?:
                @"No se pudo resolver la ruta del archivo."
        ];

        return;
    }


    NSURL *downloadURL =
        [self
            absoluteServerURLForString:
                fileUrl
        ];


    if (!downloadURL) {

        [self
            xf2_fail:
                @"La URL de uno de los archivos no es válida."
        ];

        return;
    }


    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                downloadURL
        ];


    request.HTTPMethod =
        @"GET";

    request.timeoutInterval =
        60.0;


    __weak typeof(self) weakSelf =
        self;


    NSURLSessionDownloadTask *task =
        [[NSURLSession sharedSession]
            downloadTaskWithRequest:
                request

            completionHandler:
                ^(
                    NSURL * _Nullable location,
                    NSURLResponse * _Nullable response,
                    NSError * _Nullable error
                ) {

                    __strong typeof(weakSelf) strongSelf =
                        weakSelf;


                    if (!strongSelf) {
                        return;
                    }


                    NSHTTPURLResponse *http =
                        [response
                            isKindOfClass:
                                [NSHTTPURLResponse class]
                        ]
                            ? (NSHTTPURLResponse *)response
                            : nil;


                    BOOL httpOK =
                        !http ||
                        (
                            http.statusCode >= 200 &&
                            http.statusCode <= 299
                        );


                    if (
                        error ||
                        !location ||
                        !httpOK
                    ) {

                        [strongSelf
                            xf2_fail:
                                @"No se pudo descargar uno de los archivos."
                        ];

                        return;
                    }


                    NSError *writeError =
                        nil;


                    BOOL written =
                        XF2WriteExactFile(
                            location,
                            destinationURL,
                            &writeError
                        );


                    if (!written) {

                        NSString *message =
                            writeError.localizedDescription.length > 0
                                ? [NSString
                                    stringWithFormat:
                                        @"No se pudo agregar %@. %@",
                                        fileName,
                                        writeError.localizedDescription
                                  ]
                                : [NSString
                                    stringWithFormat:
                                        @"No se pudo agregar %@.",
                                        fileName
                                  ];


                        [strongSelf
                            xf2_fail:
                                message
                        ];

                        return;
                    }


                    NSError *verifyError =
                        nil;


                    BOOL verified =
                        XF2FilesAreIdentical(
                            location,
                            destinationURL,
                            &verifyError
                        );


                    if (!verified) {

                        NSString *message =
                            verifyError.localizedDescription.length > 0
                                ? [NSString
                                    stringWithFormat:
                                        @"%@ se escribió, pero no quedó verificado. %@",
                                        fileName,
                                        verifyError.localizedDescription
                                  ]
                                : [NSString
                                    stringWithFormat:
                                        @"%@ se escribió, pero no quedó verificado.",
                                        fileName
                                  ];


                        [strongSelf
                            xf2_fail:
                                message
                        ];

                        return;
                    }


                    NSLog(
                        @"XITFORGE TWO FILES: aplicado %@ -> %@",
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
                                option:
                                    option
                            ];
                        }
                    );
                }
        ];


    [task resume];
}


#pragma mark - Método que sustituye applyOption:

- (void)xf2_applyOption:
    (XITForgeOption *)option {

    if (
        !option ||
        option.optionId == nil ||
        self.game.length == 0
    ) {

        /*
         * Después del swizzle, este selector llama
         * al applyOption: ORIGINAL.
         */
        [self
            xf2_applyOption:
                option
        ];

        return;
    }


    NSString *encodedGame =
        [self.game
            stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet
                    URLQueryAllowedCharacterSet]
        ];


    NSString *base =
        [self apiBaseURL] ?:
        @"";


    NSString *manifestString =
        [NSString
            stringWithFormat:
                @"%@/api/app/options?game=%@",
                base,
                encodedGame ?:
                    @""
        ];


    NSURL *manifestURL =
        [NSURL
            URLWithString:
                manifestString
        ];


    if (!manifestURL) {

        [self
            xf2_applyOption:
                option
        ];

        return;
    }


    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                manifestURL
        ];


    request.HTTPMethod =
        @"GET";

    request.timeoutInterval =
        20.0;


    __weak typeof(self) weakSelf =
        self;


    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:
                request

            completionHandler:
                ^(
                    NSData * _Nullable data,
                    NSURLResponse * _Nullable response,
                    NSError * _Nullable error
                ) {

                    __strong typeof(weakSelf) strongSelf =
                        weakSelf;


                    if (!strongSelf) {
                        return;
                    }


                    NSHTTPURLResponse *http =
                        [response
                            isKindOfClass:
                                [NSHTTPURLResponse class]
                        ]
                            ? (NSHTTPURLResponse *)response
                            : nil;


                    BOOL httpOK =
                        !http ||
                        (
                            http.statusCode >= 200 &&
                            http.statusCode <= 299
                        );


                    if (
                        error ||
                        data.length == 0 ||
                        !httpOK
                    ) {

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                [strongSelf
                                    xf2_applyOption:
                                        option
                                ];
                            }
                        );

                        return;
                    }


                    NSError *jsonError =
                        nil;


                    id json =
                        [NSJSONSerialization
                            JSONObjectWithData:
                                data
                            options:
                                0
                            error:
                                &jsonError
                        ];


                    if (
                        jsonError ||
                        ![json
                            isKindOfClass:
                                [NSDictionary class]
                         ]
                    ) {

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                [strongSelf
                                    xf2_applyOption:
                                        option
                                ];
                            }
                        );

                        return;
                    }


                    NSDictionary *dictionary =
                        (NSDictionary *)json;


                    NSNumber *ok =
                        [dictionary[@"ok"]
                            isKindOfClass:
                                [NSNumber class]
                        ]
                            ? dictionary[@"ok"]
                            : nil;


                    NSArray *rawOptions =
                        [dictionary[@"options"]
                            isKindOfClass:
                                [NSArray class]
                        ]
                            ? dictionary[@"options"]
                            : nil;


                    if (
                        !ok.boolValue ||
                        !rawOptions
                    ) {

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                [strongSelf
                                    xf2_applyOption:
                                        option
                                ];
                            }
                        );

                        return;
                    }


                    NSDictionary *rawOption =
                        [strongSelf
                            xf2_findRawOption:
                                rawOptions
                            optionId:
                                option.optionId
                        ];


                    if (!rawOption) {

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                [strongSelf
                                    xf2_applyOption:
                                        option
                                ];
                            }
                        );

                        return;
                    }


                    NSArray<NSDictionary *> *items =
                        [strongSelf
                            xf2_fileItemsFromRawOption:
                                rawOption
                        ];


                    if (
                        items.count == 0
                    ) {

                        [strongSelf
                            xf2_fail:
                                @"Esta opción no tiene archivos configurados."
                        ];

                        return;
                    }


                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            [strongSelf
                                xf2_applyItems:
                                    items
                                index:
                                    0
                                option:
                                    option
                            ];
                        }
                    );
                }
        ];


    [task resume];
}

@end
