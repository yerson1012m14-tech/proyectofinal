#import "XITForgeEngineManager.h"
#import <dlfcn.h>

static NSString *XITTestOwnDirectory(NSString *label, NSSearchPathDirectory directory) {
    NSArray<NSString *> *paths =
        NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
    NSString *folder = paths.firstObject;
    if (!folder.length) {
        return [NSString stringWithFormat:@"%@: no se obtuvo ruta", label];
    }

    // Archivo nuevo y único: evita sobrescribir archivos de la aplicación.
    NSString *filename = [NSString stringWithFormat:@".xitforge-diagnostic-%@.tmp",
        [[NSUUID UUID] UUIDString]];
    NSString *file = [folder stringByAppendingPathComponent:filename];
    NSString *nonce = [[NSUUID UUID] UUIDString];
    NSData *expected = [nonce dataUsingEncoding:NSUTF8StringEncoding];

    NSError *writeError = nil;
    BOOL wrote = [expected writeToFile:file
                              options:NSDataWritingAtomic
                                error:&writeError];
    if (!wrote) {
        return [NSString stringWithFormat:@"%@: escritura FALLÓ (%@)",
            label, writeError.localizedDescription ?: @"error desconocido"];
    }

    NSError *readError = nil;
    NSData *observed = [NSData dataWithContentsOfFile:file
                                              options:0
                                                error:&readError];
    BOOL matches = observed && [observed isEqualToData:expected];

    NSError *deleteError = nil;
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:file
                                                              error:&deleteError];

    if (!matches) {
        return [NSString stringWithFormat:@"%@: lectura FALLÓ (%@). Limpieza: %@",
            label,
            readError.localizedDescription ?: @"contenido distinto",
            removed ? @"OK" : @"falló"];
    }
    if (!removed) {
        return [NSString stringWithFormat:@"%@: lectura/escritura OK, borrado FALLÓ (%@)",
            label, deleteError.localizedDescription ?: @"error desconocido"];
    }
    return [NSString stringWithFormat:@"%@: lectura, escritura y borrado OK", label];
}

// Consulta pasiva de compatibilidad publicada; no invoca exploits.
// 3105: https://github.com/YangJiiii/3105 (Compatibility)
// worse_query: https://github.com/forcequitOS/worse_query (README)
static BOOL XITVersionInRange(NSOperatingSystemVersion os,
                              NSInteger major, NSInteger minMinor, NSInteger minPatch,
                              NSInteger maxMinor, NSInteger maxPatch) {
    if (os.majorVersion != major) return NO;
    if (os.minorVersion < minMinor || os.minorVersion > maxMinor) return NO;
    if (os.minorVersion == minMinor && os.patchVersion < minPatch) return NO;
    if (os.minorVersion == maxMinor && os.patchVersion > maxPatch) return NO;
    return YES;
}

static NSString *XITEngineCompatibility(NSString *engine, NSOperatingSystemVersion os) {
    if ([engine isEqualToString:@"worse_query"]) {
        BOOL inRange = XITVersionInRange(os, 26, 0, 0, 7, 2) ||
                       XITVersionInRange(os, 27, 0, 0, 2, 0);
        return inRange
            ? @"Compatibilidad publicada: este iOS está en el rango. No enlazado ni probado."
            : @"Compatibilidad publicada: fuera del rango documentado. No ejecutar.";
    }
    if ([engine isEqualToString:@"3105 kexploit"]) {
        BOOL inRange = XITVersionInRange(os, 17, 0, 0, 7, 0) ||
                       XITVersionInRange(os, 18, 0, 0, 7, 1);
        return inRange
            ? @"Compatibilidad publicada: este iOS está en el rango. No enlazado ni probado."
            : @"Compatibilidad publicada: fuera del rango documentado para kexploit. No ejecutar.";
    }
    return @"Sin matriz de compatibilidad.";
}

@implementation XITForgeEngineManager

