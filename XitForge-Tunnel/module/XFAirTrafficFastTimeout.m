#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/*
 XITFORGE V15 — AIRTRAFFIC FAST TIMEOUT

 Este archivo se compila dentro de XFAirLift.dylib.

 Qué hace:
 - No cambia la ruta de activación: sigue usando Books/AirTraffic exacto.
 - Reduce la espera de waitFor:stream:seconds:support:error: a máximo 5 segundos.
 - Reduce retryATCPreparation de 3 intentos a 1 intento.
 - Si SyncAllowed no responde rápido, falla rápido en vez de dejar ACTIVANDO mucho tiempo.

 No navega carpetas.
 No usa House Arrest/AFC.
 No toca licencias ni opciones.
*/

static IMP XFOriginalWaitForIMP = NULL;
static IMP XFOriginalRetryIMP = NULL;

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

static NSError *XFFastATCError(NSInteger code, NSString *message, NSDictionary *extra) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = message ?: @"AirTraffic no respondió a tiempo.";
    if ([extra isKindOfClass:NSDictionary.class]) [info addEntriesFromDictionary:extra];
    return [NSError errorWithDomain:@"XitForge.ATCFastTimeout" code:code userInfo:info];
}

/*
 Firma original:
 - (NSDictionary *)waitFor:(NSString *)wanted
                    stream:(ReadWriteOpaque *)stream
                   seconds:(NSTimeInterval)seconds
                   support:(NSDictionary **)support
                     error:(NSError **)error
*/
static id XFFastWaitFor(id self,
                        SEL _cmd,
                        NSString *wanted,
                        void *stream,
                        double seconds,
                        NSDictionary **support,
                        NSError **error) {
    double requested = seconds;
    double clamped = seconds;

    /*
     El cuello de botella que viste es SyncAllowed.
     Clamp global para esta sesión rápida: SyncAllowed, ReadyForSync y AssetManifest.
    */
    if (clamped > 5.0) clamped = 5.0;
    if (clamped < 1.0) clamped = 1.0;

    NSLog(@"XITFORGE V15: AirTraffic waitFor %@ %.1fs -> %.1fs",
          wanted ?: @"(nil)",
          requested,
          clamped);

    if (!XFOriginalWaitForIMP) {
        if (error) {
            *error = XFFastATCError(1501, @"AirTraffic rápido no encontró el método original de espera.", nil);
        }
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

/*
 Firma original:
 - (BOOL)retryATCPreparation:(BOOL (^)(NSError **))operation
                       error:(NSError **)error
*/
static BOOL XFFastRetryATCPreparation(id self,
                                      SEL _cmd,
                                      BOOL (^operation)(NSError **),
                                      NSError **error) {
    (void)_cmd;

    NSError *failure = nil;

    XFSetKey(self, @"atcMoveAttempted", @NO);
    XFSetKey(self, @"atcSyncAttempt", @1);

    BOOL ok = NO;
    if (operation) {
        ok = operation(&failure);
    } else {
        failure = XFFastATCError(1502, @"AirTraffic rápido no recibió operación para ejecutar.", nil);
    }

    NSMutableArray *attempts = nil;
    id currentAttempts = XFGetKey(self, @"syncAttempts");
    if ([currentAttempts isKindOfClass:NSMutableArray.class]) {
        attempts = currentAttempts;
    } else if ([currentAttempts isKindOfClass:NSArray.class]) {
        attempts = [currentAttempts mutableCopy];
    } else {
        attempts = [NSMutableArray array];
    }

    NSString *phase = XFStringValue(XFGetKey(self, @"protocolPhase"));
    BOOL moveAttempted = [XFGetKey(self, @"atcMoveAttempted") boolValue];

    [attempts addObject:@{
        @"attempt": @1,
        @"phase": phase.length ? phase : @"ConnectATC",
        @"code": @((failure && failure.code) ? failure.code : 0),
        @"completed": @(ok),
        @"fileMoveAttempted": @(moveAttempted),
        @"fastTimeout": @YES
    }];

    while (attempts.count > 24) [attempts removeObjectAtIndex:0];
    XFSetKey(self, @"syncAttempts", attempts);

    if (ok) return YES;

    if (error) {
        NSMutableDictionary *details = failure.userInfo ? [failure.userInfo mutableCopy] : [NSMutableDictionary dictionary];
        NSString *base = failure.localizedDescription ?: @"El servicio no confirmó la operación.";
        details[@"ATCSyncAttempts"] = @1;
        details[@"ATCFileMoveAttempted"] = @(moveAttempted);
        details[@"XITForgeFastTimeout"] = @YES;
        details[NSLocalizedDescriptionKey] =
            [NSString stringWithFormat:@"%@\nPreparación de AirTraffic: 1 intento rápido. %@",
             base,
             moveAttempted ? @"Se intentó enviar el movimiento de archivo." :
                             @"No se envió ningún movimiento de archivo porque SyncAllowed no respondió rápido."];

        *error = [NSError errorWithDomain:failure.domain ?: @"XitForge.ATCFastTimeout"
                                     code:failure ? failure.code : 1503
                                 userInfo:details];
    }

    return NO;
}

static void XFInstallATCFastTimeout(void) {
    Class cls = NSClassFromString(@"XFATCDirectory");
    if (!cls) return;

    SEL waitSelector = NSSelectorFromString(@"waitFor:stream:seconds:support:error:");
    Method waitMethod = class_getInstanceMethod(cls, waitSelector);
    if (waitMethod) {
        IMP current = method_getImplementation(waitMethod);
        if (current != (IMP)XFFastWaitFor) {
            XFOriginalWaitForIMP = current;
            method_setImplementation(waitMethod, (IMP)XFFastWaitFor);
            NSLog(@"XITFORGE V15: waitFor de AirTraffic limitado a 5 segundos.");
        }
    }

    SEL retrySelector = NSSelectorFromString(@"retryATCPreparation:error:");
    Method retryMethod = class_getInstanceMethod(cls, retrySelector);
    if (retryMethod) {
        IMP current = method_getImplementation(retryMethod);
        if (current != (IMP)XFFastRetryATCPreparation) {
            XFOriginalRetryIMP = current;
            method_setImplementation(retryMethod, (IMP)XFFastRetryATCPreparation);
            NSLog(@"XITFORGE V15: retryATCPreparation limitado a 1 intento.");
        }
    }
}

__attribute__((constructor))
static void XFAirTrafficFastTimeoutConstructor(void) {
    XFInstallATCFastTimeout();

    dispatch_async(dispatch_get_main_queue(), ^{
        XFInstallATCFastTimeout();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XFInstallATCFastTimeout();
        });
    });
}
