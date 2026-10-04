#import "XITForgeFileEngine.h"
#import <objc/message.h>
#import <UIKit/UIKit.h>

@implementation XITForgeFileEngine

+ (dispatch_queue_t)operationQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.xitforge.file-engine.tunnel-fallback", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

+ (id)installedTunnelBackend {
    __block id backend = nil;

    void (^lookup)(void) = ^{
        id delegate = UIApplication.sharedApplication.delegate;
        SEL tabGetter = NSSelectorFromString(@"mainTabBar");
        if (![delegate respondsToSelector:tabGetter]) return;

        id candidate = ((id (*)(id, SEL))objc_msgSend)(delegate, tabGetter);
        if (![candidate isKindOfClass:UITabBarController.class]) return;

        Class tunnelClass = NSClassFromString(@"XFAirLiftViewController");
        if (!tunnelClass) return;

        for (UIViewController *entry in ((UITabBarController *)candidate).viewControllers ?: @[]) {
            UIViewController *root = entry;
            if ([entry isKindOfClass:UINavigationController.class]) {
                root = ((UINavigationController *)entry).viewControllers.firstObject;
            }
            if (![root isKindOfClass:tunnelClass]) continue;

            SEL backendGetter = NSSelectorFromString(@"backend");
            if ([root respondsToSelector:backendGetter]) {
                backend = ((id (*)(id, SEL))objc_msgSend)(root, backendGetter);
            }
            if (backend) break;
        }
    };

    if (NSThread.isMainThread) lookup();
    else dispatch_sync(dispatch_get_main_queue(), lookup);

    return backend;
}

+ (id)sharedTunnelBackend {
    // Lo primero es reutilizar EXACTAMENTE la instancia de backend que ya usa
    // la pestaña Túnel. Así Home hereda el pairing, la conexión y los handles
    // que el usuario ya dejó listos antes de volver a Inicio.
    id backend = [self installedTunnelBackend];
    if (backend) return backend;

    // Respaldo si la pestaña todavía no está instalada en el tab bar.
    Class backendClass = NSClassFromString(@"XFAirLiftBackend");
    SEL selector = NSSelectorFromString(@"sharedBackend");
    if (!backendClass || ![backendClass respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(backendClass, selector);
}

+ (BOOL)boolGetter:(SEL)selector object:(id)object {
    if (!object || ![object respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

+ (BOOL)tunnelFallbackConfigured {
    // MUY IMPORTANTE: esto solo decide si Home debe CONTINUAR al fallback.
    // No debe volver a mostrar el error de MCM por falta de sandbox token.
    // El pairing/conexión se comprueba después en ensureTunnelReady.
    return [self sharedTunnelBackend] != nil;
}

+ (BOOL)isSafeComponent:(NSString *)component {
    if (![component isKindOfClass:NSString.class] || component.length == 0) return NO;
    if ([component isEqualToString:@"."] || [component isEqualToString:@".."]) return NO;
    if ([component containsString:@"/"] || [component containsString:@"\\"]) return NO;
    NSString *nul = [NSString stringWithFormat:@"%C", (unichar)0];
    return [component rangeOfString:nul].location == NSNotFound;
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
        if (errorOut) *errorOut = @"El nombre del archivo no es válido.";
        return nil;
    }

    NSString *cleanRoute = [route isKindOfClass:NSString.class]
        ? [route stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    cleanRoute = [cleanRoute stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([cleanRoute hasPrefix:@"/"]) cleanRoute = [cleanRoute substringFromIndex:1];
    while ([cleanRoute hasSuffix:@"/"] && cleanRoute.length > 0) cleanRoute = [cleanRoute substringToIndex:cleanRoute.length - 1];

    if (cleanRoute.length == 0) {
        if (errorOut) *errorOut = @"La ruta configurada está vacía.";
        return nil;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger logicalIndex = 0;
    for (NSString *raw in [cleanRoute componentsSeparatedByString:@"/"]) {
        NSString *component = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (component.length == 0) continue;
        if (logicalIndex == 0) component = [self normalizedRootComponent:component];
        if (![self isSafeComponent:component]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"La ruta contiene un componente inválido: %@", component];
            return nil;
        }
        [parts addObject:component];
        logicalIndex++;
    }

    if (parts.count == 0) {
        if (errorOut) *errorOut = @"La ruta no contiene ninguna carpeta válida.";
        return nil;
    }

    [parts addObject:fileName];
    return [parts componentsJoinedByString:@"/"];
}

+ (BOOL)ensureTunnelReady:(id)backend error:(NSError **)errorOut {
    if (!backend) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                       code:5001
                                                   userInfo:@{NSLocalizedDescriptionKey: @"El módulo Túnel no está cargado."}];
        return NO;
    }

    if (![self boolGetter:NSSelectorFromString(@"hasPairingRecord") object:backend]) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                       code:5002
                                                   userInfo:@{NSLocalizedDescriptionKey: @"El Túnel todavía no tiene un pairing válido."}];
        return NO;
    }

    if ([self boolGetter:NSSelectorFromString(@"connected") object:backend]) return YES;

    SEL connectSelector = NSSelectorFromString(@"connectWithError:");
    if (![backend respondsToSelector:connectSelector]) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                       code:5003
                                                   userInfo:@{NSLocalizedDescriptionKey: @"El módulo Túnel no expone la conexión esperada."}];
        return NO;
    }

    NSError *connectError = nil;
    BOOL connected = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(backend, connectSelector, &connectError);
    if (!connected && errorOut) {
        *errorOut = connectError ?: [NSError errorWithDomain:@"XITFORGE.FileEngine"
                                                        code:5004
                                                    userInfo:@{NSLocalizedDescriptionKey: @"No se pudo reconectar el Túnel."}];
    }
    return connected;
}

