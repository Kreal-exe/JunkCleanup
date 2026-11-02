// Core tests for the macOS app, the counterpart of tests/JunkCleanup.Tests: byte formatting, the path guard,
// catalog invariants, localization parity and scan/clean behaviour on a scratch folder. Run by ./build.sh --test.
#import <Foundation/Foundation.h>
#import "CCCore.h"
#import "CCEngine.h"
#import "CCSettings.h"
#include <sys/stat.h>
#include <utime.h>

static int gFailed = 0, gPassed = 0;

#define CHECK(cond, ...)                                                                   \
    do {                                                                                   \
        if (cond) gPassed++;                                                               \
        else {                                                                             \
            gFailed++;                                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, [[NSString stringWithFormat:__VA_ARGS__] UTF8String]); \
        }                                                                                  \
    } while (0)

#define EQUAL(a, b) CHECK([(a) isEqual:(b)], @"%@ != %@", (a), (b))

static NSString *Scratch(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [CCPathGuard normalize:dir];
}

static void Write(NSString *path, NSUInteger bytes) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSMutableData dataWithLength:bytes] writeToFile:path atomically:NO];
}

static void Age(NSString *path, double hours) {
    struct utimbuf times = { .actime = time(NULL) - (time_t)(hours * 3600), .modtime = time(NULL) - (time_t)(hours * 3600) };
    utime(path.fileSystemRepresentation, &times);
}

static BOOL Exists(NSString *path) { return [NSFileManager.defaultManager fileExistsAtPath:path]; }

static void TestFormatting(void) {
    CCSetFormatLocale([NSLocale localeWithLocaleIdentifier:@"en_US"]);
    EQUAL(CCFormatBytes(0), @"0 B");
    EQUAL(CCFormatBytes(1023), @"1023 B");
    EQUAL(CCFormatBytes(1024), @"1.00 KB");
    EQUAL(CCFormatBytes(1536), @"1.50 KB");
    EQUAL(CCFormatBytes(10.5 * 1024 * 1024), @"10.5 MB");
    EQUAL(CCFormatBytes(150.0 * 1024 * 1024 * 1024), @"150 GB");
    EQUAL(CCFormatBytes(-5), @"0 B");
    EQUAL(CCFormatCount(133697), @"133,697");
    NSString *number, *unit;
    CCSplitBytes(37.6 * 1024 * 1024 * 1024, &number, &unit);
    EQUAL(number, @"37.6");
    EQUAL(unit, @"GB");

    CCSetFormatLocale([NSLocale localeWithLocaleIdentifier:@"ru"]);
    EQUAL(CCFormatBytes(1536), @"1,50 KB");
    EQUAL(CCFormatDecimal(0.4), @"0,4");
    CCSetFormatLocale([NSLocale localeWithLocaleIdentifier:@"en_US"]);
}

static void TestPathGuard(NSString *home) {
    CHECK(![CCPathGuard isAllowedRoot:@"/"], @"/ allowed");
    CHECK(![CCPathGuard isAllowedRoot:@"/Users"], @"/Users allowed");
    CHECK(![CCPathGuard isAllowedRoot:@"/System"], @"/System allowed");
    CHECK(![CCPathGuard isAllowedRoot:@"/Applications"], @"/Applications allowed");
    CHECK(![CCPathGuard isAllowedRoot:home], @"home allowed");
    CHECK(![CCPathGuard isAllowedRoot:[home stringByAppendingString:@"/"]], @"home/ allowed");
    for (NSString *p in @[ @"Documents", @"Desktop", @"Downloads", @"Library", @"Library/Application Support", @"Library/Containers",
                           @"Library/Mobile Documents", @"Pictures", @".ssh" ])
        CHECK(![CCPathGuard isAllowedRoot:[home stringByAppendingPathComponent:p]], @"%@ allowed", p);
    CHECK(![CCPathGuard isAllowedRoot:[home stringByAppendingString:@"/Library/Caches/../../Documents"]], @"dot-dot escape allowed");
    CHECK([CCPathGuard isAllowedRoot:[home stringByAppendingPathComponent:@"Library/Caches"]], @"Caches refused");
    CHECK(![CCPathGuard isAllowedRoot:@"relative/path"], @"relative path allowed");
    CHECK(![CCPathGuard isAllowedRoot:@""], @"empty allowed");

    CHECK([CCPathGuard isPath:@"/a/b/c" insideRoots:@[ @"/a/b" ]], @"child not inside");
    CHECK(![CCPathGuard isPath:@"/a/bc" insideRoots:@[ @"/a/b" ]], @"sibling prefix inside");
    CHECK(![CCPathGuard isPath:@"/a/b" insideRoots:@[ @"/a/b" ]], @"root itself inside");
    CHECK(![CCPathGuard isPath:@"/a/b/../../etc/passwd" insideRoots:@[ @"/a/b" ]], @"dot-dot inside");
    CHECK(![CCPathGuard isPath:@"relative" insideRoots:@[ @"/a/b" ]], @"relative inside");

    // /var is a symlink to /private/var: both spellings must agree.
    NSString *tmp = [CCPathGuard normalize:NSTemporaryDirectory()];
    CHECK([tmp hasPrefix:@"/private/"], @"temp not resolved: %@", tmp);
    CHECK([CCPathGuard isPath:[tmp stringByAppendingPathComponent:@"x/y"] insideRoots:@[ NSTemporaryDirectory() ]], @"temp file not inside temp");
}

