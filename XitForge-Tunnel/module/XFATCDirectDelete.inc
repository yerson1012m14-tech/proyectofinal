/* A panel delete rule authorizes destruction of this exact file. The ATC move
   goes to a fresh owned Trash slot and AFC unlinks it; no app-original backup,
   rollback or pending recovery is created. */
- (BOOL)deleteConfiguredAbsoluteFile:(NSString *)path error:(NSError **)error {
    NSString *target=XFATCPath(path);
    if(!target||!XFATCKnownFilePath(target)||!target.UTF8String||
       [target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096) {
        if(error)*error=XFATCError(2264,@"La regla de borrado debe señalar un archivo de la app.");return NO;
    }
    NSMutableDictionary *previousJournal=self.journal;
    self.directWriteActive=YES;self.batchActive=NO;self.lastWarning=nil;
    self.deletedFileBackupURL=nil;self.deletionAbsenceConfirmed=NO;
    self.batchEvents=[NSMutableArray new];self.batchLastPhase=0;
    NSError *failure=nil;BOOL deleted=NO,manifestTouched=NO,manifestAbsent=NO;
    NSData *previousManifest=nil,*publishedManifest=nil;
    @try {
        do {
            if(![self prepareDirectWrite:target error:&failure])break;
            NSMutableDictionary *file=self.journal[@"knownFile"];
            file[@"operation"]=@"directDelete";
            NSArray *ids=[self knownFileAssetIDs:self.journal];
            self.journal[@"fileManifest"]=@{@"Books":@[
                @{@"Persistent ID":ids[0],@"Item ID":@1,@"DSID":@"1"},
                @{@"Persistent ID":ids[1],@"Item ID":@2,@"DSID":@"1"}]};
            for(NSString *dir in @[@"Books",@"Books/Sync"]) {
                BOOL missing=NO;NSDictionary *info=[self info:dir missing:&missing error:&failure];
                if((!info&&!missing)||(info&&![info[@"kind"] isEqual:@"S_IFDIR"])||
                   (missing&&![self makeOwnedDirectory:dir error:&failure]))goto directDeleteDone;
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
            BOOL missing=NO;NSError *probeError=nil;
            NSDictionary *targetInfo=[self info:[self knownFileDestination] missing:&missing error:&probeError];
            if(missing){deleted=YES;self.deletionAbsenceConfirmed=YES;break;}
            if(targetInfo&&![targetInfo[@"kind"] isEqual:@"S_IFREG"]){failure=XFATCError(2265,@"La regla señala una carpeta o un enlace; no se borró.");break;}
            if(!targetInfo&&!(probeError.code==106&&[probeError.userInfo[@"NativeSubcode"] integerValue]==10)) {
                failure=probeError?:XFATCError(2266,@"No se pudo consultar el archivo configurado para borrar.");break;
            }
            // The destination is reserved within a new token and must be absent.
            [self info:file[@"Incoming"] missing:&missing error:&failure];if(!missing)break;
            if(![self saveJournal:@"remove exact panel file through fresh owned Trash" error:&failure]||
               ![self runKnownFilePairs:[self knownFilePair:1 destination:file[@"Incoming"]] error:&failure]||
               ![self waitKnownFile:file[@"Incoming"] missing:NO error:&failure])break;
            info=[self info:file[@"Incoming"] missing:&missing error:&failure];
            if(!info||missing||![info[@"kind"] isEqual:@"S_IFREG"]){failure=failure?:XFATCError(2265,@"El archivo trasladado no es regular; no se destruyó.");break;}
            if(![self removeOwned:file[@"Incoming"] expectedKind:@"S_IFREG" error:&failure])break;
            deleted=YES;
        }while(0);
directDeleteDone:;
    } @finally {
        if(manifestTouched) {
            NSError *cleanupError=nil;BOOL missing=NO;
            NSDictionary *info=[self info:@"Books/Sync/Books.plist" missing:&missing error:&cleanupError];
            NSData *current=(info&&[info[@"kind"] isEqual:@"S_IFREG"]&&[info[@"size"] unsignedLongLongValue]<=64u*1024u*1024u)?
                [self readSnapshot:@"Books/Sync/Books.plist" expectedSize:[info[@"size"] unsignedIntegerValue] error:&cleanupError]:nil;
            if([current isEqual:publishedManifest]) {
                BOOL clean=manifestAbsent?[self removeOwned:@"Books/Sync/Books.plist" expectedKind:@"S_IFREG" error:&cleanupError]:
                    [self writeBooksBytes:previousManifest path:@"Books/Sync/Books.plist" error:&cleanupError];
                if(!clean)self.lastWarning=@"Quedó estado temporal de sincronización.";
            }else if(!missing)self.lastWarning=@"El manifiesto de sincronización cambió; se conservó su estado actual.";
        }
        if(self.journal!=previousJournal&&[self.journal[@"directWrite"] boolValue]) {
            NSError *cleanupError=nil;
            if([self verifyRemoteOwner:&cleanupError]) {
                [self cleanGeneratedStage:&cleanupError];
                if(deleted) {
                    NSString *backup=self.journal[@"backup"];
                    [self removeOwned:[backup stringByAppendingPathComponent:@"owner.plist"] expectedKind:@"S_IFREG" error:&cleanupError];
                    [self removeOwned:backup expectedKind:@"S_IFDIR" error:&cleanupError];
                }
            }
            self.journal[@"knownFile"][@"committed"]=@(deleted);
            [self saveJournal:deleted?@"panel delete confirmed":@"panel delete not confirmed" error:NULL];
        }
        self.fileOperationDiagnostics=@{@"operation":@"directDelete",@"committed":@(deleted),
            @"stage":deleted?@"Deleted":@"NotConfirmed",@"automaticRecovery":@NO,@"originalCaptured":@NO,@"code":@(failure.code)};
        [self closeAFC];self.directWriteActive=NO;self.journal=previousJournal;
    }
    if(!deleted&&error)*error=failure?:XFATCError(2267,@"No se confirmó el borrado del archivo configurado en el panel.");
    return deleted;
}
