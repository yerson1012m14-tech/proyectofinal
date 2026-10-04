# Resultado de la inspección de 3105

Se examinó el ejecutable del IPA 3105 suministrado y se contrastó su comportamiento con fuentes primarias. El teléfono indicado tiene iOS 27.0.0, build 24A5355q, iPhone13,2.

**3105 sí tiene funciones para ver nombres y contenido de archivos.** Incluye además exportación, edición, reemplazo, creación y borrado. Tener esas funciones en el binario no garantiza permiso para cada app.

| Operación | Evidencia en el ejecutable suministrado |
|---|---|
| Listar mediante AirLift | La vista de navegador llama a AirLiftTransport.listEntries en 0x1001308b4. |
| Acceso nativo independiente | installedAppsFromMCM solicita clase 2 mediante MCMActivateContainerPath en 0x1000675a4. El bridge activa la extensión y conserva el objeto del contenedor. El navegador también contiene la alternativa MCMActivateContainer y listFilesChecked. |
| Abrir contenido | QuickLook llama a AirLiftTransport.read(reference) en 0x10013c7b4. El editor llama a la misma lectura y convierte los bytes a texto en 0x1003bf6f8. |
| Exportar | QuickLook escribe una copia local de los bytes en 0x10013cce8 y ofrece ShareLink de esa URL. |
| Reemplazar o editar | La importación llama a write(data:reference) en 0x1001353e8; guardar texto lo llama en 0x1003bfd3c. |
| Crear y borrar | Existen funciones nativas de creación y borrado verificado. La ruta de borrado AirLift lee y compara el contenido esperado antes de eliminar; la vista de navegador examinada utiliza también FileManager directamente. |

La lectura AirLift de esa vista termina en readFileArbitrary: traslada temporalmente el archivo a una zona accesible mediante AFC, lee sus bytes en 0x100014708 y solicita devolverlo en 0x1000147ac. El acceso directo nativo usa el permiso de ContainerManager y operaciones locales. Son rutas distintas.

## Por qué aparece PermDenied

En la ruta examinada, 106 corresponde al error AFC de la biblioteca nativa y 10 a **permiso denegado** de AFC. XitForge estaba intentando enumerar un enlace hacia el contenedor mediante AFC. Esa respuesta no significa que el PIN esté mal ni demuestra que el túnel completo se desconectó.

3105 también ejecuta afc_list_directory y propaga errores. Su texto interno distingue una carpeta que no puede enumerarse de un parche que puede actuar sobre rutas conocidas. Por tanto, 3105 no elimina esa restricción de AFC. Puede emplear otra ruta, incluido acceso nativo MHA-C2. Esa ruta faltaba en XitForge y se añadió en 1.2.7. El log suministrado de 3105 termina en pruebas de servicios: no identifica qué ruta abrió una carpeta concreta.

## Cambio aplicado a XitForge

1. Intenta MHA-C2 antes de exigir una conexión del túnel: activa el permiso del contenedor existente, lista o lee y libera el permiso al terminar.
2. Comprueba la identidad firmada com.apple.mobile.MobileHouseArrest. Ambas IPAs ya tienen ese identificador en Info.plist; el firmador debe conservar también la identidad del ejecutable.
3. Permite previsualizar/exportar por lectura directa. Limita archivos a 128 MB y no sigue enlaces simbólicos. Esta nueva ruta no escribe, crea, borra ni mueve archivos del contenedor.
4. Conserva CoreDevice, HouseArrest y AirTraffic como alternativas. Separa el error al listar la app de los errores de temporales en el diagnóstico.

La compilación ARM64, las comprobaciones de autenticación/transiciones y la integridad del paquete pasaron. La revisión independiente confirmó la duración del permiso, la identidad firmada y las rutas relativas de lectura. **No se verificó el IPA en un iPhone físico.** La concesión del permiso y la firma final deben comprobarse en el dispositivo.

Fuentes primarias: [3105 y sus requisitos de instalación](https://github.com/YangJiiii/3105), [MobileHouseArrest PoC](https://github.com/0xjohnnydev/MobileHouseArrest-PoC), [AirLift](https://github.com/0xjohnnydev/airlift), [códigos AFC](https://github.com/libimobiledevice/libimobiledevice/blob/master/include/libimobiledevice/afc.h), [XNU de Apple para csops](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c).
