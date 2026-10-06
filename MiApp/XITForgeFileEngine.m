#import "XITForgeFileEngine.h"
#import "XFTunnelV2Config.h"
#import "LicenseValidator.h"
#import <objc/message.h>
#import <UIKit/UIKit.h>

static NSString * const XITForgeServerBaseURL =
    @"https://xitforge-license-server.onrender.com";

@implementation XITForgeFileEngine

+ (dispatch_queue_t)operationQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        queue =
            dispatch_queue_create(
                "com.xitforge.file-engine.tunnel-fallback",
                DISPATCH_QUEUE_SERIAL
            );
    });

    return queue;
}

+ (id)installedTunnelBackend {
    __block id backend = nil;

    void (^lookup)(void) = ^{
        id delegate =
            UIApplication.sharedApplication.delegate;

        SEL tabGetter =
            NSSelectorFromString(@"mainTabBar");

        if (![delegate respondsToSelector:tabGetter]) {
            return;
        }

        id candidate =
            ((id (*)(id, SEL))objc_msgSend)(
                delegate,
                tabGetter
            );

        if (![candidate
                isKindOfClass:
                    UITabBarController.class]) {
            return;
        }

        Class tunnelClass =
            NSClassFromString(
                @"XFAirLiftViewController"
            );

        if (!tunnelClass) {
            return;
        }

        for (
            UIViewController *entry
            in ((UITabBarController *)candidate).viewControllers ?: @[]
        ) {
            UIViewController *root = entry;

            if (
                [entry
                    isKindOfClass:
                        UINavigationController.class]
            ) {
                root =
                    ((UINavigationController *)entry)
                        .viewControllers
                        .firstObject;
            }

            if (![root isKindOfClass:tunnelClass]) {
                continue;
            }

            SEL backendGetter =
                NSSelectorFromString(@"backend");

            if ([root respondsToSelector:backendGetter]) {
                backend =
                    ((id (*)(id, SEL))objc_msgSend)(
                        root,
                        backendGetter
                    );
            }

            if (backend) {
                break;
            }
        }
    };

    if (NSThread.isMainThread) {
        lookup();
    } else {
        dispatch_sync(
            dispatch_get_main_queue(),
            lookup
        );
    }

    return backend;
}

+ (id)sharedTunnelBackend {
    id backend =
        [self installedTunnelBackend];

    if (backend) {
        return backend;
    }

    Class backendClass =
        NSClassFromString(@"XFAirLiftBackend");

    SEL selector =
        NSSelectorFromString(@"sharedBackend");

    if (
        !backendClass ||
        ![backendClass
            respondsToSelector:
                selector]
    ) {
        return nil;
    }

    return
        ((id (*)(id, SEL))objc_msgSend)(
            backendClass,
            selector
        );
}

+ (BOOL)boolGetter:(SEL)selector
            object:(id)object {
    if (
        !object ||
        ![object respondsToSelector:selector]
    ) {
        return NO;
    }

    return
        ((BOOL (*)(id, SEL))objc_msgSend)(
            object,
            selector
        );
}

+ (BOOL)tunnelFallbackConfigured {
    return
        [self sharedTunnelBackend] != nil;
}

#pragma mark - Path helpers

+ (BOOL)isSafeComponent:(NSString *)component {
    if (
        ![component
            isKindOfClass:
                NSString.class] ||
        component.length == 0
    ) {
        return NO;
    }

    if (
        [component
            isEqualToString:
                @"."] ||
        [component
            isEqualToString:
                @".."]
    ) {
        return NO;
    }

    if (
        [component
            containsString:
                @"/"] ||
        [component
            containsString:
                @"\\"]
    ) {
        return NO;
    }

    NSString *nul =
        [NSString
            stringWithFormat:
                @"%C",
                (unichar)0];

    return
        [component
            rangeOfString:
                nul]
            .location ==
        NSNotFound;
}

+ (NSString *)normalizedRootComponent:
    (NSString *)component {

    NSString *lower =
        component.lowercaseString;

    if ([lower isEqualToString:@"documents"]) {
        return @"Documents";
    }

    if ([lower isEqualToString:@"library"]) {
        return @"Library";
    }

    if ([lower isEqualToString:@"systemdata"]) {
        return @"SystemData";
    }

    if ([lower isEqualToString:@"tmp"]) {
        return @"tmp";
    }

    return component;
}

