#import <Foundation/Foundation.h>

// Presentation only. Never change the operation result or authorization decision.
static inline NSString *XFUserFacingError(NSString *detail) {
    if(![detail isKindOfClass:NSString.class]||!detail.length)return @"No se pudo completar la operación. Vuelve a intentarlo.";
    NSString *value=detail.lowercaseString;
    if([value containsString:@"no tiene original ni regla"]||[value containsString:@"no tiene acciones de desactivación"]) {
        return @"Revisa en el panel que esta opción tenga un original o una regla de borrado configurados para el mismo juego, carpeta y archivo.";
    }
    BOOL technical=NO;
    for(NSString *marker in @[@"afc(",@"socket(",@"coredevice",@"rsd",@"airtraffic",@"grappa",@"servicenotfound",@"unknownerrortype",@"permdenied",@"invalidarg",@"networkunreachable",@"brokenpipe",@"channel closed",@"adapter closed",@"nscocoaerrordomain",@"nsposix",@"http ",@"error domain=",@"mha-c2",@"installationlookupfailed",@"filecomplete",@"datacomplete",@"books",@"documents/",@"library/",@"/private/",@"bundleid",@"com.dts.",@"timeout",@"timed out",@"atc:",@"atc ",@"airlift:",@"the operation couldn",@"the operation could not",@"error code"])
        if([value containsString:marker]){technical=YES;break;}
    NSRegularExpression *codes=[NSRegularExpression regularExpressionWithPattern:@"(c[oó]digo|code|error)\\s*[:=]?\\s*-?[0-9]+|\\([0-9]+/[0-9]+\\)" options:NSRegularExpressionCaseInsensitive error:NULL];
    if([codes firstMatchInString:detail options:0 range:NSMakeRange(0,detail.length)])technical=YES;
    if(!technical)return detail;
    if([value containsString:@"permdenied"]||[value containsString:@"deneg"]||[value containsString:@"permission"])
        return @"El iPhone no permitió acceder a este archivo. Cierra la app de destino, comprueba el túnel y vuelve a intentarlo.";
    if([value containsString:@"no recibió un permiso"]||[value containsString:@"servicenotfound"]||[value containsString:@"no anunció"])
        return @"Esta conexión no ofrece el acceso necesario. Reconecta el túnel y vuelve a intentarlo.";
    if([value containsString:@"networkunreachable"]||[value containsString:@"brokenpipe"]||[value containsString:@"channel closed"]||[value containsString:@"adapter closed"]||[value containsString:@"timeout"]||[value containsString:@"timed out"])
        return @"Se interrumpió la conexión. Comprueba el Wi-Fi y LocalDevVPN, reconecta el túnel y vuelve a intentarlo.";
    if([value containsString:@"installationlookupfailed"])
        return @"No se pudo acceder a la app de destino. Comprueba que esté instalada y que hayas seleccionado la app correcta.";
    if([value containsString:@"invalidarg"])
        return @"No se pudo usar el destino configurado. Revisa la carpeta y el nombre del archivo en el panel.";
    if([value containsString:@"http 401"]||[value containsString:@"http 403"]||[value containsString:@"grappa"])
        return @"No se pudo autorizar la operación. Comprueba tu licencia y el emparejamiento del iPhone.";
    if([value containsString:@"http 404"])
        return @"El archivo ya no está disponible en el panel. Revisa su configuración y vuelve a cargarlo si hace falta.";
    if([value containsString:@"http "])
        return @"El panel no pudo entregar el archivo. Comprueba tu conexión y vuelve a intentarlo.";
    if([value containsString:@"pendiente"]||[value containsString:@"recuper"])
        return @"La operación anterior no se completó. Revisa el estado del túnel antes de volver a intentarlo.";
    return @"No se pudo completar la operación. Revisa la conexión y la configuración de esta opción antes de volver a intentarlo.";
}