+ (void)replaceFileViaTunnelFromURL:(NSURL *)sourceURL
                           bundleID:(NSString *)bundleID
                              route:(NSString *)route
                           fileName:(NSString *)fileName
                         completion:(void (^)(BOOL, NSString *))completion {
    NSString *pathError = nil;
    NSString *relativePath = [self relativePathForRoute:route fileName:fileName error:&pathError];
    if (!relativePath || bundleID.length == 0) {
        if (completion) completion(NO, pathError ?: @"Falta el bundle ID del juego.");
        return;
    }

    /*
     * IMPORTANTE:
     * `sourceURL` viene de URLSession:didFinishDownloadingToURL:. iOS solo
     * garantiza ese archivo temporal durante el callback. La V1/V2 esperaba
     * a otra cola antes de leerlo y para entonces el archivo podía haber sido
     * eliminado, provocando "NO SE PUDO ACTIVAR" aunque el Túnel estuviera
     * conectado. Copiamos los bytes AHORA y solo el trabajo nativo se manda
     * a la cola del Túnel.
     */
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:sourceURL options:0 error:&readError];
    if (!data) {
        if (completion) {
            completion(NO, readError.localizedDescription ?: @"No se pudo copiar el archivo temporal descargado antes de usar el Túnel.");
        }
        return;
    }

    NSData *payload = [data copy];

    // Resolver ANTES de saltar a otra cola. En Home esta llamada ocurre en el
    // main thread, donde podemos recuperar con seguridad el backend de la tab Túnel.
    id backend = [self sharedTunnelBackend];

    dispatch_async([self operationQueue], ^{
        NSError *readyError = nil;
        if (![self ensureTunnelReady:backend error:&readyError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, readyError.localizedDescription ?: @"El Túnel no está listo.");
            });
            return;
        }

        SEL selector = NSSelectorFromString(@"replaceFileForApplication:relativePath:data:error:");
        if (![backend respondsToSelector:selector]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, @"El Túnel no tiene disponible el reemplazo de archivos.");
            });
            return;
        }

        NSError *operationError = nil;
        BOOL success = ((BOOL (*)(id, SEL, NSString *, NSString *, NSData *, NSError **))objc_msgSend)(
            backend, selector, bundleID, relativePath, payload, &operationError);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success, success
                    ? @"Archivo aplicado mediante Túnel."
                    : (operationError.localizedDescription ?: @"El Túnel no pudo reemplazar el archivo."));
            }
        });
    });
}

+ (void)deleteFileViaTunnelForBundleID:(NSString *)bundleID
                                 route:(NSString *)route
                              fileName:(NSString *)fileName
                            completion:(void (^)(BOOL, NSString *))completion {
    NSString *pathError = nil;
    NSString *relativePath = [self relativePathForRoute:route fileName:fileName error:&pathError];
    if (!relativePath || bundleID.length == 0) {
        if (completion) completion(NO, pathError ?: @"Falta el bundle ID del juego.");
        return;
    }

    id backend = [self sharedTunnelBackend];

    dispatch_async([self operationQueue], ^{
        NSError *readyError = nil;
        if (![self ensureTunnelReady:backend error:&readyError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, readyError.localizedDescription ?: @"El Túnel no está listo.");
            });
            return;
        }

        SEL selector = NSSelectorFromString(@"deleteFileForApplication:relativePath:error:");
        if (![backend respondsToSelector:selector]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, @"El Túnel no tiene disponible el borrado de archivos.");
            });
            return;
        }

        NSError *operationError = nil;
        BOOL success = ((BOOL (*)(id, SEL, NSString *, NSString *, NSError **))objc_msgSend)(
            backend, selector, bundleID, relativePath, &operationError);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success, success
                    ? @"Archivo eliminado mediante Túnel."
                    : (operationError.localizedDescription ?: @"El Túnel no pudo eliminar el archivo."));
            }
        });
    });
}

@end
