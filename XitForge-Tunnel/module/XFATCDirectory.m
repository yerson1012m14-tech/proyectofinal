#import "XFATCDirectory.h"
#import "XFStreamBridge.h"
#import "XFATCZip.h"
#import "XFGrappaHelper.h"
#import "XFATCProtocolState.h"
#import "XFATCSyncRetry.h"
#import "XFATCFileRecovery.h"
#import "XFFileCreationProbe.h"
#import "XFFileCreationProbePolicy.h"
#import <sys/stat.h>
#import <string.h>
#import <stdlib.h>
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static NSError *XFATCError(NSInteger code, NSString *text) {
    return [NSError errorWithDomain:@"XitForge.ATCDirectory" code:code
                          userInfo:@{NSLocalizedDescriptionKey:text}];
}
static BOOL XFATCConsume(IdeviceFfiError *native, NSString *action, NSError **error) {
    if (!native) return YES;
    NSString *detail = native->message ? [NSString stringWithUTF8String:native->message] : @"Error del servicio";
    if (error) *error=[NSError errorWithDomain:@"XitForge.ATCDirectory" code:native->code
        userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@: %@ (%d/%d).",action,detail ?: @"Respuesta inválida",native->code,native->sub_code],
                   @"NativeSubcode":@(native->sub_code)}];
    idevice_error_free(native); return NO;
}
static BOOL XFATCComponent(NSString *name) {
    return name.length && ![name isEqual:@"."] && ![name isEqual:@".."] &&
        ![name containsString:@"/"] && ![name containsString:@"\\"] &&
        [name rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location==NSNotFound;
}
static NSString *XFATCPath(NSString *path) {
    if (![path isKindOfClass:NSString.class]) return nil;
    /* Media is physically below /private/var. Three '..' components reach /private,
       so the relocated link must use 'var/...' rather than 'private/var/...'. */
    if ([path hasPrefix:@"/private/var/"]) path=[path substringFromIndex:@"/private".length];
    NSArray *parts=[path componentsSeparatedByString:@"/"];
    if (parts.count<7 || ![parts.firstObject isEqual:@""]) return nil;
    for (NSUInteger i=1;i<parts.count;i++) if (!XFATCComponent(parts[i])) return nil;
    BOOL data=[path hasPrefix:@"/var/mobile/Containers/Data/Application/"];
    BOOL group=[path hasPrefix:@"/var/mobile/Containers/Shared/AppGroup/"];
    if (!data&&!group) return nil;
    NSString *container=parts[6];
    if (![[NSUUID alloc] initWithUUIDString:container]) return nil;
    return path;
}
static BOOL XFATCKnownFilePath(NSString *path) {
    NSArray *parts=[path componentsSeparatedByString:@"/"];
    return parts.count>=8&&!(parts.count==8&&
        [@[@"Documents",@"Library",@"SystemData",@"tmp"] containsObject:parts.lastObject]);
}
static NSArray<NSString *> *XFATCTrackedFiles(void) {
    return @[@"Books/Books.plist",@"Books/Sync/Books.plist",@"Books/Sync/Upload.plist",
             @"Books/Sync/Database/OutstandingAssets_4.sqlite",
             @"Books/Sync/Database/OutstandingAssets_4.sqlite-shm",
             @"Books/Sync/Database/OutstandingAssets_4.sqlite-wal"];
}
static NSData *XFATCPlist(id value, NSError **error) {
    return [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
}
static NSString *XFATCDigest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *hex=[NSMutableString new];
    for(NSUInteger i=0;i<sizeof(bytes);i++)[hex appendFormat:@"%02x",bytes[i]];
    return hex;
}
static BOOL XFATCHash(NSString *value) {
    if(![value isKindOfClass:NSString.class]||value.length!=64)return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}
static BOOL XFATCSyncURL(NSURL *url, NSError **error) {
    int fd=open(url.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
    if(fd<0){if(error)*error=XFATCError(2201,@"No se pudo abrir el registro para conservar la recuperación.");return NO;}
    int result=fsync(fd);int saved=errno;close(fd);
    if(result){if(error)*error=XFATCError(2201,[NSString stringWithFormat:@"No se pudo guardar de forma duradera la recuperación (%d).",saved]);return NO;}
    return YES;
}
static NSDictionary *XFATCBooksManifest(NSDictionary *journal) {
    if([journal[@"fileManifest"] isKindOfClass:NSDictionary.class])return journal[@"fileManifest"];
    /* Old pending journals used a string. Restore them using their original schema. */
    id itemID=[journal[@"archiveProfile"] isEqual:@"3105-directory-v1"]?@1:@"1";
    return @{@"Books":@[@{@"Persistent ID":journal[@"identifier"],@"Item ID":itemID,@"DSID":@"1"}]};
}
static NSArray<NSString *> *XFATCDirectories(NSString *tail) {
    NSMutableArray *dirs=[NSMutableArray arrayWithArray:@[@"META-INF",@"p0",@"p0/p1",@"p0/p1/p2"]];
    NSString *cursor=@"";
    for (NSString *component in [tail componentsSeparatedByString:@"/"]) {
        cursor=cursor.length?[cursor stringByAppendingPathComponent:component]:component;
        [dirs addObject:cursor];
    }
    return dirs;
}

@interface XFATCServiceTunnel : NSObject
@property (nonatomic) AdapterHandle *adapter;
@property (nonatomic) RsdHandshakeHandle *rsd;
@property (nonatomic) BOOL owned;
- (void)close;
@end
@implementation XFATCServiceTunnel
- (void)close {
    if(self.owned) {
        if(self.rsd)rsd_handshake_free(self.rsd);
        if(self.adapter){IdeviceFfiError *failure=adapter_close(self.adapter);if(failure)idevice_error_free(failure);adapter_free(self.adapter);}
    }
    self.rsd=NULL;self.adapter=NULL;self.owned=NO;
}
@end

@interface XFATCDirectory ()
@property (nonatomic) AdapterHandle *adapter;
@property (nonatomic) RsdHandshakeHandle *rsd;
@property (nonatomic) AfcClientHandle *afc;
@property (nonatomic, copy) XFATCTunnelFactory tunnelFactory;
@property (nonatomic, strong) XFATCServiceTunnel *afcTunnel;
@property (nonatomic, strong) NSURL *journalURL;
@property (nonatomic, strong) NSMutableDictionary *journal;
@property (nonatomic, copy) NSString *deviceID;
@property (nonatomic, readwrite, nullable) NSString *lastWarning;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *protocolEvents;
@property (nonatomic, copy) NSString *protocolPhase;
@property (nonatomic, copy) NSDictionary *grappaParameters;
@property (nonatomic, strong) NSMutableDictionary *servicePorts;
@property (nonatomic, copy) NSDictionary *appDirectoryFailure;
@property (nonatomic, copy) NSDictionary *temporaryDirectoryFailure;
@property (nonatomic, copy) NSDictionary *generatedAppLinkProbe;
@property (nonatomic, copy) NSDictionary *fileOperationDiagnostics;
@property (nonatomic) BOOL atcMoveAttempted;
@property (nonatomic) NSUInteger atcSyncAttempt;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *syncAttempts;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *batchEvents;
@property (nonatomic) BOOL batchActive;
@property (nonatomic) NSUInteger batchLastPhase;
@property (nonatomic, readwrite, nullable) NSURL *deletedFileBackupURL;
@property (nonatomic, readwrite) BOOL deletionAbsenceConfirmed;
- (BOOL)validKnownFileJournal:(NSDictionary *)journal;
- (NSArray<NSString *> *)knownFileAssetIDs:(NSDictionary *)journal;
- (NSDictionary *)ownerRecord;
- (BOOL)verifyRemoteOwner:(NSError **)error;
- (BOOL)validJournal:(NSDictionary *)journal;
- (BOOL)recoverKnownFile:(BOOL)explicitRestore error:(NSError **)error;
- (BOOL)publishDeleteReceipt:(NSError **)error;
- (void)loadLatestDeletedBackup;
@end

@implementation XFATCDirectory
- (void)recordBatchSetupPhase:(NSUInteger)phase {
    if(!self.batchActive||phase<1||phase>12||phase<=self.batchLastPhase)return;
    NSArray *labels=@[@"RPPairing record loaded",@"RSD tunnel established",@"AFC connected",@"preflight OK",
        @"stage zip reply = DataComplete",@"stage OK",@"Books/Sync/Books.plist written (4 rows)",
        @"ATC sync to manifest OK",@"placement FileComplete sent (3 messages, mode=replace)",
        @"verify OK",@"move-back FileComplete sent",@"BATCH WRITE COMPLETE"];
    self.batchLastPhase=phase;
    [self.batchEvents addObject:@{@"step":@(phase),@"event":labels[phase-1],@"time":@([NSDate date].timeIntervalSince1970)}];
}
- (instancetype)initWithAdapter:(AdapterHandle *)adapter rsd:(RsdHandshakeHandle *)rsd journalURL:(NSURL *)journalURL {
    if ((self=[super init])) { _adapter=adapter; _rsd=rsd; _journalURL=journalURL; }
    return self;
}
- (instancetype)initWithAdapter:(AdapterHandle *)adapter rsd:(RsdHandshakeHandle *)rsd journalURL:(NSURL *)journalURL tunnelFactory:(XFATCTunnelFactory)tunnelFactory {
    if((self=[self initWithAdapter:adapter rsd:rsd journalURL:journalURL]))self.tunnelFactory=tunnelFactory;
    return self;
}
- (XFATCServiceTunnel *)openServiceTunnel:(NSError **)error {
    XFATCServiceTunnel *tunnel=[XFATCServiceTunnel new];
    if(self.tunnelFactory) {
        AdapterHandle *adapter=NULL;RsdHandshakeHandle *rsd=NULL;
        BOOL ok=self.tunnelFactory(&adapter,&rsd,error);
        tunnel.adapter=adapter;tunnel.rsd=rsd;tunnel.owned=YES;
        if(!ok||!adapter||!rsd){[tunnel close];if(error&&!*error)*error=XFATCError(2154,@"No se pudo abrir un túnel independiente para este servicio.");return nil;}
    } else {tunnel.adapter=self.adapter;tunnel.rsd=self.rsd;}
    [self recordBatchSetupPhase:1];
    return tunnel;
}
- (void)recordProtocolEvent:(NSString *)event command:(NSString *)command code:(NSInteger)code {
    if (!self.protocolEvents) self.protocolEvents=[NSMutableArray new];
    // Only known command names and numeric result codes enter copied diagnostics.
    NSArray *known=@[@"Capabilities",@"InstalledAssets",@"AssetMetrics",@"SyncAllowed",@"Ping",@"Pong",@"HostInfo",@"RequestingSync",
                     @"ReadyForSync",@"FinishedSyncingMetadata",@"AssetManifest",@"FileComplete",
                     @"SyncFailed",@"SyncStopped",@"SyncFinished"];
    NSString *name=[command isKindOfClass:NSString.class]&&[known containsObject:command]?command:@"Other";
    [self.protocolEvents addObject:@{@"event":event,@"command":name,
        @"phase":self.protocolPhase?:@"NotStarted",@"code":@(code),@"syncAttempt":@(self.atcSyncAttempt)}];
    if(self.protocolEvents.count>96)[self.protocolEvents removeObjectAtIndex:0];
}
- (NSDictionary *)protocolDiagnostics {
    return @{@"phase":self.protocolPhase?:@"NotStarted",@"events":[self.protocolEvents copy]?:@[],
             @"grappaParameters":self.grappaParameters?:@{},@"archiveProfile":@"3105-directory-v1",
             @"tunnelMode":self.tunnelFactory?@"FreshPerService":@"SharedAdapter",
             @"servicePorts":[self.servicePorts copy]?:@{},
             @"appDirectoryFailure":self.appDirectoryFailure?:@{},
             @"temporaryDirectoryFailure":self.temporaryDirectoryFailure?:@{},
             @"generatedAppLinkProbe":self.generatedAppLinkProbe?:@{},
             @"knownFileOperation":self.fileOperationDiagnostics?:@{},
             @"syncAttempts":[self.syncAttempts copy]?:@[],
             @"batchWrite":@{@"mode":@"replace",@"filesPerBatch":@1,@"events":[self.batchEvents copy]?:@[],
                 @"completed":@(self.batchLastPhase==12),@"originalBackupBeforePlacement":@YES}};
}
- (void)recordServicePort:(const char *)name tunnel:(XFATCServiceTunnel *)tunnel {
    CRsdService *service=NULL;
    IdeviceFfiError *failure=rsd_get_service_info(tunnel.rsd,name,&service);
    if(!self.servicePorts)self.servicePorts=[NSMutableDictionary new];
    self.servicePorts[[NSString stringWithUTF8String:name]]=@(failure||!service?0:service->port);
    if(failure)idevice_error_free(failure);
    if(service)rsd_free_service(service);
}
- (void)closeAFC { if (_afc) { afc_client_free(_afc); _afc=NULL; } [self.afcTunnel close];self.afcTunnel=nil; }
- (BOOL)openAFC:(NSError **)error {
    if (_afc) {[self recordBatchSetupPhase:1];[self recordBatchSetupPhase:2];[self recordBatchSetupPhase:3];return YES;}
    char *uuid=NULL;
    if (!XFATCConsume(rsd_get_uuid(_rsd,&uuid),@"Identificar el dispositivo del túnel",error)) return NO;
    self.deviceID=uuid?[NSString stringWithUTF8String:uuid]:nil;
    if (uuid) rsd_free_string(uuid);
    if (!self.deviceID.length) { if(error)*error=XFATCError(2100,@"RSD no identificó este dispositivo. No se modificarán temporales."); return NO; }
    self.afcTunnel=[self openServiceTunnel:error];if(!self.afcTunnel)return NO;
    [self recordServicePort:"com.apple.afc.shim.remote" tunnel:self.afcTunnel];
    BOOL ok=XFATCConsume(xf_afc_connect_rsd(self.afcTunnel.adapter,self.afcTunnel.rsd,10000,&_afc),@"Abrir AFC por su túnel independiente",error)&&_afc;
    if(ok)[self recordBatchSetupPhase:2];
    if(!ok)[self closeAFC];else [self recordBatchSetupPhase:3];return ok;
}
- (NSURL *)activeURL { return [self.journalURL URLByAppendingPathComponent:@"active.plist"]; }
- (BOOL)saveJournal:(NSString *)intent error:(NSError **)error {
    self.journal[@"intent"]=intent;
    self.journal[@"updatedAt"]=[NSDate date];
    NSData *data=XFATCPlist(self.journal,error);
    if (!data) return NO;
    if (![data writeToURL:self.activeURL options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error]) return NO;
    chmod(self.activeURL.fileSystemRepresentation,0600);
    if(self.journal[@"knownFile"]&&(!XFATCSyncURL(self.activeURL,error)||!XFATCSyncURL(self.journalURL,error)))return NO;
    return YES;
}
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error {
    if (missing) *missing=NO;
    AfcFileInfo info={0};
    IdeviceFfiError *failure=afc_get_file_info(_afc,path.UTF8String,&info);
    if (failure) {
        BOOL absent=failure->code==106 && failure->sub_code==8;
        afc_file_info_free(&info);
        if (absent) { idevice_error_free(failure); if(missing)*missing=YES; return nil; }
        XFATCConsume(failure,@"Consultar un objeto temporal",error); return nil;
    }
    NSString *kind=info.st_ifmt?[NSString stringWithUTF8String:info.st_ifmt]:nil;
    NSString *link=info.st_link_target?[NSString stringWithUTF8String:info.st_link_target]:nil;
    NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:@{@"size":@(info.size),@"blocks":@(info.blocks),@"creation":@(info.creation),@"modified":@(info.modified),@"kind":kind?:@"unknown"}];
    if(link)row[@"linkTarget"]=link;
    afc_file_info_free(&info);
    int64_t mtime=0;
    if (!XFATCConsume(xf_afc_get_mtime(_afc,path.UTF8String,&mtime,8000),@"Guardar la fecha del objeto",error)) return nil;
    row[@"mtimeNS"]=@(mtime);
    return row;
}
- (NSString *)directoryPathRole:(NSString *)path {
    if([path isEqual:self.journal[@"link"]])return @"GeneratedAppLink";
    for(NSArray<NSString *> *mapping in @[@[@"source",@"GeneratedStage"],@[@"backup",@"OwnedBackup"]]) {
        NSString *root=self.journal[mapping[0]];
        if(root.length&&([path isEqual:root]||[path hasPrefix:[root stringByAppendingString:@"/"]]))return mapping[1];
    }
    if([path isEqual:@"Books"]||[path hasPrefix:@"Books/"])return @"BooksState";
    if([path isEqual:@"Airlock"]||[path hasPrefix:@"Airlock/"])return @"Airlock";
    return @"OtherTemporary";
}
- (void)probeGeneratedAppLinkAfterListingFailure {
    // One metadata-only query before recovery. This describes the generated object,
    // not whether its target can be resolved or the target directory can be opened.
    AfcFileInfo info={0};
    IdeviceFfiError *failure=afc_get_file_info(_afc,[self.journal[@"link"] UTF8String],&info);
    @try {
        NSString *kind=@"Unknown";
        BOOL linkTargetMetadataPresent=NO,expectedLinkTarget=NO;
        if(!failure) {
            if(info.st_ifmt) {
                if(strcmp(info.st_ifmt,"S_IFLNK")==0)kind=@"S_IFLNK";
                else if(strcmp(info.st_ifmt,"S_IFDIR")==0)kind=@"S_IFDIR";
                else if(strcmp(info.st_ifmt,"S_IFREG")==0)kind=@"S_IFREG";
                else kind=@"Other";
            }
            linkTargetMetadataPresent=info.st_link_target!=NULL;
            NSString *expected=[@"../../../" stringByAppendingString:self.journal[@"tail"]];
            expectedLinkTarget=[kind isEqual:@"S_IFLNK"]&&linkTargetMetadataPresent&&
                strcmp(info.st_link_target,expected.UTF8String)==0;
        }
        // Only fixed labels, booleans and numeric codes enter copied diagnostics.
        self.generatedAppLinkProbe=@{@"pathRole":@"GeneratedAppLink",@"operation":@"GetFileInfo",
            @"status":failure?@"Failed":@"ReturnedMetadata",@"code":@(failure?failure->code:0),
            @"subcode":@(failure?failure->sub_code:0),@"kind":kind,
            @"linkTargetMetadataPresent":@(linkTargetMetadataPresent),
            @"isExpectedLinkTarget":@(expectedLinkTarget)};
    } @finally {
        if(failure)idevice_error_free(failure);
        afc_file_info_free(&info);
    }
}
- (NSArray<NSString *> *)names:(NSString *)path error:(NSError **)error {
    char **names=NULL; size_t count=0;
    NSString *role=[self directoryPathRole:path];
    BOOL appDirectory=[role isEqual:@"GeneratedAppLink"];
    NSString *phase=appDirectory?@"DirectoryListing":([self.protocolPhase isEqual:@"Recovery"]?@"Recovery":@"TemporaryCleanup");
    IdeviceFfiError *native=afc_list_directory(_afc,path.UTF8String,&names,&count);
    if(native) {
        // Fixed roles and numeric codes distinguish the app target from cleanup without copying paths.
        NSDictionary *failure=@{@"pathRole":role,@"phase":phase,@"code":@(native->code),@"subcode":@(native->sub_code)};
        if(appDirectory)self.appDirectoryFailure=failure;else self.temporaryDirectoryFailure=failure;
    }
    BOOL denied=appDirectory&&native&&native->code==106&&native->sub_code==10;
    BOOL notFound=appDirectory&&native&&native->code==106&&native->sub_code==8;
    if(denied||notFound)[self probeGeneratedAppLinkAfterListingFailure];
    BOOL ok=XFATCConsume(native,appDirectory?@"Listar la carpeta de la app":@"Listar un directorio temporal",error);
    if(!ok&&error&&*error) {
        NSMutableDictionary *details=[(*error).userInfo mutableCopy];
        details[@"DirectoryPathRole"]=role;details[@"DirectoryPhase"]=phase;
        if(denied)details[NSLocalizedDescriptionKey]=@"AFC denegó enumerar la carpeta de esta app. iOS no permitió listar su contenido mediante este enlace (106/10).";
        else if(notFound)details[NSLocalizedDescriptionKey]=@"AFC no encontró el objeto al intentar listar la carpeta de esta app mediante el enlace generado (106/8).";
        *error=[NSError errorWithDomain:(*error).domain code:(*error).code userInfo:details];
    }
    NSMutableArray *out=[NSMutableArray new];
    if (ok && count && !names) { ok=NO; if(error)*error=XFATCError(2101,@"AFC devolvió un listado vacío de datos."); }
    if (ok) for(size_t i=0;i<count;i++) {
        NSString *name=names[i]?[NSString stringWithUTF8String:names[i]]:nil;
        if ([name isEqual:@"."]||[name isEqual:@".."])continue;
        if (!XFATCComponent(name)) { ok=NO; if(error)*error=XFATCError(2102,@"AFC devolvió un nombre de archivo que no se puede usar con seguridad.");break; }
        [out addObject:name];
    }
    if(names){for(size_t i=0;i<count;i++)if(names[i])idevice_string_free(names[i]);free(names);}
    return ok?out:nil;
}
- (NSData *)readSnapshot:(NSString *)path expectedSize:(NSUInteger)size error:(NSError **)error {
    if (size>128u*1024u*1024u) { if(error)*error=XFATCError(2103,@"El estado de Books es demasiado grande para preservarlo de forma segura.");return nil; }
    AfcFileHandle *handle=NULL;
    if (!XFATCConsume(afc_file_open(_afc,path.UTF8String,AfcRdOnly,&handle),@"Preservar el estado de Books",error)) return nil;
    NSMutableData *out=[NSMutableData dataWithCapacity:size]; BOOL ok=YES;
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:60];
    while(out.length<size) {
        if(deadline.timeIntervalSinceNow<=0){ok=NO;if(error)*error=XFATCError(2211,@"La lectura del archivo superó el tiempo de espera.");break;}
        uint8_t *bytes=NULL;size_t got=0;size_t wanted=MIN((NSUInteger)65536,size-out.length);
        ok=XFATCConsume(afc_file_read(handle,&bytes,wanted,&got),@"Leer la copia de seguridad de Books",error);
        if (ok&&(got>wanted||(got&&!bytes))) {ok=NO;if(error&&!*error)*error=XFATCError(2145,@"AFC devolvió más datos de los solicitados durante la copia de seguridad.");}
        if (ok&&got&&bytes) [out appendBytes:bytes length:got];
        if(bytes)afc_file_read_data_free(bytes,got);
        if(!ok||!got||got>wanted){ok=NO;break;}
    }
    NSError *closeError=nil;
    if(!XFATCConsume(afc_file_close(handle),@"Cerrar la copia de seguridad",&closeError)){ok=NO;if(error&&!*error)*error=closeError;}
    if(!ok||out.length!=size){if(error&&!*error)*error=XFATCError(2104,@"La copia de seguridad de Books quedó incompleta.");return nil;}
    return out;
}
- (BOOL)removeOwned:(NSString *)path expectedKind:(NSString *)kind error:(NSError **)error {
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(missing)return YES;if(!info)return NO;
    if(![info[@"kind"] isEqual:kind]){if(error)*error=XFATCError(2105,@"Cambió el tipo de un temporal; se conservará para recuperación.");return NO;}
    if (![self saveJournal:[@"remove " stringByAppendingString:path] error:error])return NO;
    if(!XFATCConsume(afc_remove_path(_afc,path.UTF8String),@"Eliminar un objeto generado",error))return NO;
    info=[self info:path missing:&missing error:error];
    if(!missing){if(error&&!*error)*error=XFATCError(2106,@"El iPhone todavía conserva un objeto temporal.");return NO;}
    return YES;
}
- (BOOL)makeOwnedDirectory:(NSString *)path error:(NSError **)error {
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(!missing){if(info&&[info[@"kind"] isEqual:@"S_IFDIR"])return YES;return NO;}
    BOOL sharedRoot=[path isEqual:@"Airlock"]||[path isEqual:@"Airlock/Book"];
    if(sharedRoot) {
        NSMutableDictionary *ownership=[self.journal[@"mkdirOwnership"] mutableCopy]?:[NSMutableDictionary new];
        ownership[path]=@{@"creationRequested":@YES};self.journal[@"mkdirOwnership"]=ownership;
    }
    if(![self saveJournal:[@"mkdir " stringByAppendingString:path] error:error])return NO;
    if(!XFATCConsume(afc_make_directory(_afc,path.UTF8String),@"Crear un directorio temporal",error))return NO;
    if(sharedRoot) {
        NSDictionary *created=[self info:path missing:&missing error:error];if(!created||missing)return NO;
        NSMutableDictionary *ownership=[self.journal[@"mkdirOwnership"] mutableCopy];
        ownership[path]=@{@"creationRequested":@YES,@"createdInfo":created};self.journal[@"mkdirOwnership"]=ownership;
        if(![self saveJournal:[@"mkdir ownership confirmed " stringByAppendingString:path] error:error])return NO;
    }
    return YES;
}
- (BOOL)renameOwned:(NSString *)source to:(NSString *)destination error:(NSError **)error {
    BOOL missing=NO;NSDictionary *before=[self info:source missing:&missing error:error];
    if(!before||missing)return NO;
    [self info:destination missing:&missing error:error];
    if(!missing){if(error&&!*error)*error=XFATCError(2107,@"El destino de un temporal ya existe. Se preservó el estado para recuperación.");return NO;}
    if(![self saveJournal:[NSString stringWithFormat:@"rename %@ -> %@",source,destination] error:error])return NO;
    NSError *failure=nil;
    BOOL ok=XFATCConsume(afc_rename_path(_afc,source.UTF8String,destination.UTF8String),@"Reubicar temporal",&failure);
    if(!ok && failure.code==106 && [failure.userInfo[@"NativeSubcode"] integerValue]==7) {
        // Retry only the server's InvalidArg response, after confirming that no
        // move occurred. Some AFC endpoints require root-relative absolute names.
        BOOL sourceMissing=NO,destinationMissing=NO;
        NSDictionary *current=[self info:source missing:&sourceMissing error:error];
        [self info:destination missing:&destinationMissing error:error];
        if(!current||sourceMissing||!destinationMissing||![current isEqual:before])return NO;
        NSString *from=[source hasPrefix:@"/"]?source:[@"/" stringByAppendingString:source];
        NSString *to=[destination hasPrefix:@"/"]?destination:[@"/" stringByAppendingString:destination];
        if(![self saveJournal:@"retry rejected rename with absolute Media names" error:error])return NO;
        ok=XFATCConsume(afc_rename_path(_afc,from.UTF8String,to.UTF8String),@"Reubicar temporal con rutas absolutas",&failure);
    }
    if(!ok){
        if(error)*error=failure;return NO;
    }
    BOOL sourceMissing=NO,destinationMissing=NO;
    NSDictionary *after=[self info:destination missing:&destinationMissing error:error];
    [self info:source missing:&sourceMissing error:error];
    if(!after||destinationMissing||!sourceMissing||![after[@"kind"] isEqual:before[@"kind"]]) {
        if(error&&!*error)*error=XFATCError(2107,@"El traslado del temporal no se pudo confirmar. Se conservó el registro.");return NO;
    }
    return YES;
}

