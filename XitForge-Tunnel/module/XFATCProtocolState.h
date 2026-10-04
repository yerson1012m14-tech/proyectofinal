#ifndef XF_ATC_PROTOCOL_STATE_H
#define XF_ATC_PROTOCOL_STATE_H
#include <stdbool.h>
#include <stdint.h>

typedef enum { XFATCWaitContinue=0, XFATCWaitAccept=1,
    XFATCWaitPong=2, XFATCWaitRejectSync=3, XFATCWaitRejectEnd=4 } XFATCWaitDecision;

static inline bool XFATCCommandEquals(const char *a,const char *b) {
    if(!a||!b)return false;
    while(*a&&*a==*b){a++;b++;}
    return *a==*b;
}

/* ReadyForSync is required before metadata. A manifest cannot replace it.
   Cancellation while waiting for the post-metadata manifest is a real failure. */
static inline XFATCWaitDecision XFATCDecisionForMessage(const char *wanted,
    const char *command,bool hasErrorCode,int64_t errorCode) {
    if(!wanted||!command)return XFATCWaitContinue;
    if(XFATCCommandEquals(command,"Ping"))return XFATCWaitPong;
    if(XFATCCommandEquals(command,"SyncFailed")) {
        if(hasErrorCode&&errorCode==4&&!XFATCCommandEquals(wanted,"AssetManifest"))return XFATCWaitContinue;
        return XFATCWaitRejectSync;
    }
    if(XFATCCommandEquals(command,"SyncFinished"))return XFATCWaitRejectEnd;
    if(XFATCCommandEquals(wanted,command))return XFATCWaitAccept;
    return XFATCWaitContinue;
}
#endif
