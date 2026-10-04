# Qué hicimos para llegar a 1.3.1

## 1. Separar conexión de acceso a archivos

Se inspeccionaron la IPA 3105 suministrada y sus registros para identificar el emparejamiento, el túnel RPPairing, el descubrimiento RSD y los servicios ATC y streaming_zip. Se añadieron pairing/PIN e importación del registro, y se mantuvieron separados los indicadores de túnel conectado y pairing guardado. Ninguno de esos indicadores garantiza por sí solo permiso para leer una app.

## 2. Conectar el catálogo y las rutas de acceso

Se incorporaron catálogo de apps, CoreDevice FileService, acceso a documentos mediante HouseArrest/AFC y la solicitud nativa MHA-C2. La ruta nativa valida la identidad de firma, el contenedor y la vigencia del acceso. Los servicios y permisos disponibles se comprueban en cada conexión; no se presupone que anunciar un túnel anuncie también FileService.

En Rust se corrigieron la lectura de anuncios RSD, el transporte de datos binarios, límites y tiempos de espera de AFC, el atributo LinkTarget y el manejo de resultados de FileService. Se conservó la ABI de handles opacos. native/XITFORGE_PATCHES.md y native-tracked-changes.patch documentan los cambios; el código final completo está incluido.

## 3. Entender Afc(PermDenied)

Los fallos sucesivos incluían servicio no anunciado, InstallationLookupFailed, autenticación Grappa, BrokenPipe y denegación de listado. La comparación decisiva fue el registro de 3105 en 24A437: **3105 también fallaba al enumerar carpetas**, pero completaba una copia y un reemplazo de un archivo cuya ruta ya conocía.

No se encontró un permiso universal que convirtiera el listado denegado en permitido. La diferencia útil era la operación de archivo por ruta conocida. El informe histórico 3105_24A437_COMPARACION_RUNTIME.md conserva la evidencia, con las rutas e identificadores personales omitidos. Sus apartados sobre funciones todavía pendientes describen el estado 1.2.9, no el módulo actual.

## 4. Leer y reemplazar por ruta conocida

Se implementó una transacción nueva: identificar la app y la ruta, registrar la intención, trasladar el original a un espacio propio, leerlo, conservar una copia local duradera y devolverlo o preparar el reemplazo. Los bytes nuevos se verifican antes de marcar el reemplazo como completado.

El registro liga dispositivo, ruta, transacción y copias. Se guarda y sincroniza antes de los movimientos. Los errores de permisos, sockets y análisis nunca se tratan como desaparición. Un estado ambiguo conserva datos y bloquea operaciones nuevas hasta resolver la recuperación. La restauración explícita identifica el destino y avisa que puede reemplazar el contenido actual.

## 5. Corregir la espera al elegir el reemplazo

En 1.3.0, el callback del selector esperaba a que terminara una lectura coordinada antes de cerrar Archivos. Eso podía dejar la interfaz aparentemente inmóvil. En 1.3.1 se amplió el filtro de tipos, se pidió importar una copia y se cerró el selector antes de leer los bytes recibidos.

La lectura muestra progreso, permite cancelar, tiene un plazo de 30 segundos después de recibir la selección y descarta resultados tardíos. Se limita a un lector pendiente, fuera de la cola del túnel. Conserva la validación de archivo regular, el rechazo de enlaces y el límite de 64 MiB. Una descarga del proveedor anterior al callback sigue dependiendo de Archivos.

## 6. Añadir eliminación con respaldo

La eliminación reutiliza la operación por ruta conocida para retirar el original y conservarlo en un respaldo remoto propio y una copia local duradera. Se vuelve a comprobar el hash antes de confirmar. Si el servicio acredita la ausencia del destino, la interfaz informa Archivo eliminado; si deniega esa comprobación, informa Archivo trasladado al respaldo. El resultado ofrece guardar una copia.

La recuperación automática no vuelve a crear un archivo retirado intencionalmente. Antes de completar la eliminación, una interrupción deja disponible la restauración explícita del original. No se eliminan carpetas, no se hace borrado seguro y no se supone una operación atómica frente a una app que vuelva a crear el destino.

## 7. Construir y revisar la entrega

Se compilaron las ocho fuentes del módulo ARM64 sin avisos. El clasificador de recuperación pasó 51 casos nombrados y 5.265 combinaciones. La IPA final pasó 561 controles independientes de estructura, identidad, recursos, helper y carga única del módulo. Estos datos describen las pruebas efectuadas; no son una prueba física de UIKit ni de los servicios del iPhone.

El archivo incluido en releases/ es exactamente la IPA 1.3.1 entregada. No se incorpora la IPA de 3105 ni sus claves o registros privados. El proyecto contiene una implementación independiente y las dependencias nativas con sus licencias.