- (BOOL)writeOwned:(NSData *)data path:(NSString *)path error:(NSError **)error {
    BOOL missing=NO;[self info:path missing:&missing error:error];
    if(!missing){if(error&&!*error)*error=XFATCError(2108,@"El manifiesto temporal ya existe.");return NO;}
    if(![self saveJournal:[@"write " stringByAppendingString:path] error:error])return NO;
    AfcFileHandle *file=NULL;
    if(!XFATCConsume(afc_file_open(_afc,path.UTF8String,AfcWrOnly,&file),@"Preparar el manifiesto temporal",error))return NO;
    BOOL ok=XFATCConsume(afc_file_write(file,data.bytes,data.length),@"Escribir el manifiesto temporal",error);
    NSError *closeError=nil;
    if(!XFATCConsume(afc_file_close(file),@"Cerrar el manifiesto temporal",&closeError)){ok=NO;if(error&&!*error)*error=closeError;}
    return ok;
}
- (BOOL)snapshotBooks:(NSError **)error {
    BOOL missing=NO;NSDictionary *root=[self info:@"Books" missing:&missing error:error];
    if(!root&&!missing)return NO;
    if(root&&![root[@"kind"] isEqual:@"S_IFDIR"]){if(error)*error=XFATCError(2109,@"Books tiene un tipo inesperado. No se inició la exploración.");return NO;}
    self.journal[@"booksOriginallyPresent"]=@(!missing);
    self.journal[@"booksOriginalInfo"]=root?:@{};
    NSMutableDictionary *tracked=[NSMutableDictionary new]; NSUInteger total=0,index=0;
    for(NSString *path in XFATCTrackedFiles()) {
        NSDictionary *info=[self info:path missing:&missing error:error];
        if(!info&&!missing)return NO;
        NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:@{@"exists":@(!missing)}];
        if(info) {
            if(![info[@"kind"] isEqual:@"S_IFREG"]){if(error)*error=XFATCError(2110,@"Un archivo de sincronización de Books tiene un tipo inesperado.");return NO;}
            NSData *bytes=[self readSnapshot:path expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
            if(!bytes)return NO;total+=bytes.length;
            if(total>256u*1024u*1024u){if(error)*error=XFATCError(2111,@"No hay una copia de seguridad suficientemente pequeña del estado de Books.");return NO;}
            NSString *local=[NSString stringWithFormat:@"%@-preimage-%lu.bin",self.journal[@"token"],(unsigned long)index];
            NSURL *url=[self.journalURL URLByAppendingPathComponent:local];
            if(![bytes writeToURL:url options:NSDataWritingWithoutOverwriting|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
            chmod(url.fileSystemRepresentation,0600);
            if(!XFATCSyncURL(url,error)||!XFATCSyncURL(self.journalURL,error))return NO;
            row[@"info"]=info;row[@"snapshot"]=local;row[@"snapshotDigest"]=XFATCDigest(bytes);
        }
        tracked[path]=row;index++;
    }
    self.journal[@"trackedPreimage"]=tracked;
    return [self saveJournal:@"snapshot complete" error:error];
}
// BEGIN Books in-place transaction
- (BOOL)writeBooksBytes:(NSData *)bytes path:(NSString *)path error:(NSError **)error {
    if(![XFATCTrackedFiles() containsObject:path])return NO;
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if((!info&&!missing)||(info&&![info[@"kind"] isEqual:@"S_IFREG"]))return NO;
    AfcFileHandle *handle=NULL;
    if(!XFATCConsume(afc_file_open(_afc,path.UTF8String,AfcWrOnly,&handle),@"Abrir estado de sincronización",error)||!handle)return NO;
    BOOL ok=!bytes.length||XFATCConsume(afc_file_write(handle,bytes.bytes,bytes.length),@"Escribir estado de sincronización",error);
    NSError *closeError=nil;
    if(!XFATCConsume(afc_file_close(handle),@"Cerrar estado de sincronización",&closeError)){if(ok&&error)*error=closeError;ok=NO;}
    if(!ok)return NO;
    info=[self info:path missing:&missing error:error];
    NSData *observed=info?[self readSnapshot:path expectedSize:[info[@"size"] unsignedIntegerValue] error:error]:nil;
    if(![observed isEqual:bytes]){if(error&&!*error)*error=XFATCError(2255,@"El estado escrito no coincide con su copia. Se conserva la recuperación.");return NO;}
    return YES;
}
- (BOOL)beginBooksInPlace:(NSError **)error {
    BOOL missing=NO;NSDictionary *root=[self info:@"Books" missing:&missing error:error];
    if([self.journal[@"booksOriginallyPresent"] boolValue]) {
        if(!root||missing||![self preimageMatches:@"Books" error:error])return NO;
    }else if(!missing)return NO;
    BOOL markerMissing=NO;
    [self info:@"Books/XitForgeOwner.plist" missing:&markerMissing error:error];
    if(!markerMissing){if(error&&!*error)*error=XFATCError(2256,@"Books ya contiene un marcador ajeno. No se modificó.");return NO;}
    self.journal[@"booksInPlace"]=@YES;
    if(![self saveJournal:@"Books rename rejected; preserve root and use durable file snapshots" error:error])return NO;
    if(missing&&![self makeOwnedDirectory:@"Books" error:error])return NO;
    NSData *owner=XFATCPlist(self.ownerRecord,error);
    if(!owner||![self writeOwned:owner path:@"Books/XitForgeOwner.plist" error:error])return NO;
    NSDictionary *sync=[self info:@"Books/Sync" missing:&missing error:error];
    if(!sync&&!missing)return NO;
    if(sync&&![sync[@"kind"] isEqual:@"S_IFDIR"])return NO;
    if(missing) {
        self.journal[@"inPlaceSyncCreated"]=@YES;
        if(![self saveJournal:@"create absent synchronization directory" error:error]||
           ![self makeOwnedDirectory:@"Books/Sync" error:error])return NO;
    }
    return YES;
}
- (BOOL)isolateBooks:(NSError **)error {
    if(![self.journal[@"booksOriginallyPresent"] boolValue])return YES;
    NSError *failure=nil;
    if([self renameOwned:@"Books" to:[self.journal[@"backup"] stringByAppendingPathComponent:@"Books"] error:&failure])return YES;
    if(failure.code==106&&[failure.userInfo[@"NativeSubcode"] integerValue]==7) {
        // Only a positively unchanged original permits switching strategies.
        return [self beginBooksInPlace:error];
    }
    if(error)*error=failure;return NO;
}
- (BOOL)installWorkingBooks:(NSString *)working error:(NSError **)error {
    if(![self.journal[@"booksInPlace"] boolValue]) {
        NSError *failure=nil;
        if([self renameOwned:working to:@"Books" error:&failure])return YES;
        if(failure.code!=106||[failure.userInfo[@"NativeSubcode"] integerValue]!=7||
           [self.journal[@"booksOriginallyPresent"] boolValue]){if(error)*error=failure;return NO;}
        if(![self beginBooksInPlace:error])return NO;
    }
    if(![self booksOwnerMatches:@"Books" error:error])return NO;
    NSData *bytes=XFATCPlist(XFATCBooksManifest(self.journal),error);
    self.journal[@"inPlaceManifestWriteStarted"]=@YES;
    if(!bytes||![self saveJournal:@"persist synchronization write intent before touching original manifest" error:error])return NO;
    return [self writeBooksBytes:bytes path:@"Books/Sync/Books.plist" error:error];
}
- (BOOL)restoreBooksInPlace:(NSError **)error {
    BOOL restored=[self.journal[@"booksRestored"] boolValue];
    BOOL missing=NO;
    NSDictionary *marker=[self info:@"Books/XitForgeOwner.plist" missing:&missing error:error];
    if(!marker&&!missing)return NO;
    BOOL started=[self.journal[@"inPlaceManifestWriteStarted"] boolValue];
    if((marker&&![self booksOwnerMatches:@"Books" error:error])||(missing&&started&&!restored)) {
        if(error&&!*error)*error=XFATCError(2257,@"El marcador de sincronización cambió. Se conservan las copias.");return NO;
    }
    if(started&&!restored)for(NSString *path in XFATCTrackedFiles()) {
        NSDictionary *row=self.journal[@"trackedPreimage"][path];
        NSData *original=[row[@"exists"] boolValue]?[NSData dataWithContentsOfURL:
            [self.journalURL URLByAppendingPathComponent:row[@"snapshot"]] options:0 error:error]:nil;
        if([row[@"exists"] boolValue]&&(!original||original.length!=[row[@"info"][@"size"] unsignedLongLongValue]||
           (row[@"snapshotDigest"]&&![row[@"snapshotDigest"] isEqual:XFATCDigest(original)]))) {
            if(error&&!*error)*error=XFATCError(2258,@"La copia de sincronización no coincide con el registro. Se conservó el estado actual.");return NO;
        }
        NSDictionary *info=[self info:path missing:&missing error:error];
        if(!info&&!missing)return NO;
        if(info&&![info[@"kind"] isEqual:@"S_IFREG"])return NO;
        NSData *current=info?[self readSnapshot:path expectedSize:[info[@"size"] unsignedIntegerValue] error:error]:nil;
        if(info&&!current)return NO;
        if((original&&[original isEqual:current])||(!original&&missing))continue;
        // Preserve daemon-written bytes before restoring any synchronization file.
        if(current) {
            NSString *name=[NSString stringWithFormat:@"%@-sync-change-%@.bin",self.journal[@"token"],NSUUID.UUID.UUIDString];
            NSURL *url=[self.journalURL URLByAppendingPathComponent:name];
            if(![current writeToURL:url options:NSDataWritingWithoutOverwriting|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
            chmod(url.fileSystemRepresentation,0600);
            if(!XFATCSyncURL(url,error)||!XFATCSyncURL(self.journalURL,error))return NO;
        }
        if(![self saveJournal:@"restore tracked synchronization file from durable snapshot" error:error])return NO;
        if(original) {
            if(![self writeBooksBytes:original path:path error:error])return NO;
        }else if(![self removeOwned:path expectedKind:@"S_IFREG" error:error])return NO;
    }
    self.journal[@"booksRestored"]=@YES;
    // Persist restoration before removing our marker, so an interrupted cleanup
    // never reclassifies a restored library as a foreign mutable transaction.
    if(![self saveJournal:@"tracked synchronization state restored without moving Books" error:error])return NO;
    if(marker&&![self removeOwned:@"Books/XitForgeOwner.plist" expectedKind:@"S_IFREG" error:error])return NO;
    if([self.journal[@"inPlaceSyncCreated"] boolValue]) {
        [self info:@"Books/Sync" missing:&missing error:error];
        if(!missing) {
            NSArray *names=[self names:@"Books/Sync" error:error];
            if(!names)return NO;
            if(!names.count&&![self removeOwned:@"Books/Sync" expectedKind:@"S_IFDIR" error:error])return NO;
        }
    }
    if(![self.journal[@"booksOriginallyPresent"] boolValue]) {
        [self info:@"Books" missing:&missing error:error];
        if(!missing) {
            NSArray *names=[self names:@"Books" error:error];
            if(!names)return NO;
            if(!names.count&&![self removeOwned:@"Books" expectedKind:@"S_IFDIR" error:error])return NO;
        }
    }
    return YES;
}
// END Books in-place transaction

- (BOOL)preimageMatches:(NSString *)root error:(NSError **)error {
    BOOL rootMissing=NO;NSDictionary *rootInfo=[self info:root missing:&rootMissing error:error];
    NSDictionary *expectedRoot=self.journal[@"booksOriginalInfo"];
    if(!rootInfo||rootMissing||![rootInfo[@"kind"] isEqual:@"S_IFDIR"]||
       ![rootInfo[@"creation"] isEqual:expectedRoot[@"creation"]]||
       ![rootInfo[@"mtimeNS"] isEqual:expectedRoot[@"mtimeNS"]])return NO;
    NSDictionary *tracked=self.journal[@"trackedPreimage"];
    for(NSString *path in XFATCTrackedFiles()) {
        NSDictionary *row=tracked[path];
        NSString *tail=[path substringFromIndex:@"Books/".length];
        NSString *actual=[root stringByAppendingPathComponent:tail];
        BOOL missing=NO;NSDictionary *observed=[self info:actual missing:&missing error:error];
        BOOL expected=[row[@"exists"] boolValue];
        if(!observed&&!missing)return NO;
        if(expected==missing)return NO;
        if(expected) {
            NSDictionary *previous=row[@"info"];
            if(![observed[@"kind"] isEqual:@"S_IFREG"]||![observed[@"size"] isEqual:previous[@"size"]]||![observed[@"creation"] isEqual:previous[@"creation"]]||![observed[@"mtimeNS"] isEqual:previous[@"mtimeNS"]])return NO;
            NSURL *url=[self.journalURL URLByAppendingPathComponent:row[@"snapshot"]];
            NSData *before=[NSData dataWithContentsOfURL:url options:0 error:error];
            NSData *now=[self readSnapshot:actual expectedSize:[observed[@"size"] unsignedIntegerValue] error:error];
            if(!before||!now||![before isEqual:now])return NO;
        }
    }
    return YES;
}
- (BOOL)sendDictionary:(NSDictionary *)dictionary stream:(ReadWriteOpaque *)stream littleEndian:(BOOL)little error:(NSError **)error {
    NSData *body=XFATCPlist(dictionary,error);if(!body||body.length>10u*1024u*1024u)return NO;
    uint32_t n=(uint32_t)body.length;uint8_t prefix[4];
    for(int i=0;i<4;i++)prefix[i]=(uint8_t)(n>>(little?8*i:8*(3-i)));
    NSMutableData *frame=[NSMutableData dataWithBytes:prefix length:4];[frame appendData:body];
    BOOL ok=XFATCConsume(xf_stream_send(stream,frame.bytes,frame.length,8000),@"Enviar el mensaje al servicio",error);
    if(little)[self recordProtocolEvent:ok?@"Sent":@"SendFailed" command:dictionary[@"Command"] code:ok?0:(error&&*error?(*error).code:1)];
    return ok;
}
- (NSDictionary *)receiveDictionary:(ReadWriteOpaque *)stream littleEndian:(BOOL)little timeout:(uint64_t)timeout error:(NSError **)error {
    uint8_t bytes[4]={0};
    if(!XFATCConsume(xf_stream_read_exact(stream,bytes,4,timeout),@"Esperar respuesta del servicio",error))return nil;
    uint32_t n=0;for(int i=0;i<4;i++)n|=(uint32_t)bytes[i]<<(little?8*i:8*(3-i));
    if(!n||n>10u*1024u*1024u){if(error)*error=XFATCError(2112,@"El servicio devolvió una longitud de mensaje inválida.");return nil;}
    NSMutableData *body=[NSMutableData dataWithLength:n];
    if(!XFATCConsume(xf_stream_read_exact(stream,body.mutableBytes,n,timeout),@"Recibir la respuesta del servicio",error))return nil;
    id value=[NSPropertyListSerialization propertyListWithData:body options:NSPropertyListImmutable format:NULL error:error];
    if(![value isKindOfClass:NSDictionary.class]){if(error&&!*error)*error=XFATCError(2113,@"El servicio devolvió una respuesta que no es un diccionario.");return nil;}
    if(value[@"Params"]&&![value[@"Params"] isKindOfClass:NSDictionary.class]){if(error)*error=XFATCError(2139,@"El servicio devolvió parámetros de un tipo inesperado.");return nil;}
    return value;
}
- (BOOL)stageZip:(NSData *)archive error:(NSError **)error {
    self.protocolPhase=@"StreamingZip";
    XFATCServiceTunnel *tunnel=[self openServiceTunnel:error];if(!tunnel)return NO;
    [self recordServicePort:"com.apple.streaming_zip_conduit.shim.remote" tunnel:tunnel];
    ReadWriteOpaque *stream=NULL;
    if(!XFATCConsume(xf_rsd_connect_service(tunnel.adapter,tunnel.rsd,"com.apple.streaming_zip_conduit.shim.remote",true,10000,&stream),@"Abrir StreamingZip",error)){[tunnel close];return NO;}
    BOOL ok=[self saveJournal:@"extract generated directory archive" error:error] &&
        [self sendDictionary:@{@"MediaSubdir":self.journal[@"source"]} stream:stream littleEndian:NO error:error] &&
        XFATCConsume(xf_stream_send(stream,archive.bytes,archive.length,12000),@"Preparar el enlace de exploración",error);
    if(ok){NSDictionary *reply=[self receiveDictionary:stream littleEndian:NO timeout:15000 error:error];ok=reply!=nil&&reply[@"Error"]==nil&&[reply[@"Status"] isEqual:@"DataComplete"];if(reply&&!ok&&error)*error=XFATCError(2114,@"StreamingZip no confirmó DataComplete para el archivo temporal.");if(ok)[self recordBatchSetupPhase:5];}
    IdeviceFfiError *close=xf_stream_close(stream,1000);if(close)idevice_error_free(close);
    [tunnel close];
    if(!ok){if(error&&*error)*error=XFATCError((*error).code,[@"StreamingZip: " stringByAppendingString:(*error).localizedDescription]);return NO;}
    NSString *link=[self.journal[@"source"] stringByAppendingPathComponent:@"p0/p1/p2/link"];
    BOOL missing=NO;NSDictionary *info=[self info:link missing:&missing error:error];
    NSString *expected=[@"../../../" stringByAppendingString:self.journal[@"tail"]];
    if(!info){
        if(error&&!*error)*error=XFATCError(2150,missing?@"StreamingZip respondió, pero el enlace temporal no apareció en la zona de exploración.":@"No se pudo consultar el enlace temporal antes de iniciar la exploración.");return NO;
    }
    if(![info[@"kind"] isEqual:@"S_IFLNK"]){
        if(error)*error=XFATCError(2151,[NSString stringWithFormat:@"El objeto temporal se creó con un tipo distinto al de un enlace (%@). No se inició la exploración.",info[@"kind"]?:@"desconocido"]);return NO;
    }
    if(![info[@"linkTarget"] isKindOfClass:NSString.class]){
        if(error)*error=XFATCError(2152,@"El iPhone informó que el objeto es un enlace, pero no devolvió su destino. No se inició la exploración.");return NO;
    }
    if(![info[@"linkTarget"] isEqual:expected]){
        if(error)*error=XFATCError(2153,@"El destino del enlace temporal no coincide con la carpeta solicitada. Se conservó la verificación y no se inició la exploración.");return NO;
    }
    return YES;
}
- (NSDictionary *)message:(NSString *)name session:(NSNumber *)session params:(NSDictionary *)params {
    NSMutableDictionary *message=[NSMutableDictionary dictionaryWithDictionary:@{@"Command":name,@"Session":session}];
    if(params)message[@"Params"]=params;return message;
}
- (NSString *)nameOfMessage:(NSDictionary *)message {
    id name=message[@"Command"]?:message[@"MessageName"];
    return [name isKindOfClass:NSString.class]?name:nil;
}
- (NSDictionary *)waitFor:(NSString *)wanted stream:(ReadWriteOpaque *)stream seconds:(NSTimeInterval)seconds support:(NSDictionary **)support error:(NSError **)error {
    self.protocolPhase=wanted;
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(deadline.timeIntervalSinceNow>0) {
        uint64_t ms=(uint64_t)MAX(1,MIN(12000,deadline.timeIntervalSinceNow*1000));
        NSError *readError=nil;
        NSDictionary *message=[self receiveDictionary:stream littleEndian:YES timeout:ms error:&readError];
        if(!message){
            [self recordProtocolEvent:@"ReceiveFailed" command:wanted code:readError.code?:1];
            if(error){
                NSMutableDictionary *details=[readError.userInfo mutableCopy]?:[NSMutableDictionary new];
                details[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"AirTraffic, esperando %@: %@",wanted,readError.localizedDescription?:@"conexión cerrada"];
                *error=[NSError errorWithDomain:readError.domain?:@"XitForge.ATCDirectory" code:readError.code?:1 userInfo:details];
            }
            return nil;
        }
        NSString *name=[self nameOfMessage:message];
        NSDictionary *params=[message[@"Params"] isKindOfClass:NSDictionary.class]?message[@"Params"]:@{};
        NSNumber *responseCode=[params[@"ErrorCode"] isKindOfClass:NSNumber.class]?params[@"ErrorCode"]:nil;
        NSInteger numericCode=responseCode?responseCode.integerValue:0;
        [self recordProtocolEvent:@"Received" command:name code:numericCode];
        // Preserve only bounded numeric sessions, never arbitrary fields from a reply.
        id session=message[@"Session"];
        if([session isKindOfClass:NSNumber.class]&&[session longLongValue]>=0&&[session unsignedLongLongValue]<=UINT32_MAX) {
            NSMutableDictionary *event=[self.protocolEvents.lastObject mutableCopy];
            event[@"session"]=session;self.protocolEvents[self.protocolEvents.count-1]=event;
        }
        if([name isEqual:@"Capabilities"]&&support) {
            id info=message[@"Params"][@"GrappaSupportInfo"];
            if([info isKindOfClass:NSDictionary.class])*support=info;
        }
        XFATCWaitDecision decision=XFATCDecisionForMessage(wanted.UTF8String,name.UTF8String,responseCode!=nil,numericCode);
        if(decision==XFATCWaitPong) {
            NSNumber *session=[message[@"Session"] isKindOfClass:NSNumber.class]?message[@"Session"]:@1;
            if(![self sendDictionary:[self message:@"Pong" session:session params:nil] stream:stream littleEndian:YES error:error])return nil;
            continue;
        }
        if(decision==XFATCWaitAccept)return message;
        if(decision==XFATCWaitRejectSync){
            if(error)*error=XFATCError(2116,[NSString stringWithFormat:@"AirTraffic devolvió SyncFailed al esperar %@ (código %@).",wanted,responseCode?:@"no informado"]);return nil;
        }
        if(decision==XFATCWaitRejectEnd){if(error)*error=XFATCError(2117,@"AirTraffic terminó antes de autorizar el enlace de exploración.");return nil;}
    }
    if(error)*error=XFATCError(2118,[NSString stringWithFormat:@"AirTraffic no envió %@ dentro del tiempo de espera.",wanted]);return nil;
}
- (BOOL)retryATCPreparation:(BOOL (^)(NSError **))operation error:(NSError **)error {
    NSError *failure=nil;
    for(NSUInteger attempt=1;attempt<=3;attempt++) {
        self.atcMoveAttempted=NO;self.atcSyncAttempt=attempt;
        failure=nil;
        BOOL ok=operation(&failure); // Each attempt closes its stream and tunnel.
        if(!self.syncAttempts)self.syncAttempts=[NSMutableArray new];
        [self.syncAttempts addObject:@{@"attempt":@(attempt),@"phase":self.protocolPhase?:@"ConnectATC",
            @"code":@(failure.code),@"completed":@(ok),@"fileMoveAttempted":@(self.atcMoveAttempted)}];
        if(self.syncAttempts.count>24)[self.syncAttempts removeObjectAtIndex:0];
        if(ok)return YES;
        BOOL nativeError=[failure.domain isEqual:@"XitForge.ATCDirectory"]&&
            [failure.userInfo[@"NativeSubcode"] isKindOfClass:NSNumber.class];
        BOOL transportFailure=XFATCPreparationTransportFailure(nativeError,failure.code,
            [failure.userInfo[@"NativeSubcode"] longValue]);
        if(!XFATCShouldRetryPreparation((unsigned)attempt,self.tunnelFactory!=nil,transportFailure,self.atcMoveAttempted))break;
        [self recordProtocolEvent:@"ReconnectBeforeFileMove" command:self.protocolPhase code:failure.code];
        [NSThread sleepForTimeInterval:XFATCSyncRetryDelayMS((unsigned)attempt)/1000.0];
    }
    if(error) {
        NSMutableDictionary *details=[failure.userInfo mutableCopy]?:[NSMutableDictionary new];
        details[@"ATCSyncAttempts"]=@(self.atcSyncAttempt);
        details[@"ATCFileMoveAttempted"]=@(self.atcMoveAttempted);
        details[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"%@\nPreparación de AirTraffic: %lu intento(s).%@",
            failure.localizedDescription?:@"El servicio no confirmó la operación.",(unsigned long)self.atcSyncAttempt,
            self.atcMoveAttempted?@"":@" No se envió ningún movimiento de archivo en esta sesión."];
        *error=[NSError errorWithDomain:failure.domain?:@"XitForge.ATCDirectory" code:failure.code?:2118 userInfo:details];
    }
    return NO;
}
- (BOOL)runATC:(NSError **)error {
    return [self retryATCPreparation:^BOOL(NSError **attemptError){return [self runATCOnce:attemptError];} error:error];
}
- (BOOL)runATCOnce:(NSError **)error {
    self.protocolPhase=@"ConnectATC";
    XFATCServiceTunnel *tunnel=[self openServiceTunnel:error];if(!tunnel)return NO;
    [self recordServicePort:"com.apple.atc.shim.remote" tunnel:tunnel];
    ReadWriteOpaque *stream=NULL;
    if(!XFATCConsume(xf_rsd_connect_service(tunnel.adapter,tunnel.rsd,"com.apple.atc.shim.remote",true,10000,&stream),@"Abrir AirTraffic",error)){[tunnel close];return NO;}
    BOOL ok=NO;NSDictionary *support=nil;
    do {
        if(![self waitFor:@"SyncAllowed" stream:stream seconds:20 support:&support error:error])break;
        uint8_t token[8192];size_t length=0;char details[512]={0};
        for(NSString *key in @[@"version",@"deviceType",@"protocolVersion"])if(support[key]&&(![support[key] isKindOfClass:NSNumber.class]||[support[key] unsignedLongLongValue]>UINT32_MAX)){if(error)*error=XFATCError(2140,@"AirTraffic devolvió parámetros de autenticación inválidos.");goto closeATC;}
        uint32_t version=[support[@"version"] unsignedIntValue]?:1;
        uint32_t type=[support[@"deviceType"] unsignedIntValue];
        uint32_t protocol=[support[@"protocolVersion"] unsignedIntValue]?:1;
        self.grappaParameters=@{@"version":@(version),@"deviceType":@(type),@"protocolVersion":@(protocol)};
        if(XFGetGrappaToken(version,type,protocol,token,sizeof(token),&length,details,sizeof(details))!=0||!length){
            if(error)*error=XFATCError(2119,[NSString stringWithFormat:@"No se pudo autenticar AirTraffic: %s",details]);break;
        }
        NSData *grappa=[NSData dataWithBytes:token length:length];
        // Match the supplied 3105 host protocol identity. Visible app branding
        // and the user's approved pairing keys remain separate from these fields.
        NSDictionary *host=@{@"Type":@"iTunes",@"Version":@"13.7.0.161",@"MacOSVersion":@"27.0",@"SyncHostName":@"airlift",@"LibraryID":NSUUID.UUID.UUIDString,@"SyncedDataclasses":@[@"Book"],@"SyncedAssetTypes":@[@"Book"],@"Wakeable":@NO};
        self.protocolPhase=@"HostInfo";
        if(![self sendDictionary:[self message:@"HostInfo" session:@0 params:@{@"HostInfo":host,@"LocalCloudSupport":@NO}] stream:stream littleEndian:YES error:error])break;
        // AirTrafficHost and the supplied 3105 wait 200 ms after HostInfo.
        [NSThread sleepForTimeInterval:0.2];
        NSMutableDictionary *syncHost=[host mutableCopy];syncHost[@"Grappa"]=grappa;
        self.protocolPhase=@"RequestingSync";
        if(![self sendDictionary:[self message:@"RequestingSync" session:@1 params:@{@"Dataclasses":@[@"Book"],@"DataclassAnchors":@{},@"HostInfo":syncHost}] stream:stream littleEndian:YES error:error])break;
        if(![self waitFor:@"ReadyForSync" stream:stream seconds:40 support:NULL error:error])break;
        self.protocolPhase=@"FinishedSyncingMetadata";
        if(![self sendDictionary:[self message:@"FinishedSyncingMetadata" session:@1 params:@{@"SyncTypes":@{@"Book":@1},@"DataclassAnchors":@{}}] stream:stream littleEndian:YES error:error])break;
        NSDictionary *message=[self waitFor:@"AssetManifest" stream:stream seconds:30 support:NULL error:error];if(!message)break;
        id manifest=message[@"Params"][@"AssetManifest"];
        BOOL found=NO;
        if([manifest isKindOfClass:NSDictionary.class]&&[manifest[@"Book"] isKindOfClass:NSArray.class])for(id book in manifest[@"Book"])if([book isKindOfClass:NSDictionary.class]&&[book[@"AssetID"] isEqual:self.journal[@"identifier"]]&&[book[@"IsDownload"] isKindOfClass:NSNumber.class]&&[book[@"IsDownload"] boolValue])found=YES;
        if(!found){if(error)*error=XFATCError(2120,@"El manifiesto de AirTraffic no autorizó el enlace generado. No se enviará FileComplete.");break;}
        self.protocolPhase=@"FileComplete";
        if(![self saveJournal:@"move generated symlink inside Media" error:error])break;
        NSDictionary *params=@{@"AssetID":self.journal[@"identifier"],@"Dataclass":@"Book",@"AssetPath":self.journal[@"link"]};
        self.atcMoveAttempted=YES; // Set before send, including a partial/failed send.
        if(![self sendDictionary:[self message:@"FileComplete" session:@1 params:params] stream:stream littleEndian:YES error:error])break;
        // The supplied 3105 lets ATC process FileComplete before closing its channel.
        self.protocolPhase=@"FileCompleteSettle";
        [NSThread sleepForTimeInterval:0.15];
        ok=YES;
    }while(0);
closeATC:;
    IdeviceFfiError *close=xf_stream_close(stream,1000);if(close)idevice_error_free(close);
    [tunnel close];
    if(!ok)return NO;
    // Probe only after ATC closes, using the AFC connection opened before staging.
    self.protocolPhase=@"VerifyLink";ok=NO;
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
    while(deadline.timeIntervalSinceNow>0) {
        BOOL missing=NO;NSDictionary *info=[self info:self.journal[@"link"] missing:&missing error:error];
        if(info&&[info[@"kind"] isEqual:@"S_IFLNK"]&&[info[@"linkTarget"] isEqual:[@"../../../" stringByAppendingString:self.journal[@"tail"]]]){ok=YES;break;}
        if(!missing&&!info)break;
        [NSThread sleepForTimeInterval:0.125];
    }
    if(!ok&&error&&!*error)*error=XFATCError(2121,@"AirTraffic no trasladó el enlace generado. El estado temporal se recuperará antes del siguiente intento.");
    return ok;
}
- (BOOL)validKnownFileJournal:(NSDictionary *)journal {
    NSDictionary *file=[journal[@"knownFile"] isKindOfClass:NSDictionary.class]?journal[@"knownFile"]:nil;
    NSString *target=file[@"target"],*token=journal[@"token"],*backup=journal[@"backup"];
    NSString *device=journal[@"rsdUUID"];
    if(![device isKindOfClass:NSString.class]||!device.length||device.length>512||!device.UTF8String||
       strlen(device.UTF8String)!=[device lengthOfBytesUsingEncoding:NSUTF8StringEncoding])return NO;
    if(!file||![target isKindOfClass:NSString.class]||![target isEqual:XFATCPath(target)]||
       ![target.stringByDeletingLastPathComponent isEqual:[@"/" stringByAppendingString:journal[@"tail"]]]||
       !XFATCComponent(target.lastPathComponent)||
       [target componentsSeparatedByString:@"/"].count<8)return NO;
    if(![@[@"read",@"replace",@"delete",@"createProbe",@"create"] containsObject:file[@"operation"]])return NO;
    for(NSString *pair in @[@"Original",@"Incoming",@"Verify"])
        if(![file[pair] isEqual:[backup stringByAppendingPathComponent:[@"File" stringByAppendingString:pair]]])return NO;
    if(![file[@"snapshot"] isEqual:[token stringByAppendingString:@"-original.bin"]])return NO;
    for(NSString *key in @[@"originalMoveIntent",@"originalObserved",@"originalCaptured",@"returnOriginalIntent",@"originalReturned",
                          @"incomingPlaceIntent",@"verifyMoveIntent",@"newVerified",@"returnNewIntent",@"committed"])
        if(![file[key] isKindOfClass:NSNumber.class])return NO;
    if(file[@"originalDigest"]&&!XFATCHash(file[@"originalDigest"]))return NO;
    if(file[@"newDigest"]&&!XFATCHash(file[@"newDigest"]))return NO;
    if([file[@"originalCaptured"] boolValue]&&(!XFATCHash(file[@"originalDigest"])||
       ![file[@"originalSize"] isKindOfClass:NSNumber.class]||[file[@"originalSize"] unsignedLongLongValue]>64u*1024u*1024u))return NO;
    if([file[@"newVerified"] boolValue]&&(!XFATCHash(file[@"newDigest"])||
       ![file[@"newSize"] isKindOfClass:NSNumber.class]||[file[@"newSize"] unsignedLongLongValue]>64u*1024u*1024u))return NO;
    if([file[@"originalReturned"] boolValue]&&![file[@"returnOriginalIntent"] boolValue])return NO;
    if([file[@"operation"] isEqual:@"create"]) {
        if ([file[@"originalMoveIntent"] boolValue] || [file[@"originalCaptured"] boolValue] ||
            [file[@"returnOriginalIntent"] boolValue] || [file[@"originalReturned"] boolValue]) return NO;
        if(file[@"newDigest"] && (!XFATCHash(file[@"newDigest"]) ||
            ![file[@"newSize"] isKindOfClass:NSNumber.class] || [file[@"newSize"] unsignedLongLongValue]>64u*1024u*1024u)) return NO;
    }
    if([file[@"operation"] isEqual:@"createProbe"]) {
        NSData *marker=XFProbeContents(target);
        if(!marker || [file[@"originalMoveIntent"] boolValue] || [file[@"originalObserved"] boolValue] ||
           [file[@"originalCaptured"] boolValue] || [file[@"returnOriginalIntent"] boolValue] ||
           [file[@"originalReturned"] boolValue])return NO;
        if(file[@"newDigest"]&&![file[@"newDigest"] isEqual:XFATCDigest(marker)])return NO;
        if(file[@"newSize"]&&[file[@"newSize"] unsignedLongLongValue]!=marker.length)return NO;
    }
    if([file[@"operation"] isEqual:@"delete"]) {
        if(![file[@"targetAbsenceConfirmed"] isKindOfClass:NSNumber.class]||
           ![file[@"deleteReceiptWritten"] isKindOfClass:NSNumber.class]||
           [file[@"incomingPlaceIntent"] boolValue]||[file[@"verifyMoveIntent"] boolValue]||
           [file[@"newVerified"] boolValue]||[file[@"returnNewIntent"] boolValue]||file[@"newDigest"]||file[@"newSize"])return NO;
        if([file[@"committed"] boolValue]&&(![file[@"originalMoveIntent"] boolValue]||
           ![file[@"originalObserved"] boolValue]||![file[@"originalCaptured"] boolValue]||
           [file[@"returnOriginalIntent"] boolValue]||[file[@"originalReturned"] boolValue]||
           ![file[@"deletedAt"] isKindOfClass:NSDate.class]))return NO;
        if([file[@"deleteReceiptWritten"] boolValue]&&![file[@"committed"] boolValue])return NO;
    } else if([file[@"committed"] boolValue]&&(![file[@"newVerified"] boolValue]||![file[@"returnNewIntent"] boolValue]))return NO;
    NSDictionary *manifest=[journal[@"fileManifest"] isKindOfClass:NSDictionary.class]?journal[@"fileManifest"]:nil;
    NSArray *ids=[self knownFileAssetIDs:journal];
    if(ids.count!=5)return NO;
    if(file[@"batchPlacement"]&&![file[@"batchPlacement"] isKindOfClass:NSNumber.class])return NO;
    if(file[@"batchLinkReset"]&&![file[@"batchLinkReset"] isKindOfClass:NSNumber.class])return NO;
    if([file[@"batchPlacement"] boolValue]) {
        if(![file[@"operation"] isEqual:@"replace"]||![file[@"originalCaptured"] boolValue])return NO;
        ids=@[ids[0],ids[3],ids[1],ids[4]];
    }
    if(![manifest[@"Books"] isKindOfClass:NSArray.class]||[manifest[@"Books"] count]!=ids.count)return NO;
    for(NSUInteger i=0;i<ids.count;i++) {
        id row=manifest[@"Books"][i];
        if(![row isKindOfClass:NSDictionary.class]||[row count]!=3||![row[@"Persistent ID"] isEqual:ids[i]]||
           ![row[@"Item ID"] isEqual:@(i+1)]||![row[@"DSID"] isEqual:@"1"])return NO;
    }
    return YES;
}
- (NSArray<NSString *> *)knownFileAssetIDs:(NSDictionary *)journal {
    NSDictionary *file=journal[@"knownFile"];
    NSString *target=file[@"target"];
    if(![target isKindOfClass:NSString.class]||![target hasPrefix:@"/var/mobile/Containers/"])return @[];
    NSString *protectedSource=[@"../../../" stringByAppendingString:[target substringFromIndex:@"/var/mobile/".length]];
    return @[journal[@"identifier"],protectedSource,
             [@"../../" stringByAppendingString:file[@"Original"]],
             [@"../../" stringByAppendingString:file[@"Incoming"]],
             [@"../../" stringByAppendingString:file[@"Verify"]]];
}
- (NSArray *)knownFilePair:(NSUInteger)source destination:(NSString *)destination {
    return @[@{@"AssetID":[self knownFileAssetIDs:self.journal][source],@"AssetPath":destination,@"Dataclass":@"Book"}];
}
- (NSString *)knownFileDestination {
    NSString *target=self.journal[@"knownFile"][@"target"];
    return [self.journal[@"link"] stringByAppendingPathComponent:target.lastPathComponent];
}
- (NSDictionary *)knownManifestForBatch:(BOOL)batch {
    NSArray *ids=[self knownFileAssetIDs:self.journal];
    if(ids.count!=5)return nil;
    NSArray *ordered=batch?@[ids[0],ids[3],ids[1],ids[4]]:ids;
    NSMutableArray *rows=[NSMutableArray new];
    for(NSString *identifier in ordered)[rows addObject:@{@"Persistent ID":identifier,@"Item ID":@(rows.count+1),@"DSID":@"1"}];
    return @{@"Books":rows};
}
- (BOOL)publishKnownManifestForBatch:(BOOL)batch error:(NSError **)error {
    if(![self verifyRemoteOwner:error]||![self booksOwnerMatches:@"Books" error:error])return NO;
    NSString *path=@"Books/Sync/Books.plist";
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(!info||missing||![info[@"kind"] isEqual:@"S_IFREG"]||[info[@"size"] unsignedLongLongValue]>65536)return NO;
    NSData *before=[self readSnapshot:path expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
    id previous=before?[NSPropertyListSerialization propertyListWithData:before options:0 format:NULL error:error]:nil;
    NSDictionary *full=[self knownManifestForBatch:NO],*grouped=[self knownManifestForBatch:YES];
    if(!previous||(![previous isEqual:full]&&![previous isEqual:grouped])) {
        if(error&&!*error)*error=XFATCError(2250,@"El manifiesto temporal cambió. Se conservó el respaldo y se detuvo el lote.");return NO;
    }
    NSDictionary *manifest=batch?grouped:full;
    NSData *bytes=XFATCPlist(manifest,error);if(!bytes)return NO;
    self.journal[@"knownFile"][@"batchPlacement"]=@(batch);self.journal[@"fileManifest"]=manifest;
    if(![self saveJournal:@"persist batch manifest transition before publishing" error:error])return NO;
    AfcFileHandle *handle=NULL;
    if(!XFATCConsume(afc_file_open(_afc,path.UTF8String,AfcWrOnly,&handle),@"Abrir manifiesto del lote",error)||!handle)return NO;
    BOOL ok=XFATCConsume(afc_file_write(handle,bytes.bytes,bytes.length),@"Publicar manifiesto del lote",error);
    NSError *closeError=nil;
    if(!XFATCConsume(afc_file_close(handle),@"Cerrar manifiesto del lote",&closeError)){if(ok&&error)*error=closeError;ok=NO;}
    if(!ok)return NO;
    info=[self info:path missing:&missing error:error];
    if(!info||missing||[info[@"size"] unsignedLongLongValue]!=bytes.length)return NO;
    NSData *observed=[self readSnapshot:path expectedSize:bytes.length error:error];
    if(![observed isEqual:bytes]){if(error&&!*error)*error=XFATCError(2251,@"El manifiesto del lote no se verificó.");return NO;}
    if(batch)[self recordBatchSetupPhase:7];
    return YES;
}
- (NSArray *)batchPlacementPairs {
    NSMutableArray *pairs=[NSMutableArray new];
    [pairs addObjectsFromArray:[self knownFilePair:0 destination:self.journal[@"link"]]];
    [pairs addObjectsFromArray:[self knownFilePair:3 destination:[self knownFileDestination]]];
    [pairs addObjectsFromArray:[self knownFilePair:1 destination:self.journal[@"knownFile"][@"Verify"]]];
    return pairs;
}
- (BOOL)verifyBatchStagedLink:(NSError **)error {
    NSString *staged=[self.journal[@"source"] stringByAppendingPathComponent:@"p0/p1/p2/link"];
    BOOL missing=NO;NSDictionary *info=[self info:staged missing:&missing error:error];
    NSString *expected=[@"../../../" stringByAppendingString:self.journal[@"tail"]];
    if(!info||missing||![info[@"kind"] isEqual:@"S_IFLNK"]||![info[@"linkTarget"] isEqual:expected]) {
        if(error&&!*error)*error=XFATCError(2252,@"El enlace preparado para el lote no coincide con el destino.");return NO;
    }
    [self info:self.journal[@"link"] missing:&missing error:error];
    if(!missing){if(error&&!*error)*error=XFATCError(2252,@"El destino del enlace del lote ya existe o no pudo comprobarse.");return NO;}
    return YES;
}
- (BOOL)rearmBatchLink:(NSError **)error {
    if(![self verifyKnownTargetLink:error])return NO;
    self.journal[@"knownFile"][@"batchLinkReset"]=@YES;
    if(![self saveJournal:@"persist link rearm intent for grouped placement" error:error])return NO;
    NSString *staged=[self.journal[@"source"] stringByAppendingPathComponent:@"p0/p1/p2/link"];
    return [self renameOwned:self.journal[@"link"] to:staged error:error]&&[self verifyBatchStagedLink:error];
}
- (BOOL)runKnownFilePairs:(NSArray<NSDictionary *> *)pairs error:(NSError **)error {
    return [self retryATCPreparation:^BOOL(NSError **attemptError){return [self runKnownFilePairsOnce:pairs error:attemptError];} error:error];
}
- (BOOL)runKnownFilePairsOnce:(NSArray<NSDictionary *> *)pairs error:(NSError **)error {
    self.protocolPhase=@"ConnectATC";
    NSSet *allowed=[NSSet setWithArray:[self knownFileAssetIDs:self.journal]];
    NSDictionary *file=self.journal[@"knownFile"];
    BOOL grouped=[file[@"batchPlacement"] boolValue]&&[pairs isEqual:[self batchPlacementPairs]];
    NSSet *destinations=[NSSet setWithArray:@[file[@"Original"],file[@"Incoming"],file[@"Verify"],[self knownFileDestination],self.journal[@"link"]]];
    for(NSDictionary *pair in pairs)if(![allowed containsObject:pair[@"AssetID"]]||![destinations containsObject:pair[@"AssetPath"]]||
       ![pair[@"Dataclass"] isEqual:@"Book"]||([pair[@"AssetPath"] isEqual:self.journal[@"link"]]&&!grouped)){if(error)*error=XFATCError(2202,@"El movimiento solicitado no pertenece a esta transacción.");return NO;}
    if(!pairs.count||pairs.count>8||![self verifyRemoteOwner:error])return NO;
    if(grouped&&(![self validatedLocalOriginal:file error:error]||![self verifyBatchStagedLink:error]))return NO;
    XFATCServiceTunnel *tunnel=[self openServiceTunnel:error];if(!tunnel)return NO;
    ReadWriteOpaque *stream=NULL;
    if(!XFATCConsume(xf_rsd_connect_service(tunnel.adapter,tunnel.rsd,"com.apple.atc.shim.remote",true,10000,&stream),
                     @"Abrir la operación de archivo AirLift",error)){[tunnel close];return NO;}
    BOOL ok=NO;NSDictionary *support=nil;
    do {
        if(![self waitFor:@"SyncAllowed" stream:stream seconds:20 support:&support error:error])break;
        for(NSString *key in @[@"version",@"deviceType",@"protocolVersion"])
            if(support[key]&&(![support[key] isKindOfClass:NSNumber.class]||[support[key] unsignedLongLongValue]>UINT32_MAX)){
                if(error)*error=XFATCError(2140,@"AirTraffic devolvió parámetros de autenticación inválidos.");goto closeKnownFile;}
        uint32_t version=[support[@"version"] unsignedIntValue]?:1,type=[support[@"deviceType"] unsignedIntValue],protocol=[support[@"protocolVersion"] unsignedIntValue]?:1;
        self.grappaParameters=@{@"version":@(version),@"deviceType":@(type),@"protocolVersion":@(protocol)};
        uint8_t token[8192];size_t length=0;char details[512]={0};
        if(XFGetGrappaToken(version,type,protocol,token,sizeof(token),&length,details,sizeof(details))||!length){
            if(error)*error=XFATCError(2119,[NSString stringWithFormat:@"No se pudo autenticar AirTraffic: %s",details]);break;}
        NSDictionary *host=@{@"Type":@"iTunes",@"Version":@"13.7.0.161",@"MacOSVersion":@"27.0",@"SyncHostName":@"airlift",
                              @"LibraryID":NSUUID.UUID.UUIDString,@"SyncedDataclasses":@[@"Book"],@"SyncedAssetTypes":@[@"Book"],@"Wakeable":@NO};
        if(![self sendDictionary:[self message:@"HostInfo" session:@0 params:@{@"HostInfo":host,@"LocalCloudSupport":@NO}] stream:stream littleEndian:YES error:error])break;
        [NSThread sleepForTimeInterval:0.2];
        NSMutableDictionary *sync=[host mutableCopy];sync[@"Grappa"]=[NSData dataWithBytes:token length:length];
        if(![self sendDictionary:[self message:@"RequestingSync" session:@1 params:@{@"Dataclasses":@[@"Book"],@"DataclassAnchors":@{},@"HostInfo":sync}] stream:stream littleEndian:YES error:error]||
           ![self waitFor:@"ReadyForSync" stream:stream seconds:40 support:NULL error:error]||
           ![self sendDictionary:[self message:@"FinishedSyncingMetadata" session:@1 params:@{@"SyncTypes":@{@"Book":@1},@"DataclassAnchors":@{}}] stream:stream littleEndian:YES error:error])break;
        NSDictionary *assetManifestMessage=[self waitFor:@"AssetManifest" stream:stream seconds:30 support:NULL error:error];
        if(!assetManifestMessage)break;
        if(grouped) {
            id books=assetManifestMessage[@"Params"][@"AssetManifest"][@"Book"];
            if(![books isKindOfClass:NSArray.class]){if(error)*error=XFATCError(2120,@"El manifiesto agrupado de AirTraffic no tiene una lista Book válida. No se enviará FileComplete.");break;}
            BOOL authorized=YES;
            for(NSDictionary *pair in pairs) {
                BOOL found=NO;
                for(id item in books) if([item isKindOfClass:NSDictionary.class]&&[item[@"AssetID"] isEqual:pair[@"AssetID"]]&&[item[@"IsDownload"] isKindOfClass:NSNumber.class]&&[item[@"IsDownload"] boolValue]){found=YES;break;}
                if(!found){authorized=NO;break;}
            }
            if(!authorized){if(error)*error=XFATCError(2120,@"El manifiesto agrupado de AirTraffic no autorizó todos los archivos del lote. No se enviará FileComplete.");break;}
        }
        if(grouped)[self recordBatchSetupPhase:8];
        for(NSDictionary *pair in pairs) {
            if(!grouped&&[pair[@"AssetPath"] isEqual:[self knownFileDestination]]){
                BOOL missing=NO;NSDictionary *link=[self info:self.journal[@"link"] missing:&missing error:error];
                if(!link||missing||![link[@"kind"] isEqual:@"S_IFLNK"]||
                   ![link[@"linkTarget"] isEqual:[@"../../../" stringByAppendingString:self.journal[@"tail"]]]){
                    if(error&&!*error)*error=XFATCError(2220,@"El enlace de retorno cambió o desapareció. Se conservaron el original y la recuperación, sin enviarlo a otro destino.");goto closeKnownFile;}
                if(([@[@"createProbe",@"create"] containsObject:file[@"operation"]])&&![self requireProbeDestinationAbsent:error])goto closeKnownFile;
            }
            if(![self saveJournal:@"send persisted known-file move" error:error])goto closeKnownFile;
            self.protocolPhase=@"FileComplete";
            self.atcMoveAttempted=YES;
            if(![self sendDictionary:[self message:@"FileComplete" session:@1 params:pair] stream:stream littleEndian:YES error:error])goto closeKnownFile;
        }
        if(grouped)[self recordBatchSetupPhase:9];
        else if([file[@"batchPlacement"] boolValue]&&[file[@"newVerified"] boolValue]&&
                [pairs isEqual:[self knownFilePair:4 destination:[self knownFileDestination]]])[self recordBatchSetupPhase:11];
        [NSThread sleepForTimeInterval:0.15];ok=YES;
    }while(0);
closeKnownFile:;
    IdeviceFfiError *close=xf_stream_close(stream,1000);if(close)idevice_error_free(close);
    [tunnel close];return ok;
}
- (BOOL)waitKnownFile:(NSString *)path missing:(BOOL)wantMissing error:(NSError **)error {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
    do {
        BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
        if(!info&&!missing)return NO; // Socket/permission errors are never disappearance.
        if(wantMissing?missing:info!=nil)return YES;
        [NSThread sleepForTimeInterval:0.125];
    }while(deadline.timeIntervalSinceNow>0);
    if(error)*error=XFATCError(2203,@"No se confirmó el traslado del archivo. Se conserva la recuperación pendiente.");
    return NO;
}
- (NSData *)readKnownStage:(NSString *)path limit:(NSUInteger)limit error:(NSError **)error {
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(!info||![info[@"kind"] isEqual:@"S_IFREG"]||[info[@"size"] unsignedLongLongValue]>limit){
        if(error&&!*error)*error=XFATCError(2204,@"El archivo recuperado está ausente, no es regular o supera el límite de 64 MiB.");return nil;}
    NSData *data=[self readSnapshot:path expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
    if(!data)return nil;
    NSDictionary *after=[self info:path missing:&missing error:error];
    if(!after||missing||![after[@"kind"] isEqual:@"S_IFREG"]||
       ![after[@"size"] isEqual:info[@"size"]]||![after[@"mtimeNS"] isEqual:info[@"mtimeNS"]]){
        if(error&&!*error)*error=XFATCError(2205,@"El archivo cambió mientras se leía; se conservará para recuperar.");return nil;}
    return data;
}
- (BOOL)persistKnownOriginal:(NSData *)data error:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    NSURL *url=[self.journalURL URLByAppendingPathComponent:file[@"snapshot"]];
    if([[NSFileManager defaultManager] fileExistsAtPath:url.path]){
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||[attributes[NSFileSize] unsignedLongLongValue]!=data.length){
            if(error&&!*error)*error=XFATCError(2206,@"La copia original existente no es un archivo regular del tamaño esperado.");return NO;}
        NSData *prior=[NSData dataWithContentsOfURL:url options:0 error:error];
        if(![prior isEqual:data]){if(error&&!*error)*error=XFATCError(2206,@"La copia original existente no coincide; no se reemplazará.");return NO;}
    }else if(![data writeToURL:url options:NSDataWritingWithoutOverwriting|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
    chmod(url.fileSystemRepresentation,0600);
    if(!XFATCSyncURL(url,error)||!XFATCSyncURL(self.journalURL,error))return NO;
    file[@"originalDigest"]=XFATCDigest(data);file[@"originalSize"]=@(data.length);
    file[@"originalCaptured"]=@YES;
    return [self saveJournal:@"durable original file captured" error:error];
}
- (NSData *)validatedLocalOriginal:(NSDictionary *)record error:(NSError **)error {
    NSString *snapshot=record[@"snapshot"];
    NSNumber *size=record[@"originalSize"];
    if(![snapshot isKindOfClass:NSString.class]||!XFATCComponent(snapshot)||
       ![size isKindOfClass:NSNumber.class]||size.unsignedLongLongValue>64u*1024u*1024u||
       !XFATCHash(record[@"originalDigest"])) {
        if(error)*error=XFATCError(2222,@"La copia original no tiene un registro válido.");return nil;
    }
    NSURL *url=[self.journalURL URLByAppendingPathComponent:snapshot];
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||
       [attributes[NSFileSize] unsignedLongLongValue]!=size.unsignedLongLongValue) {
        if(error&&!*error)*error=XFATCError(2222,@"La copia original no es legible o cambió de tamaño.");return nil;
    }
    NSData *bytes=[NSData dataWithContentsOfURL:url options:0 error:error];
    if(!bytes||bytes.length!=size.unsignedLongLongValue||![XFATCDigest(bytes) isEqual:record[@"originalDigest"]]) {
        if(error&&!*error)*error=XFATCError(2222,@"La copia original no coincide con los bytes conservados.");return nil;
    }
    return bytes;
}
- (BOOL)validDeleteReceipt:(NSDictionary *)receipt name:(NSString *)name {
    if(![receipt isKindOfClass:NSDictionary.class]||receipt.count!=12||
       ![receipt[@"module"] isEqual:@"XitForgeATCFileDelete"]||![receipt[@"version"] isEqual:@1]||
       ![receipt[@"operation"] isEqual:@"delete"]||![receipt[@"namespace"] isEqual:self.journalURL.lastPathComponent])return NO;
    NSString *token=[receipt[@"token"] isKindOfClass:NSString.class]?receipt[@"token"]:nil;
    NSString *target=[receipt[@"target"] isKindOfClass:NSString.class]?receipt[@"target"]:nil;
    if(!token||![[NSUUID alloc] initWithUUIDString:token]||
       ![name isEqual:[NSString stringWithFormat:@"deleted-%@.plist",token]]||
       !target.UTF8String||![target isEqual:XFATCPath(target)]||[target componentsSeparatedByString:@"/"].count<8||
       ![receipt[@"snapshot"] isEqual:[token stringByAppendingString:@"-original.bin"]]||
       ![receipt[@"remoteOriginal"] isEqual:[NSString stringWithFormat:@"xf_atc_state_%@/FileOriginal",token]]||
       !XFATCHash(receipt[@"originalDigest"])||![receipt[@"originalSize"] isKindOfClass:NSNumber.class]||
       [receipt[@"originalSize"] unsignedLongLongValue]>64u*1024u*1024u||
       ![receipt[@"targetAbsenceConfirmed"] isKindOfClass:NSNumber.class]||![receipt[@"deletedAt"] isKindOfClass:NSDate.class])return NO;
    return YES;
}
- (BOOL)publishDeleteReceipt:(NSError **)error {
    NSDictionary *file=self.journal[@"knownFile"];
    if(![file[@"operation"] isEqual:@"delete"]||![file[@"committed"] boolValue]||
       ![self validJournal:self.journal]||![self validatedLocalOriginal:file error:error]) {
        if(error&&!*error)*error=XFATCError(2222,@"No se pudo verificar la copia del archivo retirado.");return NO;
    }
    NSString *name=[NSString stringWithFormat:@"deleted-%@.plist",self.journal[@"token"]];
    NSDictionary *receipt=@{@"module":@"XitForgeATCFileDelete",@"version":@1,@"operation":@"delete",
        @"token":self.journal[@"token"],@"namespace":self.journal[@"namespace"],@"target":file[@"target"],
        @"snapshot":file[@"snapshot"],@"remoteOriginal":file[@"Original"],@"originalDigest":file[@"originalDigest"],
        @"originalSize":file[@"originalSize"],@"targetAbsenceConfirmed":file[@"targetAbsenceConfirmed"],@"deletedAt":file[@"deletedAt"]};
    if(![self validDeleteReceipt:receipt name:name])return NO;
    NSURL *url=[self.journalURL URLByAppendingPathComponent:name];
    if([NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||[attributes[NSFileSize] unsignedLongLongValue]>32768)return NO;
        NSData *prior=[NSData dataWithContentsOfURL:url options:0 error:error];
        id value=prior?[NSPropertyListSerialization propertyListWithData:prior options:NSPropertyListImmutable format:NULL error:error]:nil;
        if(![value isEqual:receipt]){if(error&&!*error)*error=XFATCError(2223,@"El comprobante existente no coincide; se conservó la copia sin reemplazarlo.");return NO;}
    } else {
        NSData *encoded=XFATCPlist(receipt,error);
        if(!encoded||![encoded writeToURL:url options:NSDataWritingWithoutOverwriting|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
        chmod(url.fileSystemRepresentation,0600);
    }
    if(!XFATCSyncURL(url,error)||!XFATCSyncURL(self.journalURL,error))return NO;
    self.deletedFileBackupURL=[self.journalURL URLByAppendingPathComponent:file[@"snapshot"]];
    self.deletionAbsenceConfirmed=[file[@"targetAbsenceConfirmed"] boolValue];
    self.journal[@"knownFile"][@"deleteReceiptWritten"]=@YES;
    return [self saveJournal:@"committed deletion receipt and original retained durably" error:error];
}
- (void)loadLatestDeletedBackup {
    self.deletedFileBackupURL=nil;self.deletionAbsenceConfirmed=NO;
    NSArray<NSURL *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.journalURL includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSDictionary *latest=nil;
    for(NSURL *url in files) {
        if(![url.lastPathComponent hasPrefix:@"deleted-"]||![url.pathExtension isEqual:@"plist"])continue;
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:NULL];
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||[attributes[NSFileSize] unsignedLongLongValue]>32768)continue;
        NSData *data=[NSData dataWithContentsOfURL:url options:0 error:NULL];
        id value=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL]:nil;
        if(![self validDeleteReceipt:value name:url.lastPathComponent])continue;
        if(!latest||[value[@"deletedAt"] compare:latest[@"deletedAt"]]==NSOrderedDescending)latest=value;
    }
    if(latest&&[self validatedLocalOriginal:latest error:NULL]) {
        self.deletedFileBackupURL=[self.journalURL URLByAppendingPathComponent:latest[@"snapshot"]];
        self.deletionAbsenceConfirmed=[latest[@"targetAbsenceConfirmed"] boolValue];
    }
}
- (BOOL)returnKnownOriginal:(NSError **)error requireDestinationAbsent:(BOOL)requireDestinationAbsent {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    if(requireDestinationAbsent) {
        BOOL destinationMissing=NO;
        [self info:[self knownFileDestination] missing:&destinationMissing error:error];
        if(!destinationMissing){
            if(error&&!*error)*error=XFATCError(2225,@"La ruta de la app ya contiene un objeto; no se restaurará encima de contenido nuevo.");
            return NO;
        }
    }
    file[@"returnOriginalIntent"]=@YES;
    if(![self saveJournal:@"return original file to application" error:error]||
       ![self runKnownFilePairs:[self knownFilePair:2 destination:[self knownFileDestination]] error:error]||
       ![self waitKnownFile:file[@"Original"] missing:YES error:error])return NO;
    file[@"originalReturned"]=@YES;
    return [self saveJournal:@"original source positively absent after return" error:error];
}
- (BOOL)returnKnownReplacement:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    if(![file[@"newVerified"] boolValue])return NO;
    file[@"returnNewIntent"]=@YES;
    if(![self saveJournal:@"return verified replacement file" error:error]||
       ![self runKnownFilePairs:[self knownFilePair:4 destination:[self knownFileDestination]] error:error]||
       ![self waitKnownFile:file[@"Verify"] missing:YES error:error])return NO;
    file[@"committed"]=@YES;
    return [self saveJournal:@"verified replacement source positively absent; committed" error:error];
}
- (void)recordKnownFileStage:(NSString *)stage error:(NSError *)error {
    NSDictionary *file=self.journal[@"knownFile"];
    self.fileOperationDiagnostics=@{@"operation":file[@"operation"]?:@"Unknown",@"stage":stage,
        @"code":@(error.code),@"originalCaptured":file[@"originalCaptured"]?:@NO,
        @"originalReturned":file[@"originalReturned"]?:@NO,@"replacementVerified":file[@"newVerified"]?:@NO,
        @"committed":file[@"committed"]?:@NO,
        @"targetAbsenceConfirmed":file[@"targetAbsenceConfirmed"]?:@NO};
}
- (NSError *)knownFilePending:(NSString *)message {
    NSDictionary *file=self.journal[@"knownFile"];
    BOOL committedDelete=[self validKnownFileJournal:self.journal]&&
        [file[@"operation"] isEqual:@"delete"]&&[file[@"committed"] boolValue];
    return [NSError errorWithDomain:@"XitForge.ATCDirectory" code:2210
        userInfo:@{NSLocalizedDescriptionKey:message,@"KnownFileRecoveryPending":@YES,
            @"KnownFileDeleteCommitted":@(committedDelete)}];
}
- (BOOL)prepareKnownFile:(NSString *)target operation:(NSString *)operation error:(NSError **)error {
    self.protocolEvents=[NSMutableArray new];self.protocolPhase=@"KnownFileRecovery";
    self.syncAttempts=[NSMutableArray new];self.atcSyncAttempt=0;self.atcMoveAttempted=NO;
    self.fileOperationDiagnostics=nil;self.grappaParameters=nil;self.servicePorts=[NSMutableDictionary new];
    self.appDirectoryFailure=nil;self.temporaryDirectoryFailure=nil;self.generatedAppLinkProbe=nil;
    if(![self recoverPendingTransaction:error]||![self openAFC:error])return NO;
    if(![[NSFileManager defaultManager] createDirectoryAtURL:self.journalURL withIntermediateDirectories:YES
        attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error])return NO;
    chmod(self.journalURL.fileSystemRepresentation,0700);
    NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
    NSString *source=[@"xf_atc_src_" stringByAppendingString:token],*link=[@"xf_atc_link_" stringByAppendingString:token],
             *backup=[@"xf_atc_state_" stringByAppendingString:token];
    for(NSString *name in @[source,link,backup]){
        BOOL missing=NO;NSDictionary *info=[self info:name missing:&missing error:error];
        if(info||!missing){if(error&&!*error)*error=XFATCError(2134,@"Uno de los nombres temporales ya existe; no se inició la operación.");return NO;}}
    NSString *tail=[target.stringByDeletingLastPathComponent substringFromIndex:1];
    NSMutableDictionary *file=[NSMutableDictionary dictionaryWithDictionary:@{
        @"operation":operation,@"target":target,@"snapshot":[token stringByAppendingString:@"-original.bin"],
        @"Original":[backup stringByAppendingPathComponent:@"FileOriginal"],
        @"Incoming":[backup stringByAppendingPathComponent:@"FileIncoming"],
        @"Verify":[backup stringByAppendingPathComponent:@"FileVerify"],
        @"originalMoveIntent":@NO,@"originalObserved":@NO,@"originalCaptured":@NO,@"returnOriginalIntent":@NO,@"originalReturned":@NO,
        @"incomingPlaceIntent":@NO,@"verifyMoveIntent":@NO,@"newVerified":@NO,@"returnNewIntent":@NO,@"committed":@NO}];
    if([operation isEqual:@"delete"]) {
        file[@"targetAbsenceConfirmed"]=@NO;file[@"deleteReceiptWritten"]=@NO;
    }
    self.journal=[NSMutableDictionary dictionaryWithDictionary:@{
        @"version":@1,@"archiveProfile":@"3105-directory-v1",@"token":token,@"namespace":self.journalURL.lastPathComponent,
        @"rsdUUID":self.deviceID,@"source":source,@"link":link,@"backup":backup,@"tail":tail,
        @"identifier":[NSString stringWithFormat:@"../../%@/p0/p1/p2/link",source],
        @"createdAt":[NSDate date],@"booksRestored":@NO,@"cleanupComplete":@NO,@"knownFile":file}];
    NSMutableArray *rows=[NSMutableArray new];NSUInteger item=0;
    for(NSString *identifier in [self knownFileAssetIDs:self.journal])
        [rows addObject:@{@"Persistent ID":identifier,@"Item ID":@(++item),@"DSID":@"1"}];
    self.journal[@"fileManifest"]=@{@"Books":rows};
    if(![self snapshotBooks:error]||![self makeOwnedDirectory:backup error:error])return NO;
    NSData *owner=XFATCPlist(self.ownerRecord,error);
    if(!owner||![self writeOwned:owner path:[backup stringByAppendingPathComponent:@"owner.plist"] error:error])return NO;
    NSString *working=[backup stringByAppendingPathComponent:@"WorkingBooks"];
    if(![self makeOwnedDirectory:working error:error]||
       ![self writeOwned:owner path:[working stringByAppendingPathComponent:@"XitForgeOwner.plist"] error:error]||
       ![self makeOwnedDirectory:[working stringByAppendingPathComponent:@"Sync"] error:error])return NO;
    NSData *books=XFATCPlist(XFATCBooksManifest(self.journal),error);
    if(!books||![self writeOwned:books path:[working stringByAppendingPathComponent:@"Sync/Books.plist"] error:error])return NO;
    if([self.journal[@"booksOriginallyPresent"] boolValue]){
        if(![self preimageMatches:@"Books" error:error])return NO;
    }else {
        BOOL absent=NO;[self info:@"Books" missing:&absent error:error];
        if(!absent){if(error&&!*error)*error=XFATCError(2144,@"Books apareció antes de preparar el archivo; no se alteró.");return NO;}
    }
    self.journal[@"booksIsolationStarted"]=@YES;
    if(![self saveJournal:@"isolate Books for known-file transaction" error:error])return NO;
    if([self.journal[@"booksOriginallyPresent"] boolValue]&&![self renameOwned:@"Books" to:[backup stringByAppendingPathComponent:@"Books"] error:error])return NO;
    NSData *metadata=XFATCPlist(@{@"Version":@2},error);uint8_t *bytes=NULL;size_t length=0;
    if(!metadata||xf_atc_build_directory_zip(tail.UTF8String,metadata.bytes,metadata.length,&bytes,&length)){
        if(error&&!*error)*error=XFATCError(2136,@"No se pudo preparar el enlace del archivo.");return NO;}
    NSData *archive=[[NSData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:YES];
    if([operation isEqual:@"replace"]&&self.batchActive)[self recordBatchSetupPhase:4];
    if(![self stageZip:archive error:error]||![self makeOwnedDirectory:@"Airlock" error:error]||
       ![self makeOwnedDirectory:@"Airlock/Book" error:error]||![self renameOwned:working to:@"Books" error:error]||
       ![self runATC:error])return NO;
    if([operation isEqual:@"replace"]&&self.batchActive)[self recordBatchSetupPhase:6];
    [self recordKnownFileStage:@"Prepared" error:nil];return YES;
}
- (BOOL)observeKnownOriginal:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    NSError *probeError=nil;BOOL absent=NO;
    NSDictionary *preflight=[self info:[self knownFileDestination] missing:&absent error:&probeError];
    if(absent|| (preflight&&![preflight[@"kind"] isEqual:@"S_IFREG"])){
        if(error)*error=XFATCError(2221,absent?@"No existe un archivo en la ruta indicada. No se movió el destino.":@"La ruta indicada no es un archivo regular. No se movió el destino.");return NO;}
    if(!preflight&&probeError&&!(probeError.code==106&&[probeError.userInfo[@"NativeSubcode"] integerValue]==10)){
        if(error)*error=probeError;return NO;}
    file[@"originalMoveIntent"]=@YES;
    if(![self saveJournal:@"move known original into owned Media backup" error:error]||
       ![self runKnownFilePairs:[self knownFilePair:1 destination:file[@"Original"]] error:error]||
       ![self waitKnownFile:file[@"Original"] missing:NO error:error])return NO;
    BOOL missing=NO;NSDictionary *info=[self info:file[@"Original"] missing:&missing error:error];
    if(!info)return NO;
    file[@"originalObserved"]=@YES;file[@"originalInfo"]=info;
    return [self saveJournal:@"known original observed in owned backup" error:error];
}
- (BOOL)writeKnownIncoming:(NSData *)data error:(NSError **)error {
    NSString *path=self.journal[@"knownFile"][@"Incoming"];
    BOOL absent=NO;[self info:path missing:&absent error:error];
    if(!absent)return NO;
    if(![self saveJournal:@"create owned incoming file" error:error])return NO;
    AfcFileHandle *handle=NULL;
    if(!XFATCConsume(afc_file_open(_afc,path.UTF8String,AfcWrOnly,&handle),@"Preparar los bytes nuevos",error)||!handle)return NO;
    BOOL ok=YES;NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:60];
    for(NSUInteger offset=0;offset<data.length;){
        if(deadline.timeIntervalSinceNow<=0){if(error)*error=XFATCError(2211,@"La preparación del archivo superó el tiempo de espera.");ok=NO;break;}
        NSUInteger count=MIN((NSUInteger)65536,data.length-offset);
        if(!XFATCConsume(afc_file_write(handle,(const uint8_t *)data.bytes+offset,count),@"Preparar los bytes nuevos",error)){ok=NO;break;}
        offset+=count;
    }
    NSError *closeError=nil;
    if(!XFATCConsume(afc_file_close(handle),@"Cerrar el archivo nuevo",&closeError)){if(ok&&error)*error=closeError;ok=NO;}
    if(!ok)return NO;
    NSData *observed=[self readKnownStage:path limit:64u*1024u*1024u error:error];
    if(![observed isEqual:data]){if(error&&!*error)*error=XFATCError(2212,@"Los bytes preparados no coinciden con el archivo elegido.");return NO;}
    return YES;
}
- (BOOL)restoreBatchLinkForAutomaticRecovery:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    if(![file[@"batchLinkReset"] boolValue])return YES;
    NSString *external=self.journal[@"link"];
    NSString *staged=[self.journal[@"source"] stringByAppendingPathComponent:@"p0/p1/p2/link"];
    BOOL externalMissing=NO;NSDictionary *externalInfo=[self info:external missing:&externalMissing error:error];
    if(externalInfo&&!externalMissing) {
        if(![externalInfo[@"kind"] isEqual:@"S_IFLNK"]||
           ![externalInfo[@"linkTarget"] isEqual:[@"../../../" stringByAppendingString:self.journal[@"tail"]]]){
            if(error&&!*error)*error=XFATCError(2226,@"El enlace temporal de recuperación cambió; se conservaron todos los objetos.");return NO;
        }
        return YES;
    }
    if(!externalMissing)return NO;
    BOOL stagedMissing=NO;NSDictionary *stagedInfo=[self info:staged missing:&stagedMissing error:error];
    if(!stagedInfo||stagedMissing||![stagedInfo[@"kind"] isEqual:@"S_IFLNK"]||
       ![stagedInfo[@"linkTarget"] isEqual:[@"../../../" stringByAppendingString:self.journal[@"tail"]]]){
        if(error&&!*error)*error=XFATCError(2226,@"El enlace temporal de recuperación no se puede rearmar de forma segura.");return NO;
    }
    return [self renameOwned:staged to:external error:error]&&[self verifyKnownTargetLink:error];
}
- (BOOL)discardKnownIncomingForAutomaticRecovery:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    BOOL missing=NO;NSDictionary *info=[self info:file[@"Incoming"] missing:&missing error:error];
    if(missing)return YES;
    if(!info||![info[@"kind"] isEqual:@"S_IFREG"]||!XFATCHash(file[@"newDigest"])){
        if(error&&!*error)*error=XFATCError(2227,@"El archivo nuevo pendiente no tiene una identidad verificable; se conservaron los datos.");return NO;
    }
    NSData *bytes=[self readKnownStage:file[@"Incoming"] limit:64u*1024u*1024u error:error];
    if(!bytes||![XFATCDigest(bytes) isEqual:file[@"newDigest"]]){
        if(error&&!*error)*error=XFATCError(2227,@"El archivo nuevo pendiente cambió; se conservaron los datos para revisión.");return NO;
    }
    if(![self removeOwned:file[@"Incoming"] expectedKind:@"S_IFREG" error:error])return NO;
    file[@"incomingPlaceIntent"]=@NO;
    return [self saveJournal:@"discard verified staged replacement before automatic original recovery" error:error];
}
- (BOOL)recoverKnownFile:(BOOL)explicitRestore error:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    if(!file)return YES;
    if([file[@"operation"] isEqual:@"create"]) {
        if(![self validKnownFileJournal:self.journal]) return NO;
        if([file[@"committed"] boolValue]) return YES;
        BOOL missing=NO;
        NSDictionary *info=[self info:file[@"Verify"] missing:&missing error:error];
        if(!info && !missing) return NO;
        if(info) {
            NSData *bytes=[self readKnownStage:file[@"Verify"] limit:64u*1024u*1024u error:error];
            if(!bytes || ![XFATCDigest(bytes) isEqual:file[@"newDigest"]]) return NO;
            file[@"newVerified"]=@YES;
            if(![self saveJournal:@"resume verified created file" error:error]) return NO;
            return [self returnKnownReplacement:error];
        }
        if([file[@"newVerified"] boolValue] && [file[@"returnNewIntent"] boolValue]) {
            BOOL incomingMissing=NO;
            [self info:file[@"Incoming"] missing:&incomingMissing error:error];
            if(!incomingMissing)return NO;
            file[@"committed"]=@YES;
            return [self saveJournal:@"created file return confirmed after reconnect" error:error];
        }
        if([file[@"incomingPlaceIntent"] boolValue]) {
            if(error)*error=[self knownFilePending:@"La creación quedó sin confirmar. Se conservaron los datos para recuperación; no se sobrescribirá la ruta."];
            return NO;
        }
        NSDictionary *incoming=[self info:file[@"Incoming"] missing:&missing error:error];
        if(!incoming && !missing) return NO;
        if(incoming) {
            NSData *bytes=[self readKnownStage:file[@"Incoming"] limit:64u*1024u*1024u error:error];
            if(!bytes || ![XFATCDigest(bytes) isEqual:file[@"newDigest"]]) return NO;
            if(![self removeOwned:file[@"Incoming"] expectedKind:@"S_IFREG" error:error]) return NO;
        }
        return YES;
    }
    if([file[@"operation"] isEqual:@"createProbe"]) {
        if(![self validKnownFileJournal:self.journal])return NO;
        // Recovery never writes to or deletes the app target. Only staged bytes
        // matching this generated marker may be removed from our owned area.
        BOOL absent=NO;
        [self info:file[@"Original"] missing:&absent error:error];
        if(!absent){if(error&&!*error)*error=XFATCError(2240,@"Hay un objeto inesperado en el respaldo de la prueba. Se conservó.");return NO;}
        NSData *expected=XFProbeContents(file[@"target"]);
        for(NSString *key in @[@"Incoming",@"Verify"]) {
            BOOL missing=NO;NSDictionary *info=[self info:file[key] missing:&missing error:error];
            if(missing)continue;
            if(!info)return NO;
            NSData *bytes=[self readKnownStage:file[key] limit:1024 error:error];
            if(![bytes isEqual:expected]) {
                // Retain partial or unexpected staging; never delete unknown bytes.
                self.lastWarning=@"Se conservaron temporales de una prueba incompleta.";
                continue;
            }
            if(![self removeOwned:file[key] expectedKind:@"S_IFREG" error:error])return NO;
        }
        return YES;
    }
    if(![file[@"originalMoveIntent"] boolValue])return YES; // No app-file movement was authorized.
    if(![self validKnownFileJournal:self.journal])return NO;
    BOOL committedDelete=[file[@"operation"] isEqual:@"delete"]&&[file[@"committed"] boolValue];
    if(committedDelete&&explicitRestore) {
        if(error)*error=XFATCError(2224,@"Este archivo se retiró intencionalmente. Su copia sigue conservada; esta acción no volverá a crearlo en la app.");return NO;
    }
    BOOL originalMissing=NO,verifyMissing=NO,incomingMissing=NO;
    NSDictionary *original=[self info:file[@"Original"] missing:&originalMissing error:error];
    if(!original&&!originalMissing)return NO;
    NSDictionary *verify=[self info:file[@"Verify"] missing:&verifyMissing error:error];
    if(!verify&&!verifyMissing)return NO;
    NSDictionary *incoming=[self info:file[@"Incoming"] missing:&incomingMissing error:error];
    if(!incoming&&!incomingMissing)return NO;
    if([file[@"operation"] isEqual:@"replace"] && ![file[@"committed"] boolValue] &&
       [file[@"newVerified"] boolValue] && verify && incomingMissing) {
        NSData *bytes=[self readKnownStage:file[@"Verify"] limit:64u*1024u*1024u error:error];
        if(!bytes || ![XFATCDigest(bytes) isEqual:file[@"newDigest"]])return NO;
        if(![self restoreBatchLinkForAutomaticRecovery:error] ||
           ![self publishKnownManifestForBatch:NO error:error] ||
           ![self returnKnownReplacement:error])return NO;
        verify=nil;verifyMissing=YES;
    }
    XFATCFilePresence targetPresence=XFATCFilePresenceUnknown;
    if(![file[@"operation"] isEqual:@"delete"]) {
        if(![self restoreBatchLinkForAutomaticRecovery:error] || ![self verifyKnownTargetLink:error])return NO;
        BOOL targetMissing=NO;NSError *targetError=nil;
        NSDictionary *targetInfo=[self info:[self knownFileDestination] missing:&targetMissing error:&targetError];
        if(!targetInfo && !targetMissing &&
           !(targetError.code==106 && [targetError.userInfo[@"NativeSubcode"] integerValue]==10)) {
            if(error)*error=targetError;return NO;
        }
        // PermDenied leaves the protected destination Unknown. A verified
        // return plus missing owned sources still permits closing a committed
        // transaction; it never permits treating this destination as absent.
        targetPresence=targetMissing?XFATCFilePresenceMissing:
            (targetInfo?XFATCFilePresencePresent:XFATCFilePresenceUnknown);
        BOOL safeOriginalReturn=[file[@"operation"] isEqual:@"read"]||[file[@"operation"] isEqual:@"replace"];
        safeOriginalReturn=safeOriginalReturn&&[file[@"originalCaptured"] boolValue]&&
            [file[@"originalMoveIntent"] boolValue]&&![file[@"originalReturned"] boolValue]&&
            original&&[original[@"kind"] isEqual:@"S_IFREG"]&&
            verifyMissing&&targetMissing&&! [file[@"newVerified"] boolValue]&&
            ![file[@"returnNewIntent"] boolValue]&&! [file[@"committed"] boolValue];
        if(safeOriginalReturn) {
            NSData *originalBytes=[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:error];
            safeOriginalReturn=originalBytes&&[XFATCDigest(originalBytes) isEqual:file[@"originalDigest"]];
            if(!incomingMissing&&safeOriginalReturn)safeOriginalReturn=[self discardKnownIncomingForAutomaticRecovery:error];
            if(safeOriginalReturn)safeOriginalReturn=[self restoreBatchLinkForAutomaticRecovery:error];
        }
        if(safeOriginalReturn) {
            if(![self returnKnownOriginal:error requireDestinationAbsent:YES])return NO;
            [self recordKnownFileStage:@"OriginalAutoRestored" error:nil];
            return YES;
        }
    }
    if(committedDelete) {
        NSData *local=[self validatedLocalOriginal:file error:error];
        NSData *remote=original?[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:error]:nil;
        XFATCFileRecoveryObservation observation={
            .operation=XFATCFileRecoveryDelete,
            .original=remote&&[XFATCDigest(remote) isEqual:file[@"originalDigest"]]?XFATCFilePresencePresent:XFATCFilePresenceUnknown,
            .incoming=incomingMissing?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,
            .verify=verifyMissing?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,
            .target=XFATCFilePresenceUnknown,.originalCaptured=local!=nil,.committed=true};
        if(XFATCClassifyFileRecovery(observation)!=XFATCFileRecoveryDeleteCommitted) {
            if(error&&!*error)*error=[self knownFilePending:@"El retiro ya se confirmó, pero su respaldo requiere revisión. Se conservaron los datos y no se restaurará el archivo automáticamente."];return NO;
        }
        // Retained deletion deliberately keeps both originals and never sends
        // a FileComplete return, even during reconnect or explicit recovery.
        return [self publishDeleteReceipt:error];
    }
    if([file[@"originalReturned"] boolValue]&&originalMissing){
        if([file[@"operation"] isEqual:@"read"]&&[file[@"originalCaptured"] boolValue]){
            XFATCFileRecoveryObservation observation={
                .operation=XFATCFileRecoveryRead,.original=XFATCFilePresenceMissing,
                .incoming=incomingMissing?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,
                .verify=verifyMissing?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,
                .target=targetPresence,.originalCaptured=true,.returnOriginalIntent=true};
            if(XFATCClassifyFileRecovery(observation)!=XFATCFileRecoveryReadReturnConfirmed){
                if(error)*error=[self knownFilePending:@"El retorno del original requiere revisión: se conservaron los objetos de recuperación."];return NO;}
        }
        return YES;
    }
    // A return can complete before its final journal update. Only positive
    // absence on a healthy AFC connection is evidence of source disappearance.
    if([file[@"returnOriginalIntent"] boolValue]&&[file[@"originalObserved"] boolValue]&&originalMissing){
        file[@"originalReturned"]=@YES;return [self saveJournal:@"original return confirmed after reconnect" error:error];}
    if([file[@"newVerified"] boolValue]&&[file[@"returnNewIntent"] boolValue]&&verifyMissing&&incomingMissing){
        file[@"committed"]=@YES;
        if(![self saveJournal:@"verified replacement return confirmed after reconnect" error:error])return NO;
    }
    if([file[@"committed"] boolValue]){
        if(![file[@"originalCaptured"] boolValue]||!XFATCHash(file[@"originalDigest"]))return NO;
        NSURL *backup=[self.journalURL URLByAppendingPathComponent:file[@"snapshot"]];
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:backup.path error:error];
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||
           [attributes[NSFileSize] unsignedLongLongValue]!=[file[@"originalSize"] unsignedLongLongValue])return NO;
        NSData *local=[NSData dataWithContentsOfURL:backup options:0 error:error];
        if(!local||![XFATCDigest(local) isEqual:file[@"originalDigest"]])return NO;
        if(original){
            NSData *bytes=[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:error];
            if(!bytes||![XFATCDigest(bytes) isEqual:file[@"originalDigest"]])return NO;
        }
        XFATCFileRecoveryObservation observation={
            .operation=XFATCFileRecoveryReplace,
            .original=originalMissing?XFATCFilePresenceMissing:XFATCFilePresencePresent,
            .incoming=incomingMissing?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,
            .verify=verifyMissing?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,
            .target=targetPresence,.originalCaptured=true,
            .replacementVerified=[file[@"newVerified"] boolValue],.placementIntent=[file[@"incomingPlaceIntent"] boolValue],
            .returnReplacementIntent=[file[@"returnNewIntent"] boolValue],.committed=true};
        if(XFATCClassifyFileRecovery(observation)!=XFATCFileRecoveryWriteCommitted){
            if(error)*error=[self knownFilePending:@"No se confirmó el estado final del reemplazo; el respaldo original sigue conservado."];return NO;}
        if(original){
            if(![self removeOwned:file[@"Original"] expectedKind:@"S_IFREG" error:error])return NO;
        }
        return YES;
    }
    if(explicitRestore&&original){
        if(![@[@"S_IFREG",@"S_IFDIR",@"S_IFLNK"] containsObject:original[@"kind"]])return NO;
        if([file[@"originalCaptured"] boolValue]){
            NSData *bytes=[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:error];
            if(!bytes||![XFATCDigest(bytes) isEqual:file[@"originalDigest"]])return NO;
        }else {
            file[@"originalObserved"]=@YES;file[@"originalInfo"]=original;
            if(![self saveJournal:@"original observed for explicit restore" error:error])return NO;
        }
        // This path is reached only by the dedicated, user-confirmed restore
        // action, whose UI identifies the destination and requires its app closed.
        return [self returnKnownOriginal:error requireDestinationAbsent:NO];
    }
    self.lastWarning=@"Hay una recuperación pendiente. Se conservaron el original y el estado; XitForge volverá a intentarla automáticamente cuando la ruta sea segura.";
    [self recordKnownFileStage:@"RecoveryPending" error:nil];
    if(error)*error=[self knownFilePending:self.lastWarning];return NO;
}
- (BOOL)finishKnownFileWithError:(NSError **)error {
    [self closeAFC];
    if(![NSFileManager.defaultManager fileExistsAtPath:self.activeURL.path])return YES;
    NSError *recovery=nil;
    if(![self recoverPendingTransaction:&recovery]){
        if(error){
            NSMutableDictionary *details=[recovery.userInfo mutableCopy]?:[NSMutableDictionary new];
            NSString *prior=(*error).localizedDescription?:@"No se completó la operación.";
            details[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"%@\n\n%@",prior,recovery.localizedDescription?:@"Se conserva la recuperación pendiente."];
            *error=[NSError errorWithDomain:recovery.domain?:@"XitForge.ATCDirectory" code:recovery.code?:2210 userInfo:details];
        }
        return NO;
    }
    return YES;
}
- (NSData *)readAbsoluteFile:(NSString *)path maximumBytes:(NSUInteger)maximumBytes error:(NSError **)error {
    NSString *target=XFATCPath(path);
    if(!target||!XFATCKnownFilePath(target)||!target.UTF8String||
       [target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096||!maximumBytes||maximumBytes>64u*1024u*1024u){
        if(error)*error=XFATCError(2213,@"Introduce una ruta de archivo dentro del contenedor, con un límite de hasta 64 MiB.");return nil;}
    NSError *failure=nil;NSData *data=nil;
    do {
        if(![self prepareKnownFile:target operation:@"read" error:&failure]||![self observeKnownOriginal:&failure])break;
        data=[self readKnownStage:self.journal[@"knownFile"][@"Original"] limit:maximumBytes error:&failure];
        if(data&&![self persistKnownOriginal:data error:&failure])data=nil;
        NSError *returnError=nil;
        if(![self returnKnownOriginal:&returnError requireDestinationAbsent:YES]){data=nil;failure=returnError;break;}
        [self recordKnownFileStage:data?@"ReadReturned":@"ReadFailedOriginalReturned" error:failure];
    }while(0);
    NSString *snapshot=self.journal[@"knownFile"][@"snapshot"];
    if(![self finishKnownFileWithError:&failure])data=nil;
    if(data&&snapshot)[NSFileManager.defaultManager removeItemAtURL:[self.journalURL URLByAppendingPathComponent:snapshot] error:NULL];
    if(!data&&error)*error=failure?:XFATCError(2214,@"No se pudo leer y devolver el archivo; revisa la recuperación pendiente.");
    return data;
}
- (BOOL)replaceAbsoluteFile:(NSString *)path data:(NSData *)data error:(NSError **)error {
    NSString *target=XFATCPath(path);
    if(!target||!XFATCKnownFilePath(target)||!target.UTF8String||
       [target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096||!data||data.length>64u*1024u*1024u){
        if(error)*error=XFATCError(2213,@"El destino debe ser un archivo de la app y el archivo nuevo no puede superar 64 MiB.");return NO;}
    self.batchActive=YES;self.batchLastPhase=0;self.batchEvents=[NSMutableArray new];
    NSError *failure=nil;BOOL ok=NO;
    do {
        if(![self prepareKnownFile:target operation:@"replace" error:&failure])break;
        NSError *absenceError=nil;
        if([self requireProbeDestinationAbsent:&absenceError]) {
            NSMutableDictionary *created=self.journal[@"knownFile"];
            created[@"operation"]=@"create";
            if(![self saveJournal:@"select creation at confirmed missing file" error:&failure])break;
            ok=[self createPreparedFileWithData:data error:&failure];
            break;
        }
        // A denied metadata query is not absence. The existing-file route can
        // still retrieve the original through ATC and verify its replacement.
        if(![self observeKnownOriginal:&failure])break;
        NSMutableDictionary *file=self.journal[@"knownFile"];
        NSData *original=[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:&failure];
        if(!original||![self persistKnownOriginal:original error:&failure])break;
        file[@"newDigest"]=XFATCDigest(data);file[@"newSize"]=@(data.length);
        if(![self saveJournal:@"replacement bytes identified before staging" error:&failure]||![self writeKnownIncoming:data error:&failure])break;

        // The first placement is grouped into one ATC session. The generated
        // link is rearmed into the source tree so the three FileComplete
        // messages use the same manifest that 3105 publishes for replacement.
        file[@"incomingPlaceIntent"]=@YES;
        if(![self saveJournal:@"place replacement into selected application path" error:&failure]||
           ![self rearmBatchLink:&failure])break;
        file[@"batchPlacement"]=@YES;
        if(![self publishKnownManifestForBatch:YES error:&failure]||
           ![self runKnownFilePairs:[self batchPlacementPairs] error:&failure]||
           ![self waitKnownFile:file[@"Incoming"] missing:YES error:&failure]||
           ![self waitKnownFile:file[@"Verify"] missing:NO error:&failure])break;

        NSData *observed=[self readKnownStage:file[@"Verify"] limit:64u*1024u*1024u error:&failure];
        if(![observed isEqual:data]){if(!failure)failure=XFATCError(2215,@"La verificación del reemplazo no coincide. Se conservaron el original y los datos recuperados.");break;}
        file[@"newVerified"]=@YES;
        if(![self saveJournal:@"replacement bytes verified" error:&failure])break;
        [self recordBatchSetupPhase:10];
        if(![self returnKnownReplacement:&failure]||
           ![self publishKnownManifestForBatch:NO error:&failure])break;
        [self recordKnownFileStage:@"ReplacementCommitted" error:nil];
        ok=YES;
    }while(0);
    if(![self finishKnownFileWithError:&failure])ok=NO;
    if(ok)[self recordBatchSetupPhase:12];
    self.batchActive=NO;
    if(ok){
        NSString *backupNote=@"Reemplazo verificado. La copia original se conservó con su registro de recuperación.";
        self.lastWarning=self.lastWarning.length?[backupNote stringByAppendingFormat:@"\n%@",self.lastWarning]:backupNote;
    }
    if(!ok&&error)*error=failure?:XFATCError(2216,@"El reemplazo no se completó; se conservaron el original y el estado para reintentar la recuperación.");
    return ok;
}
- (BOOL)requireProbeDestinationAbsent:(NSError **)error {
    if(![self verifyKnownTargetLink:error])return NO;
    AfcFileInfo metadata={0};NSError *probeError=nil;
    IdeviceFfiError *native=afc_get_file_info(_afc,[self knownFileDestination].UTF8String,&metadata);
    BOOL returnedError=native!=NULL;
    int code=native?native->code:0,subcode=native?native->sub_code:0;
    afc_file_info_free(&metadata);
    BOOL absent=XFProbeAFCConfirmsAbsence(returnedError,code,subcode,YES,YES);
    if(native) {
        if(absent)idevice_error_free(native);
        else XFATCConsume(native,@"Comprobar si existe el archivo de prueba",&probeError);
    }
    if(!absent) {
        NSString *reason=!returnedError?@"El destino ya existe; no se reemplazará.":
            [NSString stringWithFormat:@"No se pudo comprobar que el destino esté libre. %@",probeError.localizedDescription?:@"Respuesta desconocida."];
        if(error)*error=[NSError errorWithDomain:@"XitForge.ATCDirectory" code:2243
            userInfo:@{NSLocalizedDescriptionKey:reason,@"ProbeInconclusive":@YES,
                       @"UnderlyingCode":@(probeError.code),@"NativeSubcode":probeError.userInfo[@"NativeSubcode"]?:@0}];
        return NO;
    }
    return XFProbeAFCConfirmsAbsence(returnedError,code,subcode,YES,[self verifyKnownTargetLink:error]);
}
- (BOOL)createPreparedFileWithData:(NSData *)data error:(NSError **)error {
    NSMutableDictionary *file=self.journal[@"knownFile"];
    file[@"newDigest"]=XFATCDigest(data);file[@"newSize"]=@(data.length);
    if(![self saveJournal:@"identify Home payload before creation" error:error] ||
       ![self writeKnownIncoming:data error:error])return NO;
    file[@"incomingPlaceIntent"]=@YES;
    if(![self saveJournal:@"place payload at absent application destination" error:error] ||
       ![self runKnownFilePairs:[self knownFilePair:3 destination:[self knownFileDestination]] error:error] ||
       ![self waitKnownFile:file[@"Incoming"] missing:YES error:error])return NO;
    file[@"verifyMoveIntent"]=@YES;
    if(![self saveJournal:@"read back created application file" error:error] ||
       ![self runKnownFilePairs:[self knownFilePair:1 destination:file[@"Verify"]] error:error] ||
       ![self waitKnownFile:file[@"Verify"] missing:NO error:error])return NO;
    NSData *observed=[self readKnownStage:file[@"Verify"] limit:64u*1024u*1024u error:error];
    if(![observed isEqual:data]) {
        if(error&&!*error)*error=XFATCError(2244,@"La lectura de verificación no coincide con el archivo del panel.");return NO;
    }
    file[@"newVerified"]=@YES;
    if(![self saveJournal:@"created Home file verified byte for byte" error:error])return NO;
    return [self returnKnownReplacement:error];
}

- (BOOL)createTestAbsoluteFile:(NSString *)path error:(NSError **)error {
    NSString *target=XFATCPath(path);
    NSData *marker=XFProbeContents(target);
    if(!target||!XFATCKnownFilePath(target)||!marker||[target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096) {
        if(error)*error=XFATCError(2241,@"La prueba requiere una ruta válida y un nombre xitforge_prueba_UUID.txt generado por la app.");return NO;
    }
    NSError *failure=nil;BOOL verified=NO,ok=NO;NSString *stage=@"Preparar servicio";
    do {
        if(![self prepareKnownFile:target operation:@"createProbe" error:&failure])break;
        stage=@"Comprobar destino libre";
        if(![self requireProbeDestinationAbsent:&failure])break;
        NSMutableDictionary *file=self.journal[@"knownFile"];
        file[@"newDigest"]=XFATCDigest(marker);file[@"newSize"]=@(marker.length);
        stage=@"Preparar archivo de prueba";
        if(![self saveJournal:@"identify generated creation probe before staging" error:&failure]||
           ![self writeKnownIncoming:marker error:&failure])break;
        file[@"incomingPlaceIntent"]=@YES;stage=@"Crear archivo en la app";
        if(![self saveJournal:@"create fresh marker at checked absent destination" error:&failure]||
           ![self runKnownFilePairs:[self knownFilePair:3 destination:[self knownFileDestination]] error:&failure]||
           ![self waitKnownFile:file[@"Incoming"] missing:YES error:&failure])break;
        file[@"verifyMoveIntent"]=@YES;stage=@"Leer la misma ruta y comparar";
        if(![self saveJournal:@"read generated marker back from application path" error:&failure]||
           ![self runKnownFilePairs:[self knownFilePair:1 destination:file[@"Verify"]] error:&failure]||
           ![self waitKnownFile:file[@"Verify"] missing:NO error:&failure])break;
        NSData *observed=[self readKnownStage:file[@"Verify"] limit:1024 error:&failure];
        if(![observed isEqual:marker]) {
            if(!failure)failure=XFATCError(2244,@"El contenido leído desde la app no coincide con la prueba. No se declara éxito.");break;
        }
        verified=YES;file[@"newVerified"]=@YES;stage=@"Devolver archivo comprobado a la app";
        if(![self saveJournal:@"new app file read-back verified byte for byte" error:&failure]||
           ![self returnKnownReplacement:&failure])break;
        ok=YES;stage=@"Creación y lectura verificadas";
    }while(0);
    [self recordKnownFileStage:stage error:failure];
    if(![self finishKnownFileWithError:&failure]){ok=NO;stage=@"Recuperar estado temporal";}
    self.fileOperationDiagnostics=@{@"operation":@"createProbe",@"stage":stage,@"code":@(failure.code),
        @"readBackVerified":@(verified),@"completed":@(ok),@"targetNameGenerated":@YES};
    if(!ok&&error) {
        NSMutableDictionary *details=[failure.userInfo mutableCopy]?:[NSMutableDictionary new];
        details[@"ProbeStage"]=stage;details[@"ProbeReadBackVerified"]=@(verified);
        details[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"Etapa: %@\n%@%@",stage,
            failure.localizedDescription?:@"El servicio no confirmó el resultado.",
            verified?@"\nLa creación y la lectura sí se comprobaron, pero el cierre de la prueba quedó incompleto.":@"\nResultado inconcluso: esto no demuestra que todas las formas de creación estén bloqueadas."];
        *error=[NSError errorWithDomain:failure.domain?:@"XitForge.ATCDirectory" code:failure.code?:2245 userInfo:details];
    }
    return ok;
}
- (BOOL)verifyKnownTargetLink:(NSError **)error {
    BOOL missing=NO;
    NSDictionary *info=[self info:self.journal[@"link"] missing:&missing error:error];
    NSString *expected=[@"../../../" stringByAppendingString:self.journal[@"tail"]];
    if(!info||missing||![info[@"kind"] isEqual:@"S_IFLNK"]||![info[@"linkTarget"] isEqual:expected]) {
        if(error&&!*error)*error=XFATCError(2228,@"No se pudo comprobar el enlace hacia la app. No se declarará que el archivo esté ausente.");return NO;
    }
    return YES;
}
- (BOOL)knownTargetAbsenceAfterMove:(BOOL *)confirmed error:(NSError **)error {
    if(confirmed)*confirmed=NO;
    if(![self verifyKnownTargetLink:error])return NO;
    AfcFileInfo info={0};
    IdeviceFfiError *failure=afc_get_file_info(_afc,[self knownFileDestination].UTF8String,&info);
    @try {
        if(failure&&failure->code==106&&(failure->sub_code==8||failure->sub_code==10)) {
            BOOL targetMissing=failure->sub_code==8;
            // A missing generated link can produce the same AFC 106/8 as a
            // missing file. Verify its exact target on both sides of the probe.
            if(![self verifyKnownTargetLink:error])return NO;
            if(confirmed)*confirmed=targetMissing;
            return YES; // Permission denial remains Unknown, never absence.
        }
        if(failure) {
            IdeviceFfiError *consumed=failure;failure=NULL;
            return XFATCConsume(consumed,@"Comprobar la ruta después del traslado",error);
        }
        if(error)*error=XFATCError(2225,@"iOS todavía informa un objeto en el destino. No se confirmó el retiro; se conservó el original para recuperación.");
        return NO;
    } @finally {
        afc_file_info_free(&info);
        if(failure)idevice_error_free(failure);
    }
}
- (BOOL)deleteAbsoluteFile:(NSString *)path error:(NSError **)error {
    return [self deleteAbsoluteFile:path expectedProbe:nil error:error];
}
- (BOOL)deleteTestAbsoluteFile:(NSString *)path error:(NSError **)error {
    NSData *marker=XFProbeContents(path);
    if(!marker){if(error)*error=XFATCError(2241,@"El destino no identifica un archivo de prueba de XitForge.");return NO;}
    return [self deleteAbsoluteFile:path expectedProbe:marker error:error];
}
- (BOOL)deleteAbsoluteFile:(NSString *)path expectedProbe:(NSData *)expected error:(NSError **)error {
    self.deletedFileBackupURL=nil;self.deletionAbsenceConfirmed=NO;
    NSString *target=XFATCPath(path);
    if(!target||!XFATCKnownFilePath(target)||!target.UTF8String||[target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096) {
        if(error)*error=XFATCError(2213,@"Elige la ruta de un archivo dentro de la app. No se pueden eliminar carpetas.");return NO;
    }
    NSError *failure=nil;BOOL ok=NO,committedCurrent=NO,currentAbsence=NO,alreadyAbsent=NO;
    NSURL *currentBackupURL=nil;
    NSDictionary *currentOriginalRecord=nil;
    do {
        if(![self prepareKnownFile:target operation:@"delete" error:&failure])break;
        // Preparation can load a historical receipt during automatic recovery.
        // It must never become the backup reported for this new destination.
        self.deletedFileBackupURL=nil;self.deletionAbsenceConfirmed=NO;
        if(expected) {
            BOOL confirmed=NO;NSError *absenceError=nil;
            if([self knownTargetAbsenceAfterMove:&confirmed error:&absenceError]&&confirmed) {
                alreadyAbsent=YES;ok=YES;break;
            }
        }
        if(![self observeKnownOriginal:&failure])break;
        NSMutableDictionary *file=self.journal[@"knownFile"];
        NSData *original=[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:&failure];
        if(!original||![self persistKnownOriginal:original error:&failure])break;
        if(expected&&![original isEqual:expected]) {
            failure=XFATCError(2242,@"El contenido ya no coincide con la prueba. No se confirmó la eliminación; se conservó el original para una recuperación segura.");
            break;
        }
        BOOL absence=NO;
        if(![self knownTargetAbsenceAfterMove:&absence error:&failure])break;
        BOOL incomingMissing=NO,verifyMissing=NO;
        [self info:file[@"Incoming"] missing:&incomingMissing error:&failure];
        if(!incomingMissing)break;
        [self info:file[@"Verify"] missing:&verifyMissing error:&failure];
        if(!verifyMissing)break;
        // Recheck the staged original after the durable snapshot and target
        // probes. A changed backup must remain pending, never committed.
        NSData *freshOriginal=[self readKnownStage:file[@"Original"] limit:64u*1024u*1024u error:&failure];
        if(!freshOriginal)break;
        if(freshOriginal.length!=[file[@"originalSize"] unsignedLongLongValue]||
           ![XFATCDigest(freshOriginal) isEqual:file[@"originalDigest"]]) {
            failure=XFATCError(2229,@"El original cambió antes de confirmar el retiro. Se conservaron los respaldos para recuperación.");break;
        }
        XFATCFileRecoveryObservation observation={.operation=XFATCFileRecoveryDelete,
            .original=XFATCFilePresencePresent,.incoming=XFATCFilePresenceMissing,.verify=XFATCFilePresenceMissing,
            .target=absence?XFATCFilePresenceMissing:XFATCFilePresenceUnknown,.originalCaptured=true,.committed=true};
        if(XFATCClassifyFileRecovery(observation)!=XFATCFileRecoveryDeleteCommitted) {
            failure=XFATCError(2226,@"No se pudo validar el estado del retiro. Se conserva el original para recuperar.");break;
        }
        file[@"targetAbsenceConfirmed"]=@(absence);file[@"deletedAt"]=[NSDate date];file[@"committed"]=@YES;
        if(![self saveJournal:@"intentional retained deletion committed after durable original capture" error:&failure]) {
            // The durable write may be ambiguous. Never authorize an automatic
            // return from this in-memory committed state; recovery reloads disk.
            break;
        }
        self.deletedFileBackupURL=[self.journalURL URLByAppendingPathComponent:file[@"snapshot"]];
        self.deletionAbsenceConfirmed=absence;
        committedCurrent=YES;currentBackupURL=[self.deletedFileBackupURL copy];currentAbsence=absence;
        currentOriginalRecord=@{@"snapshot":file[@"snapshot"],@"originalSize":file[@"originalSize"],@"originalDigest":file[@"originalDigest"]};
        [self recordKnownFileStage:absence?@"DeleteAbsentConfirmed":@"DeleteRelocationRetained" error:nil];
        ok=YES;
    } while(0);
    if(![self finishKnownFileWithError:&failure])ok=NO;
    if(alreadyAbsent) {
        self.deletionAbsenceConfirmed=ok;
        if(!ok&&error)*error=failure;
        return ok;
    }
    BOOL verifiedCurrentBackup=committedCurrent&&[self validatedLocalOriginal:currentOriginalRecord error:NULL]!=nil;
    if(committedCurrent&&!verifiedCurrentBackup) {
        ok=NO;
        if(!failure)failure=XFATCError(2230,@"El retiro se confirmó, pero no se pudo validar la copia local. Se conservó el respaldo remoto para revisión.");
    }
    self.deletedFileBackupURL=verifiedCurrentBackup?currentBackupURL:nil;
    self.deletionAbsenceConfirmed=verifiedCurrentBackup&&currentAbsence;
    if(!ok&&error)*error=failure?:XFATCError(2227,@"El retiro no se completó. Se conserva el estado para recuperación; no se ha declarado que el archivo esté ausente.");
    return ok;
}
- (BOOL)recoverPendingKnownFileAtPath:(NSString *)path error:(NSError **)error {
    NSString *target=XFATCPath(path);
    if(!target){if(error)*error=XFATCError(2213,@"El destino de recuperación no es una ruta válida de app.");return NO;}
    NSData *data=[NSData dataWithContentsOfURL:self.activeURL options:0 error:error];
    id value=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:error]:nil;
    if(![value isKindOfClass:NSMutableDictionary.class]||![self validJournal:value]||
       ![value[@"knownFile"][@"target"] isEqual:target]){
        if(error&&!*error)*error=XFATCError(2217,@"No hay una recuperación válida para esta app y esta ruta. Se conservaron los datos.");return NO;}
    self.journal=value;
    if(![self openAFC:error]||![self verifyRemoteOwner:error]){[self closeAFC];return NO;}
    if([value[@"knownFile"][@"committed"] boolValue]){
        [self closeAFC];
        NSString *message=[value[@"knownFile"][@"operation"] isEqual:@"delete"]?
            @"El archivo ya se retiró intencionalmente y se conservó una copia. Volver a conectar completa la limpieza pendiente sin restaurarlo en la app.":
            @"El reemplazo ya se verificó. El original está respaldado; la recuperación pendiente corresponde al estado temporal de sincronización, no a un original trasladado.";
        if(error)*error=XFATCError(2222,message);return NO;}
    BOOL ok=[self recoverKnownFile:YES error:error];
    [self closeAFC];
    if(ok)ok=[self recoverPendingTransaction:error];
    return ok;
}
- (BOOL)validJournal:(NSDictionary *)journal {
    NSString *token=[journal[@"token"] isKindOfClass:NSString.class]?journal[@"token"]:nil;
    if(!token||![[NSUUID alloc] initWithUUIDString:token]||![journal[@"version"] isEqual:@1])return NO;
    if(![journal[@"namespace"] isEqual:self.journalURL.lastPathComponent])return NO;
    if(journal[@"archiveProfile"]&&![journal[@"archiveProfile"] isEqual:@"3105-directory-v1"])return NO;
    if(![journal[@"source"] isEqual:[@"xf_atc_src_" stringByAppendingString:token]]||
       ![journal[@"link"] isEqual:[@"xf_atc_link_" stringByAppendingString:token]]||
       ![journal[@"backup"] isEqual:[@"xf_atc_state_" stringByAppendingString:token]])return NO;
    NSString *tail=[journal[@"tail"] isKindOfClass:NSString.class]?journal[@"tail"]:nil;
    if(!tail||!XFATCPath([@"/" stringByAppendingString:tail]))return NO;
    if(![journal[@"identifier"] isEqual:[NSString stringWithFormat:@"../../%@/p0/p1/p2/link",journal[@"source"]]])return NO;
    if(journal[@"knownFile"]&&![self validKnownFileJournal:journal])return NO;
    for(NSString *key in @[@"booksOriginallyPresent",@"booksRestored",@"cleanupComplete"])if(![journal[key] isKindOfClass:NSNumber.class])return NO;
    for(NSString *key in @[@"booksIsolationStarted",@"temporaryBooksQuarantined",@"originalRestoredWithChanges",@"deleteBackupRetained",@"booksInPlace",@"inPlaceSyncCreated",@"inPlaceManifestWriteStarted"])if(journal[key]&&![journal[key] isKindOfClass:NSNumber.class])return NO;
    if(![journal[@"booksOriginalInfo"] isKindOfClass:NSDictionary.class])return NO;
    if([journal[@"booksOriginallyPresent"] boolValue]&&![journal[@"booksOriginalInfo"][@"kind"] isEqual:@"S_IFDIR"])return NO;
    if([journal[@"booksOriginallyPresent"] boolValue])for(NSString *key in @[@"size",@"creation",@"mtimeNS"])if(![journal[@"booksOriginalInfo"][key] isKindOfClass:NSNumber.class])return NO;
    if(journal[@"mkdirOwnership"]&&![journal[@"mkdirOwnership"] isKindOfClass:NSDictionary.class])return NO;
    for(NSString *path in journal[@"mkdirOwnership"]) {
        if(![path isEqual:@"Airlock"]&&![path isEqual:@"Airlock/Book"])return NO;
        NSDictionary *row=journal[@"mkdirOwnership"][path];
        if(![row isKindOfClass:NSDictionary.class]||![row[@"creationRequested"] isKindOfClass:NSNumber.class])return NO;
        if(row[@"createdInfo"]&&(![row[@"createdInfo"] isKindOfClass:NSDictionary.class]||![row[@"createdInfo"][@"creation"] isKindOfClass:NSNumber.class]||![row[@"createdInfo"][@"kind"] isEqual:@"S_IFDIR"]))return NO;
    }
    NSDictionary *tracked=[journal[@"trackedPreimage"] isKindOfClass:NSDictionary.class]?journal[@"trackedPreimage"]:nil;
    if(!tracked||tracked.count!=XFATCTrackedFiles().count)return NO;
    for(id key in tracked)if(![XFATCTrackedFiles() containsObject:key])return NO;
    NSUInteger index=0;
    for(NSString *path in XFATCTrackedFiles()) {
        NSDictionary *row=[tracked[path] isKindOfClass:NSDictionary.class]?tracked[path]:nil;
        if(![row[@"exists"] isKindOfClass:NSNumber.class])return NO;
        if(![row[@"exists"] boolValue]&&row.count!=1)return NO;
        if([row[@"exists"] boolValue]) {
            NSString *expected=[NSString stringWithFormat:@"%@-preimage-%lu.bin",token,(unsigned long)index];
            if(![row[@"snapshot"] isEqual:expected]||![row[@"info"] isKindOfClass:NSDictionary.class])return NO;
            if(row[@"snapshotDigest"]&&!XFATCHash(row[@"snapshotDigest"]))return NO;
            if(![row[@"info"][@"kind"] isEqual:@"S_IFREG"])return NO;
            for(NSString *key in @[@"size",@"creation",@"mtimeNS"])if(![row[@"info"][key] isKindOfClass:NSNumber.class])return NO;
            NSDictionary *localInfo=[[NSFileManager defaultManager] attributesOfItemAtPath:[self.journalURL URLByAppendingPathComponent:expected].path error:NULL];
            if(![localInfo[NSFileType] isEqual:NSFileTypeRegular])return NO;
        }
        index++;
    }
    return YES;
}
- (NSDictionary *)ownerRecord {
    return @{@"module":@"XitForgeATCDirectory",@"version":@1,@"token":self.journal[@"token"],@"namespace":self.journal[@"namespace"]};
}
- (BOOL)booksOwnerMatches:(NSString *)root error:(NSError **)error {
    BOOL missing=NO;NSString *path=[root stringByAppendingPathComponent:@"XitForgeOwner.plist"];
    NSDictionary *info=[self info:path missing:&missing error:error];
    if(!info||missing||![info[@"kind"] isEqual:@"S_IFREG"]||[info[@"size"] unsignedIntegerValue]>4096)return NO;
    NSData *bytes=[self readSnapshot:path expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
    id owner=bytes?[NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:error]:nil;
    return [owner isEqual:self.ownerRecord];
}
- (BOOL)verifyRemoteOwner:(NSError **)error {
    // journalURL's namespace is derived by the authenticated backend from the
    // pairing's stable IRK/UDID/certificate identity. RSD UUID is diagnostic:
    // it may change after reboot and must not prevent returning an original.
    if(self.journal[@"knownFile"]&&![self.journal[@"namespace"] isEqual:self.journalURL.lastPathComponent]){
        if(error)*error=XFATCError(2219,@"El registro pertenece a otra identidad de emparejamiento. No se moverán sus datos.");return NO;}
    NSString *backup=self.journal[@"backup"];
    BOOL missing=NO;NSDictionary *info=[self info:backup missing:&missing error:error];
    if(missing)return YES;if(!info)return NO;
    if(![info[@"kind"] isEqual:@"S_IFDIR"]){if(error)*error=XFATCError(2122,@"El respaldo de recuperación tiene un tipo inesperado.");return NO;}
    NSString *owner=[backup stringByAppendingPathComponent:@"owner.plist"];
    info=[self info:owner missing:&missing error:error];
    if(missing){
        NSArray *names=[self names:backup error:error];
        /* Crash between directory creation and marker write: only an empty directory is ours to clear. */
        if(!names||names.count){if(error&&!*error)*error=XFATCError(2123,@"El respaldo tiene contenido pero no se pudo comprobar su propietario.");return NO;}
        return YES;
    }
    if(!info||![info[@"kind"] isEqual:@"S_IFREG"]||[info[@"size"] unsignedIntegerValue]>4096)return NO;
    NSData *bytes=[self readSnapshot:owner expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
    NSDictionary *expected=self.ownerRecord;
    id marker=bytes?[NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:error]:nil;
    if(![marker isEqual:expected]){if(error&&!*error)*error=XFATCError(2124,@"El marcador del respaldo no coincide. No se tocará su contenido.");return NO;}
    return YES;
}
- (BOOL)cleanExactTemporaryBooks:(NSString *)root error:(NSError **)error {
    BOOL missing=NO;NSDictionary *info=[self info:root missing:&missing error:error];
    if(missing)return YES;if(!info||![info[@"kind"] isEqual:@"S_IFDIR"])return NO;
    NSArray *rootNames=[self names:root error:error];
    if(!rootNames)return NO;
    if(!rootNames.count)return[self removeOwned:root expectedKind:@"S_IFDIR" error:error];
    if(![self booksOwnerMatches:root error:error])return NO;
    NSSet *allowed=[NSSet setWithArray:@[@"Sync",@"XitForgeOwner.plist"]];
    for(NSString *name in rootNames)if(![allowed containsObject:name])return NO;
    NSString *sync=[root stringByAppendingPathComponent:@"Sync"];
    info=[self info:sync missing:&missing error:error];
    if(!missing) {
        if(!info||![info[@"kind"] isEqual:@"S_IFDIR"])return NO;
        NSArray *names=[self names:sync error:error];
        if(!names||names.count>1||(names.count&&![names.firstObject isEqual:@"Books.plist"]))return NO;
        NSString *file=[sync stringByAppendingPathComponent:@"Books.plist"];
        info=[self info:file missing:&missing error:error];
        if(!missing) {
            if(!info||![info[@"kind"] isEqual:@"S_IFREG"])return NO;
            NSData *observed=[self readSnapshot:file expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
            NSDictionary *expected=XFATCBooksManifest(self.journal);
            id plist=observed?[NSPropertyListSerialization propertyListWithData:observed options:NSPropertyListImmutable format:NULL error:error]:nil;
            if(![plist isEqual:expected])return NO;
            if(![self removeOwned:file expectedKind:@"S_IFREG" error:error])return NO;
        }
        if(![self removeOwned:sync expectedKind:@"S_IFDIR" error:error])return NO;
    }
    if(![self removeOwned:[root stringByAppendingPathComponent:@"XitForgeOwner.plist"] expectedKind:@"S_IFREG" error:error])return NO;
    return [self removeOwned:root expectedKind:@"S_IFDIR" error:error];
}
- (BOOL)restoreBooks:(NSError **)error {
    if([self.journal[@"booksInPlace"] boolValue])return [self restoreBooksInPlace:error];
    NSString *backupBooks=[self.journal[@"backup"] stringByAppendingPathComponent:@"Books"];
    NSString *temporary=[self.journal[@"backup"] stringByAppendingPathComponent:@"TemporaryBooks"];
    BOOL backupMissing=NO,currentMissing=NO;
    NSDictionary *backup=[self info:backupBooks missing:&backupMissing error:error];
    if(!backup&&!backupMissing)return NO;
    NSDictionary *current=[self info:@"Books" missing:&currentMissing error:error];
    if(!current&&!currentMissing)return NO;
    BOOL original=[self.journal[@"booksOriginallyPresent"] boolValue];
    BOOL restoreAlready=[self.journal[@"booksRestored"] boolValue];
    if(![self.journal[@"booksIsolationStarted"] boolValue]) {
        /* No original rename was ever authorized: Books is not ours to quarantine. */
        if(!backupMissing){if(error)*error=XFATCError(2141,@"Hay un respaldo de Books sin una operación de aislamiento registrada.");return NO;}
        self.journal[@"booksRestored"]=@YES;
        return [self saveJournal:@"Books never isolated" error:error];
    }
    if(original&&backupMissing) {
        if(currentMissing||![current[@"kind"] isEqual:@"S_IFDIR"]||![self preimageMatches:@"Books" error:error]){
            if(error&&!*error)*error=XFATCError(2125,@"No se pudo verificar la biblioteca original de Books. Se conservaron el respaldo y el registro de recuperación.");return NO;
        }
        /* Rename may have completed before the persisted state update, or never started. */
        self.journal[@"booksRestored"]=@YES;
        return [self saveJournal:@"Books original verified at original path" error:error];
    }
    if(restoreAlready) {
        if(original){if(error)*error=XFATCError(2126,@"El respaldo original reapareció después de una restauración. Se conservará para revisión.");return NO;}
        if(!currentMissing){if(error)*error=XFATCError(2127,@"Books apareció después de la restauración. No se eliminará.");return NO;}
        return YES;
    }
    if(backup&&![backup[@"kind"] isEqual:@"S_IFDIR"]){if(error)*error=XFATCError(2128,@"El respaldo original de Books no es un directorio.");return NO;}
    BOOL unchanged=!original||[self preimageMatches:backupBooks error:error];
    NSError *preimageError=error?*error:nil;
    if(error)*error=nil;
    if(!currentMissing) {
        if(![current[@"kind"] isEqual:@"S_IFDIR"]){if(error)*error=XFATCError(2129,@"El Books temporal cambió de tipo. Se preservó todo para recuperación.");return NO;}
        if(![self booksOwnerMatches:@"Books" error:error]){if(error&&!*error)*error=XFATCError(2143,@"Books contiene un directorio ajeno al temporal generado. Se preservó junto al respaldo original.");return NO;}
        if(![self renameOwned:@"Books" to:temporary error:error])return NO;
        self.journal[@"temporaryBooksQuarantined"]=@YES;
        if(![self saveJournal:@"temporary Books retained" error:error])return NO;
    }
    if(original) {
        if(backupMissing){if(error)*error=XFATCError(2130,@"El respaldo original de Books no está disponible.");return NO;}
        if(![self renameOwned:backupBooks to:@"Books" error:error])return NO;
        NSDictionary *restored=[self info:@"Books" missing:&currentMissing error:error];
        if(!restored||![restored[@"kind"] isEqual:@"S_IFDIR"]||![self preimageMatches:@"Books" error:error])unchanged=NO;
    }
    if(!unchanged) {
        /* Keep the actual original, including daemon writes through previously open file descriptors.
           Never overwrite those bytes with the snapshot. Restoration is reported as unverified. */
        self.journal[@"originalRestoredWithChanges"]=@YES;
        [self saveJournal:@"original Books restored but preimage changed" error:NULL];
        if(error)*error=preimageError?:XFATCError(2131,@"Books cambió durante la operación. Se devolvió la biblioteca original a su lugar y se conservaron los temporales; no se aprobó la exploración.");return NO;
    }
    self.journal[@"booksRestored"]=@YES;
    return [self saveJournal:@"Books preimage restored and verified" error:error];
}
- (BOOL)validateGeneratedTree:(NSString *)path allowed:(NSDictionary<NSString *,NSString *> *)allowed error:(NSError **)error {
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(missing)return YES;if(!info)return NO;
    if(![info[@"kind"] isEqual:@"S_IFDIR"]||![allowed[path] isEqual:@"S_IFDIR"])return NO;
    NSArray *names=[self names:path error:error];if(!names)return NO;
    for(NSString *name in names) {
        NSString *child=[path stringByAppendingPathComponent:name];
        if(!allowed[child])return NO;
        NSDictionary *stat=[self info:child missing:&missing error:error];if(!stat||missing)return NO;
        if(![stat[@"kind"] isEqual:allowed[child]])return NO;
        if([stat[@"kind"] isEqual:@"S_IFDIR"]&&! [self validateGeneratedTree:child allowed:allowed error:error])return NO;
        if(![stat[@"kind"] isEqual:@"S_IFDIR"]&&![stat[@"kind"] isEqual:@"S_IFREG"]&&![stat[@"kind"] isEqual:@"S_IFLNK"])return NO;
    }
    return YES;
}
- (BOOL)cleanGeneratedStage:(NSError **)error {
    NSString *source=self.journal[@"source"],*relocated=self.journal[@"link"];
    NSString *sourceLink=[source stringByAppendingPathComponent:@"p0/p1/p2/link"];
    NSString *expected=[@"../../../" stringByAppendingString:self.journal[@"tail"]];
    NSString *metadata=[source stringByAppendingPathComponent:@"META-INF/com.apple.ZipMetadata.plist"];
    NSString *marker=[source stringByAppendingPathComponent:@"payload"];
    BOOL hasMarker=[self.journal[@"archiveProfile"] isEqual:@"3105-directory-v1"];
    NSMutableArray *directories=[NSMutableArray new];
    for(NSString *relative in XFATCDirectories(self.journal[@"tail"]))[directories addObject:[source stringByAppendingPathComponent:relative]];
    NSMutableDictionary *allowed=[NSMutableDictionary new];
    for(NSString *directory in directories)allowed[directory]=@"S_IFDIR";
    allowed[source]=@"S_IFDIR";allowed[metadata]=@"S_IFREG";allowed[sourceLink]=@"S_IFLNK";
    if(hasMarker)allowed[marker]=@"S_IFREG";
    /* Validate every ancestor before looking up or unlinking a nested path. */
    if(![self validateGeneratedTree:source allowed:allowed error:error])return NO;
    for(NSString *link in @[relocated,sourceLink]) {
        BOOL missing=NO;NSDictionary *info=[self info:link missing:&missing error:error];
        if(missing)continue;if(!info)return NO;
        if(![info[@"kind"] isEqual:@"S_IFLNK"]||![info[@"linkTarget"] isEqual:expected])return NO;
        /* Unlink the generated symlink itself. Never traverse or recursively remove its target. */
        if(![self removeOwned:link expectedKind:@"S_IFLNK" error:error])return NO;
    }
    BOOL missing=NO;NSDictionary *info=[self info:metadata missing:&missing error:error];
    if(!missing) {
        if(!info||![info[@"kind"] isEqual:@"S_IFREG"])return NO;
        NSData *actual=[self readSnapshot:metadata expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
        id parsed=actual?[NSPropertyListSerialization propertyListWithData:actual options:NSPropertyListImmutable format:NULL error:error]:nil;
        if(![parsed isEqual:@{@"Version":@2}])return NO;
        if(![self removeOwned:metadata expectedKind:@"S_IFREG" error:error])return NO;
    }
    if(hasMarker) {
        info=[self info:marker missing:&missing error:error];
        if(!missing) {
            NSData *expectedMarker=[@"directory-list" dataUsingEncoding:NSUTF8StringEncoding];
            if(!info||![info[@"kind"] isEqual:@"S_IFREG"]||[info[@"size"] unsignedIntegerValue]!=expectedMarker.length)return NO;
            NSData *actual=[self readSnapshot:marker expectedSize:expectedMarker.length error:error];
            if(![actual isEqual:expectedMarker])return NO;
            if(![self removeOwned:marker expectedKind:@"S_IFREG" error:error])return NO;
        }
    }
    NSArray *reverse=[directories sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
        if(a.length>b.length)return NSOrderedAscending;if(a.length<b.length)return NSOrderedDescending;return[b compare:a];}];
    for(NSString *path in reverse)if(![self removeOwned:path expectedKind:@"S_IFDIR" error:error])return NO;
    return [self removeOwned:source expectedKind:@"S_IFDIR" error:error];
}
- (BOOL)cleanCreatedAirlock:(NSError **)error {
    NSDictionary *ownership=self.journal[@"mkdirOwnership"];
    BOOL clean=YES;
    for(NSString *path in @[@"Airlock/Book",@"Airlock"]) {
        NSDictionary *row=ownership[path];if(!row)continue;
        BOOL missing=NO;NSDictionary *current=[self info:path missing:&missing error:error];
        if(missing)continue;
        NSDictionary *created=[row[@"createdInfo"] isKindOfClass:NSDictionary.class]?row[@"createdInfo"]:nil;
        if(!current||!created||![current[@"kind"] isEqual:@"S_IFDIR"]||![current[@"creation"] isEqual:created[@"creation"]]){clean=NO;continue;}
        NSArray *names=[self names:path error:error];
        if(!names||names.count){clean=NO;continue;}
        if(![self removeOwned:path expectedKind:@"S_IFDIR" error:error])clean=NO;
    }
    return clean;
}
- (BOOL)finishRecovery:(NSError **)error {
    if(![self verifyRemoteOwner:error])return NO;
    if(self.journal[@"knownFile"]&&![self recoverKnownFile:NO error:error])return NO;
    BOOL committedDelete=[self.journal[@"knownFile"][@"operation"] isEqual:@"delete"]&&
        [self.journal[@"knownFile"][@"committed"] boolValue];
    if(![self restoreBooks:error])return NO;
    NSError *stageError=nil,*booksError=nil;
    BOOL stageClean=[self cleanGeneratedStage:&stageError];
    NSString *temporary=[self.journal[@"backup"] stringByAppendingPathComponent:@"TemporaryBooks"];
    BOOL booksClean=[self cleanExactTemporaryBooks:temporary error:&booksError];
    NSString *working=[self.journal[@"backup"] stringByAppendingPathComponent:@"WorkingBooks"];
    BOOL workingClean=[self cleanExactTemporaryBooks:working error:&booksError];
    BOOL airlockClean=[self cleanCreatedAirlock:&stageError];
    BOOL cleanupComplete=stageClean&&booksClean&&workingClean&&airlockClean;
    if(cleanupComplete&&!committedDelete) {
        BOOL absent=NO;NSDictionary *backupInfo=[self info:self.journal[@"backup"] missing:&absent error:&stageError];
        NSArray *remaining=backupInfo?[self names:self.journal[@"backup"] error:&stageError]:nil;
        if(!absent&&(!remaining||remaining.count>1||(remaining.count==1&&![remaining.firstObject isEqual:@"owner.plist"])))cleanupComplete=NO;
        else if(!absent){
            NSString *owner=[self.journal[@"backup"] stringByAppendingPathComponent:@"owner.plist"];
            cleanupComplete=[self removeOwned:owner expectedKind:@"S_IFREG" error:&stageError]&&[self removeOwned:self.journal[@"backup"] expectedKind:@"S_IFDIR" error:&stageError];
        }
    }
    if(committedDelete)self.journal[@"deleteBackupRetained"]=@YES;
    self.journal[@"cleanupComplete"]=@(cleanupComplete);
    if(!cleanupComplete) {
        self.lastWarning=@"Books se restauró y verificó. Se conservaron archivos temporales de sincronización para no descartar cambios del iPhone.";
        self.journal[@"cleanupWarning"]=self.lastWarning;
        if(stageError)self.journal[@"stageCleanupError"]=stageError.localizedDescription;
        if(booksError)self.journal[@"booksCleanupError"]=booksError.localizedDescription;
        if(![self saveJournal:@"original restored; staging retained" error:error])return NO;
        NSURL *archive=[self.journalURL URLByAppendingPathComponent:[NSString stringWithFormat:@"retained-%@.plist",self.journal[@"token"]]];
        NSData *data=XFATCPlist(self.journal,error);
        if([[NSFileManager defaultManager] fileExistsAtPath:archive.path]) {
            NSData *prior=[NSData dataWithContentsOfURL:archive options:0 error:error];
            id record=prior?[NSPropertyListSerialization propertyListWithData:prior options:NSPropertyListImmutable format:NULL error:error]:nil;
            if(![record isKindOfClass:NSDictionary.class]||![self validJournal:record]||![record[@"token"] isEqual:self.journal[@"token"]]||![record[@"booksRestored"] boolValue]){if(error&&!*error)*error=XFATCError(2142,@"El registro retenido no coincide con esta recuperación.");return NO;}
        }
        if(!data||![data writeToURL:archive options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
        chmod(archive.fileSystemRepresentation,0600);
    }
    NSDictionary *file=self.journal[@"knownFile"];
    if([file[@"operation"] isEqual:@"replace"]&&[file[@"originalCaptured"] boolValue]){
        NSDictionary *receipt=@{@"version":@1,@"token":self.journal[@"token"],@"namespace":self.journal[@"namespace"],
            @"target":file[@"target"],@"snapshot":file[@"snapshot"],@"originalDigest":file[@"originalDigest"],
            @"originalSize":file[@"originalSize"],@"committed":file[@"committed"],@"originalReturned":file[@"originalReturned"]};
        NSURL *url=[self.journalURL URLByAppendingPathComponent:[NSString stringWithFormat:@"file-receipt-%@.plist",self.journal[@"token"]]];
        NSData *encoded=XFATCPlist(receipt,error);
        if(!encoded||![encoded writeToURL:url options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
        chmod(url.fileSystemRepresentation,0600);
        if(!XFATCSyncURL(url,error)||!XFATCSyncURL(self.journalURL,error))return NO;
    }
    if(![[NSFileManager defaultManager] removeItemAtURL:self.activeURL error:error])return NO;
    if(committedDelete&&!XFATCSyncURL(self.journalURL,error))return NO;
    if(cleanupComplete)for(NSString *path in XFATCTrackedFiles()){
        NSDictionary *row=self.journal[@"trackedPreimage"][path];
        if([row[@"exists"] boolValue]&&row[@"snapshot"])[[NSFileManager defaultManager] removeItemAtURL:[self.journalURL URLByAppendingPathComponent:row[@"snapshot"]] error:NULL];
    }
    self.journal=nil;
    return YES;
}
- (BOOL)recoverPendingTransaction:(NSError **)error {
    self.lastWarning=nil;
    if(![[NSFileManager defaultManager] fileExistsAtPath:self.activeURL.path]){[self loadLatestDeletedBackup];return YES;}
    NSData *data=[NSData dataWithContentsOfURL:self.activeURL options:0 error:error];if(!data)return NO;
    id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:error];
    if(![value isKindOfClass:NSMutableDictionary.class]||![self validJournal:value]){
        if(error&&!*error)*error=XFATCError(2132,@"El registro de recuperación no es válido. Se conservaron todos los temporales.");return NO;
    }
    self.journal=value;
    if(![self openAFC:error])return NO;
    BOOL ok=[self finishRecovery:error];[self closeAFC];return ok;
}
- (NSArray<NSDictionary *> *)listAbsoluteDirectory:(NSString *)path error:(NSError **)error {
    NSString *target=XFATCPath(path);
    if(!target){if(error)*error=XFATCError(2133,@"Esta ruta no es una carpeta de un contenedor de app o de un grupo de apps.");return nil;}
    self.protocolEvents=[NSMutableArray new];self.protocolPhase=@"Recovery";self.grappaParameters=nil;self.servicePorts=[NSMutableDictionary new];
    self.appDirectoryFailure=nil;self.temporaryDirectoryFailure=nil;self.generatedAppLinkProbe=nil;self.fileOperationDiagnostics=nil;
    if(![self recoverPendingTransaction:error]||![self openAFC:error])return nil;
    self.protocolPhase=@"Prepare";
    NSString *previousWarning=self.lastWarning;
    if(![[NSFileManager defaultManager] createDirectoryAtURL:self.journalURL withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error]){[self closeAFC];return nil;}
    chmod(self.journalURL.fileSystemRepresentation,0700);
    NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
    NSString *source=[@"xf_atc_src_" stringByAppendingString:token],*link=[@"xf_atc_link_" stringByAppendingString:token],*backup=[@"xf_atc_state_" stringByAppendingString:token];
    for(NSString *name in @[source,link,backup]){
        BOOL missing=NO;[self info:name missing:&missing error:error];
        if(!missing){if(error&&!*error)*error=XFATCError(2134,@"Ya existe uno de los nombres temporales; no se inició la operación.");[self closeAFC];return nil;}
    }
    NSString *tail=[target substringFromIndex:1];
    NSString *identifier=[NSString stringWithFormat:@"../../%@/p0/p1/p2/link",source];
    self.journal=[NSMutableDictionary dictionaryWithDictionary:@{@"version":@1,@"archiveProfile":@"3105-directory-v1",@"token":token,@"namespace":self.journalURL.lastPathComponent,@"rsdUUID":self.deviceID,@"source":source,@"link":link,@"backup":backup,@"tail":tail,@"identifier":identifier,@"createdAt":[NSDate date],@"booksRestored":@NO,@"cleanupComplete":@NO}];
    NSError *operationError=nil;NSArray *rows=nil;
    do {
        if(![self snapshotBooks:&operationError])break;
        if(![self makeOwnedDirectory:backup error:&operationError])break;
        NSData *owner=XFATCPlist(self.ownerRecord,&operationError);
        if(!owner||![self writeOwned:owner path:[backup stringByAppendingPathComponent:@"owner.plist"] error:&operationError])break;
        NSString *working=[backup stringByAppendingPathComponent:@"WorkingBooks"];
        if(![self makeOwnedDirectory:working error:&operationError]||![self writeOwned:owner path:[working stringByAppendingPathComponent:@"XitForgeOwner.plist"] error:&operationError]||![self makeOwnedDirectory:[working stringByAppendingPathComponent:@"Sync"] error:&operationError])break;
        NSData *books=XFATCPlist(XFATCBooksManifest(self.journal),&operationError);
        if(!books||![self writeOwned:books path:[working stringByAppendingPathComponent:@"Sync/Books.plist"] error:&operationError])break;
        if([self.journal[@"booksOriginallyPresent"] boolValue]&&![self preimageMatches:@"Books" error:&operationError]){if(!operationError)operationError=XFATCError(2135,@"Books cambió durante la copia de seguridad. No se inició la exploración.");break;}
        if(![self.journal[@"booksOriginallyPresent"] boolValue]){BOOL absent=NO;[self info:@"Books" missing:&absent error:&operationError];if(!absent){if(!operationError)operationError=XFATCError(2144,@"Books apareció antes de iniciar la exploración. Se conservó y no se inició la operación.");break;}}
        self.journal[@"booksIsolationStarted"]=@YES;
        if(![self saveJournal:@"isolate Books original" error:&operationError])break;
        if(![self isolateBooks:&operationError])break;
        NSData *metadata=XFATCPlist(@{@"Version":@2},&operationError);uint8_t *bytes=NULL;size_t length=0;
        if(!metadata||xf_atc_build_directory_zip(tail.UTF8String,metadata.bytes,metadata.length,&bytes,&length)!=0){if(!operationError)operationError=XFATCError(2136,@"No se pudo construir el archivo de directorios.");break;}
        NSData *archive=[[NSData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:YES];
        if(![self stageZip:archive error:&operationError])break;
        if(![self makeOwnedDirectory:@"Airlock" error:&operationError]||![self makeOwnedDirectory:@"Airlock/Book" error:&operationError])break;
        if(![self installWorkingBooks:working error:&operationError])break;
        if(![self runATC:&operationError])break;
        self.protocolPhase=@"DirectoryListing";
        NSArray *names=[self names:link error:&operationError];
        [self recordProtocolEvent:names?@"DirectoryListed":@"DirectoryListFailed" command:nil code:names?0:operationError.code];
        if(!names)break;
        NSMutableArray *entries=[NSMutableArray new];
        for(NSString *name in names) {
            AfcFileInfo info={0};NSString *entry=[link stringByAppendingPathComponent:name];
            IdeviceFfiError *failure=afc_get_file_info(_afc,entry.UTF8String,&info);
            BOOL directory=NO,known=NO;
            if(!failure&&info.st_ifmt){directory=strcmp(info.st_ifmt,"S_IFDIR")==0;known=directory||strcmp(info.st_ifmt,"S_IFREG")==0;}
            if(failure)idevice_error_free(failure);afc_file_info_free(&info);
            [entries addObject:@{@"name":name,@"isDirectory":@(directory),@"typeKnown":@(known)}];
        }
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[a[@"name"] localizedStandardCompare:b[@"name"]];}];rows=entries;
    }while(0);
    [self closeAFC];
    if([[NSFileManager defaultManager] fileExistsAtPath:self.activeURL.path]) {
        NSError *recoveryError=nil;
        if(![self recoverPendingTransaction:&recoveryError]) {
            rows=nil;
            operationError=XFATCError(2137,[NSString stringWithFormat:@"%@ Se conserva la recuperación de Books: %@",operationError.localizedDescription?:@"No se pudo completar la exploración.",recoveryError.localizedDescription?:@"estado pendiente"]);
        }
    }
    if(!self.lastWarning)self.lastWarning=previousWarning;
    if(rows)self.protocolPhase=@"Complete";
    if(!rows&&error)*error=operationError?:XFATCError(2138,@"No se pudo explorar la carpeta mediante AirTraffic.");
    return rows;
}
@end
