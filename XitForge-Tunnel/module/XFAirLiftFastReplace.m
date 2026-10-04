#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/*
 XITFORGE V10/V11 — ACTIVACIÓN RÁPIDA SIN AIRTRAFFIC

 Este archivo se compila dentro de XFAirLift.dylib.

 Qué hace:
 - Intercepta replaceFileForApplication:relativePath:data:error:
 - Para ACTIVAR usa solo la ruta directa House Arrest/AFC.
 - NO intenta AirTraffic/ATC, porque ATC se queda esperando SyncAllowed.
 - Si la ruta directa no puede escribir, falla rápido con el error real.

 No toca DESACTIVAR ni la UI de Home.
*/

static NSError *XFFastError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"XitForge.FastTunnel"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Error desconocido."}];
}

static id XFGetIvarObject(id object, const char *name) {
    if (!object || !name) return nil;
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar) return nil;
    return object_getIvar(object, ivar);
}

static void XFSetIvarObject(id object, const char *name, id value) {
    if (!object || !name) return;
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar) return;
    object_setIvar(object, ivar, value);
}

static void XFSetRouteCode(id backend, NSString *key, NSInteger code) {
    id routes = XFGetIvarObject(backend, "_routeResultCodes");
    if ([routes respondsToSelector:@selector(setObject:forKey:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(
            routes,
            @selector(setObject:forKey:),
            @(code),
            key
        );
    }
}

static BOOL XFFastReplaceFileForApplication(id self,
                                            SEL _cmd,
                                            NSString *identifier,
                                            NSString *path,
                                            NSData *data,
                                            NSError **error) {
    (void)_cmd;

    if (![data isKindOfClass:NSData.class] || data.length > (64ULL * 1024ULL * 1024ULL)) {
        if (error) *error = XFFastError(1033, @"El archivo elegido supera el límite de reemplazo de 64 MiB.");
        return NO;
    }

    NSData *replacement = [data copy];

    id worker = XFGetIvarObject(self, "_worker");
    SEL performSelector = NSSelectorFromString(@"perform:");
    if (!worker || ![worker respondsToSelector:performSelector]) {
        if (error) *error = XFFastError(6100, @"El worker nativo del Túnel no está disponible.");
        return NO;
    }

    __block BOOL replaced = NO;
    __block NSError *failure = nil;

    void (^operation)(void) = ^{
        XFSetIvarObject(self, "_directoryWarning", @"");
        XFSetIvarObject(self, "_fileServiceAttempt", @{});

        const char *identifierBytes =
            [identifier isKindOfClass:NSString.class] ? identifier.UTF8String : NULL;

        if (!identifier.length || !identifierBytes ||
            strlen(identifierBytes) != [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
            failure = XFFastError(1009, @"Falta un identificador válido de la app.");
            return;
        }

        SEL validateSelector = NSSelectorFromString(@"validatedKnownFileRelativePath:error:");
        if (![self respondsToSelector:validateSelector]) {
            failure = XFFastError(6101, @"El backend no expone la validación de ruta necesaria.");
            return;
        }

        NSError *pathError = nil;
        NSString *relative =
            ((NSString * (*)(id, SEL, NSString *, NSError **))objc_msgSend)(
                self,
                validateSelector,
                path,
                &pathError
            );

        if (!relative.length) {
            failure = pathError ?: XFFastError(1008, @"La ruta relativa del archivo no es válida.");
            return;
        }

        SEL requireSelector = NSSelectorFromString(@"requireConnection:");
        if (![self respondsToSelector:requireSelector]) {
            failure = XFFastError(6102, @"El backend no expone la comprobación de conexión.");
            return;
        }

        NSError *connectionError = nil;
        BOOL connected =
            ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
                self,
                requireSelector,
                &connectionError
            );

        if (!connected) {
            failure = connectionError ?: XFFastError(1007, @"Conecta primero el Túnel con el iPhone.");
            return;
        }

        SEL directSelector =
            NSSelectorFromString(@"replaceViaHouseArrestForApplication:relativePath:data:error:");

        if (![self respondsToSelector:directSelector]) {
            failure = XFFastError(
                6103,
                @"Esta versión del backend no tiene escritura directa House Arrest/AFC. Reemplaza XFAirLiftBackend.m por la versión con replaceViaHouseArrest."
            );
            return;
        }

        NSError *directError = nil;
        replaced =
            ((BOOL (*)(id, SEL, NSString *, NSString *, NSData *, NSError **))objc_msgSend)(
                self,
                directSelector,
                identifier,
                relative,
                replacement,
                &directError
            );

        XFSetRouteCode(self, @"HouseArrestWriteFast", replaced ? 0 : (directError ? directError.code : -1));

        if (replaced) {
            XFSetIvarObject(self, "_directoryWarning", @"Archivo escrito y verificado por ruta rápida House Arrest/AFC. AirTraffic omitido.");
            return;
        }

        /*
         IMPORTANTE:
         No caer a AirTraffic/ATC aquí.
         ATC es lo que estaba esperando SyncAllowed y provocaba timeout.
        */
        failure = XFFastError(
            6041,
            [NSString stringWithFormat:
                @"Ruta rápida House Arrest/AFC no pudo escribir el archivo. AirTraffic fue omitido para evitar espera.\n\nDetalle: %@",
                directError.localizedDescription ?: @"Sin detalle del backend."]
        );
    };

    ((void (*)(id, SEL, id))objc_msgSend)(
        worker,
        performSelector,
        [operation copy]
    );

    if (!replaced && error) *error = failure ?: XFFastError(6041, @"El Túnel no pudo escribir el archivo por ruta rápida.");
    return replaced;
}

static void XFInstallFastReplaceHook(void) {
    Class backendClass = NSClassFromString(@"XFAirLiftBackend");
    if (!backendClass) return;

    SEL selector = NSSelectorFromString(@"replaceFileForApplication:relativePath:data:error:");
    Method method = class_getInstanceMethod(backendClass, selector);
    if (!method) return;

    IMP current = method_getImplementation(method);
    if (current == (IMP)XFFastReplaceFileForApplication) return;

    method_setImplementation(method, (IMP)XFFastReplaceFileForApplication);
    NSLog(@"XITFORGE V11: replaceFileForApplication ahora usa ruta rápida y omite AirTraffic.");
}

__attribute__((constructor))
static void XFFastReplaceConstructor(void) {
    XFInstallFastReplaceHook();

    dispatch_async(dispatch_get_main_queue(), ^{
        XFInstallFastReplaceHook();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XFInstallFastReplaceHook();
        });
    });
}
