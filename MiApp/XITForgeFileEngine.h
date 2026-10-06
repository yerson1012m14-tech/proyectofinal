#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XITForgeFileEngine : NSObject
+ (BOOL)tunnelFallbackConfigured;
+ (BOOL)tunnelReadyForHome;
+ (nullable NSString *)relativePathForRoute:(NSString *)route
                                   fileName:(NSString *)fileName
                                      error:(NSString * _Nullable * _Nullable)errorOut;
+ (void)replaceFileViaTunnelFromURL:(NSURL *)sourceURL
                           bundleID:(NSString *)bundleID
                              route:(NSString *)route
                           fileName:(NSString *)fileName
                         completion:(void (^)(BOOL success, NSString *message))completion;
+ (void)deleteFileViaTunnelForBundleID:(NSString *)bundleID
                                 route:(NSString *)route
                              fileName:(NSString *)fileName
                            completion:(void (^)(BOOL success, NSString *message))completion;
@end

NS_ASSUME_NONNULL_END
