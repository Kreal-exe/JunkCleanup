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

@implementation CCInsights

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
