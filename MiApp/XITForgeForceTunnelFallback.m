#import <Foundation/Foundation.h>

@interface XITForgeForceTunnelFallback : NSObject
@end

@implementation XITForgeForceTunnelFallback

+ (void)load {
    /*
     * NO volver a enganchar applyOption: aquí.
     *
     * XITForgeTwoFiles.m es ahora el único dueño del hook de ACTIVAR:
     * - conserva acceso local primero;
     * - carga tunnelBundleId desde el panel;
     * - registra legacy -> Tunnel V2;
     * - usa XITForgeFileEngine como fallback.
     *
     * Tener dos hooks distintos sobre applyOption: era una de las causas
     * de que unas compilaciones usaran bundleId viejo y otras no.
     */
    NSLog(@"XITFORGE: ForceTunnelFallback legacy desactivado.");
}

@end
