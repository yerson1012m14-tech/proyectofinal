//! Binary-safe stream operations for XitForge, compiled in this same FFI crate.
//! Never interprets ReadWriteOpaque as the obsolete AdapterStreamHandle.

use crate::{IdeviceFfiError, ReadWriteOpaque, ffi_err, run_sync_local};
use crate::core_device_proxy::AdapterHandle;
use crate::rsd::RsdHandshakeHandle;
use idevice::{Idevice, IdeviceError};
use std::{ffi::{CStr, c_char}, ptr::null_mut, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const MAX_TRANSFER: usize = 64 * 1024 * 1024;

fn deadline(ms: u64) -> Result<Duration, IdeviceError> {
    if ms == 0 || ms > 120_000 {
        return Err(IdeviceError::FfiInvalidArg);
    }
    Ok(Duration::from_millis(ms))
}

/// Borrow both adapter and discovery handle; returned stream is caller-owned.
/// Must run on the same thread as the adapter. Plain services only.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_rsd_connect_service(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    service_name: *const c_char,
    perform_checkin: bool,
    timeout_ms: u64,
    out_stream: *mut *mut ReadWriteOpaque,
) -> *mut IdeviceFfiError {
    if adapter.is_null() || handshake.is_null() || service_name.is_null() || out_stream.is_null() {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    unsafe { *out_stream = null_mut(); }
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let name = match unsafe { CStr::from_ptr(service_name) }.to_str() {
        Ok(s) if !s.is_empty() => s.to_owned(),
        _ => return ffi_err!(IdeviceError::FfiInvalidString),
    };
    let service = match unsafe { &(*handshake).0 }.services.get(&name).cloned() {
        Some(s) => s,
        None => return ffi_err!(IdeviceError::ServiceNotFound),
    };
    if service.uses_remote_xpc {
        return ffi_err!(IdeviceError::UnexpectedResponse(format!(
            "Service {name} uses RemoteXPC; refusing a plain byte stream"
        )));
    }
    let adapter = unsafe { &mut (*adapter).0 };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, async {
            let stream = adapter.connect(service.port).await.map_err(|e|
                IdeviceError::InternalError(format!("Connect {name}: {e}")))?;
            if perform_checkin {
                let mut device = Idevice::new(Box::new(stream), "airlift-mini");
                device.rsd_checkin().await?;
                device.get_socket().ok_or(IdeviceError::FfiInvalidArg)
            } else {
                Ok(Box::new(stream) as Box<dyn idevice::ReadWrite>)
            }
        }).await.map_err(|_| IdeviceError::Timeout)?
    });
    match result {
        Ok(inner) => {
            unsafe { *out_stream = Box::into_raw(Box::new(ReadWriteOpaque { inner: Some(inner) })); }
            null_mut()
        }
        Err(e) => ffi_err!(e),
    }
}

/// Complete binary write with an operation deadline, borrowing the stream.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_stream_send(
    stream: *mut ReadWriteOpaque, data: *const u8, length: usize, timeout_ms: u64,
) -> *mut IdeviceFfiError {
    if stream.is_null() || (data.is_null() && length != 0) || length > MAX_TRANSFER {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let inner = match unsafe { &mut *stream }.inner.as_mut() {
        Some(s) => s, None => return ffi_err!(IdeviceError::FfiInvalidArg),
    };
    if length == 0 { return null_mut(); }
    let bytes = unsafe { std::slice::from_raw_parts(data, length) };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, async {
            inner.write_all(bytes).await?;
            inner.flush().await
        }).await.map_err(|_| IdeviceError::Timeout)?.map_err(IdeviceError::from)
    });
    match result {
        Ok(()) => null_mut(),
        Err(e) => { unsafe { (*stream).inner = None; } ffi_err!(e) },
    }
}

/// Reads at most capacity bytes; EOF is success with out_length=0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_stream_recv(
    stream: *mut ReadWriteOpaque, buffer: *mut u8, capacity: usize,
    out_length: *mut usize, timeout_ms: u64,
) -> *mut IdeviceFfiError {
    if stream.is_null() || buffer.is_null() || out_length.is_null() || capacity == 0 || capacity > MAX_TRANSFER {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    unsafe { *out_length = 0; }
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let inner = match unsafe { &mut *stream }.inner.as_mut() {
        Some(s) => s, None => return ffi_err!(IdeviceError::FfiInvalidArg),
    };
    let bytes = unsafe { std::slice::from_raw_parts_mut(buffer, capacity) };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, inner.read(bytes)).await
            .map_err(|_| IdeviceError::Timeout)?.map_err(IdeviceError::from)
    });
    match result {
        Ok(n) => { unsafe { *out_length = n; } null_mut() },
        Err(e) => { unsafe { (*stream).inner = None; } ffi_err!(e) },
    }
}

