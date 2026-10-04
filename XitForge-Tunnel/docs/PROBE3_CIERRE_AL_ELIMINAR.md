# 1.3.2-probe3: manejo del cierre después de confirmar

El usuario informa un cierre inmediato tras confirmar «Comprobar y eliminar prueba». No se dispone de reporte .ips; la causa exacta no está confirmada.

Cambios:

- La operación espera a que termine la transición de la confirmación. Un guardia impide iniciar dos veces desde sus callbacks.
- Se comprueba el registro de la prueba y se proporciona una cola serial si el controlador no recibe una.
- El ejecutor NSThread devuelve las excepciones Objective-C a su llamador síncrono. Antes, un catch en el llamador no podía recibir una excepción de ese hilo.
- La operación de prueba captura la excepción en el hilo nativo, conserva el registro de recuperación y devuelve un error. No realiza reintentos ni consultas nativas adicionales después de esa excepción. La pantalla pide reiniciar la app y no declara eliminación correcta.
- Los errores al preparar el diagnóstico también se convierten en un resultado inconcluso.

Este manejo no intercepta señales fatales, corrupción de memoria, abortos de Rust ni terminaciones de iOS. No se afirma que el cierre observado esté resuelto sin comprobarlo en el dispositivo.

Validación local: módulo ARM64 compilado; fixture del ejecutor compilado para ARM64. La prueba de ejecución del ejecutor requiere Foundation de macOS y se incorpora a GitHub Actions. La transición de UIKit y el borrado físico siguen pendientes de validación en iPhone.

Instalación: reemplaza los archivos del ZIP sobre el proyecto actual y compila 1.3.2-probe3. Si aparece un mensaje en pantalla, usa «Copiar resultado».
