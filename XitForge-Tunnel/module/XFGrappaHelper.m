// Adapted from AirCard-iOS GrappaHelper.m. MIT; see AirCard-LICENSE.txt.
#import "XFGrappaHelper.h"
#import "XFGrappaFallback.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* Native host generation is optional on iOS. A private device-side verifier
 * inside this app is not the AirTraffic daemon and cannot authorize/reject the
 * request on its behalf. In particular, missing CoreFP or a failed local
 * session must not prevent sending the public protocol request to the service.
 */
static NSData *XFNativeGrappaRequest(NSDictionary *info) {
    @try {
        void *handle = dlopen("/System/Library/PrivateFrameworks/AirTrafficDevice.framework/AirTrafficDevice", RTLD_NOW);
        if (!handle)
            handle = dlopen("/System/Library/PrivateFrameworks/AirTrafficHost.framework/AirTrafficHost", RTLD_NOW);
        if (!handle) return nil;

        Class cls = objc_getClass("ATGrappaSession");
        if (!cls) return nil;
        id session = [cls alloc];
        SEL initialize = sel_registerName("initWithType:");
        if (![session respondsToSelector:initialize]) return nil;
        session = ((id (*)(id, SEL, unsigned int))objc_msgSend)(session, initialize, 1);
        SEL establish = sel_registerName("establishHostSessionWithDeviceInfo:clientRequestData:");
        if (!session || ![session respondsToSelector:establish]) return nil;

        NSData *request = nil;
        NSError *failure = ((id (*)(id, SEL, id, id *))objc_msgSend)(session, establish, info, &request);
        if (failure || ![request isKindOfClass:NSData.class] || !request.length) return nil;
        return request;
    } @catch (NSException *exception) {
        // Private API failure leaves the protocol fallback available.
        return nil;
    }
}

__attribute__((visibility("default"), used))
int XFGetGrappaToken(uint32_t in_version,
                     uint32_t in_device_type,
                     uint32_t in_protocol_version,
                     uint8_t *out_buf,
                     size_t max_len,
                     size_t *out_len,
                     char *err_buf,
                     size_t err_len) {
    if (out_len) *out_len = 0;
    if (err_buf && err_len) err_buf[0] = '\0';
    if (!out_buf || !max_len) {
        if (err_buf && err_len) snprintf(err_buf, err_len, "invalid output buffer");
        return -1;
    }

    @autoreleasepool {
        uint32_t version = in_version ? in_version : 1;
        uint32_t protocol = in_protocol_version ? in_protocol_version : 1;
        size_t length = 0;
        int result = XFCopyGrappaProtocolRequest(version, protocol, out_buf, max_len, &length);
        if (!result) {
            if (out_len) *out_len = length;
            return 0; // Request available; runATC still requires service approval.
        }
        if (result != -5) {
            if (err_buf && err_len) snprintf(err_buf, err_len, "Grappa request buffer too small: %zu", max_len);
            return result;
        }
        // Use the service's advertised values, including a valid deviceType 0.
        NSDictionary *info = @{@"version":@(version), @"deviceType":@(in_device_type),
                               @"protocolVersion":@(protocol)};
        NSData *request = XFNativeGrappaRequest(info);
        if (request.length) {
            if (request.length > max_len) {
                if (err_buf && err_len) snprintf(err_buf, err_len, "buffer too small: %zu > %zu", (size_t)request.length, max_len);
                return -6;
            }
            memcpy(out_buf, request.bytes, request.length);
            if (out_len) *out_len = request.length;
            return 0;
        }

        if (err_buf && err_len) {
            if (result == -5)
                snprintf(err_buf, err_len, "unsupported Grappa parameters: version=%u deviceType=%u protocolVersion=%u", version, in_device_type, protocol);
            else
                snprintf(err_buf, err_len, "Grappa request buffer too small: %zu", max_len);
        }
        return result;
    }
}
