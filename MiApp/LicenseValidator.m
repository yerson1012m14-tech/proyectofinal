#import "LicenseValidator.h"
#import <UIKit/UIKit.h>

static NSString * const kLicenseAPIURL =
    @"https://xitforge-license-server.onrender.com/api/license/validate";

static NSString * const kLicenseAccessLevelDefaultsKey =
    @"XITForgeLicenseAccessLevel";

static NSString *xfSessionToken = nil;
// Retained only in memory to retrieve restore-only originals after an expiry.
static NSString *xfOriginalsCleanupToken = nil;
static NSDate *xfCleanupTokenCachedUntil = nil;
static NSDate *xfSessionExpiresAt = nil;
static NSString * const kXFHost = @"xitforge-license-server.onrender.com";
static NSString * const kXFLockNotification = @"XITForgeLicenseNeedsLogin";

@implementation LicenseValidator

+ (BOOL)isValidFormat:(NSString *)key {

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];

    return [predicate evaluateWithObject:key];
}

+ (NSString *)deviceIdentifier {

    /*
     * Identificador por proveedor de Apple.
     *
     * Dos iPhones diferentes, incluso siendo el mismo modelo,
     * tendrán normalmente valores diferentes.
     */
    NSUUID *identifier =
        [UIDevice currentDevice].identifierForVendor;

    if (identifier.UUIDString.length > 0) {
        return identifier.UUIDString;
    }

    return nil;
}

+ (void)validateKey:(NSString *)key
         completion:(LicenseValidationCompletion)completion {

    // Do not keep the previous in-memory token if a fresh validation fails.
    [self clearSession];
    NSString *normalizedKey =
        [[key stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            uppercaseString];

    if (![self isValidFormat:normalizedKey]) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO, @"invalid_format", nil);
            }
        });

        return;
    }

    NSString *deviceID =
        [self deviceIdentifier];

    if (deviceID.length == 0) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO, @"device_unavailable", nil);
            }
        });

        return;
    }

    NSURL *url =
        [NSURL URLWithString:kLicenseAPIURL];

    if (!url) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO, @"invalid_url", nil);
            }
        });

        return;
    }

    /*
     * La key y el ID del dispositivo viajan por HTTPS.
     * El servidor almacena solamente el hash del deviceId.
     */
    NSDictionary *payload = @{
        @"key": normalizedKey,
        @"deviceId": deviceID
    };

    NSError *jsonError = nil;

    NSData *jsonData =
        [NSJSONSerialization
            dataWithJSONObject:payload
                        options:0
                          error:&jsonError];

    if (!jsonData) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO, @"json_error", nil);
            }
        });

        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"POST";

    [request setValue:@"application/json"
        forHTTPHeaderField:@"Content-Type"];

    [request setValue:@"application/json"
        forHTTPHeaderField:@"Accept"];

    request.HTTPBody = jsonData;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:
    ^(NSData * _Nullable data,
      NSURLResponse * _Nullable response,
      NSError * _Nullable error) {

        dispatch_async(dispatch_get_main_queue(), ^{

            if (error) {

                if (completion) {
                    completion(NO,
                               @"network_error",
                               nil);
                }

                return;
            }

            NSHTTPURLResponse *httpResponse =
                [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? (NSHTTPURLResponse *)response : nil;

            if (httpResponse.statusCode < 200 ||
                httpResponse.statusCode >= 300) {

                if (completion) {
                    completion(NO,
                               @"server_error",
                               nil);
                }

                return;
            }

            if (!data) {

                if (completion) {
                    completion(NO,
                               @"empty_response",
                               nil);
                }

                return;
            }

            NSError *parseError = nil;

            id object =
                [NSJSONSerialization
                    JSONObjectWithData:data
                    options:0
                    error:&parseError];

            if (parseError ||
                ![object isKindOfClass:
                    [NSDictionary class]]) {

                if (completion) {
                    completion(NO,
                               @"invalid_response",
                               nil);
                }

                return;
            }

            NSDictionary *json =
                (NSDictionary *)object;

            BOOL valid =
                [json[@"valid"] boolValue];

            NSString *newToken = [json[@"sessionToken"] isKindOfClass:[NSString class]]
                ? json[@"sessionToken"] : nil;
            NSString *sessionExpiry = [json[@"sessionExpiresAt"] isKindOfClass:[NSString class]]
                ? json[@"sessionExpiresAt"] : nil;
            NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
            iso.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                NSISO8601DateFormatWithFractionalSeconds;
            NSDate *newExpiry = sessionExpiry ? [iso dateFromString:sessionExpiry] : nil;
            if (!newExpiry) {
                iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
                newExpiry = sessionExpiry ? [iso dateFromString:sessionExpiry] : nil;
            }
            NSPredicate *tokenFormat = [NSPredicate predicateWithFormat:
                @"SELF MATCHES %@", @"^xf2_[0-9a-f]{64}$"];
            BOOL completeSession = [newToken isKindOfClass:[NSString class]] &&
                [tokenFormat evaluateWithObject:newToken] &&
                newExpiry && [newExpiry timeIntervalSinceNow] > 0;
            valid = valid && completeSession;

            NSString *reason =
                [json[@"reason"] isKindOfClass:
                    [NSString class]]
                    ? json[@"reason"]
                    : nil;

            NSString *expiresAt =
                [json[@"expiresAt"] isKindOfClass:
                    [NSString class]]
                    ? json[@"expiresAt"]
                    : nil;

            NSString *accessLevel =
                [json[@"accessLevel"] isKindOfClass:
                    [NSString class]]
                    ? [json[@"accessLevel"] lowercaseString]
                    : nil;

            NSUserDefaults *defaults =
                [NSUserDefaults standardUserDefaults];

            if (valid) {
                /*
                 * El servidor es la autoridad sobre el tipo de licencia.
                 * Solo aceptamos los dos niveles conocidos. Si por alguna
                 * razón el campo falta o llega alterado, se usa el nivel
                 * más limitado para no desbloquear funciones premium.
                 */
                if (![accessLevel isEqualToString:@"premium"] &&
                    ![accessLevel isEqualToString:@"aimbot_only"]) {
                    accessLevel = @"aimbot_only";
                }

                if (![accessLevel isEqualToString:@"premium"]) {
                    valid = NO; // El servidor V2 ya no admite keys gratuitas.
                } else {
                    @synchronized(self) {
                        xfSessionToken = [newToken copy];
                        xfOriginalsCleanupToken = [newToken copy];
                        xfSessionExpiresAt = newExpiry;
                    }
                    [defaults setObject:accessLevel
                                 forKey:kLicenseAccessLevelDefaultsKey];
                }
            }
            if (!valid) {
                [self clearSession];
                [defaults removeObjectForKey:kLicenseAccessLevelDefaultsKey];
                if ([json[@"valid"] boolValue] && !completeSession) {
                    reason = @"authorization_unavailable";
                }
            }

            if (completion) {
                completion(valid,
                           reason,
                           expiresAt);
            }
        });
    }];

    [task resume];
}