+ (NSString *)relativePathForRoute:
    (NSString *)route
    fileName:
    (NSString *)fileName
    error:
    (NSString **)errorOut {

    if (errorOut) {
        *errorOut = nil;
    }

    if (![self isSafeComponent:fileName]) {
        if (errorOut) {
            *errorOut =
                @"El nombre del archivo no es válido.";
        }

        return nil;
    }

    NSString *cleanRoute =
        [route
            isKindOfClass:
                NSString.class]
            ? [route
                stringByTrimmingCharactersInSet:
                    NSCharacterSet
                        .whitespaceAndNewlineCharacterSet]
            : @"";

    cleanRoute =
        [cleanRoute
            stringByReplacingOccurrencesOfString:
                @"\\"
            withString:
                @"/"];

    while ([cleanRoute hasPrefix:@"/"]) {
        cleanRoute =
            [cleanRoute
                substringFromIndex:
                    1];
    }

    while (
        [cleanRoute hasSuffix:@"/"] &&
        cleanRoute.length > 0
    ) {
        cleanRoute =
            [cleanRoute
                substringToIndex:
                    cleanRoute.length - 1];
    }

    if (cleanRoute.length == 0) {
        if (errorOut) {
            *errorOut =
                @"La ruta configurada está vacía.";
        }

        return nil;
    }

    NSMutableArray<NSString *> *parts =
        [NSMutableArray array];

    NSUInteger logicalIndex = 0;

    for (
        NSString *raw
        in [cleanRoute
            componentsSeparatedByString:
                @"/"]
    ) {
        NSString *component =
            [raw
                stringByTrimmingCharactersInSet:
                    NSCharacterSet
                        .whitespaceAndNewlineCharacterSet];

        if (component.length == 0) {
            continue;
        }

        if (logicalIndex == 0) {
            component =
                [self
                    normalizedRootComponent:
                        component];
        }

        if (![self isSafeComponent:component]) {
            if (errorOut) {
                *errorOut =
                    [NSString
                        stringWithFormat:
                            @"La ruta contiene un componente inválido: %@",
                            component];
            }

            return nil;
        }

        [parts addObject:component];
        logicalIndex++;
    }

    if (parts.count == 0) {
        if (errorOut) {
            *errorOut =
                @"La ruta no contiene ninguna carpeta válida.";
        }

        return nil;
    }

    [parts addObject:fileName];

    return
        [parts
            componentsJoinedByString:
                @"/"];
}

+ (NSString *)normalizedRouteOnly:(NSString *)route {
    if (![route isKindOfClass:NSString.class]) {
        return @"";
    }

    NSString *value =
        [route
            stringByTrimmingCharactersInSet:
                NSCharacterSet
                    .whitespaceAndNewlineCharacterSet];

    value =
        [value
            stringByReplacingOccurrencesOfString:
                @"\\"
            withString:
                @"/"];

    while ([value hasPrefix:@"/"]) {
        value =
            [value
                substringFromIndex:
                    1];
    }

    while (
        [value hasSuffix:@"/"] &&
        value.length > 0
    ) {
        value =
            [value
                substringToIndex:
                    value.length - 1];
    }

    return value.lowercaseString;
}

#pragma mark - Tunnel ready

