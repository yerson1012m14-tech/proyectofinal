#import <Foundation/Foundation.h>

/*
 XITFORGE V15 — NO FORZAR HOUSE ARREST/AFC

 Este archivo reemplaza XFAirLiftFastReplace.m.

 V10/V11/V12/V13 forzaban House Arrest/AFC y en tu caso esa ruta falla.
 V14 volvió al replace original por Books/AirTraffic.
 V15 mantiene ese flujo, pero agrega XFAirTrafficFastTimeout.m para que AirTraffic
 no haga 3 intentos largos ni espere demasiado SyncAllowed.
*/

__attribute__((constructor))
static void XITForgeV15UseOriginalAirTrafficReplace(void) {
    NSLog(@"XITFORGE V15: FastReplace desactivado. Replace usará Books/AirTraffic con timeout rápido.");
}