static NSDictionary *MergedStrings(NSArray<NSString *> *folders, NSString *code) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *folder in folders) {
        NSData *data = [NSData dataWithContentsOfFile:[[folder stringByAppendingPathComponent:code] stringByAppendingPathExtension:@"json"]];
        if (!data) continue;
        if (data.length >= 3 && memcmp(data.bytes, "\xEF\xBB\xBF", 3) == 0) data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        CHECK([json isKindOfClass:NSDictionary.class], @"%@/%@.json is not a JSON object", folder, code);
        if (json) [d addEntriesFromDictionary:json];
    }
    return d;
}

static NSSet *Placeholders(NSString *s) {
    NSMutableSet *set = [NSMutableSet set];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\{\\d+\\}" options:0 error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) [set addObject:[s substringWithRange:m.range]];
    return set;
}

static void TestCatalogAndStrings(NSArray<NSString *> *folders) {
    NSArray<CCTarget *> *all = CCCatalog.allTargets;
    CHECK(all.count >= 40, @"only %lu targets", (unsigned long)all.count);
    NSMutableSet *ids = [NSMutableSet set], *patterns = [NSMutableSet set];
    NSDictionary *en = MergedStrings(folders, @"en");
    for (CCTarget *t in all) {
        CHECK(![ids containsObject:t.identifier], @"duplicate id %@", t.identifier);
        [ids addObject:t.identifier];
        CHECK(en[t.nameKey] != nil, @"missing %@", t.nameKey);
        CHECK(en[t.descriptionKey] != nil, @"missing %@", t.descriptionKey);
        CHECK(t.rootPatterns.count > 0, @"%@ has no roots", t.identifier);
        CHECK(t.category != CCCategoryCustom, @"%@ is custom", t.identifier);
        for (NSString *p in t.rootPatterns) {
            CHECK(![patterns containsObject:p], @"%@ is listed twice", p);
            [patterns addObject:p];
            CHECK([p hasPrefix:@"~/"] || [p hasPrefix:@"$TMP"] || [p hasPrefix:@"$DARWIN_CACHE/"] || [p hasPrefix:@"/Users/Shared/"],
                  @"%@ escapes the user's own folders", p);
        }
    }
    for (NSString *key in @[ @"insight.snapshots.title", @"insight.swap.detail", @"menu.quit", @"titlebar.runAsAdmin" ])
        CHECK(en[key] != nil, @"missing %@", key);

    // The overlay may only replace keys English has, and must keep their {0} placeholders.
    NSString *overlay = folders.lastObject;
    NSDictionary *enOverlay = MergedStrings(@[ overlay ], @"en");
    for (CCLanguage *language in CCLocalization.languages) {
        NSString *code = language.code;
        if ([code isEqualToString:@"en"]) continue;
        NSDictionary *strings = MergedStrings(@[ overlay ], code);
        CHECK(strings.count > 0, @"no macOS strings for %@", code);
        for (NSString *key in strings) {
            CHECK(enOverlay[key] != nil, @"%@.json has %@, English does not", code, key);
            if (enOverlay[key]) CHECK([Placeholders(strings[key]) isEqualToSet:Placeholders(enOverlay[key])], @"%@: placeholders of %@", code, key);
        }
        NSDictionary *merged = MergedStrings(folders, code);
        for (CCTarget *t in all) CHECK(merged[t.nameKey] != nil, @"%@ has no %@", code, t.nameKey);
    }
}

static void TestLocalization(NSArray<NSString *> *folders) {
    CCLocalization *loc = [CCLocalization new];
    loc.searchFolders = folders;
    [loc setLanguage:@"ru"];
    EQUAL(loc.code, @"ru");
    EQUAL([loc string:@"dash.modeRecycle"], @"В Корзину");
    EQUAL([loc string:@"nav.dashboard"], @"Обзор");
    EQUAL([loc format:@"dash.filesCount" arguments:@[ @"12" ]], @"Файлов: 12");
    EQUAL([loc string:@"no.such.key"], @"no.such.key");
    [loc setLanguage:@"de"];
    // German has no description for this macOS-only target and falls back to English.
    EQUAL([loc string:@"target.dev.bun.desc"], @"Packages downloaded by bun install.");
    [loc setLanguage:@"xx"];
    EQUAL(loc.code, @"en");
}

