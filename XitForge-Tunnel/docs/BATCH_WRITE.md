# XitForge batch write

El reemplazo de un archivo por ruta conocida usa una sola preparación de Books y una sesión agrupada de AirTraffic para la colocación. El original se captura antes de publicar los bytes nuevos y queda guardado en el registro de recuperación hasta que la verificación termina.

El diagnóstico `batchWrite.events` registra, en orden, estas etapas:

1. RPPairing record loaded
2. RSD tunnel established
3. AFC connected
4. preflight OK
5. stage zip reply = DataComplete
6. stage OK
7. Books/Sync/Books.plist written (4 rows)
8. ATC sync to manifest OK
9. placement FileComplete sent (3 messages, mode=replace)
10. verify OK
11. move-back FileComplete sent
12. BATCH WRITE COMPLETE

La sesión agrupada publica tres mensajes `FileComplete`: el enlace temporal hacia su zona de enlace, el archivo nuevo hacia la ruta seleccionada y la copia protegida hacia `FileVerify`. Después se comprueba el contenido, se envía el cuarto movimiento para devolver el archivo verificado a la ruta de la app y se restaura el manifiesto normal de la aplicación. Si una etapa falla, el registro y la copia original permanecen disponibles para recuperación.

La compilación local genera `module/build/XFAirLift.dylib` para arm64. La IPA final debe volver a empaquetarse y firmarse con el flujo habitual del proyecto; este cambio no inventa una firma ni elimina las protecciones de recuperación.
