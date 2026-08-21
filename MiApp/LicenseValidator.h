#import <Foundation/Foundation.h>

@interface LicenseValidator : NSObject

+ (BOOL)isValidKey:(NSString *)key;
+ (NSArray *)validKeys;

@end