static CCTarget *Custom(NSString *root) { return [CCCatalog customTargetForFolder:root]; }

static void TestScanAndClean(void) {
    NSString *base = Scratch();
    NSString *root = [base stringByAppendingPathComponent:@"cache"];
    NSString *outside = [base stringByAppendingPathComponent:@"outside"];
    Write([root stringByAppendingPathComponent:@"a/1.bin"], 100);
    Write([root stringByAppendingPathComponent:@"a/b/2.bin"], 200);
    Write([root stringByAppendingPathComponent:@"top.txt"], 50);
    Write([root stringByAppendingPathComponent:@"other/3.bin"], 300);
    Write([outside stringByAppendingPathComponent:@"keep.txt"], 10);
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"link"] withDestinationPath:outside error:nil];
    for (NSString *f in @[ @"a/1.bin", @"a/b/2.bin", @"top.txt", @"other/3.bin" ]) Age([root stringByAppendingPathComponent:f], 48);

    CCScanEngine *scanner = [CCScanEngine new];
    CCScanOptions *options = [CCScanOptions new];
    options.excludedRoots = [NSSet setWithObject:[root stringByAppendingPathComponent:@"other"]];
    CCScanResult *r = [scanner scanTarget:Custom(root) options:options cancel:nil onBytes:nil];
    CHECK(r.totalBytes == 350, @"scanned %lld bytes, expected 350 (excluded root and symlink skipped)", r.totalBytes);
    CHECK(r.fileCount == 3, @"scanned %ld files", (long)r.fileCount);
    CCEntry *a = nil;
    for (CCEntry *e in r.topEntries)
        if ([e.name isEqualToString:@"a"]) a = e;
    CHECK(a && a.isDirectory && a.bytes == 300 && a.files == 2 && a.complete, @"entry a: %@ %lld %ld", a.name, a.bytes, (long)a.files);
    CHECK(r.topEntries.firstObject == a, @"largest entry first");

    // Side-by-side builds: every one but the newest version is offered.
    NSString *builds = [base stringByAppendingPathComponent:@"builds"];
    for (NSString *v in @[ @"2.1.9", @"2.1.308", @"2.1.309" ]) Write([builds stringByAppendingPathComponent:[v stringByAppendingPathComponent:@"bin"]], 10);
    CCTarget *versions = Custom([builds stringByAppendingPathComponent:@"*"]);
    versions.keepsNewest = YES;
    NSArray<NSString *> *offered = [[versions.resolveRoots valueForKey:@"lastPathComponent"] sortedArrayUsingSelector:@selector(compare:)];
    EQUAL(offered, (@[ @"2.1.308", @"2.1.9" ]));

    // The age filter skips fresh files and marks their folder incomplete.
    CCTarget *aged = Custom(root);
    aged.respectsAgeFilter = YES;
    Write([root stringByAppendingPathComponent:@"a/fresh.bin"], 1000);
    options.skipNewerThanHours = 24;
    CCScanResult *agedResult = [scanner scanTarget:aged options:options cancel:nil onBytes:nil];
    CHECK(agedResult.totalBytes == 350, @"age filter: %lld", agedResult.totalBytes);
    for (CCEntry *e in agedResult.topEntries)
        if ([e.name isEqualToString:@"a"]) CHECK(!e.complete, @"folder with a skipped file is complete");
    options.skipNewerThanHours = 0;

    // Dry run counts without touching anything.
    CCCleanOptions *dry = [CCCleanOptions new];
    dry.dryRun = YES;
    CCTargetCleanResult *d = [[CCCleanEngine new] cleanTarget:agedResult options:dry cancel:nil onProgress:nil];
    CHECK(d.bytesFreed == 350 && d.filesDeleted == 3, @"dry run %lld/%ld", d.bytesFreed, (long)d.filesDeleted);
    CHECK(Exists([root stringByAppendingPathComponent:@"a/1.bin"]), @"dry run deleted a file");

    // A file list that points outside the scanned roots is refused.
    CCScanResult *forged = [scanner scanTarget:Custom(root) options:options cancel:nil onBytes:nil];
    [forged.files addObject:[outside stringByAppendingPathComponent:@"keep.txt"]];
    long long ten = 10;
    [forged.sizes appendBytes:&ten length:sizeof ten];
    [forged.files addObject:[root stringByAppendingPathComponent:@"link/keep.txt"]];
    [forged.sizes appendBytes:&ten length:sizeof ten];
    CCCleanOptions *permanent = [CCCleanOptions new];
    permanent.useTrash = NO;
    CCTargetCleanResult *c = [[CCCleanEngine new] cleanTarget:forged options:permanent cancel:nil onProgress:nil];
    CHECK(c.filesDeleted == 4, @"deleted %ld files, expected 4 (fresh.bin included in this scan)", (long)c.filesDeleted);
    CHECK(c.failed == 2, @"%ld refused, expected 2", (long)c.failed);
    CHECK(Exists([outside stringByAppendingPathComponent:@"keep.txt"]), @"a file outside the roots was deleted");
    CHECK(Exists([root stringByAppendingPathComponent:@"other/3.bin"]), @"another target's file was deleted");
    CHECK(!Exists([root stringByAppendingPathComponent:@"a"]), @"emptied folder a was not pruned");
    CHECK(Exists(root), @"the root itself was removed");
    CHECK(!Exists([root stringByAppendingPathComponent:@"top.txt"]), @"top.txt survived");

    // A stopped clean leaves the rest of the files alone and says how many remain.
    Write([root stringByAppendingPathComponent:@"again/4.bin"], 40);
    CCScanResult *again = [scanner scanTarget:Custom(root) options:options cancel:nil onBytes:nil];
    CCCancelToken *stop = [CCCancelToken new];
    [stop cancel];
    CCCleanReport *stopped = [[CCCleanEngine new] clean:@[ again ] options:permanent cancel:stop progress:nil];
    CHECK(stopped.cancelled && stopped.filesDeleted == 0, @"stopped clean deleted %ld files", (long)stopped.filesDeleted);
    CHECK(Exists([root stringByAppendingPathComponent:@"again/4.bin"]), @"stopped clean removed a file");
    CCTargetCleanResult *partial = [[CCCleanEngine new] cleanTarget:again options:permanent cancel:stop onProgress:nil];
    CHECK(partial.filesRemaining == again.fileCount && partial.bytesRemaining == again.totalBytes, @"remaining after stop");

    // One entry picked by hand goes, its siblings stay, and the scan forgets it.
    Write([root stringByAppendingPathComponent:@"pick/big.bin"], 500);
    Write([root stringByAppendingPathComponent:@"pick/sub/more.bin"], 70);
    Write([root stringByAppendingPathComponent:@"keep/small.bin"], 30);
    CCScanResult *picked = [scanner scanTarget:Custom(root) options:options cancel:nil onBytes:nil];
    CCEntry *pick = nil;
    for (CCEntry *e in picked.topEntries)
        if ([e.name isEqualToString:@"pick"]) pick = e;
    long long before = picked.totalBytes;
    CCTargetCleanResult *one = [[CCCleanEngine new] removeEntry:pick fromScan:picked options:permanent];
    CHECK(one && one.bytesFreed == 570 && one.filesDeleted == 2, @"entry removal freed %lld", one.bytesFreed);
    CHECK(!Exists([root stringByAppendingPathComponent:@"pick"]), @"picked folder survived");
    CHECK(Exists([root stringByAppendingPathComponent:@"keep/small.bin"]), @"sibling was removed");
    CHECK(picked.totalBytes == before - 570 && ![picked.topEntries containsObject:pick], @"scan still lists the entry");
    CCEntry *outsider = [CCEntry new];
    outsider.path = [outside stringByAppendingPathComponent:@"keep.txt"];
    CHECK([[CCCleanEngine new] removeEntry:outsider fromScan:picked options:permanent] == nil, @"an entry outside the roots was removed");
    CHECK(Exists([outside stringByAppendingPathComponent:@"keep.txt"]), @"a file outside the roots was deleted");

    // Protected and missing roots resolve to nothing.
    CHECK([Custom(CCHomeDirectory()) resolveRoots].count == 0, @"home resolved as a root");
    CHECK([Custom([base stringByAppendingPathComponent:@"missing"]) resolveRoots].count == 0, @"missing folder resolved");

    // An unreadable root is reported as denied, not as empty.
    NSString *locked = [base stringByAppendingPathComponent:@"locked"];
    Write([locked stringByAppendingPathComponent:@"x.bin"], 10);
    chmod(locked.fileSystemRepresentation, 0);
    CCScanResult *denied = [scanner scanTarget:Custom(locked) options:options cancel:nil onBytes:nil];
    CHECK(denied.accessDenied || getuid() == 0, @"unreadable root not reported");
    chmod(locked.fileSystemRepresentation, 0755);

    // Parallel scanning reports progress and every result.
    __block NSInteger completed = 0;
    NSArray *results = [scanner scanTargets:@[ Custom(root), Custom(outside) ] options:options cancel:nil progress:^(CCScanEvent *e) {
        if (e.phase == CCScanPhaseCompleted) completed++;
    }];
    CHECK(results.count == 2 && completed == 2, @"parallel scan: %lu results, %ld completions", (unsigned long)results.count, (long)completed);

    // A cancelled scan stops.
    CCCancelToken *token = [CCCancelToken new];
    [token cancel];
    CHECK([scanner scanTargets:@[ Custom(root) ] options:options cancel:token progress:nil].count == 0, @"cancelled scan ran");

    [NSFileManager.defaultManager removeItemAtPath:base error:nil];
}

