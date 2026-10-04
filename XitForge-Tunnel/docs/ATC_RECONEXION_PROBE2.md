# Corrección de recuperación de conexión: 1.3.2-probe2

El diagnóstico recibido muestra que el contenedor se resolvió y AirTraffic respondió ReadyForSync, pero la conexión se cerró al esperar AssetManifest. No se había enviado FileComplete en esa sesión.

La revisión del binario de 3105 suministrado encontró una diferencia verificable: `_AirLiftOpenATCSyncRetrying` (0x1000162f0) abre un túnel, ejecuta ATCBegin y ATCSyncToManifest; si fallan, libera el flujo y destruye el túnel. Hace hasta tres intentos, con pausas de 300 y 600 milisegundos. Referencias de instrucciones: llamadas 0x1000163e4/0x100016410, cierre 0x100016440/0x100016460, límite 0x10001649c y espera 0x1000164a8. El binario analizado tiene SHA256 C9194B58967059F9EB84622C465EE87CEF27174F1BEAFA1C401CCC17806A2442.

XitForge se detenía en el primer fallo. Ahora puede renovar la sesión antes de mover archivos, tanto al preparar el enlace como al abrir una operación de archivo. Solo reintenta errores nativos de socket, con un túnel independiente disponible. No reintenta denegaciones de permisos, rechazos del protocolo ni fallos después de intentar enviar FileComplete, incluso si el envío fue parcial. Los temporales y el registro de recuperación se conservan entre intentos; no se repite toda la transacción.

El diagnóstico conserva los códigos nativos y agrega syncAttempts y syncAttempt para distinguir cada intento. Se mantienen las comprobaciones de ausencia, contenido y recuperación existentes.

## Validación

- Compilación ARM64 del módulo completada.
- Seis escenarios simulados de transporte: recuperación al segundo intento, límite de tres fallos, envío parcial sin repetición, rechazo sin repetición, ausencia de túnel independiente y éxito inicial.
- Pruebas de pausas y 48 combinaciones de la política de reintento.
- Pruebas anteriores de ausencia y recuperación aprobadas.

Esto corrige una diferencia concreta de recuperación frente a 3105. No demuestra la causa del cierre remoto ni garantiza que un fallo persistente desaparezca. Esta versión no se ha probado en un iPhone.

## Instalación

Extrae el ZIP de cambios en la raíz del proyecto 1.3.2-probe1, reemplaza los archivos y compila con el workflow. El artefacto será `Mi-App-XitForge-1.3.2-probe2` y la IPA `XitForge-1.3.2-probe2-unsigned.ipa`.

Si la prueba anterior sigue pendiente, usa «Comprobar y eliminar prueba». Cuando confirme ausencia podrás repetir «Crear archivo de prueba». Si falla, «Copiar resultado» incluirá los intentos y el punto en que terminó cada uno.
