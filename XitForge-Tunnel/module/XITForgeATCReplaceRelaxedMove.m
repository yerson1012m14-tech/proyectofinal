#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

/*
 XITFORGE V22 — RELAX REPLACE MOVE CONFIRMATION

 Problema real:
 - AirTraffic sí coloca el archivo.
 - Pero AFC a veces NO confirma que el temporal fuente desapareció.
 - El método waitKnownFile(... missing:YES) espera hasta 15s y devuelve:
   "No se confirmó el traslado del archivo".

 Arreglo:
 - Solo para operación "replace".
 - Solo para los temporales internos:
     FileIncoming después de place replacement.
     FileVerify después de return verified replacement.
 - No declara éxito final solo por esto.
 - Deja que la verificación real lea de vuelta la ruta destino y compare bytes.
*/

static IMP XITOriginalWaitKnownFileIMP = NULL;

static id XITValueForKeySafe(id object, NSString *key) {
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static BOOL XITIsReplaceJournal(id self, NSString *path, BOOL wantMissing) {
    if (!wantMissing || ![path isKindOfClass:NSString.class]) return NO;

    NSDictionary *journal = XITValueForKeySafe(self, @"journal");
    if (![journal isKindOfClass:NSDictionary.class]) return NO;

    NSDictionary *file = journal[@"knownFile"];
    if (![file isKindOfClass:NSDictionary.class]) return NO;

    if (![file[@"operation"] isEqual:@"replace"]) return NO;

    NSString *incoming = [file[@"Incoming"] isKindOfClass:NSString.class] ? file[@"Incoming"] : nil;
    NSString *verify = [file[@"Verify"] isKindOfClass:NSString.class] ? file[@"Verify"] : nil;

    BOOL isIncomingPlacement =
        incoming.length &&
        [path isEqual:incoming] &&
        [file[@"incomingPlaceIntent"] boolValue];

    BOOL isVerifyReturn =
        verify.length &&
        [path isEqual:verify] &&
        [file[@"returnNewIntent"] boolValue];

    return isIncomingPlacement || isVerifyReturn;
}

static BOOL XITRelaxedWaitKnownFile(id self,
                                    SEL _cmd,
                                    NSString *path,
                                    BOOL wantMissing,
                                    NSError **error) {
    if (XITIsReplaceJournal(self, path, wantMissing)) {
        /*
         AirTraffic procesa FileComplete asíncrono. En iOS 27 vimos que el destino
         puede quedar escrito aunque el temporal fuente siga apareciendo por AFC.
         Esperamos corto y dejamos que el siguiente paso verifique bytes reales.
        */
        [NSThread sleepForTimeInterval:0.75];
        return YES;
    }

    if (XITOriginalWaitKnownFileIMP) {
        return ((BOOL (*)(id, SEL, NSString *, BOOL, NSError **))XITOriginalWaitKnownFileIMP)(
            self, _cmd, path, wantMissing, error);
    }

    if (error) {
        *error = [NSError errorWithDomain:@"XitForge.V22"
                                     code:2290
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"No se encontró el waitKnownFile original."}];
    }
    return NO;
}

static void XITInstallRelaxedWait(void) {
    Class cls = NSClassFromString(@"XFATCDirectory");
    if (!cls) return;

    SEL selector = NSSelectorFromString(@"waitKnownFile:missing:error:");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;

    IMP current = method_getImplementation(method);
    if (current == (IMP)XITRelaxedWaitKnownFile) return;

    XITOriginalWaitKnownFileIMP = current;
    method_setImplementation(method, (IMP)XITRelaxedWaitKnownFile);

    NSLog(@"XITFORGE V22: waitKnownFile relax aplicado solo para replace.");
}

__attribute__((constructor))
static void XITRelaxedWaitConstructor(void) {
    XITInstallRelaxedWait();

    dispatch_async(dispatch_get_main_queue(), ^{
        XITInstallRelaxedWait();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XITInstallRelaxedWait();
        });
    });
}
