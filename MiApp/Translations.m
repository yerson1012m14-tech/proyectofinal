#import "Translations.h"

NSString * const TranslationsLanguageDidChangeNotification =
    @"TranslationsLanguageDidChangeNotification";

static NSInteger currentLanguage = 0;

@implementation Translations

+ (void)setLanguage:(NSInteger)language {

    if (language < 0 || language > 2) {
        language = 0;
    }

    currentLanguage = language;

    [[NSNotificationCenter defaultCenter]
        postNotificationName:
            TranslationsLanguageDidChangeNotification
        object:nil
        userInfo:@{
            @"language": @(currentLanguage)
        }];
}

+ (NSInteger)currentLanguage {
    return currentLanguage;
}

+ (NSString *)tr:(NSString *)key {

    static NSDictionary *translations = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{

        translations = @{
            @"continue":
                @[
                    @"CONTINUAR",
                    @"CONTINUE",
                    @"CONTINUAR"
                ],

            @"incorrect":
                @[
                    @"Incorrecta",
                    @"Incorrect",
                    @"Incorreta"
                ],

            @"language":
                @[
                    @"IDIOMA",
                    @"LANGUAGE",
                    @"IDIOMA"
                ],

            @"select_language":
                @[
                    @"Selecciona tu idioma",
                    @"Select your language",
                    @"Selecione seu idioma"
                ],

            @"spanish":
                @[
                    @"Español",
                    @"Spanish",
                    @"Espanhol"
                ],

            @"english":
                @[
                    @"English",
                    @"English",
                    @"Inglês"
                ],

            @"portuguese":
                @[
                    @"Português",
                    @"Portuguese",
                    @"Português"
                ],

            @"settings":
                @[
                    @"Configuración",
                    @"Settings",
                    @"Configurações"
                ],

            @"protection":
                @[
                    @"PROTECCIÓN PARA REVISIÓN",
                    @"SCREEN PROTECTION",
                    @"PROTEÇÃO DE TELA"
                ],

            @"protection_desc":
                @[
                    @"Ocultar contenido al grabar o capturar pantalla",
                    @"Hide content when recording or capturing screen",
                    @"Ocultar conteúdo ao gravar ou capturar tela"
                ],

            @"license":
                @[
                    @"LICENCIA",
                    @"LICENSE",
                    @"LICENÇA"
                ],

            @"license_active":
                @[
                    @"LICENCIA ACTIVA",
                    @"LICENSE ACTIVE",
                    @"LICENÇA ATIVA"
                ],

            @"license_expired":
                @[
                    @"LICENCIA EXPIRADA",
                    @"LICENSE EXPIRED",
                    @"LICENÇA EXPIRADA"
                ],

            @"no_expiration":
                @[
                    @"SIN VENCIMIENTO",
                    @"NO EXPIRATION",
                    @"SEM VENCIMENTO"
                ],

            @"expires":
                @[
                    @"Vence",
                    @"Expires",
                    @"Vence"
                ],

            @"preferences":
                @[
                    @"PREFERENCIAS",
                    @"PREFERENCES",
                    @"PREFERÊNCIAS"
                ],

            @"information":
                @[
                    @"INFORMACIÓN",
                    @"INFORMATION",
                    @"INFORMAÇÕES"
                ],

            @"app_version":
                @[
                    @"Versión de la App",
                    @"App Version",
                    @"Versão do App"
                ],

            @"active":
                @[
                    @"Activa",
                    @"Active",
                    @"Ativa"
                ],

            @"inactive":
                @[
                    @"Desactivado",
                    @"Disabled",
                    @"Desativado"
                ],

            @"enabled":
                @[
                    @"Activado",
                    @"Enabled",
                    @"Ativado"
                ],

            @"cancel":
                @[
                    @"Cancelar",
                    @"Cancel",
                    @"Cancelar"
                ],

            @"select":
                @[
                    @"Seleccionar",
                    @"Select",
                    @"Selecionar"
                ]
        };
    });

    NSArray *texts =
        translations[key];

    if (texts &&
        currentLanguage >= 0 &&
        currentLanguage < texts.count) {

        return texts[currentLanguage];
    }

    return key;
}

@end
