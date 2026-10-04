#import <Foundation/Foundation.h>

// The experiment accepts only a generated marker, never arbitrary upload bytes.
static inline NSString *XFProbeUUID(NSString *path) {
    if (![path isKindOfClass:NSString.class]) return nil;
    NSString *name = path.lastPathComponent;
    NSString *prefix = @"xitforge_prueba_";
    if (![name hasPrefix:prefix] || ![name hasSuffix:@".txt"] || name.length != prefix.length + 36 + 4) return nil;
    NSString *token = [name substringWithRange:NSMakeRange(prefix.length, 36)];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:token];
    return [uuid.UUIDString.lowercaseString isEqualToString:token] ? token : nil;
}
static inline NSData *XFProbeContents(NSString *path) {
    NSString *token = XFProbeUUID(path);
    return token ? [[NSString stringWithFormat:@"Prueba XitForge\nIdentificador: %@\n", token] dataUsingEncoding:NSUTF8StringEncoding] : nil;
}
