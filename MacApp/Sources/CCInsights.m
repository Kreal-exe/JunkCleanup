#import "CCInsights.h"
#import "CCCore.h"
#import "CCEngine.h"
#include <glob.h>
#include <sys/stat.h>

@implementation CCInsight
- (NSString *)titleKey { return [NSString stringWithFormat:@"insight.%@.title", self.identifier]; }
- (NSString *)detailKey { return [NSString stringWithFormat:@"insight.%@.detail", self.identifier]; }
@end

static const long long GB = 1024LL * 1024 * 1024;

static CCInsight *Make(NSString *identifier, NSString *symbol, long long bytes, CCInsightAction action, NSString *payload) {
    CCInsight *i = [CCInsight new];
    i.identifier = identifier;
    i.symbol = symbol;
    i.bytes = bytes;
    i.action = action;
    i.payload = payload;
    i.extra = @[];
    return i;
}

static long long FolderSize(NSString *folder, BOOL *denied) {
    CCTarget *t = [CCTarget new];
    t.identifier = @"insight";
    t.rootPatterns = @[ folder ];
    CCScanOptions *options = [CCScanOptions new];
    options.maxTopEntries = 0;
    CCScanResult *r = [[CCScanEngine new] scanTarget:t options:options cancel:nil onBytes:nil];
    if (denied) *denied = r.accessDenied;
    return r.totalBytes;
}

static long long GlobSize(const char *pattern) {
    glob_t g;
    long long total = 0;
    if (glob(pattern, 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) {
            struct stat st;
            if (lstat(g.gl_pathv[i], &st) == 0 && S_ISREG(st.st_mode)) total += st.st_size;
        }
    }
    globfree(&g);
    return total;
}

static NSString *Run(NSString *tool, NSArray<NSString *> *arguments) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return @"";
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

/// Apple Intelligence's on-device models, as MobileAsset records them: world-readable descriptors, read as plain property
/// lists, no private API. Several versions of one model can be on record; only the newest one counts.
static long long AppleIntelligenceBytes(NSString *folder) {
    NSArray<NSString *> *types = @[
        @"com.apple.MobileAsset.UAF.FM.GenerativeModels", @"com.apple.MobileAsset.UAF.FM.Visual", @"com.apple.MobileAsset.UAF.FM.CodeLM",
        @"com.apple.MobileAsset.UAF.Photos.MagicCleanup", @"com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive",
    ];
    NSString *prefix = @"AutoAssetDescriptors_Entry_";
    // "<type>_<model>_<version>_0.state": the newest version of each model and its size.
    NSMutableDictionary<NSString *, NSArray *> *newest = [NSMutableDictionary dictionary];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name hasPrefix:prefix] || ![name hasSuffix:@"_0.state"]) continue;
        NSString *entry = [name substringWithRange:NSMakeRange(prefix.length, name.length - prefix.length - @"_0.state".length)];
        BOOL wanted = NO;
        for (NSString *type in types) wanted |= [entry hasPrefix:[type stringByAppendingString:@"_"]];
        NSRange cut = [entry rangeOfString:@"_" options:NSBackwardsSearch];
        if (!wanted || cut.location == NSNotFound) continue;
        NSString *model = [entry substringToIndex:cut.location], *version = [entry substringFromIndex:cut.location + 1];

        NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:name]];
        NSDictionary *state = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil] : nil;
        if (![state isKindOfClass:NSDictionary.class]) continue;
        NSData *blob = state[@"SUCorePersistedStatePolicySecureCodedObjectsFields"][@"assetDescriptor"];
        NSDictionary *archive = [blob isKindOfClass:NSData.class]
            ? [NSPropertyListSerialization propertyListWithData:blob options:0 format:NULL error:nil] : nil;
        NSArray *objects = [archive isKindOfClass:NSDictionary.class] ? archive[@"$objects"] : nil;
        long long bytes = 0;
        for (id object in [objects isKindOfClass:NSArray.class] ? objects : @[])
            if ([object isKindOfClass:NSDictionary.class] && [object[@"downloadedFilesystemBytes"] isKindOfClass:NSNumber.class])
                bytes = [object[@"downloadedFilesystemBytes"] longLongValue];
        NSArray *known = newest[model];
        if (!known || [version compare:known[0] options:NSNumericSearch] == NSOrderedDescending) newest[model] = @[ version, @(bytes) ];
    }
    long long total = 0;
    for (NSArray *v in newest.allValues) total += [v[1] longLongValue];
    return total;
}

