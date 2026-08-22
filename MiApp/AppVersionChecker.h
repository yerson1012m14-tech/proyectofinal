#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AppVersionCheckCompletion)(
    BOOL success,
    BOOL blocked,
    BOOL updateAvailable,
    NSString *currentVersion,
    NSString *latestVersion,
    NSString *minimumVersion,
    NSString *message,
    NSString *downloadURL,
    NSString * _Nullable errorMessage
);

@interface AppVersionChecker : NSObject

+ (NSString *)currentVersion;

+ (void)checkWithCompletion:(AppVersionCheckCompletion)completion;

@end

NS_ASSUME_NONNULL_END
