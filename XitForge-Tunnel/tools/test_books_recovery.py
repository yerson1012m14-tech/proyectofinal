"""Run production Books fallback/recovery methods with an in-memory AFC endpoint on macOS."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
source = (root / 'module/XFATCDirectory.m').read_text(encoding='utf-8')
def method(signature):
    start = source.index(signature)
    end = source.index('\n- (', start + len(signature))
    return source[start:end]
# Cover the actual Home preparation entry point, not only standalone helpers.
preparation = method('- (BOOL)prepareKnownFile:(NSString *)target operation:(NSString *)operation error:(NSError **)error {')
assert '[self isolateBooks:error]' in preparation, 'Home must use the Books fallback during isolation'
assert '[self installWorkingBooks:working error:error]' in preparation, 'Home must use the Books fallback during installation'
assert '[self renameOwned:@"Books"' not in preparation, 'Home still bypasses the Books fallback'
assert '[self renameOwned:working' not in preparation, 'Home still bypasses manifest installation'
def static(start, end):
    return source[source.index(start):source.index(end, source.index(start))]
helpers = static('static NSArray<NSString *> *XFATCTrackedFiles', 'static BOOL XFATCHash')
helpers += static('static BOOL XFATCSyncURL', 'static NSArray<NSString *> *XFATCDirectories')
production = '\n'.join(method(s) for s in [
    '- (BOOL)beginBooksInPlace:', '- (BOOL)isolateBooks:',
    '- (BOOL)installWorkingBooks:', '- (BOOL)restoreBooksInPlace:'])
fixture = r'''
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
static NSError *XFATCError(NSInteger code, NSString *text) {
    return [NSError errorWithDomain:@"BooksFixture" code:code userInfo:@{NSLocalizedDescriptionKey:text}];
}
__HELPERS__
@interface BooksFixture : NSObject
@property NSMutableDictionary *journal;
@property NSURL *journalURL;
@property NSMutableDictionary *nodes;
@property NSDictionary *seed;
@property NSString *failWrite;
@property BOOL failMarkerRemoval;
@property NSInteger renameSubcode;
- (NSDictionary *)ownerRecord;
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error;
- (BOOL)preimageMatches:(NSString *)path error:(NSError **)error;
- (BOOL)saveJournal:(NSString *)stage error:(NSError **)error;
- (BOOL)makeOwnedDirectory:(NSString *)path error:(NSError **)error;
- (BOOL)writeOwned:(NSData *)data path:(NSString *)path error:(NSError **)error;
- (BOOL)booksOwnerMatches:(NSString *)path error:(NSError **)error;
- (BOOL)renameOwned:(NSString *)from to:(NSString *)to error:(NSError **)error;
- (NSData *)readSnapshot:(NSString *)path expectedSize:(NSUInteger)size error:(NSError **)error;
- (BOOL)writeBooksBytes:(NSData *)bytes path:(NSString *)path error:(NSError **)error;
- (BOOL)removeOwned:(NSString *)path expectedKind:(NSString *)kind error:(NSError **)error;
- (NSArray *)names:(NSString *)path error:(NSError **)error;
- (BOOL)restoreBooksInPlace:(NSError **)error;
- (BOOL)isolateBooks:(NSError **)error;
- (BOOL)installWorkingBooks:(NSString *)working error:(NSError **)error;
@end
@implementation BooksFixture
- (NSDictionary *)ownerRecord { return @{@"token":self.journal[@"token"]}; }
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error {
    id value=self.nodes[path];*missing=value==nil;
    if(!value)return nil;
    return @{@"kind":[value isKindOfClass:NSData.class]?@"S_IFREG":@"S_IFDIR",@"size":@([value isKindOfClass:NSData.class]?[value length]:0)};
}
- (BOOL)preimageMatches:(NSString *)path error:(NSError **)error {
    for(NSString *key in XFATCTrackedFiles())if(![self.nodes[key] isEqual:self.seed[key]]&&(self.nodes[key]||self.seed[key]))return NO;
    return YES;
}
- (BOOL)saveJournal:(NSString *)stage error:(NSError **)error { return YES; }
- (BOOL)makeOwnedDirectory:(NSString *)path error:(NSError **)error {
    if(self.nodes[path])return NO;self.nodes[path]=@YES;return YES;
}
- (BOOL)writeOwned:(NSData *)data path:(NSString *)path error:(NSError **)error {
    if(self.nodes[path])return NO;self.nodes[path]=data;return YES;
}
- (BOOL)booksOwnerMatches:(NSString *)path error:(NSError **)error {
    NSData *data=self.nodes[[path stringByAppendingPathComponent:@"XitForgeOwner.plist"]];
    return data&&[[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error] isEqual:self.ownerRecord];
}
- (BOOL)renameOwned:(NSString *)from to:(NSString *)to error:(NSError **)error {
    if(error)*error=[NSError errorWithDomain:@"Native" code:106 userInfo:@{@"NativeSubcode":@(self.renameSubcode)}];return NO;
}
- (NSData *)readSnapshot:(NSString *)path expectedSize:(NSUInteger)size error:(NSError **)error {
    NSData *value=self.nodes[path];return [value isKindOfClass:NSData.class]&&value.length==size?value:nil;
}
- (BOOL)writeBooksBytes:(NSData *)bytes path:(NSString *)path error:(NSError **)error {
    if([path isEqual:self.failWrite]){if(error)*error=XFATCError(1,@"Injected write failure");return NO;}
    self.nodes[path]=bytes;return YES;
}
- (BOOL)removeOwned:(NSString *)path expectedKind:(NSString *)kind error:(NSError **)error {
    if(self.failMarkerRemoval&&[path isEqual:@"Books/XitForgeOwner.plist"]){self.failMarkerRemoval=NO;return NO;}
    [self.nodes removeObjectForKey:path];return YES;
}
- (NSArray *)names:(NSString *)path error:(NSError **)error {
    NSMutableArray *names=[NSMutableArray new];NSString *prefix=[path stringByAppendingString:@"/"];
    for(NSString *name in self.nodes)if([name hasPrefix:prefix]){
        NSString *tail=[name substringFromIndex:prefix.length];if(![tail containsString:@"/"])[names addObject:tail];
    }
    return names;
}
__PRODUCTION__
@end
static NSData *bytes(NSString *value){return [value dataUsingEncoding:NSUTF8StringEncoding];}
static BooksFixture *make(BOOL existing) {
    BooksFixture *f=[BooksFixture new];f.renameSubcode=7;f.nodes=[NSMutableDictionary new];
    f.journalURL=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:f.journalURL withIntermediateDirectories:YES attributes:nil error:NULL];
    if(existing){f.nodes[@"Books"]=@YES;f.nodes[@"Books/Sync"]=@YES;f.nodes[@"Books/Sync/Database"]=@YES;
        f.nodes[@"Books/Sync/Books.plist"]=bytes(@"original manifest");
        f.nodes[@"Books/Books.plist"]=NSData.data;
        f.nodes[@"Books/user-book.epub"]=bytes(@"unrelated user book");}
    f.seed=[f.nodes copy];NSMutableDictionary *tracked=[NSMutableDictionary new];NSUInteger index=0;
    for(NSString *path in XFATCTrackedFiles()){
        NSData *data=f.nodes[path];NSMutableDictionary *row=[@{@"exists":@(data!=nil)} mutableCopy];
        if(data){NSString *name=[NSString stringWithFormat:@"snapshot-%lu.bin",(unsigned long)index];
            [data writeToURL:[f.journalURL URLByAppendingPathComponent:name] atomically:YES];
            row[@"snapshot"]=name;row[@"info"]=@{@"size":@(data.length)};row[@"snapshotDigest"]=XFATCDigest(data);}
        tracked[path]=row;index++;
    }
    f.journal=[@{@"token":NSUUID.UUID.UUIDString,@"booksOriginallyPresent":@(existing),@"booksRestored":@NO,
        @"backup":@"backup",@"trackedPreimage":tracked,@"fileManifest":@{@"Books":@[]}} mutableCopy];return f;
}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"Books fixture failed at line %d\n",__LINE__);return 1;}}while(0)
int main(void){@autoreleasepool{
    BooksFixture *f=make(YES);CHECK([f isolateBooks:NULL]);CHECK([f.journal[@"booksInPlace"] boolValue]);
    CHECK([f installWorkingBooks:@"backup/WorkingBooks" error:NULL]);
    f.nodes[@"Books/Sync/Upload.plist"]=bytes(@"daemon update to preserve");
    CHECK([f restoreBooksInPlace:NULL]);CHECK([f.nodes[@"Books/Sync/Books.plist"] isEqual:f.seed[@"Books/Sync/Books.plist"]]);
    CHECK([f.nodes[@"Books/Books.plist"] isEqual:NSData.data]);CHECK(f.nodes[@"Books/user-book.epub"]!=nil);
    CHECK(f.nodes[@"Books/Sync/Upload.plist"]==nil);CHECK(f.nodes[@"Books/XitForgeOwner.plist"]==nil);
    CHECK([[NSFileManager.defaultManager contentsOfDirectoryAtURL:f.journalURL includingPropertiesForKeys:nil options:0 error:NULL] count]>=4);
    f=make(NO);CHECK([f installWorkingBooks:@"working" error:NULL]);CHECK([f restoreBooksInPlace:NULL]);CHECK(f.nodes.count==0);
    f=make(YES);f.renameSubcode=10;CHECK(![f isolateBooks:NULL]);CHECK(f.journal[@"booksInPlace"]==nil);CHECK([f.nodes isEqual:f.seed]);
    f=make(YES);f.nodes[@"Books/XitForgeOwner.plist"]=bytes(@"foreign");CHECK(![f isolateBooks:NULL]);CHECK(f.journal[@"booksInPlace"]==nil);
    f=make(YES);f.failWrite=@"Books/Sync/Books.plist";CHECK([f isolateBooks:NULL]);CHECK(![f installWorkingBooks:@"working" error:NULL]);
    f.failWrite=nil;CHECK([f restoreBooksInPlace:NULL]);CHECK([f.nodes isEqual:f.seed]);
    f=make(YES);CHECK([f isolateBooks:NULL]);CHECK([f installWorkingBooks:@"working" error:NULL]);f.failWrite=@"Books/Sync/Books.plist";
    CHECK(![f restoreBooksInPlace:NULL]);CHECK(![f.journal[@"booksRestored"] boolValue]);f.failWrite=nil;CHECK([f restoreBooksInPlace:NULL]);
    CHECK([f.nodes isEqual:f.seed]);
    f=make(YES);CHECK([f isolateBooks:NULL]);CHECK([f installWorkingBooks:@"working" error:NULL]);f.failMarkerRemoval=YES;
    CHECK(![f restoreBooksInPlace:NULL]);CHECK([f.journal[@"booksRestored"] boolValue]);CHECK([f restoreBooksInPlace:NULL]);CHECK([f.nodes isEqual:f.seed]);
    f=make(YES);CHECK([f isolateBooks:NULL]);CHECK([f installWorkingBooks:@"working" error:NULL]);
    NSDictionary *row=f.journal[@"trackedPreimage"][@"Books/Sync/Books.plist"];
    [bytes(@"corrupted snapshot") writeToURL:[f.journalURL URLByAppendingPathComponent:row[@"snapshot"]] atomically:YES];
    CHECK(![f restoreBooksInPlace:NULL]);CHECK(![f.journal[@"booksRestored"] boolValue]);
    CHECK(f.nodes[@"Books/XitForgeOwner.plist"]!=nil);
}return 0;}
'''.replace('__HELPERS__', helpers).replace('__PRODUCTION__', production)
build=root/'.test-build';build.mkdir(exist_ok=True)
path=build/'books-recovery.m';path.write_text(fixture,encoding='utf-8')
if '--emit-only' in sys.argv:print(path)
elif sys.platform!='darwin':raise SystemExit('Runtime regression requires macOS Foundation; use --emit-only for cross-compilation.')
else:
    binary=build/'books-recovery'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra',str(path),'-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
    print('PASS: production Books fallback and recovery, 8 scenarios; mocked AFC, no iPhone I/O.')
