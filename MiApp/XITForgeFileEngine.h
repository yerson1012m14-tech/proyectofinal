#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridge between Home's existing FilzaSlop/MCM path and the optional
/// XitForge tunnel module. Home remains local-first; these helpers are used
/// only when local container access/write/delete fails.
@interface XITForgeFileEngine : NSObject

/// YES when the tunnel module is loaded and this device already has a pairing
/// record. The actual connection is checked/re-established when an operation runs.
+ (BOOL)tunnelFallbackConfigured;

/// Builds the app-relative path expected by XFAirLiftBackend from the panel
/// route + file name (for example Library/foo/bar.bytes).
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
