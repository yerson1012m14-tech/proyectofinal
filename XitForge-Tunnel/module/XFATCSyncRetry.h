#ifndef XF_ATC_SYNC_RETRY_H
#define XF_ATC_SYNC_RETRY_H
#include <stdbool.h>

/* Native FFI: Socket=1; Timeout=109/0. Do not classify a Foundation or
   protocol error by its numeric code alone. */
static inline bool XFATCPreparationTransportFailure(bool nativeError, long code, long subcode) {
    return nativeError && (code == 1 || (code == 109 && subcode == 0));
}

/* Reconnect only during session preparation. A partially sent FileComplete can
   already have moved a file; its outcome must be reconciled, never replayed. */
static inline bool XFATCShouldRetryPreparation(unsigned completedAttempts,
    bool freshTunnelAvailable, bool transportFailure, bool fileMoveAttempted) {
    return completedAttempts > 0 && completedAttempts < 3 && freshTunnelAvailable &&
           transportFailure && !fileMoveAttempted;
}
static inline unsigned XFATCSyncRetryDelayMS(unsigned completedAttempts) {
    return completedAttempts == 1 ? 300 : completedAttempts == 2 ? 600 : 0;
}
#endif
