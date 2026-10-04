#include "XFATCFileRecovery.h"
#include <assert.h>
#include <stddef.h>

#define U XFATCFilePresenceUnknown
#define M XFATCFilePresenceMissing
#define P XFATCFilePresencePresent
#define R XFATCFileRecoveryRead
#define W XFATCFileRecoveryReplace
#define D XFATCFileRecoveryDelete
#define WAIT XFATCFileRecoveryPending
#define READ_OK XFATCFileRecoveryReadReturnConfirmed
#define WRITE_OK XFATCFileRecoveryWriteCommitted
#define RESTORE XFATCFileRecoveryOriginalRestoreCandidate
#define DELETE_OK XFATCFileRecoveryDeleteCommitted

/* Independent crash/conflict fixtures. Field order after four presences is:
   captured, verified, returnOriginalIntent, placementIntent,
   returnReplacementIntent, committed. */
static const struct {
    const char *name;
    XFATCFileRecoveryObservation state;
    XFATCFileRecoveryDecision expected;
} fixtures[] = {
    {"read before original capture", {R,M,M,M,P,0,0,0,0,0,0}, WAIT},
    {"read original protected, destination absent", {R,P,M,M,M,1,0,0,0,0,0}, RESTORE},
    {"read return may retry while original still protected", {R,P,M,M,M,1,0,1,0,0,0}, RESTORE},
    {"read occupied destination must not be replaced", {R,P,M,M,P,1,0,1,0,0,0}, WAIT},
    {"read uninspectable destination retains original", {R,P,M,M,U,1,0,1,0,0,0}, WAIT},
    {"read recorded return and positively missing source", {R,M,M,M,U,1,0,1,0,0,0}, READ_OK},
    {"read no durable return intent", {R,M,M,M,U,1,0,0,0,0,0}, WAIT},
    {"read source stat transport failure", {R,U,M,M,U,1,0,1,0,0,0}, WAIT},
    {"read source absent but destination known absent", {R,M,M,M,M,1,0,1,0,0,0}, WAIT},
    {"read unexpected incoming file retained", {R,M,P,M,U,1,0,1,0,0,0}, WAIT},
    {"read unexpected verify file retained", {R,M,M,P,U,1,0,1,0,0,0}, WAIT},
    {"read incoming inspection error is not absence", {R,M,U,M,U,1,0,1,0,0,0}, WAIT},
    {"write original protected before placement", {W,P,P,M,M,1,0,0,0,0,0}, RESTORE},
    {"write staged source absent before placement", {W,P,M,M,M,1,0,0,0,0,0}, RESTORE},
    {"write recreated destination blocks rollback", {W,P,P,M,P,1,0,0,0,0,0}, WAIT},
    {"write destination permission denied blocks rollback", {W,P,P,M,U,1,0,0,0,0,0}, WAIT},
    {"write placement intent, lost acknowledgement", {W,P,M,M,M,1,0,0,1,0,0}, WAIT},
    {"write candidate moved to verify but not compared", {W,P,M,P,U,1,0,0,1,0,0}, WAIT},
    {"write compared candidate still in verify", {W,P,M,P,U,1,1,0,1,1,0}, WAIT},
    {"write new return source stat failure", {W,P,M,U,U,1,1,0,1,1,1}, WAIT},
    {"write return proof without durable commit", {W,P,M,M,U,1,1,0,1,1,0}, WAIT},
    {"write committed return proof, original preserved", {W,P,M,M,U,1,1,0,1,1,1}, WRITE_OK},
    {"write committed original already cleaned", {W,M,M,M,U,1,1,0,1,1,1}, WRITE_OK},
    {"write committed destination now known absent", {W,P,M,M,M,1,1,0,1,1,1}, WAIT},
    {"write leftover incoming contradicts completion", {W,P,P,M,U,1,1,0,1,1,1}, WAIT},
    {"write no recorded comparison", {W,P,M,M,U,1,0,0,1,1,1}, WAIT},
    {"write no recorded original", {W,P,M,M,U,0,1,0,1,1,1}, WAIT},
    {"write mutually conflicting return intents", {W,P,M,M,U,1,1,1,1,1,1}, WAIT},
    {"write unknown original must be retained", {W,U,M,M,U,1,1,0,1,1,1}, WAIT},
    {"journal invalid presence discriminant", {W,P,M,M,99,1,1,0,1,1,1}, WAIT},
    {"journal invalid operation discriminant", {99,P,M,M,U,1,1,0,1,1,1}, WAIT},
    {"delete before original capture stays pending", {D,P,M,M,M,0,0,0,0,0,0}, WAIT},
    {"delete captured original before commit stays pending", {D,P,M,M,M,1,0,0,0,0,0}, WAIT},
    {"delete interrupted before commit with uninspectable target", {D,P,M,M,U,1,0,0,0,0,0}, WAIT},
    {"delete explicitly returning original before commit is caller controlled", {D,P,M,M,M,1,0,1,0,0,0}, WAIT},
    {"delete committed relocation with uninspectable target", {D,P,M,M,U,1,0,0,0,0,1}, DELETE_OK},
    {"delete committed and destination positively absent", {D,P,M,M,M,1,0,0,0,0,1}, DELETE_OK},
    {"delete destination recreated after commit stays pending", {D,P,M,M,P,1,0,0,0,0,1}, WAIT},
    {"delete original missing is not committed proof while active", {D,M,M,M,U,1,0,0,0,0,1}, WAIT},
    {"delete original stat failure cannot be disappearance", {D,U,M,M,U,1,0,0,0,0,1}, WAIT},
    {"delete incoming stat failure retains recovery", {D,P,U,M,U,1,0,0,0,0,1}, WAIT},
    {"delete verify stat failure retains recovery", {D,P,M,U,U,1,0,0,0,0,1}, WAIT},
    {"delete unexpected incoming file contradicts commit", {D,P,P,M,U,1,0,0,0,0,1}, WAIT},
    {"delete unexpected verify file contradicts commit", {D,P,M,P,U,1,0,0,0,0,1}, WAIT},
    {"delete missing durable original snapshot blocks commit", {D,P,M,M,U,0,0,0,0,0,1}, WAIT},
    {"delete original return intent conflicts with commit", {D,P,M,M,U,1,0,1,0,0,1}, WAIT},
    {"delete placement intent conflicts with commit", {D,P,M,M,U,1,0,0,1,0,1}, WAIT},
    {"delete replacement return intent conflicts with commit", {D,P,M,M,U,1,0,0,0,1,1}, WAIT},
    {"delete replacement verification conflicts with commit", {D,P,M,M,U,1,1,0,0,0,1}, WAIT},
    {"delete invalid target discriminant fails closed", {D,P,M,M,99,1,0,0,0,0,1}, WAIT},
    {"delete invalid original discriminant fails closed", {D,99,M,M,U,1,0,0,0,0,1}, WAIT}
};