/// Reads exactly length bytes, including NUL and non-UTF8 data.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_stream_read_exact(
    stream: *mut ReadWriteOpaque, buffer: *mut u8, length: usize, timeout_ms: u64,
) -> *mut IdeviceFfiError {
    if stream.is_null() || (buffer.is_null() && length != 0) || length > MAX_TRANSFER {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let inner = match unsafe { &mut *stream }.inner.as_mut() {
        Some(s) => s, None => return ffi_err!(IdeviceError::FfiInvalidArg),
    };
    if length == 0 { return null_mut(); }
    let bytes = unsafe { std::slice::from_raw_parts_mut(buffer, length) };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, inner.read_exact(bytes)).await
            .map_err(|_| IdeviceError::Timeout)?.map(|_| ()).map_err(IdeviceError::from)
    });
    match result {
        Ok(()) => null_mut(),
        Err(e) => { unsafe { (*stream).inner = None; } ffi_err!(e) },
    }
}

/// Consumes the stream unconditionally; caller must clear its pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_stream_close(
    stream: *mut ReadWriteOpaque, timeout_ms: u64,
) -> *mut IdeviceFfiError {
    if stream.is_null() { return null_mut(); }
    let mut wrapper = unsafe { Box::from_raw(stream) };
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let Some(mut inner) = wrapper.inner.take() else { return null_mut(); };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, inner.shutdown()).await
            .map_err(|_| IdeviceError::Timeout)?.map_err(IdeviceError::from)
    });
    match result { Ok(()) => null_mut(), Err(e) => ffi_err!(e) }
}

/// Read-only service discovery diagnostics, without pairing secrets.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_rsd_advertised_services(
    handshake: *mut RsdHandshakeHandle, out_data: *mut *mut u8, out_length: *mut usize,
) -> *mut IdeviceFfiError {
    if handshake.is_null() || out_data.is_null() || out_length.is_null() {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    unsafe { *out_data = null_mut(); *out_length = 0; }
    let value = plist::Value::Dictionary(unsafe { &(*handshake).0 }.advertised_services.clone());
    let mut bytes = Vec::new();
    if let Err(e) = value.to_writer_xml(&mut bytes) { return ffi_err!(e); }
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    let ptr = Box::into_raw(boxed) as *mut u8;
    unsafe { *out_data = ptr; *out_length = len; }
    null_mut()
}

#[cfg(feature = "afc")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_afc_connect_rsd(
    adapter: *mut AdapterHandle, handshake: *mut RsdHandshakeHandle,
    timeout_ms: u64, out_client: *mut *mut crate::afc::AfcClientHandle,
) -> *mut IdeviceFfiError {
    use idevice::RsdService as _;
    if adapter.is_null() || handshake.is_null() || out_client.is_null() {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    unsafe { *out_client = null_mut(); }
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, idevice::afc::AfcClient::connect_rsd(
            unsafe { &mut (*adapter).0 }, unsafe { &mut (*handshake).0 }
        )).await.map_err(|_| IdeviceError::Timeout)?
    });
    match result {
        Ok(client) => {
            unsafe { *out_client = Box::into_raw(Box::new(crate::afc::AfcClientHandle(client))); }
            null_mut()
        }
        Err(e) => ffi_err!(e),
    }
}

#[cfg(feature = "afc")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_afc_get_mtime(
    client: *mut crate::afc::AfcClientHandle, path: *const c_char,
    out_mtime_nanos: *mut i64, timeout_ms: u64,
) -> *mut IdeviceFfiError {
    if client.is_null() || path.is_null() || out_mtime_nanos.is_null() {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    unsafe { *out_mtime_nanos = 0; }
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s.to_owned(), _ => return ffi_err!(IdeviceError::FfiInvalidString),
    };
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, unsafe { &mut (*client).0 }.get_file_info_raw(path))
            .await.map_err(|_| IdeviceError::Timeout)?
    });
    match result {
        Ok(info) => match info.get("st_mtime").and_then(|s| s.parse::<i64>().ok()).filter(|n| *n >= 0) {
            Some(n) => { unsafe { *out_mtime_nanos = n; } null_mut() },
            None => ffi_err!(IdeviceError::UnexpectedResponse("AFC st_mtime is absent or invalid".into())),
        },
        Err(e) => {
            if matches!(e, IdeviceError::Timeout) { unsafe { (*client).0.invalidate_connection(); } }
            ffi_err!(e)
        },
    }
}

