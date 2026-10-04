"""Compile and execute the production C recovery classifier on the host."""
from pathlib import Path
import argparse
import ctypes
import os
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default=os.environ.get('CC', 'clang'))
    parser.add_argument('--linker', help='Optional lld-link on Windows; runs fixtures as a host DLL without requiring the MSVC runtime')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    build = root / '.test-build'
    build.mkdir(exist_ok=True)
    if os.name == 'nt' and args.linker:
        include = build / 'include'
        include.mkdir(exist_ok=True)
        (include / 'assert.h').write_text('#define assert(expr) do { if (!(expr)) return __LINE__; } while (0)\n', encoding='utf-8')
        obj = build / 'recovery.obj'
        binary = build / 'recovery.dll'
        subprocess.run([args.cc, '-target', 'x86_64-pc-windows-msvc', '-O2', '-fno-builtin',
                        '-Wall', '-Wextra', '-Werror', '-I', str(include), '-I', str(root / 'module'),
                        '-c', str(root / 'module/XFATCFileRecoveryFixtures.c'), '-o', str(obj)], check=True)
        subprocess.run([args.linker, '/dll', '/noentry', '/nodefaultlib', '/export:main',
                        '/out:' + str(binary), str(obj)], check=True)
        library = ctypes.CDLL(str(binary))
        library.main.argtypes = []
        library.main.restype = ctypes.c_int
        failed_line = library.main()
        if failed_line:
            raise SystemExit('Recovery assertion failed at source line ' + str(failed_line))
        print('PASS: 51 named recovery cases and 5265 state combinations; no iPhone I/O.')
        return
    binary = build / ('recovery.exe' if os.name == 'nt' else 'recovery')
    subprocess.run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-I', str(root / 'module'), str(root / 'module/XFATCFileRecoveryFixtures.c'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    print('PASS: 51 named recovery cases and 5265 state combinations; no iPhone I/O.')

if __name__ == '__main__':
    main()
