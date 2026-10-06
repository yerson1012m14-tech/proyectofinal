#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../XitForge-Tunnel/shared/XFUserFacingError.h"

static IMP XFOriginalFinishActivationUI = NULL;

static void XFFinishActivationUIWithDiagnostics(id self, SEL _cmd, BOOL success, NSString *message) {
    if (XFOriginalFinishActivationUI) {
        ((void (*)(id, SEL, BOOL, NSString *))XFOriginalFinishActivationUI)(self, _cmd, success, message);
    }

    if (success || ![message isKindOfClass:NSString.class] || message.length == 0) return;
    NSLog(@"XITFORGE diagnóstico de activación: %@",message);
    message=XFUserFacingError(message);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self isKindOfClass:UIViewController.class]) return;
        UIViewController *controller = (UIViewController *)self;
        if (controller.presentedViewController) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"NO SE PUDO ACTIVAR"
            message:message
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"ENTENDIDO"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

@interface XITForgeActivationDiagnostics : NSObject
@end

@implementation XITForgeActivationDiagnostics

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"XITForgeOptionsViewController");
        SEL selector = NSSelectorFromString(@"finishActivationUIWithSuccess:message:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (!method) return;

        XFOriginalFinishActivationUI = method_getImplementation(method);
        method_setImplementation(method, (IMP)XFFinishActivationUIWithDiagnostics);
    });
}

@end
