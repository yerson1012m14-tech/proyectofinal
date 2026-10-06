/* Home writes downloaded payloads directly. Legacy recovery is an explicit,
   separate feature: this route never captures or moves the application original. */
- (BOOL)prepareDirectWrite:(NSString *)target error:(NSError **)error {
    self.protocolEvents=[NSMutableArray new];self.protocolPhase=@"DirectWrite";
    self.syncAttempts=[NSMutableArray new];self.atcSyncAttempt=0;self.atcMoveAttempted=NO;
    self.fileOperationDiagnostics=nil;self.grappaParameters=nil;self.servicePorts=[NSMutableDictionary new];
    self.appDirectoryFailure=nil;self.temporaryDirectoryFailure=nil;self.generatedAppLinkProbe=nil;
    if(![self openAFC:error])return NO;
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.journalURL withIntermediateDirectories:YES
        attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error])return NO;
    chmod(self.journalURL.fileSystemRepresentation,0700);
    NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
    NSString *source=[@"xf_atc_src_" stringByAppendingString:token],*link=[@"xf_atc_link_" stringByAppendingString:token],
             *backup=[@"xf_atc_state_" stringByAppendingString:token];
    for(NSString *name in @[source,link,backup]) {
        BOOL missing=NO;NSDictionary *info=[self info:name missing:&missing error:error];
        if(info||!missing){if(error&&!*error)*error=XFATCError(2260,@"No se pudo reservar el temporal del archivo descargado.");return NO;}
    }
    NSString *tail=[target.stringByDeletingLastPathComponent substringFromIndex:1];
    NSMutableDictionary *file=[@{@"operation":@"directWrite",@"target":target,
        @"Original":[backup stringByAppendingPathComponent:@"FileOriginal"],
        @"Incoming":[backup stringByAppendingPathComponent:@"FileIncoming"],
        @"Verify":[backup stringByAppendingPathComponent:@"FileVerify"]} mutableCopy];
    self.journal=[@{@"version":@1,@"directWrite":@YES,@"archiveProfile":@"3105-directory-v1",
        @"token":token,@"namespace":self.journalURL.lastPathComponent,@"rsdUUID":self.deviceID,
        @"source":source,@"link":link,@"backup":backup,@"tail":tail,
        @"identifier":[NSString stringWithFormat:@"../../%@/p0/p1/p2/link",source],
        @"createdAt":[NSDate date],@"knownFile":file} mutableCopy];
    NSArray *ids=[self knownFileAssetIDs:self.journal];
    // Only the generated link and downloaded bytes are advertised. Never the app original.
    self.journal[@"fileManifest"]=@{@"Books":@[
        @{@"Persistent ID":ids[0],@"Item ID":@1,@"DSID":@"1"},
        @{@"Persistent ID":ids[3],@"Item ID":@2,@"DSID":@"1"}]};
    if(![self saveJournal:@"prepare downloaded payload only" error:error]||
       ![self makeOwnedDirectory:backup error:error])return NO;
    NSData *owner=XFATCPlist(self.ownerRecord,error);
    if(!owner||![self writeOwned:owner path:[backup stringByAppendingPathComponent:@"owner.plist"] error:error])return NO;
    NSData *metadata=XFATCPlist(@{@"Version":@2},error);uint8_t *bytes=NULL;size_t length=0;
    if(!metadata||xf_atc_build_directory_zip(tail.UTF8String,metadata.bytes,metadata.length,&bytes,&length)) {
        if(error&&!*error)*error=XFATCError(2261,@"No se pudo preparar el enlace del archivo descargado.");return NO;
    }
    NSData *archive=[[NSData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:YES];
    return [self stageZip:archive error:error]&&[self makeOwnedDirectory:@"Airlock" error:error]&&
        [self makeOwnedDirectory:@"Airlock/Book" error:error];
}

