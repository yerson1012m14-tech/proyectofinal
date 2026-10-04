# Alcance de las verificaciones

Los informes de 1.3.1 corresponden exactamente a la IPA y la dylib entregadas en releases/ y prebuilt/. Solo se sustituyeron rutas locales del equipo por marcadores en estas copias de los informes. Los hashes de los binarios se conservaron.

La compilación ARM64 terminó sin avisos. La revisión independiente registró 561 controles correctos. El clasificador C pasó 51 casos nombrados, 81 combinaciones previas y 5.184 combinaciones de eliminación. Los casos están en module/XFATCFileRecoveryFixtures.c; tools/test_recovery.py los ejecuta de nuevo con un compilador C local.

Las pruebas no ejecutan UIKit ni los servicios de Apple en un iPhone. La versión 1.3.1 no fue probada físicamente durante esta entrega. El registro de 3105 es evidencia del comportamiento de 3105, no una prueba de funcionamiento de esta IPA.