+ (BOOL)ensureTunnelReady:
    (id)backend
    error:
    (NSError **)errorOut {

    if (!backend) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:
                        @"XITFORGE.FileEngine"
                    code:
                        5001
                    userInfo:
                        @{
                            NSLocalizedDescriptionKey:
                                @"El módulo Túnel no está cargado."
                        }];
        }

        return NO;
    }

    if (
        ![self
            boolGetter:
                NSSelectorFromString(
                    @"hasPairingRecord"
                )
            object:
                backend]
    ) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:
                        @"XITFORGE.FileEngine"
                    code:
                        5002
                    userInfo:
                        @{
                            NSLocalizedDescriptionKey:
                                @"El Túnel todavía no tiene un pairing válido."
                        }];
        }

        return NO;
    }

    if (
        [self
            boolGetter:
                NSSelectorFromString(
                    @"connected"
                )
            object:
                backend]
    ) {
        return YES;
    }

    SEL connectSelector =
        NSSelectorFromString(
            @"connectWithError:"
        );

    if (
        ![backend
            respondsToSelector:
                connectSelector]
    ) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:
                        @"XITFORGE.FileEngine"
                    code:
                        5003
                    userInfo:
                        @{
                            NSLocalizedDescriptionKey:
                                @"El módulo Túnel no expone la conexión esperada."
                        }];
        }

        return NO;
    }

    NSError *connectError = nil;

    BOOL connected =
        ((BOOL (*)
            (id, SEL, NSError **))
            objc_msgSend)(
                backend,
                connectSelector,
                &connectError
            );

    if (
        !connected &&
        errorOut
    ) {
        *errorOut =
            connectError ?:
            [NSError
                errorWithDomain:
                    @"XITFORGE.FileEngine"
                code:
                    5004
                userInfo:
                    @{
                        NSLocalizedDescriptionKey:
                            @"No se pudo reconectar el Túnel."
                    }];
    }

    return connected;
}

#pragma mark - Tunnel Bundle ID auto resolver

+ (NSString *)gameForLegacyBundleID:
    (NSString *)bundleID {

    NSString *value =
        [bundleID
            isKindOfClass:
                NSString.class]
            ? bundleID.lowercaseString
            : @"";

    if (
        [value
            isEqualToString:
                @"com.dts.freefireth"]
    ) {
        return @"freefire_normal";
    }

    if (
        [value
            isEqualToString:
                @"com.dts.freefiremax"]
    ) {
        return @"freefire_max";
    }

    return nil;
}

+ (BOOL)rawOption:
    (NSDictionary *)raw
    matchesRoute:
    (NSString *)route
    fileName:
    (NSString *)fileName {

    if (![raw isKindOfClass:NSDictionary.class]) {
        return NO;
    }

    NSString *wantedRoute =
        [self normalizedRouteOnly:route];

    NSString *rawRoute =
        [self
            normalizedRouteOnly:
                [raw[@"route"]
                    isKindOfClass:
                        NSString.class]
                    ? raw[@"route"]
                    : @""];

    if (
        wantedRoute.length &&
        rawRoute.length &&
        ![wantedRoute
            isEqualToString:
                rawRoute]
    ) {
        return NO;
    }

    NSString *wantedFile =
        [fileName
            isKindOfClass:
                NSString.class]
            ? fileName.lowercaseString
            : @"";

    if (!wantedFile.length) {
        return YES;
    }

    NSString *file1 =
        [raw[@"fileName"]
            isKindOfClass:
                NSString.class]
            ? [raw[@"fileName"]
                lowercaseString]
            : @"";

    if (
        file1.length &&
        [file1
            isEqualToString:
                wantedFile]
    ) {
        return YES;
    }

    NSString *file2 =
        [raw[@"file2Name"]
            isKindOfClass:
                NSString.class]
            ? [raw[@"file2Name"]
                lowercaseString]
            : @"";

    if (
        file2.length &&
        [file2
            isEqualToString:
                wantedFile]
    ) {
        return YES;
    }

    NSArray *files =
        [raw[@"files"]
            isKindOfClass:
                NSArray.class]
            ? raw[@"files"]
            : nil;

    for (id value in files ?: @[]) {
        if (![value
                isKindOfClass:
                    NSDictionary.class]) {
            continue;
        }

        NSString *name =
            [value[@"fileName"]
                isKindOfClass:
                    NSString.class]
                ? [value[@"fileName"]
                    lowercaseString]
                : @"";

        if (
            name.length &&
            [name
                isEqualToString:
                    wantedFile]
        ) {
            return YES;
        }
    }

    return NO;
}

