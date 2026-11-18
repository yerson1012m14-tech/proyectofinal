#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Diagnóstico de estado; no inicia escapes del sandbox ni exploits del kernel.
@interface XITForgeEngineManager : NSObject
+ (NSDictionary<NSString *, id> *)buildManifest;
+ (BOOL)filzaSymbolsAvailable;
+ (NSString *)diagnosticReport;
@end

NS_ASSUME_NONNULL_END
