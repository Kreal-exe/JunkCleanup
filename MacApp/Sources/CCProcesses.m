#import "CCProcesses.h"
#import "CCCore.h"
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

/// A copy created this close to a running Chrome's start belongs to it.
static const NSTimeInterval CloneKeep = 180;
static const double HermesTabBytes = 2.5e9, HermesIdleMinutes = 15;
static const double OrphanMinAge = 600, OrphanMinShare = 0.2, ScanMinAge = 300;

@implementation CCProcess
@end

@implementation CCStuckProcess
- (NSString *)kindName {
    switch (self.kind) {
        case CCStuckHermesTab: return @"hermesTab";
        case CCStuckOrphanLoop: return @"orphanLoop";
        case CCStuckDiskScan: return @"diskScan";
    }
    return @"diskScan";
}
@end

/// "[dd-]a:b:c" → seconds; the last field may have a fraction.
static double ParseClock(NSString *text) {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    double days = 0;
    NSRange dash = [t rangeOfString:@"-"];
    if (dash.location != NSNotFound) {
        days = [t substringToIndex:dash.location].doubleValue;
        t = [t substringFromIndex:dash.location + 1];
    }
    NSArray<NSString *> *parts = [t componentsSeparatedByString:@":"];
    double seconds = 0;
    for (NSString *p in parts) seconds = seconds * 60 + p.doubleValue;
    return days * 86400 + seconds;
}

double CCParseElapsed(NSString *text) { return ParseClock(text); }
double CCParseCPUTime(NSString *text) { return ParseClock(text); }

/// Runs a tool and returns what it printed, killing it when it takes longer than `timeout`.
static NSString *Run(NSString *tool, NSArray<NSString *> *arguments, NSTimeInterval timeout) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return @"";
    __block NSData *data = nil;
    dispatch_semaphore_t read = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        data = [pipe.fileHandleForReading readDataToEndOfFile];
        dispatch_semaphore_signal(read);
    });
    if (dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        [task terminate];
        dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    [task waitUntilExit];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"" : @"";
}

static NSArray<CCProcess *> *ChildrenOf(NSArray<CCProcess *> *processes, pid_t pid) {
    NSMutableArray *kids = [NSMutableArray array];
    for (CCProcess *p in processes)
        if (p.ppid == pid) [kids addObject:p];
    return kids;
}

static BOOL StartedByClaude(NSDictionary<NSNumber *, CCProcess *> *byPid, pid_t pid) {
    for (int depth = 0; depth < 30; depth++) {
        CCProcess *p = byPid[@(pid)];
        if (!p) return NO;
        NSString *a = p.args;
        if ([a containsString:@"/.claude/shell-snapshots/"] || [a containsString:@"claude-code/"] || [a hasSuffix:@"/claude"]
            || [a containsString:@"/claude.app/"])
            return YES;
        pid = p.ppid;
    }
    return NO;
}

/// The whole disk, all mounted volumes or every user's home: a search there runs for hours over network shares.
static BOOL IsDiskWideRoot(NSString *arg) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^(/|/Volumes/?|/Volumes/[^/]+/?|/System/Volumes/Data/?|/Users/?)$"
                                                       options:0 error:nil];
    });
    return [re numberOfMatchesInString:arg options:0 range:NSMakeRange(0, arg.length)] > 0;
}

@implementation CCProcesses

+ (NSArray<CCProcess *> *)snapshot {
    return [self parse:Run(@"/bin/ps", @[ @"-Awwo", @"pid=,ppid=,etime=,time=,pcpu=,rss=,args=" ], 15)];
}

