# XITFORGE: fase 1 — Diagnóstico de motores

Se han modificado estos archivos del proyecto original:

- `.github/workflows/build.yml`: descarga el código fuente de `worse_query` y solamente el directorio `ThreeOneOSFive/kexploit` del repositorio 3105; registra las revisiones en `XITForgeEngineManifest.json` y ejecuta `xcodegen generate` después de crear dicho manifiesto.
- `MiApp/XITForgeEngineManager.h` y `.m` (nuevos): detectan de forma pasiva los símbolos públicos `MCMFilzaStart` y `MCMFilzaDataContainerPath`, y leen el manifiesto de compilación.
- `MiApp/MainSettingsViewController.m`: muestra la opción «Motores de XITFORGE» en Ajustes > Información. Al pulsarla aparece un diagnóstico informativo.

**Limitación importante:** `worse_query` y `3105 kexploit` NO se compilan, enlazan ni ejecutan en esta fase. Solo se descargan durante CI y su identificador de revisión se incorpora al manifiesto. No se añaden nuevas capacidades de acceso a contenedores o al kernel.

**Sin pruebas en iOS:** esta versión pasó validación estática de código y YAML donde fue posible; no se compiló con Xcode ni se instaló en un dispositivo iOS.

Sube los archivos conservando su estructura de carpetas y ejecuta GitHub Actions. Para un diagnóstico de producción de FilzaSlop, se requieren pruebas separadas de compatibilidad y permisos efectivos.
