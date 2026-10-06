"""Run the real legacy Books copy methods with mocked AFC on macOS.

The complete original tree remains in the remote backup. Native device I/O is
modeled; local snapshots and journal durability use actual Foundation/POSIX I/O.
Use --emit-only on other platforms to prepare a syntax-check fixture.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "module/XFATCDirectory.m").read_text(encoding="utf-8")
PRODUCTION = (ROOT / "module/XFATCLegacyBooksRecovery.inc").read_text(encoding="utf-8")
assert "afc_rename_path" not in PRODUCTION and "renameOwned:" not in PRODUCTION


def between(start, end):
    index = SOURCE.index(start)
    return SOURCE[index:SOURCE.index(end, index)]


def method(signature):
    index = SOURCE.index(signature)
    return SOURCE[index:SOURCE.index("\n}\n", index + len(signature)) + 3]


HELPERS = between("static BOOL XFATCComponent", "static NSString *XFATCPath")
HELPERS += between("static NSData *XFATCPlist", "static NSArray<NSString *> *XFATCDirectories")
CLEAN = method("- (BOOL)cleanExactTemporaryBooks:(NSString *)root error:(NSError **)error {")

FIXTURE = r'''
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <stdint.h>
#include <stdio.h>
static NSError *XFATCError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"LegacyBooksFixture" code:code
        userInfo:@{NSLocalizedDescriptionKey:message}];
}
__HELPERS__
@interface LegacyBooksFixture : NSObject
@property NSMutableDictionary *journal;
@property NSURL *journalURL;
@property NSMutableDictionary *nodes;
@property NSString *failWrite;
@property BOOL partialWrite;
@property NSString *failRemoval;
@property BOOL mutateSourceAfterBookWrite;
@property BOOL failRootIdentityInfo;
@property NSUInteger serial;
@property NSUInteger writes;
@property NSUInteger renames;
- (NSDictionary *)ownerRecord;
- (NSURL *)activeURL;
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error;
- (NSArray *)names:(NSString *)path error:(NSError **)error;
- (NSData *)readSnapshot:(NSString *)path expectedSize:(NSUInteger)size error:(NSError **)error;
- (BOOL)saveJournal:(NSString *)stage error:(NSError **)error;
- (BOOL)verifyRemoteOwner:(NSError **)error;
- (BOOL)booksOwnerMatches:(NSString *)path error:(NSError **)error;
- (BOOL)makeOwnedDirectory:(NSString *)path error:(NSError **)error;
- (BOOL)writeOwned:(NSData *)bytes path:(NSString *)path error:(NSError **)error;
- (BOOL)removeOwned:(NSString *)path expectedKind:(NSString *)kind error:(NSError **)error;
- (BOOL)cleanExactTemporaryBooks:(NSString *)root error:(NSError **)error;
- (BOOL)restoreLegacyBooksCopy:(NSError **)error;
- (BOOL)validLegacyBooksCopyJournal:(NSDictionary *)journal;
- (void)directory:(NSString *)path;
- (void)file:(NSString *)path bytes:(NSData *)bytes;
@end
@implementation LegacyBooksFixture
- (void)directory:(NSString *)path {
    self.nodes[path]=[@{@"kind":@"S_IFDIR",@"creation":@(++self.serial),@"mtimeNS":@1} mutableCopy];
}
- (void)file:(NSString *)path bytes:(NSData *)bytes {
    self.nodes[path]=[@{@"kind":@"S_IFREG",@"data":bytes,@"creation":@(++self.serial),@"mtimeNS":@1} mutableCopy];
}
- (NSDictionary *)ownerRecord {return @{@"module":@"XitForgeATCDirectory",@"version":@1,@"token":self.journal[@"token"],@"namespace":@"fixture"};}
- (NSURL *)activeURL {return [self.journalURL URLByAppendingPathComponent:@"active.plist"];}
- (BOOL)saveJournal:(NSString *)stage error:(NSError **)error {
    self.journal[@"intent"]=stage;NSData *bytes=XFATCPlist(self.journal,error);
    return bytes&&[bytes writeToURL:self.activeURL options:NSDataWritingAtomic error:error];
}
- (NSDictionary *)info:(NSString *)path missing:(BOOL *)missing error:(NSError **)error {
    NSDictionary *node=self.nodes[path];if(missing)*missing=node==nil;if(!node)return nil;
    NSDictionary *copy=self.journal[@"legacyBooksCopy"];
    if(self.failRootIdentityInfo&&[path isEqual:@"Books"]&&[copy[@"rootCreateIntent"] boolValue]&&!copy[@"rootInfo"]) {
        if(missing)*missing=NO;if(error)*error=XFATCError(1,@"Injected interruption before root identity persisted");return nil;
    }
    return @{@"kind":node[@"kind"],@"size":@([node[@"data"] length]),@"creation":node[@"creation"],
        @"mtimeNS":node[@"mtimeNS"],@"modified":@0,@"blocks":@0};
}
- (NSArray *)names:(NSString *)path error:(NSError **)error {
    NSMutableArray *names=[NSMutableArray new];NSString *prefix=[path stringByAppendingString:@"/"];
    for(NSString *key in self.nodes)if([key hasPrefix:prefix]) {
        NSString *tail=[key substringFromIndex:prefix.length];if(![tail containsString:@"/"])[names addObject:tail];
    }
    return names;
}
- (NSData *)readSnapshot:(NSString *)path expectedSize:(NSUInteger)size error:(NSError **)error {
    NSDictionary *node=self.nodes[path];NSData *data=node[@"data"];
    return [node[@"kind"] isEqual:@"S_IFREG"]&&data.length==size?data:nil;
}
- (BOOL)verifyRemoteOwner:(NSError **)error {return YES;}
- (BOOL)booksOwnerMatches:(NSString *)path error:(NSError **)error {
    NSData *bytes=self.nodes[[path stringByAppendingPathComponent:@"XitForgeOwner.plist"]][@"data"];
    return bytes&&[[NSPropertyListSerialization propertyListWithData:bytes options:0 format:NULL error:error] isEqual:self.ownerRecord];
}
- (BOOL)makeOwnedDirectory:(NSString *)path error:(NSError **)error {
    if(self.nodes[path])return [self.nodes[path][@"kind"] isEqual:@"S_IFDIR"];
    if(![self saveJournal:[@"mkdir " stringByAppendingString:path] error:error])return NO;
    [self directory:path];return YES;
}
- (BOOL)writeOwned:(NSData *)bytes path:(NSString *)path error:(NSError **)error {
    if(self.nodes[path])return NO;
    if(![self saveJournal:[@"write " stringByAppendingString:path] error:error])return NO;
    if([path isEqual:self.failWrite]) {
        if(self.partialWrite)[self file:path bytes:[bytes subdataWithRange:NSMakeRange(0,bytes.length/2)]];
        if(error)*error=XFATCError(1,@"Injected interrupted copy");return NO;
    }
    [self file:path bytes:bytes];self.writes++;
    if(self.mutateSourceAfterBookWrite&&[path isEqual:@"Books/user-book.epub"])
        self.nodes[@"backup/Books/user-book.epub"][@"data"]=[@"daemon changed book" dataUsingEncoding:NSUTF8StringEncoding];
    return YES;
}
- (BOOL)removeOwned:(NSString *)path expectedKind:(NSString *)kind error:(NSError **)error {
    NSDictionary *node=self.nodes[path];if(!node)return YES;
    if(![node[@"kind"] isEqual:kind])return NO;
    if([path isEqual:self.failRemoval]) {self.failRemoval=nil;if(error)*error=XFATCError(1,@"Injected interrupted marker removal");return NO;}
    if([kind isEqual:@"S_IFDIR"]&&[[self names:path error:error] count])return NO;
    if(![self saveJournal:[@"remove " stringByAppendingString:path] error:error])return NO;
    [self.nodes removeObjectForKey:path];return YES;
}
- (BOOL)renameOwned:(NSString *)source to:(NSString *)target error:(NSError **)error {
    self.renames++;if(error)*error=XFATCError(106,@"Forbidden rename");return NO;
}
__CLEAN__
__PRODUCTION__
@end
static NSData *bytes(NSString *value){return [value dataUsingEncoding:NSUTF8StringEncoding];}
static LegacyBooksFixture *make(BOOL temporary) {
    LegacyBooksFixture *f=[LegacyBooksFixture new];f.nodes=[NSMutableDictionary new];
    f.journalURL=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:f.journalURL withIntermediateDirectories:YES attributes:nil error:NULL];
    f.journal=[@{@"token":NSUUID.UUID.UUIDString.lowercaseString,@"backup":@"backup",@"booksOriginallyPresent":@YES,
        @"booksRestored":@NO,@"booksIsolationStarted":@YES,@"fileManifest":@{@"Books":@[]}} mutableCopy];
    [f directory:@"backup"];[f directory:@"backup/Books"];[f directory:@"backup/Books/Sync"];
    [f directory:@"backup/Books/Untracked"];[f directory:@"backup/Books/Untracked/Empty"];
    [f file:@"backup/Books/Sync/Books.plist" bytes:bytes(@"original Books manifest")];
    [f file:@"backup/Books/user-book.epub" bytes:bytes(@"untracked original book")];
    [f file:@"backup/Books/Untracked/extra.dat" bytes:NSData.data];
    if(temporary) {
        [f directory:@"Books"];[f directory:@"Books/Sync"];
        [f file:@"Books/Sync/Books.plist" bytes:XFATCPlist(XFATCBooksManifest(f.journal),NULL)];
        [f file:@"Books/XitForgeOwner.plist" bytes:XFATCPlist(f.ownerRecord,NULL)];
    }
    return f;
}
static NSDictionary *backupNodes(LegacyBooksFixture *f) {
    NSMutableDictionary *result=[NSMutableDictionary new];
    for(NSString *key in f.nodes)if([key isEqual:@"backup/Books"]||[key hasPrefix:@"backup/Books/"])result[key]=[f.nodes[key] copy];
    return result;
}
static void reconnect(LegacyBooksFixture *f) {
    f.journal=[NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:f.activeURL]
        options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"Legacy Books fixture failed at line %d\n",__LINE__);return 1;}}while(0)
int main(void){@autoreleasepool{
    NSError *error=nil;LegacyBooksFixture *f=make(YES);NSDictionary *before=backupNodes(f);
    CHECK([f restoreLegacyBooksCopy:&error]);CHECK(error==nil);CHECK(f.renames==0);
    CHECK([backupNodes(f) isEqual:before]);CHECK([f.journal[@"legacyCopyRestored"] boolValue]);
    CHECK([f.journal[@"booksRestored"] boolValue]);CHECK([f validLegacyBooksCopyJournal:f.journal]);
    CHECK([f.nodes[@"Books/user-book.epub"][@"data"] isEqual:bytes(@"untracked original book")]);
    CHECK([f.nodes[@"Books/Sync/Books.plist"][@"data"] isEqual:bytes(@"original Books manifest")]);
    CHECK(f.nodes[@"Books/Untracked/Empty"]!=nil);CHECK([f.nodes[@"Books/Untracked/extra.dat"][@"data"] isEqual:NSData.data]);
    CHECK(f.nodes[@"Books/XitForgeOwner.plist"]==nil);reconnect(f);CHECK([f restoreLegacyBooksCopy:NULL]);
    CHECK([backupNodes(f) isEqual:before]);

    /* Complete files survive interruption and reconnect; remaining files are copied. */
    f=make(YES);before=backupNodes(f);f.failWrite=@"Books/user-book.epub";error=nil;
    CHECK(![f restoreLegacyBooksCopy:&error]);CHECK(error!=nil);CHECK(f.nodes[@"Books/XitForgeOwner.plist"]!=nil);
    CHECK(f.nodes[@"Books/Sync/Books.plist"]!=nil);CHECK(f.nodes[@"Books/user-book.epub"]==nil);
    reconnect(f);f.failWrite=nil;CHECK([f restoreLegacyBooksCopy:NULL]);CHECK([backupNodes(f) isEqual:before]);CHECK(f.renames==0);

    /* An occupied foreign root, including one carrying an owned marker plus extra data, is preserved. */
    f=make(YES);[f file:@"Books/foreign.epub" bytes:bytes(@"foreign book")];NSDictionary *foreign=[f.nodes copy];
    CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.nodes isEqual:foreign]);CHECK(f.journal[@"legacyBooksCopy"]==nil);

    /* Tampering with any durable local source is rejected before the next remote write. */
    f=make(YES);f.failWrite=@"Books/user-book.epub";CHECK(![f restoreLegacyBooksCopy:NULL]);
    reconnect(f);f.failWrite=nil;NSDictionary *record=f.journal[@"legacyBooksCopy"],*bookRow=nil;
    for(NSDictionary *row in record[@"entries"])if([row[@"path"] isEqual:@"user-book.epub"])bookRow=row;
    NSURL *local=[[f.journalURL URLByAppendingPathComponent:record[@"snapshotDirectory"]] URLByAppendingPathComponent:bookRow[@"snapshot"]];
    CHECK([bytes(@"corrupt original bytes!") writeToURL:local atomically:YES]);foreign=[f.nodes copy];
    CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.nodes isEqual:foreign]);CHECK(![f.journal[@"booksRestored"] boolValue]);

    /* Source symlinks are never traversed, copied, or deleted. */
    f=make(YES);f.nodes[@"backup/Books/untrusted-link"]=[@{@"kind":@"S_IFLNK",@"creation":@999,@"mtimeNS":@1} mutableCopy];
    foreign=[f.nodes copy];CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.nodes isEqual:foreign]);CHECK(f.journal[@"legacyBooksCopy"]==nil);

    /* Partial or externally changed destination files are retained without truncation. */
    f=make(YES);f.failWrite=@"Books/user-book.epub";f.partialWrite=YES;CHECK(![f restoreLegacyBooksCopy:NULL]);
    reconnect(f);f.failWrite=nil;NSData *partial=f.nodes[@"Books/user-book.epub"][@"data"];foreign=[f.nodes copy];
    CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.nodes isEqual:foreign]);CHECK([f.nodes[@"Books/user-book.epub"][@"data"] isEqual:partial]);
    f=make(YES);f.failWrite=@"Books/user-book.epub";CHECK(![f restoreLegacyBooksCopy:NULL]);
    reconnect(f);f.failWrite=nil;f.nodes[@"Books/Sync/Books.plist"][@"data"]=bytes(@"new external manifest");foreign=[f.nodes copy];
    CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.nodes isEqual:foreign]);

    /* Durable completion permits a crash before marker removal, and new inode timestamps. */
    f=make(YES);before=backupNodes(f);f.failRemoval=@"Books/XitForgeOwner.plist";
    CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.journal[@"legacyCopyRestored"] boolValue]);CHECK(f.nodes[@"Books/XitForgeOwner.plist"]!=nil);
    reconnect(f);CHECK([f restoreLegacyBooksCopy:NULL]);CHECK(f.nodes[@"Books/XitForgeOwner.plist"]==nil);CHECK([backupNodes(f) isEqual:before]);

    /* Missing Books can be created and fully restored without a generated prior root. */
    f=make(NO);before=backupNodes(f);CHECK([f restoreLegacyBooksCopy:NULL]);CHECK([backupNodes(f) isEqual:before]);
    CHECK([f.nodes[@"Books/user-book.epub"][@"data"] isEqual:bytes(@"untracked original book")]);CHECK(f.renames==0);

    /* A root created before its identity became durable cannot be assumed owned. */
    f=make(NO);f.failRootIdentityInfo=YES;CHECK(![f restoreLegacyBooksCopy:NULL]);reconnect(f);
    CHECK([f.journal[@"legacyBooksCopy"][@"rootCreateIntent"] boolValue]);CHECK(f.journal[@"legacyBooksCopy"][@"rootInfo"]==nil);
    CHECK(f.nodes[@"Books"]!=nil);f.failRootIdentityInfo=NO;foreign=[f.nodes copy];
    CHECK(![f restoreLegacyBooksCopy:NULL]);CHECK([f.nodes isEqual:foreign]);CHECK(![f.journal[@"booksRestored"] boolValue]);

    /* A durably identified empty copy may safely continue after marker creation failed. */
    f=make(NO);before=backupNodes(f);f.failWrite=@"Books/XitForgeOwner.plist";CHECK(![f restoreLegacyBooksCopy:NULL]);reconnect(f);
    CHECK(f.journal[@"legacyBooksCopy"][@"rootInfo"]!=nil);CHECK(f.nodes[@"Books/XitForgeOwner.plist"]==nil);
    f.failWrite=nil;CHECK([f restoreLegacyBooksCopy:NULL]);CHECK([backupNodes(f) isEqual:before]);

    /* The source is checked again after all writes; a daemon change prevents success. */
    f=make(YES);f.mutateSourceAfterBookWrite=YES;CHECK(![f restoreLegacyBooksCopy:NULL]);
    CHECK(![f.journal[@"legacyCopyRestored"] boolValue]);CHECK(![f.journal[@"booksRestored"] boolValue]);CHECK(f.nodes[@"Books/XitForgeOwner.plist"]!=nil);
}return 0;}
'''.replace("__HELPERS__", HELPERS).replace("__CLEAN__", CLEAN).replace("__PRODUCTION__", PRODUCTION)

build = ROOT / ".test-build"
build.mkdir(exist_ok=True)
path = build / "legacy-books.m"
path.write_text(FIXTURE, encoding="utf-8")
if "--emit-only" in sys.argv:
    print(path)
elif sys.platform != "darwin":
    raise SystemExit("Runtime regression requires macOS Foundation; use --emit-only for cross-compilation.")
else:
    binary = build / "legacy-books"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra",
                    "-Wno-unused-parameter", str(path), "-framework", "Foundation", "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: production legacy Books copy, 12 scenarios; mocked AFC, full original tree retained.")
