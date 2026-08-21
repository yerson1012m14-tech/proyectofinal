#import "LicenseValidator.h"
#import <UIKit/UIKit.h>

static NSString * const kLicenseAPIURL =
    @"https://xitforge-license-server.onrender.com/api/license/validate";

@implementation LicenseValidator

+ (BOOL)isValidFormat:(NSString *)key {

    NSString *regex =
        @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";

    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];

    return [predicate evaluateWithObject:key];
}

+ (NSString *)deviceIdentifier {

    NSUUID *identifier =
        [UIDevice currentDevice].identifierForVendor;

    if (identifier.UUIDString.length > 0) {
        return identifier.UUIDString;
    }

    return @"unknown-device";
}

+ (void)validateKey:(NSString *)key
         completion:(LicenseValidationCompletion)completion {

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

    NSDictionary *payload = @{
        @"key": normalizedKey,
        @"deviceId": deviceID
    };

    NSError *jsonError = nil;

    NSData *jsonData =
        [NSJSONSerialization dataWithJSONObject:payload
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
                    completion(NO, @"network_error", nil);
                }

                return;
            }

            if (!data) {

                if (completion) {
                    completion(NO, @"empty_response", nil);
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
                ![object isKindOfClass:[NSDictionary class]]) {

                if (completion) {
                    completion(NO, @"invalid_response", nil);
                }

                return;
            }

            NSDictionary *json =
                (NSDictionary *)object;

            BOOL valid =
                [json[@"valid"] boolValue];

            NSString *reason =
                [json[@"reason"] isKindOfClass:[NSString class]]
                    ? json[@"reason"]
                    : nil;

            NSString *expiresAt =
                [json[@"expiresAt"] isKindOfClass:[NSString class]]
                    ? json[@"expiresAt"]
                    : nil;

            if (completion) {
                completion(valid, reason, expiresAt);
            }
        });
    }];

    [task resume];
}

@end
