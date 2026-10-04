#ifndef XF_ATC_FILE_RECOVERY_H
#define XF_ATC_FILE_RECOVERY_H

#include <stdbool.h>

/* Observations must be fresh. Permission/transport/parse failures are Unknown,
   never Missing. Present means an owned, regular staging file whose identity
   and expected content were validated; foreign or changed files are Unknown. */
typedef enum {
    XFATCFilePresenceUnknown = 0,
    XFATCFilePresenceMissing = 1,
    XFATCFilePresencePresent = 2
} XFATCFilePresence;

typedef enum {
    XFATCFileRecoveryRead = 0,
    XFATCFileRecoveryReplace = 1,
    XFATCFileRecoveryDelete = 2
} XFATCFileRecoveryOperation;

typedef struct {
    XFATCFileRecoveryOperation operation;
    XFATCFilePresence original;
    XFATCFilePresence incoming;
    XFATCFilePresence verify;
    /* Target Present means a known occupied path; recovery never overwrites it.
       Target Unknown is expected when the protected path cannot be inspected. */
    XFATCFilePresence target;
    /* Facts loaded from a valid, same-device, same-token durable journal. */
    bool originalCaptured;
    bool replacementVerified;
    bool returnOriginalIntent;
    bool placementIntent;
    bool returnReplacementIntent;
    bool committed;
} XFATCFileRecoveryObservation;

typedef enum {
    XFATCFileRecoveryPending = 0,
    XFATCFileRecoveryReadReturnConfirmed = 1,
    XFATCFileRecoveryWriteCommitted = 2,
    XFATCFileRecoveryOriginalRestoreCandidate = 3,
    XFATCFileRecoveryDeleteCommitted = 4
} XFATCFileRecoveryDecision;

static inline bool XFATCFileRecoveryPresenceValid(XFATCFilePresence presence) {
    return presence >= XFATCFilePresenceUnknown &&
           presence <= XFATCFilePresencePresent;
}

/* Classifies evidence only; it performs no I/O and grants no mutation authority.
   ReturnConfirmed is the journal/source-location predicate: it does not prove
   atomic no-clobber placement or that the app has not changed the destination.
   RestoreCandidate still needs a caller-controlled return operation; without
   an atomic no-clobber facility, target absence alone cannot prevent races.
   Pending retains original/local backup and journal; never claim rollback.
   DeleteCommitted means a durable delete decision with the validated original
   retained in staging. Target Unknown proves only that relocation was retained;
   only a fresh Target Missing observation confirms destination absence. Neither
   result grants permission to remove the staged original or its local backup.
   A delete decision must never trigger automatic restoration, including when
   later observations are Pending; the caller must preserve the durable commit
   flag. Before that flag is durable, an exact, explicitly authorized restoration
   remains a separate operation controlled by the caller. */
static inline XFATCFileRecoveryDecision XFATCClassifyFileRecovery(
    XFATCFileRecoveryObservation state) {
    if ((state.operation != XFATCFileRecoveryRead &&
         state.operation != XFATCFileRecoveryReplace &&
         state.operation != XFATCFileRecoveryDelete) ||
        !XFATCFileRecoveryPresenceValid(state.original) ||
        !XFATCFileRecoveryPresenceValid(state.incoming) ||
        !XFATCFileRecoveryPresenceValid(state.verify) ||
        !XFATCFileRecoveryPresenceValid(state.target) ||
        state.original == XFATCFilePresenceUnknown ||
        state.incoming == XFATCFilePresenceUnknown ||
        state.verify == XFATCFilePresenceUnknown ||
        !state.originalCaptured) {
        return XFATCFileRecoveryPending;
    }

    if (state.operation == XFATCFileRecoveryDelete) {
        if (state.committed &&
            state.original == XFATCFilePresencePresent &&
            state.incoming == XFATCFilePresenceMissing &&
            state.verify == XFATCFilePresenceMissing &&
            state.target != XFATCFilePresencePresent &&
            !state.returnOriginalIntent && !state.placementIntent &&
            !state.returnReplacementIntent && !state.replacementVerified) {
            return XFATCFileRecoveryDeleteCommitted;
        }
        return XFATCFileRecoveryPending;
    }

    if (state.operation == XFATCFileRecoveryRead) {
        if (state.incoming != XFATCFilePresenceMissing ||
            state.verify != XFATCFilePresenceMissing ||
            state.placementIntent || state.returnReplacementIntent ||
            state.replacementVerified || state.committed) {
            return XFATCFileRecoveryPending;
        }
        if (state.original == XFATCFilePresenceMissing &&
            state.returnOriginalIntent &&
            state.target != XFATCFilePresenceMissing) {
            return XFATCFileRecoveryReadReturnConfirmed;
        }
        if (state.original == XFATCFilePresencePresent &&
            state.target == XFATCFilePresenceMissing) {
            return XFATCFileRecoveryOriginalRestoreCandidate;
        }
        return XFATCFileRecoveryPending;
    }

    if (state.returnOriginalIntent) return XFATCFileRecoveryPending;

    if (state.committed && state.placementIntent &&
        state.replacementVerified && state.returnReplacementIntent &&
        state.incoming == XFATCFilePresenceMissing &&
        state.verify == XFATCFilePresenceMissing &&
        state.target != XFATCFilePresenceMissing) {
        return XFATCFileRecoveryWriteCommitted;
    }

    if (!state.committed && !state.placementIntent &&
        !state.returnReplacementIntent && !state.replacementVerified &&
        state.original == XFATCFilePresencePresent &&
        state.verify == XFATCFilePresenceMissing &&
        state.target == XFATCFilePresenceMissing) {
        return XFATCFileRecoveryOriginalRestoreCandidate;
    }
    return XFATCFileRecoveryPending;
}

#endif
