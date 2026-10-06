#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lector pequeño y retrocompatible para el campo nuevo del panel.
/// No cambia el campo legacy `bundleId`.
@interface XFTunnelV2Config : NSObject

/// Devuelve el Bundle ID nuevo de Tunnel V2 si existe y es válido.
/// Si no existe, devuelve nil.
+ (nullable NSString *)tunnelBundleIdFromOptionDictionary:(NSDictionary *)option;

@end

NS_ASSUME_NONNULL_END