+ (void)resolveTunnelBundleID:
    (NSString *)inputBundleID
    route:
    (NSString *)route
    fileName:
    (NSString *)fileName
    completion:
    (void (^)(NSString *bundleID, NSString *errorMessage))completion {

    if (
        ![inputBundleID
            isKindOfClass:
                NSString.class] ||
        inputBundleID.length == 0
    ) {
        if (completion) {
            completion(
                nil,
                @"Falta el bundle ID de la opción."
            );
        }

        return;
    }

    /*
     * Si ya tenemos un mapeo válido, usarlo.
     */
    NSString *cached =
        [XFTunnelV2Config
            tunnelBundleIdForLegacyBundleId:
                inputBundleID];

    if (cached.length) {
        NSLog(
            @"XITFORGE Tunnel V2 resolver: cache %@ -> %@",
            inputBundleID,
            cached
        );

        if (completion) {
            completion(cached, nil);
        }

        return;
    }

    /*
     * Si no es uno de los dos bundleId legacy conocidos,
     * se considera que el llamador ya pasó el tunnelBundleId.
     */
    NSString *game =
        [self
            gameForLegacyBundleID:
                inputBundleID];

    if (!game.length) {
        NSLog(
            @"XITFORGE Tunnel V2 resolver: bundle directo %@",
            inputBundleID
        );

        if (completion) {
            completion(
                inputBundleID,
                nil
            );
        }

        return;
    }

    NSString *encodedGame =
        [game
            stringByAddingPercentEncodingWithAllowedCharacters:
                NSCharacterSet
                    .URLQueryAllowedCharacterSet];

    NSString *urlString =
        [NSString
            stringWithFormat:
                @"%@/api/app/options?game=%@",
                XITForgeServerBaseURL,
                encodedGame ?: @""];

    NSURL *url =
        [NSURL
            URLWithString:
                urlString];

    if (!url) {
        if (completion) {
            completion(
                nil,
                @"No se pudo construir la URL para consultar tunnelBundleId."
            );
        }

        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                url];

    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20.0;

    [LicenseValidator
        authorizeRequest:
            request
        completion:
            ^(BOOL authorized) {

                if (!authorized) {
                    if (completion) {
                        completion(
                            nil,
                            @"No se pudo autorizar la consulta de tunnelBundleId."
                        );
                    }

                    return;
                }

                NSURLSessionDataTask *task =
                    [NSURLSession.sharedSession
                        dataTaskWithRequest:
                            request
                        completionHandler:
                            ^(
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

                                if (
                                    error ||
                                    !data.length ||
                                    !http ||
                                    http.statusCode < 200 ||
                                    http.statusCode > 299
                                ) {
                                    NSString *detail =
                                        error.localizedDescription ?:
                                        [NSString
                                            stringWithFormat:
                                                @"HTTP %@",
                                                http
                                                    ? @(http.statusCode)
                                                    : @"sin respuesta"];

                                    if (completion) {
                                        completion(
                                            nil,
                                            [NSString
                                                stringWithFormat:
                                                    @"No se pudo consultar tunnelBundleId. %@",
                                                    detail]
                                        );
                                    }

                                    return;
                                }

                                NSError *jsonError = nil;

                                id json =
                                    [NSJSONSerialization
                                        JSONObjectWithData:
                                            data
                                        options:
                                            0
                                        error:
                                            &jsonError];

                                if (
                                    jsonError ||
                                    ![json
                                        isKindOfClass:
                                            NSDictionary.class]
                                ) {
                                    if (completion) {
                                        completion(
                                            nil,
                                            @"El servidor devolvió una respuesta inválida al consultar tunnelBundleId."
                                        );
                                    }

                                    return;
                                }

                                NSDictionary *dictionary =
                                    (NSDictionary *)json;

                                NSArray *options =
                                    [dictionary[@"options"]
                                        isKindOfClass:
                                            NSArray.class]
                                        ? dictionary[@"options"]
                                        : nil;

                                NSLog(
                                    @"XITFORGE Tunnel V2 resolver: game=%@ rows=%lu route=%@ file=%@",
                                    game,
                                    (unsigned long)options.count,
                                    route ?: @"",
                                    fileName ?: @""
                                );

                                NSString *found = nil;

                                /*
                                 * 1) Coincidencia exacta de ruta + archivo.
                                 */
                                for (id value in options ?: @[]) {
                                    if (![value
                                            isKindOfClass:
                                                NSDictionary.class]) {
                                        continue;
                                    }

                                    NSDictionary *raw =
                                        (NSDictionary *)value;

                                    if (
                                        ![self
                                            rawOption:
                                                raw
                                            matchesRoute:
                                                route
                                            fileName:
                                                fileName]
                                    ) {
                                        continue;
                                    }

                                    NSString *candidate =
                                        [XFTunnelV2Config
                                            tunnelBundleIdFromOptionDictionary:
                                                raw];

                                    if (candidate.length) {
                                        found = candidate;
                                        break;
                                    }
                                }

                                /*
                                 * 2) Si no coincidió exactamente, usar un único
                                 *    tunnelBundleId no vacío del juego.
                                 */
                                if (!found.length) {
                                    NSMutableOrderedSet<NSString *> *unique =
                                        [NSMutableOrderedSet orderedSet];

                                    for (id value in options ?: @[]) {
                                        if (![value
                                                isKindOfClass:
                                                    NSDictionary.class]) {
                                            continue;
                                        }

                                        NSString *candidate =
                                            [XFTunnelV2Config
                                                tunnelBundleIdFromOptionDictionary:
                                                    value];

                                        if (candidate.length) {
                                            [unique addObject:candidate];
                                        }
                                    }

                                    if (unique.count == 1) {
                                        found = unique.firstObject;
                                    }
                                }

                                if (!found.length) {
                                    /*
                                     * Puede existir un valor superior en una
                                     * futura versión del endpoint.
                                     */
                                    found =
                                        [XFTunnelV2Config
                                            tunnelBundleIdFromOptionDictionary:
                                                dictionary];
                                }

                                if (!found.length) {
                                    if (completion) {
                                        completion(
                                            nil,
                                            [NSString
                                                stringWithFormat:
                                                    @"El servidor respondió, pero no envió tunnelBundleId para %@. "
                                                     "Verifica que Render esté desplegando la rama que guarda tunnel_bundle_id.",
                                                    game]
                                        );
                                    }

                                    return;
                                }

                                [XFTunnelV2Config
                                    rememberTunnelBundleId:
                                        found
                                    forLegacyBundleId:
                                        inputBundleID];

                                NSLog(
                                    @"XITFORGE Tunnel V2 resolver: RESUELTO %@ -> %@",
                                    inputBundleID,
                                    found
                                );

                                if (completion) {
                                    completion(
                                        found,
                                        nil
                                    );
                                }
                            }];

                [task resume];
            }];
}

