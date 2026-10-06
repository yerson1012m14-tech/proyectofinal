- (void)fetchDeactivationList:(NSString *)endpoint completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *listKey=[endpoint isEqual:@"delete-files"]?@"deleteFiles":@"originals";
    NSString *game=[self.game stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"%@/api/app/%@?game=%@",self.apiBaseURL,endpoint,game?:@""]];
    if(!url){completion(nil,@"No se pudo consultar el panel.");return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.timeoutInterval=20;
    request.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    [LicenseValidator authorizeRequest:request completion:^(BOOL authorized) {
        if(!authorized){completion(nil,@"No se pudo autorizar la desactivación en el panel.");return;}
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
            [LicenseValidator handleProtectedHTTPResponse:response];
            NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(id)response:nil;
            if(error||!data||!http||http.statusCode<200||http.statusCode>=300){completion(nil,[NSString stringWithFormat:@"No se pudo consultar %@ en el panel (%ld).",endpoint,(long)http.statusCode]);return;}
            id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if(![json isKindOfClass:NSDictionary.class]||![json[@"ok"] isKindOfClass:NSNumber.class]||![json[@"ok"] boolValue]||
               ![json[listKey] isKindOfClass:NSArray.class]) {
                completion(nil,@"El panel devolvió una lista de desactivación inválida.");return;
            }
            completion(json,nil);
        }] resume];
    }];
}

- (void)showPanelDeactivationError:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"NO SE PUDO DESACTIVAR" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Entendido" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)beginPanelDeactivation {
    [self fetchDeactivationList:@"originals" completion:^(NSDictionary *originalResponse,NSString *failure) {
        if(!originalResponse){dispatch_async(dispatch_get_main_queue(),^{[self finishDeactivationUIWithSuccess:NO noOriginals:NO];[self showPanelDeactivationError:failure];});return;}
        [self fetchDeactivationList:@"delete-files" completion:^(NSDictionary *deleteResponse,NSString *deleteFailure) {
            dispatch_async(dispatch_get_main_queue(),^{
                if(!deleteResponse){[self finishDeactivationUIWithSuccess:NO noOriginals:NO];[self showPanelDeactivationError:deleteFailure];return;}
                NSMutableArray *destinations=[NSMutableArray new];NSMutableSet *ids=[NSMutableSet new];
                for(XITForgeOption *option in self.options) {
                    if(![self.deactivationTargetKeys containsObject:[self activationKeyForOption:option]])continue;
                    if(option.optionId)[ids addObject:option.optionId];
                    NSArray *files=option.fileItems;
                    if(!files.count&&option.route.length&&option.fileName.length)files=@[@{@"route":option.route,@"fileName":option.fileName}];
                    for(NSDictionary *file in files) {
                        NSMutableDictionary *destination=[file mutableCopy];
                        destination[@"bundleId"]=option.bundleId?:self.bundleId?:@"";
                        [destinations addObject:destination];
                    }
                }
                NSString *planError=nil;
                NSArray *plan=XFPanelDeactivationPlan(originalResponse[@"originals"],deleteResponse[@"deleteFiles"],destinations,ids,&planError);
                if(!plan){[self finishDeactivationUIWithSuccess:NO noOriginals:NO];[self showPanelDeactivationError:planError];return;}
                NSMutableArray *items=[NSMutableArray new];
                for(NSDictionary *action in plan) {
                    XITForgeOption *option=[XITForgeOption new];
                    option.route=action[@"route"];option.fileName=action[@"fileName"];
                    option.bundleId=[action[@"bundleId"] isKindOfClass:NSString.class]?action[@"bundleId"]:self.bundleId;
                    NSString *tunnelID=[XFTunnelV2Config tunnelBundleIdFromOptionDictionary:action];
                    if(tunnelID.length&&option.bundleId.length)[XFTunnelV2Config rememberTunnelBundleId:tunnelID forLegacyBundleId:option.bundleId];
                    NSMutableDictionary *item=[@{@"action":action[@"action"],@"route":option.route,@"fileName":option.fileName,
                        @"bundleID":option.bundleId?:@"",@"relativePath":action[@"relativePath"]} mutableCopy];
                    NSURL *destination=[self destinationURLForOption:option error:NULL];
                    if(destination)item[@"destinationURL"]=destination;
                    if([action[@"action"] isEqual:@"replace"]) {
                        NSURL *download=[self absoluteServerURLForString:action[@"originalFileUrl"]];
                        if(!download){[self finishDeactivationUIWithSuccess:NO noOriginals:NO];[self showPanelDeactivationError:@"La URL del original configurado no es válida."];return;}
                        item[@"downloadURL"]=download;
                    }
                    [items addObject:item];
                }
                [self restoreOriginalItems:items index:0];
            });
        }];
    }];
}

- (void)deletePanelItem:(NSDictionary *)item completion:(void (^)(BOOL,NSString *))completion {
    void (^tunnelDelete)(void)=^{
        if(![XITForgeFileEngine tunnelFallbackConfigured]){completion(NO,@"Conecta el túnel para borrar el archivo configurado.");return;}
        [XITForgeFileEngine deleteFileViaTunnelForBundleID:item[@"bundleID"] route:item[@"route"] fileName:item[@"fileName"] completion:completion];
    };
    NSURL *url=item[@"destinationURL"];
    if([XITForgeFileEngine tunnelReadyForHome]||!url){tunnelDelete();return;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSFileManager *manager=NSFileManager.defaultManager;
        NSDictionary *info=[manager attributesOfItemAtPath:url.path error:&error];
        BOOL absent=!info&&[error.domain isEqual:NSCocoaErrorDomain]&&(error.code==NSFileReadNoSuchFileError||error.code==NSFileNoSuchFileError);
        BOOL removed=absent;
        if([info[NSFileType] isEqual:NSFileTypeRegular])removed=[manager removeItemAtURL:url error:&error];
        if(removed){completion(YES,@"Archivo eliminado.");return;}
        // Exact files only; folders and links are never recursively deleted.
        if(info&&![info[NSFileType] isEqual:NSFileTypeRegular]){completion(NO,@"La regla de borrado debe señalar un archivo regular.");return;}
        tunnelDelete();
    });
}
