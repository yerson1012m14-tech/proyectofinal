#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/* A short-lived native lease: existing OS access, MHA-C2, or the alternate
   token route on the four recognized kernel builds. It reads containers only.
   Retain the lease during operations, then invalidate it to revoke access. */
@interface XFMHAContainerAccess : NSObject
@property (nonatomic, readonly) NSString *rootPath;
@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly, getter=isGroup) BOOL group;
@property (nonatomic, readonly) NSString *accessMethod;
+ (NSString *)kernelBuild;
+ (BOOL)alternateAccessSupported;
+ (nullable NSString *)signedProcessIdentifier:(NSError **)error;
+ (BOOL)availableWithError:(NSError **)error;
/* Permission failures expose a fixed MHAStage in NSError.userInfo:
   query_result (3013), object_copy (3015), sandbox_token (3021),
   sandbox_activate (3022). NativePOSIXError is a numeric errno when available;
   neither token data nor raw native messages are included. */
+ (nullable instancetype)leaseForBundleID:(NSString *)bundleID
                                  group:(BOOL)group
                                  error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)listDirectory:(NSString *)relativePath
                                              error:(NSError **)error;
- (nullable NSData *)readFile:(NSString *)relativePath
                maximumBytes:(NSUInteger)maximumBytes
                       error:(NSError **)error;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
