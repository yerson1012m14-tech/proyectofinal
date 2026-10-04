#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "LicenseValidator.h"
#import "XITForgeFileEngine.h"

static IMP XFOriginalApplyOptionIMP = NULL;

static NSString *XFStringValue(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static id XFOptionValue(id option, NSString *key) {
    @try { return [option valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static void XFShowActivationResult(id owner, NSString *message, BOOL success) {
    SEL selector = NSSelectorFromString(@"showResult:success:");
    if ([owner respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSString *, BOOL))objc_msgSend)(owner, selector, message ?: @"Sin detalle.", success);
    }
}

static NSURL *XFAbsoluteServerURL(id owner, NSString *rawURL) {
    SEL selector = NSSelectorFromString(@"absoluteServerURLForString:");
    if (![owner respondsToSelector:selector]) return nil;
    return ((NSURL * (*)(id, SEL, NSString *))objc_msgSend)(owner, selector, rawURL);
}

static void XFForceTunnelApplyOption(id self, SEL _cmd, id option) {
    (void)_cmd;

    NSString *fileURL = XFStringValue(XFOptionValue(option, @"fileUrl"));
    NSString *route = XFStringValue(XFOptionValue(option, @"route"));
    NSString *fileName = XFStringValue(XFOptionValue(option, @"fileName"));
    NSString *bundleID = XFStringValue(XFOptionValue(option, @"bundleId"));
    if (!bundleID.length) {
        @try { bundleID = XFStringValue([self valueForKey:@"bundleId"]); }
        @catch (__unused NSException *exception) { bundleID = nil; }
    }

    if (!fileURL.length) { XFShowActivationResult(self, @"Esta opción no tiene un archivo configurado.", NO); return; }
    if (!route.length) { XFShowActivationResult(self, @"Esta opción no tiene una ruta configurada.", NO); return; }
    if (!fileName.length) { XFShowActivationResult(self, @"Esta opción no tiene un nombre de archivo configurado.", NO); return; }
    if (!bundleID.length) { XFShowActivationResult(self, @"No se pudo determinar el bundle ID del juego.", NO); return; }

    NSString *relativeError = nil;
    NSString *relativePath = [XITForgeFileEngine relativePathForRoute:route fileName:fileName error:&relativeError];
    if (!relativePath.length) {
        XFShowActivationResult(self, relativeError ?: @"La ruta configurada no es válida.", NO);
        return;
    }

    NSURL *downloadURL = XFAbsoluteServerURL(self, fileURL);
    if (!downloadURL) { XFShowActivationResult(self, @"La URL del archivo no es válida.", NO); return; }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:downloadURL];
    request.timeoutInterval = 60.0;

    [LicenseValidator authorizeRequest:request completion:^(BOOL authorized) {
        if (!authorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                XFShowActivationResult(self, @"Licencia no autorizada. Inicia sesión nuevamente.", NO);
            });
            return;
        }

        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            [LicenseValidator handleProtectedHTTPResponse:response];

            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (error || !data.length || !http || http.statusCode < 200 || http.statusCode >= 300) {
                NSString *detail = error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %@", http ? @(http.statusCode) : @"sin respuesta"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    XFShowActivationResult(self, [NSString stringWithFormat:@"La descarga fue rechazada por el servidor. %@", detail], NO);
                });
                return;
            }

            NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            NSString *tempName = [NSString stringWithFormat:@"xitforge-tunnel-%@-%@", NSUUID.UUID.UUIDString, fileName.lastPathComponent ?: @"payload.bin"];
            NSURL *tempURL = [tempDir URLByAppendingPathComponent:tempName isDirectory:NO];
            NSError *writeError = nil;
            if (![data writeToURL:tempURL options:NSDataWritingAtomic error:&writeError]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    XFShowActivationResult(self, writeError.localizedDescription ?: @"No se pudo preparar el archivo descargado.", NO);
                });
                return;
            }

            [XITForgeFileEngine replaceFileViaTunnelFromURL:tempURL
                                                   bundleID:bundleID
                                                      route:route
                                                   fileName:fileName
                                                 completion:^(BOOL success, NSString *message) {
                [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
                XFShowActivationResult(self, success ? @"Archivo agregado correctamente · TÚNEL" : message, success);
            }];
        }];
        [task resume];
    }];
}

@interface XITForgeForceTunnelFallback : NSObject
@end

@implementation XITForgeForceTunnelFallback
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"XITForgeOptionsViewController");
        SEL selector = NSSelectorFromString(@"applyOption:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (!method) return;
        XFOriginalApplyOptionIMP = method_getImplementation(method);
        method_setImplementation(method, (IMP)XFForceTunnelApplyOption);
    });
}
@end
