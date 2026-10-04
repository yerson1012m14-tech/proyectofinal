#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import "XFIDeviceABI.h"

/*
 XITFORGE V13 — TÚNEL RÁPIDO + AUTO BUNDLE ID

 Reemplaza:
   XitForge-Tunnel/module/XFAirLiftFastReplace.m

 Qué corrige:
 - Sigue sin usar AirTraffic/ATC.
 - Sigue escribiendo por House Arrest/AFC directo.
 - Si Home manda com.dts.freefireth pero iOS responde InstallationLookupFailed,
   consulta el catálogo interno y busca automáticamente el bundle real de Free Fire.
 - No navega carpetas. Solo usa app exacta + ruta exacta + archivo exacto.
*/

static NSError *XFFastError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"XitForge.FastTunnel"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Error desconocido."}];
}

static NSError *XFFastNativeError(IdeviceFfiError *native, NSString *action) {
    if (!native) return nil;
    NSString *detail = native->message ? [NSString stringWithUTF8String:native->message] : @"Error del servicio iOS";
    NSInteger code = native->code;
    NSError *error = XFFastError(code, [NSString stringWithFormat:@"%@: %@ (código %d/%d).",
                                        action ?: @"Operación nativa",
                                        detail ?: @"Respuesta no válida",
                                        native->code,
                                        native->sub_code]);
    idevice_error_free(native);
    return error;
}

static BOOL XFConsumeFast(IdeviceFfiError *native, NSString *action, NSError **error) {
    if (!native) return YES;
    if (error) *error = XFFastNativeError(native, action);
    else idevice_error_free(native);
    return NO;
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
        ((void (*)(id, SEL, id, id))objc_msgSend)(routes, @selector(setObject:forKey:), @(code), key);
    }
}

