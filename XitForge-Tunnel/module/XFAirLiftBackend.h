#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Synchronous API. Call from a background queue; all native handles are kept
/// on one dedicated worker thread. AirTraffic file operations use a recoverable
/// device staging area; replacement is limited to an explicitly selected file.
@interface XFAirLiftBackend : NSObject
+ (instancetype)sharedBackend;
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) BOOL hasPairingRecord;
@property (nonatomic, copy) NSString *deviceAddress;
/// Defaults to 49152 for the local tunnel. A Bonjour-advertised port can differ.
@property (nonatomic) NSUInteger remotePairingPort;
/// Enable only when the configured port was advertised as _remoted._tcp.
/// The default raw transport expects _remotepairing._tcp.
@property (nonatomic) BOOL usesRemoteXPC;
@property (nonatomic, readonly, copy) NSString *pairingKind;
/// Empty until a catalogue has been loaded; "CoreDevice AppService" or
/// "Installation Proxy" after a successful query.
@property (nonatomic, readonly, copy) NSString *applicationCatalogSource;
/// Whether RSD advertises the FileService control channel. This does not imply
/// permission to open an app's container or availability of the download channel.
@property (nonatomic, readonly) BOOL fileServiceAvailable;
/// Whether the signed identity and native APIs support requesting a local
/// container lease. Actual access is checked separately for each app.
@property (nonatomic, readonly) BOOL directContainerAccessAvailable;
/// Whether native access or the connection permits attempting an app-file route.
/// A capability alone does not prove access to a particular app.
@property (nonatomic, readonly) BOOL applicationFileAccessAvailable;
@property (nonatomic, readonly, copy) NSString *fileAccessSummary;
/// Contains versions and sanitized service capabilities, never pairing secrets
/// or application paths/content.
@property (nonatomic, readonly, copy) NSString *connectionDiagnostics;
@property (nonatomic, readonly, copy) NSString *lastDirectoryWarning;
/// Durable local original from the latest committed deletion, for user export.
/// The URL remains valid across reconnects; callers must never move/remove it.
@property (nonatomic, readonly, nullable) NSURL *lastDeletedFileBackupURL;
/// Whether AFC positively confirmed target absence after that relocation.
@property (nonatomic, readonly) BOOL lastDeletionAbsenceConfirmed;
- (BOOL)importPairingRecordURL:(NSURL *)url error:(NSError **)error;
- (BOOL)connectWithError:(NSError **)error;
- (void)disconnect;
/// Entries contain name, bundleIdentifier, isDeveloperApp and isFirstParty.
- (nullable NSArray<NSDictionary *> *)installedApplicationsWithError:(NSError **)error;
/// Entries contain name, isDirectory and typeKnown. FileService returns names;
/// HouseArrest/AFC and AirTraffic supply stat metadata. Its Documents-only fallback exposes
/// a virtual root with a single Documents folder, preserving app-relative paths.
- (nullable NSArray<NSDictionary *> *)listDirectoryForApplication:(NSString *)bundleIdentifier
                                                   relativePath:(NSString *)relativePath
                                                          error:(NSError **)error;
- (nullable NSData *)readFileForApplication:(NSString *)bundleIdentifier
                              relativePath:(NSString *)relativePath
                                     error:(NSError **)error;
/// Replaces an existing known app file through AirTraffic. The caller must first
/// confirm the destination with the user. Input is limited to 64 MiB.
- (BOOL)replaceFileForApplication:(NSString *)bundleIdentifier
                    relativePath:(NSString *)relativePath
                            data:(NSData *)data
                           error:(NSError **)error;
/// Experimental marker only; rejects occupied or uncheckable destinations.
- (BOOL)createTestFileForApplication:(NSString *)bundleIdentifier
                       relativePath:(NSString *)relativePath error:(NSError **)error;
/// Retained deletion is authorized only if bytes still match the generated marker.
- (BOOL)deleteTestFileForApplication:(NSString *)bundleIdentifier
                       relativePath:(NSString *)relativePath error:(NSError **)error;
/// Intentionally retires a known regular app file (maximum 64 MiB) to retained
/// backup. Confirm the concrete destination before calling. A YES result proves
/// retained relocation; lastDeletionAbsenceConfirmed distinguishes target absence.
- (BOOL)deleteFileForApplication:(NSString *)bundleIdentifier
                    relativePath:(NSString *)relativePath
                           error:(NSError **)error;
/// Explicitly restores the retained original for this exact known-file target.
/// The caller must confirm that the current target content may be replaced.
- (BOOL)restorePendingFileForApplication:(NSString *)bundleIdentifier
                           relativePath:(NSString *)relativePath
                                  error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)listDirectoryForAppGroup:(NSString *)groupIdentifier
                                                relativePath:(NSString *)relativePath
                                                       error:(NSError **)error;
- (nullable NSData *)readFileForAppGroup:(NSString *)groupIdentifier
                         relativePath:(NSString *)relativePath
                                error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
