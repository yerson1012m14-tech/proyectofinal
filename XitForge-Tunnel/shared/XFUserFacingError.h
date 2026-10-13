#import <Foundation/Foundation.h>

// Presentation only. Never change the operation result or authorization decision.
static inline NSString *XFUserFacingError(NSString *detail) {
    if(![detail isKindOfClass:NSString.class]||!detail.length)return @"No se pudo completar la operación. Vuelve a intentarlo.";
    NSString *value=detail.lowercaseString;
    if([value containsString:@"no tiene original ni regla"]||[value containsString:@"no tiene acciones de desactivación"]) {
        return @"Esta opción no está disponible para desactivar en este momento. Contacta soporte.";
    }
    if([value containsString:@"sin originales configurados"]) {
        return @"Esta opción no está disponible para desactivar en este momento. Contacta soporte.";
    }
    BOOL technical=NO;
    for(NSString *marker in @[@"filzaslop",@"filzaapply",@"streamingzip",@"posix",@"errno",@"excepción",@"excepcion",@"error interno",@"nsurlerrordomain",@"xitforge.airlift",@"delete-files",@"en el panel",@"panel devolvió",@"ssl",@"tls",@"json"])
        if([value containsString:marker]){technical=YES;break;}
    for(NSString *marker in @[@"connectionreset",@"connection reset",@"connection refused",@"stage=",@"internalerror",@"unexpectedresponse",@"exception",@"rppairing",@"remote pairing",@"lockdown",@"network extensions",@"packet-tunnel-provider",@"public_key",@"private_key",@"alt_irk",@"hostprivatekey",@"neconfigurationerrordomain",@"nevpnerrordomain",@"kcferrordomain",@"cfnetwork",@"/var/",@"0x",@"afc(",@"socket(",@"coredevice",@"rsd",@"airtraffic",@"grappa",@"servicenotfound",@"unknownerrortype",@"permdenied",@"invalidarg",@"networkunreachable",@"brokenpipe",@"channel closed",@"adapter closed",@"nscocoaerrordomain",@"nsposix",@"http ",@"error domain=",@"mha-c2",@"installationlookupfailed",@"filecomplete",@"datacomplete",@"books",@"documents/",@"library/",@"/private/",@"bundleid",@"com.dts.",@"timeout",@"timed out",@"atc:",@"atc ",@"airlift:",@"the operation couldn",@"the operation could not",@"error code"])
        if([value containsString:marker]){technical=YES;break;}
    NSRegularExpression *codes=[NSRegularExpression regularExpressionWithPattern:@"(c[oó]digo|code|error)\\s*[:=]?\\s*-?[0-9]+|\\(-?[0-9]+(?:/[0-9]+)?\\)|\\b(?:com|org|net)\\.[a-z0-9_.-]+|/(?:[^/\\s]+/)+" options:NSRegularExpressionCaseInsensitive error:NULL];
    if([codes firstMatchInString:detail options:0 range:NSMakeRange(0,detail.length)])technical=YES;
    if(!technical)return detail;
    if([value containsString:@"exception"]||[value containsString:@"excepción"]||[value containsString:@"excepcion"]||[value containsString:@"error interno"])
        return @"La operación se interrumpió. Cierra y vuelve a abrir XITFORGE antes de intentarlo de nuevo.";
    if([value containsString:@"permdenied"]||[value containsString:@"deneg"]||[value containsString:@"permission"])
        return @"El iPhone no permitió acceder a este archivo. Cierra la app de destino, comprueba el túnel y vuelve a intentarlo.";
    if([value containsString:@"no recibió un permiso"]||[value containsString:@"servicenotfound"]||[value containsString:@"no anunció"])
        return @"Esta conexión no ofrece el acceso necesario. Reconecta el túnel y vuelve a intentarlo.";
    if([value containsString:@"connectionreset"]||[value containsString:@"connection reset"]||[value containsString:@"connection refused"]||[value containsString:@"networkunreachable"]||[value containsString:@"brokenpipe"]||[value containsString:@"channel closed"]||[value containsString:@"adapter closed"]||[value containsString:@"timeout"]||[value containsString:@"timed out"])
        return @"La conexión se interrumpió. Comprueba el Wi-Fi y vuelve a conectar el túnel.";
    if([value containsString:@"installationlookupfailed"])
        return @"No se pudo acceder a la app de destino. Comprueba que esté instalada y que hayas seleccionado la app correcta.";
    if([value containsString:@"invalidarg"])
        return @"No se pudo aplicar esta opción. Contacta soporte para revisar su configuración.";
    if([value containsString:@"grappa"])
        return @"El emparejamiento no permitió esta operación. Importa uno válido de este iPhone y vuelve a conectar.";
    if([value containsString:@"http 401"]||[value containsString:@"http 403"])
        return @"No se pudo autorizar esta operación. Vuelve a intentarlo. Si continúa, contacta soporte.";
    if([value containsString:@"http 404"])
        return @"El archivo de esta opción no está disponible. Contacta soporte.";
    if([value containsString:@"http "])
        return @"No se pudo descargar el archivo. Comprueba tu conexión y vuelve a intentarlo.";
    if([value containsString:@"pendiente"]||[value containsString:@"recuper"])
        return @"La operación anterior no se completó. Revisa el estado del túnel antes de volver a intentarlo.";
    return @"No se pudo completar la operación. Vuelve a intentarlo. Si continúa, contacta soporte.";
}
