#ifndef XF_ATC_SYNC_RETRY_H
#define XF_ATC_SYNC_RETRY_H
#include <stdbool.h>

/* Reconnect only during session preparation. A partially sent FileComplete can
   already have moved a file; its outcome must be reconciled, never replayed. */
static inline bool XFATCShouldRetryPreparation(unsigned completedAttempts,
    bool freshTunnelAvailable, bool socketFailure, bool fileMoveAttempted) {
    return completedAttempts > 0 && completedAttempts < 3 && freshTunnelAvailable &&
           socketFailure && !fileMoveAttempted;
}
static inline unsigned XFATCSyncRetryDelayMS(unsigned completedAttempts) {
    return completedAttempts == 1 ? 300 : completedAttempts == 2 ? 600 : 0;
}
#endif