+ (NSDictionary<NSString *, id> *)buildManifest {
    NSString *path = [[NSBundle mainBundle]
        pathForResource:@"XITForgeEngineManifest" ofType:@"json"];
    if (!path.length) return @{};

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @{};

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSDictionary class]]) return @{};
    return (NSDictionary<NSString *, id> *)object;
}

+ (BOOL)filzaSymbolsAvailable {
    // Solo comprueba símbolos; no invoca exploits ni cambia permisos.
    return dlsym(RTLD_DEFAULT, "MCMFilzaStart") != NULL &&
           dlsym(RTLD_DEFAULT, "MCMFilzaDataContainerPath") != NULL;
}

+ (NSString *)diagnosticReport {
    NSDictionary<NSString *, id> *manifest = [self buildManifest];
    id rawEntries = manifest[@"components"];
    NSArray *entries = [rawEntries isKindOfClass:[NSArray class]]
        ? (NSArray *)rawEntries : @[];

    NSOperatingSystemVersion os = [NSProcessInfo processInfo].operatingSystemVersion;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"iOS: %@",
        [NSProcessInfo processInfo].operatingSystemVersionString]];

    BOOL filzaAPI = [self filzaSymbolsAvailable];
    [lines addObject:[NSString stringWithFormat:@"FilzaSlop: %@",
        filzaAPI ? @"API base detectada" : @"API base no detectada"]];

    // Mostrar la biblioteca que contiene el símbolo, si es posible.
    void *symbol = dlsym(RTLD_DEFAULT, "MCMFilzaStart");
    if (symbol) {
        Dl_info info = {0};
        if (dladdr(symbol, &info) != 0 && info.dli_fname) {
            NSString *library = [[NSString stringWithUTF8String:info.dli_fname]
                lastPathComponent];
            if (library.length) {
                [lines addObject:[NSString stringWithFormat:@"Biblioteca cargada: %@",
                    library]];
            }
        }
    }
    [lines addObject:@"Acceso de FilzaSlop a otras aplicaciones: NO probado."];

    for (id rawEntry in entries) {
        if (![rawEntry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *entry = (NSDictionary *)rawEntry;
        id rawId = entry[@"id"];
        if (![rawId isKindOfClass:[NSString class]]) continue;
        NSString *identifier = (NSString *)rawId;
        if ([identifier isEqualToString:@"FilzaSlop"]) continue;

        id rawRevision = entry[@"revision"];
        NSString *revision = [rawRevision isKindOfClass:[NSString class]]
            ? (NSString *)rawRevision : @"desconocida";
        id rawMode = entry[@"mode"];
        NSString *mode = [rawMode isKindOfClass:[NSString class]]
            ? (NSString *)rawMode : @"desconocido";
        NSString *shortRev = revision.length > 10
            ? [revision substringToIndex:10] : revision;

        [lines addObject:[NSString stringWithFormat:@"%@: %@ (rev. %@)\n%@",
            identifier, mode, shortRev, XITEngineCompatibility(identifier, os)]];
    }

    if (entries.count == 0) {
        [lines addObject:@"Manifiesto ausente o ilegible en la IPA."];
    }

    [lines addObject:@"worse_query y 3105: registrados como fuente; no enlazados ni ejecutables."];
    [lines addObject:@"Prueba local disponible: solo Documents/Caches de XITFORGE."];
    return [lines componentsJoinedByString:@"\n\n"];
}


+ (NSString *)localSandboxTestReport {
    // Nunca usa rutas de terceros, escalada de privilegios ni funciones
    // de FilzaSlop. Solo invocación explícita del usuario en Ajustes.
    NSString *documents = XITTestOwnDirectory(@"Documents", NSDocumentDirectory);
    NSString *caches = XITTestOwnDirectory(@"Caches", NSCachesDirectory);

    return [NSString stringWithFormat:
        @"Prueba del sandbox PROPIO de XITFORGE\n\n%@\n\n%@\n\n"
        @"Esta prueba NO comprueba el escape del sandbox, el acceso a otras apps "
        @"ni el funcionamiento de FilzaSlop, worse_query o 3105.",
        documents, caches];
}

@end
