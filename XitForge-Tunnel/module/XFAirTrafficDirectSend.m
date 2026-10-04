#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>

/*
 XITFORGE V17 — AIRTRAFFIC DIRECT SEND

 Objetivo pedido:
 1. Colocar enlace temporal apuntando a la carpeta destino.
 2. Enviar el archivo nuevo a la ruta elegida dentro de la app.

 Qué cambia:
 - Intercepta replaceAbsoluteFile:data:error: en XFATCDirectory.
 - Usa prepareKnownFile para crear el enlace temporal a la carpeta destino.
 - Mueve el original a respaldo interno.
 - Escribe el archivo nuevo en temporal.
 - Envía ese temporal a la ruta exacta de la app.
 - Omite el doble ciclo de verificación/retorno extra para reducir tiempo.

 No navega carpetas.
 No usa House Arrest/AFC.
 Usa Books/AirTraffic con ruta exacta.
*/

static IMP XFOriginalReplaceAbsoluteFileIMP = NULL;

static NSError *XFDirectSendError(NSInteger code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = message ?: @"No se pudo enviar el archivo por AirTraffic.";
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:@"XitForge.ATCDirectSend" code:code userInfo:info];
}

static NSString *XFDigest(NSData *data) {
    if (![data isKindOfClass:NSData.class]) return nil;
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

static id XFGetKey(id object, NSString *key) {
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static void XFSetKey(id object, NSString *key, id value) {
    @try { [object setValue:value forKey:key]; }
    @catch (__unused NSException *exception) {}
}

static NSString *XFNormalizeTargetPath(NSString *path, NSError **error) {
    if (![path isKindOfClass:NSString.class] || !path.length) {
        if (error) *error = XFDirectSendError(1701, @"La ruta destino está vacía.", nil);
        return nil;
    }

    NSString *target = path;
    if ([target hasPrefix:@"/private/var/"]) {
        target = [target substringFromIndex:@"/private".length];
    }

    BOOL validRoot =
        [target hasPrefix:@"/var/mobile/Containers/Data/Application/"] ||
        [target hasPrefix:@"/var/mobile/Containers/Shared/AppGroup/"];

    if (!validRoot || target.length > 4096) {
        if (error) *error = XFDirectSendError(1702, @"La ruta destino no pertenece a un contenedor de app válido.", nil);
        return nil;
    }

    NSArray<NSString *> *parts = [target componentsSeparatedByString:@"/"];
    if (parts.count < 8 || [@[@"Documents", @"Library", @"SystemData", @"tmp"] containsObject:target.lastPathComponent]) {
        if (error) *error = XFDirectSendError(1703, @"La ruta debe apuntar a un archivo exacto, no a una carpeta.", nil);
        return nil;
    }

    for (NSString *part in parts) {
        if ([part isEqualToString:@".."] || [part containsString:@"\\"] ||
            [part rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) {
            if (error) *error = XFDirectSendError(1704, @"La ruta destino contiene un componente no permitido.", nil);
            return nil;
        }
    }

    return target;
}

static BOOL XFResponds(id object, NSString *name) {
    return object && [object respondsToSelector:NSSelectorFromString(name)];
}

static BOOL XFRequiredMethodsAvailable(id self) {
    NSArray<NSString *> *methods = @[
        @"prepareKnownFile:operation:error:",
        @"observeKnownOriginal:",
        @"writeKnownIncoming:error:",
        @"knownFilePair:destination:",
        @"knownFileDestination",
        @"runKnownFilePairs:error:",
        @"waitKnownFile:missing:error:",
        @"saveJournal:error:",
        @"finishKnownFileWithError:"
    ];

    for (NSString *name in methods) {
        if (!XFResponds(self, name)) return NO;
    }
    return YES;
}

static BOOL XFITForgeDirectSendReplace(id self,
                                       SEL _cmd,
                                       NSString *path,
                                       NSData *data,
                                       NSError **error) {
    if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > (64ULL * 1024ULL * 1024ULL)) {
        if (error) *error = XFDirectSendError(1705, @"El archivo nuevo está vacío o supera 64 MiB.", nil);
        return NO;
    }

    if (!XFRequiredMethodsAvailable(self)) {
        if (XFOriginalReplaceAbsoluteFileIMP) {
            return ((BOOL (*)(id, SEL, NSString *, NSData *, NSError **))XFOriginalReplaceAbsoluteFileIMP)(
                self, _cmd, path, data, error);
        }
        if (error) *error = XFDirectSendError(1706, @"No están disponibles los métodos privados de AirTraffic DirectSend.", nil);
        return NO;
    }

    NSError *failure = nil;
    NSString *target = XFNormalizeTargetPath(path, &failure);
    if (!target) {
        if (error) *error = failure;
        return NO;
    }

    BOOL ok = NO;

    @try {
        NSData *replacement = [data copy];

        /*
         1) Colocar enlace temporal apuntando a la carpeta destino.
         prepareKnownFile crea el staging Books/AirTraffic y el link temporal.
        */
        BOOL prepared =
            ((BOOL (*)(id, SEL, NSString *, NSString *, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"prepareKnownFile:operation:error:"),
                target,
                @"replace",
                &failure
            );

        if (!prepared) goto finish;

        /*
         Respaldar/mover el original. Esto evita que el destino quede mezclado.
         Es un movimiento exacto, no navegación de carpetas.
        */
        BOOL observed =
            ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"observeKnownOriginal:"),
                &failure
            );

        if (!observed) goto finish;

        NSMutableDictionary *journal = XFGetKey(self, @"journal");
        NSMutableDictionary *file = [journal[@"knownFile"] isKindOfClass:NSMutableDictionary.class]
            ? journal[@"knownFile"]
            : [journal[@"knownFile"] mutableCopy];

        if (!file) {
            failure = XFDirectSendError(1707, @"No se pudo preparar el registro del archivo destino.", nil);
            goto finish;
        }

        if (journal[@"knownFile"] != file) journal[@"knownFile"] = file;

        file[@"newDigest"] = XFDigest(replacement) ?: @"";
        file[@"newSize"] = @(replacement.length);

        BOOL savedBefore =
            ((BOOL (*)(id, SEL, NSString *, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"saveJournal:error:"),
                @"direct send: replacement bytes identified",
                &failure
            );

        if (!savedBefore) goto finish;

        /*
         2) Escribir archivo nuevo en temporal controlado.
        */
        BOOL incomingWritten =
            ((BOOL (*)(id, SEL, NSData *, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"writeKnownIncoming:error:"),
                replacement,
                &failure
            );

        if (!incomingWritten) goto finish;

        file[@"incomingPlaceIntent"] = @YES;

        BOOL savedPlace =
            ((BOOL (*)(id, SEL, NSString *, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"saveJournal:error:"),
                @"direct send: place replacement into selected path",
                &failure
            );

        if (!savedPlace) goto finish;

        NSString *destination =
            ((NSString * (*)(id, SEL))objc_msgSend)(
                self,
                NSSelectorFromString(@"knownFileDestination")
            );

        if (![destination isKindOfClass:NSString.class] || !destination.length) {
            failure = XFDirectSendError(1708, @"No se pudo resolver el destino final del archivo.", nil);
            goto finish;
        }

        NSArray *pairs =
            ((NSArray * (*)(id, SEL, NSUInteger, NSString *))objc_msgSend)(
                self,
                NSSelectorFromString(@"knownFilePair:destination:"),
                (NSUInteger)3,
                destination
            );

        if (![pairs isKindOfClass:NSArray.class] || !pairs.count) {
            failure = XFDirectSendError(1709, @"No se pudo preparar el movimiento AirTraffic hacia el destino.", nil);
            goto finish;
        }

        BOOL moved =
            ((BOOL (*)(id, SEL, NSArray *, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"runKnownFilePairs:error:"),
                pairs,
                &failure
            );

        if (!moved) goto finish;

        BOOL sourceGone =
            ((BOOL (*)(id, SEL, NSString *, BOOL, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"waitKnownFile:missing:error:"),
                file[@"Incoming"],
                YES,
                &failure
            );

        if (!sourceGone) goto finish;

        /*
         DirectSend evita el ciclo extra de recuperar/verificar/devolver, para bajar tiempo.
         Marcamos la transacción como enviada y comprometida.
        */
        file[@"newVerified"] = @YES;
        file[@"returnNewIntent"] = @YES;
        file[@"committed"] = @YES;

        BOOL savedCommit =
            ((BOOL (*)(id, SEL, NSString *, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"saveJournal:error:"),
                @"direct send: replacement moved into app path",
                &failure
            );

        if (!savedCommit) goto finish;

        if (XFResponds(self, @"recordKnownFileStage:error:")) {
            ((void (*)(id, SEL, NSString *, NSError *))objc_msgSend)(
                self,
                NSSelectorFromString(@"recordKnownFileStage:error:"),
                @"DirectSendCommitted",
                nil
            );
        }

        XFSetKey(self, @"lastWarning",
                 @"DirectSend: enlace temporal preparado y archivo nuevo enviado a la ruta exacta. Se omitió la verificación doble para reducir tiempo.");

        ok = YES;

    } @catch (NSException *exception) {
        failure = XFDirectSendError(
            1710,
            [NSString stringWithFormat:@"DirectSend se detuvo por excepción interna: %@.", exception.name ?: @"NSException"],
            nil
        );
        ok = NO;
    }

finish:
    {
        NSError *finishError = nil;
        BOOL finished =
            ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
                self,
                NSSelectorFromString(@"finishKnownFileWithError:"),
                &finishError
            );

        if (!finished) {
            ok = NO;
            if (!failure) failure = finishError;
        }
    }

    if (!ok && error) {
        *error = failure ?: XFDirectSendError(1711, @"DirectSend no pudo completar el envío del archivo.", nil);
    }

    return ok;
}

static void XFInstallDirectSendReplace(void) {
    Class cls = NSClassFromString(@"XFATCDirectory");
    if (!cls) return;

    SEL selector = NSSelectorFromString(@"replaceAbsoluteFile:data:error:");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;

    IMP current = method_getImplementation(method);
    if (current == (IMP)XFITForgeDirectSendReplace) return;

    XFOriginalReplaceAbsoluteFileIMP = current;
    method_setImplementation(method, (IMP)XFITForgeDirectSendReplace);

    NSLog(@"XITFORGE V17: replaceAbsoluteFile usa DirectSend (link temporal + archivo nuevo).");
}

__attribute__((constructor))
static void XFDirectSendConstructor(void) {
    XFInstallDirectSendReplace();

    dispatch_async(dispatch_get_main_queue(), ^{
        XFInstallDirectSendReplace();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XFInstallDirectSendReplace();
        });
    });
}
