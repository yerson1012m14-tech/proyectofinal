# XitForge 1.3.2-probe1: prueba de creación

Esta versión agrega «Crear archivo de prueba» en la pantalla del túnel. Es una prueba de creación de un texto nuevo; todavía no habilita subir cualquier archivo a una ruta nueva.

## Obtener la IPA

Sube los archivos de este proyecto a tu repositorio, incluida `.github/workflows/build.yml`. La compilación de GitHub Actions genera el artefacto **Mi-App-XitForge-1.3.2-probe1**, con **XitForge-1.3.2-probe1-unsigned.ipa**. Esa IPA necesita la firma que usas normalmente.

La carpeta `XitForge-Tunnel/releases` conserva la IPA anterior 1.3.1 como archivo histórico: **no contiene esta prueba**. El módulo nuevo sí está compilado en `XitForge-Tunnel/prebuilt/XFAirLift.dylib`; no se ha compilado aquí una IPA completa de esta versión del proyecto.

## Probar en el iPhone

1. Conecta el túnel con el emparejamiento de ese mismo iPhone.
2. Abre **Crear archivo de prueba**. Introduce el identificador de la app y una carpeta existente, por ejemplo `Documents`.
3. Cierra la app de destino y pulsa **Crear archivo de prueba**. El nombre se genera automáticamente: `xitforge_prueba_<UUID>.txt`.
4. Lee el resultado y usa **Copiar resultado** si necesitas compartirlo.
5. Pulsa **Comprobar y eliminar prueba** para retirar ese mismo archivo. El registro permanece pendiente hasta que el servicio confirme su ausencia.

## Qué comprueba

- Antes de escribir, exige una respuesta positiva de archivo ausente y verifica el enlace. `PermDenied` o una desconexión producen un resultado inconcluso; nunca se interpretan como ausencia.
- Escribe el texto generado, lo recupera desde la ruta de la app y compara todos sus bytes. Luego solicita devolverlo a la app; confirma ese movimiento por la desaparición del archivo de la zona temporal.
- El resultado de retorno no equivale a una segunda lectura directa en el destino. El protocolo tampoco ofrece una operación atómica de «crear solo si no existe»: se usa un nombre aleatorio y se comprueba ausencia antes de cada envío. Mantén cerrada la app de destino durante la prueba.
- Para eliminarlo, comprueba el contenido. Si cambió, conserva el respaldo y permite la restauración existente; no declara una eliminación correcta.
- La recuperación automática de esta prueba solo limpia temporales cuyo contenido coincide con el marcador. No modifica automáticamente el destino de la app.

Se comprobó la compilación ARM64 y se ejecutaron pruebas locales de las decisiones de ausencia y de recuperación. **Falta ejecutar esta versión en un iPhone**. Tener el túnel conectado no confirma que iOS permita esta operación.
