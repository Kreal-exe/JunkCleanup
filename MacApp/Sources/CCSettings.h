// Settings (the same JSON shape as the Windows app) and localization (the Windows app's Strings/*.json plus a macOS
// overlay that replaces the Windows-specific wording).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CCSettings : NSObject
/// "auto" or a language code.
@property (nonatomic, copy) NSString *language;
/// "dark", "light" or "system".
@property (nonatomic, copy) NSString *theme;
@property (nonatomic) BOOL useTrash;
@property (nonatomic) NSInteger skipRecentHours;
@property (nonatomic) BOOL animations;
@property (nonatomic) BOOL translucency;
@property (nonatomic) BOOL scanOnStartup;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *targetStates;
@property (nonatomic, strong) NSMutableArray<NSString *> *customFolders;
@property (nonatomic) double windowWidth;
@property (nonatomic) double windowHeight;
@property (nonatomic) long long lifetimeBytesFreed;

/// ~/Library/Application Support/JunkCleanup/settings.json; JUNKCLEANUP_SETTINGS overrides it.
+ (NSString *)filePath;
+ (instancetype)load;
- (void)save;
- (void)resetToDefaults;
@end

@interface CCLanguage : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *nativeName;
@end

FOUNDATION_EXPORT NSNotificationName const CCLanguageDidChangeNotification;

@interface CCLocalization : NSObject
@property (class, nonatomic, readonly) CCLocalization *shared;
@property (class, nonatomic, readonly) NSArray<CCLanguage *> *languages;
/// The language actually shown ("auto" resolved).
@property (nonatomic, readonly) NSString *code;
/// Folders holding <code>.json files, later folders overriding earlier ones.
@property (nonatomic, copy) NSArray<NSString *> *searchFolders;
/// "auto" follows the macOS language list.
- (void)setLanguage:(NSString *)codeOrAuto;
+ (NSString *)systemLanguageCode;
- (NSString *)string:(NSString *)key;
- (NSString *)format:(NSString *)key arguments:(NSArray *)arguments;
- (BOOL)hasKey:(NSString *)key;
@end

NSString *L(NSString *key);
NSString *CCLF(NSString *key, NSArray *arguments);
#define LF(key, ...) CCLF(key, @[ __VA_ARGS__ ])

NS_ASSUME_NONNULL_END
