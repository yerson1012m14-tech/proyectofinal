#import <Foundation/Foundation.h>

@interface Translations : NSObject

+ (NSString *)tr:(NSString *)key;
+ (void)setLanguage:(NSInteger)language;
+ (NSInteger)currentLanguage;

@end
