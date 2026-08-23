#import "AppVersionChecker.h"

static NSString * const kAppVersionAPIURL =
    @"https://xitforge-license-server.onrender.com/api/app/version";

@implementation AppVersionChecker

+ (NSString *)normalizedVersion:(NSString *)rawVersion {

    NSString *trimmed =
        [[rawVersion ?: @""
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            copy];

    if (trimmed.length == 0) {
        return @"0.0.0";
    }

    NSArray<NSString *> *parts =
        [trimmed componentsSeparatedByString:@"."];

    NSMutableArray<NSString *> *normalized =
        [NSMutableArray arrayWithArray:parts];

    while (normalized.count < 3) {
        [normalized addObject:@"0"];
    }

    if (normalized.count > 3) {
        normalized =
            [NSMutableArray arrayWithArray:
                [normalized subarrayWithRange:NSMakeRange(0, 3)]];
    }

    for (NSString *part in normalized) {
        if (part.length == 0 ||
            [part rangeOfCharacterFromSet:
                [[NSCharacterSet decimalDigitCharacterSet]
                    invertedSet]].location != NSNotFound) {
            return @"0.0.0";
        }
    }

    return [normalized componentsJoinedByString:@"."];
}

+ (NSString *)currentVersion {

    NSString *raw =
        [[NSBundle mainBundle]
            objectForInfoDictionaryKey:
                @"CFBundleShortVersionString"];

    return [self normalizedVersion:raw];
}

+ (void)finish:(AppVersionCheckCompletion)completion
       success:(BOOL)success
       blocked:(BOOL)blocked
updateAvailable:(BOOL)updateAvailable
currentVersion:(NSString *)currentVersion
 latestVersion:(NSString *)latestVersion
minimumVersion:(NSString *)minimumVersion
       message:(NSString *)message
   downloadURL:(NSString *)downloadURL
  errorMessage:(NSString * _Nullable)errorMessage {

    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(
                success,
                blocked,
                updateAvailable,
                currentVersion ?: @"",
                latestVersion ?: @"",
                minimumVersion ?: @"",
                message ?: @"",
                downloadURL ?: @"",
                errorMessage
            );
        }
    });
}

+ (void)checkWithCompletion:(AppVersionCheckCompletion)completion {

    NSString *currentVersion =
        [self currentVersion];

    NSString *encoded =
        [currentVersion
            stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet URLQueryAllowedCharacterSet]];

    NSString *urlString =
        [NSString stringWithFormat:
            @"%@?current=%@",
            kAppVersionAPIURL,
            encoded ?: @""];

    NSURL *url =
        [NSURL URLWithString:urlString];

    if (!url) {
        [self finish:completion
             success:NO
             blocked:YES
     updateAvailable:NO
      currentVersion:currentVersion
       latestVersion:@""
      minimumVersion:@""
             message:@""
         downloadURL:@""
        errorMessage:@"No se pudo crear la URL de verificación."];
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"GET";
    request.timeoutInterval = 15.0;

    [request setValue:@"application/json"
        forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:
    ^(NSData * _Nullable data,
      NSURLResponse * _Nullable response,
      NSError * _Nullable error) {

        if (error) {
            [self finish:completion
                 success:NO
                 blocked:YES
         updateAvailable:NO
          currentVersion:currentVersion
           latestVersion:@""
          minimumVersion:@""
                 message:@""
             downloadURL:@""
            errorMessage:@"No se pudo conectar con el servidor para verificar la versión."];
            return;
        }

        NSHTTPURLResponse *http =
            (NSHTTPURLResponse *)response;

        if (![http isKindOfClass:[NSHTTPURLResponse class]] ||
            http.statusCode < 200 ||
            http.statusCode >= 300 ||
            data.length == 0) {

            NSString *errorText =
                [NSString stringWithFormat:
                    @"El servidor no pudo verificar esta versión (HTTP %ld).",
                    (long)http.statusCode];

            [self finish:completion
                 success:NO
                 blocked:YES
         updateAvailable:NO
          currentVersion:currentVersion
           latestVersion:@""
          minimumVersion:@""
                 message:@""
             downloadURL:@""
            errorMessage:errorText];
            return;
        }

        NSError *jsonError = nil;

        id object =
            [NSJSONSerialization JSONObjectWithData:data
                                           options:0
                                             error:&jsonError];

        if (jsonError ||
            ![object isKindOfClass:[NSDictionary class]]) {

            [self finish:completion
                 success:NO
                 blocked:YES
         updateAvailable:NO
          currentVersion:currentVersion
           latestVersion:@""
          minimumVersion:@""
                 message:@""
             downloadURL:@""
            errorMessage:@"El servidor devolvió una respuesta de versión inválida."];
            return;
        }

        NSDictionary *json =
            (NSDictionary *)object;

        if (![json[@"ok"] boolValue]) {

            NSString *serverError =
                [json[@"error"] isKindOfClass:[NSString class]]
                    ? json[@"error"]
                    : @"El servidor rechazó la verificación de versión.";

            [self finish:completion
                 success:NO
                 blocked:YES
         updateAvailable:NO
          currentVersion:currentVersion
           latestVersion:@""
          minimumVersion:@""
                 message:@""
             downloadURL:@""
            errorMessage:serverError];
            return;
        }

        id blockedValue = json[@"blocked"];
        id updateValue = json[@"updateAvailable"];

        if (![blockedValue isKindOfClass:[NSNumber class]] ||
            ![updateValue isKindOfClass:[NSNumber class]]) {

            [self finish:completion
                 success:NO
                 blocked:YES
         updateAvailable:NO
          currentVersion:currentVersion
           latestVersion:@""
          minimumVersion:@""
                 message:@""
             downloadURL:@""
            errorMessage:@"La API no devolvió el estado de actualización esperado."];
            return;
        }

        NSString *latest =
            [json[@"latestVersion"] isKindOfClass:[NSString class]]
                ? json[@"latestVersion"]
                : @"";

        NSString *minimum =
            [json[@"minimumVersion"] isKindOfClass:[NSString class]]
                ? json[@"minimumVersion"]
                : @"";

        NSString *message =
            [json[@"message"] isKindOfClass:[NSString class]]
                ? json[@"message"]
                : @"";

        NSString *downloadURL =
            [json[@"downloadUrl"] isKindOfClass:[NSString class]]
                ? json[@"downloadUrl"]
                : @"";

        [self finish:completion
             success:YES
             blocked:[blockedValue boolValue]
     updateAvailable:[updateValue boolValue]
      currentVersion:currentVersion
       latestVersion:latest
      minimumVersion:minimum
             message:message
         downloadURL:downloadURL
        errorMessage:nil];
    }];

    [task resume];
}

@end
