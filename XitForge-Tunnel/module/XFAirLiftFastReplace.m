#import <Foundation/Foundation.h>

/*
 XITFORGE V14 — USAR RUTA BOOKS/AIRTRAFFIC EXACTA

 Este archivo reemplaza XFAirLiftFastReplace.m de V10/V11/V12/V13.

 IMPORTANTE:
 - V10/V11/V12/V13 interceptaban replaceFileForApplication y forzaban House Arrest/AFC.
 - En tu iPhone House Arrest/AFC falla para com.dts.freefireth.
 - La prueba manual mostró que el método Books/AirTraffic sí puede eliminar/reemplazar por ruta exacta.

 Por eso esta V14 NO instala ningún hook.
 Al no enganchar replaceFileForApplication:, se usa el método original de XFAirLiftBackend.m:

   - (BOOL)replaceFileForApplication:relativePath:data:error:

Ese método usa:
   AirTraffic / Books / ruta exacta / archivo exacto

No navega carpetas.
No usa House Arrest/AFC para activar.
No usa el bypass rápido que estaba fallando.
*/

__attribute__((constructor))
static void XITForgeV14UseOriginalAirTrafficReplace(void) {
    NSLog(@"XITFORGE V14: FastReplace desactivado. ACTIVAR usará XFAirLiftBackend original por Books/AirTraffic.");
}
