#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
module="$PWD"
bundle="$(cd .. && pwd)"
native="${XF_IDEVICE_NATIVE:-$bundle/native}"
archive="${XF_IDEVICE_ARCHIVE:-$bundle/prebuilt/libidevice_ffi.a}"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
export SDKROOT="$sdk"
export IPHONEOS_DEPLOYMENT_TARGET=17.0
if [ "${XF_REBUILD_NATIVE:-0}" = 1 ]; then
  rustup target add aarch64-apple-ios
  (cd "$native" && cargo build -p idevice-ffi --target aarch64-apple-ios --release --lib --no-default-features --features full,rustcrypto --locked)
  archive="$native/target/aarch64-apple-ios/release/libidevice_ffi.a"
fi
test -f "$archive"
mkdir -p build
objects=()
for source in XFAirLiftBackend.m XFOnDevicePairing.m XFAirLiftViewController.m XFAirLiftInstaller.m XFATCDirectory.m XFGrappaHelper.m XFMHAContainerAccess.m; do
  object="build/${source%.m}.o"
  xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.0 -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror=implicit-function-declaration -Werror=incompatible-pointer-types -Wno-unused-parameter -I . -c "$source" -o "$object"
  objects+=("$object")
done
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.0 -O2 -Wall -Wextra -I . -c XFATCZip.c -o build/XFATCZip.o
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.0 -dynamiclib -Wl,-dead_strip -Wl,-exported_symbols_list,exports.txt -Wl,-install_name,@executable_path/XFAirLift.dylib "${objects[@]}" build/XFATCZip.o "$archive" -framework UIKit -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework UniformTypeIdentifiers -framework QuickLook -framework AVFoundation -framework Security -framework SystemConfiguration -framework CFNetwork -lresolv -liconv -lz -lc++ -o build/XFAirLift.dylib
xcrun lipo -verify_arch arm64 build/XFAirLift.dylib
xcrun otool -L build/XFAirLift.dylib > build/dependencies.txt
shasum -a 256 build/XFAirLift.dylib > build/SHA256.txt
echo "Módulo generado: $module/build/XFAirLift.dylib"