+ (NSArray<CCProcess *> *)parse:(NSString *)psOutput {
    NSMutableArray<CCProcess *> *list = [NSMutableArray array];
    NSCharacterSet *space = NSCharacterSet.whitespaceCharacterSet;
    for (NSString *line in [psOutput componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSScanner *s = [NSScanner scannerWithString:line];
        s.charactersToBeSkipped = space;
        int pid, ppid;
        NSString *etime, *cputime;
        double cpu;
        long long rss;
        if (![s scanInt:&pid] || ![s scanInt:&ppid] || ![s scanUpToCharactersFromSet:space intoString:&etime]
            || ![s scanUpToCharactersFromSet:space intoString:&cputime] || ![s scanDouble:&cpu] || ![s scanLongLong:&rss])
            continue;
        NSString *args = [[line substringFromIndex:s.scanLocation] stringByTrimmingCharactersInSet:space];
        if (args.length == 0) continue;
        CCProcess *p = [CCProcess new];
        p.pid = pid;
        p.ppid = ppid;
        p.age = CCParseElapsed(etime);
        p.cpu = cpu;
        p.cpuShare = CCParseCPUTime(cputime) / MAX(p.age, 1);
        p.rss = rss * 1024;
        p.args = args;
        NSString *program = [args componentsSeparatedByString:@" "].firstObject;
        p.command = program.lastPathComponent;
        [list addObject:p];
    }
    return list;
}

+ (NSArray<NSNumber *> *)chromeStarts:(NSArray<CCProcess *> *)processes now:(NSTimeInterval)now {
    NSMutableArray *starts = [NSMutableArray array];
    for (CCProcess *p in processes) {
        NSString *program = [p.args componentsSeparatedByString:@" --"].firstObject;
        if ([program hasSuffix:@"/Contents/MacOS/Google Chrome"]) [starts addObject:@(now - p.age)];
    }
    return starts;
}

+ (NSArray<CCStuckProcess *> *)stuckIn:(NSArray<CCProcess *> *)processes hermesIdleMinutes:(double)hermesIdleMinutes {
    NSMutableArray<CCStuckProcess *> *stuck = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, CCProcess *> *byPid = [NSMutableDictionary dictionary];
    for (CCProcess *p in processes) byPid[@(p.pid)] = p;
    CCStuckProcess * (^add)(CCStuckKind, CCProcess *) = ^CCStuckProcess *(CCStuckKind kind, CCProcess *p) {
        CCStuckProcess *s = [CCStuckProcess new];
        s.kind = kind;
        s.pid = p.pid;
        s.rss = p.rss;
        s.minutes = p.age / 60;
        s.commandLine = p.args;
        [stuck addObject:s];
        return s;
    };

    // 1. The hidden Hermes Chrome: one of its tabs leaks memory or spins while nobody uses the browser.
    CCProcess *hermes = nil;
    for (CCProcess *p in processes)
        if ([p.args containsString:@"Hermes_Profile"] && [p.args containsString:@"remote-debugging-port"] && ![p.args containsString:@"Helper"]) {
            hermes = p;
            break;
        }
    if (hermes)
        for (CCProcess *r in ChildrenOf(processes, hermes.pid)) {
            if (![r.args containsString:@"--type=renderer"] || [r.args containsString:@"--extension-process"]) continue;
            BOOL heavy = r.rss > HermesTabBytes;
            BOOL busy = r.cpu > 100 && hermesIdleMinutes > HermesIdleMinutes;
            if (heavy || busy) add(CCStuckHermesTab, r).cpu = r.cpu;
        }

    // 2. A Claude shell left behind by its session (its parent is launchd now) that burns CPU by itself.
    for (CCProcess *p in processes) {
        BOOL shell = [p.command isEqualToString:@"zsh"] || [p.command isEqualToString:@"bash"] || [p.command isEqualToString:@"sh"];
        if (p.ppid == 1 && shell && [p.args containsString:@"/.claude/shell-snapshots/"] && p.age > OrphanMinAge
            && p.cpuShare > OrphanMinShare && ChildrenOf(processes, p.pid).count == 0)
            add(CCStuckOrphanLoop, p).cpu = p.cpuShare * 100;
    }

    // 3. A search of the whole disk that Claude started and that has been running for minutes.
    NSSet *tools = [NSSet setWithArray:@[ @"bfs", @"find", @"gfind", @"fd", @"rg", @"mdfind", @"du", @"locate" ]];
    for (CCProcess *p in processes) {
        if (![tools containsObject:p.command] || p.age <= ScanMinAge || !StartedByClaude(byPid, p.pid)) continue;
        NSArray *argv = [p.args componentsSeparatedByString:@" "];
        for (NSUInteger i = 1; i < argv.count; i++)
            if (IsDiskWideRoot(argv[i])) {
                add(CCStuckDiskScan, p).cpu = p.cpu;
                break;
            }
    }
    return stuck;
}

+ (double)hermesIdleMinutes {
    struct stat st;
    NSString *stamp = [CCHomeDirectory() stringByAppendingPathComponent:@".cache/hb-last-use"];
    if (lstat(stamp.fileSystemRepresentation, &st) != 0) return 1e6;
    return (NSDate.date.timeIntervalSince1970 - st.st_mtimespec.tv_sec) / 60;
}

+ (NSArray<NSNumber *> *)virtualMachinesHolding:(NSString *)path in:(NSArray<CCProcess *> *)processes {
    NSMutableArray *pids = [NSMutableArray array];
    for (CCProcess *p in processes) {
        if (![p.args containsString:@"com.apple.Virtualization.VirtualMachine"]) continue;
        // One pid at a time, -b and -w: lsof over everything hangs on a network share.
        NSString *open = Run(@"/usr/sbin/lsof", @[ @"-b", @"-n", @"-w", @"-p", [NSString stringWithFormat:@"%d", p.pid] ], 15);
        if ([open containsString:path]) [pids addObject:@(p.pid)];
    }
    return pids;
}

+ (void)terminate:(NSArray<NSNumber *> *)pids {
    if (pids.count == 0) return;
    for (NSNumber *pid in pids) kill(pid.intValue, SIGTERM);
    for (int i = 0; i < 15; i++) {
        BOOL alive = NO;
        for (NSNumber *pid in pids) alive |= kill(pid.intValue, 0) == 0;
        if (!alive) return;
        usleep(100000);
    }
    for (NSNumber *pid in pids) kill(pid.intValue, SIGKILL);
}

+ (NSString *)hermesStopScript {
    NSString *script = [CCHomeDirectory() stringByAppendingPathComponent:@".claude/skills/hermes-browser/scripts/hb-stop"];
    return [NSFileManager.defaultManager isReadableFileAtPath:script] ? script : nil;
}

+ (BOOL)stopHermesBecause:(NSString *)reason {
    NSString *script = [self hermesStopScript];
    if (!script) return NO;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[ script, reason ];
    task.standardOutput = task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return NO;
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

@end

// ───────────── Chrome's signing copies ─────────────

NSString *CCChromeCloneRoot(void) {
    char buffer[PATH_MAX];
    size_t length = confstr(_CS_DARWIN_USER_TEMP_DIR, buffer, sizeof buffer);
    if (length == 0 || length > sizeof buffer) return nil;
    NSString *temp = [NSString stringWithUTF8String:buffer].stringByStandardizingPath;
    return [[temp.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"X"]
            stringByAppendingPathComponent:@"com.google.Chrome.code_sign_clone"];
}

NSArray<NSString *> *CCStaleChromeClones(NSString *root, NSArray<NSNumber *> *chromeStarts) {
    NSMutableArray *stale = [NSMutableArray array];
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        if (![name hasPrefix:@"code_sign_clone."]) continue;
        NSString *path = [root stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) continue;
        double born = st.st_birthtimespec.tv_sec + st.st_birthtimespec.tv_nsec / 1e9;
        BOOL inUse = NO;
        for (NSNumber *start in chromeStarts) inUse |= fabs(born - start.doubleValue) <= CloneKeep;
        if (!inUse) [stale addObject:path];
    }
    return stale;
}

// ───────────── Cowork's virtual machine ─────────────

NSString *CCCoworkBundle(void) {
    return [CCHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Claude/vm_bundles/claudevm.bundle"];
}

NSString *CCCoworkSessions(void) {
    return [CCHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Claude/local-agent-mode-sessions"];
}

BOOL CCCoworkNeeded(NSString *sessions, NSTimeInterval idle, NSString **why) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSTimeInterval limit = NSDate.date.timeIntervalSince1970 - idle;
    BOOL (^isDir)(NSString *) = ^BOOL(NSString *p) {
        struct stat st;
        return lstat(p.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode);
    };
    for (NSString *account in [fm contentsOfDirectoryAtPath:sessions error:nil] ?: @[]) {
        // A copy of the skills the app refreshes by itself.
        if ([account isEqualToString:@"skills-plugin"]) continue;
        NSString *accountPath = [sessions stringByAppendingPathComponent:account];
        if (!isDir(accountPath)) continue;
        for (NSString *org in [fm contentsOfDirectoryAtPath:accountPath error:nil] ?: @[]) {
            NSString *orgPath = [accountPath stringByAppendingPathComponent:org];
            if (!isDir(orgPath)) continue;
            NSString *tasksFile = [orgPath stringByAppendingPathComponent:@"scheduled-tasks.json"];
            if ([fm fileExistsAtPath:tasksFile]) {
                NSData *data = [NSData dataWithContentsOfFile:tasksFile];
                id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if (![json isKindOfClass:NSDictionary.class]) {
                    if (why) *why = @"unreadable";
                    return YES;
                }
                id tasks = json[@"scheduledTasks"];
                if (([tasks isKindOfClass:NSArray.class] || [tasks isKindOfClass:NSDictionary.class]) && [tasks count] > 0) {
                    if (why) *why = @"scheduled";
                    return YES;
                }
            }
            for (NSString *item in [fm contentsOfDirectoryAtPath:orgPath error:nil] ?: @[]) {
                // rpm/manifest.json and the task list are rewritten by the app itself.
                if ([item isEqualToString:@"rpm"] || [item isEqualToString:@"scheduled-tasks.json"]) continue;
                NSString *path = [orgPath stringByAppendingPathComponent:item];
                struct stat st;
                if ((lstat(path.fileSystemRepresentation, &st) == 0 && st.st_mtimespec.tv_sec > limit) || CCTouchedWithin(path, idle)) {
                    if (why) *why = @"recent";
                    return YES;
                }
            }
        }
    }
    if (why) *why = @"idle";
    return NO;
}
