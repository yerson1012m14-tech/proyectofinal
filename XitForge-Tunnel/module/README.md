# XitForge: archivos por ruta conocida — módulo 1.3.1

Esta versión corrige la espera del selector de reemplazo y añade eliminación de archivos por ruta conocida. Mantiene la lectura, exportación, reemplazo verificado y recuperación de 1.3.0.

## Uso

Firma la IPA y sus dylibs conservando la identidad com.apple.mobile.MobileHouseArrest. Conecta el túnel con el emparejamiento de ese iPhone, selecciona una app y entra en **Abrir ruta**. Introduce una ruta relativa completa, por ejemplo Documents/carpeta/archivo.ext.

- **Reemplazar archivo**: en Archivos elige el archivo nuevo cuyos bytes sustituirán al destino. La selección importa una copia; cuando Archivos la entrega, XitForge cierra el selector y muestra una lectura cancelable. Revisa la app, el destino y el tamaño antes de confirmar.
- **Eliminar archivo**: confirma la app y la ruta. El original se traslada a un respaldo propio y se guarda una copia local duradera antes de confirmar la operación. El resultado ofrece **Guardar copia original**. Solo dice Archivo eliminado si el servicio confirma que el destino está ausente; cuando iOS deniega esa comprobación, informa Archivo trasladado al respaldo.
- **Restaurar original pendiente**: úsalo para la misma app y ruta si una operación quedó interrumpida antes de completarse. Requiere confirmación porque puede reemplazar el contenido actual. Una eliminación ya completada no se deshace automáticamente al reconectar.

Cierra la app de destino durante las operaciones. El límite es 64 MiB por archivo; no se eliminan carpetas. Conserva XitForge y sus datos mientras haya una recuperación pendiente. Guarda las copias antes de desinstalarlo.

## Selector de reemplazo

El selector acepta tipos de archivo generales e importa una copia. La lectura local se ejecuta fuera de la cola del túnel, valida que el origen sea regular, rechaza enlaces, limita el tamaño y detecta cambios durante la lectura. La interfaz permite cancelar y deja de esperar a los 30 segundos. Los resultados tardíos no muestran confirmaciones ni modifican archivos. Si un proveedor tarda antes de entregar la selección a la app, ese tiempo lo controla Archivos; descarga el archivo antes de elegirlo.

## Alcance

La operación AirLift usa un traslado temporal o definitivo del archivo existente; los permisos para listar carpetas siguen siendo independientes. El log aportado de 3105 también registra PermDenied al listar carpetas, aunque completa lectura y reemplazo de una ruta conocida. Esta versión no afirma corregir permisos de exploración.

El protocolo no ofrece una colocación atómica sin conflictos con una app que modifique o recree el destino. Los permisos denegados, errores de conexión y estados desconocidos no se convierten en una confirmación de ausencia. Las copias se conservan con registros de dispositivo, ruta y transacción.

## Compilación y comprobación

build-windows-local.py usa el LLVM, el SDK de iPhone y la biblioteca idevice ARM64 ya presentes en el workspace. package_ipa.py genera una copia de la IPA original con el módulo 1.3.1; verifica su estructura y la conservación del código y recursos originales. No incluye una identidad de firma.

Las pruebas del clasificador de recuperación ejecutan el código C de producción. La revisión independiente verifica el paquete final y sus símbolos. Ninguna de estas comprobaciones sustituye una ejecución de UIKit y los servicios de Apple en el iPhone; esta entrega no se ha probado físicamente en él.

Las interfaces del protocolo se revisaron en la IPA 3105 suministrada y en AirLift; el módulo mantiene su implementación independiente y no incorpora código ejecutable de 3105. Consulte Notices.txt para los avisos de las dependencias.
