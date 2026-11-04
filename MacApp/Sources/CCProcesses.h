// What runs on the Mac, for the checks the mac-janitor watcher makes: which Chrome copies are still in use, which VM
// holds Cowork's image, and which processes are stuck (orphaned shell loops, disk-wide searches, a bloated Hermes tab).
// Foundation only, so the tests can build it.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CCProcess : NSObject
@property (nonatomic) pid_t pid, ppid;
/// Seconds since it started.
@property (nonatomic) double age;
/// Current CPU use, percent of one core (ps's pcpu).
@property (nonatomic) double cpu;
/// CPU time over its whole life as a share of one core (0.5 = half a core on average).
@property (nonatomic) double cpuShare;
/// Resident memory in bytes.
@property (nonatomic) long long rss;
@property (nonatomic, copy) NSString *args;
/// The file name of the program ("zsh", "find").
@property (nonatomic, copy) NSString *command;
@end

typedef NS_ENUM(NSInteger, CCStuckKind) {
    /// A tab of the hidden Hermes Chrome that grew past 2.5 GB or spins while nobody uses the browser.
    CCStuckHermesTab,
    /// A Claude shell whose session ended, burning CPU on its own with nothing running under it.
    CCStuckOrphanLoop,
    /// A search over the whole disk started by Claude (find /, du /Volumes…), running for minutes.
    CCStuckDiskScan,
};

@interface CCStuckProcess : NSObject
@property (nonatomic) CCStuckKind kind;
@property (nonatomic) pid_t pid;
@property (nonatomic) long long rss;
@property (nonatomic) double minutes;
/// Percent of a core: now for a Hermes tab, on average for an orphaned loop.
@property (nonatomic) double cpu;
@property (nonatomic, copy) NSString *commandLine;
/// "hermesTab", "orphanLoop", "diskScan" — the suffix of the "stuck.*" strings.
@property (nonatomic, readonly) NSString *kindName;
@end

/// "1-02:03:04", "03:04" (ps etime) → seconds.
double CCParseElapsed(NSString *text);
/// "1-02:03:04.50", "3:04.50" (ps time) → seconds.
double CCParseCPUTime(NSString *text);

@interface CCProcesses : NSObject
/// Every process, from ps; nil when ps failed, timed out or gave a list without launchd (an empty list would make
/// every Chrome copy look abandoned).
+ (nullable NSArray<CCProcess *> *)snapshot;
/// ps -Awwo pid=,ppid=,etime=,time=,pcpu=,rss=,args= output → processes.
+ (NSArray<CCProcess *> *)parse:(NSString *)psOutput;
/// When each running Chrome started (its main process, any profile), seconds since 1970.
+ (NSArray<NSNumber *> *)chromeStarts:(NSArray<CCProcess *> *)processes now:(NSTimeInterval)now;
/// What is stuck; hermesIdleMinutes is how long nobody has used the Hermes browser.
+ (NSArray<CCStuckProcess *> *)stuckIn:(NSArray<CCProcess *> *)processes hermesIdleMinutes:(double)hermesIdleMinutes;
/// Minutes since the hb tool last ran (~/.cache/hb-last-use), a large number when it never did.
+ (double)hermesIdleMinutes;
/// Apple Virtualization VM processes that have the file or folder open (lsof on that one pid, never on all of them).
+ (NSArray<NSNumber *> *)virtualMachinesHolding:(NSString *)path in:(NSArray<CCProcess *> *)processes;
/// SIGTERM, and SIGKILL to what is still there a moment later.
+ (void)terminate:(NSArray<NSNumber *> *)pids;
/// Ends it only when that pid still runs the same command line: a pid freed since the check may belong to anything.
+ (BOOL)terminateIfUnchanged:(CCStuckProcess *)process;
/// The script that closes the Hermes browser properly, when it is installed.
+ (nullable NSString *)hermesStopScript;
/// Runs it; YES when the browser closed.
+ (BOOL)stopHermesBecause:(NSString *)reason;
@end

/// Where Chrome keeps the copies of itself it signs on start: …/X/com.google.Chrome.code_sign_clone.
NSString *_Nullable CCChromeCloneRoot(void);
/// The copies under root created more than 3 minutes away from the start of every running Chrome: left behind by a
/// Chrome that was killed or crashed.
NSArray<NSString *> *CCStaleChromeClones(NSString *root, NSArray<NSNumber *> *chromeStarts);

/// ~/Library/Application Support/Claude/vm_bundles/claudevm.bundle and the folder of Cowork's sessions.
NSString *CCCoworkBundle(void);
NSString *CCCoworkSessions(void);
/// Cowork is in use: it has scheduled tasks, or something in its sessions changed within `idle` seconds (the files the
/// Claude app refreshes by itself do not count). An unreadable task list counts as in use.
BOOL CCCoworkNeeded(NSString *sessions, NSTimeInterval idle, NSString *_Nullable *_Nullable why);

NS_ASSUME_NONNULL_END
