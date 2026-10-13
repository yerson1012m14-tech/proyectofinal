#import <Foundation/Foundation.h>

@interface XFLocalVPNManager : NSObject

+ (void)connectWithPeerAddress:(NSString *)address completion:(void (^)(NSError *error))completion;


@end

