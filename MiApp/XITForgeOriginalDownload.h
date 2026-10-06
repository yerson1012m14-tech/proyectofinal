#import <Foundation/Foundation.h>

// Original IDs belong to the originals table, independently of option IDs.
// Build the download on the same backend that authenticated the manifest;
// PUBLIC_BASE_URL must not change the server receiving the cleanup token.
static NSURL *XFPanelOriginalDownloadURL(NSDictionary *original, NSString *baseURL) {
    NSURLComponents *base=[NSURLComponents componentsWithString:baseURL];
    if(![base.scheme.lowercaseString isEqual:@"https"]||!base.host.length||base.user.length||base.password.length)return nil;
    NSString *identifier=nil;
    id rawID=original[@"id"];
    if([rawID isKindOfClass:NSNumber.class]||[rawID isKindOfClass:NSString.class])identifier=[rawID description];
    NSPredicate *digits=[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"^[1-9][0-9]*$"];
    if(!identifier||![digits evaluateWithObject:identifier]) {
        NSString *value=[original[@"originalFileUrl"] isKindOfClass:NSString.class]?original[@"originalFileUrl"]:nil;
        NSURLComponents *advertised=value?[NSURLComponents componentsWithString:value]:nil;
        NSArray *parts=advertised.path.pathComponents;
        if(parts.count!=6||![parts[1] isEqual:@"api"]||![parts[2] isEqual:@"app"]||
           ![parts[3] isEqual:@"originals"]||![parts[5] isEqual:@"file"]||
           ![digits evaluateWithObject:parts[4]])return nil;
        identifier=parts[4];
    }
    base.path=[NSString stringWithFormat:@"/api/app/originals/%@/file",identifier];
    base.query=nil;base.fragment=nil;
    return base.URL;
}
