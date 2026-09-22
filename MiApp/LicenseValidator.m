#import "LicenseValidator.h"
#import <UIKit/UIKit.h>

static NSString * const kLicenseAPIURL =
    @"https://xitforge-license-server.onrender.com/api/license/validate";

static NSString * const kLicenseAccessLevelDefaultsKey =
    @"XITForgeLicenseAccessLevel";

static NSString *xfSessionToken = nil;
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
                (NSHTTPURLResponse *)response;

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


+ (void)clearSession {
    @synchronized(self) {
        xfSessionToken = nil;
        xfSessionExpiresAt = nil;
    }
}

+ (void)handleProtectedHTTPResponse:(NSURLResponse *)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status == 401 || status == 403) {
        [self clearSession];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kXFLockNotification
                                                                object:nil];
        });
    }
}

+ (void)authorizeRequest:(NSMutableURLRequest *)request
              completion:(void (^)(BOOL authorized))completion {
    NSURL *url = request.URL;
    // Never leak the bearer token to arbitrary hosts / external file URLs.
    BOOL isBackend = [url.scheme.lowercaseString isEqualToString:@"https"] &&
        [url.host.lowercaseString isEqualToString:kXFHost] &&
        [url.path hasPrefix:@"/api/app/"];
    if (!isBackend) {
        if (completion) completion(NO);
        return;
    }
    NSString *token = nil;
    @synchronized(self) {
        if (xfSessionToken.length > 0 &&
            [xfSessionExpiresAt timeIntervalSinceNow] > 30.0) {
            token = [xfSessionToken copy];
        }
    }
    if (token.length > 0) {
        [request setValue:[@"Bearer " stringByAppendingString:token]
      forHTTPHeaderField:@"Authorization"];
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
            if (valid && xfSessionToken.length > 0 &&
                [xfSessionExpiresAt timeIntervalSinceNow] > 0) {
                fresh = [xfSessionToken copy];
            }
        }
        if (fresh.length > 0) {
            [request setValue:[@"Bearer " stringByAppendingString:fresh]
          forHTTPHeaderField:@"Authorization"];
            if (completion) completion(YES);
        } else {
            if (completion) completion(NO);
            [[NSNotificationCenter defaultCenter] postNotificationName:kXFLockNotification object:nil];
        }
    }];
}

@end
