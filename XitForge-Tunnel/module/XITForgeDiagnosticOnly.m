#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/*
 XITFORGE V18A — PLAN ONLY / DIAGNÓSTICO SEGURO

 Qué hace:
 - Intercepta replaceFileForApplication:relativePath:data:error:
 - No llama al reemplazo real.
 - No escribe archivo.
 - No crea archivo.
 - No elimina archivo.
 - Solo muestra el plan que usaría:
      * ruta exacta
      * carpeta destino
      * nombre de archivo
      * tamaño del archivo nuevo
      * decisión: primero verificar existencia; si existe replace, si falta create

 Importante:
 Este modo NO activa nada. Es solo para diagnosticar sin tocar el contenedor.
*/

static IMP XITOriginalReplaceFileIMP = NULL;

static NSString *XITSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSError *XITDiagnosticError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"XitForge.DiagnosticOnly"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Diagnóstico detenido."}];
}

static BOOL XITLooksLikeFolderPath(NSString *relative) {
    if (![relative isKindOfClass:NSString.class] || !relative.length) return YES;
    NSString *trim = [relative stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trim.length) return YES;
    if ([trim hasSuffix:@"/"]) return YES;
    NSString *last = trim.lastPathComponent ?: @"";
    return [@[@"Documents", @"Library", @"SystemData", @"tmp"] containsObject:last];
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

    NSString *status = @"OK";
    NSString *decision = @"PLAN: comprobar existencia primero; si existe usar replace, si falta usar create.";
    NSString *reason = @"Modo diagnóstico: no se modifica nada.";

    if (!bundle.length) {
        status = @"ERROR";
        decision = @"No se puede planear: falta bundle ID.";
    } else if (XITPathHasUnsafeComponent(relative)) {
        status = @"ERROR";
        decision = @"No se puede planear: ruta insegura.";
    } else if (XITLooksLikeFolderPath(relative)) {
        status = @"ERROR";
        decision = @"No se puede planear: la ruta parece carpeta, no archivo exacto.";
    } else if (!size) {
        status = @"ERROR";
        decision = @"No se puede planear: archivo nuevo vacío o inválido.";
    }

    NSString *folder = relative.length ? [relative stringByDeletingLastPathComponent] : @"";
    NSString *file = relative.length ? relative.lastPathComponent : @"";

    NSString *message = [NSString stringWithFormat:
        @"MODO DIAGNÓSTICO XITFORGE V18A\n\n"
         "Estado: %@\n\n"
         "Bundle:\n%@\n\n"
         "Ruta exacta:\n%@\n\n"
         "Carpeta destino:\n%@\n\n"
         "Archivo:\n%@\n\n"
         "Tamaño archivo nuevo:\n%lu bytes\n\n"
         "%@\n\n"
         "%@\n\n"
         "No se escribió, no se creó, no se reemplazó y no se eliminó ningún archivo.",
         status,
         bundle.length ? bundle : @"(vacío)",
         relative.length ? relative : @"(vacía)",
         folder.length ? folder : @"(sin carpeta)",
         file.length ? file : @"(sin nombre)",
         (unsigned long)size,
         decision,
         reason];

    if (error) *error = XITDiagnosticError(1800, message);

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

    NSLog(@"XITFORGE V18A: replaceFileForApplication interceptado en modo diagnóstico.");
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
