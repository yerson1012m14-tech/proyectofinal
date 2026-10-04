#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/*
 XITFORGE V18B — DIAGNÓSTICO DE EXISTENCIA / PLAN

 Modo seguro:
 - Intercepta replaceFileForApplication:relativePath:data:error:
 - NO escribe
 - NO crea
 - NO reemplaza
 - NO elimina
 - NO manda FileComplete
 - NO toca el archivo destino

 Qué muestra:
 - Bundle
 - Ruta exacta
 - Carpeta destino
 - Archivo
 - Tamaño del archivo nuevo
 - Validación de mayúsculas: Compulsory
 - Plan:
      * si el archivo existe -> replace
      * si el archivo falta -> create
 - Estado de existencia:
      * NO comprobado por seguridad en este modo
      * confirma que la ruta ya está lista para una comprobación real desde el módulo de túnel
*/

static IMP XITOriginalReplaceFileIMP = NULL;

static NSString *XITSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSError *XITDiagnosticError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"XitForge.ExistenceDiagnostic"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Diagnóstico detenido."}];
}

static NSString *XITCleanRelative(NSString *path) {
    NSString *p = XITSafeString(path);
    p = [p stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([p hasPrefix:@"/"]) p = [p substringFromIndex:1];
    while ([p containsString:@"//"]) p = [p stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
    return p;
}

static BOOL XITPathHasUnsafeComponent(NSString *path) {
    if (![path isKindOfClass:NSString.class]) return YES;
    if ([path rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) return YES;
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if ([part isEqualToString:@".."]) return YES;
    }
    return NO;
}

static BOOL XITLooksLikeFolderPath(NSString *relative) {
    if (![relative isKindOfClass:NSString.class] || !relative.length) return YES;
    NSString *trim = [relative stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trim.length) return YES;
    if ([trim hasSuffix:@"/"]) return YES;
    NSString *last = trim.lastPathComponent ?: @"";
    return [@[@"Documents", @"Library", @"SystemData", @"tmp", @"avatar", @"gameassetbundles"] containsObject:last];
}

static NSString *XITCaseDiagnostic(NSString *relative) {
    if ([relative containsString:@"contentcache/Compulsory/"]) {
        return @"OK: usa Compulsory con C mayúscula.";
    }
    if ([relative containsString:@"contentcache/compulsory/"]) {
        return @"ERROR: usa compulsory en minúscula. Debe ser Compulsory.";
    }
    return @"AVISO: no se encontró contentcache/Compulsory en la ruta.";
}

static NSString *XITPlanForRelativePath(NSString *relative) {
    NSString *caseInfo = XITCaseDiagnostic(relative);
    if ([caseInfo hasPrefix:@"ERROR"]) {
        return @"PLAN BLOQUEADO: corrige la C mayúscula antes de comprobar existencia.";
    }
    return @"PLAN: comprobar existencia real en el módulo Túnel; si existe usar replace; si falta usar create.";
}

static BOOL XITDiagnosticReplaceFile(id self,
                                     SEL _cmd,
                                     NSString *identifier,
                                     NSString *path,
                                     NSData *data,
                                     NSError **error) {
    (void)self;
    (void)_cmd;
    (void)XITOriginalReplaceFileIMP;

    NSString *bundle = XITSafeString(identifier);
    NSString *relative = XITCleanRelative(path);
    NSUInteger size = [data isKindOfClass:NSData.class] ? data.length : 0;
    NSString *folder = relative.length ? [relative stringByDeletingLastPathComponent] : @"";
    NSString *file = relative.length ? relative.lastPathComponent : @"";
    NSString *caseDiagnostic = XITCaseDiagnostic(relative);
    NSString *plan = XITPlanForRelativePath(relative);

    NSString *status = @"OK";
    NSMutableArray<NSString *> *issues = [NSMutableArray array];

    if (!bundle.length) {
        status = @"ERROR";
        [issues addObject:@"Falta bundle ID."];
    }
    if (XITPathHasUnsafeComponent(relative)) {
        status = @"ERROR";
        [issues addObject:@"La ruta contiene componentes no permitidos."];
    }
    if (XITLooksLikeFolderPath(relative)) {
        status = @"ERROR";
        [issues addObject:@"La ruta parece carpeta. Debe ser archivo exacto."];
    }
    if (!size) {
        status = @"ERROR";
        [issues addObject:@"El archivo nuevo está vacío o inválido."];
    }
    if ([caseDiagnostic hasPrefix:@"ERROR"]) {
        status = @"ERROR";
        [issues addObject:caseDiagnostic];
    }

    NSString *existence = @"NO COMPROBADO EN V18B: este modo no toca el destino.";
    NSString *wouldUse = [status isEqualToString:@"OK"] ? @"replace si existe / create si falta" : @"bloqueado hasta corregir errores";

    NSString *message = [NSString stringWithFormat:
        @"MODO DIAGNÓSTICO XITFORGE V18B\n\n"
         "Estado: %@\n\n"
         "Bundle:\n%@\n\n"
         "Ruta exacta:\n%@\n\n"
         "Carpeta destino:\n%@\n\n"
         "Archivo:\n%@\n\n"
         "Tamaño archivo nuevo:\n%lu bytes\n\n"
         "Mayúsculas:\n%@\n\n"
         "Existencia:\n%@\n\n"
         "Decisión:\n%@\n\n"
         "%@\n\n"
         "Problemas:\n%@\n\n"
         "No se escribió, no se creó, no se reemplazó y no se eliminó ningún archivo.",
         status,
         bundle.length ? bundle : @"(vacío)",
         relative.length ? relative : @"(vacía)",
         folder.length ? folder : @"(sin carpeta)",
         file.length ? file : @"(sin nombre)",
         (unsigned long)size,
         caseDiagnostic,
         existence,
         wouldUse,
         plan,
         issues.count ? [issues componentsJoinedByString:@"\n"] : @"ninguno"];

    if (error) *error = XITDiagnosticError(1810, message);
    NSLog(@"%@", message);
    return NO;
}

static void XITInstallDiagnosticOnly(void) {
    Class cls = NSClassFromString(@"XFAirLiftBackend");
    if (!cls) return;

    SEL selector = NSSelectorFromString(@"replaceFileForApplication:relativePath:data:error:");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;

    IMP current = method_getImplementation(method);
    if (current == (IMP)XITDiagnosticReplaceFile) return;

    XITOriginalReplaceFileIMP = current;
    method_setImplementation(method, (IMP)XITDiagnosticReplaceFile);

    NSLog(@"XITFORGE V18B: replaceFileForApplication interceptado en diagnóstico de existencia/plan.");
}

__attribute__((constructor))
static void XITDiagnosticOnlyConstructor(void) {
    XITInstallDiagnosticOnly();

    dispatch_async(dispatch_get_main_queue(), ^{
        XITInstallDiagnosticOnly();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XITInstallDiagnosticOnly();
        });
    });
}
