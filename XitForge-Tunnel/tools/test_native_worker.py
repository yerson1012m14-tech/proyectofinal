"""Exercise the production NSThread worker on macOS, without device services."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = (root / 'module/XFAirLiftBackend.m').read_text(encoding='utf-8')
start = source.index('@interface XFNativeWorker : NSObject')
end = source.index('@interface XFAirLiftBackend ()', start)
fixture = r'''
int main(void) {
    @autoreleasepool {
        XFNativeWorker *worker=[XFNativeWorker new];
        __block int result=0;
        [worker perform:^{ result=17; }];
        if(result!=17)return 1;
        BOOL caught=NO;
        @try {
            [worker perform:^{ [NSException raise:@"ProbeWorkerFixture" format:@"Injected test exception"]; }];
        } @catch(NSException *e) { caught=[e.name isEqual:@"ProbeWorkerFixture"]; }
        if(!caught)return 2;
        [worker perform:^{ result=23; }];
        if(result!=23)return 3;
        caught=NO;
        @try {
            [worker perform:^{ [worker perform:^{ [NSException raise:@"NestedFixture" format:@"Nested test"]; }]; }];
        } @catch(NSException *e) { caught=[e.name isEqual:@"NestedFixture"]; }
        if(!caught)return 4;
        [worker stop];
        for(int i=0;i<1000&&worker.thread.executing;i++)[NSThread sleepForTimeInterval:0.001];
        if(worker.thread.executing)return 5;
    }
    return 0;
}
'''
build = root / '.test-build'
build.mkdir(exist_ok=True)
test = build / 'native-worker.m'
test.write_text('#import <Foundation/Foundation.h>\n'+source[start:end]+fixture,encoding='utf-8')
if '--emit-only' in sys.argv:
    print(test)
elif sys.platform != 'darwin':
    raise SystemExit('This execution test requires macOS Foundation; use --emit-only for cross-compilation.')
else:
    binary=build/'native-worker'
    subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra',str(test),
                    '-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=15)
    print('PASS: worker completion, exception propagation, nested call, continued execution and shutdown.')
