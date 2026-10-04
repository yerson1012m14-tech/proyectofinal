#ifndef XFGrappaHelper_h
#define XFGrappaHelper_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Prepares a Grappa client request for AirTraffic sync.
/// Returns 0 when bytes are available, not when authentication is approved.
/// The caller must still wait for the service's sync/manifest response.
__attribute__((visibility("default"), used))
int XFGetGrappaToken(
    uint32_t in_version,
    uint32_t in_device_type,
    uint32_t in_protocol_version,
    uint8_t *out_buf,
    size_t max_len,
    size_t *out_len,
    char *err_buf,
    size_t err_len
);

#ifdef __cplusplus
}
#endif

#endif /* XFGrappaHelper_h */
