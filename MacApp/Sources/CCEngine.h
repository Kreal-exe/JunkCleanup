// Scanning and cleaning. Foundation only; both engines run synchronously on the caller's (background) thread and
// report progress through blocks that may be called from any thread.
#import <Foundation/Foundation.h>
#import "CCCore.h"

NS_ASSUME_NONNULL_BEGIN

/// A cooperative cancellation flag shared between the UI and a running engine.
@interface CCCancelToken : NSObject
@property (atomic, readonly) BOOL isCancelled;
- (void)cancel;
@end

/// One first-level entry under a root, for the details view.
@interface CCEntry : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isDirectory;
@property (nonatomic) long long bytes;
@property (nonatomic) NSInteger files;
/// Every file underneath was collected (nothing skipped by age, pattern, exclusion or errors).
@property (nonatomic) BOOL complete;
@end

@interface CCScanOptions : NSObject
/// Files modified within this many hours are skipped for targets that respect the age filter. 0 disables.
@property (nonatomic) double skipNewerThanHours;
@property (nonatomic) NSInteger maxTopEntries;
/// Directories that belong to other targets; a scan never descends into them, so nothing is counted twice.
@property (nonatomic, copy) NSSet<NSString *> *excludedRoots;
@end

@interface CCScanResult : NSObject
@property (nonatomic, strong) CCTarget *target;
@property (nonatomic, copy) NSArray<NSString *> *roots;
@property (nonatomic, readonly) NSMutableArray<NSString *> *files;
/// One long long per entry of files.
@property (nonatomic, readonly) NSMutableData *sizes;
@property (nonatomic, copy) NSArray<CCEntry *> *topEntries;
@property (nonatomic) long long totalBytes;
/// For a target whose files are clones (sharesBlocks): what they share with the original, on top of totalBytes. It is
/// freed only once the original changes (Chrome updates), so a clean does not count it.
@property (nonatomic) long long sharedBytes;
@property (nonatomic) NSInteger fileCount;
@property (nonatomic) BOOL accessDenied;
@property (nonatomic, copy, nullable) NSString *error;
@property (nonatomic) double elapsed;
- (long long)sizeAtIndex:(NSUInteger)index;
@end

typedef NS_ENUM(NSInteger, CCScanPhase) { CCScanPhaseStarted, CCScanPhaseProgress, CCScanPhaseCompleted };

@interface CCScanEvent : NSObject
@property (nonatomic) CCScanPhase phase;
@property (nonatomic) NSInteger completed;
@property (nonatomic) NSInteger total;
@property (nonatomic, copy) NSString *targetId;
@property (nonatomic) long long bytesFound;
/// What this event's target has found so far.
@property (nonatomic) long long targetBytes;
@property (nonatomic, strong, nullable) CCScanResult *result;
@end

@interface CCScanEngine : NSObject
- (NSArray<CCScanResult *> *)scanTargets:(NSArray<CCTarget *> *)targets
                                 options:(CCScanOptions *)options
                                  cancel:(nullable CCCancelToken *)cancel
                                progress:(nullable void (^)(CCScanEvent *event))progress;
- (CCScanResult *)scanTarget:(CCTarget *)target
                     options:(CCScanOptions *)options
                      cancel:(nullable CCCancelToken *)cancel
                     onBytes:(nullable void (^)(long long delta))onBytes;
@end

// ───────────── cleaning ─────────────

@interface CCCleanOptions : NSObject
@property (nonatomic) BOOL useTrash;
@property (nonatomic) BOOL dryRun;
@end

@interface CCTargetCleanResult : NSObject
@property (nonatomic, copy) NSString *targetId;
@property (nonatomic) long long bytesFreed;
@property (nonatomic) long long bytesRemaining;
@property (nonatomic) NSInteger filesDeleted;
@property (nonatomic) NSInteger failed;
/// Files still on disk afterwards: the failed ones plus any left when the clean was stopped.
@property (nonatomic) NSInteger filesRemaining;
@property (nonatomic, copy, nullable) NSString *error;
@end

