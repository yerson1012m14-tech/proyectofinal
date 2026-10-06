#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFTunnelV2Config : NSObject

/// Lee y valida el campo opcional `tunnelBundleId` enviado por el panel.
+ (nullable NSString *)tunnelBundleIdFromOptionDictionary:(NSDictionary *)option;

/// Guarda la relación bundleId legacy -> tunnelBundleId.
/// Se usa para que los flujos existentes de Home/DESACTIVAR puedan seguir
/// pasando el bundleId legacy sin terminar apuntando al contenedor equivocado.
+ (void)rememberTunnelBundleId:(NSString *)tunnelBundleId
             forLegacyBundleId:(NSString *)legacyBundleId;

/// Devuelve el tunnelBundleId guardado para un bundleId legacy.
+ (nullable NSString *)tunnelBundleIdForLegacyBundleId:(NSString *)legacyBundleId;

/// YES si el valor ya está registrado como destino Tunnel V2.
+ (BOOL)isRememberedTunnelBundleId:(NSString *)bundleId;

@end

NS_ASSUME_NONNULL_END
