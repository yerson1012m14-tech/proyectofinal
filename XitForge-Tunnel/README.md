# Prueba de creación 1.3.2-probe4

Consulta [PRUEBA_CREACION.md](../PRUEBA_CREACION.md). El módulo precompilado incluye esta prueba; la IPA de `releases/` es la versión histórica 1.3.1 y no la incluye. La nueva IPA se genera con el workflow del proyecto.

---

# Módulo XitForge 1.3.1

Esta carpeta contiene todo el trabajo del túnel y los archivos de apps: fuentes Objective-C/C, fuentes Rust modificadas, biblioteca ARM64, módulo compilado, IPA final, pruebas y explicación de los cambios.

## Contenido

| Carpeta | Contenido |
|---|---|
| module/ | Interfaz, túnel, pairing/PIN, archivos, transacciones y empaquetador |
| native/ | idevice v0.1.68 completo, fijado por Cargo.lock, con las modificaciones utilizadas |
| prebuilt/ | XFAirLift.dylib y libidevice_ffi.a exactos de la entrega |
| releases/ | IPA 1.3.1 sin firmar |
| tools/ | Verificación de hashes y prueba del clasificador de recuperación |
| docs/ | Componentes, pasos realizados, diferencias y evidencia histórica |
| verification/ | Informes de la IPA entregada y pruebas anteriores |

Los registros privados de emparejamiento, claves, certificados de firma y archivos personales del iPhone no forman parte de esta entrega. Los compiladores, Xcode y las cachés de compilación tampoco son fuentes del proyecto. Las dependencias Rust públicas se descargan según Cargo.lock si se reconstruye la biblioteca; la biblioteca ya compilada permite omitir esa descarga.

## Usar el módulo ya compilado

Con Python 3, desde la raíz del repositorio:

```sh
python3 XitForge-Tunnel/tools/verify_delivery.py
python3 XitForge-Tunnel/module/package_ipa.py /ruta/base.ipa XitForge-Tunnel/prebuilt/XFAirLift.dylib /ruta/XitForge-1.3.1.ipa XitForge-Tunnel/module/Notices.txt
```

La base debe ser una IPA ARM64 compatible, sin cifrar y que aún no contenga este módulo. El empaquetador escribe otra IPA, conserva el código y los recursos originales y añade una sola dependencia del módulo y los permisos de red/Bonjour. El instalador del módulo espera que el AppDelegate exponga `mainTabBar`, como hace MiApp en este repositorio. No convierte automáticamente cualquier IPA ajena en una app compatible.

Firma la app y sus dylibs conservando `com.apple.mobile.MobileHouseArrest`. El emparejamiento guardado debe corresponder al iPhone conectado. La pestaña Túnel distingue el último estado comprobado del túnel y del pairing.

## Reconstruir en macOS

Requiere Xcode con el SDK de iPhone y sus herramientas de línea de comandos.

```sh
bash XitForge-Tunnel/module/build-module.sh
```

Por defecto compila todas las fuentes del módulo y enlaza la biblioteca ARM64 verificada de prebuilt/. Para reconstruir también la biblioteca Rust con Rust/rustup instalados:

```sh
XF_REBUILD_NATIVE=1 bash XitForge-Tunnel/module/build-module.sh
```

Ese modo añade el target aarch64-apple-ios y ejecuta Cargo con `--locked`, sin depender de rutas del equipo original. El resultado queda en module/build/XFAirLift.dylib. Para empaquetarlo, sustituye prebuilt/XFAirLift.dylib por esa ruta en el comando anterior. Los hashes pueden variar al cambiar de compilador o SDK.

## Reconstruir en Windows

Requiere Python 3, clang/ld64.lld y un SDK de iPhone disponible en el equipo. El SDK de Apple no se redistribuye aquí. Ejemplo:

```powershell
python XitForge-Tunnel/module/build-windows-local.py --clang C:/LLVM/bin/clang.exe --linker C:/LLVM/bin/ld64.lld.exe --sdk C:/SDKs/iPhoneOS16.5.sdk --sdk-version 16.5
```

Este modo reutiliza prebuilt/libidevice_ffi.a. El resultado y el registro de compilación quedan en module/build/. La biblioteca Rust se puede reconstruir mediante el flujo de macOS; el binario ARM64 incluido es el usado en la IPA entregada.

## Archivos de las apps

Selecciona la app, entra en **Abrir ruta** y escribe una ruta relativa completa, como Documents/carpeta/archivo.ext. Cierra la app de destino durante la operación.

- Leer/exportar: usa las rutas de acceso disponibles y, cuando corresponde, el traslado temporal AirLift.
- Reemplazar: en Archivos elige el archivo nuevo y confirma el destino. El selector importa una copia y muestra lectura cancelable después de recibirla.
- Eliminar: confirma la ruta. Se conserva el original local y remoto; solo se informa ausencia confirmada cuando el servicio realmente la acredita. No es borrado seguro del contenido.
- Restaurar original pendiente: corresponde a una operación interrumpida antes de completarse. Una eliminación completada no se deshace automáticamente al reconectar.

Estas operaciones AirLift admiten archivos de hasta 64 MiB. Conservar XitForge y su emparejamiento es necesario mientras haya recuperación pendiente. El acceso depende de la app, versión, firma y servicios del dispositivo. Listar una carpeta y acceder a un archivo conocido son operaciones diferentes.

## Verificar

```sh
python3 XitForge-Tunnel/tools/verify_delivery.py
python3 XitForge-Tunnel/tools/test_recovery.py --cc clang
```

El segundo comando necesita un compilador C para el equipo anfitrión. No ejecuta movimientos ni servicios de un iPhone. La integración de Actions se verifica por separado al ejecutarse; los informes entregados corresponden al artefacto 1.3.1 ya compilado.

Las licencias de idevice y AirCard están incluidas. El núcleo propio se implementó de forma independiente; no se copió el ejecutable de 3105 al módulo. No se concede aquí una licencia nueva para el código original de MiApp ni para componentes de terceros.
