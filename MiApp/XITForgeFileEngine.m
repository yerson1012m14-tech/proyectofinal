#import "XITForgeFileEngine.h"
#import "XFTunnelV2Config.h"
#import "LicenseValidator.h"
#import <objc/message.h>
#import <UIKit/UIKit.h>

@implementation XITForgeFileEngine

+ (dispatch_queue_t)operationQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(
            "com.xitforge.file-engine.tunnel-fallback",
            DISPATCH_QUEUE_SERIAL
        );
    });
    return queue;
}

+ (id)installedTunnelBackend {
    __block id backend = nil;

    void (^lookup)(void) = ^{
        id delegate = UIApplication.sharedApplication.delegate;
        SEL tabGetter = NSSelectorFromString(@"mainTabBar");
        if (![delegate respondsToSelector:tabGetter]) return;

        id candidate =
            ((id (*)(id, SEL))objc_msgSend)(delegate, tabGetter);

        if (![candidate isKindOfClass:UITabBarController.class]) return;

        Class tunnelClass = NSClassFromString(@"XFAirLiftViewController");
        if (!tunnelClass) return;

        for (UIViewController *entry
             in ((UITabBarController *)candidate).viewControllers ?: @[]) {
            UIViewController *root = entry;

            if ([entry isKindOfClass:UINavigationController.class]) {
                root =
                    ((UINavigationController *)entry)
                        .viewControllers.firstObject;
            }

            if (![root isKindOfClass:tunnelClass]) continue;

            SEL backendGetter = NSSelectorFromString(@"backend");
            if ([root respondsToSelector:backendGetter]) {
                backend =
                    ((id (*)(id, SEL))objc_msgSend)(
                        root,
                        backendGetter
                    );
            }

            if (backend) break;
        }
    };

    if (NSThread.isMainThread) lookup();
    else dispatch_sync(dispatch_get_main_queue(), lookup);

    return backend;
}

+ (id)sharedTunnelBackend {
    id backend = [self installedTunnelBackend];
    if (backend) return backend;

    Class backendClass = NSClassFromString(@"XFAirLiftBackend");
    SEL selector = NSSelectorFromString(@"sharedBackend");

    if (!backendClass ||
        ![backendClass respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(
        backendClass,
        selector
    );
}

+ (BOOL)boolGetter:(SEL)selector object:(id)object {
    if (!object || ![object respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

+ (BOOL)tunnelFallbackConfigured {
    return [self sharedTunnelBackend] != nil;
}

+ (BOOL)isSafeComponent:(NSString *)component {
    if (![component isKindOfClass:NSString.class] ||
        component.length == 0) {
        return NO;
    }

    if ([component isEqualToString:@"."] ||
        [component isEqualToString:@".."]) {
        return NO;
    }

    if ([component containsString:@"/"] ||
        [component containsString:@"\\"]) {
        return NO;
    }

    NSString *nul =
        [NSString stringWithFormat:@"%C", (unichar)0];

    return
        [component rangeOfString:nul].location ==
        NSNotFound;
}

+ (NSString *)normalizedRootComponent:(NSString *)component {
    NSString *lower = component.lowercaseString;

    if ([lower isEqualToString:@"documents"]) return @"Documents";
    if ([lower isEqualToString:@"library"]) return @"Library";
    if ([lower isEqualToString:@"systemdata"]) return @"SystemData";
    if ([lower isEqualToString:@"tmp"]) return @"tmp";

    return component;
}

+ (NSString *)relativePathForRoute:(NSString *)route
                          fileName:(NSString *)fileName
                             error:(NSString **)errorOut {
    if (errorOut) *errorOut = nil;

    if (![self isSafeComponent:fileName]) {
        if (errorOut) {
            *errorOut = @"El nombre del archivo no es válido.";
        }
        return nil;
    }

    NSString *cleanRoute =
        [route isKindOfClass:NSString.class]
            ? [route stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet]
            : @"";

    cleanRoute =
        [cleanRoute
            stringByReplacingOccurrencesOfString:@"\\"
            withString:@"/"];

    while ([cleanRoute hasPrefix:@"/"]) {
        cleanRoute = [cleanRoute substringFromIndex:1];
    }

    while ([cleanRoute hasSuffix:@"/"] &&
           cleanRoute.length > 0) {
        cleanRoute =
            [cleanRoute substringToIndex:
                cleanRoute.length - 1];
    }

    if (cleanRoute.length == 0) {
        if (errorOut) {
            *errorOut = @"La ruta configurada está vacía.";
        }
        return nil;
    }

    NSMutableArray<NSString *> *parts =
        [NSMutableArray array];

    NSUInteger logicalIndex = 0;

    for (NSString *raw
         in [cleanRoute componentsSeparatedByString:@"/"]) {
        NSString *component =
            [raw stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];

        if (component.length == 0) continue;

        if (logicalIndex == 0) {
            component =
                [self normalizedRootComponent:component];
        }

        if (![self isSafeComponent:component]) {
            if (errorOut) {
                *errorOut =
                    [NSString stringWithFormat:
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
    return [parts componentsJoinedByString:@"/"];
}

+ (BOOL)ensureTunnelReady:(id)backend
                    error:(NSError **)errorOut {
    if (!backend) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:@"XITFORGE.FileEngine"
                    code:5001
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"El módulo Túnel no está cargado."
                    }];
        }
        return NO;
    }

    if (![self boolGetter:
            NSSelectorFromString(@"hasPairingRecord")
            object:backend]) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:@"XITFORGE.FileEngine"
                    code:5002
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"El Túnel todavía no tiene un pairing válido."
                    }];
        }
        return NO;
    }

    if ([self boolGetter:
            NSSelectorFromString(@"connected")
            object:backend]) {
        return YES;
    }

    SEL connectSelector =
        NSSelectorFromString(@"connectWithError:");

    if (![backend respondsToSelector:connectSelector]) {
        if (errorOut) {
            *errorOut =
                [NSError
                    errorWithDomain:@"XITFORGE.FileEngine"
                    code:5003
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"El módulo Túnel no expone la conexión esperada."
                    }];
        }
        return NO;
    }

    NSError *connectError = nil;

    BOOL connected =
        ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
            backend,
            connectSelector,
            &connectError
        );

    if (!connected && errorOut) {
        *errorOut =
            connectError ?:
            [NSError
                errorWithDomain:@"XITFORGE.FileEngine"
                code:5004
                userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"No se pudo reconectar el Túnel."
                }];
    }

    return connected;
}