@interface CCCleanEvent : NSObject
@property (nonatomic, copy) NSString *targetId;
@property (nonatomic) BOOL targetDone;
@property (nonatomic) long long bytesFreed;
@property (nonatomic) NSInteger filesDeleted;
@property (nonatomic) NSInteger failed;
@property (nonatomic) NSInteger targetsDone;
@property (nonatomic) NSInteger targetsTotal;
@property (nonatomic, strong, nullable) CCTargetCleanResult *targetResult;
@end

@interface CCCleanReport : NSObject
@property (nonatomic) long long bytesFreed;
@property (nonatomic) NSInteger filesDeleted;
@property (nonatomic) NSInteger failed;
@property (nonatomic) double elapsed;
@property (nonatomic) BOOL cancelled;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, CCTargetCleanResult *> *targets;
@end

/// Deletes scanned files, into the Trash or permanently, never leaving the scanned roots. Targets are cleaned side by
/// side and the files of a target in parallel chunks; cancelling stops between files.
@interface CCCleanEngine : NSObject
- (CCCleanReport *)clean:(NSArray<CCScanResult *> *)scans
                 options:(CCCleanOptions *)options
                  cancel:(nullable CCCancelToken *)cancel
                progress:(nullable void (^)(CCCleanEvent *event))progress;
- (CCTargetCleanResult *)cleanTarget:(CCScanResult *)scan
                             options:(CCCleanOptions *)options
                              cancel:(nullable CCCancelToken *)cancel
                          onProgress:(nullable void (^)(long long freed, NSInteger deleted, NSInteger failed))onProgress;
/// Removes one first-level entry the user picked (a whole folder or a file) and takes it out of the scan result.
/// Refuses anything that is not underneath the scanned roots. Returns nil when nothing was removed.
- (nullable CCTargetCleanResult *)removeEntry:(CCEntry *)entry fromScan:(CCScanResult *)scan options:(CCCleanOptions *)options;
@end

// ───────────── disk map ─────────────

/// Where the space on a disk goes, in the bands of the Disk page's bar.
typedef NS_ENUM(NSInteger, CCSpaceSegment) {
    CCSpaceSystem,
    CCSpaceApps,
    CCSpaceCaches,
    CCSpaceDeveloper,
    CCSpaceModels,
    CCSpaceVirtualMachines,
    CCSpaceFiles,
    CCSpaceOther,
};
#define CCSpaceSegmentCount 8

/// How safe removing an item is; the first three match CCRisk. Keep items are only shown, never removed by the app.
typedef NS_ENUM(NSInteger, CCSpaceRisk) { CCSpaceRiskSafe, CCSpaceRiskModerate, CCSpaceRiskCareful, CCSpaceRiskKeep };

/// "System", "Apps"… — the suffix of the "disk.seg.*" keys.
NSString *CCSpaceSegmentName(CCSpaceSegment segment);
/// "Safe" … "Keep" — the suffix of the "risk.*" keys.
NSString *CCSpaceRiskName(CCSpaceRisk risk);

/// A part of a known item, relative to it ("cache", "hermes-agent/.cache"). The kind names the strings
/// "space.kind.<kind>.name / .desc"; the pattern may hold "*" segments.
@interface CCSpacePart : NSObject
+ (instancetype)kind:(NSString *)kind pattern:(NSString *)pattern risk:(CCSpaceRisk)risk;
@property (nonatomic, copy, readonly) NSString *kind;
@property (nonatomic, copy, readonly) NSString *pattern;
@property (nonatomic, readonly) CCSpaceRisk risk;
@end

/// A known space consumer (an AI agent's folder, model downloads, emulator images, virtual machines…): where it lives,
/// which band it belongs to and which of its parts are safe to remove. Names live in the localization files under
/// "space.<id>.name" / "space.<id>.desc".
@interface CCSpaceRule : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) CCSpaceSegment segment;
/// SF Symbol name.
@property (nonatomic, copy) NSString *symbol;
/// Folder patterns, expanded like a target's roots.
@property (nonatomic, copy) NSArray<NSString *> *paths;
/// Risk of the item as a whole (and of its listed subfolders). Keep by default.
@property (nonatomic) CCSpaceRisk risk;
/// A command that removes it when the app cannot (it belongs to root, a tool manages it).
@property (nonatomic, copy, nullable) NSString *command;
@property (nonatomic, copy) NSArray<CCSpacePart *> *parts;
/// Each subfolder becomes a child of this kind, named after the folder (one per model, VM, image…).
@property (nonatomic, copy, nullable) NSString *listKind;
/// fnmatch pattern the listed subfolders must match ("*--*" for Hugging Face's models); nil lists them all.
@property (nonatomic, copy, nullable) NSString *listPattern;
/// Readable only with Full Disk Access; without it the item is shown unmeasured.
@property (nonatomic) BOOL needsFullDiskAccess;
@end