/// VM image downloads live inside ~/Library/Caches: the app-caches target leaves them to their own target, so nothing is
/// counted (or cleaned) twice. "Skip recent" Off scans even files written a moment ago.
static void TestNestedTargets(void) {
    NSString *home = Scratch();
    setenv("JUNKCLEANUP_HOME", home.fileSystemRepresentation, 1);
    NSString *(^H)(NSString *) = ^NSString *(NSString *p) { return [home stringByAppendingPathComponent:p]; };
    Write(H(@"Library/Caches/lima/download/by-url-sha256/abc/data"), 9000);
    Write(H(@"Library/Caches/lima/other.bin"), 100);
    Write(H(@"Library/Caches/colima/img.qcow2"), 7000);
    Write(H(@".colima/_lima/_cache/base.img"), 5000);
    Write(H(@"Library/Caches/com.example.app/cache.db"), 300);

    CCTarget *caches = nil, *images = nil;
    for (CCTarget *t in CCCatalog.allTargets) {
        if ([t.identifier isEqualToString:@"mac.caches"]) caches = t;
        if ([t.identifier isEqualToString:@"dev.vmimages"]) images = t;
    }
    CHECK(images && images.category == CCCategoryDeveloper && images.risk == CCRiskModerate && images.enabledByDefault, @"dev.vmimages");
    CHECK([images resolveRoots].count == 3, @"dev.vmimages resolved %lu roots", (unsigned long)[images resolveRoots].count);

    CCScanOptions *options = [CCScanOptions new];
    NSMutableSet *all = [NSMutableSet set];
    for (CCTarget *t in @[ caches, images ]) [all addObjectsFromArray:[t resolveRoots]];
    options.excludedRoots = all;
    options.skipNewerThanHours = 0; // Off: the files above were written just now and still count
    NSArray<CCScanResult *> *results = [[CCScanEngine new] scanTargets:@[ caches, images ] options:options cancel:nil progress:nil];
    long long cacheBytes = 0, imageBytes = 0;
    NSMutableSet *seen = [NSMutableSet set];
    BOOL twice = NO;
    for (CCScanResult *r in results) {
        if (r.target == caches) cacheBytes = r.totalBytes;
        if (r.target == images) imageBytes = r.totalBytes;
        for (NSString *f in r.files) {
            if ([seen containsObject:f]) twice = YES;
            [seen addObject:f];
        }
    }
    CHECK(!twice, @"a file was scanned by both targets");
    CHECK(imageBytes == 21000, @"VM images found %lld bytes, expected 21000", imageBytes);
    CHECK(cacheBytes == 400, @"app caches found %lld bytes, expected 400 (Off skips nothing, images left out)", cacheBytes);

    unsetenv("JUNKCLEANUP_HOME");
    [NSFileManager.defaultManager removeItemAtPath:home error:nil];
}