#[cfg(feature = "afc")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn xf_afc_set_file_time(
    client: *mut crate::afc::AfcClientHandle, path: *const c_char,
    mtime_nanos: i64, timeout_ms: u64,
) -> *mut IdeviceFfiError {
    if client.is_null() || path.is_null() || mtime_nanos < 0 {
        return ffi_err!(IdeviceError::FfiInvalidArg);
    }
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s.to_owned(), _ => return ffi_err!(IdeviceError::FfiInvalidString),
    };
    let timeout = match deadline(timeout_ms) { Ok(t) => t, Err(e) => return ffi_err!(e) };
    let result = run_sync_local(async {
        tokio::time::timeout(timeout, unsafe { &mut (*client).0 }.set_file_time(path, mtime_nanos as u64))
            .await.map_err(|_| IdeviceError::Timeout)?
    });
    match result {
        Ok(()) => null_mut(),
        Err(e) => {
            if matches!(e, IdeviceError::Timeout) { unsafe { (*client).0.invalidate_connection(); } }
            ffi_err!(e)
        },
    }
}

#[cfg(test)]
mod binary_tests {
    use super::*;

    #[test]
    fn read_exact_preserves_nuls_and_non_utf8_bytes() {
        let expected = [0x00, 0xff, 0x80, 0x50, 0x4b, 0x00, 0xfe, 0x7f];
        let (client, mut peer) = tokio::io::duplex(64);
        run_sync_local(async { peer.write_all(&expected).await.unwrap(); });
        let stream = Box::into_raw(Box::new(ReadWriteOpaque { inner: Some(Box::new(client)) }));
        let mut actual = [0_u8; 8];
        unsafe {
            let error = xf_stream_read_exact(stream, actual.as_mut_ptr(), actual.len(), 2000);
            assert!(error.is_null(), "binary read failed");
            assert_eq!(actual, expected);
            assert!(xf_stream_close(stream, 2000).is_null());
        }
    }

    #[test]
    fn send_preserves_binary_bytes_across_small_stream_buffers() {
        let expected: Vec<u8> = (0_u16..256).map(|i| i as u8).collect();
        let (client, mut peer) = tokio::io::duplex(16);
        let (sender, receiver) = std::sync::mpsc::channel();
        crate::GLOBAL_RUNTIME.spawn(async move {
            let mut actual = vec![0_u8; 256];
            peer.read_exact(&mut actual).await.unwrap();
            sender.send(actual).unwrap();
        });
        let stream = Box::into_raw(Box::new(ReadWriteOpaque { inner: Some(Box::new(client)) }));
        unsafe {
            assert!(xf_stream_send(stream, expected.as_ptr(), expected.len(), 2000).is_null());
            assert_eq!(receiver.recv_timeout(Duration::from_secs(2)).unwrap(), expected);
            assert!(xf_stream_close(stream, 2000).is_null());
        }
    }

    #[test]
    fn timeout_invalidates_the_connection_before_reuse() {
        let (client, _silent_peer) = tokio::io::duplex(16);
        let stream = Box::into_raw(Box::new(ReadWriteOpaque { inner: Some(Box::new(client)) }));
        let mut output = [0_u8; 1];
        let started = std::time::Instant::now();
        unsafe {
            let error = xf_stream_read_exact(stream, output.as_mut_ptr(), 1, 20);
            assert!(!error.is_null());
            assert_eq!((*error).code, IdeviceError::Timeout.code());
            crate::idevice_error_free(error);
            assert!((*stream).inner.is_none());
            let reuse_error = xf_stream_send(stream, output.as_ptr(), 1, 20);
            assert!(!reuse_error.is_null());
            crate::idevice_error_free(reuse_error);
            assert!(xf_stream_close(stream, 20).is_null());
        }
        assert!(started.elapsed() < Duration::from_secs(1));
    }
}
