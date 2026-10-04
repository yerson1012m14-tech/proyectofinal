#import <Foundation/Foundation.h>

/*
 XITFORGE V17 — NO FORZAR HOUSE ARREST/AFC

 ACTIVAR usa Books/AirTraffic.
 El envío directo rápido está en XFAirTrafficDirectSend.m.
 SyncAllowed 8 mensajes + 3 intentos está en XFAirTrafficFastTimeout.m.
*/

__attribute__((constructor))
static void XITForgeV17UseATCDirectSend(void) {
    NSLog(@"XITFORGE V17: FastReplace desactivado. ACTIVAR usa ATC DirectSend.");
}