// La decisión sobre una opción es siempre del servidor; una preferencia local
// o una respuesta previa de /validate no son autorización suficiente.
+ (void)authorizeActivationForOptionId:(NSNumber *)optionId
                          completion:(void (^)(BOOL, BOOL))completion {
    if (![optionId isKindOfClass:[NSNumber class]] || optionId.longLongValue < 1) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, NO); });
        return;
    }
    NSString *urlString = [NSString stringWithFormat:
        @"https://xitforge-license-server.onrender.com/api/app/options/%@/authorize", optionId];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, NO); }); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20.0;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [self authorizeRequest:request completion:^(BOOL permitted) {
        if (!permitted) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, NO); }); return; }
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            [self handleProtectedHTTPResponse:response];
            BOOL accepted = NO;
            BOOL warn = NO;
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSHTTPURLResponse *)response : nil;
            if (!error && data && http.statusCode == 200) {
                id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([object isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *json = (NSDictionary *)object;
                    NSNumber *returnedId = [json[@"optionId"] isKindOfClass:[NSNumber class]]
                        ? json[@"optionId"] : nil;
                    accepted = [json[@"ok"] isKindOfClass:[NSNumber class]] &&
                        [json[@"ok"] boolValue] &&
                        [json[@"authorized"] isKindOfClass:[NSNumber class]] &&
                        [json[@"authorized"] boolValue] &&
                        [returnedId isEqualToNumber:optionId];
                    warn = accepted && [json[@"warnOnActivate"] isKindOfClass:[NSNumber class]] &&
                        [json[@"warnOnActivate"] boolValue];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(accepted, warn); });
        }];
        [task resume];
    }];
}

+ (void)clearSession {
    @synchronized(self) {
        xfSessionToken = nil;
        xfSessionExpiresAt = nil;
    }
}