@interface CCSpaceEntry : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) CCSpaceSegment segment;
@property (nonatomic) CCSpaceRisk risk;
@property (nonatomic, copy) NSString *symbol;
/// The string key prefix ("space.hermes", "space.kind.cache"); nil when name is literal.
@property (nonatomic, copy, nullable) NSString *key;
/// A literal name (a folder name) for discovered folders and listed children.
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic, copy, nullable) NSString *command;
/// A cache target found by the cleaner: removed from the Targets page, not here.
@property (nonatomic, copy, nullable) NSString *targetId;
@property (atomic) long long bytes;
/// Part of it could not be read.
@property (atomic) BOOL unreadable;
/// Not measured: it needs Full Disk Access.
@property (nonatomic) BOOL needsAccess;
/// Worked out once by the engine: one folder or file, not Keep, no command, not a cache target, not protected.
@property (nonatomic) BOOL canDelete;
/// An app in /Applications that can be uninstalled with its data.
@property (nonatomic) BOOL uninstallable;
@property (nonatomic, readonly) NSMutableArray<CCSpaceEntry *> *children;
@property (nonatomic, readonly) NSString *path;
@end

@interface CCSpaceReport : NSObject
@property (nonatomic, copy) NSString *volumeName;
@property (nonatomic) long long total;
@property (nonatomic) long long free;
@property (nonatomic, readonly) long long used;
@property (nonatomic, readonly) NSMutableArray<CCSpaceEntry *> *items;
/// Bytes per band; System also holds what is used but was not measured.
@property (nonatomic, readonly) long long *segments;
@property (nonatomic) double elapsed;
@property (nonatomic, readonly) long long measured;
@end

/// A disk the Disk page can map: the startup disk or a mounted local drive.
@interface CCVolume : NSObject
/// Where it is mounted ("/", "/Volumes/980PRO").
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *name;
/// The file system ("apfs", "exfat", "msdos"…).
@property (nonatomic, copy, readonly) NSString *format;
@property (nonatomic, readonly) long long total, free;
/// It holds the home folder.
@property (nonatomic, readonly) BOOL isHome;
/// exFAT or FAT: no journal, snapshots or index of their own, and every file takes whole clusters.
@property (nonatomic, readonly) BOOL isFAT;
/// The home disk first, then the other local disks that can be written to; no network shares or read-only images.
+ (NSArray<CCVolume *> *)mounted;
/// The disk holding the path, or nil when it went away.
+ (nullable instancetype)volumeAtPath:(NSString *)path;
@end

/// A folder whose subfolders are each measured as an item.
@interface CCSpaceRoot : NSObject
+ (instancetype)pattern:(NSString *)pattern segment:(CCSpaceSegment)segment keep:(BOOL)keep;
@property (nonatomic, copy, readonly) NSString *pattern;
@property (nonatomic, readonly) CCSpaceSegment segment;
/// What is found there is only shown (apps, the system's own support files).
@property (nonatomic, readonly) BOOL keep;
@end

