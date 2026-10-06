"""Add the separately built tunnel module to a copy of the supplied IPA."""
import argparse
import copy
import hashlib
import json
import pathlib
import plistlib
import struct
import zipfile

DYLIB_NAME = "XFAirLift.dylib"
LOAD_PATH = "@executable_path/" + DYLIB_NAME
MODULE_VERSION = "1.4.2-home-books"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse_macho(data):
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin little-endian 64-bit Mach-O")
    header = list(struct.unpack_from("<8I", data))
    if header[1] != 0x100000c:
        raise ValueError("Expected ARM64")
    commands, first_section = [], len(data)
    cursor = 32
    for _ in range(header[4]):
        cmd, size = struct.unpack_from("<II", data, cursor)
        if size < 8 or size % 8 or cursor + size > 32 + header[5]:
            raise ValueError("Invalid Mach-O load command")
        command = data[cursor:cursor + size]
        commands.append((cmd, command))
        if cmd == 0x19:
            nsects = struct.unpack_from("<I", command, 64)[0]
            for i in range(nsects):
                section = 72 + 80 * i
                offset = struct.unpack_from("<I", command, section + 48)[0]
                flags = struct.unpack_from("<I", command, section + 64)[0] & 0xff
                if offset and flags not in (1, 0xc, 0x12):
                    first_section = min(first_section, offset)
        if cmd == 0x2c and struct.unpack_from("<I", command, 16)[0]:
            raise ValueError("Encrypted executables are unsupported")
        cursor += size
    if cursor != 32 + header[5]:
        raise ValueError("Load-command length mismatch")
    return header, commands, first_section


def add_dependency(data):
    header, commands, first_section = parse_macho(data)
    if header[3] != 2:
        raise ValueError("Expected MH_EXECUTE")
    for cmd, command in commands:
        if cmd in (0xc, 0x80000018):
            name_offset = struct.unpack_from("<I", command, 8)[0]
            if command[name_offset:].split(b"\0", 1)[0].decode() == LOAD_PATH:
                raise ValueError("Tunnel module is already referenced")
    retained = [command for cmd, command in commands if cmd != 0x1d]
    path = LOAD_PATH.encode() + b"\0"
    size = (24 + len(path) + 7) & ~7
    load = struct.pack("<6I", 0xc, size, 24, 0, 0, 0) + path
    load += bytes(size - len(load))
    retained.append(load)
    joined = b"".join(retained)
    if 32 + len(joined) > first_section:
        raise ValueError("Insufficient verified Mach-O header padding")
    old_end = 32 + header[5]
    new_end = 32 + len(joined)
    if new_end > old_end and any(data[old_end:new_end]):
        raise ValueError("Nonzero data in required header padding")
    result = bytearray(data)
    result[32:max(old_end, new_end)] = bytes(max(old_end, new_end) - 32)
    result[32:new_end] = joined
    header[4], header[5] = len(retained), len(joined)
    struct.pack_into("<8I", result, 0, *header)
    result = bytes(result)
    parse_macho(result)
    assert result[first_section:] == data[first_section:]
    return result


def package(base, module, output, notices):
    module_data = module.read_bytes()
    module_header, _, _ = parse_macho(module_data)
    if module_header[3] != 6:
        raise ValueError("Module must be a real MH_DYLIB")
    report = {"base_sha256": digest(base.read_bytes()), "module_sha256": digest(module_data)}
    with zipfile.ZipFile(base) as source:
        infos = [n for n in source.namelist() if n.startswith("Payload/") and n.count("/") == 2 and n.endswith("Info.plist")]
        if len(infos) != 1:
            raise ValueError("Expected exactly one app bundle")
        info_path = infos[0]
        bundle = info_path.rsplit("/", 1)[0] + "/"
        info = plistlib.loads(source.read(info_path))
        if info.get("CFBundleDisplayName") != "XITFORGE":
            raise ValueError("Wrong base app")
        executable_path = bundle + info["CFBundleExecutable"]
        patched_executable = add_dependency(source.read(executable_path))
        info["NSLocalNetworkUsageDescription"] = "XitForge anuncia el emparejamiento por PIN y se conecta localmente a este iPhone para explorar archivos mediante tu autorización."
        for key, required in (("NSBonjourServices", "_remotepairing-pairable-host._tcp"),
                              ("UIBackgroundModes", "audio")):
            existing = info.get(key, [])
            if not isinstance(existing, list):
                raise ValueError(f"{key} must be an array")
            info[key] = existing + ([] if required in existing else [required])
        info["XFTunnelModuleVersion"] = MODULE_VERSION
        patched_info = plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=False)
        modified = {executable_path: patched_executable, info_path: patched_info}
        output.parent.mkdir(parents=True, exist_ok=True)
        removed = []
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as dest:
            for entry in source.infolist():
                name = entry.filename
                if name.startswith(bundle + "_CodeSignature/") or name == bundle + "embedded.mobileprovision":
                    removed.append(name)
                    continue
                if name == bundle + DYLIB_NAME:
                    raise ValueError("Module already in bundle")
                dest.writestr(copy.copy(entry), modified.get(name, source.read(name)))
            module_entry = zipfile.ZipInfo(bundle + DYLIB_NAME)
            module_entry.create_system = 3
            module_entry.external_attr = 0o100755 << 16
            module_entry.compress_type = zipfile.ZIP_DEFLATED
            dest.writestr(module_entry, module_data)
            notice_entry = zipfile.ZipInfo(bundle + "XitForge-Tunnel-Notices.txt")
            notice_entry.create_system = 3
            notice_entry.external_attr = 0o100644 << 16
            notice_entry.compress_type = zipfile.ZIP_DEFLATED
            dest.writestr(notice_entry, notices.read_bytes())
        with zipfile.ZipFile(output) as built:
            assert built.testzip() is None
            preserved = 0
            for entry in source.infolist():
                name = entry.filename
                if name not in modified and name not in removed:
                    assert digest(source.read(name)) == digest(built.read(name)), name
                    preserved += 1
            assert built.read(bundle + DYLIB_NAME) == module_data
            verified_info = plistlib.loads(built.read(info_path))
            assert verified_info["CFBundleIdentifier"] == info["CFBundleIdentifier"]
            assert "_remotepairing-pairable-host._tcp" in verified_info["NSBonjourServices"]
            assert "audio" in verified_info["UIBackgroundModes"]
            assert verified_info["XFTunnelModuleVersion"] == MODULE_VERSION
            report.update({"preserved_entries": preserved, "changed_entries": list(modified), "removed_signature_entries": removed})
    report["ipa_sha256"] = digest(output.read_bytes())
    report["validation"] = "ARM64 dylib, valid archive, preserved original executable code and resources; not tested on a physical iPhone"
    output.with_suffix(".validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=pathlib.Path)
    parser.add_argument("module", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("notices", type=pathlib.Path)
    args = parser.parse_args()
    if args.output.resolve() in (args.base.resolve(), args.module.resolve()):
        parser.error("Output must not replace an input")
    package(args.base, args.module, args.output, args.notices)
