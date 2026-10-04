"""Verify the distributed files, compiled module and IPA without external packages."""
from pathlib import Path
import hashlib
import json
import plistlib
import struct
import zipfile

def main():
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'SHA256SUMS.json').read_text(encoding='utf-8'))
    release = json.loads((root / 'RELEASE.json').read_text(encoding='utf-8'))
    for relative, expected in manifest.items():
        path = root / relative
        assert path.resolve().is_relative_to(root.resolve()), relative
        assert path.is_file(), 'Missing file: ' + relative
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, 'Hash differs: ' + relative
    for relative, record in release['artifacts'].items():
        assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == record['sha256'], relative
    module = (root / 'prebuilt/XFAirLift.dylib').read_bytes()
    assert struct.unpack_from('<I', module)[0] == 0xfeedfacf
    assert struct.unpack_from('<I', module, 4)[0] == 0x0100000c
    assert struct.unpack_from('<I', module, 12)[0] == 6
    ipa = root / 'releases/XITFORGE_10.0.15_ARCHIVOS_1.3.1_unsigned.ipa'
    with zipfile.ZipFile(ipa) as z:
        assert z.testzip() is None
        info = plistlib.loads(z.read('Payload/MiApp.app/Info.plist'))
        assert info['CFBundleIdentifier'] == 'com.apple.mobile.MobileHouseArrest'
        assert info['XFTunnelModuleVersion'] == '1.3.1'
        assert z.read('Payload/MiApp.app/XFAirLift.dylib') == module
    print(json.dumps({'verifiedFiles': len(manifest), 'moduleVersion': release['moduleVersion'], 'ipaIntegrity': True,
                      'physicalIPhoneTest': False}, indent=2))

if __name__ == '__main__':
    main()