+ (NSString *)cachedTunnelBundleIDForInput:(NSString *)bundleID {
    if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0) {
        return nil;
    }

    NSString *mapped =
        [XFTunnelV2Config tunnelBundleIdForLegacyBundleId:bundleID];
    if (mapped.length) return mapped;

    if ([XFTunnelV2Config isRememberedTunnelBundleId:bundleID]) {
        return bundleID;
    }

    return nil;
}

+ (NSString *)trimmedRoute:(NSString *)route {
    NSString *value =
        [route isKindOfClass:NSString.class]
            ? [route stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet]
            : @"";

    value = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([value hasPrefix:@"/"] && value.length) {
        value = [value substringFromIndex:1];
    }
    while ([value hasSuffix:@"/"] && value.length) {
        value = [value substringToIndex:value.length - 1];
    }
    return value;
}

+ (NSString *)tunnelBundleIDFromManifest:(NSDictionary *)dictionary
                             inputBundle:(NSString *)inputBundle
                                   route:(NSString *)route
                                fileName:(NSString *)fileName
                         matchedLegacyID:(NSString **)matchedLegacyID {
    NSArray *rawOptions =
        [dictionary[@"options"] isKindOfClass:NSArray.class]
            ? dictionary[@"options"]
            : nil;

    NSString *topLegacy =
        [dictionary[@"bundleId"] isKindOfClass:NSString.class]
            ? dictionary[@"bundleId"]
            : nil;

    NSString *topTunnel =
        [XFTunnelV2Config tunnelBundleIdFromOptionDictionary:dictionary];

    NSString *wantedRoute = [self trimmedRoute:route];
    NSMutableOrderedSet<NSString *> *candidates =
        [NSMutableOrderedSet orderedSet];

    NSString *exactTunnel = nil;
    NSString *exactLegacy = nil;

    for (id value in rawOptions ?: @[]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *raw = (NSDictionary *)value;

        NSString *legacy =
            [raw[@"bundleId"] isKindOfClass:NSString.class]
                ? raw[@"bundleId"]
                : topLegacy;

        NSString *tunnel =
            [XFTunnelV2Config tunnelBundleIdFromOptionDictionary:raw];
        if (!tunnel.length) tunnel = topTunnel;
        if (!tunnel.length) continue;

        // Si el caller ya pasó el tunnelBundleId, aceptarlo directamente
        // cuando el servidor confirma que existe en el manifiesto.
        if ([tunnel isEqualToString:inputBundle]) {
            if (matchedLegacyID) *matchedLegacyID = legacy;
            return tunnel;
        }

        if (legacy.length && ![legacy isEqualToString:inputBundle]) {
            continue;
        }

        [candidates addObject:tunnel];

        NSString *rawRoute =
            [raw[@"route"] isKindOfClass:NSString.class]
                ? [self trimmedRoute:raw[@"route"]]
                : @"";

        NSString *rawFile =
            [raw[@"fileName"] isKindOfClass:NSString.class]
                ? raw[@"fileName"]
                : nil;

        BOOL routeMatches =
            wantedRoute.length == 0 ||
            [rawRoute caseInsensitiveCompare:wantedRoute] == NSOrderedSame;

        BOOL fileMatches =
            fileName.length == 0 ||
            (rawFile.length &&
             [rawFile caseInsensitiveCompare:fileName] == NSOrderedSame);

        if (routeMatches && fileMatches) {
            exactTunnel = tunnel;
            exactLegacy = legacy;
            break;
        }
    }

    if (exactTunnel.length) {
        if (matchedLegacyID) *matchedLegacyID = exactLegacy ?: inputBundle;
        return exactTunnel;
    }

    // Si todas las opciones de ese bundle legacy usan el mismo tunnelBundleId,
    // se puede resolver sin depender de la ruta de una opción concreta.
    if (candidates.count == 1) {
        if (matchedLegacyID) *matchedLegacyID = inputBundle;
        return candidates.firstObject;
    }

    return nil;
}