@implementation CCInsights

+ (long long)appleIntelligenceBytesInFolder:(NSString *)folder { return AppleIntelligenceBytes(folder); }

+ (NSArray<CCInsight *> *)scanWithTrashTargetEnabled:(BOOL)trashTargetEnabled {
    NSMutableArray<CCInsight *> *found = [NSMutableArray array];
    NSString *home = CCHomeDirectory();

    // Purgeable space: what macOS reports as available for important use beyond the plain free space —
    // mostly local Time Machine snapshots and iCloud files that can be evicted.
    NSURL *volume = [NSURL fileURLWithPath:home];
    NSDictionary *values = [volume resourceValuesForKeys:@[ NSURLVolumeAvailableCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey ]
                                                   error:nil];
    long long available = [values[NSURLVolumeAvailableCapacityKey] longLongValue];
    long long important = [values[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue];
    NSString *snapshots = Run(@"/usr/bin/tmutil", @[ @"listlocalsnapshots", @"/" ]);
    NSUInteger snapshotCount = 0;
    for (NSString *line in [snapshots componentsSeparatedByString:@"\n"])
        if ([line containsString:@"com.apple.TimeMachine"]) snapshotCount++;
    if (important - available >= GB) {
        CCInsight *i = snapshotCount
            ? Make(@"snapshots", @"clock.arrow.circlepath", important - available, CCInsightActionCopyCommand,
                   @"tmutil thinlocalsnapshots / 999999999999 4")
            : Make(@"purgeable", @"icloud", important - available, CCInsightActionOpenURL,
                   @"x-apple.systempreferences:com.apple.settings.Storage");
        i.extra = @[ CCFormatCount((long long)snapshotCount) ];
        [found addObject:i];
    }

    // The sleep image is the macOS hiberfil.sys; swap files are its page file.
    // Since Catalina they live on the VM volume; older systems kept them in /private/var/vm.
    struct stat st;
    long long sleep = 0;
    for (NSString *path in @[ @"/System/Volumes/VM/sleepimage", @"/private/var/vm/sleepimage" ])
        if (lstat(path.fileSystemRepresentation, &st) == 0) sleep = MAX(sleep, (long long)st.st_size);
    if (sleep >= GB / 2)
        [found addObject:Make(@"sleepimage", @"moon.zzz", sleep, CCInsightActionCopyCommand, @"sudo pmset -a hibernatemode 0")];

    long long swap = MAX(GlobSize("/System/Volumes/VM/swapfile*"), GlobSize("/private/var/vm/swapfile*"));
    if (swap >= GB)
        [found addObject:Make(@"swap", @"memorychip", swap, CCInsightActionOpenURL,
                              @"file:///System/Applications/Utilities/Activity%20Monitor.app")];

    NSString *devices = [home stringByAppendingPathComponent:@"Library/Developer/CoreSimulator/Devices"];
    long long simulators = FolderSize(devices, NULL);
    if (simulators >= GB)
        [found addObject:Make(@"simulators", @"ipad.and.iphone", simulators, CCInsightActionCopyCommand, @"xcrun simctl delete unavailable")];

    // macOS keeps the models while Apple Intelligence is on; turning it off in Settings is the one public way to have
    // macOS remove them (on macOS 15 and 26 there is no other).
    long long intelligence = AppleIntelligenceBytes(@"/System/Library/AssetsV2/persisted/AutoAssetDescriptors");
    if (intelligence >= GB / 2)
        [found addObject:Make(@"appleintelligence", @"sparkles", intelligence, CCInsightActionOpenURL,
                              @"x-apple.systempreferences:com.apple.Siri-Settings.extension")];

    if (!trashTargetEnabled) {
        BOOL denied = NO;
        long long trash = FolderSize([home stringByAppendingPathComponent:@".Trash"], &denied);
        if (!denied && trash > 0)
            [found addObject:Make(@"trash", @"trash", trash, CCInsightActionNone, nil)];
    }

    [found sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
    return found;
}

@end
