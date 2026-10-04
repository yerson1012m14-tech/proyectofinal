#include "XFFileCreationProbePolicy.h"
#define CHECK(condition) do { if (!(condition)) return __LINE__; } while (0)
int main(void) {
    CHECK(XFProbeAFCConfirmsAbsence(true,106,8,true,true));
    CHECK(!XFProbeAFCConfirmsAbsence(false,0,0,true,true)); /* existing file */
    CHECK(!XFProbeAFCConfirmsAbsence(true,106,10,true,true)); /* permission denied */
    CHECK(!XFProbeAFCConfirmsAbsence(true,106,15,true,true)); /* already exists */
    CHECK(!XFProbeAFCConfirmsAbsence(true,1,0,true,true)); /* channel closed */
    CHECK(!XFProbeAFCConfirmsAbsence(true,15,8,true,true)); /* unrelated native error */
    CHECK(!XFProbeAFCConfirmsAbsence(true,106,8,false,true)); /* stale link */
    CHECK(!XFProbeAFCConfirmsAbsence(true,106,8,true,false)); /* link changed during probe */
    CHECK(!XFProbeAFCConfirmsAbsence(false,106,8,true,true)); /* stale error fields */
    for(int code=0;code<220;code++)for(int sub=0;sub<32;sub++)
        if(code!=106||sub!=8)CHECK(!XFProbeAFCConfirmsAbsence(true,code,sub,true,true));
    return 0;
}