/// What the Mac contributes: its known items, the folders to look through and how to file what is found.
@interface CCSpaceScope : NSObject
@property (nonatomic, copy) NSArray<CCSpaceRule *> *rules;
@property (nonatomic, copy) NSArray<CCSpaceRoot *> *roots;
/// Discovered folders that are only containers: each of their subfolders is listed as a child.
@property (nonatomic, copy) NSArray<NSString *> *containers;
/// Discovered folders that belong to a band other than their root's (pattern → CCSpaceSegment).
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *filed;
/// The user's own folders: Files band, Keep.
@property (nonatomic, copy) NSArray<NSString *> *personal;
/// Folder names shown but never removed here, whatever their band (the file system's own folders at a drive's root).
@property (nonatomic, copy) NSArray<NSString *> *keepNames;
/// Never entered, never listed: other apps' sandbox containers (opening them makes macOS ask for permission).
@property (nonatomic, copy) NSArray<NSString *> *skipped;
/// Entered only with Full Disk Access (macOS asks or refuses otherwise); shown unmeasured without it.
@property (nonatomic, copy) NSArray<NSString *> *guarded;
@property (nonatomic) BOOL hasFullDiskAccess;
/// The volume to report on.
@property (nonatomic, copy) NSString *volumePath;
/// Which known items and cache targets belong to the report: only those on the disk being mapped. Nil takes them all.
@property (nonatomic, copy, nullable) BOOL (^includes)(NSString *path);
/// Files at the top of this folder are listed too (a drive's root holds them as much as its folders do).
@property (nonatomic, copy, nullable) NSString *looseFilesRoot;
/// exFAT or FAT: each file counts as the whole clusters it takes.
@property (nonatomic) long long clusterSize;
/// The startup disk: lists macOS's own volumes and system folders, and with Full Disk Access other apps' containers.
@property (nonatomic) BOOL listsSystemSpace;
/// What is in use but no folder accounts for gets a row of its own, so the band's rows add up to the band.
@property (nonatomic) BOOL namesUnaccounted;
/// Discovered folders smaller than this fold into one "Smaller folders" entry per band.
@property (nonatomic) long long smallFolder;
@property (nonatomic, copy) NSString *folderSymbol, *personalSymbol, *cachesSymbol;
@end

@interface CCSpaceCatalog : NSObject
+ (NSArray<CCSpaceRule *> *)rules;
+ (CCSpaceScope *)scopeWithFullDiskAccess:(BOOL)fullDiskAccess;
/// What to map on a disk: the home disk through the home folder, any other through the folders at its root.
+ (CCSpaceScope *)scopeForVolume:(CCVolume *)volume fullDiskAccess:(BOOL)fullDiskAccess;
@end

/// What an app leaves in the user's Library, for uninstalling it the way AppCleaner does.
@interface CCAppLeftovers : NSObject
+ (nullable NSString *)bundleIdOfApp:(NSString *)appPath;
/// A real .app with a bundle id; never Apple's own apps or JunkCleanup.
+ (BOOL)canUninstall:(NSString *)appPath;
/// The app's folders and files under ~/Library: by bundle id, and by its exact name where apps use that. What belongs to
/// another installed app (a Canary next to Chrome) is left out, and so is anything the path guard protects.
+ (NSArray<NSString *> *)leftoversOfApp:(NSString *)appPath otherApps:(NSArray<NSString *> *)otherApps;
/// The apps in /Applications and ~/Applications.
+ (NSArray<NSString *> *)installedApps;
+ (BOOL)moveToTrash:(NSString *)path;
@end

/// Measures the disk: every known item (with its parts), every cache target, and every other folder under the scope's
/// roots, each byte counted once (allocated size, links never followed). What is used but was not measured (the
/// system, swap, snapshots, unreadable places) becomes the System band.
@interface CCDiskMapEngine : NSObject
- (CCSpaceReport *)analyze:(CCSpaceScope *)scope
                   targets:(NSArray<CCTarget *> *)targets
                    cancel:(nullable CCCancelToken *)cancel
                  progress:(nullable void (^)(NSString *path))progress;
/// Removes one entry the user picked, into the Trash or permanently. Refuses everything canDelete refuses, links and
/// paths whose parents were swapped for links. Returns the bytes freed (0 when nothing was removed).
- (long long)removeEntry:(CCSpaceEntry *)entry useTrash:(BOOL)useTrash;
/// Allocated bytes under a folder or file, never following links, skipping the excluded folders.
+ (long long)measure:(NSString *)path excluding:(nullable NSSet<NSString *> *)excluded cancel:(nullable CCCancelToken *)cancel unreadable:(nullable BOOL *)unreadable;
@end

NS_ASSUME_NONNULL_END
