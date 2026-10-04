"""Run the production ATC reconnect policy on the host, without iPhone I/O."""
from pathlib import Path
import argparse
import ctypes
import os
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default=os.environ.get('CC', 'clang'))
    parser.add_argument('--linker')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    build = root / '.test-build'
    build.mkdir(exist_ok=True)
    source = root / 'module/XFATCSyncRetryFixtures.c'
    flags = ['-O2', '-Wall', '-Wextra', '-Werror']
    if os.name == 'nt' and args.linker:
        obj, binary = build / 'sync-retry.obj', build / 'sync-retry.dll'
        subprocess.run([args.cc, '-target', 'x86_64-pc-windows-msvc', '-fno-builtin', *flags,
                        '-c', str(source), '-o', str(obj)], check=True)
        subprocess.run([args.linker, '/dll', '/noentry', '/nodefaultlib', '/export:main',
                        '/out:' + str(binary), str(obj)], check=True)
        library = ctypes.CDLL(str(binary))
        library.main.restype = ctypes.c_int
        library.main.argtypes = []
        result = library.main()
        if result:
            raise SystemExit('ATC retry assertion failed at line ' + str(result))
    else:
        binary = build / 'sync-retry'
        subprocess.run([args.cc, *flags, str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
    print('PASS: 6 transport scenarios, retry delays and 48 policy combinations; no iPhone I/O.')

if __name__ == '__main__':
    main()
