// The platform-independent core: byte formatting, the target model and catalog, and the path guard.
// Foundation only, so the tests can build it without AppKit.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CCCategory) {
    CCCategorySystem,
    CCCategoryBrowsers,
    CCCategoryDeveloper,
    CCCategoryApps,
    CCCategoryGaming,
    CCCategoryCustom,
};
#define CCCategoryCount 6

typedef NS_ENUM(NSInteger, CCRisk) { CCRiskSafe, CCRiskModerate, CCRiskCareful };

/// How the cleaner picks what to clean: by itself from the risk levels, or by hand.
typedef NS_ENUM(NSInteger, CCSelectionMode) {
    /// Every Safe target (caches that come back by themselves).
    CCSelectionSafe,
    /// Safe and Moderate targets; Careful ones (models, backups, archives) are never picked by the app.
    CCSelectionModerate,
    /// What the user ticked.
    CCSelectionManual,
};

/// "System", "Browsers"… — the suffix of the localization keys "cat.*" and of the category colours.
NSString *CCCategoryName(CCCategory category);
/// "Safe", "Moderate", "Careful" — the suffix of the "risk.*" keys.
NSString *CCRiskName(CCRisk risk);

// ───────────── formatting ─────────────

/// The locale numbers are formatted with; follows the interface language.
void CCSetFormatLocale(NSLocale *locale);
/// "12.4 GB" with 1024-based units, like the Windows app.
NSString *CCFormatBytes(double bytes);
void CCSplitBytes(double bytes, NSString *_Nullable *_Nullable number, NSString *_Nullable *_Nullable unit);
/// "133 697" with the locale's grouping.
NSString *CCFormatCount(long long count);
/// "0.4" with the locale's decimal separator.
NSString *CCFormatDecimal(double value);

// ───────────── targets ─────────────

/// A declarative description of one cleanable location. Names and descriptions live in the localization files
/// under "target.<id>.name" / "target.<id>.desc".
@interface CCTarget : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) CCCategory category;
/// SF Symbol name.
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic) CCRisk risk;
/// Readable only with Full Disk Access (Safari, Trash, iOS backups…).
@property (nonatomic) BOOL needsFullDiskAccess;
@property (nonatomic) BOOL enabledByDefault;
/// The "skip recent files" setting applies (temporary folders).
@property (nonatomic) BOOL respectsAgeFilter;
/// Files are always deleted, never moved to the Trash (the Trash itself).
@property (nonatomic) BOOL alwaysPermanent;
@property (nonatomic) BOOL recursive;
/// Directory patterns: "~/…", "$TMP/…", "$DARWIN_CACHE/…", with "*" allowed in any segment.
@property (nonatomic, copy) NSArray<NSString *> *rootPatterns;
/// fnmatch patterns for first-level entries under a root that are left alone.
@property (nonatomic, copy, nullable) NSArray<NSString *> *excludedNames;
/// fnmatch patterns matched against file names; nil means every file.
@property (nonatomic, copy, nullable) NSArray<NSString *> *filePatterns;
/// A catch-all (other apps' caches, ~/.cache): it never takes a root that a specific target owns; folders such
/// targets own deeper inside are skipped by the scan.
@property (nonatomic) BOOL fallback;
/// The roots are versions of one thing (an app's bundled runtimes): the newest one is in use and left alone.
@property (nonatomic) BOOL keepsNewest;
/// Finds the roots itself instead of expanding rootPatterns (old projects' build folders).
@property (nonatomic, copy, nullable) NSArray<NSString *> * (^finder)(void);
/// A root is itself the junk (a project's node_modules): once emptied it is removed too.
@property (nonatomic) BOOL removesRoots;
/// A root is offered only when nothing inside it changed for this many days (temp folders of finished sessions).
@property (nonatomic) double idleDays;
/// Each root is junk as a whole (an abandoned copy of an app, a VM image, a finished session's folder): a clean removes
/// it in one go, links and all, instead of file by file.
@property (nonatomic) BOOL deletesWholeRoots;
/// The files are APFS clones of another app's files: the scan counts only the blocks they do not share, which is
/// what removing them frees today.
@property (nonatomic) BOOL sharesBlocks;
/// Runs on the cleaning thread right before the roots are removed (stops the VM that has its image open).
@property (nonatomic, copy, nullable) void (^beforeClean)(NSArray<NSString *> *roots);
/// Display name override (custom folders); nil means the localized key.
@property (nonatomic, copy, nullable) NSString *displayName;

@property (nonatomic, readonly) NSString *nameKey;
@property (nonatomic, readonly) NSString *descriptionKey;
@property (nonatomic, readonly) BOOL isCustom;

/// Existing, allowed, de-duplicated root directories (symlinks resolved).
- (NSArray<NSString *> *)resolveRoots;
@end

/// Whether the app ticks this target by itself in the given mode: custom folders always, the Trash never, otherwise the
/// targets on by default whose risk the mode covers. Manual mode picks nothing by itself.
BOOL CCAutoSelects(CCTarget *target, CCSelectionMode mode);
/// "safe", "moderate", "manual" — how the settings file stores the mode.
NSString *CCSelectionModeName(CCSelectionMode mode);
CCSelectionMode CCSelectionModeFromName(NSString *_Nullable name);

/// Something inside the folder (or the file itself) was modified within the last `seconds`. Stops at the first hit.
BOOL CCTouchedWithin(NSString *path, NSTimeInterval seconds);

@interface CCCatalog : NSObject
+ (NSArray<CCTarget *> *)allTargets;
+ (CCTarget *)customTargetForFolder:(NSString *)folder;
+ (NSString *)customIdForFolder:(NSString *)folder;
@end

/// Expands one root pattern into the existing directories it names.
NSArray<NSString *> *CCExpandPattern(NSString *pattern);
/// The home folder; JUNKCLEANUP_HOME overrides it (tests).
NSString *CCHomeDirectory(void);

// ───────────── path guard ─────────────

/// Last line of defence: refuses critical folders as cleanable roots and refuses to touch anything that does not
/// live underneath one of the roots that were scanned.
@interface CCPathGuard : NSObject
+ (NSString *)normalize:(NSString *)path;
+ (BOOL)isAllowedRoot:(NSString *)root;
+ (BOOL)isPath:(NSString *)path insideRoots:(NSArray<NSString *> *)roots;
@end

NS_ASSUME_NONNULL_END