#pragma mark - Replace

+ (void)replaceFileViaTunnelFromURL:
    (NSURL *)sourceURL
    bundleID:
    (NSString *)bundleID
    route:
    (NSString *)route
    fileName:
    (NSString *)fileName
    completion:
    (void (^)(BOOL, NSString *))completion {

    NSString *pathError = nil;

    NSString *relativePath =
        [self
            relativePathForRoute:
                route
            fileName:
                fileName
            error:
                &pathError];

    if (!relativePath.length) {
        if (completion) {
            completion(
                NO,
                pathError ?:
                    @"La ruta configurada no es válida."
            );
        }

        return;
    }

    /*
     * Copiar AHORA el temporal de URLSession.
     */
    NSError *readError = nil;

    NSData *data =
        [NSData
            dataWithContentsOfURL:
                sourceURL
            options:
                0
            error:
                &readError];

    if (!data) {
        if (completion) {
            completion(
                NO,
                readError.localizedDescription ?:
                    @"No se pudo copiar el archivo temporal descargado antes de usar el Túnel."
            );
        }

        return;
    }

    NSData *payload = [data copy];

    [self
        resolveTunnelBundleID:
            bundleID
        route:
            route
        fileName:
            fileName
        completion:
            ^(
                NSString *tunnelBundleID,
                NSString *resolveError
            ) {
                if (!tunnelBundleID.length) {
                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            if (completion) {
                                completion(
                                    NO,
                                    resolveError ?:
                                        @"No se pudo resolver tunnelBundleId."
                                );
                            }
                        });

                    return;
                }

                id backend =
                    [self sharedTunnelBackend];

                NSLog(
                    @"XITFORGE Tunnel V2 replace: input=%@ tunnel=%@ path=%@",
                    bundleID,
                    tunnelBundleID,
                    relativePath
                );

                dispatch_async(
                    [self operationQueue],
                    ^{
                        NSError *readyError = nil;

                        if (
                            ![self
                                ensureTunnelReady:
                                    backend
                                error:
                                    &readyError]
                        ) {
                            dispatch_async(
                                dispatch_get_main_queue(),
                                ^{
                                    if (completion) {
                                        completion(
                                            NO,
                                            readyError.localizedDescription ?:
                                                @"El Túnel no está listo."
                                        );
                                    }
                                });

                            return;
                        }

                        SEL selector =
                            NSSelectorFromString(
                                @"replaceFileForApplication:relativePath:data:error:"
                            );

                        if (
                            ![backend
                                respondsToSelector:
                                    selector]
                        ) {
                            dispatch_async(
                                dispatch_get_main_queue(),
                                ^{
                                    if (completion) {
                                        completion(
                                            NO,
                                            @"El Túnel no tiene disponible el reemplazo de archivos."
                                        );
                                    }
                                });

                            return;
                        }

                        NSError *operationError = nil;

                        BOOL success =
                            ((BOOL (*)
                                (
                                    id,
                                    SEL,
                                    NSString *,
                                    NSString *,
                                    NSData *,
                                    NSError **
                                ))
                                objc_msgSend)(
                                    backend,
                                    selector,
                                    tunnelBundleID,
                                    relativePath,
                                    payload,
                                    &operationError
                                );

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                if (!completion) {
                                    return;
                                }

                                completion(
                                    success,
                                    success
                                        ? @"Archivo aplicado mediante Tunnel V2."
                                        : (
                                            operationError.localizedDescription ?:
                                            @"El Túnel no pudo reemplazar el archivo."
                                        )
                                );
                            });
                    });
            }];
}

