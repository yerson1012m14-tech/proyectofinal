#import <Foundation/Foundation.h>

/*
 XITFORGE V16 — NO FORZAR HOUSE ARREST/AFC

 Este archivo reemplaza XFAirLiftFastReplace.m.

 Mantiene ACTIVAR usando el replace original por Books/AirTraffic.
 El ajuste fino de SyncAllowed/reintentos está en XFAirTrafficFastTimeout.m.
*/

__attribute__((constructor))
static void XITForgeV16UseOriginalAirTrafficReplace(void) {
    NSLog(@"XITFORGE V16: FastReplace desactivado. ACTIVAR usa Books/AirTraffic con SyncAllowed 8 mensajes.");
}