static void TestSettings(void) {
    NSString *file = [Scratch() stringByAppendingPathComponent:@"settings.json"];
    setenv("JUNKCLEANUP_SETTINGS", file.fileSystemRepresentation, 1);
    CCSettings *s = [CCSettings load];
    EQUAL(s.theme, @"dark");
    CHECK(s.useTrash && s.skipRecentHours == 24 && s.animations, @"defaults");
    CHECK(s.measureDiskWithScan && s.confirmClean, @"disk-with-scan and confirm-clean are on by default");
    s.measureDiskWithScan = NO;
    s.confirmClean = NO;
    s.theme = @"light";
    s.useTrash = NO;
    s.targetStates[@"dev.pip"] = @NO;
    [s.customFolders addObject:@"/tmp/x"];
    s.lifetimeBytesFreed = 12345;
    [s save];
    CCSettings *r = [CCSettings load];
    EQUAL(r.theme, @"light");
    CHECK(!r.useTrash, @"useTrash not saved");
    CHECK(!r.measureDiskWithScan && !r.confirmClean, @"measureDiskWithScan / confirmClean not saved");
    EQUAL(r.targetStates[@"dev.pip"], @NO);
    EQUAL(r.customFolders, @[ @"/tmp/x" ]);
    CHECK(r.lifetimeBytesFreed == 12345, @"lifetime not saved");
    [r resetToDefaults];
    CHECK(r.measureDiskWithScan && r.confirmClean, @"reset leaves them off");
    [@"{ not json" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    EQUAL([CCSettings load].theme, @"dark");
    unsetenv("JUNKCLEANUP_SETTINGS");
}

// ───────────── disk map ─────────────

static long long Allocated(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 ? (long long)st.st_blocks * 512 : 0;
}

/// Every regular file underneath, by allocated size, leaving out the given folders.
static long long AllFiles(NSString *root, NSArray<NSString *> *without) {
    long long sum = 0;
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtPath:root];
    for (NSString *relative in e) {
        NSString *path = [root stringByAppendingPathComponent:relative];
        BOOL skip = NO;
        for (NSString *w in without)
            if ([path isEqualToString:w] || [path hasPrefix:[w stringByAppendingString:@"/"]]) skip = YES;
        struct stat st;
        if (skip || lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        sum += (long long)st.st_blocks * 512;
    }
    return sum;
}

/// The entry with this id anywhere in the report (items, their parts, folded folders).
static CCSpaceEntry *Find(NSArray<CCSpaceEntry *> *entries, NSString *identifier) {
    for (CCSpaceEntry *e in entries) {
        if ([e.identifier isEqualToString:identifier]) return e;
        CCSpaceEntry *inner = Find(e.children, identifier);
        if (inner) return inner;
    }
    return nil;
}

/// The Mac catalog on a scratch home: only the rules and roots inside the home folder, so nothing real is read.
static CCSpaceScope *HomeScope(BOOL fullDiskAccess) {
    CCSpaceScope *scope = [CCSpaceCatalog scopeWithFullDiskAccess:fullDiskAccess];
    scope.rules = [scope.rules filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CCSpaceRule *r, NSDictionary *b) {
        for (NSString *p in r.paths)
            if (![p hasPrefix:@"~/"]) return NO;
        return YES;
    }]];
    scope.roots = [scope.roots filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pattern BEGINSWITH '~'"]];
    return scope;
}

