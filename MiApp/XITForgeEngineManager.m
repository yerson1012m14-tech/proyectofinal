#import "XITForgeEngineManager.h"
#import <dlfcn.h>

@implementation XITForgeEngineManager

+ (NSDictionary<NSString *, id> *)buildManifest {
    NSString *path = [[NSBundle mainBundle]
        pathForResource:@"XITForgeEngineManifest" ofType:@"json"];
    if (!path.length) return @{};
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @{};
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:NSDictionary.class]) return @{};
    return object;
}

+ (BOOL)filzaSymbolsAvailable {
    // Verificación de enlace, NO de que el exploit funcione en el dispositivo.
    return dlsym(RTLD_DEFAULT, "MCMFilzaStart") != NULL &&
           dlsym(RTLD_DEFAULT, "MCMFilzaDataContainerPath") != NULL;
}

+ (NSString *)diagnosticReport {
    NSDictionary *manifest = [self buildManifest];
    NSArray *entries = manifest[@"components"];
    if (![entries isKindOfClass:NSArray.class]) entries = @[];

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"iOS: %@",
        [NSProcessInfo processInfo].operatingSystemVersionString]];
    [lines addObject:[NSString stringWithFormat:@"FilzaSlop: %@",
        [self filzaSymbolsAvailable] ? @"API detectada (sin probar acceso)"
                                    : @"API no detectada"]];

    for (id entry in entries) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = entry[@"id"];
        NSString *revision = entry[@"revision"];
        NSString *mode = entry[@"mode"];
        if (![identifier isKindOfClass:NSString.class]) continue;
        if ([identifier isEqualToString:@"FilzaSlop"]) continue;
        if (![revision isKindOfClass:NSString.class]) revision = @"desconocida";
        if (![mode isKindOfClass:NSString.class]) mode = @"desconocido";
        NSString *shortRev = revision.length > 10 ? [revision substringToIndex:10] : revision;
        [lines addObject:[NSString stringWithFormat:@"%@: %@ (rev. %@)",
            identifier, mode, shortRev]];
    }
    if (entries.count == 0) {
        [lines addObject:@"Manifiesto no encontrado en esta IPA."];
    }
    [lines addObject:@"worse_query y 3105 no están enlazados ni ejecutables en esta fase."];
    return [lines componentsJoinedByString:@"\n\n"];
}

@end
