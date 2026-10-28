#import "CCCore.h"
#include <fnmatch.h>
#include <unistd.h>

NSString *CCCategoryName(CCCategory category) {
    switch (category) {
        case CCCategorySystem: return @"System";
        case CCCategoryBrowsers: return @"Browsers";
        case CCCategoryDeveloper: return @"Developer";
        case CCCategoryApps: return @"Apps";
        case CCCategoryGaming: return @"Gaming";
        case CCCategoryCustom: return @"Custom";
    }
    return @"Custom";
}

NSString *CCRiskName(CCRisk risk) {
    switch (risk) {
        case CCRiskSafe: return @"Safe";
        case CCRiskModerate: return @"Moderate";
        case CCRiskCareful: return @"Careful";
    }
    return @"Safe";
}

// ───────────── formatting ─────────────

static NSLocale *FormatLocale(void);
static NSLocale *gFormatLocale;

void CCSetFormatLocale(NSLocale *locale) {
    @synchronized ([NSLocale class]) { gFormatLocale = locale; }
}

static NSLocale *FormatLocale(void) {
    @synchronized ([NSLocale class]) { return gFormatLocale ?: NSLocale.currentLocale; }
}

static NSString *FormatNumber(double value, NSInteger fractionDigits, BOOL grouping) {
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.locale = FormatLocale();
    f.minimumFractionDigits = fractionDigits;
    f.maximumFractionDigits = fractionDigits;
    f.usesGroupingSeparator = grouping;
    f.roundingMode = NSNumberFormatterRoundHalfEven;
    return [f stringFromNumber:@(value)] ?: @"0";
}

void CCSplitBytes(double bytes, NSString **number, NSString **unit) {
    static NSArray<NSString *> *units;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ units = @[ @"B", @"KB", @"MB", @"GB", @"TB", @"PB" ]; });
    if (isnan(bytes) || bytes < 0) bytes = 0;

    NSUInteger index = 0;
    double value = bytes;
    while (value >= 1024 && index < units.count - 1) {
        value /= 1024;
        index++;
    }
    NSInteger digits = index == 0 ? 0 : value >= 100 ? 0 : value >= 10 ? 1 : 2;
    // "1023.6 KB" would round to "1 024 KB"; keep the number readable like the Windows formatter does.
    if (number) *number = FormatNumber(value, digits, NO);
    if (unit) *unit = units[index];
}

NSString *CCFormatBytes(double bytes) {
    NSString *number, *unit;
    CCSplitBytes(bytes, &number, &unit);
    return [NSString stringWithFormat:@"%@ %@", number, unit];
}

NSString *CCFormatCount(long long count) { return FormatNumber((double)count, 0, YES); }

NSString *CCFormatDecimal(double value) { return FormatNumber(value, 1, NO); }

// ───────────── path expansion ─────────────

NSString *CCHomeDirectory(void) {
    const char *custom = getenv("JUNKCLEANUP_HOME");
    if (custom && *custom) return [NSString stringWithUTF8String:custom];
    return NSHomeDirectory();
}

static NSString *DarwinDirectory(int name) {
    char buffer[PATH_MAX];
    size_t length = confstr(name, buffer, sizeof buffer);
    if (length == 0 || length > sizeof buffer) return nil;
    return [NSString stringWithUTF8String:buffer];
}

static BOOL IsDirectory(NSString *path) {
    BOOL dir = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&dir] && dir;
}

