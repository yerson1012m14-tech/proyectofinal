"""Run the real direct-write entry point with simulated transport on macOS."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = (root / 'module/XFATCDirectWrite.inc').read_text(encoding='utf-8')
entry = source[source.index('- (BOOL)writeDownloadedAbsoluteFile:'):]
prepare = source[:source.index('- (BOOL)writeDownloadedAbsoluteFile:')]
for forbidden in ('recoverPending', 'recoverRegistered', 'observeKnownOriginal',
                  'persistKnownOriginal', 'finishKnownFile', 'returnKnown', 'readBackInterrupted'):
    assert forbidden not in source, forbidden
assert 'ids[1]' not in prepare and 'ids[2]' not in prepare and 'ids[4]' not in prepare
backend = (root / 'module/XFAirLiftBackend.m').read_text(encoding='utf-8')
assert '[directory writeDownloadedAbsoluteFile:absolute data:replacement error:&failure]' in backend
assert 'recoverPendingTransaction:' not in backend
assert 'contentsOfDirectoryAtURL:recoveryRoot' not in backend
directory = (root / 'module/XFATCDirectory.m').read_text(encoding='utf-8')
assert 'direct-%@.plist' in directory
home = (root.parents[0] / 'MiApp/HomeViewController.m').read_text(encoding='utf-8')
assert 'if (self.deactivationTargetsAll) return YES;' not in home

fixture = r'''
#import <Foundation/Foundation.h>
#import <stdio.h>
static NSError *XFATCError(NSInteger code, NSString *message) {
 return [NSError errorWithDomain:@"DirectWriteTest" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *XFATCPath(NSString *path) {
 return [path hasPrefix:@"/var/mobile/Containers/Data/Application/"] && ![path containsString:@"/../"]?path:nil;
}
static BOOL XFATCKnownFilePath(NSString *path) { return [path containsString:@"/Documents/"]; }
static NSString *XFATCDigest(NSData *bytes) {return bytes.description;}
static NSData *XFATCPlist(id value, NSError **error) {
 return [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
}
@interface DirectWriteTest : NSObject
@property NSMutableDictionary *journal;
@property NSMutableDictionary *nodes;
@property NSMutableArray *moves;
@property NSMutableArray *batchEvents;
@property NSDictionary *completedKnownWrite;
@property NSDictionary *fileOperationDiagnostics;
@property NSString *lastWarning;
@property BOOL directWriteActive;
@property BOOL batchActive;
@property NSUInteger batchLastPhase;
@property BOOL failPrepare;
@property BOOL failStage;
@property BOOL failManifest;
@property BOOL failATC;
@property BOOL failSend;
@property BOOL noTransfer;
@property BOOL denySourceQuery;
@property BOOL corruptLink;
@property BOOL failCleanup;
@property BOOL changedManifest;
@property BOOL closed;
@property NSData *applicationBytes;
@property NSUInteger sends;
@end
@implementation DirectWriteTest
- (BOOL)prepareDirectWrite:(NSString *)target error:(NSError **)error {
 if(self.failPrepare){if(error)*error=XFATCError(1,@"prepare");return NO;}
 self.journal=[@{@"directWrite":@YES,@"backup":@"new-owned-stage",
  @"knownFile":[@{@"target":target,@"Incoming":@"new-owned-stage/FileIncoming"} mutableCopy],
  @"fileManifest":@{@"Books":@[]}} mutableCopy];return YES;
}
- (BOOL)saveJournal:(NSString *)intent error:(NSError **)error {return YES;}
- (BOOL)writeKnownIncoming:(NSData *)data error:(NSError **)error {
 if(self.failStage){if(error)*error=XFATCError(2,@"stage");return NO;}
 self.nodes[self.journal[@"knownFile"][@"Incoming"]]=data;return YES;
}
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error {
 id value=self.nodes[path];if(missing)*missing=value==nil;
 if(!value)return nil;
 return @{ @"kind":[value isEqual:@"dir"]?@"S_IFDIR":@"S_IFREG",@"size":@([value isKindOfClass:NSData.class]?[value length]:0)};
}
- (BOOL)makeOwnedDirectory:(NSString *)path error:(NSError **)error {self.nodes[path]=@"dir";return YES;}
- (NSData *)readSnapshot:(NSString *)path expectedSize:(NSUInteger)size error:(NSError **)error {return self.nodes[path];}
- (BOOL)writeBooksBytes:(NSData *)bytes path:(NSString *)path error:(NSError **)error {
 if(self.failManifest||(self.failCleanup&&self.sends)){if(error)*error=XFATCError(3,@"manifest");return NO;}
 self.nodes[path]=bytes;return YES;
}
- (BOOL)runATC:(NSError **)error {
 if(self.failATC){if(error)*error=XFATCError(4,@"ATC");return NO;}return YES;
}
- (BOOL)verifyKnownTargetLink:(NSError **)error {
 if(self.corruptLink){if(error)*error=XFATCError(5,@"link");return NO;}return YES;
}
- (NSString *)knownFileDestination {return @"new-generated-link/selected-file";}
- (NSArray *)knownFilePair:(NSUInteger)source destination:(NSString *)destination {
 return @[@{@"source":@(source),@"destination":destination}];
}
- (BOOL)runKnownFilePairs:(NSArray *)pairs error:(NSError **)error {
 self.sends++;[self.moves addObjectsFromArray:pairs];
 if(self.failSend){if(error)*error=XFATCError(6,@"send");return NO;}
 if(!self.noTransfer){
  self.applicationBytes=self.nodes[self.journal[@"knownFile"][@"Incoming"]];
  [self.nodes removeObjectForKey:self.journal[@"knownFile"][@"Incoming"]];
 }
 if(self.changedManifest)self.nodes[@"Books/Sync/Books.plist"]=[@"daemon state" dataUsingEncoding:NSUTF8StringEncoding];
 return YES;
}
- (BOOL)waitKnownFile:(NSString *)path missing:(BOOL)missing error:(NSError **)error {
 if(self.denySourceQuery||self.nodes[path]){if(error)*error=XFATCError(7,@"not confirmed");return NO;}return YES;
}
- (BOOL)removeOwned:(NSString *)path expectedKind:(NSString *)kind error:(NSError **)error {
 [self.nodes removeObjectForKey:path];return YES;
}
- (BOOL)verifyRemoteOwner:(NSError **)error {return YES;}
- (BOOL)cleanGeneratedStage:(NSError **)error {return YES;}
- (void)closeAFC {self.closed=YES;}
__ENTRY__
@end
static NSData *bytes(NSString *s){return [s dataUsingEncoding:NSUTF8StringEncoding];}
static NSString *target(void){return @"/var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000001/Documents/selected-file";}
static DirectWriteTest *make(void){
 DirectWriteTest *f=[DirectWriteTest new];f.moves=[NSMutableArray new];
 f.journal=[@{@"oldPending":@YES} mutableCopy];f.applicationBytes=bytes(@"old app file");
 f.nodes=[@{@"Books":@"dir",@"Books/Sync":@"dir",@"Books/Sync/Books.plist":bytes(@"old transport metadata"),
  @"Books/XitForgeOwner.plist":bytes(@"old foreign marker"),@"old-retained-backup":bytes(@"old backup")} mutableCopy];return f;
}
#define CHECK(x) do {if(!(x)){fprintf(stderr,"Direct write failed at line %d\n",__LINE__);return 1;}}while(0)
int main(void){@autoreleasepool {
 NSError *error=nil;NSData *payload=bytes(@"downloaded option"),*render=bytes(@"downloaded Render original");
 DirectWriteTest *f=make();NSMutableDictionary *old=f.journal;
 CHECK([f writeDownloadedAbsoluteFile:target() data:payload error:&error]);
 CHECK([f.applicationBytes isEqual:payload]&&f.sends==1&&f.moves.count==1);
 CHECK([f.moves[0][@"source"] isEqual:@3]);CHECK(f.journal==old&&f.closed&&!f.directWriteActive);
 CHECK([f.nodes[@"Books/Sync/Books.plist"] isEqual:bytes(@"old transport metadata")]);
 CHECK([f.nodes[@"Books/XitForgeOwner.plist"] isEqual:bytes(@"old foreign marker")]);
 CHECK([f.nodes[@"old-retained-backup"] isEqual:bytes(@"old backup")]);
 CHECK([f.fileOperationDiagnostics[@"committed"] boolValue]&&![f.fileOperationDiagnostics[@"targetReadBackVerified"] boolValue]);
 CHECK([f writeDownloadedAbsoluteFile:target() data:render error:&error]);CHECK([f.applicationBytes isEqual:render]);
 CHECK(f.sends==2&&[f.moves[1][@"source"] isEqual:@3]);
 f=make();CHECK([f writeDownloadedAbsoluteFile:target() data:[NSData data] error:&error]);CHECK(f.applicationBytes.length==0);
 f=make();f.applicationBytes=nil;CHECK([f writeDownloadedAbsoluteFile:target() data:payload error:&error]);CHECK([f.applicationBytes isEqual:payload]);
 f=make();[f.nodes removeObjectForKey:@"Books/Sync/Books.plist"];
 CHECK([f writeDownloadedAbsoluteFile:target() data:payload error:&error]);CHECK(f.nodes[@"Books/Sync/Books.plist"]==nil);
 for(NSUInteger fault=0;fault<8;fault++) {
  f=make();old=f.journal;switch(fault){case 0:f.failPrepare=YES;break;case 1:f.failStage=YES;break;
   case 2:f.failManifest=YES;break;case 3:f.failATC=YES;break;case 4:f.corruptLink=YES;break;
   case 5:f.failSend=YES;break;case 6:f.noTransfer=YES;break;case 7:f.denySourceQuery=YES;break;}
  error=nil;CHECK(![f writeDownloadedAbsoluteFile:target() data:payload error:&error]&&error!=nil);
  CHECK(f.journal==old&&!f.directWriteActive&&f.closed&&f.sends<=1);
  if(fault<7)CHECK([f.applicationBytes isEqual:bytes(@"old app file")]);
  CHECK([f.nodes[@"Books/XitForgeOwner.plist"] isEqual:bytes(@"old foreign marker")]);
 }
 f=make();f.failCleanup=YES;CHECK([f writeDownloadedAbsoluteFile:target() data:payload error:&error]);CHECK(f.lastWarning.length);
 f=make();f.changedManifest=YES;CHECK([f writeDownloadedAbsoluteFile:target() data:payload error:&error]);
 CHECK([f.nodes[@"Books/Sync/Books.plist"] isEqual:bytes(@"daemon state")]);
 f=make();CHECK(![f writeDownloadedAbsoluteFile:@"/bad/path" data:payload error:&error]);CHECK(f.sends==0);
}return 0;}
'''.replace('__ENTRY__', entry)
build = root / '.test-build'
build.mkdir(exist_ok=True)
path = build / 'direct-write.m'
path.write_text(fixture, encoding='utf-8')
if '--emit-only' in sys.argv:
    print(path)
elif sys.platform != 'darwin':
    raise SystemExit('Runtime test requires macOS Foundation; use --emit-only for cross-compilation.')
else:
    binary = build / 'direct-write'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra',
                    '-Wno-unused-parameter', str(path), '-framework', 'Foundation', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
    print('PASS: downloaded Activate/Deactivate, no original capture/recovery; 16 simulated cases.')
