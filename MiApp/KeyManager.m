#import "KeyManager.h"

static NSString *const kSavedKeyPref = @"SavedUserLicenseKey";

@implementation KeyManager

+ (instancetype)sharedManager {
    static KeyManager *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[KeyManager alloc] init];
    });
    return inst;
}

- (BOOL)isKeyValid {
    NSString *savedKey = [[NSUserDefaults standardUserDefaults] stringForKey:kSavedKeyPref];
    return savedKey != nil && savedKey.length == 19;
}

- (void)validateKey:(NSString *)key completion:(void(^)(BOOL success, NSString *message))completion {
    NSString *cleanKey = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSString *regexPattern = @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regexPattern];
    
    if (![predicate evaluateWithObject:cleanKey]) {
        completion(NO, @"Formato de clave inválido (Ej: XXXX-XXXX-XXXX-XXXX)");
        return;
    }
    
    // Simulación de validación o petición API
    // Para conectar a servidor, actualiza la URL correspondiente
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] setObject:cleanKey forKey:kSavedKeyPref];
        [[NSUserDefaults standardUserDefaults] synchronize];
        completion(YES, @"Licencia activada con éxito");
    });
}

- (void)revokeKey {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedKeyPref];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