static NSString *XFStringFast(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static BOOL XFContainsFast(NSString *haystack, NSString *needle) {
    return [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSArray *XFFetchInstalledAppsFast(id backend, NSError **error) {
    SEL appService = NSSelectorFromString(@"applicationsFromAppServiceWithError:");
    if ([backend respondsToSelector:appService]) {
        NSError *appServiceError = nil;
        NSArray *apps =
            ((NSArray * (*)(id, SEL, NSError **))objc_msgSend)(backend, appService, &appServiceError);
        if ([apps isKindOfClass:NSArray.class] && apps.count) return apps;
        if (error && appServiceError) *error = appServiceError;
    }

    SEL installationProxy = NSSelectorFromString(@"applicationsFromInstallationProxyWithError:");
    if ([backend respondsToSelector:installationProxy]) {
        NSError *installError = nil;
        NSArray *apps =
            ((NSArray * (*)(id, SEL, NSError **))objc_msgSend)(backend, installationProxy, &installError);
        if ([apps isKindOfClass:NSArray.class] && apps.count) return apps;
        if (error && installError) *error = installError;
    }

    return nil;
}

static NSInteger XFScoreFreeFireCandidate(NSDictionary *row, NSString *requestedIdentifier) {
    NSString *bundle = XFStringFast(row[@"bundleIdentifier"]).lowercaseString;
    NSString *name = XFStringFast(row[@"name"]).lowercaseString;
    NSString *combined = [NSString stringWithFormat:@"%@ %@", bundle ?: @"", name ?: @""];
    NSString *requested = requestedIdentifier.lowercaseString ?: @"";

    if (!bundle.length) return NSIntegerMin;

    NSInteger score = 0;

    if ([bundle isEqualToString:requested]) score += 10000;

    BOOL requestedMax = XFContainsFast(requested, @"max");
    BOOL candidateMax = XFContainsFast(combined, @"max");

    // Señales fuertes de Free Fire / Garena / DTS.
    if (XFContainsFast(combined, @"freefire")) score += 700;
    if (XFContainsFast(combined, @"free fire")) score += 700;
    if (XFContainsFast(combined, @"garena")) score += 300;
    if (XFContainsFast(combined, @"dts")) score += 250;
    if (XFContainsFast(combined, @"free")) score += 80;
    if (XFContainsFast(combined, @"fire")) score += 80;

    // Paquetes conocidos.
    if (XFContainsFast(bundle, @"com.dts.freefireth")) score += 900;
    if (XFContainsFast(bundle, @"com.dts.freefiremax")) score += 900;

    // Mantener Normal/MAX según lo que Home pidió.
    if (requestedMax) {
        if (candidateMax) score += 350;
        else score -= 150;
    } else {
        if (candidateMax) score -= 400;
        else score += 120;
    }

    // Evitar candidatos claramente no relacionados.
    BOOL looksRelated =
        XFContainsFast(combined, @"freefire") ||
        XFContainsFast(combined, @"free fire") ||
        XFContainsFast(combined, @"garena") ||
        XFContainsFast(combined, @"dts");

    if (!looksRelated) score -= 1000;

    return score;
}

static NSString *XFResolveBundleIDFast(id backend,
                                       NSString *requestedIdentifier,
                                       NSString **reportOut) {
    if (reportOut) *reportOut = nil;

    NSString *requested = XFStringFast(requestedIdentifier);
    if (!requested.length) return requestedIdentifier;

    NSError *catalogError = nil;
    NSArray *apps = XFFetchInstalledAppsFast(backend, &catalogError);

    if (![apps isKindOfClass:NSArray.class] || !apps.count) {
        if (reportOut) {
            *reportOut = [NSString stringWithFormat:@"No se pudo consultar el catálogo para resolver %@. %@",
                          requested,
                          catalogError.localizedDescription ?: @"Sin detalle."];
        }
        return requestedIdentifier;
    }

    NSDictionary *best = nil;
    NSInteger bestScore = NSIntegerMin;

    NSMutableArray<NSString *> *related = [NSMutableArray array];

    for (id item in apps) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *row = (NSDictionary *)item;

        NSString *bundle = XFStringFast(row[@"bundleIdentifier"]);
        NSString *name = XFStringFast(row[@"name"]);
        if (!bundle.length) continue;

        if ([bundle caseInsensitiveCompare:requested] == NSOrderedSame) {
            if (reportOut) *reportOut = [NSString stringWithFormat:@"Bundle confirmado en catálogo: %@.", bundle];
            return bundle;
        }

        NSInteger score = XFScoreFreeFireCandidate(row, requested);
        if (score > bestScore) {
            bestScore = score;
            best = row;
        }

        NSString *combined = [NSString stringWithFormat:@"%@ %@", bundle, name ?: @""];
        if (XFContainsFast(combined, @"freefire") ||
            XFContainsFast(combined, @"free fire") ||
            XFContainsFast(combined, @"garena") ||
            XFContainsFast(combined, @"dts")) {
            [related addObject:[NSString stringWithFormat:@"%@%@", bundle, name.length ? [NSString stringWithFormat:@" · %@", name] : @""]];
        }
    }

    NSString *bestBundle = XFStringFast(best[@"bundleIdentifier"]);
    NSString *bestName = XFStringFast(best[@"name"]);

    if (bestBundle.length && bestScore >= 250) {
        if (reportOut) {
            *reportOut = [NSString stringWithFormat:
                          @"Bundle %@ no apareció exacto. Usando candidato del catálogo: %@%@. Puntuación: %ld.",
                          requested,
                          bestBundle,
                          bestName.length ? [NSString stringWithFormat:@" · %@", bestName] : @"",
                          (long)bestScore];
        }
        return bestBundle;
    }

    if (reportOut) {
        NSString *list = related.count ? [related componentsJoinedByString:@"\n"] : @"No se encontraron candidatos Free Fire/Garena/DTS.";
        *reportOut = [NSString stringWithFormat:
                      @"Bundle %@ no encontrado en catálogo y no hubo candidato seguro.\n\nCandidatos vistos:\n%@",
                      requested,
                      list];
    }
    return requestedIdentifier;
}

static NSString *XFAFCPathForRelative(NSString *relative) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in relative.pathComponents) {
        if (!part.length || [part isEqualToString:@"."]) continue;
        [parts addObject:part];
    }
    NSString *normalized = [parts componentsJoinedByString:@"/"];
    return normalized.length ? [@"/" stringByAppendingString:normalized] : @"/";
}

