// The app state of ViewModels/MainViewModel.cs: targets, categories, scanning, cleaning. Views listen for
// CCModelDidChangeNotification and pull what they show.
#import <Foundation/Foundation.h>
#import "CCCore.h"
#import "CCEngine.h"
#import "CCInsights.h"
#import "CCSettings.h"
#import "CCProcesses.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const CCModelDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const CCModelScanStateNotification;
FOUNDATION_EXPORT NSNotificationName const CCModelCleanStateNotification;
FOUNDATION_EXPORT NSNotificationName const CCModelInsightsNotification;
FOUNDATION_EXPORT NSNotificationName const CCModelPageNotification;
/// userInfo: "symbol", "text".
FOUNDATION_EXPORT NSNotificationName const CCModelToastNotification;
FOUNDATION_EXPORT NSNotificationName const CCModelCustomFoldersNotification;
FOUNDATION_EXPORT NSNotificationName const CCModelDetailsNotification;

typedef NS_ENUM(NSInteger, CCPage) { CCPageDashboard, CCPageTargets, CCPageDisk, CCPageSettings, CCPageAbout };
typedef NS_ENUM(NSInteger, CCTargetState) { CCTargetIdle, CCTargetScanning, CCTargetDone, CCTargetDenied, CCTargetError };

@interface CCTargetItem : NSObject
@property (nonatomic, strong, readonly) CCTarget *target;
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy) NSArray<NSString *> *roots;
@property (nonatomic, readonly) BOOL isPresent;
/// Looks for the roots again: junk that comes and goes (an abandoned Chrome copy, a finished session's folder).
- (void)refreshPresence;
/// Roots worked out elsewhere (a scan finds them off the main thread).
- (void)applyRoots:(NSArray<NSString *> *)roots;
@property (nonatomic) BOOL enabled;
@property (nonatomic) long long bytes;
@property (nonatomic) NSInteger fileCount;
@property (nonatomic) CCTargetState state;
@property (nonatomic, copy, nullable) NSString *error;
@property (nonatomic) BOOL expanded;
@property (nonatomic) double share;
@property (nonatomic, copy) NSArray<CCEntry *> *topEntries;
@property (nonatomic, strong, nullable) CCScanResult *lastResult;
/// A clean left files behind (in use, or out of reach): only a new scan offers them again.
@property (nonatomic, readonly) BOOL hasLeftovers;
/// The Trash: emptied rather than cleaned, and shown on its own line rather than as junk of its category.
@property (nonatomic, readonly) BOOL isTrash;

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *details;
@property (nonatomic, readonly) NSString *riskText;
@property (nonatomic, readonly) NSString *riskHint;
@property (nonatomic, readonly) NSString *rootsText;
@property (nonatomic, readonly) NSString *statusText;
@property (nonatomic, readonly) BOOL showsAccessBadge;
@end

@interface CCCategoryItem : NSObject
@property (nonatomic, readonly) CCCategory category;
@property (nonatomic, copy) NSArray<CCTargetItem *> *targets;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *symbol;
@property (nonatomic) long long bytes;
/// What of it is ticked for cleaning.
@property (nonatomic) long long selectedBytes;
@property (nonatomic) long long fileCount;
@property (nonatomic) NSInteger presentCount;
@property (nonatomic) double share;
@property (nonatomic) BOOL enabled;
@end

@interface CCCleanLogItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) long long bytes;
@property (nonatomic) NSInteger failed;
@end

@interface CCModel : NSObject
@property (class, nonatomic, readonly) CCModel *shared;
@property (nonatomic, strong, readonly) CCSettings *settings;

@property (nonatomic, readonly) NSArray<CCTargetItem *> *targets;
@property (nonatomic, readonly) NSArray<CCCategoryItem *> *categories;
@property (nonatomic, readonly) NSArray<CCTargetItem *> *topTargets;
@property (nonatomic, readonly) NSArray<CCInsight *> *insights;

@property (nonatomic) CCPage page;
@property (nonatomic, copy) NSString *searchText;
/// "All" or a category name.
@property (nonatomic, copy) NSString *filter;
- (BOOL)targetMatchesFilter:(CCTargetItem *)target;

// scanning
@property (nonatomic, readonly) BOOL scanning;
@property (nonatomic, readonly) BOOL hasResults;
@property (nonatomic, readonly) BOOL nothingFound;
@property (nonatomic, readonly) NSString *statusText;
@property (nonatomic, readonly) NSString *currentTargetName;
@property (nonatomic, readonly) long long displayBytes;
@property (nonatomic, readonly) long long foundBytes;
@property (nonatomic, readonly) long long selectedBytes;
@property (nonatomic, readonly) NSInteger selectedCount;
@property (nonatomic, readonly) NSInteger presentCount;
@property (nonatomic, readonly) double ringAngle;
@property (nonatomic, readonly) BOOL canClean;
/// What a press of Clean frees now; files a clean could not remove are left out until the next scan.
@property (nonatomic, readonly) long long cleanableBytes;
/// All that is left to clean is the Trash: the button empties it.
@property (nonatomic, readonly) BOOL onlyTrashLeft;
/// What is in the Trash; on its own line of the dashboard unless the ring already shows it.
@property (nonatomic, readonly) long long trashBytes;
@property (nonatomic, readonly) BOOL showsTrashLine;
@property (nonatomic, readonly) NSString *trashLine;
/// Under the ring: the share of the whole disk that a press of Clean frees.
@property (nonatomic, readonly) NSString *ringCaption;

