#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LicenseValidationCompletion)(BOOL valid,
                                             NSString * _Nullable reason,
                                             NSString * _Nullable expiresAt);

@interface LicenseValidator : NSObject

+ (void)validateKey:(NSString *)key
         completion:(LicenseValidationCompletion)completion;

// Configura Authorization: Bearer para cada peticion protegida; renueva la
// sesion contra el servidor cuando falten menos de 30 segundos para su fin.
+ (void)authorizeRequest:(NSMutableURLRequest *)request
              completion:(void (^)(BOOL authorized))completion;

+ (void)clearSession;
+ (void)handleProtectedHTTPResponse:(NSURLResponse * _Nullable)response;

@end

NS_ASSUME_NONNULL_END