static NSData *XFReadAFCFast(AfcClientHandle *afc, NSString *path, NSError **error) {
    AfcFileInfo info = {0};
    if (!XFConsumeFast(afc_get_file_info(afc, path.UTF8String, &info), @"Consultar archivo escrito", error)) {
        afc_file_info_free(&info);
        return nil;
    }

    BOOL regular = info.st_ifmt && strcmp(info.st_ifmt, "S_IFREG") == 0;
    size_t length = info.size;
    afc_file_info_free(&info);

    if (!regular) {
        if (error) *error = XFFastError(6201, @"La ruta escrita no es un archivo regular.");
        return nil;
    }

    if (length > (64ULL * 1024ULL * 1024ULL)) {
        if (error) *error = XFFastError(6202, @"El archivo escrito supera el límite de verificación.");
        return nil;
    }

    AfcFileHandle *file = NULL;
    if (!XFConsumeFast(afc_file_open(afc, path.UTF8String, AfcRdOnly, &file), @"Abrir archivo escrito para verificar", error) || !file) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithCapacity:MIN(length, (size_t)(1024 * 1024))];
    BOOL ok = YES;

    while (data.length < length) {
        size_t wanted = MIN(length - data.length, (size_t)(1024 * 1024));
        uint8_t *bytes = NULL;
        size_t received = 0;

        ok = XFConsumeFast(afc_file_read(file, &bytes, wanted, &received), @"Leer archivo escrito para verificar", error);

        if (ok && (!received || !bytes || received > wanted)) {
            if (error) *error = XFFastError(6203, @"La lectura de verificación quedó incompleta.");
            ok = NO;
        }

        if (ok) [data appendBytes:bytes length:received];
        if (bytes) afc_file_read_data_free(bytes, received);
        if (!ok) break;
    }

    NSError *closeError = nil;
    BOOL closed = XFConsumeFast(afc_file_close(file), @"Cerrar archivo verificado", &closeError);
    file = NULL;

    if (ok && !closed) {
        if (error) *error = closeError;
        ok = NO;
    }

    return ok ? data : nil;
}

static BOOL XFWriteAFCFast(AfcClientHandle *afc, NSString *path, NSData *data, NSError **error) {
    if (!afc || !path.length || ![data isKindOfClass:NSData.class]) {
        if (error) *error = XFFastError(6204, @"No se pudo preparar la escritura directa por Túnel.");
        return NO;
    }

    AfcFileHandle *file = NULL;
    if (!XFConsumeFast(afc_file_open(afc, path.UTF8String, AfcWrOnly, &file), @"Abrir destino para escritura directa", error) || !file) {
        return NO;
    }

    BOOL ok = YES;
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];

    while (offset < data.length) {
        if (deadline.timeIntervalSinceNow <= 0) {
            if (error) *error = XFFastError(6205, @"La escritura directa por Túnel superó el tiempo de espera.");
            ok = NO;
            break;
        }

        NSUInteger count = MIN((NSUInteger)(1024 * 1024), data.length - offset);
        if (!XFConsumeFast(afc_file_write(file, bytes + offset, count), @"Escribir archivo por Túnel directo", error)) {
            ok = NO;
            break;
        }

        offset += count;
    }

    NSError *closeError = nil;
    BOOL closed = XFConsumeFast(afc_file_close(file), @"Cerrar archivo escrito", &closeError);
    file = NULL;

    if (ok && !closed) {
        if (error) *error = closeError;
        ok = NO;
    }

    if (!ok) return NO;

    NSError *verifyError = nil;
    NSData *observed = XFReadAFCFast(afc, path, &verifyError);
    if (!observed || ![observed isEqualToData:data]) {
        if (error) *error = verifyError ?: XFFastError(6206, @"El archivo se escribió, pero la verificación no coincide.");
        return NO;
    }

    return YES;
}