// disk
@property (nonatomic, readonly) NSString *diskName;
@property (nonatomic, readonly) long long diskUsed, diskTotal, diskFree;
@property (nonatomic, readonly) long long lifetimeFreed;
@property (nonatomic, readonly) BOOL hasFullDiskAccess;

// cleaning
@property (nonatomic, readonly) BOOL overlayVisible;
@property (nonatomic, readonly) BOOL cleaning;
@property (nonatomic, readonly) BOOL cleanDone;
/// Stop was pressed; the running target finishes its current file and the rest are left alone.
@property (nonatomic, readonly) BOOL cleanStopping;
@property (nonatomic, readonly) long long cleanFreed;
@property (nonatomic, readonly) double cleanProgress;
@property (nonatomic, readonly) NSString *cleanCurrent;
@property (nonatomic, readonly) NSString *cleanSummary;
@property (nonatomic, readonly) NSArray<CCCleanLogItem *> *cleanLog;

/// The icon of the next question; the trash when nil. Read and cleared by the window.
@property (nonatomic, copy, nullable) NSString *confirmSymbol;
/// Asks before cleaning; the block answers with YES to go ahead.
@property (nonatomic, copy, nullable) void (^confirm)(NSString *title, NSString *body, NSString *okText, BOOL danger, void (^answer)(BOOL ok));

- (void)toggleScan;
- (void)startScan;
- (void)cancelScan;
- (void)clean;
- (void)cancelClean;
- (void)closeCleanOverlay;
/// How targets are picked: by the app from their risk (Safe, Safe + Moderate) or by hand. Any tick changed by hand
/// switches to Manual, starting from what was ticked.
@property (nonatomic, readonly) CCSelectionMode selectionMode;
/// Manual brings back the ticks last set by hand.
- (void)setSelectionMode:(CCSelectionMode)mode;
- (void)selectNone;
/// Ticks one target (from the Disk page), leaving the automatic mode only when the mode would not pick it.
- (void)includeTarget:(NSString *)identifier;
/// The Disk page's Clean: ticks the target (nil for all caches), opens Overview and scans when nothing was scanned yet.
- (void)cleanFromDisk:(nullable NSString *)targetId;
- (void)setTarget:(CCTargetItem *)target enabled:(BOOL)enabled;
- (void)setCategory:(CCCategoryItem *)category enabled:(BOOL)enabled;
- (void)openCategory:(CCCategoryItem *)category;
- (void)toggleExpanded:(CCTargetItem *)target;

// The details sheet: a target's entries, each removable on its own.
@property (nonatomic, strong, readonly, nullable) CCTargetItem *detailsTarget;
- (void)openDetails:(CCTargetItem *)target;
- (void)closeDetails;
- (void)revealPath:(NSString *)path;
/// Moves one entry to the Trash (or deletes it, per the setting); the answer arrives on the main thread.
- (void)deleteEntry:(CCEntry *)entry ofTarget:(CCTargetItem *)target completion:(void (^)(BOOL ok))completion;
- (void)runInsightAction:(CCInsight *)insight;
/// Processes that are stuck (an orphaned Claude shell loop, a disk-wide search, a bloated Hermes tab); refreshed with
/// the insights.
@property (nonatomic, readonly) NSArray<CCStuckProcess *> *stuckProcesses;
/// The Hermes tab is closed with the whole Hermes browser, through its own stop script; nothing else can end it.
- (BOOL)canTerminate:(CCStuckProcess *)process;
/// Asks, then ends it.
- (void)terminateStuck:(CCStuckProcess *)process;
- (void)refreshInsights;
/// Space freed outside a clean (the Disk page), added to the all-time total.
- (void)addFreed:(long long)bytes;
- (void)refreshDisk;
- (void)refreshAccess;
- (void)openFullDiskAccessSettings;
/// Without Full Disk Access, asks for it and opens its page of System Settings; `declined` runs when the answer is no.
- (void)askForFullDiskAccessDeclined:(nullable void (^)(void))declined;
- (void)addCustomFolder:(NSString *)folder refused:(void (^)(void))refused;
- (void)removeCustomFolder:(NSString *)folder;
- (void)resetSettings;
- (void)saveSettings;
@end

NS_ASSUME_NONNULL_END
