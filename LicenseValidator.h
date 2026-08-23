#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LicenseValidationCompletion)(BOOL valid,
                                             NSString * _Nullable reason,
                                             NSString * _Nullable expiresAt);

@interface LicenseValidator : NSObject

+ (void)validateKey:(NSString *)key
         completion:(LicenseValidationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
