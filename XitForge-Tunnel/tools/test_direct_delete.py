"""Exercise the production panel-delete entry point; transport is simulated."""
from pathlib import Path
import runpy
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
saved=sys.argv[:]
sys.argv=[str(root/'tools/test_direct_write.py'),'--emit-only']
ns=runpy.run_path(sys.argv[0])
sys.argv=saved
entry=(root/'module/XFATCDirectDelete.inc').read_text(encoding='utf-8')
for forbidden in ('recoverPending','recoverRegistered','persistKnownOriginal','finishKnownFile','returnKnown'):
    assert forbidden not in entry, forbidden
assert '[directory deleteConfiguredAbsoluteFile:absolute error:&failure]' in (root/'module/XFAirLiftBackend.m').read_text(encoding='utf-8')
fixture=ns['fixture'][:ns['fixture'].index('int main(void)')]
fixture=fixture.replace('@property BOOL closed;', '''@property BOOL closed;
@property BOOL targetQueryable;
@property BOOL wrongTargetKind;
@property BOOL failTrashRemove;
@property BOOL deletionAbsenceConfirmed;
@property NSURL *deletedFileBackupURL;''')
fixture=fixture.replace(ns['entry'],entry+'\n'+ns['entry'])
needle=' id value=self.nodes[path];if(missing)*missing=value==nil;'
fixture=fixture.replace(needle,''' if([path isEqual:[self knownFileDestination]]) {
  if(self.wrongTargetKind){if(missing)*missing=NO;return @{@"kind":@"S_IFDIR",@"size":@0};}
  if(!self.targetQueryable){if(missing)*missing=NO;if(error)*error=[NSError errorWithDomain:@"XitForge.ATCDirectory" code:106 userInfo:@{@"NativeSubcode":@10}];return nil;}
  if(missing)*missing=self.applicationBytes==nil;
  return self.applicationBytes?@{@"kind":@"S_IFREG",@"size":@(self.applicationBytes.length)}:nil;
 }
'''+needle)
fixture=fixture.replace('- (NSArray *)knownFilePair:', '- (NSArray *)knownFileAssetIDs:(NSDictionary *)journal {return @[@"link",@"target",@"unused",@"incoming",@"unused2"]; }\n- (NSArray *)knownFilePair:')
fixture=fixture.replace(' if(!self.noTransfer){',''' if(!self.noTransfer&&[pairs[0][@"source"] isEqual:@1]) {
  if(!self.applicationBytes){if(error)*error=XFATCError(6,@"missing target");return NO;}
  self.nodes[self.journal[@"knownFile"][@"Incoming"]]=self.applicationBytes;
  self.applicationBytes=nil;
 }else if(!self.noTransfer){''')
fixture=fixture.replace('self.denySourceQuery||self.nodes[path]', 'self.denySourceQuery||(missing?self.nodes[path]!=nil:self.nodes[path]==nil)')
fixture=fixture.replace(' [self.nodes removeObjectForKey:path];return YES;', ''' if(self.failTrashRemove&&[path hasSuffix:@"FileIncoming"]){if(error)*error=XFATCError(8,@"remove denied");return NO;}
 [self.nodes removeObjectForKey:path];return YES;''')
fixture+=r'''
int main(void){@autoreleasepool {
 NSError *error=nil;DirectWriteTest *f=make();NSMutableDictionary *old=f.journal;
 CHECK([f deleteConfiguredAbsoluteFile:target() error:&error]);
 CHECK(f.applicationBytes==nil&&f.nodes[@"new-owned-stage/FileIncoming"]==nil);
 CHECK(f.sends==1&&[f.moves[0][@"source"] isEqual:@1]);
 CHECK(f.journal==old&&f.closed&&!f.directWriteActive&&f.deletedFileBackupURL==nil);
 CHECK([f.nodes[@"Books/Sync/Books.plist"] isEqual:bytes(@"old transport metadata")]);
 CHECK([f.nodes[@"Books/XitForgeOwner.plist"] isEqual:bytes(@"old foreign marker")]);
 CHECK([f.nodes[@"old-retained-backup"] isEqual:bytes(@"old backup")]);
 CHECK([f.fileOperationDiagnostics[@"committed"] boolValue]);
 f=make();f.targetQueryable=YES;f.applicationBytes=nil;
 CHECK([f deleteConfiguredAbsoluteFile:target() error:&error]&&f.sends==0&&f.deletionAbsenceConfirmed);
 for(NSUInteger fault=0;fault<8;fault++) {
  f=make();old=f.journal;switch(fault){case 0:f.failPrepare=YES;break;case 1:f.failManifest=YES;break;
   case 2:f.failATC=YES;break;case 3:f.corruptLink=YES;break;case 4:f.failSend=YES;break;
   case 5:f.noTransfer=YES;break;case 6:f.denySourceQuery=YES;break;case 7:f.failTrashRemove=YES;break;}
  error=nil;CHECK(![f deleteConfiguredAbsoluteFile:target() error:&error]&&error!=nil);
  CHECK(![f.fileOperationDiagnostics[@"committed"] boolValue]&&f.sends<=1);
  CHECK(f.journal==old&&f.closed&&!f.directWriteActive);
  CHECK([f.nodes[@"Books/XitForgeOwner.plist"] isEqual:bytes(@"old foreign marker")]);
  if(fault<6)CHECK([f.applicationBytes isEqual:bytes(@"old app file")]);
  if(fault==7)CHECK(f.nodes[@"new-owned-stage/FileIncoming"]!=nil&&f.applicationBytes==nil);
 }
 f=make();f.wrongTargetKind=YES;CHECK(![f deleteConfiguredAbsoluteFile:target() error:&error]&&f.sends==0);
 f=make();CHECK(![f deleteConfiguredAbsoluteFile:@"/bad" error:&error]&&f.sends==0);
}return 0;}
'''
build=root/'.test-build';build.mkdir(exist_ok=True)
path=build/'direct-delete.m';path.write_text(fixture,encoding='utf-8')
if '--emit-only' in sys.argv:print(path)
elif sys.platform!='darwin':raise SystemExit('Runtime regression requires macOS; use --emit-only for cross-compilation.')
else:
    binary=build/'direct-delete'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Wno-unused-parameter',str(path),'-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
    print('PASS: 12 production direct-delete scenarios; simulated transport, no iPhone I/O.')
