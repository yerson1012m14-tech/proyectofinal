#import <Foundation/Foundation.h>

/*
 XITFORGE V18B — DIAGNÓSTICO DE RUTA / EXISTENCIA PLAN

 FastReplace queda desactivado.
 La lógica está en XITForgeExistenceDiagnostic.m.

 Este modo NO escribe.
 Este modo NO crea.
 Este modo NO reemplaza.
 Este modo NO elimina.
*/

__attribute__((constructor))
static void XITForgeV18BDiagnosticMode(void) {
    NSLog(@"XITFORGE V18B: FastReplace desactivado. Diagnóstico de ruta/existencia solamente.");
}