+ (void)handleProtectedHTTPResponse:(NSURLResponse *)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSInteger status = http.statusCode;
    if (status != 401 && status != 403) return;
    // A failed restore request must NOT erase the credentials needed to retry.
    if ([http.URL.path isEqualToString:@"/api/app/originals"] ||
        [http.URL.path hasPrefix:@"/api/app/originals/"]) {
        @synchronized(self) {
            xfOriginalsCleanupToken = nil;
            xfCleanupTokenCachedUntil = nil;
        }
        return;
    }
    [self clearSession];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kXFLockNotification object:nil];
    });
}

+ (void)authorizeRestoreRequest:(NSMutableURLRequest *)request
                       completion:(void (^)(BOOL authorized))completion {
    NSString *cached = nil;
    @synchronized(self) {
        if (xfOriginalsCleanupToken.length > 0 &&
            [xfCleanupTokenCachedUntil timeIntervalSinceNow] > 30.0) {
            cached = [xfOriginalsCleanupToken copy];
        }
    }
    if (cached) {
        [request setValue:[@"Bearer " stringByAppendingString:cached] forHTTPHeaderField:@"Authorization"];
        if (completion) completion(YES);
        return;
    }
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiFilzaLicenseKey"];
    NSString *deviceId = [self deviceIdentifier];
    if (key.length == 0 || deviceId.length == 0) {
        if (completion) completion(NO);
        return;
    }
    NSURL *url = [NSURL URLWithString:@"https://xitforge-license-server.onrender.com/api/license/cleanup-token"];
    NSMutableURLRequest *tokenRequest = [NSMutableURLRequest requestWithURL:url];
    tokenRequest.HTTPMethod = @"POST";
    tokenRequest.timeoutInterval = 20.0;
    tokenRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [tokenRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    tokenRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"key": key, @"deviceId": deviceId}
                                                         options:0 error:nil];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:tokenRequest
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? (NSHTTPURLResponse *)response : nil;
        if (error || http.statusCode != 200 || data.length == 0) {
            if (completion) completion(NO);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *token = [json isKindOfClass:[NSDictionary class]] &&
            [json[@"cleanupToken"] isKindOfClass:[NSString class]] ? json[@"cleanupToken"] : nil;
        NSPredicate *pattern = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^xf2_[0-9a-f]{64}$"];
        if (!token || ![pattern evaluateWithObject:token]) {
            if (completion) completion(NO);
            return;
        }
        @synchronized(self) {
            xfOriginalsCleanupToken = [token copy];
            xfCleanupTokenCachedUntil = [NSDate dateWithTimeIntervalSinceNow:600];
        }
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        if (completion) completion(YES);
    }];
    [task resume];
}

+ (void)authorizeRequest:(NSMutableURLRequest *)request
              completion:(void (^)(BOOL authorized))completion {
    NSURL *url = request.URL;
    BOOL isBackend = [url.scheme.lowercaseString isEqualToString:@"https"] &&
        [url.host.lowercaseString isEqualToString:kXFHost] &&
        [url.path hasPrefix:@"/api/app/"];
    if (!isBackend) { if (completion) completion(NO); return; }
    BOOL isRestore = [url.path isEqualToString:@"/api/app/originals"] ||
        [url.path hasPrefix:@"/api/app/originals/"];
    if (isRestore) {
        [self authorizeRestoreRequest:request completion:completion];
        return;
    }
    NSString *token = nil;
    @synchronized(self) {
        if (xfSessionToken.length > 0 && [xfSessionExpiresAt timeIntervalSinceNow] > 30.0) {
            token = [xfSessionToken copy];
        }
    }
    if (token.length > 0) {
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        if (completion) completion(YES);
        return;
    }
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiFilzaLicenseKey"];
    if (key.length == 0) {
        [self clearSession];
        if (completion) completion(NO);
        [[NSNotificationCenter defaultCenter] postNotificationName:kXFLockNotification object:nil];
        return;
    }
    [self validateKey:key completion:^(BOOL valid, NSString *reason, NSString *expiresAt) {
        (void)reason; (void)expiresAt;
        NSString *fresh = nil;
        @synchronized(self) {
            if (valid && xfSessionToken.length > 0 && [xfSessionExpiresAt timeIntervalSinceNow] > 0) {
                fresh = [xfSessionToken copy];
            }
        }
        if (fresh.length > 0) {
            [request setValue:[@"Bearer " stringByAppendingString:fresh] forHTTPHeaderField:@"Authorization"];
            if (completion) completion(YES);
        } else {
            if (completion) completion(NO);
            [[NSNotificationCenter defaultCenter] postNotificationName:kXFLockNotification object:nil];
        }
    }];
}

@end
