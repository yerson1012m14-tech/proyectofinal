"""Exercise the production known-file write flow with mocked AFC/ATC on macOS.

The entry point, placement, partial read-back, verified return, and completion predicate
are extracted from production.
Transport and persistent I/O are modeled; this is not a physical iPhone test.
Every AFC rename or batch-link rearm is rejected by the fixture.
"""
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "module/XFATCDirectory.m").read_text(encoding="utf-8")


def method(signature):
    start = SOURCE.find(signature)
    if start < 0:
        raise SystemExit("Missing production method: " + signature)
    end = SOURCE.find("\n- (", start + len(signature))
    if end < 0:
        end = SOURCE.find("\n@end", start + len(signature))
    if end < 0:
        raise SystemExit("Could not delimit production method: " + signature)
    return SOURCE[start:end]


replace = method("- (BOOL)replaceAbsoluteFile:(NSString *)path data:(NSData *)data error:(NSError **)error {")
place = method("- (BOOL)placePreparedReplacementData:(NSData *)data error:(NSError **)error {")
return_replacement = method("- (BOOL)returnKnownReplacement:(NSError **)error {")
read_interrupted = method("- (BOOL)readBackInterruptedReplacement:(NSError **)error {")
match_completed = method("- (BOOL)completedWriteMatchesToken:(NSString *)token target:(NSString *)target digest:(NSString *)digest {")
link_recovery = method("- (BOOL)restoreBatchLinkForAutomaticRecovery:(NSError **)error {")
recovery = method("- (BOOL)recoverKnownFile:(BOOL)explicitRestore error:(NSError **)error {")
for name, text in (("replacement entry point", replace), ("placement helper", place)):
    assert "rearmBatchLink" not in text, name + " still moves the app symlink through AFC"
    assert "renameOwned:" not in text and "afc_rename_path" not in text, name + " still uses AFC rename"
assert "renameOwned:" not in link_recovery and "afc_rename_path" not in link_recovery, \
    "Legacy link recovery still uses the failing AFC rename"
assert "placePreparedReplacementData:data" in replace, \
    "Home's replacement entry point does not use the tested placement helper"
assert 'if(!explicitRestore && [file[@"readBackMismatch"] boolValue])' in recovery, \
    "A confirmed mismatching read-back can be moved again by automatic recovery"
for signature in ("- (BOOL)isolateBooks:(NSError **)error {",
                  "- (BOOL)installWorkingBooks:(NSString *)working error:(NSError **)error {"):
    text = method(signature)
    assert "renameOwned:" not in text and "afc_rename_path" not in text, \
        "Fresh Books setup still requires AFC rename"


