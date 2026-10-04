#import <Foundation/Foundation.h>

/*
 XITFORGE V18A — DIAGNÓSTICO SOLAMENTE

 Este archivo deja desactivado el FastReplace.
 La lógica de diagnóstico está en XITForgeDiagnosticOnly.m.

 Este modo NO escribe.
 Este modo NO reemplaza.
 Este modo NO crea archivos.
*/

__attribute__((constructor))
static void XITForgeV18ADiagnosticMode(void) {
    NSLog(@"XITFORGE V18A: FastReplace desactivado. Modo diagnóstico solamente.");
}