int main(void) {
    for (size_t i = 0; i < sizeof(fixtures)/sizeof(fixtures[0]); ++i) {
        (void)fixtures[i].name;
        assert(XFATCClassifyFileRecovery(fixtures[i].state) == fixtures[i].expected);
    }

    /* Safety properties across all 81 observed placement combinations. */
    for (int o=0; o<3; ++o) for (int i=0; i<3; ++i)
    for (int v=0; v<3; ++v) for (int d=0; d<3; ++d) {
        XFATCFileRecoveryObservation before = {W,o,i,v,d,1,0,0,0,0,0};
        XFATCFileRecoveryDecision decision = XFATCClassifyFileRecovery(before);
        if (d != M || o != P || v != M || i == U) assert(decision != RESTORE);
        before.placementIntent = true;
        assert(XFATCClassifyFileRecovery(before) == WAIT);

        XFATCFileRecoveryObservation committed = {W,o,i,v,d,1,1,0,1,1,1};
        decision = XFATCClassifyFileRecovery(committed);
        if (o == U || i != M || v != M || d == M) assert(decision != WRITE_OK);

        /* Delete covers every presence and all six durable flag combinations.
           A Pending delete never grants restore authority, even after commit. */
        for (unsigned flags=0; flags<64; ++flags) {
            XFATCFileRecoveryObservation deletion = {
                D,o,i,v,d,
                (flags & 1u) != 0, (flags & 2u) != 0,
                (flags & 4u) != 0, (flags & 8u) != 0,
                (flags & 16u) != 0, (flags & 32u) != 0
            };
            decision = XFATCClassifyFileRecovery(deletion);
            bool expectedCommit = o == P && i == M && v == M && d != P &&
                deletion.originalCaptured && deletion.committed &&
                !deletion.replacementVerified && !deletion.returnOriginalIntent &&
                !deletion.placementIntent && !deletion.returnReplacementIntent;
            assert(decision == (expectedCommit ? DELETE_OK : WAIT));
            assert(decision != RESTORE && decision != READ_OK && decision != WRITE_OK);
        }
    }
    return 0;
}