NSArray<NSString *> *CCExpandPattern(NSString *pattern) {
    NSString *base;
    NSString *rest;
    if ([pattern hasPrefix:@"~"]) {
        base = CCHomeDirectory();
        rest = [pattern substringFromIndex:1];
    } else if ([pattern hasPrefix:@"$TMP"]) {
        base = DarwinDirectory(_CS_DARWIN_USER_TEMP_DIR) ?: NSTemporaryDirectory();
        rest = [pattern substringFromIndex:4];
    } else if ([pattern hasPrefix:@"$DARWIN_CACHE"]) {
        base = DarwinDirectory(_CS_DARWIN_USER_CACHE_DIR);
        rest = [pattern substringFromIndex:13];
    } else {
        base = @"/";
        rest = pattern;
    }
    if (base.length == 0) return @[];

    NSMutableArray<NSString *> *current = [NSMutableArray arrayWithObject:base];
    for (NSString *segment in [rest componentsSeparatedByString:@"/"]) {
        if (segment.length == 0) continue;
        NSMutableArray<NSString *> *next = [NSMutableArray array];
        BOOL wildcard = [segment rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?["]].location != NSNotFound;
        for (NSString *dir in current) {
            if (!wildcard) {
                [next addObject:[dir stringByAppendingPathComponent:segment]];
                continue;
            }
            NSArray<NSString *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *child in [children sortedArrayUsingSelector:@selector(compare:)]) {
                if (fnmatch(segment.fileSystemRepresentation, child.fileSystemRepresentation, FNM_CASEFOLD) == 0)
                    [next addObject:[dir stringByAppendingPathComponent:child]];
            }
        }
        current = next;
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *path in current)
        if (IsDirectory(path)) [result addObject:path];
    return result;
}

// ───────────── targets ─────────────

@implementation CCTarget

- (instancetype)init {
    if ((self = [super init])) {
        _enabledByDefault = YES;
        _recursive = YES;
        _rootPatterns = @[];
        _symbol = @"folder";
    }
    return self;
}

- (NSString *)nameKey { return [NSString stringWithFormat:@"target.%@.name", self.identifier]; }
- (NSString *)descriptionKey { return [NSString stringWithFormat:@"target.%@.desc", self.identifier]; }
- (BOOL)isCustom { return self.category == CCCategoryCustom; }

- (NSArray<NSString *> *)resolveRoots {
    NSMutableOrderedSet<NSString *> *roots = [NSMutableOrderedSet orderedSet];
    for (NSString *pattern in self.rootPatterns) {
        for (NSString *path in CCExpandPattern(pattern)) {
            NSString *normalized = [CCPathGuard normalize:path];
            if ([CCPathGuard isAllowedRoot:normalized]) [roots addObject:normalized];
        }
    }
    if (self.keepsNewest && roots.count) {
        NSString *newest = roots.firstObject;
        for (NSString *root in roots)
            if ([root.lastPathComponent compare:newest.lastPathComponent options:NSNumericSearch] == NSOrderedDescending) newest = root;
        [roots removeObject:newest];
    }
    if (self.fallback)
        for (CCTarget *t in CCCatalog.allTargets)
            if (!t.fallback) [roots minusSet:[NSSet setWithArray:[t resolveRoots]]];
    return roots.array;
}

@end

static CCTarget *T(NSString *identifier, CCCategory category, NSString *symbol, CCRisk risk, NSArray<NSString *> *roots) {
    CCTarget *t = [CCTarget new];
    t.identifier = identifier;
    t.category = category;
    t.symbol = symbol;
    t.risk = risk;
    t.rootPatterns = roots;
    return t;
}

static CCTarget *Off(CCTarget *t) {
    t.enabledByDefault = NO;
    return t;
}

static CCTarget *Aged(CCTarget *t) {
    t.respectsAgeFilter = YES;
    return t;
}

static CCTarget *Protected(CCTarget *t) {
    t.needsFullDiskAccess = YES;
    return t;
}

/// The caches Chromium keeps next to each profile (the HTTP cache itself lives in ~/Library/Caches on macOS).
static NSArray<NSString *> *Chromium(NSString *caches, NSString *userData) {
    return @[
        caches,
        [userData stringByAppendingString:@"/*/Code Cache"],
        [userData stringByAppendingString:@"/*/GPUCache"],
        [userData stringByAppendingString:@"/*/DawnCache"],
        [userData stringByAppendingString:@"/*/DawnWebGPUCache"],
        [userData stringByAppendingString:@"/*/DawnGraphiteCache"],
        [userData stringByAppendingString:@"/*/Service Worker/CacheStorage"],
        [userData stringByAppendingString:@"/*/Service Worker/ScriptCache"],
        [userData stringByAppendingString:@"/GrShaderCache"],
        [userData stringByAppendingString:@"/ShaderCache"],
        [userData stringByAppendingString:@"/GraphiteDawnCache"],
    ];
}

/// The same caches for Electron apps, which keep one profile directly in their folder.
static NSArray<NSString *> *Electron(NSString *appRoot) {
    NSMutableArray *roots = [NSMutableArray array];
    for (NSString *name in @[ @"Cache", @"Code Cache", @"GPUCache", @"DawnCache", @"DawnWebGPUCache", @"DawnGraphiteCache",
                              @"Service Worker/CacheStorage", @"Service Worker/ScriptCache", @"logs" ])
        [roots addObject:[NSString stringWithFormat:@"%@/%@", appRoot, name]];
    return roots;
}

static NSArray *Join(NSArray *a, NSArray *b) { return [a arrayByAddingObjectsFromArray:b]; }

@implementation CCCatalog

+ (NSArray<CCTarget *> *)allTargets {
    static NSArray<CCTarget *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *AS = @"~/Library/Application Support";
        NSString *LC = @"~/Library/Caches";

        CCTarget *caches = Aged(T(@"mac.caches", CCCategorySystem, @"archivebox", CCRiskModerate, @[ LC ]));
        // Apple's own caches belong to system services (iCloud, Siri, Photos…); they are left to macOS.
        caches.excludedNames = @[ @"com.apple.*", @"CloudKit", @"FamilyCircle", @"GeoServices", @"familycircled" ];

        CCTarget *trash = Off(Protected(T(@"mac.trash", CCCategorySystem, @"trash", CCRiskSafe, @[ @"~/.Trash" ])));

        // Every other Electron / Chromium-based app (Claude, Notion, Figma, Obsidian…).
        CCTarget *electron = T(@"app.electron", CCCategoryApps, @"bubble.left.and.text.bubble.right", CCRiskModerate, Electron([AS stringByAppendingString:@"/*"]));
        electron.fallback = YES;
        // ~/.cache mixes real caches with things that only look like them: model weights (GigaAM, Whisper, Hugging Face),
        // installed runtimes (Codex), even database files (a Postgres data folder). So only folders known to be
        // regenerable caches are taken, never the whole directory.
        // Claude keeps the Claude Code builds it downloads side by side; only the newest is used.
        CCTarget *claudeCode = T(@"app.claudecode", CCCategoryApps, @"terminal", CCRiskSafe, @[ [AS stringByAppendingString:@"/Claude/claude-code/*"] ]);
        claudeCode.keepsNewest = YES;
        CCTarget *xdg = T(@"dev.xdgcache", CCCategoryDeveloper, @"folder", CCRiskSafe, @[
            @"~/.cache/fontconfig", @"~/.cache/mesa_shader_cache", @"~/.cache/gh", @"~/.cache/pip",
            @"~/.cache/pre-commit", @"~/.cache/node-gyp", @"~/.cache/typescript", @"~/.cache/yarn",
            @"~/.cache/puppeteer", @"~/.cache/selenium", @"~/.cache/black", @"~/.cache/mypy",
            @"~/.cache/ruff", @"~/.cache/pylint", @"~/.cache/jedi", @"~/.cache/matplotlib",
            @"~/.cache/deno", @"~/.cache/codex-runtimes/codex-runtime-install-*"
        ]);
        xdg.fallback = YES;
        trash.alwaysPermanent = YES;

        all = @[
            // ── system ──
            caches,
            Aged(T(@"mac.temp", CCCategorySystem, @"folder", CCRiskSafe, @[ @"$TMP" ])),
            T(@"mac.logs", CCCategorySystem, @"doc.text", CCRiskSafe, @[ @"~/Library/Logs" ]),
            T(@"mac.crashreports", CCCategorySystem, @"exclamationmark.triangle", CCRiskSafe, @[ @"~/Library/Logs/DiagnosticReports" ]),
            T(@"mac.thumbnails", CCCategorySystem, @"photo", CCRiskSafe, @[ @"$DARWIN_CACHE/com.apple.QuickLook.thumbnailcache" ]),
            Off(T(@"mac.savedstate", CCCategorySystem, @"macwindow", CCRiskModerate, @[ @"~/Library/Saved Application State" ])),
            Off(Protected(T(@"mac.iosbackups", CCCategorySystem, @"iphone", CCRiskCareful, @[ [AS stringByAppendingString:@"/MobileSync/Backup"] ]))),
            trash,

            // ── browsers ──
            Protected(T(@"browser.safari", CCCategoryBrowsers, @"safari", CCRiskSafe, @[ [LC stringByAppendingString:@"/com.apple.Safari"] ])),
            T(@"browser.chrome", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Chromium([LC stringByAppendingString:@"/Google/Chrome"], [AS stringByAppendingString:@"/Google/Chrome"])),
            T(@"browser.edge", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Chromium([LC stringByAppendingString:@"/Microsoft Edge"], [AS stringByAppendingString:@"/Microsoft Edge"])),
            T(@"browser.brave", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Chromium([LC stringByAppendingString:@"/BraveSoftware/Brave-Browser"], [AS stringByAppendingString:@"/BraveSoftware/Brave-Browser"])),
            T(@"browser.arc", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Chromium([LC stringByAppendingString:@"/Arc"], [AS stringByAppendingString:@"/Arc/User Data"])),
            T(@"browser.vivaldi", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Chromium([LC stringByAppendingString:@"/Vivaldi"], [AS stringByAppendingString:@"/Vivaldi"])),
            T(@"browser.yandex", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Chromium([LC stringByAppendingString:@"/Yandex/YandexBrowser"], [AS stringByAppendingString:@"/Yandex/YandexBrowser"])),
            T(@"browser.opera", CCCategoryBrowsers, @"globe", CCRiskSafe,
              Join(Electron([AS stringByAppendingString:@"/com.operasoftware.Opera"]),
                   Join(Electron([AS stringByAppendingString:@"/com.operasoftware.OperaGX"]),
                        @[ [LC stringByAppendingString:@"/com.operasoftware.Opera"], [LC stringByAppendingString:@"/com.operasoftware.OperaGX"] ]))),
            T(@"browser.firefox", CCCategoryBrowsers, @"globe", CCRiskSafe, @[ [LC stringByAppendingString:@"/Firefox"] ]),

            // ── developer ──
            T(@"dev.xcode.deriveddata", CCCategoryDeveloper, @"hammer", CCRiskSafe,
              @[ @"~/Library/Developer/Xcode/DerivedData", [LC stringByAppendingString:@"/com.apple.dt.Xcode"] ]),
            T(@"dev.xcode.devicesupport", CCCategoryDeveloper, @"iphone", CCRiskModerate,
              @[ @"~/Library/Developer/Xcode/iOS DeviceSupport", @"~/Library/Developer/Xcode/watchOS DeviceSupport",
                 @"~/Library/Developer/Xcode/tvOS DeviceSupport", @"~/Library/Developer/Xcode/visionOS DeviceSupport" ]),
            Off(T(@"dev.xcode.archives", CCCategoryDeveloper, @"archivebox", CCRiskCareful, @[ @"~/Library/Developer/Xcode/Archives" ])),
            T(@"dev.simulator", CCCategoryDeveloper, @"ipad.and.iphone", CCRiskSafe, @[ @"~/Library/Developer/CoreSimulator/Caches" ]),
            T(@"dev.homebrew", CCCategoryDeveloper, @"mug", CCRiskSafe, @[ [LC stringByAppendingString:@"/Homebrew"] ]),
            T(@"dev.cocoapods", CCCategoryDeveloper, @"shippingbox", CCRiskSafe, @[ [LC stringByAppendingString:@"/CocoaPods"] ]),
            T(@"dev.swiftpm", CCCategoryDeveloper, @"swift", CCRiskSafe, @[ [LC stringByAppendingString:@"/org.swift.swiftpm"] ]),
            T(@"dev.pip", CCCategoryDeveloper, @"terminal", CCRiskSafe, @[ [LC stringByAppendingString:@"/pip"] ]),
            T(@"dev.uv", CCCategoryDeveloper, @"terminal", CCRiskSafe, @[ @"~/.cache/uv", [LC stringByAppendingString:@"/uv"] ]),
            T(@"dev.npm", CCCategoryDeveloper, @"shippingbox", CCRiskSafe, @[ @"~/.npm/_cacache", @"~/.npm/_npx", @"~/.npm/_logs" ]),
            T(@"dev.yarn", CCCategoryDeveloper, @"shippingbox", CCRiskSafe, @[ [LC stringByAppendingString:@"/Yarn"], @"~/.yarn/berry/cache" ]),
            T(@"dev.pnpm", CCCategoryDeveloper, @"shippingbox", CCRiskModerate, @[ @"~/Library/pnpm/store" ]),
            T(@"dev.bun", CCCategoryDeveloper, @"shippingbox", CCRiskSafe, @[ @"~/.bun/install/cache" ]),
            T(@"dev.nuget", CCCategoryDeveloper, @"shippingbox", CCRiskSafe, @[ @"~/.local/share/NuGet/http-cache", @"~/.local/share/NuGet/v3-cache" ]),
            Off(T(@"dev.nuget.packages", CCCategoryDeveloper, @"shippingbox", CCRiskModerate, @[ @"~/.nuget/packages" ])),
            T(@"dev.gradle", CCCategoryDeveloper, @"cube", CCRiskModerate, @[ @"~/.gradle/caches", @"~/.gradle/wrapper/dists" ]),
            Off(T(@"dev.maven", CCCategoryDeveloper, @"cube", CCRiskModerate, @[ @"~/.m2/repository" ])),
            T(@"dev.cargo", CCCategoryDeveloper, @"cube", CCRiskSafe, @[ @"~/.cargo/registry/cache", @"~/.cargo/git/checkouts" ]),
            T(@"dev.go", CCCategoryDeveloper, @"cube", CCRiskSafe, @[ [LC stringByAppendingString:@"/go-build"] ]),
            T(@"dev.conda", CCCategoryDeveloper, @"cube", CCRiskModerate,
              @[ @"~/miniconda3/pkgs", @"~/anaconda3/pkgs", @"~/miniforge3/pkgs", @"~/opt/miniconda3/pkgs", @"~/opt/anaconda3/pkgs" ]),
            T(@"dev.android", CCCategoryDeveloper, @"cube", CCRiskSafe, @[ @"~/.android/cache", @"~/.android/build-cache" ]),
            T(@"dev.vscode", CCCategoryDeveloper, @"curlybraces", CCRiskSafe,
              Join(Electron([AS stringByAppendingString:@"/Code"]),
                   @[ [AS stringByAppendingString:@"/Code/CachedData"], [AS stringByAppendingString:@"/Code/CachedExtensionVSIXs"],
                      [LC stringByAppendingString:@"/com.microsoft.VSCode.ShipIt"],
                      // forks keep the same layout
                      [AS stringByAppendingString:@"/Cursor/CachedData"], [AS stringByAppendingString:@"/Cursor/CachedExtensionVSIXs"],
                      [AS stringByAppendingString:@"/Windsurf/CachedData"], [AS stringByAppendingString:@"/Windsurf/CachedExtensionVSIXs"] ])),
            T(@"dev.jetbrains", CCCategoryDeveloper, @"curlybraces", CCRiskModerate,
              @[ [LC stringByAppendingString:@"/JetBrains"], @"~/Library/Logs/JetBrains" ]),
            Off(T(@"dev.playwright", CCCategoryDeveloper, @"theatermasks", CCRiskCareful, @[ [LC stringByAppendingString:@"/ms-playwright"] ])),
            Off(T(@"dev.huggingface", CCCategoryDeveloper, @"brain", CCRiskCareful, @[ @"~/.cache/huggingface/hub" ])),
            Off(T(@"dev.ollama", CCCategoryDeveloper, @"brain", CCRiskCareful, @[ @"~/.ollama/models" ])),
            Off(T(@"dev.lmstudio", CCCategoryDeveloper, @"brain", CCRiskCareful, @[ @"~/.lmstudio/models", @"~/.cache/lm-studio/models" ])),
            xdg,

            // ── apps ──
            T(@"app.discord", CCCategoryApps, @"bubble.left.and.bubble.right", CCRiskSafe, Electron([AS stringByAppendingString:@"/discord"])),
            T(@"app.slack", CCCategoryApps, @"bubble.left.and.bubble.right", CCRiskSafe, Electron([AS stringByAppendingString:@"/Slack"])),
            T(@"app.teams", CCCategoryApps, @"bubble.left.and.bubble.right", CCRiskSafe, Electron([AS stringByAppendingString:@"/Microsoft/Teams"])),
            T(@"app.telegram", CCCategoryApps, @"paperplane", CCRiskModerate, @[ [AS stringByAppendingString:@"/Telegram Desktop/tdata/user_data"] ]),
            T(@"app.spotify", CCCategoryApps, @"music.note", CCRiskModerate,
              @[ [LC stringByAppendingString:@"/com.spotify.client"], [AS stringByAppendingString:@"/Spotify/PersistentCache"] ]),
            T(@"app.itunes", CCCategoryApps, @"iphone", CCRiskSafe,
              @[ @"~/Library/iTunes/iPhone Software Updates", @"~/Library/iTunes/iPad Software Updates", @"~/Library/iTunes/iPod Software Updates" ]),
            T(@"app.adobe", CCCategoryApps, @"film", CCRiskSafe,
              @[ [AS stringByAppendingString:@"/Adobe/Common/Media Cache Files"], [AS stringByAppendingString:@"/Adobe/Common/Media Cache"] ]),
            claudeCode,
            T(@"app.codex", CCCategoryApps, @"terminal", CCRiskSafe, @[ @"~/.codex/cache" ]),
            // Node, Python and LibreOffice for Codex: downloaded again (~1.6 GB) the next time Codex needs them.
            Off(T(@"app.codexruntime", CCCategoryApps, @"shippingbox", CCRiskModerate, @[ @"~/.cache/codex-runtimes/codex-primary-runtime" ])),
            electron,

            // ── gaming ──
            T(@"game.metal", CCCategoryGaming, @"cpu", CCRiskSafe, @[ @"$DARWIN_CACHE/*/com.apple.metal" ]),
            T(@"game.steam", CCCategoryGaming, @"gamecontroller", CCRiskSafe,
              @[ [AS stringByAppendingString:@"/Steam/appcache/httpcache"], [AS stringByAppendingString:@"/Steam/config/htmlcache"],
                 [AS stringByAppendingString:@"/Steam/steamapps/shadercache"] ]),
            T(@"game.epic", CCCategoryGaming, @"gamecontroller", CCRiskSafe,
              @[ [AS stringByAppendingString:@"/Epic/EpicGamesLauncher/Saved/webcache*"], [AS stringByAppendingString:@"/Epic/EpicGamesLauncher/Saved/Logs"],
                 [LC stringByAppendingString:@"/com.epicgames.EpicGamesLauncher"] ]),
            T(@"game.battlenet", CCCategoryGaming, @"gamecontroller", CCRiskSafe,
              @[ [AS stringByAppendingString:@"/Battle.net/Cache"], [AS stringByAppendingString:@"/Battle.net/BrowserCaches"],
                 @"/Users/Shared/Battle.net/Agent/data/cache" ]),
        ];
    });
    return all;
}

