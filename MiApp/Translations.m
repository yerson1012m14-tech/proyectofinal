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
        // LicenseViewController
        @"continue": @[@"CONTINUAR", @"CONTINUE", @"CONTINUAR"],
        @"invalid_key": @[@"Clave no válida", @"Invalid key", @"Chave inválida"],
        @"key_format": @[@"Ingresa una clave con el formato XXXX-XXXX-XXXX-XXXX.", @"Enter a key with the format XXXX-XXXX-XXXX-XXXX.", @"Insira uma chave com o formato XXXX-XXXX-XXXX-XXXX."],
        @"retry": @[@"Reintentar", @"Retry", @"Tentar novamente"],
        
        // SettingsViewController
        @"settings": @[@"Configuración", @"Settings", @"Configurações"],
        @"language": @[@"IDIOMA", @"LANGUAGE", @"IDIOMA"],
        @"select_language": @[@"Selecciona tu idioma", @"Select your language", @"Selecione seu idioma"],
        @"spanish": @[@"Español", @"Spanish", @"Espanhol"],
        @"english": @[@"English", @"English", @"Inglês"],
        @"portuguese": @[@"Português", @"Portuguese", @"Português"],
        @"protection": @[@"PROTECCIÓN PARA REVISIÓN", @"SCREEN PROTECTION", @"PROTEÇÃO DE TELA"],
        @"protection_desc": @[@"Ocultar contenido al grabar o capturar pantalla", @"Hide content when recording or capturing screen", @"Ocultar conteúdo ao gravar ou capturar tela"],
        @"protection_detail": @[@"Cuando esta opción esté activada, la pantalla se volverá negra al detectar una captura o grabación.", @"When this option is enabled, the screen will turn black when detecting a capture or recording.", @"Quando esta opção estiver ativada, a tela ficará preta ao detectar uma captura ou gravação."],
    };
    
    NSArray *texts = translations[key];
    if (texts && currentLanguage < texts.count) {
        return texts[currentLanguage];
    }
    return key;
}

@end