+ (void)fetchTunnelManifestForGame:(NSString *)game
                        completion:(void (^)(NSDictionary *manifest,
                                             NSError *error))completion {
    NSString *encoded =
        [game stringByAddingPercentEncodingWithAllowedCharacters:
            NSCharacterSet.URLQueryAllowedCharacterSet];

    NSString *urlString =
        [NSString stringWithFormat:
            @"https://xitforge-license-server.onrender.com/api/app/options?game=%@",
            encoded ?: @""];

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) {
            completion(nil,
                [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                    code:5010
                                userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"No se pudo crear la URL del manifiesto Tunnel V2."
                }]);
        }
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20.0;

    [LicenseValidator authorizeRequest:request completion:^(BOOL authorized) {
        if (!authorized) {
            if (completion) {
                completion(nil,
                    [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                        code:5011
                                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"No se pudo autorizar la lectura del manifiesto Tunnel V2."
                    }]);
            }
            return;
        }

        NSURLSessionDataTask *task =
            [NSURLSession.sharedSession
                dataTaskWithRequest:request
                completionHandler:^(NSData *data,
                                    NSURLResponse *response,
                                    NSError *error) {
                    [LicenseValidator handleProtectedHTTPResponse:response];

                    NSHTTPURLResponse *http =
                        [response isKindOfClass:NSHTTPURLResponse.class]
                            ? (NSHTTPURLResponse *)response
                            : nil;

                    if (error || !data.length || !http ||
                        http.statusCode < 200 || http.statusCode > 299) {
                        if (completion) {
                            completion(nil,
                                error ?:
                                [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                    code:5012
                                                userInfo:@{
                                    NSLocalizedDescriptionKey:
                                        [NSString stringWithFormat:
                                            @"El servidor no entregó el manifiesto Tunnel V2 (HTTP %@).",
                                            http ? @(http.statusCode) : @"sin respuesta"]
                                }]);
                        }
                        return;
                    }

                    NSError *jsonError = nil;
                    id json =
                        [NSJSONSerialization JSONObjectWithData:data
                                                       options:0
                                                         error:&jsonError];

                    if (jsonError ||
                        ![json isKindOfClass:NSDictionary.class]) {
                        if (completion) {
                            completion(nil,
                                jsonError ?:
                                [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                    code:5013
                                                userInfo:@{
                                    NSLocalizedDescriptionKey:
                                        @"El manifiesto Tunnel V2 no es JSON válido."
                                }]);
                        }
                        return;
                    }

                    NSDictionary *dictionary = (NSDictionary *)json;
                    NSNumber *ok =
                        [dictionary[@"ok"] isKindOfClass:NSNumber.class]
                            ? dictionary[@"ok"]
                            : nil;

                    if (!ok.boolValue) {
                        if (completion) {
                            completion(nil,
                                [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                    code:5014
                                                userInfo:@{
                                    NSLocalizedDescriptionKey:
                                        @"El servidor rechazó el manifiesto Tunnel V2."
                                }]);
                        }
                        return;
                    }

                    if (completion) completion(dictionary, nil);
                }];

        [task resume];
    }];
}

