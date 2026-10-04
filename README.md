# XitForge: proyecto y módulo de túnel

El código original de la app permanece en **MiApp/**. La entrega completa del módulo **1.3.1**, con fuentes, biblioteca nativa, binarios y documentación, está en **[XitForge-Tunnel/](XitForge-Tunnel/README.md)**.

- [Guía de compilación y uso](XitForge-Tunnel/README.md)
- [Qué se hizo y por qué](XitForge-Tunnel/docs/COMO_SE_HIZO.md)
- [Mapa de archivos y componentes](XitForge-Tunnel/docs/COMPONENTES.md)
- [IPA 1.3.1 sin firmar](XitForge-Tunnel/releases/XITFORGE_10.0.15_ARCHIVOS_1.3.1_unsigned.ipa)
- [Verificación y límites](XitForge-Tunnel/verification/README.md)

La compilación existente de GitHub Actions añade ahora el módulo al terminar de empaquetar la app. El artefacto final se llama **Mi-App-XitForge-1.3.1**. Para usarlo hay que firmar la IPA y sus bibliotecas conservando la identidad `com.apple.mobile.MobileHouseArrest`.

La IPA incluida se construyó sobre la base 10.0.15 proporcionada durante el trabajo. Una nueva ejecución de Actions compila la versión actual de MiApp de este repositorio y le añade el mismo módulo 1.3.1. Son bases distintas y sus hashes no tienen por qué coincidir.

La entrega contiene verificaciones de código y empaquetado; no acredita una ejecución física de esta versión en el iPhone.