static BOOL XFReplaceViaDirectHouseArrest(id backend,
                                          NSString *identifier,
                                          NSString *relative,
                                          NSData *data,
                                          NSError **error) {
    SEL openSelector = NSSelectorFromString(@"openHouseArrestForApplication:documentsOnly:error:");
    if (![backend respondsToSelector:openSelector]) {
        if (error) *error = XFFastError(6207, @"El backend no expone House Arrest/AFC directo.");
        return NO;
    }

    NSString *afcPath = XFAFCPathForRelative(relative);
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    for (NSNumber *documentsMode in @[@NO, @YES]) {
        BOOL documentsOnly = documentsMode.boolValue;

        if (documentsOnly &&
            !([relative isEqualToString:@"Documents"] || [relative hasPrefix:@"Documents/"])) {
            [failures addObject:@"Documents: la ruta queda fuera de Documents."];
            continue;
        }

        NSError *openError = nil;
        AfcClientHandle *afc =
            ((AfcClientHandle * (*)(id, SEL, NSString *, BOOL, NSError **))objc_msgSend)(
                backend,
                openSelector,
                identifier,
                documentsOnly,
                &openError
            );

        if (!afc) {
            [failures addObject:[NSString stringWithFormat:@"%@: %@",
                                 documentsOnly ? @"Documents" : @"Contenedor",
                                 openError.localizedDescription ?: @"iOS no concedió acceso."]];
            continue;
        }

        NSError *writeError = nil;
        BOOL written = XFWriteAFCFast(afc, afcPath, data, &writeError);
        afc_client_free(afc);

        if (written) return YES;

        [failures addObject:[NSString stringWithFormat:@"%@: %@",
                             documentsOnly ? @"Documents" : @"Contenedor",
                             writeError.localizedDescription ?: @"No se pudo escribir/verificar."]];
    }

    if (error) {
        *error = XFFastError(6208, failures.count
            ? [failures componentsJoinedByString:@"\n\n"]
            : @"House Arrest/AFC no devolvió una ruta de escritura.");
    }
    return NO;
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

        NSString *resolutionReport = nil;
        NSString *resolvedIdentifier = XFResolveBundleIDFast(self, identifier, &resolutionReport);
        if (!resolvedIdentifier.length) resolvedIdentifier = identifier;

        NSError *directError = nil;
        replaced = XFReplaceViaDirectHouseArrest(self, resolvedIdentifier, relative, replacement, &directError);

        XFSetRouteCode(self, @"HouseArrestWriteFast", replaced ? 0 : (directError ? directError.code : -1));

        if (replaced) {
            NSString *warning = [resolvedIdentifier isEqualToString:identifier]
                ? @"Archivo escrito y verificado por ruta rápida House Arrest/AFC. AirTraffic omitido."
                : [NSString stringWithFormat:@"Archivo escrito y verificado por ruta rápida House Arrest/AFC. Bundle corregido: %@ → %@. AirTraffic omitido.",
                   identifier, resolvedIdentifier];
            XFSetIvarObject(self, "_directoryWarning", warning);
            return;
        }

        // Si la resolución automática no cambió el ID y falló, dejar claro qué vio el catálogo.
        NSString *bundleText = [resolvedIdentifier isEqualToString:identifier]
            ? [NSString stringWithFormat:@"Bundle usado: %@.", identifier ?: @""]
            : [NSString stringWithFormat:@"Bundle original: %@.\nBundle resuelto: %@.", identifier ?: @"", resolvedIdentifier ?: @""];

        failure = XFFastError(
            6041,
            [NSString stringWithFormat:
                @"Ruta rápida House Arrest/AFC no pudo escribir el archivo. AirTraffic fue omitido para evitar espera.\n\n%@\n\nResolución de app:\n%@\n\nDetalle:\n%@",
                bundleText,
                resolutionReport ?: @"No hubo detalle de resolución.",
                directError.localizedDescription ?: @"Sin detalle del backend."]
        );
    };

    ((void (*)(id, SEL, id))objc_msgSend)(worker, performSelector, [operation copy]);

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
    NSLog(@"XITFORGE V13: ACTIVAR usa AFC directo con auto bundle resolver, sin AirTraffic.");
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