- (BOOL)writeDownloadedAbsoluteFile:(NSString *)path data:(NSData *)data error:(NSError **)error {
    NSString *target=XFATCPath(path);
    if(!target||!XFATCKnownFilePath(target)||!target.UTF8String||
       [target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096||!data||data.length>64u*1024u*1024u) {
        if(error)*error=XFATCError(2213,@"El destino debe ser un archivo de la app y el archivo nuevo no puede superar 64 MiB.");return NO;
    }
    NSMutableDictionary *previousJournal=self.journal;
    self.directWriteActive=YES;self.batchActive=NO;self.lastWarning=nil;
    self.batchEvents=[NSMutableArray new];self.batchLastPhase=0;self.completedKnownWrite=nil;
    NSError *failure=nil;BOOL applied=NO,manifestTouched=NO,manifestAbsent=NO;
    NSData *previousManifest=nil,*publishedManifest=nil;
    @try {
        do {
            if(![self prepareDirectWrite:target error:&failure])break;
            NSMutableDictionary *file=self.journal[@"knownFile"];
            file[@"newDigest"]=XFATCDigest(data);file[@"newSize"]=@(data.length);
            if(![self writeKnownIncoming:data error:&failure])break;
            // Books is transport metadata, not an application-file backup.
            // Existing owner markers and legacy journals are neither inspected nor changed.
            for(NSString *dir in @[@"Books",@"Books/Sync"]) {
                BOOL missing=NO;NSDictionary *info=[self info:dir missing:&missing error:&failure];
                if((!info&&!missing)||(info&&![info[@"kind"] isEqual:@"S_IFDIR"])||
                   (missing&&![self makeOwnedDirectory:dir error:&failure]))goto directWriteDone;
            }
            NSDictionary *info=[self info:@"Books/Sync/Books.plist" missing:&manifestAbsent error:&failure];
            if((!info&&!manifestAbsent)||(info&&![info[@"kind"] isEqual:@"S_IFREG"]))break;
            if(info) {
                if([info[@"size"] unsignedLongLongValue]>64u*1024u*1024u){failure=XFATCError(2262,@"El manifiesto de sincronización es demasiado grande.");break;}
                previousManifest=[self readSnapshot:@"Books/Sync/Books.plist" expectedSize:[info[@"size"] unsignedIntegerValue] error:&failure];
                if(!previousManifest)break;
            }
            publishedManifest=XFATCPlist(self.journal[@"fileManifest"],&failure);if(!publishedManifest)break;
            manifestTouched=YES;
            if(![self writeBooksBytes:publishedManifest path:@"Books/Sync/Books.plist" error:&failure]||
               ![self runATC:&failure]||![self verifyKnownTargetLink:&failure])break;
            file[@"incomingPlaceIntent"]=@YES;
            if(![self saveJournal:@"overwrite selected app file with downloaded payload" error:&failure]||
               ![self runKnownFilePairs:[self knownFilePair:3 destination:[self knownFileDestination]] error:&failure]||
               ![self waitKnownFile:file[@"Incoming"] missing:YES error:&failure])break;
            // FileComplete plus confirmed removal of its source proves transfer completion.
            // No read-back relocation, original capture, move-back or rollback is performed.
            applied=YES;file[@"committed"]=@YES;
            self.fileOperationDiagnostics=@{@"operation":@"directWrite",@"stage":@"TransferConfirmed",
                @"originalCaptured":@NO,@"automaticRecovery":@NO,@"sourceAbsenceConfirmed":@YES,
                @"targetReadBackVerified":@NO,@"committed":@YES};
            [self saveJournal:@"downloaded payload transfer confirmed" error:NULL];
        }while(0);
directWriteDone:;
    } @finally {
        // Release this operation's transport metadata inline. Never touch the target
        // again and never create a mandatory recovery task for a future Home tap.
        if(manifestTouched) {
            NSError *cleanupError=nil;BOOL missing=NO;
            NSDictionary *info=[self info:@"Books/Sync/Books.plist" missing:&missing error:&cleanupError];
            NSData *current=(info&&[info[@"kind"] isEqual:@"S_IFREG"]&&[info[@"size"] unsignedLongLongValue]<=64u*1024u*1024u)?
                [self readSnapshot:@"Books/Sync/Books.plist" expectedSize:[info[@"size"] unsignedIntegerValue] error:&cleanupError]:nil;
            if([current isEqual:publishedManifest]) {
                BOOL clean=manifestAbsent?[self removeOwned:@"Books/Sync/Books.plist" expectedKind:@"S_IFREG" error:&cleanupError]:
                    [self writeBooksBytes:previousManifest path:@"Books/Sync/Books.plist" error:&cleanupError];
                if(!clean)self.lastWarning=@"Quedó estado temporal de sincronización.";
            } else if(!missing)self.lastWarning=@"El manifiesto de sincronización cambió; se conservó su estado actual.";
        }
        // Cleanup is restricted to our new token. Old Books markers/backups remain untouched.
        if(self.journal!=previousJournal&&[self.journal[@"directWrite"] boolValue]) {
            NSError *cleanupError=nil;
            if([self verifyRemoteOwner:&cleanupError]) {
                [self cleanGeneratedStage:&cleanupError];
                if(applied) {
                    NSString *backup=self.journal[@"backup"];
                    [self removeOwned:[backup stringByAppendingPathComponent:@"owner.plist"] expectedKind:@"S_IFREG" error:&cleanupError];
                    [self removeOwned:backup expectedKind:@"S_IFDIR" error:&cleanupError];
                }
            }
            if(!applied)self.fileOperationDiagnostics=@{@"operation":@"directWrite",@"stage":@"NotConfirmed",
                @"originalCaptured":@NO,@"automaticRecovery":@NO,@"committed":@NO,@"code":@(failure.code)};
        }
        [self closeAFC];self.directWriteActive=NO;self.journal=previousJournal;
    }
    if(!applied&&error)*error=failure?:XFATCError(2263,@"No se confirmó la transferencia del archivo descargado.");
    return applied;
}
