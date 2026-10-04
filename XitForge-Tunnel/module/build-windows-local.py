"""Build the module with explicit LLVM and iPhone SDK paths, using the bundled archive."""
from pathlib import Path
import argparse
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', required=True, type=Path)
    parser.add_argument('--linker', required=True, type=Path)
    parser.add_argument('--sdk', required=True, type=Path)
    parser.add_argument('--sdk-version', required=True)
    parser.add_argument('--native-archive', type=Path)
    args = parser.parse_args()
    module = Path(__file__).resolve().parent
    archive = (args.native_archive or module.parent / 'prebuilt/libidevice_ffi.a').resolve()
    for path in [args.clang, args.linker, args.sdk, archive]:
        if not path.exists():
            parser.error('Missing build input: ' + str(path))
    build = module / 'build'
    build.mkdir(exist_ok=True)
    log = build / 'build.log'
    log.write_text('', encoding='utf-8')
    def run(command):
        result = subprocess.run([str(v) for v in command], capture_output=True, text=True)
        with log.open('a', encoding='utf-8') as output:
            output.write(result.stdout + result.stderr)
        if result.returncode:
            raise SystemExit('Compilation failed; see ' + str(log))
    sources = ['XFAirLiftBackend.m', 'XFOnDevicePairing.m', 'XFAirLiftViewController.m',
               'XFAirLiftInstaller.m', 'XFAirLiftProfessionalUI.m', 'XFFileCreationProbeController.m',
               'XFATCDirectory.m', 'XFGrappaHelper.m', 'XFMHAContainerAccess.m', 'XFATCZip.c']
    objects = []
    for source in sources:
        output = build / (Path(source).stem + '.o')
        run([args.clang, '-target', 'arm64-apple-ios17.0', '-isysroot', args.sdk,
             *(['-fobjc-arc', '-fblocks'] if source.endswith('.m') else []),
             '-O2', '-Wall', '-Wextra', '-Werror=implicit-function-declaration',
             '-Werror=incompatible-pointer-types', '-Wno-unused-parameter', '-I', module,
             '-c', module / source, '-o', output])
        objects.append(output)
    command = [args.linker, '-dylib', '-arch', 'arm64', '-platform_version', 'ios', '17.0', args.sdk_version,
               '-syslibroot', args.sdk, '-dead_strip', '-exported_symbols_list', module / 'exports.txt',
               '-install_name', '@executable_path/XFAirLift.dylib', '-o', build / 'XFAirLift.dylib', *objects, archive]
    for framework in ['UIKit', 'Foundation', 'CoreFoundation', 'CoreGraphics', 'UniformTypeIdentifiers',
                      'QuickLook', 'AVFoundation', 'UserNotifications', 'Security', 'SystemConfiguration', 'CFNetwork']:
        command += ['-framework', framework]
    run(command + ['-lSystem', '-lobjc', '-lresolv', '-liconv', '-lz', '-lc++'])
    print('ARM64 module: ' + str(build / 'XFAirLift.dylib'))

if __name__ == '__main__':
    main()