+ (void)resolveTunnelBundleIDForInput:(NSString *)bundleID
                                route:(NSString *)route
                             fileName:(NSString *)fileName
                               games:(NSArray<NSString *> *)games
                               index:(NSUInteger)index
                          completion:(void (^)(NSString *tunnelBundleID,
                                               NSString *message))completion {
    NSString *cached = [self cachedTunnelBundleIDForInput:bundleID];
    if (cached.length) {
        if (completion) completion(cached, nil);
        return;
    }

    if (index >= games.count) {
        if (completion) {
            completion(nil,
                [NSString stringWithFormat:
                    @"El servidor no devolvió tunnelBundleId para %@. "
                     "Verifica que Render esté desplegando la rama que contiene "
                     "tunnel_bundle_id y que la opción tenga ese campo guardado.",
                    bundleID ?: @"la opción"]);
        }
        return;
    }

    NSString *game = games[index];

    [self fetchTunnelManifestForGame:game
                          completion:^(NSDictionary *manifest, NSError *error) {
        if (manifest) {
            NSString *matchedLegacy = nil;
            NSString *resolved =
                [self tunnelBundleIDFromManifest:manifest
                                     inputBundle:bundleID
                                           route:route
                                        fileName:fileName
                                 matchedLegacyID:&matchedLegacy];

            if (resolved.length) {
                NSString *legacy =
                    matchedLegacy.length ? matchedLegacy : bundleID;

                if (legacy.length) {
                    [XFTunnelV2Config rememberTunnelBundleId:resolved
                                           forLegacyBundleId:legacy];
                }

                NSLog(@"XITFORGE Tunnel V2 RESUELTO: input=%@ tunnel=%@ game=%@ route=%@ file=%@",
                      bundleID, resolved, game, route, fileName);

                if (completion) completion(resolved, nil);
                return;
            }
        } else if (error) {
            NSLog(@"XITFORGE Tunnel V2 manifest %@: %@",
                  game, error.localizedDescription);
        }

        [self resolveTunnelBundleIDForInput:bundleID
                                      route:route
                                   fileName:fileName
                                     games:games
                                     index:index + 1
                                completion:completion];
    }];
}

+ (void)resolveTunnelBundleIDForInput:(NSString *)bundleID
                                route:(NSString *)route
                             fileName:(NSString *)fileName
                          completion:(void (^)(NSString *tunnelBundleID,
                                               NSString *message))completion {
    if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0) {
        if (completion) completion(nil, @"Falta el bundle ID de la opción.");
        return;
    }

    NSMutableArray<NSString *> *games = [NSMutableArray array];

    if ([bundleID isEqualToString:@"com.dts.freefireth"]) {
        [games addObject:@"freefire_normal"];
        [games addObject:@"freefire_max"];
    } else if ([bundleID isEqualToString:@"com.dts.freefiremax"]) {
        [games addObject:@"freefire_max"];
        [games addObject:@"freefire_normal"];
    } else {
        [games addObject:@"freefire_normal"];
        [games addObject:@"freefire_max"];
    }

    [self resolveTunnelBundleIDForInput:bundleID
                                  route:route
                               fileName:fileName
                                 games:games
                                 index:0
                            completion:completion];
}

