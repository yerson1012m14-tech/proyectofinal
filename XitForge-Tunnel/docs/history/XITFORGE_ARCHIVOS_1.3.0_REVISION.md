# XitForge 1.3.0: archivos por ruta conocida

Esta versión incorpora la operación que sí completó el log nuevo de 3105 en 24A437: acceder a un archivo cuya ruta ya se conoce y reemplazarlo con verificación. El mismo log registra Afc(PermDenied) al explorar dos contenedores. El nuevo módulo no presenta el listado como corregido.

## Uso

1. Firma e instala XITFORGE_10.0.15_ARCHIVOS_1.3.0_unsigned.ipa, conservando el identificador com.apple.mobile.MobileHouseArrest y firmando también sus dylibs.
2. Conecta el túnel con el emparejamiento de ese iPhone y selecciona la app.
3. Entra en **Abrir ruta** e introduce una ruta relativa completa, como Documents/carpeta/archivo.ext.
4. Elige **Previsualizar archivo**, **Exportar archivo** o **Reemplazar archivo**. Para reemplazar, selecciona los bytes nuevos en Archivos y confirma la app y el destino.

Cierra la app de destino durante estas operaciones. Si queda recuperación pendiente, conserva XitForge y sus datos, vuelve a conectar y usa **Abrir ruta → Restaurar original pendiente** con la misma app y ruta. Esa acción informa que puede reemplazar el archivo que exista actualmente.

## Cambio implementado

- La lectura usa primero los accesos existentes y después la nueva operación AirLift, sin exigir un listado previo.
- El reemplazo usa una ruta de archivo validada dentro del contenedor actualizado del catálogo. No crea una app ni habilita un explorador del sistema.
- Antes del reemplazo se conserva una copia local duradera del original, con SHA-256, tamaño y un recibo que asocia esa copia con dispositivo, ruta y transacción.
- Los bytes nuevos se preparan y verifican en un temporal propio. Se trasladan al destino, se recuperan para compararlos byte a byte y se devuelven antes de marcar el reemplazo como completado.
- Un registro se guarda y sincroniza antes de cada movimiento. Los sockets cerrados, permisos denegados y respuestas inválidas nunca se consideran desaparición del archivo.
- El enlace usado para devolver archivos se verifica de nuevo inmediatamente antes del movimiento. El respaldo remoto conserva su marcador si contiene objetos pendientes.
- La restauración explícita solo acepta el destino exacto del registro validado. Un error recuperable mantiene el túnel disponible para esa acción y bloquea nuevas transacciones ATC.
- La selección de archivo usa su propio selector, acceso autorizado al documento y lectura acotada. El límite de estas operaciones AirLift es **64 MiB**.

## Límites prácticos

La lectura AirLift traslada temporalmente el original a Media y luego lo devuelve; no es una lectura directa sin movimientos. El regreso se confirma mediante ausencia positiva del objeto temporal después de la intención guardada, no mediante una prueba independiente del destino protegido. No hay garantía de colocación atómica sin conflictos si la app modifica o recrea ese archivo mientras está fuera.

Una ruta inexistente o una operación cuyo movimiento no se pueda confirmar puede quedar pendiente. La comprobación de metadatos detecta ausencia o tipo incorrecto antes del traslado cuando el servicio lo permite. Si esos metadatos también están denegados, no se supone que el archivo exista ni se inventa una restauración exitosa. Se preserva el estado ambiguo.

El módulo usa el namespace estable del emparejamiento y los marcadores de sus temporales para recuperar. Cambiar el emparejamiento, eliminar XitForge o reinstalar la app de destino durante una operación pendiente puede impedir recuperar mediante la misma ruta. Las copias locales no se incluyen en los diagnósticos exportados.

## Verificación

Se compilaron y enlazaron las ocho fuentes ARM64, sin errores ni avisos en el build final. El clasificador C que usa el módulo pasó **31 casos de recuperación y 81 combinaciones de presencia**, con comprobaciones de estados desconocidos, cortes y contradicciones. Esas pruebas verifican decisiones del código; no ejecutan los movimientos de Apple en un iPhone.

El paquete se generó desde la IPA original: conserva su código después de la cabecera, el helper original, los ocho recursos restantes y sus permisos ZIP. Añade una sola dependencia del módulo. Los informes JSON incluyen la comprobación del archivo y la revisión independiente.

**No se ejecutó esta IPA en el iPhone.** La evidencia de funcionamiento del algoritmo procede de 3105; la integración nueva necesita validación física. No se afirma que toda ruta o toda app sea accesible.

SHA-256 de la IPA: c226be7c8ec5e056a04f25cba00fcdc7d35890a0c383febda1433c782e04873f.

La evidencia del log está en 3105_24A437_COMPARACION_RUNTIME.md. Las fórmulas del protocolo se revisaron en el ejecutable proporcionado de 3105 y se implementaron de forma independiente; no se incorporó su código binario.
