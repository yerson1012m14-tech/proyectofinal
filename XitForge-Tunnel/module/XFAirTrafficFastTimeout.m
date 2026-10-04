#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/*
 XITFORGE V16 — SYNCALLOWED 8 MENSAJES + 3 INTENTOS

 Qué hace:
 - Mantiene ACTIVAR por Books/AirTraffic exacto.
 - Para SyncAllowed lee hasta 8 mensajes buscando SyncAllowed.
 - Si falla la preparación, abre otra conexión: máximo 3 intentos.
 - Espera 0.3s y luego 0.6s entre reintentos.
 - No usa House Arrest/AFC.
 - No navega carpetas.
*/

static IMP XFOriginalWaitForIMP = NULL;

static id XFGetKey(id object, NSString *key) {
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static void XFSetKey(id object, NSString *key, id value) {
    @try { [object setValue:value forKey:key]; }
    @catch (__unused NSException *exception) {}
}

static NSString *XFStringValue(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSError *XFSyncAllowedError(NSInteger code, NSString *message, NSDictionary *extra) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = message ?: @"AirTraffic no confirmó SyncAllowed.";
    if ([extra isKindOfClass:NSDictionary.class]) [info addEntriesFromDictionary:extra];
    return [NSError errorWithDomain:@"XitForge.ATCSyncAllowed8" code:code userInfo:info];
}

static NSDictionary *XFMessageFor(id self, NSString *command, NSNumber *session, NSDictionary *params) {
    SEL selector = NSSelectorFromString(@"message:session:params:");
    if (![self respondsToSelector:selector]) return nil;

    return ((NSDictionary * (*)(id, SEL, NSString *, NSNumber *, NSDictionary *))objc_msgSend)(
        self,
        selector,
        command,
        session ?: @1,
        params
    );
}

static BOOL XFSendDictionary(id self, NSDictionary *dictionary, void *stream, NSError **error) {
    SEL selector = NSSelectorFromString(@"sendDictionary:stream:littleEndian:error:");
    if (![self respondsToSelector:selector]) {
        if (error) *error = XFSyncAllowedError(1601, @"AirTraffic no expone sendDictionary.", nil);
        return NO;
    }

    return ((BOOL (*)(id, SEL, NSDictionary *, void *, BOOL, NSError **))objc_msgSend)(
        self,
        selector,
        dictionary,
        stream,
        YES,
        error
    );
}

static NSDictionary *XFReceiveDictionary(id self, void *stream, uint64_t timeoutMS, NSError **error) {
    SEL selector = NSSelectorFromString(@"receiveDictionary:littleEndian:timeout:error:");
    if (![self respondsToSelector:selector]) {
        if (error) *error = XFSyncAllowedError(1602, @"AirTraffic no expone receiveDictionary.", nil);
        return nil;
    }

    return ((NSDictionary * (*)(id, SEL, void *, BOOL, uint64_t, NSError **))objc_msgSend)(
        self,
        selector,
        stream,
        YES,
        timeoutMS,
        error
    );
}

static void XFSetSupportFromSyncAllowed(NSDictionary *message, NSDictionary **support) {
    if (!support) return;

    id params = message[@"Params"];
    if ([params isKindOfClass:NSDictionary.class]) {
        id direct = params;

        // Mantener compatibilidad con variantes donde los parámetros de soporte vengan anidados.
        for (NSString *key in @[@"Support", @"SupportedVersions", @"DeviceSupport", @"AirTrafficSupport"]) {
            id nested = ((NSDictionary *)params)[key];
            if ([nested isKindOfClass:NSDictionary.class]) {
                direct = nested;
                break;
            }
        }

        if ([direct isKindOfClass:NSDictionary.class]) *support = direct;
    }
}

/*
 Firma original:
 - (NSDictionary *)waitFor:(NSString *)wanted
                    stream:(ReadWriteOpaque *)stream
                   seconds:(NSTimeInterval)seconds
                   support:(NSDictionary **)support
                     error:(NSError **)error
*/
static id XFSyncAllowed8WaitFor(id self,
                                SEL _cmd,
                                NSString *wanted,
                                void *stream,
                                double seconds,
                                NSDictionary **support,
                                NSError **error) {
    NSString *target = XFStringValue(wanted);

    // Solo reemplazamos la espera de SyncAllowed. Lo demás usa el método original.
    if (![target isEqualToString:@"SyncAllowed"]) {
        double clamped = seconds;
        if (clamped > 12.0) clamped = 12.0;
        if (clamped < 1.0) clamped = 1.0;

        if (!XFOriginalWaitForIMP) {
            if (error) *error = XFSyncAllowedError(1603, @"No se encontró waitFor original.", nil);
            return nil;
        }

        return ((id (*)(id, SEL, NSString *, void *, double, NSDictionary **, NSError **))XFOriginalWaitForIMP)(
            self,
            _cmd,
            wanted,
            stream,
            clamped,
            support,
            error
        );
    }

    NSLog(@"XITFORGE V16: buscando SyncAllowed leyendo hasta 8 mensajes.");

    NSError *lastError = nil;
    NSMutableArray<NSString *> *seen = [NSMutableArray array];

    for (NSUInteger index = 1; index <= 8; index++) {
        NSError *receiveError = nil;
        NSDictionary *message = XFReceiveDictionary(self, stream, 1500, &receiveError);

        if (![message isKindOfClass:NSDictionary.class]) {
            lastError = receiveError ?: XFSyncAllowedError(1604, @"No llegó mensaje de AirTraffic.", nil);
            [seen addObject:[NSString stringWithFormat:@"mensaje %lu: sin respuesta", (unsigned long)index]];
            break;
        }

        NSString *command = XFStringValue(message[@"Command"]);
        NSNumber *session = [message[@"Session"] isKindOfClass:NSNumber.class] ? message[@"Session"] : @1;
        NSNumber *responseCode = [message[@"ResponseCode"] isKindOfClass:NSNumber.class] ? message[@"ResponseCode"] : nil;

        [seen addObject:[NSString stringWithFormat:@"mensaje %lu: %@%@",
                         (unsigned long)index,
                         command.length ? command : @"Other",
                         responseCode ? [NSString stringWithFormat:@" (%@)", responseCode] : @""]];

        if ([command isEqualToString:@"Ping"]) {
            NSDictionary *pong = XFMessageFor(self, @"Pong", session, nil);
            NSError *pongError = nil;
            if (!pong || !XFSendDictionary(self, pong, stream, &pongError)) {
                if (error) *error = pongError ?: XFSyncAllowedError(1605, @"No se pudo responder Pong a AirTraffic.", nil);
                return nil;
            }
            continue;
        }

        if ([command isEqualToString:@"SyncAllowed"]) {
            XFSetSupportFromSyncAllowed(message, support);
            NSLog(@"XITFORGE V16: SyncAllowed encontrado en mensaje %lu.", (unsigned long)index);
            return message;
        }

        if ([command isEqualToString:@"SyncFailed"]) {
            if (error) {
                *error = XFSyncAllowedError(1606,
                    [NSString stringWithFormat:@"AirTraffic devolvió SyncFailed antes de SyncAllowed. Leídos: %@",
                     [seen componentsJoinedByString:@" / "]],
                    @{@"XITForgeSyncAllowedMessages": @([seen count])});
            }
            return nil;
        }

        if ([command isEqualToString:@"SyncStopped"] || [command isEqualToString:@"SyncFinished"]) {
            if (error) {
                *error = XFSyncAllowedError(1607,
                    [NSString stringWithFormat:@"AirTraffic terminó antes de SyncAllowed. Leídos: %@",
                     [seen componentsJoinedByString:@" / "]],
                    @{@"XITForgeSyncAllowedMessages": @([seen count])});
            }
            return nil;
        }

        // Otros mensajes se ignoran hasta completar los 8.
    }

    if (error) {
        NSString *detail = seen.count ? [seen componentsJoinedByString:@" / "] : @"ningún mensaje";
        *error = XFSyncAllowedError(1608,
            [NSString stringWithFormat:@"AirTraffic no envió SyncAllowed después de leer hasta 8 mensajes. Leídos: %@. Último error: %@",
             detail,
             lastError.localizedDescription ?: @"sin detalle"],
            @{@"XITForgeSyncAllowedMessages": @([seen count])});
    }

    return nil;
}

/*
 Firma original:
 - (BOOL)retryATCPreparation:(BOOL (^)(NSError **))operation
                       error:(NSError **)error
*/
static BOOL XFThreeAttemptRetryATCPreparation(id self,
                                              SEL _cmd,
                                              BOOL (^operation)(NSError **),
                                              NSError **error) {
    (void)_cmd;

    NSError *failure = nil;
    NSArray<NSNumber *> *delays = @[@0.3, @0.6];

    NSMutableArray *attempts = [NSMutableArray array];

    for (NSUInteger attempt = 1; attempt <= 3; attempt++) {
        XFSetKey(self, @"atcMoveAttempted", @NO);
        XFSetKey(self, @"atcSyncAttempt", @(attempt));

        failure = nil;
        BOOL ok = operation ? operation(&failure) : NO;
        BOOL moveAttempted = [XFGetKey(self, @"atcMoveAttempted") boolValue];
        NSString *phase = XFStringValue(XFGetKey(self, @"protocolPhase"));

        [attempts addObject:@{
            @"attempt": @(attempt),
            @"phase": phase.length ? phase : @"ConnectATC",
            @"code": @((failure && failure.code) ? failure.code : 0),
            @"completed": @(ok),
            @"fileMoveAttempted": @(moveAttempted),
            @"syncAllowedMessagesLimit": @8,
            @"retryDelayProfile": @"0.3s/0.6s"
        }];

        XFSetKey(self, @"syncAttempts", attempts);

        if (ok) return YES;

        if (attempt < 3) {
            NSTimeInterval delay = [delays[attempt - 1] doubleValue];
            NSLog(@"XITFORGE V16: AirTraffic intento %lu falló. Reintentando en %.1fs.",
                  (unsigned long)attempt,
                  delay);
            [NSThread sleepForTimeInterval:delay];
        }
    }

    if (error) {
        NSMutableDictionary *details = failure.userInfo ? [failure.userInfo mutableCopy] : [NSMutableDictionary dictionary];
        BOOL moveAttempted = [XFGetKey(self, @"atcMoveAttempted") boolValue];

        details[@"ATCSyncAttempts"] = @3;
        details[@"ATCFileMoveAttempted"] = @(moveAttempted);
        details[@"XITForgeSyncAllowedMessagesLimit"] = @8;
        details[@"XITForgeRetryDelays"] = @"0.3s, 0.6s";
        details[NSLocalizedDescriptionKey] =
            [NSString stringWithFormat:@"%@\nPreparación de AirTraffic: 3 intento(s). Se leyeron hasta 8 mensajes buscando SyncAllowed. Reintentos: 0,3s y 0,6s.%@",
             failure.localizedDescription ?: @"El servicio no confirmó la operación.",
             moveAttempted ? @"" : @" No se envió ningún movimiento de archivo en esta sesión."];

        *error = [NSError errorWithDomain:failure.domain ?: @"XitForge.ATCSyncAllowed8"
                                     code:failure ? failure.code : 1609
                                 userInfo:details];
    }

    return NO;
}

static void XFInstallATCSyncAllowed8(void) {
    Class cls = NSClassFromString(@"XFATCDirectory");
    if (!cls) return;

    SEL waitSelector = NSSelectorFromString(@"waitFor:stream:seconds:support:error:");
    Method waitMethod = class_getInstanceMethod(cls, waitSelector);
    if (waitMethod) {
        IMP current = method_getImplementation(waitMethod);
        if (current != (IMP)XFSyncAllowed8WaitFor) {
            XFOriginalWaitForIMP = current;
            method_setImplementation(waitMethod, (IMP)XFSyncAllowed8WaitFor);
            NSLog(@"XITFORGE V16: waitFor SyncAllowed leerá hasta 8 mensajes.");
        }
    }

    SEL retrySelector = NSSelectorFromString(@"retryATCPreparation:error:");
    Method retryMethod = class_getInstanceMethod(cls, retrySelector);
    if (retryMethod) {
        IMP current = method_getImplementation(retryMethod);
        if (current != (IMP)XFThreeAttemptRetryATCPreparation) {
            method_setImplementation(retryMethod, (IMP)XFThreeAttemptRetryATCPreparation);
            NSLog(@"XITFORGE V16: retryATCPreparation = 3 intentos con 0.3s/0.6s.");
        }
    }
}

__attribute__((constructor))
static void XFAirTrafficSyncAllowed8Constructor(void) {
    XFInstallATCSyncAllowed8();

    dispatch_async(dispatch_get_main_queue(), ^{
        XFInstallATCSyncAllowed8();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XFInstallATCSyncAllowed8();
        });
    });
}
