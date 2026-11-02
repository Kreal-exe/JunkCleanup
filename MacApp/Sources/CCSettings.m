#import "CCSettings.h"
#import "CCCore.h"

@implementation CCSettings

- (instancetype)init {
    if ((self = [super init])) [self resetToDefaults];
    return self;
}

- (void)resetToDefaults {
    _language = @"auto";
    _theme = @"dark";
    _useTrash = YES;
    _skipRecentHours = 24;
    _animations = YES;
    _translucency = YES;
    _scanOnStartup = YES;
    _measureDiskWithScan = YES;
    _confirmClean = YES;
    _targetStates = [NSMutableDictionary dictionary];
    _customFolders = [NSMutableArray array];
}

+ (NSString *)filePath {
    const char *custom = getenv("JUNKCLEANUP_SETTINGS");
    if (custom && *custom) return [NSString stringWithUTF8String:custom].stringByStandardizingPath;
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [[support stringByAppendingPathComponent:@"JunkCleanup"] stringByAppendingPathComponent:@"settings.json"];
}

static id Get(NSDictionary *d, NSString *key, Class type) {
    id value = d[key];
    return [value isKindOfClass:type] ? value : nil;
}

+ (instancetype)load {
    CCSettings *s = [CCSettings new];
    NSData *data = [NSData dataWithContentsOfFile:[self filePath]];
    // Before the rename the app was CacheCleanup: its settings are read until the first save writes the new file.
    if (!data && !getenv("JUNKCLEANUP_SETTINGS")) {
        NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        data = [NSData dataWithContentsOfFile:[[support stringByAppendingPathComponent:@"CacheCleanup"] stringByAppendingPathComponent:@"settings.json"]];
    }
    NSDictionary *d = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![d isKindOfClass:NSDictionary.class]) return s;

    s.language = Get(d, @"language", NSString.class) ?: s.language;
    s.theme = Get(d, @"theme", NSString.class) ?: s.theme;
    // "useRecycleBin" is the Windows name of the same switch; one file can serve both apps.
    NSNumber *trash = Get(d, @"useRecycleBin", NSNumber.class);
    if (trash) s.useTrash = trash.boolValue;
    NSNumber *n;
    if ((n = Get(d, @"skipRecentHours", NSNumber.class))) s.skipRecentHours = n.integerValue;
    if ((n = Get(d, @"animations", NSNumber.class))) s.animations = n.boolValue;
    if ((n = Get(d, @"backdrop", NSNumber.class))) s.translucency = n.boolValue;
    // Not "scanOnStartup": 1.0.0 builds saved that as false by default, which must not keep the new default from them.
    if ((n = Get(d, @"scanOnLaunch", NSNumber.class))) s.scanOnStartup = n.boolValue;
    if ((n = Get(d, @"measureDiskWithScan", NSNumber.class))) s.measureDiskWithScan = n.boolValue;
    if ((n = Get(d, @"confirmClean", NSNumber.class))) s.confirmClean = n.boolValue;
    if ((n = Get(d, @"windowWidth", NSNumber.class))) s.windowWidth = n.doubleValue;
    if ((n = Get(d, @"windowHeight", NSNumber.class))) s.windowHeight = n.doubleValue;
    if ((n = Get(d, @"lifetimeBytesFreed", NSNumber.class))) s.lifetimeBytesFreed = n.longLongValue;

    NSDictionary *states = Get(d, @"targetStates", NSDictionary.class);
    for (NSString *key in states)
        if ([states[key] isKindOfClass:NSNumber.class]) s.targetStates[key] = states[key];
    for (id folder in Get(d, @"customFolders", NSArray.class) ?: @[])
        if ([folder isKindOfClass:NSString.class]) [s.customFolders addObject:folder];
    return s;
}

- (void)save {
    NSDictionary *d = @{
        @"language": self.language,
        @"theme": self.theme,
        @"useRecycleBin": @(self.useTrash),
        @"skipRecentHours": @(self.skipRecentHours),
        @"animations": @(self.animations),
        @"backdrop": @(self.translucency),
        @"scanOnLaunch": @(self.scanOnStartup),
        @"measureDiskWithScan": @(self.measureDiskWithScan),
        @"confirmClean": @(self.confirmClean),
        @"targetStates": self.targetStates,
        @"customFolders": self.customFolders,
        @"windowWidth": @(self.windowWidth),
        @"windowHeight": @(self.windowHeight),
        @"windowMaximized": @NO,
        @"lifetimeBytesFreed": @(self.lifetimeBytesFreed),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    if (!data) return;
    NSString *path = [CCSettings filePath];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:path atomically:YES];
}

@end

// ───────────── localization ─────────────

NSNotificationName const CCLanguageDidChangeNotification = @"CCLanguageDidChange";

@implementation CCLanguage
+ (instancetype)code:(NSString *)code name:(NSString *)name {
    CCLanguage *l = [CCLanguage new];
    l.code = code;
    l.nativeName = name;
    return l;
}
@end