#pragma mark - Delete

+ (void)deleteFileViaTunnelForBundleID:
    (NSString *)bundleID
    route:
    (NSString *)route
    fileName:
    (NSString *)fileName
    completion:
    (void (^)(BOOL, NSString *))completion {

    NSString *pathError = nil;

    NSString *relativePath =
        [self
            relativePathForRoute:
                route
            fileName:
                fileName
            error:
                &pathError];

    if (!relativePath.length) {
        if (completion) {
            completion(
                NO,
                pathError ?:
                    @"La ruta configurada no es válida."
            );
        }

        return;
    }

    [self
        resolveTunnelBundleID:
            bundleID
        route:
            route
        fileName:
            fileName
        completion:
            ^(
                NSString *tunnelBundleID,
                NSString *resolveError
            ) {
                if (!tunnelBundleID.length) {
                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            if (completion) {
                                completion(
                                    NO,
                                    resolveError ?:
                                        @"No se pudo resolver tunnelBundleId."
                                );
                            }
                        });

                    return;
                }

                id backend =
                    [self sharedTunnelBackend];

                NSLog(
                    @"XITFORGE Tunnel V2 delete: input=%@ tunnel=%@ path=%@",
                    bundleID,
                    tunnelBundleID,
                    relativePath
                );

                dispatch_async(
                    [self operationQueue],
                    ^{
                        NSError *readyError = nil;

                        if (
                            ![self
                                ensureTunnelReady:
                                    backend
                                error:
                                    &readyError]
                        ) {
                            dispatch_async(
                                dispatch_get_main_queue(),
                                ^{
                                    if (completion) {
                                        completion(
                                            NO,
                                            readyError.localizedDescription ?:
                                                @"El Túnel no está listo."
                                        );
                                    }
                                });

                            return;
                        }

                        SEL selector =
                            NSSelectorFromString(
                                @"deleteFileForApplication:relativePath:error:"
                            );

                        if (
                            ![backend
                                respondsToSelector:
                                    selector]
                        ) {
                            dispatch_async(
                                dispatch_get_main_queue(),
                                ^{
                                    if (completion) {
                                        completion(
                                            NO,
                                            @"El Túnel no tiene disponible el borrado de archivos."
                                        );
                                    }
                                });

                            return;
                        }

                        NSError *operationError = nil;

                        BOOL success =
                            ((BOOL (*)
                                (
                                    id,
                                    SEL,
                                    NSString *,
                                    NSString *,
                                    NSError **
                                ))
                                objc_msgSend)(
                                    backend,
                                    selector,
                                    tunnelBundleID,
                                    relativePath,
                                    &operationError
                                );

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                if (!completion) {
                                    return;
                                }

                                completion(
                                    success,
                                    success
                                        ? @"Archivo eliminado mediante Tunnel V2."
                                        : (
                                            operationError.localizedDescription ?:
                                            @"El Túnel no pudo eliminar el archivo."
                                        )
                                );
                            });
                    });
            }];
}

@end
