#import "Translations.h"

static NSInteger currentLanguage = 0;

@implementation Translations

+ (void)setLanguage:(NSInteger)language {
    currentLanguage = language;
}

+ (NSString *)tr:(NSString *)key {
    NSDictionary *translations = @{
        @"continue": @[@"CONTINUAR", @"CONTINUE", @"CONTINUAR"],
        @"invalid_key": @[@"Clave no válida", @"Invalid key", @"Chave inválida"],
        @"retry": @[@"Reintentar", @"Retry", @"Tentar novamente"],
        @"key_format": @[@"Ingresa una clave con el formato XXXX-XXXX-XXXX-XXXX.", @"Enter a key with the format XXXX-XXXX-XXXX-XXXX.", @"Insira uma chave com o formato XXXX-XXXX-XXXX-XXXX."]
    };
    
    NSArray *texts = translations[key];
    if (texts && currentLanguage < texts.count) {
        return texts[currentLanguage];
    }
    return key;
}

@end