fixture = r'''
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <stdio.h>

static NSError *XFATCError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"KnownWriteFixture" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *XFATCPath(NSString *path) {
    return [path isKindOfClass:NSString.class] && [path hasPrefix:@"/private/var/"] ? path : nil;
}
static BOOL XFATCKnownFilePath(NSString *path) {
    return [path hasPrefix:@"/private/var/mobile/Containers/Data/Application/"] &&
           [path containsString:@"/Documents/"] && ![path containsString:@"/../"];
}
static NSString *XFATCDigest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *result=[NSMutableString new];
    for(NSUInteger i=0;i<sizeof(bytes);i++) [result appendFormat:@"%02x",bytes[i]];
    return result;
}

@interface KnownWriteFixture : NSObject
@property NSMutableDictionary *journal;
@property NSMutableDictionary<NSString *, NSData *> *nodes;
@property NSMutableArray<NSString *> *events;
@property NSData *localOriginal;
@property NSString *lastWarning;
@property NSMutableArray *batchEvents;
@property NSDictionary *completedKnownWrite;
@property BOOL batchActive;
@property NSUInteger batchLastPhase;
@property NSUInteger forbiddenRenameCalls;
@property NSUInteger placementPairCount;
@property BOOL corruptVerification;
@property BOOL failVerifyRead;
@property BOOL failPlacement;
@property BOOL failAfterFirstPlacement;
@property BOOL failReturn;
@property BOOL failFinish;
@property NSString *failJournalIntent;
@property BOOL recoverInFinish;
@property NSString *completedTokenOverride;
@property NSString *completedTargetOverride;
@property NSString *completedDigestOverride;
@property BOOL rootLinkValid;
@property BOOL allowTargetStat;
@property NSData *changedTargetAfterReadBack;
@property NSString *target;
- (BOOL)replaceAbsoluteFile:(NSString *)path data:(NSData *)data error:(NSError **)error;
- (BOOL)placePreparedReplacementData:(NSData *)data error:(NSError **)error;
- (BOOL)readBackInterruptedReplacement:(NSError **)error;
- (BOOL)completedWriteMatchesToken:(NSString *)token target:(NSString *)target digest:(NSString *)digest;
- (BOOL)prepareKnownFile:(NSString *)target operation:(NSString *)operation error:(NSError **)error;
- (BOOL)requireProbeDestinationAbsent:(NSError **)error;
- (BOOL)observeKnownOriginal:(NSError **)error;
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error;
- (NSData *)readKnownStage:(NSString *)path limit:(NSUInteger)limit error:(NSError **)error;
- (BOOL)persistKnownOriginal:(NSData *)data error:(NSError **)error;
- (BOOL)saveJournal:(NSString *)intent error:(NSError **)error;
- (BOOL)writeKnownIncoming:(NSData *)data error:(NSError **)error;
- (BOOL)publishKnownManifestForBatch:(BOOL)batch error:(NSError **)error;
- (BOOL)verifyKnownTargetLink:(NSError **)error;
- (BOOL)verifyRemoteOwner:(NSError **)error;
- (NSData *)validatedLocalOriginal:(NSDictionary *)record error:(NSError **)error;
- (NSArray *)knownFilePair:(NSUInteger)source destination:(NSString *)destination;
- (NSString *)knownFileDestination;
- (BOOL)runKnownFilePairs:(NSArray *)pairs error:(NSError **)error;
- (BOOL)waitKnownFile:(NSString *)path missing:(BOOL)missing error:(NSError **)error;
- (BOOL)returnKnownReplacement:(NSError **)error;
- (BOOL)finishKnownFileWithError:(NSError **)error;
- (BOOL)createPreparedFileWithData:(NSData *)data error:(NSError **)error;
- (BOOL)renameOwned:(NSString *)source to:(NSString *)destination error:(NSError **)error;
- (BOOL)rearmBatchLink:(NSError **)error;
- (void)recordKnownFileStage:(NSString *)stage error:(NSError *)error;
- (void)recordBatchSetupPhase:(NSUInteger)phase;
@end

@implementation KnownWriteFixture
- (BOOL)prepareKnownFile:(NSString *)target operation:(NSString *)operation error:(NSError **)error {
    [self.events addObject:@"prepare"];
    self.target=target;
    self.journal=[@{@"token":@"test-transaction-token",@"link":@"owned-app-link",@"source":@"owned-stage",
        @"knownFile":[@{@"target":target,@"operation":operation,
            @"Original":@"owned-backup/Original",@"Incoming":@"owned-backup/Incoming",@"Verify":@"owned-backup/Verify",
            @"originalCaptured":@NO,@"incomingPlaceIntent":@NO,@"verifyMoveIntent":@NO,
            @"newVerified":@NO,@"returnNewIntent":@NO,@"committed":@NO} mutableCopy]} mutableCopy];
    return YES;
}
- (BOOL)requireProbeDestinationAbsent:(NSError **)error {
    // The existing-file route remains valid even if AFC cannot stat the target.
    if(self.allowTargetStat&&self.rootLinkValid&&self.nodes[self.target]==nil)return YES;
    if(error)*error=XFATCError(2243,@"AFC destination lookup denied; existing-file route required");
    return NO;
}
- (BOOL)observeKnownOriginal:(NSError **)error {
    [self.events addObject:@"capture-original"];
    NSData *original=self.nodes[self.target];if(!original)return NO;
    NSMutableDictionary *file=self.journal[@"knownFile"];
    self.nodes[file[@"Original"]]=original;[self.nodes removeObjectForKey:self.target];
    file[@"originalMoveIntent"]=@YES;file[@"originalObserved"]=@YES;
    return YES;
}
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error {
    if([path isEqual:self.target]&&!self.allowTargetStat) {
        if(missing)*missing=NO;
        if(error)*error=[NSError errorWithDomain:@"Native" code:106
            userInfo:@{@"NativeSubcode":@10,NSLocalizedDescriptionKey:@"Protected target metadata denied"}];
        return nil;
    }
    NSData *data=self.nodes[path];if(missing)*missing=data==nil;
    return data?@{@"kind":@"S_IFREG",@"size":@(data.length)}:nil;
}
- (NSData *)readKnownStage:(NSString *)path limit:(NSUInteger)limit error:(NSError **)error {
    [self.events addObject:[path isEqual:self.journal[@"knownFile"][@"Verify"]]?@"read-verify":@"read-original"];
    if(self.failVerifyRead&&[path isEqual:self.journal[@"knownFile"][@"Verify"]]) {
        if(error)*error=XFATCError(1,@"Transient read-back socket failure");return nil;
    }
    NSData *bytes=self.nodes[path];
    if(!bytes||bytes.length>limit){if(error)*error=XFATCError(2204,@"Owned staged file unavailable");return nil;}
    return bytes;
}
- (BOOL)persistKnownOriginal:(NSData *)data error:(NSError **)error {
    [self.events addObject:@"persist-original"];
    self.localOriginal=[data copy];
    NSMutableDictionary *file=self.journal[@"knownFile"];
    file[@"originalCaptured"]=@YES;file[@"originalDigest"]=XFATCDigest(data);file[@"originalSize"]=@(data.length);
    return YES;
}
- (BOOL)saveJournal:(NSString *)intent error:(NSError **)error {
    if([intent isEqual:self.failJournalIntent]) {
        if(error)*error=XFATCError(2259,@"Injected durable journal failure");return NO;
    }
    self.journal[@"intent"]=intent;return YES;
}
- (BOOL)writeKnownIncoming:(NSData *)data error:(NSError **)error {
    [self.events addObject:@"write-incoming"];
    self.nodes[self.journal[@"knownFile"][@"Incoming"]]=[data copy];return YES;
}
- (BOOL)publishKnownManifestForBatch:(BOOL)batch error:(NSError **)error {
    [self.events addObject:batch?@"manifest-grouped":@"manifest-full"];
    if(batch){if(error)*error=XFATCError(2250,@"Unexpected grouped-link manifest");return NO;}
    return YES;
}
- (BOOL)verifyKnownTargetLink:(NSError **)error {
    [self.events addObject:@"verify-root-link"];
    if(!self.rootLinkValid&&error)*error=XFATCError(2228,@"Foreign application link");
    return self.rootLinkValid;
}
- (BOOL)verifyRemoteOwner:(NSError **)error {return YES;}
- (NSData *)validatedLocalOriginal:(NSDictionary *)record error:(NSError **)error {
    return [record[@"originalDigest"] isEqual:XFATCDigest(self.localOriginal)]?self.localOriginal:nil;
}
- (NSArray *)knownFilePair:(NSUInteger)source destination:(NSString *)destination {
    return @[@{@"Source":@(source),@"AssetPath":destination}];
}
- (NSString *)knownFileDestination {return self.target;}
- (BOOL)runKnownFilePairs:(NSArray *)pairs error:(NSError **)error {
    if(pairs.count==1&&[pairs[0][@"Source"] isEqual:@1]) {
        [self.events addObject:@"read-interrupted-target"];
        NSMutableDictionary *file=self.journal[@"knownFile"];
        if(![pairs[0][@"AssetPath"] isEqual:file[@"Verify"]]||
           ![file[@"verifyMoveIntent"] boolValue]||self.nodes[file[@"Verify"]]||!self.nodes[self.target]) {
            if(error)*error=XFATCError(2202,@"Unexpected interrupted read-back request");return NO;
        }
        self.nodes[file[@"Verify"]]=self.nodes[self.target];
        [self.nodes removeObjectForKey:self.target];
        if(self.changedTargetAfterReadBack)self.nodes[self.target]=self.changedTargetAfterReadBack;
        return YES;
    }
    if(pairs.count==1&&[pairs[0][@"Source"] isEqual:@4]) {
        NSMutableDictionary *file=self.journal[@"knownFile"];
        BOOL unchangedUnexpected=![file[@"newVerified"] boolValue]&&![file[@"committed"] boolValue]&&
            [self.journal[@"intent"] hasPrefix:@"return unchanged unexpected"];
        [self.events addObject:unchangedUnexpected?@"return-unexpected":@"return-replacement"];
        if(![pairs[0][@"AssetPath"] isEqual:self.target]||
           (!unchangedUnexpected&&(![file[@"newVerified"] boolValue]||![file[@"returnNewIntent"] boolValue]))||
           !self.nodes[file[@"Verify"]])return NO;
        if(unchangedUnexpected&&(!self.allowTargetStat||self.nodes[self.target])) {
            if(error)*error=XFATCError(2107,@"Unexpected read-back destination occupied or unknown");return NO;
        }
        if(self.failReturn){if(error)*error=XFATCError(2203,@"Injected return transport failure");return NO;}
        self.nodes[self.target]=self.nodes[file[@"Verify"]];
        [self.nodes removeObjectForKey:file[@"Verify"]];return YES;
    }
    [self.events addObject:@"placement"];
    self.placementPairCount=pairs.count;
    if(self.failPlacement){
        if(error)*error=[NSError errorWithDomain:@"Native" code:106
            userInfo:@{@"NativeSubcode":@7,NSLocalizedDescriptionKey:@"Injected AFC InvalidArg"}];
        return NO;
    }
    if(pairs.count!=2||![pairs[0][@"Source"] isEqual:@3]||![pairs[1][@"Source"] isEqual:@1]||
       ![pairs[0][@"AssetPath"] isEqual:self.target]||
       ![pairs[1][@"AssetPath"] isEqual:self.journal[@"knownFile"][@"Verify"]]) {
        if(error)*error=XFATCError(2202,@"Placement must use incoming-to-target and target-to-verify only");return NO;
    }
    if(![self.journal[@"knownFile"][@"incomingPlaceIntent"] boolValue]) {
        if(error)*error=XFATCError(2202,@"Placement intent was not persisted");return NO;
    }
    NSMutableDictionary *file=self.journal[@"knownFile"];
    NSData *incoming=self.nodes[file[@"Incoming"]];if(!incoming)return NO;
    self.nodes[self.target]=incoming;[self.nodes removeObjectForKey:file[@"Incoming"]];
    if(self.failAfterFirstPlacement) {
        if(error)*error=XFATCError(1,@"Channel closed after incoming-to-target FileComplete");return NO;
    }
    self.nodes[file[@"Verify"]]=self.corruptVerification?[@"different bytes" dataUsingEncoding:NSUTF8StringEncoding]:self.nodes[self.target];
    [self.nodes removeObjectForKey:self.target];
    return YES;
}
- (BOOL)waitKnownFile:(NSString *)path missing:(BOOL)missing error:(NSError **)error {
    return (self.nodes[path]==nil)==missing;
}
- (BOOL)finishKnownFileWithError:(NSError **)error {
    [self.events addObject:@"finish"];
    if(self.failFinish){if(error)*error=XFATCError(2257,@"Injected synchronization cleanup failure");return NO;}
    if(self.recoverInFinish) {
        NSMutableDictionary *file=self.journal[@"knownFile"];
        BOOL recovered=YES;NSError *recoveryError=nil;
        if(![file[@"committed"] boolValue]) {
            self.failPlacement=NO;self.failAfterFirstPlacement=NO;
            if(self.nodes[file[@"Incoming"]]&&!self.nodes[file[@"Verify"]])
                recovered=[self placePreparedReplacementData:self.nodes[file[@"Incoming"]] error:&recoveryError];
            else if(!self.nodes[file[@"Incoming"]]&&!self.nodes[file[@"Verify"]])
                recovered=[self readBackInterruptedReplacement:&recoveryError];
            else recovered=NO;
        }
        if(!recovered){if(error)*error=recoveryError?:XFATCError(2210,@"Mock recovery remains pending");return NO;}
        self.completedKnownWrite=@{@"token":self.completedTokenOverride?:self.journal[@"token"],
            @"target":self.completedTargetOverride?:file[@"target"],@"operation":file[@"operation"],
            @"newDigest":self.completedDigestOverride?:file[@"newDigest"]?:@"",
            @"newVerified":file[@"newVerified"]?:@NO,@"committed":file[@"committed"]?:@NO,
            @"originalReturned":file[@"originalReturned"]?:@NO};
    }
    // Recovery I/O is intentionally outside this fixture; retained objects are inspected by tests.
    return YES;
}
- (BOOL)createPreparedFileWithData:(NSData *)data error:(NSError **)error {
    if(error)*error=XFATCError(2243,@"Unexpected create route in replacement scenario");return NO;
}
- (BOOL)renameOwned:(NSString *)source to:(NSString *)destination error:(NSError **)error {
    self.forbiddenRenameCalls++;
    if(error)*error=XFATCError(106,@"AFC rename rejected by fixture");return NO;
}
- (BOOL)rearmBatchLink:(NSError **)error {
    self.forbiddenRenameCalls++;
    if(error)*error=XFATCError(106,@"Batch link rearm rejected by fixture");return NO;
}
- (void)recordKnownFileStage:(NSString *)stage error:(NSError *)error {(void)stage;(void)error;}
- (void)recordBatchSetupPhase:(NSUInteger)phase {self.batchLastPhase=phase;}

__PRODUCTION__
@end

static NSData *bytes(NSString *text){return [text dataUsingEncoding:NSUTF8StringEncoding];}
static NSString *target(void){return @"/private/var/mobile/Containers/Data/Application/TEST-UUID/Documents/config.bin";}
static KnownWriteFixture *make(void) {
    KnownWriteFixture *f=[KnownWriteFixture new];f.events=[NSMutableArray new];f.rootLinkValid=YES;
    f.nodes=[@{target():bytes(@"original bytes")} mutableCopy];return f;
}
static BOOL before(KnownWriteFixture *f,NSString *first,NSString *second) {
    NSUInteger a=[f.events indexOfObject:first],b=[f.events indexOfObject:second];
    return a!=NSNotFound&&b!=NSNotFound&&a<b;
}
#define CHECK(condition) do{if(!(condition)){fprintf(stderr,"Known-write fixture failed at line %d\n",__LINE__);return 1;}}while(0)
int main(void){@autoreleasepool{
    NSData *original=bytes(@"original bytes"),*payload=bytes(@"replacement from Render");
    NSError *error=nil;KnownWriteFixture *f=make();
    CHECK([f replaceAbsoluteFile:target() data:payload error:&error]);
    CHECK([f.nodes[target()] isEqual:payload]);CHECK([f.localOriginal isEqual:original]);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]);
    CHECK([f.journal[@"knownFile"][@"committed"] boolValue]);
    CHECK(f.forbiddenRenameCalls==0&&f.placementPairCount==2);
    CHECK(before(f,@"prepare",@"capture-original")&&before(f,@"capture-original",@"persist-original"));
    CHECK(before(f,@"persist-original",@"write-incoming")&&before(f,@"write-incoming",@"manifest-full"));
    CHECK(before(f,@"manifest-full",@"placement")&&before(f,@"placement",@"read-verify"));
    CHECK(before(f,@"read-verify",@"return-replacement")&&before(f,@"return-replacement",@"finish"));

    f=make();f.corruptVerification=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error!=nil);
    CHECK(![f.journal[@"knownFile"][@"committed"] boolValue]);
    CHECK([f.localOriginal isEqual:original]&&[f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]);
    CHECK([f.events indexOfObject:@"return-replacement"]==NSNotFound);CHECK(f.forbiddenRenameCalls==0);

    f=make();f.failPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error.code==106);
    CHECK([f.localOriginal isEqual:original]&&[f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Incoming"]] isEqual:payload]);
    CHECK(![f.journal[@"knownFile"][@"committed"] boolValue]);CHECK(f.forbiddenRenameCalls==0);

    f=make();f.failReturn=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    CHECK([f.journal[@"knownFile"][@"newVerified"] boolValue]&&![f.journal[@"knownFile"][@"committed"] boolValue]);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Verify"]] isEqual:payload]&&[f.localOriginal isEqual:original]);

    f=make();f.rootLinkValid=NO;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    CHECK([f.events indexOfObject:@"placement"]==NSNotFound);CHECK(f.forbiddenRenameCalls==0);

    f=make();f.failFinish=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    CHECK([f.nodes[target()] isEqual:payload]&&[f.localOriginal isEqual:original]);

    f=make();error=nil;
    CHECK([f replaceAbsoluteFile:target() data:NSData.data error:&error]);
    CHECK([f.nodes[target()] isEqual:NSData.data]);CHECK(f.forbiddenRenameCalls==0);

    f=make();f.failPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.failPlacement=NO;[f.events removeAllObjects];
    f.nodes[f.journal[@"knownFile"][@"Incoming"]]=bytes(@"tampered incoming");
    CHECK(![f placePreparedReplacementData:payload error:NULL]);
    CHECK([f.events indexOfObject:@"placement"]==NSNotFound);
    CHECK([f.localOriginal isEqual:original]&&[f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]);

    f=make();f.failPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.failPlacement=NO;[f.events removeAllObjects];
    f.nodes[f.journal[@"knownFile"][@"Verify"]]=bytes(@"foreign verification data");error=nil;
    CHECK(![f placePreparedReplacementData:payload error:&error]);
    CHECK([f.events indexOfObject:@"placement"]==NSNotFound);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Verify"]] isEqual:bytes(@"foreign verification data")]);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    CHECK([f.nodes[target()] isEqual:payload]);
    CHECK(f.nodes[f.journal[@"knownFile"][@"Incoming"]]==nil&&f.nodes[f.journal[@"knownFile"][@"Verify"]]==nil);
    CHECK([f.localOriginal isEqual:original]&&[f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]);
    CHECK([f.journal[@"knownFile"][@"incomingPlaceIntent"] boolValue]);
    CHECK(![f.journal[@"knownFile"][@"newVerified"] boolValue]&&![f.journal[@"knownFile"][@"committed"] boolValue]);
    // Recovery must read this pending target into owned Verify using ATC and compare
    // the durable expected digest/size before returning it. Missing Incoming alone
    // must never commit the write or trigger deletion of the original backup.
    CHECK([f.events indexOfObject:@"return-replacement"]==NSNotFound);CHECK(f.forbiddenRenameCalls==0);

    f=make();f.failJournalIntent=@"return verified replacement file";error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error.code==2259);
    CHECK([f.events indexOfObject:@"return-replacement"]==NSNotFound);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Verify"]] isEqual:payload]);
    CHECK(![f.journal[@"knownFile"][@"committed"] boolValue]&&[f.localOriginal isEqual:original]);

    f=make();f.failJournalIntent=@"verified replacement source positively absent; committed";error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error.code==2259);
    CHECK([f.nodes[target()] isEqual:payload]&&f.nodes[f.journal[@"knownFile"][@"Verify"]]==nil);
    CHECK([f.localOriginal isEqual:original]);
    // A memory-only committed flag does not make the operation successful.
    // Production reconnect must reload the durable return intent and recheck sources.

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    [f.events removeAllObjects];error=nil;
    CHECK([f readBackInterruptedReplacement:&error]);
    CHECK([f.nodes[target()] isEqual:payload]&&[f.journal[@"knownFile"][@"committed"] boolValue]);
    CHECK(before(f,@"read-interrupted-target",@"read-verify")&&before(f,@"read-verify",@"return-replacement"));
    CHECK([f.localOriginal isEqual:original]&&[f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.nodes[target()]=bytes(@"unexpected application update");[f.events removeAllObjects];error=nil;
    CHECK(![f readBackInterruptedReplacement:&error]);CHECK(error.code==2261);
    CHECK([f.journal[@"knownFile"][@"readBackMismatch"] boolValue]);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Verify"]] isEqual:bytes(@"unexpected application update")]);
    CHECK(![f.journal[@"knownFile"][@"newVerified"] boolValue]&&![f.journal[@"knownFile"][@"committed"] boolValue]);
    CHECK([f.events indexOfObject:@"return-replacement"]==NSNotFound&&[f.localOriginal isEqual:original]);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.nodes[f.journal[@"knownFile"][@"Original"]]=bytes(@"corrupted remote original");[f.events removeAllObjects];
    CHECK(![f readBackInterruptedReplacement:NULL]);
    CHECK([f.events indexOfObject:@"read-interrupted-target"]==NSNotFound&&[f.nodes[target()] isEqual:payload]);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.localOriginal=bytes(@"corrupted local original");[f.events removeAllObjects];
    CHECK(![f readBackInterruptedReplacement:NULL]);
    CHECK([f.events indexOfObject:@"read-interrupted-target"]==NSNotFound&&[f.nodes[target()] isEqual:payload]);

    f=make();NSMutableDictionary *completed=[@{@"token":@"test-token",@"target":target(),
        @"newDigest":XFATCDigest(payload),@"newVerified":@YES,@"committed":@YES,
        @"originalReturned":@NO,@"operation":@"replace"} mutableCopy];
    f.completedKnownWrite=completed;
    CHECK([f completedWriteMatchesToken:@"test-token" target:target() digest:XFATCDigest(payload)]);
    CHECK(![f completedWriteMatchesToken:@"another-token" target:target() digest:XFATCDigest(payload)]);
    CHECK(![f completedWriteMatchesToken:@"test-token" target:@"another-target" digest:XFATCDigest(payload)]);
    CHECK(![f completedWriteMatchesToken:@"test-token" target:target() digest:XFATCDigest(original)]);
    completed[@"newVerified"]=@NO;CHECK(![f completedWriteMatchesToken:@"test-token" target:target() digest:XFATCDigest(payload)]);
    completed[@"newVerified"]=@YES;completed[@"committed"]=@NO;
    CHECK(![f completedWriteMatchesToken:@"test-token" target:target() digest:XFATCDigest(payload)]);
    completed[@"committed"]=@YES;completed[@"originalReturned"]=@YES;
    CHECK(![f completedWriteMatchesToken:@"test-token" target:target() digest:XFATCDigest(payload)]);
    completed[@"originalReturned"]=@NO;completed[@"operation"]=@"read";
    CHECK(![f completedWriteMatchesToken:@"test-token" target:target() digest:XFATCDigest(payload)]);

    f=make();f.failPlacement=YES;f.recoverInFinish=YES;error=nil;
    CHECK([f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error==nil);
    CHECK([f.nodes[target()] isEqual:payload]&&[f.completedKnownWrite[@"committed"] boolValue]);
    CHECK([f.completedKnownWrite[@"token"] isEqual:f.journal[@"token"]]&&[f.localOriginal isEqual:original]);

    f=make();f.failAfterFirstPlacement=YES;f.recoverInFinish=YES;error=nil;
    CHECK([f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error==nil);
    CHECK([f.nodes[target()] isEqual:payload]&&[f.completedKnownWrite[@"newVerified"] boolValue]);
    CHECK([f.events indexOfObject:@"read-interrupted-target"]!=NSNotFound&&f.forbiddenRenameCalls==0);

    f=make();f.failPlacement=YES;f.recoverInFinish=YES;f.completedTokenOverride=@"foreign-token";error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error!=nil);
    CHECK([f.nodes[target()] isEqual:payload]);

    f=make();f.failPlacement=YES;f.recoverInFinish=YES;f.completedDigestOverride=XFATCDigest(original);error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);CHECK(error!=nil);
    CHECK([f.nodes[target()] isEqual:payload]);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    NSData *unexpected=bytes(@"application bytes changed before read-back");
    f.nodes[target()]=unexpected;f.allowTargetStat=YES;[f.events removeAllObjects];error=nil;
    CHECK(![f readBackInterruptedReplacement:&error]);CHECK(error.code==2261);
    CHECK([f.nodes[target()] isEqual:unexpected]&&f.nodes[f.journal[@"knownFile"][@"Verify"]]==nil);
    CHECK([f.journal[@"knownFile"][@"readBackMismatch"] boolValue]);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]&&[f.localOriginal isEqual:original]);
    CHECK(![f.journal[@"knownFile"][@"newVerified"] boolValue]&&![f.journal[@"knownFile"][@"committed"] boolValue]);
    CHECK([f.events indexOfObject:@"return-unexpected"]!=NSNotFound&&f.forbiddenRenameCalls==0);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.nodes[target()]=unexpected;f.allowTargetStat=YES;
    NSData *changedAgain=bytes(@"new object appeared at application destination");
    f.changedTargetAfterReadBack=changedAgain;[f.events removeAllObjects];error=nil;
    CHECK(![f readBackInterruptedReplacement:&error]);CHECK(error.code==2261);
    CHECK([f.nodes[target()] isEqual:changedAgain]&&[f.nodes[f.journal[@"knownFile"][@"Verify"]] isEqual:unexpected]);
    CHECK([f.journal[@"knownFile"][@"readBackMismatch"] boolValue]);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Original"]] isEqual:original]&&[f.localOriginal isEqual:original]);
    CHECK([f.events indexOfObject:@"return-unexpected"]==NSNotFound);
    CHECK(![f.journal[@"knownFile"][@"newVerified"] boolValue]&&![f.journal[@"knownFile"][@"committed"] boolValue]);

    f=make();f.failAfterFirstPlacement=YES;error=nil;
    CHECK(![f replaceAbsoluteFile:target() data:payload error:&error]);
    f.failVerifyRead=YES;error=nil;
    CHECK(![f readBackInterruptedReplacement:&error]);CHECK(error.code==1);
    CHECK([f.nodes[f.journal[@"knownFile"][@"Verify"]] isEqual:payload]&&[f.localOriginal isEqual:original]);
    CHECK(![f.journal[@"knownFile"][@"readBackMismatch"] boolValue]);
    CHECK(![f.journal[@"knownFile"][@"newVerified"] boolValue]&&![f.journal[@"knownFile"][@"committed"] boolValue]);
}return 0;}
'''.replace("__PRODUCTION__", match_completed + "\n" + return_replacement + "\n" + read_interrupted + "\n" + place + "\n" + replace)

build = ROOT / ".test-build"
build.mkdir(exist_ok=True)
path = build / "known-write.m"
path.write_text(fixture, encoding="utf-8")
if "--emit-only" in sys.argv:
    print(path)
elif sys.platform != "darwin":
    raise SystemExit("Runtime regression requires macOS Foundation; use --emit-only for cross-compilation.")
else:
    binary = build / "known-write"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra",
                    "-Wno-unused-parameter", str(path), "-framework", "Foundation", "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
    print("PASS: production replacement flow, 24 scenario groups; mocked AFC/ATC, no iPhone I/O.")
