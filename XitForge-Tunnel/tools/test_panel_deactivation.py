"""Check the production action planner with originals/delete-files server schema."""
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
repo=root.parent
engine=(repo/'MiApp/XITForgeFileEngine.m').read_text(encoding='utf-8')
def method(signature):
    start=engine.index(signature)
    end=engine.find('\n+ (',start+len(signature))
    return engine[start:end]
helpers='\n'.join(method(signature) for signature in (
    '+ (BOOL)isSafeComponent:(NSString *)component {',
    '+ (NSString *)normalizedRootComponent:(NSString *)component {',
    '+ (NSString *)relativePathForRoute:(NSString *)route'))
plan=(repo/'MiApp/XITForgeDeactivationPlan.h').read_text(encoding='utf-8')
plan='\n'.join(line for line in plan.splitlines() if not line.startswith('#import'))
ui=(repo/'MiApp/XITForgePanelDeactivation.inc').read_text(encoding='utf-8')
assert 'fetchDeactivationList:@"delete-files"' in ui and 'fetchDeactivationList:@"originals"' in ui
assert 'deactivateUsingLegacyOptionsFallback' not in ui
fixture=r'''
#import <Foundation/Foundation.h>
#import <stdio.h>
@interface XITForgeFileEngine:NSObject
+ (BOOL)isSafeComponent:(NSString *)component;
+ (NSString *)normalizedRootComponent:(NSString *)component;
+ (NSString *)relativePathForRoute:(NSString *)route fileName:(NSString *)fileName error:(NSString **)error;
@end
@implementation XITForgeFileEngine
__HELPERS__
@end
__PLAN__
static NSDictionary *dest(NSString *file){return @{@"route":@"Documents",@"fileName":file,@"bundleId":@"com.dts.freefireth"};}
static NSDictionary *orig(NSString *file){return @{@"id":@900,@"route":@"Documents",@"fileName":file,@"originalFileUrl":@"/api/app/originals/900/file"};}
static NSDictionary *rule(NSString *file,NSNumber *option){return @{@"id":@11,@"optionId":option,@"route":@"Documents",@"fileName":file,@"bundleId":@"com.dts.freefireth"};}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"Panel planner failed at line %d\n",__LINE__);return 1;}}while(0)
int main(void){@autoreleasepool {
 NSSet *ids=[NSSet setWithObject:@7];NSString *error=nil;NSArray *a;
 a=XFPanelDeactivationPlan(@[orig(@"clean.cfg")],@[],@[dest(@"clean.cfg")],ids,&error);
 CHECK(a.count==1&&[a[0][@"action"] isEqual:@"replace"]&&[a[0][@"id"] isEqual:@900]);
 a=XFPanelDeactivationPlan(@[],@[rule(@"delete.cfg",@7)],@[dest(@"delete.cfg")],ids,&error);
 CHECK(a.count==1&&[a[0][@"action"] isEqual:@"delete"]);
 a=XFPanelDeactivationPlan(@[orig(@"clean.cfg")],@[rule(@"delete.cfg",@7)],@[dest(@"clean.cfg"),dest(@"delete.cfg")],ids,&error);
 CHECK(a.count==2&&[a[0][@"action"] isEqual:@"replace"]&&[a[1][@"action"] isEqual:@"delete"]);
 a=XFPanelDeactivationPlan(@[orig(@"same.cfg")],@[rule(@"same.cfg",@7)],@[dest(@"same.cfg")],ids,&error);
 CHECK(a.count==1&&[a[0][@"action"] isEqual:@"delete"]);
 a=XFPanelDeactivationPlan(@[],@[rule(@"same.cfg",@8)],@[dest(@"same.cfg")],ids,&error);CHECK(a==nil&&error.length);
 a=XFPanelDeactivationPlan(@[orig(@"clean.cfg"),orig(@"unrelated.cfg")],@[rule(@"unrelated.cfg",@8)],@[dest(@"clean.cfg")],ids,&error);CHECK(a.count==1);
 a=XFPanelDeactivationPlan(@[orig(@"clean.cfg")],@[rule(@"extra.cfg",@7)],@[dest(@"clean.cfg")],ids,&error);CHECK(a.count==2&&[a[1][@"fileName"] isEqual:@"extra.cfg"]);
 a=XFPanelDeactivationPlan(@[orig(@"clean.cfg"),orig(@"clean.cfg")],@[rule(@"delete.cfg",@7),rule(@"delete.cfg",@7)],@[dest(@"clean.cfg"),dest(@"clean.cfg"),dest(@"delete.cfg")],ids,&error);CHECK(a.count==2);
 a=XFPanelDeactivationPlan(@[orig(@"clean.cfg")],@[],@[dest(@"clean.cfg"),dest(@"missing.cfg")],ids,&error);CHECK(a==nil);
 NSMutableDictionary *other=[orig(@"clean.cfg") mutableCopy];other[@"route"]=@"Library";
 a=XFPanelDeactivationPlan(@[other],@[],@[dest(@"clean.cfg")],ids,&error);CHECK(a==nil);
 NSMutableDictionary *invalid=[rule(@"delete.cfg",@7) mutableCopy];invalid[@"route"]=@"Documents/..";
 a=XFPanelDeactivationPlan(@[],@[invalid],@[dest(@"delete.cfg")],ids,&error);CHECK(a==nil);
 a=XFPanelDeactivationPlan(@[],@[],@[],ids,&error);CHECK(a==nil);
}return 0;}
'''.replace('__HELPERS__',helpers).replace('__PLAN__',plan)
build=root/'.test-build';build.mkdir(exist_ok=True)
path=build/'panel-deactivation.m';path.write_text(fixture,encoding='utf-8')
if '--emit-only' in sys.argv:print(path)
elif sys.platform!='darwin':raise SystemExit('Runtime regression requires macOS; use --emit-only for cross-compilation.')
else:
    binary=build/'panel-deactivation'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra',str(path),'-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
    print('PASS: 12 production planner cases; replace/delete/mixed, missing original, unrelated rules, duplicate paths.')
