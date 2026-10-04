#ifndef XF_STREAM_BRIDGE_H
#define XF_STREAM_BRIDGE_H
#include "idevice.h"

// All handles and calls stay on the adapter's native worker thread.
// A failed read/write invalidates protocol framing; close the stream before retrying.
struct IdeviceFfiError *xf_rsd_connect_service(struct AdapterHandle *adapter,
    struct RsdHandshakeHandle *handshake, const char *service_name,
    bool perform_checkin, uint64_t timeout_ms, struct ReadWriteOpaque **out_stream);
struct IdeviceFfiError *xf_stream_send(struct ReadWriteOpaque *stream,
    const uint8_t *data, uintptr_t length, uint64_t timeout_ms);
struct IdeviceFfiError *xf_stream_recv(struct ReadWriteOpaque *stream,
    uint8_t *buffer, uintptr_t capacity, uintptr_t *out_length, uint64_t timeout_ms);
struct IdeviceFfiError *xf_stream_read_exact(struct ReadWriteOpaque *stream,
    uint8_t *buffer, uintptr_t length, uint64_t timeout_ms);
// Consumes the stream even when shutdown returns an error.
struct IdeviceFfiError *xf_stream_close(struct ReadWriteOpaque *stream,
    uint64_t timeout_ms);
// Returns the original advertised Services dictionary as XML plist bytes.
// Free out_data with idevice_data_free(out_data, out_length).
struct IdeviceFfiError *xf_rsd_advertised_services(struct RsdHandshakeHandle *handshake,
    uint8_t **out_data, uintptr_t *out_length);
struct IdeviceFfiError *xf_afc_connect_rsd(struct AdapterHandle *adapter,
    struct RsdHandshakeHandle *handshake, uint64_t timeout_ms, struct AfcClientHandle **out_client);
struct IdeviceFfiError *xf_afc_get_mtime(struct AfcClientHandle *client,
    const char *path, int64_t *out_mtime_nanos, uint64_t timeout_ms);
struct IdeviceFfiError *xf_afc_set_file_time(struct AfcClientHandle *client,
    const char *path, int64_t mtime_nanos, uint64_t timeout_ms);
#endif
