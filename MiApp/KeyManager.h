#import <Foundation/Foundation.h>

@interface KeyManager : NSObject

+ (instancetype)sharedManager;
- (BOOL)isKeyValid;
- (void)validateKey:(NSString *)key completion:(void(^)(BOOL success, NSString *message))completion;
- (void)revokeKey;

@end
