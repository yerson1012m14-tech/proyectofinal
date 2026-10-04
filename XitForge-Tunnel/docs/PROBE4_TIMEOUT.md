# 1.3.2-probe4: recuperar Timeout antes del movimiento

El diagnóstico de eliminación suministrado el 4 de octubre de 2026 reporta Timeout 109/0 esperando SyncAllowed, un intento y fileMoveAttempted=false. No confirma eliminación. La prueba de creación anterior sí reportó lectura verificada tras reconectar.

La política anterior solo reintentaba errores nativos Socket (1). Esta revisión también acepta Timeout (109/0), conservando el límite de tres intentos y la exigencia de abrir un túnel independiente. Cada sesión fallida se cierra antes de abrir la siguiente. No se continúa leyendo sobre un flujo que pudo haber recibido parte de un mensaje antes del timeout.

Un timeout después de intentar FileComplete no autoriza repetir el movimiento. Los rechazos del protocolo, la denegación de permisos y los errores de otros dominios tampoco autorizan reintentos.

Validación: compilación ARM64; nueve escenarios de transporte, ocho casos de clasificación nativa, pausas y 48 combinaciones de la política. La eliminación en un iPhone sigue pendiente: el cambio corrige el caso sin reintento, pero no garantiza que el servicio responda.

Reemplaza los archivos del ZIP sobre probe3 y compila 1.3.2-probe4. Usa «Comprobar y eliminar prueba» para el registro pendiente. El resultado solo confirma limpieza cuando informa que el archivo está ausente.
