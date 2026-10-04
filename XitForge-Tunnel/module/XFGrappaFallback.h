#ifndef XF_GRAPPA_FALLBACK_H
#define XF_GRAPPA_FALLBACK_H

#include <stddef.h>
#include <stdint.h>

/* Opaque 84-byte CoreFP protocol request from the user-supplied 3105 IPA.
 * Functional protocol data only; the helper implementation is our own.
 * This is a protocol request, not an approval result. AirTraffic must accept it
 * through the normal ReadyForSync / matching AssetManifest exchange.
 * Keep this independent of optional private frameworks inside the client app.
 */
static const uint8_t XFGrappaProtocolRequestV1[] = {
    0x01,0x01,0x07,0x0b,0x83,0xc0,0x3d,0xd1,0xad,0x2a,0x2d,0x06,
    0xd9,0xe1,0xeb,0xa5,0xba,0x2b,0x01,0x40,0xbe,0x70,0x31,0x5a,
    0x30,0xf3,0x14,0x09,0xa5,0xee,0x6a,0xae,0xda,0x3d,0x64,0x78,
    0x64,0xfa,0xb9,0x8f,0x63,0xfc,0x0c,0xcd,0x65,0x28,0x8b,0xc5,
    0xa2,0x19,0xa7,0x38,0x24,0x6a,0x87,0x78,0x84,0xb8,0xb9,0x0a,
    0xb9,0x88,0x8d,0xba,0xe5,0x11,0x69,0xf5,0x94,0x8d,0xae,0x8f,
    0xee,0x67,0xb6,0xea,0x7e,0x64,0x73,0xae,0xbe,0xbd,0xc9,0xf5
};

/* 0: bytes available, -1: invalid output, -5: unsupported protocol,
 * -6: insufficient capacity. Failed calls clear length and never alter bytes.
 */
static inline int XFCopyGrappaProtocolRequest(uint32_t version,
                                             uint32_t protocolVersion,
                                             uint8_t *output,
                                             size_t capacity,
                                             size_t *length) {
    if (length) *length = 0;
    if (!output || !length) return -1;
    if (version != 1 || protocolVersion != 1) return -5;
    if (capacity < sizeof(XFGrappaProtocolRequestV1)) return -6;
    for (size_t index = 0; index < sizeof(XFGrappaProtocolRequestV1); index++)
        output[index] = XFGrappaProtocolRequestV1[index];
    *length = sizeof(XFGrappaProtocolRequestV1);
    return 0;
}

#endif