+ (void)replaceFileViaTunnelFromURL:(NSURL *)sourceURL
                           bundleID:(NSString *)bundleID
                              route:(NSString *)route
                           fileName:(NSString *)fileName
                         completion:(void (^)(BOOL, NSString *))completion {
    NSString *pathError = nil;
    NSString *relativePath =
        [self relativePathForRoute:route
                          fileName:fileName
                             error:&pathError];

    if (!relativePath) {
        if (completion) completion(NO, pathError ?: @"La ruta configurada no es válida.");
        return;
    }

    // Copiar el temporal ANTES de cualquier consulta al servidor.
    NSError *readError = nil;
    NSData *data =
        [NSData dataWithContentsOfURL:sourceURL
                              options:0
                                error:&readError];

    if (!data) {
        if (completion) {
            completion(NO,
                readError.localizedDescription ?:
                    @"No se pudo copiar el archivo temporal descargado antes de usar el Túnel.");
        }
        return;
    }

    NSData *payload = [data copy];

    [self resolveTunnelBundleIDForInput:bundleID
                                  route:route
                               fileName:fileName
                             completion:^(NSString *tunnelBundleID,
                                          NSString *resolveMessage) {
        if (!tunnelBundleID.length) {
            if (completion) {
                completion(NO,
                    resolveMessage ?: @"No se pudo resolver tunnelBundleId.");
            }
            return;
        }

        id backend = [self sharedTunnelBackend];

        NSLog(@"XITFORGE Tunnel V2 replace: input=%@ tunnel=%@ path=%@",
              bundleID, tunnelBundleID, relativePath);

        dispatch_async([self operationQueue], ^{
            NSError *readyError = nil;

            if (![self ensureTunnelReady:backend error:&readyError]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(NO,
                            readyError.localizedDescription ?:
                                @"El Túnel no está listo.");
                    }
                });
                return;
            }

            SEL selector =
                NSSelectorFromString(
                    @"replaceFileForApplication:relativePath:data:error:");

            if (![backend respondsToSelector:selector]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(NO,
                            @"El Túnel no tiene disponible el reemplazo de archivos.");
                    }
                });
                return;
            }

            NSError *operationError = nil;

            BOOL success =
                ((BOOL (*)(id, SEL, NSString *, NSString *, NSData *, NSError **))
                    objc_msgSend)(
                        backend,
                        selector,
                        tunnelBundleID,
                        relativePath,
                        payload,
                        &operationError
                    );

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!completion) return;

                completion(
                    success,
                    success
                        ? @"Archivo aplicado mediante Tunnel V2."
                        : (operationError.localizedDescription ?:
                            @"El Túnel no pudo reemplazar el archivo.")
                );
            });
        });
    }];
}

+ (void)deleteFileViaTunnelForBundleID:(NSString *)bundleID
                                 route:(NSString *)route
                              fileName:(NSString *)fileName
                            completion:(void (^)(BOOL, NSString *))completion {
    NSString *pathError = nil;
    NSString *relativePath =
        [self relativePathForRoute:route
                          fileName:fileName
                             error:&pathError];

    if (!relativePath) {
        if (completion) completion(NO, pathError ?: @"La ruta configurada no es válida.");
        return;
    }

    [self resolveTunnelBundleIDForInput:bundleID
                                  route:route
                               fileName:fileName
                             completion:^(NSString *tunnelBundleID,
                                          NSString *resolveMessage) {
        if (!tunnelBundleID.length) {
            if (completion) {
                completion(NO,
                    resolveMessage ?: @"No se pudo resolver tunnelBundleId.");
            }
            return;
        }

        id backend = [self sharedTunnelBackend];

        NSLog(@"XITFORGE Tunnel V2 delete: input=%@ tunnel=%@ path=%@",
              bundleID, tunnelBundleID, relativePath);

        dispatch_async([self operationQueue], ^{
            NSError *readyError = nil;

            if (![self ensureTunnelReady:backend error:&readyError]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(NO,
                            readyError.localizedDescription ?:
                                @"El Túnel no está listo.");
                    }
                });
                return;
            }

            SEL selector =
                NSSelectorFromString(
                    @"deleteFileForApplication:relativePath:error:");

            if (![backend respondsToSelector:selector]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(NO,
                            @"El Túnel no tiene disponible el borrado de archivos.");
                    }
                });
                return;
            }

            NSError *operationError = nil;

            BOOL success =
                ((BOOL (*)(id, SEL, NSString *, NSString *, NSError **))
                    objc_msgSend)(
                        backend,
                        selector,
                        tunnelBundleID,
                        relativePath,
                        &operationError
                    );

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!completion) return;

                completion(
                    success,
                    success
                        ? @"Archivo eliminado mediante Tunnel V2."
                        : (operationError.localizedDescription ?:
                            @"El Túnel no pudo eliminar el archivo.")
                );
            });
        });
    }];
}

@end
