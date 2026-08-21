#import "Translations.h"

static NSInteger currentLanguage = 0;

@implementation Translations

+ (void)setLanguage:(NSInteger)language {
    currentLanguage = language;
}

+ (NSInteger)currentLanguage {
    return currentLanguage;
}

+ (NSString *)tr:(NSString *)key {
    NSDictionary *translations = @{
        @"continue": @[@"CONTINUAR", @"CONTINUE", @"CONTINUAR"],
        @"incorrect": @[@"Incorrecta", @"Incorrect", @"Incorreta"],
        @"language": @[@"IDIOMA", @"LANGUAGE", @"IDIOMA"],
        @"select_language": @[@"Selecciona tu idioma", @"Select your language", @"Selecione seu idioma"],
        @"spanish": @[@"Español", @"Spanish", @"Espanhol"],
        @"english": @[@"English", @"English", @"Inglês"],
        @"portuguese": @[@"Português", @"Portuguese", @"Português"],
        @"settings": @[@"Configuración", @"Settings", @"Configurações"],
        @"protection": @[@"PROTECCIÓN PARA REVISIÓN", @"SCREEN PROTECTION", @"PROTEÇÃO DE TELA"],
        @"protection_desc": @[@"Ocultar contenido al grabar o capturar pantalla", @"Hide content when recording or capturing screen", @"Ocultar conteúdo ao gravar ou capturar tela"],
    };
    
    NSArray *texts = translations[key];
    if (texts && currentLanguage < texts.count) {
        return texts[currentLanguage];
    }
    return key;
}

@end
