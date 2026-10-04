# Comparación de 3105 y XitForge en iOS 27.0, build 24A437

El log nuevo de **3105 2.1 Beta 2** muestra que **también falla al listar las carpetas** mediante AirLift con `Afc(PermDenied)`, código 106. En la misma sesión, 3105 sí informa una copia de un archivo cuya ruta ya conoce y el reemplazo verificado de ese archivo. Son operaciones distintas.

Se leyó completo el registro de 295 líneas aportado por el usuario. Identifica `24A437`, modelo `iPhone12,1`, y selecciona explícitamente la ruta `airLift`; no es el registro anterior de la beta `24A5355q`. Las líneas siguientes se refieren al archivo original, contando desde 1. Se omiten UUID, identificadores de apps, nombres de archivos, rutas de datos y registros de emparejamiento.

| Operación | Evidencia del registro | Resultado que acredita |
|---|---|---|
| Emparejamiento | Línea 19: `host success` | El emparejamiento terminó correctamente. |
| Selección de ruta | Líneas 89 y 202: `patch.access_route selected=airLift experimental_airlift=false`; línea 171: `browser.access_route route=airLift` | El navegador y el parche usan AirLift en esta sesión. |
| Listado de App Group | Inicio en línea 147; fallo en línea 168, a las 22:55:30.687: `AIRLIFT DIRECTORY LIST FAIL phase=list`, código 106, `Afc(PermDenied)` | El servicio denegó enumerar ese contenedor compartido, después del intercambio ATC hasta AssetManifest. |
| Listado de Application | Inicio en línea 179; fallo en línea 201, a las 22:55:36.574: el mismo `phase=list`, código 106, `Afc(PermDenied)` | También se denegó enumerar ese contenedor de datos de app. El evento `filebrowser.listing_failed` de la línea 200 lo corrobora. |
| Primera copia de archivo conocido | Inicio en línea 90; fallo en línea 113, a las 22:54:55.666: `AIRLIFT BATCH COPY-OUT FAIL phase=relocate`, código 1, `BrokenPipe`, `channel closed` | Ese intento falló durante la reubicación; no llegó a informar copia completa. |
| Segunda copia de archivo conocido | Inicio en línea 203; línea 243: `BATCH COPY-OUT DISCOVERY requested=1 found=1`; línea 246: `AIRLIFT BATCH COPY-OUT COMPLETE files=1` | El segundo intento informa descubrimiento y copia completos de un archivo pedido de antemano. La línea 245 declara `original=present operation=replace`. |
| Reemplazo de ese archivo | Línea 247: `write plan existing=1 created=0`; línea 277: `verify OK (1/1)`; línea 292: `BATCH WRITE COMPLETE`; línea 295: `patch.airlift apply verified files=1 mode=batch` | El log informa que se reemplazó un archivo existente y que la verificación de 3105 pasó. No se creó ningún archivo en ese lote. |

XitForge 1.2.9, en el diagnóstico aportado de `24A437`, llegó al mismo límite en el listado: `DirectoryListing`, `GeneratedAppLink`, código 106/subcódigo 10. La conexión seguía activa. Su consulta del enlace devolvió metadatos del enlace esperado, pero eso no autoriza ni demuestra la lectura del directorio destino. El log de 3105 confirma que conexión, catálogo de apps y sondeo de servicios satisfactorios pueden coexistir con la denegación del listado.

La diferencia demostrada es funcional: 3105 dispone de una operación de copia de **ruta de archivo conocida** y un flujo de reemplazo que completaron este caso; la exploración de carpetas no completó los dos casos registrados. El éxito de la copia no elimina ni contradice la denegación al enumerar.

El registro no demuestra exploración libre de todas las apps, apertura visual del archivo, acceso nativo MHA/BadQuery en esta sesión, creación o borrado de archivos, ni que toda ruta conocida se pueda copiar. Tampoco contiene el contenido o un digest del archivo para verificar de forma independiente la comprobación declarada por 3105. Los UUID omitidos impiden afirmar a partir de esta comparación que el intento de listado de XitForge apuntó al mismo contenedor exacto que los intentos de 3105.

## Incorporación que falta en XitForge

La UI de XitForge 1.2.9 ya permite introducir una ruta relativa y pedir previsualización o exportación. Sin embargo, cuando los otros accesos fallan, su backend devuelve expresamente el error 1028: la lectura AirLift todavía no está implementada. XFATCDirectory expone listado y recuperación, pero ninguna operación de lectura arbitraria por ruta.

La lectura AirLift inspeccionada no es una lectura directa sin cambios: traslada temporalmente el archivo original a Media, lo lee mediante AFC y lo devuelve. El journal actual de XF protege Books y objetos generados, pero no recupera un original de app trasladado. La incorporación requiere una transacción nueva persistente, recuperación tras corte de conexión o cierre de la app y comprobación de que la restauración no sobrescriba un archivo recreado por la app. Se debe devolver éxito solo después de confirmar que el original regresó.

Ya existen las primitivas de transporte y lectura AFC; la diferencia es el algoritmo y su recuperación. Deben comprobarse archivos vacíos/binarios, límites, rutas inválidas, fallos antes y después de cada traslado, destinos ocupados y recuperación repetida. Nada de esto convierte una respuesta ReadDir denegada en un listado exitoso.

Este informe no propone alterar credenciales, ampliar compatibilidad de betas ni presentar el listado como solucionado. No se modificó código ni ninguna IPA durante esta revisión.
