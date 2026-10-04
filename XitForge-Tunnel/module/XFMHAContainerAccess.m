#import "XFMHAContainerAccess.h"
#import "XFContainerGrant.h"
#import <arpa/inet.h>
#import <dlfcn.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

/* Independent glue around ContainerManager interfaces. No 3105 source is incorporated.
   Only query/activation and read-only POSIX operations are used. */
static NSError *XFMHAError(NSInteger code,NSString *text) {
    return [NSError errorWithDomain:@"XitForge.MHA" code:code userInfo:@{NSLocalizedDescriptionKey:text}];
}
static NSError *XFMHAPOSIX(NSString *action,int code) {
    NSMutableDictionary *info=[@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@: %s (errno %d).",action,strerror(code),code]} mutableCopy];
    if(code>0)info[@"NativePOSIXError"]=@(code);
    return [NSError errorWithDomain:@"XitForge.MHA" code:code userInfo:info];
}
typedef struct {
    void *library;
    void *(*newQuery)(void);
    void (*queryClass)(void *,uint64_t);
    void (*queryIdentifiers)(void *,void *);
    void (*queryGroups)(void *,void *);
    void (*queryFlags)(void *,uint64_t);
    void (*queryPart)(void *,uint64_t);
    void (*queryPartDomain)(void *,const char *);
    void *(*queryResult)(void *);
    void *(*queryError)(void *);
    void (*freeQuery)(void *);
    const char *(*path)(void *);
    void *(*copyObject)(void *);
    char *(*copyToken)(void *);
    bool (*activate)(void *,bool);
    void (*freeObject)(void *);
    int (*posixError)(void *);
    const char *(*errorMessage)(void *);
    void *(*xpcString)(const char *);
    void (*xpcRelease)(void *);
    int64_t (*consumeExtension)(const char *);
    int (*releaseExtension)(int64_t);
} XFMHAAPI;
static XFMHAAPI *XFMHANative(void) {
    static XFMHAAPI api;static dispatch_once_t once;
    dispatch_once(&once,^{
        api.library=dlopen("/usr/lib/system/libsystem_containermanager.dylib",RTLD_NOW|RTLD_LOCAL);
        if(!api.library)return;
#define XF_MHA_BIND(field,name) api.field=(__typeof(api.field))dlsym(api.library,name)
        XF_MHA_BIND(newQuery,"container_query_create");
        XF_MHA_BIND(queryClass,"container_query_set_class");
        XF_MHA_BIND(queryIdentifiers,"container_query_set_identifiers");
        XF_MHA_BIND(queryGroups,"container_query_set_group_identifiers");
        XF_MHA_BIND(queryFlags,"container_query_operation_set_flags");
        XF_MHA_BIND(queryPart,"container_query_operation_set_part");
        XF_MHA_BIND(queryPartDomain,"container_query_operation_set_part_domain");
        XF_MHA_BIND(queryResult,"container_query_get_single_result");
        XF_MHA_BIND(queryError,"container_query_get_last_error");
        XF_MHA_BIND(freeQuery,"container_query_free");
        XF_MHA_BIND(path,"container_object_get_path");
        XF_MHA_BIND(copyObject,"container_object_copy");
        XF_MHA_BIND(copyToken,"container_copy_sandbox_token");
        XF_MHA_BIND(activate,"container_object_sandbox_extension_activate");
        XF_MHA_BIND(freeObject,"container_object_free");
        XF_MHA_BIND(posixError,"container_error_get_posix_errno");
        XF_MHA_BIND(errorMessage,"container_error_get_message");
#undef XF_MHA_BIND
        api.xpcString=(__typeof(api.xpcString))dlsym(RTLD_DEFAULT,"xpc_string_create");
        api.xpcRelease=(__typeof(api.xpcRelease))dlsym(RTLD_DEFAULT,"xpc_release");
        api.consumeExtension=(__typeof(api.consumeExtension))dlsym(RTLD_DEFAULT,"sandbox_extension_consume");
        api.releaseExtension=(__typeof(api.releaseExtension))dlsym(RTLD_DEFAULT,"sandbox_extension_release");
    });return &api;
}
/* Only fixed stage names and a numeric native errno enter diagnostics. */
static NSError *XFMHAStageError(NSInteger code,NSString *stage,NSString *text,XFMHAAPI *api,void *query) {
    NSMutableDictionary *info=[@{NSLocalizedDescriptionKey:text,@"MHAStage":stage} mutableCopy];
    void *native=query&&api->queryError?api->queryError(query):NULL;
    int posix=native&&api->posixError?api->posixError(native):0;
    if(posix>0)info[@"NativePOSIXError"]=@(posix);
    return [NSError errorWithDomain:@"XitForge.MHA" code:code userInfo:info];
}
static BOOL XFMHAIdentifier(NSString *identifier) {
    if(![identifier isKindOfClass:NSString.class]||!identifier.length||identifier.length>255)return NO;
    if([identifier isEqual:@"."]||[identifier isEqual:@".."])return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    return [identifier rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
static BOOL XFMHAComponent(NSString *component) {
    if(!component.length||[component isEqual:@"."]||[component isEqual:@".."]||[component containsString:@"/"]||[component containsString:@"\\"])return NO;
    NSString *nul=[NSString stringWithFormat:@"%C",(unichar)0];
    return [component rangeOfString:nul].location==NSNotFound;
}
static NSArray<NSString *> *XFMHARelative(NSString *path,BOOL file,NSError **error) {
    if(![path isKindOfClass:NSString.class]||path.length>4096||[path hasPrefix:@"/"]||[path hasSuffix:@"/"]){if(error)*error=XFMHAError(3001,@"La ruta debe ser relativa al contenedor de la app.");return nil;}
    if(!path.length){if(file){if(error)*error=XFMHAError(3002,@"Selecciona un archivo dentro del contenedor.");return nil;}return @[];}
    NSArray *parts=[path componentsSeparatedByString:@"/"];
    if(parts.count>128){if(error)*error=XFMHAError(3003,@"La ruta contiene demasiadas carpetas.");return nil;}
    for(NSString *part in parts)if(!XFMHAComponent(part)){if(error)*error=XFMHAError(3004,@"La ruta contiene un componente que no se puede abrir con seguridad.");return nil;}
    return parts;
}
static NSString *XFMHARoot(NSString *raw,BOOL group) {
    if(![raw isKindOfClass:NSString.class])return nil;
    if([raw hasPrefix:@"/var/"])raw=[@"/private" stringByAppendingString:raw];
    NSString *prefix=group?@"/private/var/mobile/Containers/Shared/AppGroup/":@"/private/var/mobile/Containers/Data/Application/";
    if(![raw hasPrefix:prefix])return nil;
    NSString *uuid=[raw substringFromIndex:prefix.length];
    if(!uuid.length||[uuid containsString:@"/"]||![[NSUUID alloc] initWithUUIDString:uuid])return nil;
    return raw;
}
@interface XFMHAContainerAccess () {
    void *_query;
    void *_object;
    int _rootFD;
    int64_t _extensionHandle;
}
@property (nonatomic, readwrite, copy) NSString *rootPath;
@property (nonatomic, readwrite, copy) NSString *bundleID;
@property (nonatomic, readwrite, copy) NSString *accessMethod;
@property (nonatomic, readwrite, getter=isGroup) BOOL group;
@end
@implementation XFMHAContainerAccess
- (instancetype)init {if((self=[super init])){_rootFD=-1;_extensionHandle=-1;_accessMethod=@"MHA-C2";}return self;}
+ (NSString *)kernelBuild {
    char build[64]={0};size_t length=sizeof(build);
    if(sysctlbyname("kern.osversion",build,&length,NULL,0)!=0||!length||length>sizeof(build)||build[length-1]!=0)return @"";
    return [NSString stringWithUTF8String:build]?:@"";
}
+ (BOOL)alternateAccessSupported {
    NSString *build=[self kernelBuild];
    return XFContainerGrantBuildSupported(build.UTF8String,[build lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}
- (BOOL)openValidatedRootWithError:(NSError **)error {
    _rootFD=open(self.rootPath.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
    if(_rootFD<0){if(error)*error=XFMHAPOSIX(@"Abrir el contenedor autorizado",errno);return NO;}
    struct stat root;
    int result=fstat(_rootFD,&root);int failure=errno;
    if(result!=0||!S_ISDIR(root.st_mode)){
        close(_rootFD);_rootFD=-1;
        if(error)*error=result!=0?XFMHAPOSIX(@"Comprobar el contenedor autorizado",failure):XFMHAError(3016,@"La raíz autorizada no es un directorio.");
        return NO;
    }
    return YES;
}
- (BOOL)tryAlternateGrantAfterError:(NSError *)original error:(NSError **)error {
    if(![self.class alternateAccessSupported]){if(error)*error=original;return NO;}
    XFMHAAPI *api=XFMHANative();
    XFContainerGrantAPI grant={
        .newQuery=api->newQuery,.queryClass=api->queryClass,.queryGroups=api->queryGroups,
        .queryFlags=api->queryFlags,.queryPart=api->queryPart,.queryPartDomain=api->queryPartDomain,
        .queryResult=api->queryResult,.freeQuery=api->freeQuery,.copyToken=api->copyToken,
        .xpcString=api->xpcString,.xpcRelease=api->xpcRelease,
        .consume=api->consumeExtension,.release=api->releaseExtension,.allocate=malloc,.freeBytes=free
    };
    XFContainerGrantStage stage;
    _extensionHandle=XFContainerGrantAcquire(&grant,self.rootPath.fileSystemRepresentation,&stage);
    if(_extensionHandle>=0){self.accessMethod=@"BadQuery";return YES;}
    NSArray *stages=@[@"success",@"invalid_input",@"missing_api",@"allocation",@"query_result",@"sandbox_token",@"sandbox_consume"];
    NSMutableDictionary *info=[original.userInfo mutableCopy]?:[NSMutableDictionary new];
    info[@"BadQueryStage"]=stages[(NSUInteger)stage];
    info[@"MHAErrorCode"]=@(original.code);
    info[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"%@\n\nEl acceso alternativo de esta beta tampoco concedió el permiso para leer el contenedor (etapa %@).",original.localizedDescription,stages[(NSUInteger)stage]];
    if(error)*error=[NSError errorWithDomain:@"XitForge.MHA" code:3030+stage userInfo:info];
    return NO;
}
+ (NSString *)signedProcessIdentifier:(NSError **)error {
    int (*identity)(pid_t,unsigned int,void *,size_t)=(__typeof(identity))dlsym(RTLD_DEFAULT,"csops");
    if(!identity){if(error)*error=XFMHAError(3005,@"No se puede consultar la identidad de la firma de este proceso.");return nil;}
    uint8_t header[8]={0};errno=0;
    int result=identity(getpid(),11,header,sizeof(header));int failure=errno;
    if(result!=0&&failure!=ERANGE){if(error)*error=XFMHAPOSIX(@"Comprobar la firma de XitForge",failure);return nil;}
    uint32_t encoded=0;memcpy(&encoded,header+4,4);uint32_t length=ntohl(encoded);
    if(length<=8||length>4096){if(error)*error=XFMHAError(3006,@"La firma no devolvió una identidad válida.");return nil;}
    NSMutableData *blob=[NSMutableData dataWithLength:length];
    if(identity(getpid(),11,blob.mutableBytes,blob.length)!=0){if(error)*error=XFMHAPOSIX(@"Leer la identidad de la firma",errno);return nil;}
    uint8_t *bytes=blob.mutableBytes;memcpy(&encoded,bytes+4,4);uint32_t actual=ntohl(encoded);
    if(actual!=length||bytes[actual-1]!=0||!memchr(bytes+8,0,actual-8)){if(error)*error=XFMHAError(3007,@"La identidad de la firma está incompleta.");return nil;}
    size_t textLength=strnlen((char *)bytes+8,actual-8);
    return [[NSString alloc] initWithBytes:bytes+8 length:textLength encoding:NSUTF8StringEncoding];
}
+ (instancetype)leaseForBundleID:(NSString *)bundleID group:(BOOL)group error:(NSError **)error {
    if(!XFMHAIdentifier(bundleID)){if(error)*error=XFMHAError(3008,@"El identificador de la app no es válido.");return nil;}
    if(![self availableWithError:error])return nil;
    XFMHAAPI *api=XFMHANative();
    if(group&&!api->queryGroups){
        if(error)*error=XFMHAError(3010,@"Las funciones nativas de ContainerManager no están disponibles en este iOS.");return nil;
    }
    XFMHAContainerAccess *lease=[self new];lease.bundleID=bundleID;lease.group=group;
    lease->_query=api->newQuery();
    if(!lease->_query){if(error)*error=XFMHAError(3011,@"ContainerManager no pudo preparar la consulta.");return nil;}
    api->queryClass(lease->_query,group?7:2);
    void *identifier=api->xpcString(bundleID.UTF8String);
    if(!identifier){if(error)*error=XFMHAError(3012,@"No se pudo preparar el identificador de la app.");return nil;}
    if(group)api->queryGroups(lease->_query,identifier);else api->queryIdentifiers(lease->_query,identifier);
    api->xpcRelease(identifier);
    /* Query an existing container and request its sandbox extension; no create operation. */
    api->queryFlags(lease->_query,UINT64_C(0x900000000));
    if(api->queryPart)api->queryPart(lease->_query,0);
    void *borrowed=api->queryResult(lease->_query);
    if(!borrowed){
        if(error)*error=XFMHAStageError(3013,@"query_result",@"MHA-C2 no devolvió el contenedor de esta app.",api,lease->_query);return nil;
    }
    const char *raw=api->path(borrowed);
    lease.rootPath=raw?XFMHARoot([NSString stringWithUTF8String:raw],group):nil;
    if(!lease.rootPath){if(error)*error=XFMHAError(3014,@"ContainerManager devolvió una ruta fuera del contenedor esperado.");return nil;}
    // The base app can already hold a valid lease. Check actual read-only
    // access before demanding that a second query issue a new sandbox token.
    if([lease openValidatedRootWithError:NULL]){lease.accessMethod=@"ExistingAccess";return lease;}
    // 3105 obtains a second query result for activation. Verify the root is
    // unchanged before using that borrowed object as the permission source.
    borrowed=api->queryResult(lease->_query);
    const char *activationRoot=borrowed?api->path(borrowed):NULL;
    NSString *checkedRoot=activationRoot?XFMHARoot([NSString stringWithUTF8String:activationRoot],group):nil;
    if(borrowed&&(!checkedRoot||![checkedRoot isEqualToString:lease.rootPath])){if(error)*error=XFMHAError(3023,@"El contenedor cambió durante la consulta del permiso. Vuelve a abrir la app.");return nil;}
    lease->_object=borrowed?api->copyObject(borrowed):NULL;
    NSError *permissionFailure=nil;
    if(!borrowed)permissionFailure=XFMHAStageError(3013,@"query_result",@"MHA-C2 no devolvió un objeto de permiso para el contenedor consultado.",api,lease->_query);
    else if(!lease->_object)permissionFailure=XFMHAStageError(3015,@"object_copy",@"MHA-C2 no pudo preparar el permiso de este contenedor.",api,lease->_query);
    else {
        char *token=api->copyToken(lease->_object);
        BOOL present=token&&token[0];free(token);
        if(!present)permissionFailure=XFMHAStageError(3021,@"sandbox_token",@"MHA-C2 no recibió un permiso utilizable para leer este contenedor.",api,lease->_query);
        else if(!api->activate(lease->_object,false))permissionFailure=XFMHAStageError(3022,@"sandbox_activate",@"El iPhone rechazó activar el permiso para leer este contenedor mediante MHA-C2.",api,lease->_query);
    }
    if(permissionFailure){
        // An activation return value alone does not determine OS access.
        if([lease openValidatedRootWithError:NULL]){lease.accessMethod=@"ExistingAccess";return lease;}
        if(![lease tryAlternateGrantAfterError:permissionFailure error:error])return nil;
    }
    NSError *openFailure=nil;
    if(![lease openValidatedRootWithError:&openFailure]){
        // 3105 also falls back when activation returned true but the actual
        // directory open remained denied. Never acquire a second owned handle.
        if(lease->_extensionHandle<0&&(openFailure.code==EACCES||openFailure.code==EPERM)&&[self alternateAccessSupported]){
            if(![lease tryAlternateGrantAfterError:openFailure error:error])return nil;
            if(![lease openValidatedRootWithError:error])return nil;
        }else{if(error)*error=openFailure;return nil;}
    }
    return lease;
}
+ (BOOL)availableWithError:(NSError **)error {
    NSString *signedID=[self signedProcessIdentifier:error];
    if(!signedID)return NO;
    if(![signedID isEqual:@"com.apple.mobile.MobileHouseArrest"]){if(error)*error=XFMHAError(3009,@"La firma cambió el identificador de XitForge. Para acceder mediante MHA-C2 debe conservar com.apple.mobile.MobileHouseArrest.");return NO;}
    XFMHAAPI *api=XFMHANative();
    if(!api->newQuery||!api->queryClass||!api->queryIdentifiers||!api->queryFlags||!api->queryResult||!api->freeQuery||!api->path||!api->copyObject||!api->copyToken||!api->activate||!api->freeObject||!api->xpcString||!api->xpcRelease){if(error)*error=XFMHAError(3010,@"Las funciones nativas de ContainerManager no están disponibles en este iOS.");return NO;}
    return YES;
}
- (int)openRelative:(NSArray<NSString *> *)parts directory:(BOOL)directory error:(NSError **)error {
    if(_rootFD<0){if(error)*error=XFMHAError(3017,@"El permiso de este contenedor ya se cerró.");return -1;}
    /* A fresh open description prevents readdir from sharing the root's directory offset. */
    int cursor=openat(_rootFD,".",O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
    if(cursor<0){if(error)*error=XFMHAPOSIX(@"Preparar la lectura del contenedor",errno);return -1;}
    for(NSUInteger i=0;i<parts.count;i++) {
        BOOL folder=directory||i+1<parts.count;
        int flags=O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK|(folder?O_DIRECTORY:0);
        int next=openat(cursor,parts[i].fileSystemRepresentation,flags);int failure=errno;close(cursor);
        if(next<0){if(error)*error=XFMHAPOSIX(@"Abrir la ruta dentro del contenedor",failure);return -1;}
        cursor=next;
    }
    return cursor;
}
- (NSArray<NSDictionary *> *)listDirectory:(NSString *)relativePath error:(NSError **)error {
    NSArray *parts=XFMHARelative(relativePath,NO,error);if(!parts)return nil;
    @synchronized(self) {
        int descriptor=[self openRelative:parts directory:YES error:error];if(descriptor<0)return nil;
        DIR *directory=fdopendir(descriptor);
        if(!directory){int code=errno;close(descriptor);if(error)*error=XFMHAPOSIX(@"Listar la carpeta autorizada",code);return nil;}
        NSMutableArray *rows=[NSMutableArray new];int readError=0;
        for(;;) {
            errno=0;struct dirent *entry=readdir(directory);
            if(!entry){readError=errno;break;}
            NSString *name=[[NSFileManager defaultManager] stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
            if([name isEqual:@"."]||[name isEqual:@".."])continue;
            if(!XFMHAComponent(name))continue;
            struct stat metadata={0};BOOL statOK=fstatat(dirfd(directory),entry->d_name,&metadata,AT_SYMLINK_NOFOLLOW)==0;
            BOOL folder=statOK&&S_ISDIR(metadata.st_mode),regular=statOK&&S_ISREG(metadata.st_mode);
            BOOL readable=NO;
            if(regular) {
                int probe=openat(dirfd(directory),entry->d_name,O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK);
                if(probe>=0){struct stat actual={0};readable=fstat(probe,&actual)==0&&S_ISREG(actual.st_mode)&&actual.st_dev==metadata.st_dev&&actual.st_ino==metadata.st_ino;close(probe);}
            }
            [rows addObject:@{@"name":name,@"isDirectory":@(folder),@"typeKnown":@(folder||regular),@"isSymlink":@(statOK&&S_ISLNK(metadata.st_mode)),@"canRead":@(readable),@"size":@(regular?metadata.st_size:0),@"accessMethod":self.accessMethod}];
            if(rows.count>65536){readError=EOVERFLOW;break;}
        }
        closedir(directory);
        if(readError){if(error)*error=XFMHAPOSIX(@"Leer el listado de la carpeta",readError);return nil;}
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[a[@"name"] localizedStandardCompare:b[@"name"]];}];return rows;
    }
}
- (NSData *)readFile:(NSString *)relativePath maximumBytes:(NSUInteger)maximumBytes error:(NSError **)error {
    NSArray *parts=XFMHARelative(relativePath,YES,error);if(!parts)return nil;
    if(!maximumBytes||maximumBytes>128u*1024u*1024u){if(error)*error=XFMHAError(3018,@"El límite de lectura debe estar entre 1 byte y 128 MB.");return nil;}
    @synchronized(self) {
        int descriptor=[self openRelative:parts directory:NO error:error];if(descriptor<0)return nil;
        struct stat before={0};
        if(fstat(descriptor,&before)!=0){int code=errno;close(descriptor);if(error)*error=XFMHAPOSIX(@"Consultar el archivo autorizado",code);return nil;}
        if(!S_ISREG(before.st_mode)||before.st_size<0||(uint64_t)before.st_size>maximumBytes){close(descriptor);if(error)*error=XFMHAError(3019,@"Esta ruta no es un archivo regular o supera el límite de lectura.");return nil;}
        NSMutableData *data=[NSMutableData dataWithCapacity:(NSUInteger)before.st_size];uint8_t buffer[65536];int readError=0;
        for(;;) {
            ssize_t got=read(descriptor,buffer,sizeof(buffer));
            if(got<0){if(errno==EINTR)continue;readError=errno;break;}
            if(got==0)break;
            if((NSUInteger)got>maximumBytes-data.length){readError=EFBIG;break;}
            [data appendBytes:buffer length:(NSUInteger)got];
        }
        struct stat after={0};BOOL stable=fstat(descriptor,&after)==0&&before.st_dev==after.st_dev&&before.st_ino==after.st_ino&&before.st_size==after.st_size&&before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec&&data.length==(NSUInteger)before.st_size;
        close(descriptor);
        if(readError){if(error)*error=XFMHAPOSIX(@"Leer el archivo del contenedor",readError);return nil;}
        if(!stable){if(error)*error=XFMHAError(3020,@"El archivo cambió durante la lectura. Vuelve a abrirlo.");return nil;}
        return data;
    }
}
- (void)invalidate {
    @synchronized(self) {
        if(_rootFD>=0){close(_rootFD);_rootFD=-1;}
        XFMHAAPI *api=XFMHANative();
        if(_extensionHandle>=0){if(api->releaseExtension)api->releaseExtension(_extensionHandle);_extensionHandle=-1;}
        if(_object){api->freeObject(_object);_object=NULL;}
        if(_query){api->freeQuery(_query);_query=NULL;}
    }
}
- (void)dealloc { [self invalidate]; }
@end
