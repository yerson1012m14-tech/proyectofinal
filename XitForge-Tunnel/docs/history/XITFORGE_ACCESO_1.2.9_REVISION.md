# XitForge 1.2.9: revisión y entrega

Se preparó `XITFORGE_10.0.15_ACCESO_1.2.9_unsigned.ipa` con las correcciones comprobadas al comparar las rutas de archivos del ejecutable suministrado de 3105, XitForge 1.2.8 y el componente de permisos ya incluido en la IPA original de XitForge. El paquete se verificó estructuralmente; no se ejecutó en el iPhone.

## Qué se encontró y se corrigió

| Diferencia comprobada | Corrección en esta versión |
| --- | --- |
| 3105 crea una conexión RPPairing/RSD nueva antes de FileService. XF usaba el mapa inicial y podía omitirlo. | Conexión propia por operación de listado o lectura, también para App Groups. Su canal de descarga usa ese mismo adaptador. |
| 3105 agrupa descendientes como Library/Caches/archivo; XF descartaba rutas con /. | Parser de rutas seguras con agrupación y clasificación de carpetas. Las cuatro raíces de navegación se añaden solo tras una respuesta FileService correcta. |
| 3105 y el helper original de XF comprueban si pueden abrir la raíz incluso cuando una activación no concede un permiso nuevo. El módulo abortaba antes de comprobarlo. | Apertura de lectura de una raíz UUID validada. Reconoce permisos ya existentes y vuelve a comprobar la apertura tras un resultado de activación negativo. |
| 3105 dispone del permiso alternativo BadQuery en cuatro betas concretas; el módulo no lo tenía. | Se solicita y libera el permiso para la raíz seleccionada, con lectura acotada a ese contenedor, únicamente en los cuatro builds que reconoce ese ejecutable. |
| Algunos identificadores de cliente en la conversación AirLift diferían. | Host de transporte y Label de check-in airlift-mini; HostInfo airlift/27.0, según el binario inspeccionado. No se presenta este cambio como una concesión de permisos. |
| FileService podía esperar sin plazo y reservar una descarga antes de comprobar su tamaño. | Plazos nativos de 15 segundos para control y 60 para descarga; rechazo de más de 128 MiB antes de reservar memoria; descarte de sesiones incompletas. |

La consulta MHA también vuelve a obtener el objeto de activación como hace 3105 y verifica que corresponda a la misma raíz. Se corrige el caso en que la activación devuelve éxito pero la apertura sigue denegada. Los permisos se mantienen durante la lectura/listado y se liberan después.

También se comprobó el emparejamiento: modelo Mac17,7, PIN obligatorio, roles device/host, PairVerify y versión de protocolo 19 coinciden con 3105. Los flags de PairSetup/Bonjour coinciden; no se habilitaron flags distintos como supuesto arreglo de AFC. En el binario, prepareHost establece pinless=false en 0x10001d7d8, el rol device aparece en 0x100434a34, el rol host en 0x100436e5c y PairVerify en 0x100452158.

El diagnóstico registra `kernelBuild` mediante kern.osversion, `nativeContainerAttempt`, la etapa de BadQuery cuando falla y `fileServiceAttempt`. Los campos nuevos excluyen identificadores de apps, rutas y tokens.

## Compatibilidad de la vía alternativa

El ejecutable de 3105 selecciona BadQuery en `24A5355q`, `24A5370h`, `24A5380h` y `24A5390f`; en `24A437` selecciona AirLift. Esta versión conserva esa restricción para BadQuery. El marketing “iOS 27.0” no distingue esos builds. El código de lectura local también puede reconocer acceso ya concedido en otros builds, siempre que la apertura real lo permita.

Las cifras históricas de los archivos aportados difieren: el log de 3105 indica 24A5355q y el diagnóstico anterior de XF indica 24A437. La inspección del helper original no encontró una falsificación de la versión del sistema. Estos archivos no prueban la ruta usada por el 3105 que ahora logra abrir la carpeta.

## Qué hace 3105 con los archivos

El binario incluye listado, lectura de contenido, previsualización/exportación, además de funciones de modificación. El navegador de apps toma el `Container` validado del catálogo y abre Data/Application o Shared/AppGroup; no toma la carpeta Bundle/Application de la .app. XF busca esos mismos contenedores.

La lectura de esta versión se realiza mediante acceso local, FileService o HouseArrest. La vía ATC/AFC incorporada sigue siendo de listado. La lectura AirLift de archivos conocidos encontrada en 3105 mueve temporalmente un archivo fuera del contenedor y lo devuelve después; esa operación no se añadió como lectura en esta versión.

## Qué significa el error actual

`Afc(PermDenied)` (`106/10`) significa que AFC denegó el listado solicitado. No encontramos una credencial adicional entregada a AFC por 3105, ni una diferencia en la cabecera/opcode de ReadDir que justifique cambiar su formato. Se verificó el orden de check-in, apertura de sesiones independientes, manifiesto, traslado y listado.

La preparación de Books sigue preservando y restaurando sus datos. 3105 elimina seis archivos de sincronización; no se demostró que esa diferencia explique una denegación posterior a confirmar el enlace y no se sustituyó la preservación por borrado.

Las correcciones eliminan diferencias reales y añaden una vía local ausente. No está demostrado que eliminen el rechazo en este iPhone: no se observó una operación actual de apertura exitosa en 3105 ni se ejecutó la IPA entregada en el teléfono. El log recibido de 3105 contiene pruebas de conexión, no la transacción de apertura de la carpeta.

## Verificación del paquete

- ARM64 MH_DYLIB compilado y enlazado; el código y datos originales después de la cabecera del ejecutable permanecen idénticos.
- Se conserva exactamente el helper FilzaApplySandboxExt original y los recursos originales. Se añade una sola dependencia del nuevo módulo.
- 191 comprobaciones del parser de rutas y 323 del puente de concesión: cero fallos. Estas pruebas ejecutan el C usado por el módulo con entradas y callbacks simulados.
- La capa nativa pasó sus pruebas de protocolo, datos fragmentados, EOF, tamaños excesivos, cancelación, descarte de sesiones y propiedad de buffers C. El informe adjunto detalla las suites y la compilación ARM64.
- Archivo ZIP sin entradas duplicadas ni errores CRC; identificador com.apple.mobile.MobileHouseArrest conservado; paquete sin firmar.

SHA-256 de la IPA: `752ae24f81cc1438c5927849dd0d3761bb7e91d892c8ba93953ae58835025022`.

Para instalarla hay que firmar la app y sus dylibs conservando `com.apple.mobile.MobileHouseArrest`. El módulo comprueba la identidad firmada del proceso para MHA; cambiar únicamente Info.plist no sustituye esa identidad.

## Fuentes y evidencia

El ZIP de fuentes contiene el módulo, las modificaciones Rust, fixtures y los informes/disassemblies relevantes del ejecutable, con las dependencias declaradas. Excluye claves de emparejamiento y binarios de 3105.

La comparación primaria fue el ejecutable de la IPA suministrada, SHA-256 c9194b58967059f9eb84622c465ee87cef27174f1beafa1c401ccc17806a2442. La documentación pública se usó como contraste: [ContainerManager de 3105](https://github.com/YangJiiii/3105/blob/main/ThreeOneOSFive/exploit/mcm_bridge.m), [bad_query](https://github.com/forcequitOS/bad_query) y [proyecto 3105](https://github.com/YangJiiii/3105). El comportamiento de la conexión nueva, la selección exacta de builds y las ramas del navegador se confirmaron en el binario suministrado.