@implementation CCLocalization {
    NSDictionary<NSString *, NSString *> *_strings;
    NSString *_code;
}

+ (CCLocalization *)shared {
    static CCLocalization *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [CCLocalization new];
        NSString *resources = NSBundle.mainBundle.resourcePath;
        shared.searchFolders = @[ [resources stringByAppendingPathComponent:@"Strings"],
                                  [resources stringByAppendingPathComponent:@"Strings-mac"] ];
        [shared setLanguage:@"auto"];
    });
    return shared;
}

+ (NSArray<CCLanguage *> *)languages {
    static NSArray *languages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        languages = @[
            [CCLanguage code:@"en" name:@"English"],
            [CCLanguage code:@"ru" name:@"Русский"],
            [CCLanguage code:@"uk" name:@"Українська"],
            [CCLanguage code:@"de" name:@"Deutsch"],
            [CCLanguage code:@"fr" name:@"Français"],
            [CCLanguage code:@"es" name:@"Español"],
            [CCLanguage code:@"pl" name:@"Polski"],
            [CCLanguage code:@"pt" name:@"Português"],
            [CCLanguage code:@"it" name:@"Italiano"],
            [CCLanguage code:@"nl" name:@"Nederlands"],
            [CCLanguage code:@"tr" name:@"Türkçe"],
            [CCLanguage code:@"id" name:@"Bahasa Indonesia"],
            [CCLanguage code:@"vi" name:@"Tiếng Việt"],
            [CCLanguage code:@"hi" name:@"हिन्दी"],
            [CCLanguage code:@"th" name:@"ไทย"],
            [CCLanguage code:@"zh-Hans" name:@"简体中文"],
            [CCLanguage code:@"zh-Hant" name:@"繁體中文"],
            [CCLanguage code:@"ja" name:@"日本語"],
            [CCLanguage code:@"ko" name:@"한국어"],
        ];
    });
    return languages;
}

+ (NSString *)systemLanguageCode {
    for (NSString *preferred in NSLocale.preferredLanguages) {
        NSString *lower = preferred.lowercaseString;
        // Taiwan, Hong Kong and Macao write Traditional Chinese; everywhere else Simplified.
        if ([lower hasPrefix:@"zh"]) {
            BOOL traditional = [lower containsString:@"hant"] || [lower hasSuffix:@"-tw"] || [lower hasSuffix:@"-hk"] || [lower hasSuffix:@"-mo"];
            return traditional ? @"zh-Hant" : @"zh-Hans";
        }
        for (CCLanguage *l in self.languages)
            if ([lower isEqualToString:l.code.lowercaseString] || [lower hasPrefix:[l.code.lowercaseString stringByAppendingString:@"-"]]) return l.code;
    }
    return @"en";
}

- (NSString *)code { return _code ?: @"en"; }

static NSDictionary *ReadStrings(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    // The Windows files are saved with a byte order mark, which NSJSONSerialization rejects.
    if (data.length >= 3 && memcmp(data.bytes, "\xEF\xBB\xBF", 3) == 0) data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

- (void)setLanguage:(NSString *)codeOrAuto {
    NSString *code = [codeOrAuto isEqualToString:@"auto"] ? [CCLocalization systemLanguageCode] : codeOrAuto;
    BOOL known = NO;
    for (CCLanguage *l in CCLocalization.languages) known |= [l.code isEqualToString:code];
    if (!known) code = @"en";

    // English underneath, so a key missing from a translation still shows readable text.
    NSMutableDictionary *strings = [NSMutableDictionary dictionary];
    for (NSString *lang in [code isEqualToString:@"en"] ? @[ @"en" ] : @[ @"en", code ])
        for (NSString *folder in self.searchFolders) {
            NSDictionary *d = ReadStrings([[folder stringByAppendingPathComponent:lang] stringByAppendingPathExtension:@"json"]);
            if (d) [strings addEntriesFromDictionary:d];
        }

    BOOL changed = _code && ![_code isEqualToString:code];
    _strings = strings;
    _code = code;
    CCSetFormatLocale([NSLocale localeWithLocaleIdentifier:code]);
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:CCLanguageDidChangeNotification object:self];
}

- (BOOL)hasKey:(NSString *)key { return _strings[key] != nil; }

- (NSString *)string:(NSString *)key { return _strings[key] ?: key; }

- (NSString *)format:(NSString *)key arguments:(NSArray *)arguments {
    NSMutableString *s = [[self string:key] mutableCopy];
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *token = [NSString stringWithFormat:@"{%lu}", (unsigned long)i];
        [s replaceOccurrencesOfString:token withString:[arguments[i] description] options:0 range:NSMakeRange(0, s.length)];
    }
    return s;
}

@end

NSString *L(NSString *key) { return [CCLocalization.shared string:key]; }

NSString *CCLF(NSString *key, NSArray *arguments) { return [CCLocalization.shared format:key arguments:arguments]; }