+ (NSString *)customIdForFolder:(NSString *)folder {
    return [@"custom:" stringByAppendingString:[CCPathGuard normalize:folder].lowercaseString];
}

+ (CCTarget *)customTargetForFolder:(NSString *)folder {
    CCTarget *t = T([self customIdForFolder:folder], CCCategoryCustom, @"folder", CCRiskModerate, @[ folder ]);
    NSString *name = folder.lastPathComponent;
    t.displayName = name.length ? name : folder;
    return t;
}

@end

// ───────────── path guard ─────────────

/// Collapses "//", "." and ".." without touching the file system. (NSString's standardizing also drops a leading
/// "/private", which would make /private/var/folders/… and its own files disagree.)
static NSString *Lexical(NSString *path) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."]) {
            [parts removeLastObject];
            continue;
        }
        [parts addObject:part];
    }
    return [@"/" stringByAppendingString:[parts componentsJoinedByString:@"/"]];
}

@implementation CCPathGuard

+ (NSString *)normalize:(NSString *)path {
    if (path.length == 0) return @"";
    NSString *expanded = [path hasPrefix:@"~"] ? [CCHomeDirectory() stringByAppendingString:[path substringFromIndex:1]] : path;
    if (![expanded hasPrefix:@"/"]) return @"";
    NSString *standard = Lexical(expanded);
    // Resolve symlinked parents (/var → /private/var) so prefix checks compare like with like.
    char resolved[PATH_MAX];
    if (realpath(standard.fileSystemRepresentation, resolved))
        standard = [NSFileManager.defaultManager stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
    return standard;
}

+ (NSSet<NSString *> *)protectedPaths {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    NSString *home = CCHomeDirectory();
    NSArray *system = @[ @"/", @"/System", @"/Library", @"/Applications", @"/Users", @"/Users/Shared", @"/usr", @"/bin", @"/sbin",
                         @"/opt", @"/opt/homebrew", @"/private", @"/private/var", @"/private/etc", @"/private/tmp", @"/var", @"/etc",
                         @"/tmp", @"/Volumes", @"/cores", @"/Network" ];
    NSArray *personal = @[ @"", @"/Desktop", @"/Documents", @"/Downloads", @"/Pictures", @"/Movies", @"/Music", @"/Public",
                           @"/Applications", @"/Library", @"/Library/Application Support", @"/Library/Preferences",
                           @"/Library/Containers", @"/Library/Group Containers", @"/Library/Mobile Documents",
                           @"/Library/CloudStorage", @"/Library/Mail", @"/Library/Messages", @"/Library/Keychains",
                           @"/Library/Photos", @"/Library/Developer", @"/Library/Developer/Xcode", @"/.ssh",
                           @"/.config", @"/.local", @"/.local/share", @"/.cargo", @"/.gradle", @"/.m2",
                           @"/.npm", @"/.nuget", @"/.android" ];
    for (NSString *p in system) [set addObject:[self normalize:p]];
    for (NSString *p in personal) [set addObject:[self normalize:[home stringByAppendingString:p]]];
    [set addObject:home];
    return set;
}

+ (BOOL)isAllowedRoot:(NSString *)root {
    if (root.length == 0) return NO;
    NSString *full = [self normalize:root];
    if (full.length <= 1 || ![full hasPrefix:@"/"]) return NO;
    if ([[self protectedPaths] containsObject:full]) return NO;

    // Never a parent of the home folder ("/Users", a volume root above it).
    NSString *home = [self normalize:CCHomeDirectory()];
    if ([home hasPrefix:[full stringByAppendingString:@"/"]]) return NO;
    return YES;
}

+ (BOOL)isPath:(NSString *)path insideRoots:(NSArray<NSString *> *)roots {
    if (path.length == 0 || ![path hasPrefix:@"/"]) return NO;
    // Only ".." and "." are collapsed here: the file itself may be a symlink, which is removed, never followed.
    NSString *full = Lexical(path);
    for (NSString *root in roots) {
        NSString *r = [self normalize:root];
        if (r.length <= 1) continue;
        if (full.length > r.length + 1 && [full hasPrefix:r] && [full characterAtIndex:r.length] == '/') return YES;
    }
    return NO;
}

@end
