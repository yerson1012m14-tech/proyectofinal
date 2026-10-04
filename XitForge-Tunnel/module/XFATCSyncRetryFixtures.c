#include "XFATCSyncRetry.h"
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
/* Model outcomes at the transport boundary using the production retry policy. */
typedef struct { bool success, socketFailure, moveAttempted; } Outcome;
static unsigned attempts(const Outcome *outcomes, unsigned count, bool fresh) {
    for(unsigned i=0;i<count;i++) {
        Outcome o=outcomes[i];
        if(o.success || !XFATCShouldRetryPreparation(i+1,fresh,o.socketFailure,o.moveAttempted))return i+1;
    }
    return 0;
}
int main(void) {
    CHECK(XFATCPreparationTransportFailure(true,109,0));
    CHECK(XFATCPreparationTransportFailure(true,1,0));
    CHECK(!XFATCPreparationTransportFailure(false,109,0));
    CHECK(!XFATCPreparationTransportFailure(false,1,0));
    CHECK(!XFATCPreparationTransportFailure(true,109,10));
    CHECK(!XFATCPreparationTransportFailure(true,106,10));
    CHECK(!XFATCPreparationTransportFailure(true,106,8));
    CHECK(!XFATCPreparationTransportFailure(true,2116,0));
    bool timeout=XFATCPreparationTransportFailure(true,109,0);
    const Outcome timedOut[]={{false,timeout,false},{true,false,true}};
    const Outcome repeatedTimeout[]={{false,timeout,false},{false,timeout,false},{false,timeout,false},{true,false,true}};
    const Outcome timeoutAfterMove[]={{false,timeout,true},{true,false,true}};
    CHECK(attempts(timedOut,2,true)==2);
    CHECK(attempts(repeatedTimeout,4,true)==3);
    CHECK(attempts(timeoutAfterMove,2,true)==1);
    const Outcome interrupted[]={{false,true,false},{true,false,true}};
    const Outcome repeated[]={{false,true,false},{false,true,false},{false,true,false},{true,false,true}};
    const Outcome partialSend[]={{false,true,true},{true,false,true}};
    const Outcome denied[]={{false,false,false},{true,false,true}};
    const Outcome firstSuccess[]={{true,false,true},{true,false,true}};
    CHECK(attempts(interrupted,2,true)==2);
    CHECK(attempts(repeated,4,true)==3);
    CHECK(attempts(partialSend,2,true)==1);
    CHECK(attempts(denied,2,true)==1);
    CHECK(attempts(interrupted,2,false)==1);
    CHECK(attempts(firstSuccess,2,true)==1);
    CHECK(XFATCSyncRetryDelayMS(1)==300);
    CHECK(XFATCSyncRetryDelayMS(2)==600);
    CHECK(XFATCSyncRetryDelayMS(3)==0);
    for(unsigned n=0;n<=5;n++)for(unsigned fresh=0;fresh<2;fresh++)
        for(unsigned socket=0;socket<2;socket++)for(unsigned moved=0;moved<2;moved++) {
            bool retry=XFATCShouldRetryPreparation(n,fresh,socket,moved);
            if(n==0||n>=3||!fresh||!socket||moved)CHECK(!retry);
            else CHECK(retry);
        }
    return 0;
}
