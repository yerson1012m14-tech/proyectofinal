# Mapa de componentes

| Archivo | Responsabilidad |
|---|---|
| module/XFAirLiftInstaller.m | Añade una sola pestaña Túnel al mainTabBar existente |
| module/XFAirLiftViewController.m | Catálogo, rutas conocidas, PIN, selección de reemplazo, confirmaciones y estados |
| module/XFOnDevicePairing.m | Anuncio Bonjour, pair-setup, presentación y aprobación del PIN, guardado del pairing |
| module/XFAirLiftBackend.m | Worker serial nativo, conexión, RSD, catálogo y selección de rutas de archivos |
| module/XFATCDirectory.m | Servicios ATC/streaming_zip/AFC, registros duraderos, movimientos y recuperación |
| module/XFATCFileRecovery.h | Clasificador puro C de estados de lectura, reemplazo y eliminación |
| module/XFATCFileRecoveryFixtures.c | Casos y combinaciones de recuperación |
| module/XFATCZip.c | Construcción del archivo temporal de directorios usado por el protocolo |
| module/XFGrappaHelper.m | Preparación de autenticación y selección de parámetros Grappa |
| module/XFMHAContainerAccess.m | Solicitud y duración del acceso nativo MHA al contenedor, con validación de rutas |
| module/XFContainerGrant.h | Política y puente de concesión del contenedor |
| module/XFFileServiceListing.h | Validación del listado recibido por FileService |
| module/XFStreamBridge.h / idevice.h | ABI C para las bibliotecas nativas, con handles opacos |
| native/ffi/src/xf_stream.rs | Puente de streams binarios, servicios RSD, AFC y metadatos exactos |
| native/idevice/src/services/rsd.rs | Lectura tolerante y validada de anuncios de servicios |
| native/idevice/src/services/afc/ | Límites de tramas, tiempos de espera, invalidación y LinkTarget |
| native/idevice/src/services/core_device/file_service.rs | Manejo y validación de listados FileService |
| native/plist_ffi_local/ | Dependencia plist_ffi fijada; adaptación de generación de cabeceras para compilación |
| module/package_ipa.py | Añade el módulo a una copia de la IPA y verifica su estructura |

El worker nativo mantiene los handles y su uso en el mismo hilo. La lectura del archivo elegido en Archivos se ejecuta aparte para que un proveedor de documentos no detenga el túnel ni la recuperación.

prebuilt/ contiene los dos binarios exactos de la entrega. RELEASE.json registra sus hashes. SHA256SUMS.json inventaría todos los archivos de esta carpeta, salvo el propio inventario.
