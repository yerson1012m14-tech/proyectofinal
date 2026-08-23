#import <Foundation/Foundation.h>

extern NSString * const TranslationsLanguageDidChangeNotification;

@interface Translations : NSObject

+ (void)setLanguage:(NSInteger)language;
+ (NSInteger)currentLanguage;
+ (NSString *)tr:(NSString *)key;

@end