static void TestDiskMap(NSArray<NSString *> *folders) {
    NSString *home = Scratch();
    setenv("JUNKCLEANUP_HOME", home.fileSystemRepresentation, 1);
    NSString *(^H)(NSString *) = ^NSString *(NSString *p) { return [home stringByAppendingPathComponent:p]; };
    Write(H(@".hermes/cache/uv/wheel.bin"), 10000);
    Write(H(@".hermes/hermes-agent/run.py"), 5000);
    Write(H(@".hermes/hermes-agent/.cache/x.bin"), 3000);
    Write(H(@".hermes/backups/pre-restore.tar"), 2000);
    Write(H(@".hermes/logs/agent.log"), 1000);
    Write(H(@".hermes/installs/python/lib.so"), 4000);
    Write(H(@".hermes/state.db"), 700);
    Write(H(@".cache/huggingface/hub/models--a--b/blob"), 9000);
    Write(H(@".cache/huggingface/hub/models--c--d/blob"), 6000);
    Write(H(@"Library/Caches/com.example.app/cache.db"), 800);
    Write(H(@"Library/Caches/com.apple.Safari/history"), 900);
    Write(H(@"Library/Application Support/OldApp/data.bin"), 1200);
    Write(H(@"Library/Containers/com.example.sandboxed/Data/secret"), 5000);
    Write(H(@"Documents/report.pages"), 1500);
    Write(H(@"Projects/big.bin"), 7000);
    Write(H(@".outside/real.bin"), 3000);
    [NSFileManager.defaultManager createSymbolicLinkAtPath:H(@".hermes/cache/link") withDestinationPath:H(@".outside") error:nil];
    NSArray<CCTarget *> *targets = @[ CCCatalog.allTargets.firstObject ]; // ~/Library/Caches, Apple's own left out

    CCSpaceReport *r = [[CCDiskMapEngine new] analyze:HomeScope(YES) targets:targets cancel:nil progress:nil];
    CHECK(r.total > 0 && r.free > 0, @"no volume figures");

    // Hermes: the agent is kept, its caches can go, the backups only with care; its code leaves the cache inside out.
    CCSpaceEntry *hermes = Find(r.items, @"hermes");
    CHECK(hermes && hermes.risk == CCSpaceRiskKeep && !hermes.canDelete && hermes.segment == CCSpaceDeveloper, @"hermes item");
    CCSpaceEntry *cache = Find(r.items, @"hermes/cache"), *inner = Find(r.items, @"hermes/hermes-agent/.cache");
    CCSpaceEntry *agent = Find(r.items, @"hermes/hermes-agent"), *backups = Find(r.items, @"hermes/backups");
    CCSpaceEntry *logs = Find(r.items, @"hermes/logs"), *installs = Find(r.items, @"hermes/installs");
    CHECK(cache.risk == CCSpaceRiskSafe && cache.canDelete && [cache.key isEqualToString:@"space.kind.cache"], @"hermes cache");
    CHECK(inner.risk == CCSpaceRiskSafe && inner.canDelete, @"hermes-agent/.cache");
    CHECK(backups.risk == CCSpaceRiskCareful && backups.canDelete, @"hermes backups");
    CHECK(logs.risk == CCSpaceRiskModerate, @"hermes logs");
    CHECK(installs.risk == CCSpaceRiskKeep && !installs.canDelete && agent.risk == CCSpaceRiskKeep && !agent.canDelete, @"hermes app parts");
    CHECK(cache.bytes == Allocated(H(@".hermes/cache/uv/wheel.bin")), @"the cache followed a link: %lld", cache.bytes);
    CHECK(agent.bytes == Allocated(H(@".hermes/hermes-agent/run.py")), @"hermes-agent counted its cache: %lld", agent.bytes);
    CHECK(hermes.bytes == AllFiles(H(@".hermes"), @[]), @"hermes %lld != %lld", hermes.bytes, AllFiles(H(@".hermes"), @[]));

    // One row per model, each removable on its own.
    CCSpaceEntry *hf = Find(r.items, @"huggingface");
    CHECK(hf && hf.children.count == 2 && hf.segment == CCSpaceModels && hf.children.firstObject.canDelete, @"huggingface models");
    EQUAL(hf.children.firstObject.name, @"models--a--b");

    // The cleaner's target is filed under the caches, without Apple's own, and is cleaned from the Targets page.
    CCSpaceEntry *caches = Find(r.items, @"caches");
    CCSpaceEntry *target = Find(r.items, CCCatalog.allTargets.firstObject.identifier);
    CHECK(caches && target && target.targetId && !target.canDelete, @"cache target");
    CHECK(target.bytes == Allocated(H(@"Library/Caches/com.example.app/cache.db")), @"Apple's caches counted as cleanable: %lld", target.bytes);

    // Discovered folders: yours are kept, the rest may go; a container lists what it holds.
    CCSpaceEntry *documents = Find(r.items, [@"folder:" stringByAppendingString:H(@"Documents")]);
    CCSpaceEntry *projects = Find(r.items, [@"folder:" stringByAppendingString:H(@"Projects")]);
    CCSpaceEntry *support = Find(r.items, [@"folder:" stringByAppendingString:H(@"Library/Application Support")]);
    CHECK(documents && documents.risk == CCSpaceRiskKeep && !documents.canDelete && documents.segment == CCSpaceFiles, @"Documents");
    CHECK(projects && projects.risk == CCSpaceRiskCareful && projects.canDelete, @"Projects");
    CHECK(support && support.risk == CCSpaceRiskKeep && support.children.count == 1 && support.children.firstObject.canDelete, @"Application Support");
    CHECK(Find(r.items, [@"folder:" stringByAppendingString:H(@"Library")]) == nil, @"~/Library listed as one folder");
    CHECK(Find(r.items, [@"folder:" stringByAppendingString:H(@"Library/Containers")]) == nil, @"a sandbox container was opened");

    // Every byte is counted once: the items add up to the files on disk, minus the containers and Apple's caches.
    long long expected = AllFiles(home, @[ H(@"Library/Containers"), H(@"Library/Caches/com.apple.Safari") ]);
    CHECK(r.measured == expected, @"measured %lld, files hold %lld", r.measured, expected);
    long long bands = 0;
    for (NSInteger s = 0; s < CCSpaceSegmentCount; s++) bands += r.segments[s];
    CHECK(bands >= r.measured && r.segments[CCSpaceSystem] >= 0, @"bands %lld < measured %lld", bands, r.measured);

    // Without Full Disk Access, Documents is shown but not opened.
    CCSpaceReport *limited = [[CCDiskMapEngine new] analyze:HomeScope(NO) targets:targets cancel:nil progress:nil];
    CCSpaceEntry *guarded = Find(limited.items, [@"folder:" stringByAppendingString:H(@"Documents")]);
    CHECK(guarded && guarded.needsAccess && guarded.bytes == 0 && !guarded.canDelete, @"Documents without access");
    CHECK(limited.measured == expected - Allocated(H(@"Documents/report.pages")), @"limited measured %lld", limited.measured);

    // A cancelled analysis measures nothing.
    CCCancelToken *stop = [CCCancelToken new];
    [stop cancel];
    CHECK([[CCDiskMapEngine new] analyze:HomeScope(YES) targets:targets cancel:stop progress:nil].items.count == 0, @"cancelled analysis ran");

    // Removal: a Safe part goes, Keep and protected items and cache targets never do.
    CCDiskMapEngine *engine = [CCDiskMapEngine new];
    CHECK([engine removeEntry:installs useTrash:NO] == 0 && Exists(H(@".hermes/installs")), @"a Keep part was removed");
    CHECK([engine removeEntry:hermes useTrash:NO] == 0 && Exists(H(@".hermes")), @"a Keep item was removed");
    CHECK([engine removeEntry:documents useTrash:NO] == 0 && Exists(H(@"Documents/report.pages")), @"your files were removed");
    CHECK([engine removeEntry:target useTrash:NO] == 0 && Exists(H(@"Library/Caches/com.example.app")), @"a cache target was removed here");
    CCSpaceEntry *forged = [CCSpaceEntry new];
    forged.risk = CCSpaceRiskSafe;
    forged.paths = @[ H(@"Library") ];
    forged.canDelete = YES;
    CHECK([engine removeEntry:forged useTrash:NO] == 0 && Exists(H(@"Library")), @"a protected folder was removed");
    forged.paths = @[ H(@".hermes/cache/link") ];
    CHECK([engine removeEntry:forged useTrash:NO] == 0 && Exists(H(@".outside/real.bin")), @"a link was followed");
    long long freed = [engine removeEntry:cache useTrash:NO];
    CHECK(freed == cache.bytes && freed > 0 && !Exists(H(@".hermes/cache")), @"the Safe cache was not removed (%lld)", freed);
    CHECK(Exists(H(@".outside/real.bin")) && Exists(H(@".hermes/state.db")), @"removing the cache touched something else");

    // Every name the Mac catalog shows exists in every language.
    NSMutableArray *keys = [NSMutableArray array];
    for (CCSpaceRule *rule in CCSpaceCatalog.rules) {
        [keys addObject:[NSString stringWithFormat:@"space.%@.name", rule.identifier]];
        [keys addObject:[NSString stringWithFormat:@"space.%@.desc", rule.identifier]];
        NSMutableArray *kinds = [[rule.parts valueForKey:@"kind"] mutableCopy];
        if (rule.listKind) [kinds addObject:rule.listKind];
        for (NSString *kind in kinds) [keys addObject:[NSString stringWithFormat:@"space.kind.%@.name", kind]];
    }
    [keys addObjectsFromArray:@[ @"nav.disk", @"disk.title", @"disk.map", @"disk.safe", @"disk.removeSafe", @"risk.Keep", @"space.caches.name",
                                 @"space.folder.desc", @"space.personal.desc", @"space.small.name", @"disk.mac.needsAccess" ]];
    for (NSInteger s = 0; s < CCSpaceSegmentCount; s++) [keys addObject:[@"disk.seg." stringByAppendingString:CCSpaceSegmentName(s)]];
    NSDictionary *enOverlay = MergedStrings(@[ folders.lastObject ], @"en");
    for (CCLanguage *language in CCLocalization.languages) {
        NSDictionary *merged = MergedStrings(folders, language.code), *overlay = MergedStrings(@[ folders.lastObject ], language.code);
        for (NSString *key in keys) CHECK(merged[key] != nil, @"%@ has no %@", language.code, key);
        // The macOS-only names are translated, not left to fall back to English.
        for (NSString *key in enOverlay)
            if ([key hasPrefix:@"space."] || [key hasPrefix:@"disk."]) CHECK(overlay[key] != nil, @"%@.json has no %@", language.code, key);
    }

    unsetenv("JUNKCLEANUP_HOME");
    [NSFileManager.defaultManager removeItemAtPath:home error:nil];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        const char *strings = getenv("JUNKCLEANUP_STRINGS");
        NSArray *folders = strings ? [[NSString stringWithUTF8String:strings] componentsSeparatedByString:@":"] : @[];
        CHECK(folders.count == 2, @"JUNKCLEANUP_STRINGS must name the shared and the macOS strings folders");

        TestFormatting();
        NSString *home = Scratch();
        setenv("JUNKCLEANUP_HOME", home.fileSystemRepresentation, 1);
        TestPathGuard(home);
        unsetenv("JUNKCLEANUP_HOME");
        if (folders.count == 2) {
            TestCatalogAndStrings(folders);
            TestLocalization(folders);
        }
        TestScanAndClean();
        TestNestedTargets();
        TestSettings();
        if (folders.count == 2) TestDiskMap(folders);
        [NSFileManager.defaultManager removeItemAtPath:home error:nil];

        printf("%d passed, %d failed\n", gPassed, gFailed);
        return gFailed ? 1 : 0;
    }
}
