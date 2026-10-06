/* Included inside XFATCDirectory's implementation. Legacy recovery deliberately
   retains backup/Books; a copied library has new inode timestamps and must be
   verified by its complete directory/file inventory and content hashes. */
- (BOOL)legacyBooksRelativePath:(NSString *)path {
    if(![path isKindOfClass:NSString.class]||!path.UTF8String||
       [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096)return NO;
    if(!path.length)return YES;
    NSArray *parts=[path componentsSeparatedByString:@"/"];
    if(parts.count>64)return NO;
    for(NSString *part in parts)if(!XFATCComponent(part))return NO;
    return ![path isEqual:@"XitForgeOwner.plist"];
}
- (NSString *)legacyBooksSnapshotName:(NSString *)relative {
    return [[@"leaf-" stringByAppendingString:XFATCDigest([relative dataUsingEncoding:NSUTF8StringEncoding])]
        stringByAppendingString:@".bin"];
}
- (NSString *)legacyBooksTreeDigest:(NSArray<NSDictionary *> *)entries {
    NSMutableData *canonical=[NSMutableData new];
    for(NSDictionary *row in entries) {
        NSArray *fields=@[row[@"path"],row[@"kind"],
            [NSString stringWithFormat:@"%llu",[row[@"size"] unsignedLongLongValue]],row[@"digest"]];
        for(NSString *field in fields) {
            NSData *bytes=[field dataUsingEncoding:NSUTF8StringEncoding];
            uint64_t size=bytes.length;uint8_t prefix[8];
            for(NSUInteger i=0;i<8;i++)prefix[i]=(uint8_t)(size>>(56-8*i));
            [canonical appendBytes:prefix length:sizeof(prefix)];[canonical appendData:bytes];
        }
    }
    return XFATCDigest(canonical);
}
- (BOOL)legacyBooksSave:(NSString *)intent error:(NSError **)error {
    return [self saveJournal:intent error:error]&&XFATCSyncURL(self.activeURL,error)&&
        XFATCSyncURL(self.journalURL,error);
}
- (NSData *)legacyBooksLocalBytes:(NSDictionary *)row record:(NSDictionary *)record error:(NSError **)error {
    NSURL *directory=[self.journalURL URLByAppendingPathComponent:record[@"snapshotDirectory"] isDirectory:YES];
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:directory.path error:error];
    if(![attributes[NSFileType] isEqual:NSFileTypeDirectory]) {
        if(error&&!*error)*error=XFATCError(2262,@"El directorio de la copia completa de Books cambió. Se conserva la recuperación.");return nil;
    }
    NSURL *url=[directory URLByAppendingPathComponent:row[@"snapshot"]];
    int fd=open(url.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);struct stat before={0},after={0};
    uint64_t size=[row[@"size"] unsignedLongLongValue];
    if(fd<0||fstat(fd,&before)||!S_ISREG(before.st_mode)||before.st_size<0||
       (uint64_t)before.st_size!=size||size>128u*1024u*1024u) {
        if(fd>=0)close(fd);
        if(error&&!*error)*error=XFATCError(2262,@"Un archivo de la copia completa de Books falta o cambió de tipo o tamaño.");return nil;
    }
    NSMutableData *bytes=[NSMutableData dataWithLength:(NSUInteger)size];NSUInteger offset=0;BOOL ok=YES;
    while(offset<bytes.length) {
        ssize_t count=read(fd,(uint8_t *)bytes.mutableBytes+offset,MIN((NSUInteger)65536,bytes.length-offset));
        if(count<0&&errno==EINTR)continue;
        if(count<=0){ok=NO;break;}offset+=(NSUInteger)count;
    }
    if(fstat(fd,&after)||after.st_size!=before.st_size||after.st_ino!=before.st_ino||after.st_dev!=before.st_dev)ok=NO;
    close(fd);
    if(!ok||![XFATCDigest(bytes) isEqual:row[@"digest"]]) {
        if(error&&!*error)*error=XFATCError(2262,@"Los bytes de la copia completa de Books no coinciden con su registro.");return nil;
    }
    return bytes;
}
- (BOOL)validLegacyBooksCopyJournal:(NSDictionary *)journal {
    NSDictionary *record=journal[@"legacyBooksCopy"];
    if(!record)return journal[@"legacyCopyRestored"]==nil;
    if(![record isKindOfClass:NSDictionary.class]||![record[@"version"] isEqual:@1]||
       ![journal[@"booksOriginallyPresent"] boolValue]||[journal[@"booksInPlace"] boolValue]||
       ![record[@"snapshotDirectory"] isEqual:[journal[@"token"] stringByAppendingString:@"-legacy-books"]]||
       !XFATCHash(record[@"treeDigest"]))return NO;
    NSSet *keys=[NSSet setWithArray:@[@"version",@"snapshotDirectory",@"entries",@"treeDigest",@"rootCreateIntent",
        @"rootInfo",@"temporaryCleanupIntent",@"temporaryRootInfo",@"markerWriteIntent",@"completed"]];
    for(id key in record)if(![keys containsObject:key])return NO;
    for(NSString *key in @[@"rootCreateIntent",@"temporaryCleanupIntent",@"markerWriteIntent",@"completed"])
        if(![record[key] isKindOfClass:NSNumber.class])return NO;
    if(journal[@"legacyCopyRestored"]&&![journal[@"legacyCopyRestored"] isKindOfClass:NSNumber.class])return NO;
    if([journal[@"legacyCopyRestored"] boolValue]&&(![record[@"completed"] boolValue]||
       ![journal[@"booksRestored"] boolValue]))return NO;
    if([record[@"completed"] boolValue]&&![journal[@"legacyCopyRestored"] boolValue])return NO;
    for(NSString *key in @[@"rootInfo",@"temporaryRootInfo"])if(record[key]) {
        NSDictionary *info=record[key];
        if(![info isKindOfClass:NSDictionary.class]||![info[@"kind"] isEqual:@"S_IFDIR"]||
           ![info[@"creation"] isKindOfClass:NSNumber.class])return NO;
    }
    if(record[@"rootInfo"]&&![record[@"rootCreateIntent"] boolValue])return NO;
    if(record[@"temporaryRootInfo"]&&![record[@"temporaryCleanupIntent"] boolValue])return NO;
    NSArray *entries=record[@"entries"];
    if(![entries isKindOfClass:NSArray.class]||!entries.count||entries.count>4096)return NO;
    NSMutableDictionary *indexed=[NSMutableDictionary new];NSString *prior=nil;uint64_t total=0;
    for(NSDictionary *row in entries) {
        if(![row isKindOfClass:NSDictionary.class]||row.count!=6||![self legacyBooksRelativePath:row[@"path"]]||
           ![row[@"size"] isKindOfClass:NSNumber.class]||[row[@"size"] longLongValue]<0||
           ![row[@"sourceInfo"] isKindOfClass:NSDictionary.class])return NO;
        NSString *path=row[@"path"],*kind=row[@"kind"];NSDictionary *source=row[@"sourceInfo"];
        if(prior&&[prior compare:path]!=NSOrderedAscending)return NO;
        if(![source[@"kind"] isEqual:kind]||![source[@"creation"] isKindOfClass:NSNumber.class]||
           ![source[@"mtimeNS"] isKindOfClass:NSNumber.class]||![source[@"size"] isKindOfClass:NSNumber.class])return NO;
        if(!indexed.count) {if(path.length||![kind isEqual:@"S_IFDIR"])return NO;}
        else if(![indexed[path.stringByDeletingLastPathComponent][@"kind"] isEqual:@"S_IFDIR"])return NO;
        if([kind isEqual:@"S_IFREG"]) {
            uint64_t size=[row[@"size"] unsignedLongLongValue];
            if(size>128u*1024u*1024u||![row[@"size"] isEqual:source[@"size"]]||!XFATCHash(row[@"digest"])||
               ![row[@"snapshot"] isEqual:[self legacyBooksSnapshotName:path]])return NO;
            total+=size;if(total>256u*1024u*1024u)return NO;
        }else if(![kind isEqual:@"S_IFDIR"]||![row[@"size"] isEqual:@0]||
                 ![row[@"digest"] isEqual:@""]||![row[@"snapshot"] isEqual:@""])return NO;
        indexed[path]=row;prior=path;
    }
    return [[self legacyBooksTreeDigest:entries] isEqual:record[@"treeDigest"]];
}
- (BOOL)legacyBooksCollectSource:(NSString *)root relative:(NSString *)relative record:(NSDictionary *)record
                         entries:(NSMutableArray *)entries total:(uint64_t *)total error:(NSError **)error {
    if(![self legacyBooksRelativePath:relative]||entries.count>=4096) {
        if(error&&!*error)*error=XFATCError(2263,@"Books contiene demasiados objetos o una ruta que no se puede copiar con seguridad.");return NO;
    }
    NSString *path=relative.length?[root stringByAppendingPathComponent:relative]:root;
    BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(!info||missing)return NO;
    NSString *kind=info[@"kind"];
    if(![kind isEqual:@"S_IFDIR"]&&![kind isEqual:@"S_IFREG"]) {
        if(error&&!*error)*error=XFATCError(2263,@"El respaldo completo de Books contiene un enlace u otro objeto no compatible. Se conserva intacto.");return NO;
    }
    NSMutableDictionary *row=[@{@"path":relative,@"kind":kind,@"size":@0,@"digest":@"",@"snapshot":@"",@"sourceInfo":info} mutableCopy];
    if([kind isEqual:@"S_IFREG"]) {
        uint64_t size=[info[@"size"] unsignedLongLongValue];
        if(size>128u*1024u*1024u||*total+size>256u*1024u*1024u) {
            if(error&&!*error)*error=XFATCError(2263,@"La copia completa de Books supera el límite seguro de 256 MiB.");return NO;
        }
        NSData *bytes=[self readSnapshot:path expectedSize:(NSUInteger)size error:error];
        NSDictionary *after=[self info:path missing:&missing error:error];
        if(!bytes||!after||missing||![after isEqual:info])return NO;
        row[@"size"]=@(size);row[@"digest"]=XFATCDigest(bytes);row[@"snapshot"]=[self legacyBooksSnapshotName:relative];*total+=size;
        NSURL *directory=[self.journalURL URLByAppendingPathComponent:record[@"snapshotDirectory"] isDirectory:YES];
        NSURL *url=[directory URLByAppendingPathComponent:row[@"snapshot"]];
        if([NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            NSData *prior=[self legacyBooksLocalBytes:row record:record error:error];
            if(![prior isEqual:bytes])return NO;
        }else if(![bytes writeToURL:url options:NSDataWritingWithoutOverwriting|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error])return NO;
        chmod(url.fileSystemRepresentation,0600);
        if(!XFATCSyncURL(url,error)||!XFATCSyncURL(directory,error))return NO;
    }
    [entries addObject:row];
    if([kind isEqual:@"S_IFDIR"]) {
        NSArray *names=[self names:path error:error];if(!names)return NO;
        for(NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *child=relative.length?[relative stringByAppendingPathComponent:name]:name;
            if(![self legacyBooksCollectSource:root relative:child record:record entries:entries total:total error:error])return NO;
        }
        NSDictionary *after=[self info:path missing:&missing error:error];
        if(!after||missing||![after isEqual:info])return NO;
    }
    return YES;
}
- (BOOL)legacyBooksVerifyTree:(NSString *)root relative:(NSString *)relative indexed:(NSDictionary *)indexed
                      source:(BOOL)source ignoreMarker:(BOOL)ignoreMarker seen:(NSMutableSet *)seen error:(NSError **)error {
    NSString *path=relative.length?[root stringByAppendingPathComponent:relative]:root;
    NSDictionary *row=indexed[relative];BOOL missing=NO;NSDictionary *info=[self info:path missing:&missing error:error];
    if(!row||!info||missing||![info[@"kind"] isEqual:row[@"kind"]]||
       (source&&![info isEqual:row[@"sourceInfo"]])) {
        if(error&&!*error)*error=XFATCError(2264,@"El árbol de Books cambió o contiene un objeto inesperado. Se conservó todo para recuperación.");return NO;
    }
    [seen addObject:relative];
    if([row[@"kind"] isEqual:@"S_IFREG"]) {
        if(![info[@"size"] isEqual:row[@"size"]])return NO;
        NSData *bytes=[self readSnapshot:path expectedSize:[row[@"size"] unsignedIntegerValue] error:error];
        NSDictionary *after=[self info:path missing:&missing error:error];
        if(!bytes||![XFATCDigest(bytes) isEqual:row[@"digest"]]||!after||missing||![after isEqual:info]) {
            if(error&&!*error)*error=XFATCError(2264,@"Un archivo de Books contiene bytes divergentes. Se conservará sin sobrescribirlo.");return NO;
        }
        return YES;
    }
    NSArray *names=[self names:path error:error];if(!names)return NO;
    for(NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if(!relative.length&&ignoreMarker&&[name isEqual:@"XitForgeOwner.plist"])continue;
        NSString *child=relative.length?[relative stringByAppendingPathComponent:name]:name;
        if(![self legacyBooksVerifyTree:root relative:child indexed:indexed source:source ignoreMarker:ignoreMarker seen:seen error:error])return NO;
    }
    NSDictionary *after=[self info:path missing:&missing error:error];
    if(!after||missing||![after isEqual:info])return NO;
    return YES;
}
- (BOOL)legacyBooksVerifyRoot:(NSString *)root record:(NSDictionary *)record source:(BOOL)source
                    complete:(BOOL)complete ignoreMarker:(BOOL)ignoreMarker error:(NSError **)error {
    NSMutableDictionary *indexed=[NSMutableDictionary new];
    for(NSDictionary *row in record[@"entries"])indexed[row[@"path"]]=row;
    NSMutableSet *seen=[NSMutableSet new];
    return [self legacyBooksVerifyTree:root relative:@"" indexed:indexed source:source ignoreMarker:ignoreMarker seen:seen error:error]&&
        (!complete||seen.count==indexed.count);
}
- (BOOL)legacyBooksTemporaryExact:(NSError **)error {
    if(![self booksOwnerMatches:@"Books" error:error])return NO;
    NSArray *names=[self names:@"Books" error:error];if(!names)return NO;
    for(NSString *name in names)if(![@[@"Sync",@"XitForgeOwner.plist"] containsObject:name])return NO;
    BOOL missing=NO;NSDictionary *sync=[self info:@"Books/Sync" missing:&missing error:error];
    if(missing)return YES;if(!sync||![sync[@"kind"] isEqual:@"S_IFDIR"])return NO;
    names=[self names:@"Books/Sync" error:error];if(!names||names.count>1)return NO;
    if(!names.count)return YES;if(![names.firstObject isEqual:@"Books.plist"])return NO;
    NSDictionary *info=[self info:@"Books/Sync/Books.plist" missing:&missing error:error];
    if(!info||missing||![info[@"kind"] isEqual:@"S_IFREG"]||[info[@"size"] unsignedLongLongValue]>65536)return NO;
    NSData *bytes=[self readSnapshot:@"Books/Sync/Books.plist" expectedSize:[info[@"size"] unsignedIntegerValue] error:error];
    id plist=bytes?[NSPropertyListSerialization propertyListWithData:bytes options:0 format:NULL error:error]:nil;
    return [plist isEqual:XFATCBooksManifest(self.journal)];
}
- (BOOL)restoreLegacyBooksCopy:(NSError **)error {
    if(![self.journal[@"booksOriginallyPresent"] boolValue]||[self.journal[@"booksInPlace"] boolValue]||
       ![self verifyRemoteOwner:error])return NO;
    NSString *source=[self.journal[@"backup"] stringByAppendingPathComponent:@"Books"];
    BOOL missing=NO;NSDictionary *sourceInfo=[self info:source missing:&missing error:error];
    if(!sourceInfo||missing||![sourceInfo[@"kind"] isEqual:@"S_IFDIR"])return NO;
    NSMutableDictionary *record=self.journal[@"legacyBooksCopy"];
    if(!record) {
        NSDictionary *current=[self info:@"Books" missing:&missing error:error];
        if((!current&&!missing)||(current&&![self legacyBooksTemporaryExact:error])) {
            if(error&&!*error)*error=XFATCError(2265,@"Books contiene datos ajenos al temporal. No se tocará; el respaldo sigue conservado.");return NO;
        }
        record=[@{@"version":@1,@"snapshotDirectory":[self.journal[@"token"] stringByAppendingString:@"-legacy-books"],
            @"rootCreateIntent":@NO,@"temporaryCleanupIntent":@NO,@"markerWriteIntent":@NO,@"completed":@NO} mutableCopy];
        NSURL *directory=[self.journalURL URLByAppendingPathComponent:record[@"snapshotDirectory"] isDirectory:YES];
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:directory.path error:NULL];
        if(attributes&&![attributes[NSFileType] isEqual:NSFileTypeDirectory])return NO;
        if(!attributes&&![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO
            attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error])return NO;
        if(!XFATCSyncURL(directory,error)||!XFATCSyncURL(self.journalURL,error))return NO;
        NSMutableArray *entries=[NSMutableArray new];uint64_t total=0;
        if(![self legacyBooksCollectSource:source relative:@"" record:record entries:entries total:&total error:error])return NO;
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"path"] compare:b[@"path"]];}];
        record[@"entries"]=entries;record[@"treeDigest"]=[self legacyBooksTreeDigest:entries];
        if(![self legacyBooksVerifyRoot:source record:record source:YES complete:YES ignoreMarker:NO error:error])return NO;
        self.journal[@"legacyBooksCopy"]=record;
        if(![self legacyBooksSave:@"complete legacy Books tree snapshotted durably before restoration" error:error])return NO;
    }
    if(![self validLegacyBooksCopyJournal:self.journal]) {
        if(error&&!*error)*error=XFATCError(2262,@"El registro de la copia completa de Books no es válido.");return NO;
    }
    /* Validate every local file and the complete remote original before clearing
       even an exact generated Books directory. */
    for(NSDictionary *row in record[@"entries"])if([row[@"kind"] isEqual:@"S_IFREG"]&&
       ![self legacyBooksLocalBytes:row record:record error:error])return NO;
    if(![self legacyBooksVerifyRoot:source record:record source:YES complete:YES ignoreMarker:NO error:error])return NO;
    NSDictionary *current=[self info:@"Books" missing:&missing error:error];if(!current&&!missing)return NO;
    BOOL restored=[self.journal[@"legacyCopyRestored"] boolValue];
    if(!restored&&current&&!record[@"rootInfo"]) {
        BOOL exact=[self legacyBooksTemporaryExact:error];
        if(!exact&&[record[@"temporaryCleanupIntent"] boolValue]&&
           [current[@"creation"] isEqual:record[@"temporaryRootInfo"][@"creation"]]&&[current[@"kind"] isEqual:@"S_IFDIR"]) {
            NSArray *names=[self names:@"Books" error:error];exact=names&&names.count==0;
        }
        if(!exact) {
            if(error&&!*error)*error=XFATCError(2265,@"Books cambió durante la recuperación. Se conservará sin sobrescribirlo.");return NO;
        }
        record[@"temporaryCleanupIntent"]=@YES;record[@"temporaryRootInfo"]=current;
        if(![self legacyBooksSave:@"clear only the exact owned temporary Books after complete snapshot" error:error]||
           ![self cleanExactTemporaryBooks:@"Books" error:error])return NO;
        current=[self info:@"Books" missing:&missing error:error];if(current||!missing)return NO;
    }
    if(!current) {
        if(restored) {if(error&&!*error)*error=XFATCError(2265,@"La copia restaurada de Books desapareció. Se mantiene su respaldo completo.");return NO;}
        record[@"rootCreateIntent"]=@YES;
        if(![self legacyBooksSave:@"create a missing Books root for the complete legacy copy" error:error]||
           ![self makeOwnedDirectory:@"Books" error:error])return NO;
        current=[self info:@"Books" missing:&missing error:error];
        if(!current||missing||![current[@"kind"] isEqual:@"S_IFDIR"])return NO;
        record[@"rootInfo"]=current;
        if(![self legacyBooksSave:@"new Books root identity captured before copying any original file" error:error])return NO;
    }
    if(![current[@"kind"] isEqual:@"S_IFDIR"]||![current[@"creation"] isEqual:record[@"rootInfo"][@"creation"]]) {
        if(error&&!*error)*error=XFATCError(2265,@"La raíz de Books no corresponde a esta copia. Se conservó el respaldo.");return NO;
    }
    BOOL markerMissing=NO;NSDictionary *marker=[self info:@"Books/XitForgeOwner.plist" missing:&markerMissing error:error];
    if(!marker&&!markerMissing)return NO;
    if(marker&&![self booksOwnerMatches:@"Books" error:error])return NO;
    if(markerMissing&&!restored) {
        NSArray *names=[self names:@"Books" error:error];if(!names||names.count)return NO;
        record[@"markerWriteIntent"]=@YES;
        NSData *owner=XFATCPlist(self.ownerRecord,error);
        if(!owner||![self legacyBooksSave:@"mark the empty owned Books copy before writing original files" error:error]||
           ![self writeOwned:owner path:@"Books/XitForgeOwner.plist" error:error]||![self booksOwnerMatches:@"Books" error:error])return NO;
        marker=[self info:@"Books/XitForgeOwner.plist" missing:&markerMissing error:error];if(!marker||markerMissing)return NO;
    }
    if(![self legacyBooksVerifyRoot:@"Books" record:record source:NO complete:restored ignoreMarker:marker!=nil error:error])return NO;
    if(!restored)for(NSDictionary *row in record[@"entries"]) {
        NSString *relative=row[@"path"];if(!relative.length)continue;
        NSString *path=[@"Books" stringByAppendingPathComponent:relative];
        NSDictionary *info=[self info:path missing:&missing error:error];if(!info&&!missing)return NO;
        if(info)continue; /* Existing entries were all verified above; never truncate them. */
        if([row[@"kind"] isEqual:@"S_IFDIR"]) {
            if(![self makeOwnedDirectory:path error:error])return NO;
        }else {
            NSData *bytes=[self legacyBooksLocalBytes:row record:record error:error];
            if(!bytes||![self writeOwned:bytes path:path error:error])return NO;
            info=[self info:path missing:&missing error:error];
            NSData *observed=info&&[info[@"kind"] isEqual:@"S_IFREG"]&&[info[@"size"] isEqual:row[@"size"]]?
                [self readSnapshot:path expectedSize:[row[@"size"] unsignedIntegerValue] error:error]:nil;
            if(![observed isEqual:bytes])return NO;
        }
    }
    if(![self legacyBooksVerifyRoot:source record:record source:YES complete:YES ignoreMarker:NO error:error]||
       ![self legacyBooksVerifyRoot:@"Books" record:record source:NO complete:YES ignoreMarker:marker!=nil error:error])return NO;
    record[@"completed"]=@YES;self.journal[@"legacyCopyRestored"]=@YES;self.journal[@"booksRestored"]=@YES;
    if(![self legacyBooksSave:@"complete Books copy verified; original remote backup deliberately retained" error:error])return NO;
    /* Completion is durable before marker removal. A reconnect can validate the
       complete copy without requiring timestamps from the original inode. */
    if(marker&&![self removeOwned:@"Books/XitForgeOwner.plist" expectedKind:@"S_IFREG" error:error])return NO;
    return [self legacyBooksVerifyRoot:source record:record source:YES complete:YES ignoreMarker:NO error:error]&&
        [self legacyBooksVerifyRoot:@"Books" record:record source:NO complete:YES ignoreMarker:NO error:error];
}
