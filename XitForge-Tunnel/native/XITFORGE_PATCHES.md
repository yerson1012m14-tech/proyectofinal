# XitForge native stream extension

Base: `jkcoxson/idevice`, exact tag `v0.1.68`, commit `d32c8189c51c2789496b0768039419c3705498c3`, MIT.

The custom FFI is compiled together with all native handle definitions. Objective-C uses only public C opaque handles. It does not inspect Rust object layouts or reinterpret `ReadWriteOpaque` as `AdapterStreamHandle`.

Changes:

- `ffi/src/xf_stream.rs`: binary send, receive, exact read, shutdown, named RSD service connection, original service advertisement export, bounded AFC connection and exact nanosecond modification times.
- `idevice/src/services/rsd.rs`: accepts integer or string service ports, permits services without an `Entitlement`, rejects zero/out-of-range ports, retains original service advertisements for diagnosis.
- `idevice/src/services/afc`: limits incoming frames to 64 MiB, bounds each send/read to 15 seconds, invalidates the connection after a timeout or framing/transport failure. Already-consumed normal AFC status errors retain the connection.
- `idevice/src/services/afc/mod.rs`: reads the standard AFC `LinkTarget` attribute, retaining `st_link_target` compatibility. Previously the standard target was silently omitted from typed file info, causing the module's required symlink verification to reject valid links. Regression tests use fragmented, null-separated AFC response frames through the actual client. Protocol reference: https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/idevicecrashreport.c
- `idevice/src/lib.rs`: connection invalidation helper.
- `plist_ffi_local`: exact registry `plist_ffi` 0.1.6 implementation, unchanged `src/`. Its build script only generates unused headers and is replaced by a no-op. Only an `rlib` is emitted as a dependency, avoiding an unnecessary standalone dylib link during Windows cross compilation.

The native TLS-PSK tunnel implementation in idevice is pure Rust. This build selects `rustcrypto` for the additional rustls TLS backend, avoiding cross compilation of AWS-LC C code. It does not replace the TLS-PSK protocol with a different implementation.

Build and dependencies stay in `work/`. `../xitforge_rust/build-ffi.ps1` builds the arm64 iOS 17+ static archive offline using the locked, checksum-verified vendor sources. The portable Rust compiler wrapper selects GNU's import-library tool for Windows host executables. GNU binutils and its runtime DLLs were extracted from checksum-verified MSYS2 packages into `work/`, without installing them globally. LLVM and the iOS SDK are used separately by the Objective-C dylib build.

Verification: all three binary FFI tests passed (embedded zero/non-UTF8 bytes, fragmented writes through a small stream buffer, and timeout poisoning before reuse). Both RSD parser tests passed (string/integer port validation, optional entitlement and the remote-XPC flag). The arm64 archive contains all nine new C bridge exports and the existing pairing, tunnel, AFC, FileService and plist exports. Exact build/test commands and the archive checksum are recorded in `../xitforge_rust/native-verification.json`.

Stream operation deadlines must be from 1 to 120000 ms. Successful receive with zero bytes means EOF. Protocol code must close each stream on any error. The close operation consumes the handle, including when its shutdown deadline expires. All adapter and service operations remain on the same native worker thread.

This verifies transport and parser behavior locally. It does not verify Apple service availability or an ATC workflow on a physical iPhone.
