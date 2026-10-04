#ifndef XF_FILE_CREATION_PROBE_POLICY_H
#define XF_FILE_CREATION_PROBE_POLICY_H
#include <stdbool.h>

/* A transport error, permission denial, or a vanished link is not absence.
   Both link observations must refer to the intended application directory. */
static inline bool XFProbeAFCConfirmsAbsence(bool returnedError, int code, int subcode,
                                           bool linkValidBefore, bool linkValidAfter) {
    return returnedError && code == 106 && subcode == 8 && linkValidBefore && linkValidAfter;
}
#endif
