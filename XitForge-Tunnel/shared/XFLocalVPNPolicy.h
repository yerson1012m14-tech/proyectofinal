#ifndef XF_LOCAL_VPN_POLICY_H
#define XF_LOCAL_VPN_POLICY_H

#include <stdbool.h>
#include <stdint.h>

enum { XFLocalVPNExternalRequired = 2 };

// An interface is only a preparation candidate. The existing authenticated
// Remote Pairing/RSD handshake still decides whether the tunnel is connected.
// IPv4 inputs are in host byte order.
static inline bool XFLocalVPNInterfaceCandidate(const char *name, bool up,
                                                uint32_t local, uint32_t mask,
                                                uint32_t peer) {
    if (!name || name[0] != 'u' || name[1] != 't' || name[2] != 'u' ||
        name[3] != 'n' || !up || !local || !peer || local == peer)
        return false;
    if ((local >> 24) == 127 || (peer >> 24) == 127 ||
        (local >> 24) >= 224 || (peer >> 24) >= 224)
        return false;
    uint32_t inverse = ~mask;
    if (mask < UINT32_C(0xFFFFFF00) || (inverse & (inverse + 1)) != 0)
        return false;
    // LocalDevVPN's current defaults use two separate /32 networks.
    if (local == UINT32_C(0x0A070101) && peer == UINT32_C(0x0A070001))
        return true;
    // Older defaults and the same-subnet /30 configuration.
    return mask != UINT32_MAX && (local & mask) == (peer & mask);
}

#endif
