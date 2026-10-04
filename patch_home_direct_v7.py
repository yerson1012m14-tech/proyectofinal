from pathlib import Path

path = Path('MiApp/HomeViewController.m')
if not path.exists():
    raise SystemExit('No encontré MiApp/HomeViewController.m. Ejecuta este script desde la raíz del repo.')

s = path.read_text(encoding='utf-8')
original = s

replacements = [
(
'''    NSURL *destinationURL = [self destinationURLForOption:option error:&resolveError];
    if (!destinationURL && ![XITForgeFileEngine tunnelFallbackConfigured]) {
        [self showResult:resolveError ?: @"No se pudo resolver el contenedor o la ruta." success:NO];
        return;
    }

''',
'''    NSURL *destinationURL = [self destinationURLForOption:option error:&resolveError];
    // Si MCM/FilzaSlop no obtiene sandbox token, no abortar aquí.
    // Continuamos para descargar y mandar la operación al Túnel.

'''),
(
'''    // 2) Fallback automático al Túnel solamente después de una descarga válida
    // y de un fallo de acceso/escritura local.
    if (![XITForgeFileEngine tunnelFallbackConfigured]) {
        NSString *message = localFailure.length
            ? [NSString stringWithFormat:@"No se pudo aplicar por acceso local. %@ Configura el Túnel para usar el respaldo automático.", localFailure]
            : @"No se pudo aplicar por acceso local y el Túnel no está configurado.";
        [self showResult:message success:NO];
        return;
    }

''',
'''    // 2) Fallback automático al Túnel después de una descarga válida.
    // No mostrar el error MCM como resultado final sin intentar el Túnel.

'''),
(
'''            if (!destinationURL && ![XITForgeFileEngine tunnelFallbackConfigured]) {
                [self finishDeactivationUIWithSuccess:NO noOriginals:NO];
                return;
            }
''',
'''            // Si el contenedor local no abre, conservar el item:
            // la restauración se intentará por Túnel con bundleId + ruta relativa.
'''),
(
'''        if (![XITForgeFileEngine tunnelFallbackConfigured]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self finishDeactivationUIWithSuccess:NO noOriginals:NO]; });
            return;
        }

''',
'''        // El acceso local falló: intentar siempre el backend real del Túnel.

'''),
]

missing = []
for old, new in replacements:
    if old in s:
        s = s.replace(old, new, 1)
    else:
        missing.append(old.splitlines()[0])

if s == original:
    raise SystemExit('No se aplicó ningún cambio. Puede que el archivo ya esté modificado o no sea la versión esperada.')

backup = path.with_suffix(path.suffix + '.bak-v7')
backup.write_text(original, encoding='utf-8')
path.write_text(s, encoding='utf-8')

print('OK: HomeViewController.m corregido.')
print(f'Backup creado: {backup}')
if missing:
    print('Aviso: algunos bloques opcionales no estaban en esta versión:')
    for item in missing:
        print(' -', item)
