#import "LicenseValidator.h"

@implementation LicenseValidator

+ (NSArray *)validKeys {
    // Agrega aquí todas las claves válidas que quieras
    return @[
        @"XITF-ORGE-2024-KEY1",
        @"ABCD-1234-EFGH-5678",
        @"TEST-1234-ABCD-5678",
        @"DEMO-USER-2024-XXXX"
    ];
}

+ (BOOL)isValidKey:(NSString *)key {
    // Primero verifica el formato
    NSString *regex = @"^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$";
    NSPredicate *predicado = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
    if (![predicado evaluateWithObject:key]) {
        return NO;
    }
    
    // Luego verifica si está en la lista de claves válidas
    NSArray *validas = [self validKeys];
    return [validas containsObject:key];
}

@end
