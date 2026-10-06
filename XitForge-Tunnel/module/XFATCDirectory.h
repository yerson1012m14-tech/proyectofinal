#import <Foundation/Foundation.h>
#import "XFIDeviceABI.h"

NS_ASSUME_NONNULL_BEGIN
/* Returns new caller-owned handles. Runs on the same native worker as the directory. */
typedef BOOL (^XFATCTunnelFactory)(AdapterHandle * _Nullable * _Nonnull adapter,
    RsdHandshakeHandle * _Nullable * _Nonnull rsd, NSError * _Nullable * _Nullable error);
/* All methods MUST execute on the native thread owning adapter and RSD. */
@interface XFATCDirectory : NSObject
@property (nonatomic, readonly, nullable) NSString *lastWarning;
/* Diagnostics contain fixed labels/codes only. generatedAppLinkProbe is populated
   by one metadata query after app-directory AFC 106/8 or 106/10, before recovery.
   A matching link target does not prove target resolution or directory access. */
@property (nonatomic, readonly) NSDictionary *protocolDiagnostics;
/* Fixed phase numbers only; called by the backend after real tunnel milestones. */
- (void)recordBatchSetupPhase:(NSUInteger)phase;
/* A durable local copy for an intentionally committed deletion. It is retained
   across reconnects and is never included in copied connection diagnostics. */
@property (nonatomic, readonly, nullable) NSURL *deletedFileBackupURL;
/* YES only when AFC positively reported the selected destination absent after
   relocation. NO means a retained relocation, not proof of target absence. */
@property (nonatomic, readonly) BOOL deletionAbsenceConfirmed;
- (instancetype)initWithAdapter:(AdapterHandle *)adapter
                             rsd:(RsdHandshakeHandle *)rsd
                      journalURL:(NSURL *)journalURL;
- (instancetype)initWithAdapter:(AdapterHandle *)adapter
                             rsd:(RsdHandshakeHandle *)rsd
                      journalURL:(NSURL *)journalURL
                   tunnelFactory:(XFATCTunnelFactory)tunnelFactory;
- (BOOL)recoverPendingTransaction:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)listAbsoluteDirectory:(NSString *)path
                                                      error:(NSError **)error;
/* These operations temporarily relocate an existing file. Recovery records are
   written before remote moves. The destination application must be closed. */
- (nullable NSData *)readAbsoluteFile:(NSString *)path maximumBytes:(NSUInteger)maximumBytes
                               error:(NSError **)error;
- (BOOL)replaceAbsoluteFile:(NSString *)path data:(NSData *)data error:(NSError **)error;
/* Home: overwrite/create using downloaded bytes, without capturing the app's
   previous file, automatic recovery, or mandatory restore on the next action. */
- (BOOL)writeDownloadedAbsoluteFile:(NSString *)path data:(NSData *)data error:(NSError **)error;
/* Experimental, generated marker only. Requires positive target absence;
   permission errors never authorize creation. Verifies a read from the app. */
- (BOOL)createTestAbsoluteFile:(NSString *)path error:(NSError **)error;
/* Uses the existing retained-deletion path, with an exact marker-content guard. */
- (BOOL)deleteTestAbsoluteFile:(NSString *)path error:(NSError **)error;
/* Retains the original in owned staging and a durable local copy. TRUE means
   committed retained relocation; consult deletionAbsenceConfirmed for absence.
   Committed deletion is never automatically restored on reconnect. */
- (BOOL)deleteAbsoluteFile:(NSString *)path error:(NSError **)error;
- (BOOL)recoverPendingKnownFileAtPath:(NSString *)path error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
