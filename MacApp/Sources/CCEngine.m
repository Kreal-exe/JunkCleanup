#import "CCEngine.h"
#include <errno.h>
#include <fnmatch.h>
#include <fts.h>
#include <sys/stat.h>
#include <unistd.h>

@implementation CCCancelToken {
    volatile int32_t _cancelled;
}
- (BOOL)isCancelled { return __atomic_load_n(&_cancelled, __ATOMIC_RELAXED) != 0; }
- (void)cancel { __atomic_store_n(&_cancelled, 1, __ATOMIC_RELAXED); }
@end

@implementation CCEntry
@end

@implementation CCScanOptions
- (instancetype)init {
    if ((self = [super init])) {
        _maxTopEntries = 100;
        _excludedRoots = [NSSet set];
    }
    return self;
}
@end

@interface CCScanResult ()
@property (nonatomic, copy) NSSet<NSString *> *skippedRoots;
@end

@implementation CCScanResult
- (instancetype)init {
    if ((self = [super init])) {
        _files = [NSMutableArray array];
        _sizes = [NSMutableData data];
        _roots = @[];
        _topEntries = @[];
        _skippedRoots = [NSSet set];
    }
    return self;
}
- (long long)sizeAtIndex:(NSUInteger)index { return ((const long long *)self.sizes.bytes)[index]; }
@end

@implementation CCScanEvent
@end

static NSString *PathFromEntry(const char *path, size_t length) {
    NSString *s = [[NSString alloc] initWithBytes:path length:length encoding:NSUTF8StringEncoding];
    return s ?: [NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:length];
}

static BOOL MatchesAny(NSArray<NSString *> *patterns, const char *name) {
    for (NSString *pattern in patterns)
        if (fnmatch(pattern.fileSystemRepresentation, name, FNM_CASEFOLD) == 0) return YES;
    return NO;
}

@implementation CCScanEngine

- (NSArray<CCScanResult *> *)scanTargets:(NSArray<CCTarget *> *)targets
                                 options:(CCScanOptions *)options
                                  cancel:(CCCancelToken *)cancel
                                progress:(void (^)(CCScanEvent *))progress {
    NSUInteger count = targets.count;
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [results addObject:NSNull.null];

    __block long long bytesFound = 0;
    __block NSInteger completed = 0;
    __block CFAbsoluteTime lastReport = 0;
    NSObject *lock = [NSObject new];

    void (^report)(CCScanPhase, NSString *, long long, CCScanResult *) = ^(CCScanPhase phase, NSString *targetId, long long targetBytes, CCScanResult *result) {
        if (!progress) return;
        CCScanEvent *event = [CCScanEvent new];
        event.phase = phase;
        event.targetId = targetId;
        event.result = result;
        event.targetBytes = targetBytes;
        event.total = (NSInteger)count;
        @synchronized (lock) {
            event.completed = completed;
            event.bytesFound = bytesFound;
        }
        progress(event);
    };

    dispatch_apply(count, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        CCTarget *target = targets[i];
        if (cancel.isCancelled) return;
        report(CCScanPhaseStarted, target.identifier, 0, nil);

        __block long long targetBytes = 0; // one worker per target
        CCScanResult *result = [self scanTarget:target options:options cancel:cancel onBytes:^(long long delta) {
            BOOL send = NO;
            targetBytes += delta;
            @synchronized (lock) {
                bytesFound += delta;
                // Live byte updates are throttled to ~30 per second across all workers.
                CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                if (now - lastReport >= 0.033) {
                    lastReport = now;
                    send = YES;
                }
            }
            if (send) report(CCScanPhaseProgress, target.identifier, targetBytes, nil);
        }];

        @synchronized (lock) {
            results[i] = result;
            completed++;
        }
        report(CCScanPhaseCompleted, target.identifier, result.totalBytes, result);
    });

    NSMutableArray<CCScanResult *> *finished = [NSMutableArray array];
    for (id r in results)
        if (r != NSNull.null) [finished addObject:r];
    return finished;
}

- (CCScanResult *)scanTarget:(CCTarget *)target
                     options:(CCScanOptions *)options
                      cancel:(CCCancelToken *)cancel
                     onBytes:(void (^)(long long))onBytes {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    CCScanResult *result = [CCScanResult new];
    result.target = target;
    result.roots = [target resolveRoots];

    time_t cutoff = 0;
    if (options.skipNewerThanHours > 0 && target.respectsAgeFilter)
        cutoff = time(NULL) - (time_t)(options.skipNewerThanHours * 3600);

    NSMutableSet<NSString *> *skipped = [options.excludedRoots mutableCopy] ?: [NSMutableSet set];
    for (NSString *root in result.roots) [skipped removeObject:root];
    result.skippedRoots = skipped;

    NSMutableDictionary<NSString *, CCEntry *> *groups = [NSMutableDictionary dictionary];
    long long pending = 0;
    long long totalBytes = 0;
    NSInteger fileCount = 0;

    for (NSString *root in result.roots) {
        if (cancel.isCancelled) break;

        char *paths[] = { (char *)root.fileSystemRepresentation, NULL };
        FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
        if (!fts) {
            result.error = [NSString stringWithUTF8String:strerror(errno)];
            continue;
        }

        CCEntry *group = nil;
        FTSENT *e;
        while ((e = fts_read(fts))) {
            if (cancel.isCancelled) break;
            switch (e->fts_info) {
                case FTS_D: {
                    if (e->fts_level == 0) break;
                    if (e->fts_level == 1) {
                        if (target.excludedNames && MatchesAny(target.excludedNames, e->fts_name)) {
                            fts_set(fts, e, FTS_SKIP);
                            group = nil;
                            break;
                        }
                        NSString *path = PathFromEntry(e->fts_path, e->fts_pathlen);
                        group = groups[path];
                        if (!group) {
                            group = [CCEntry new];
                            group.path = path;
                            group.name = PathFromEntry(e->fts_name, e->fts_namelen);
                            group.isDirectory = YES;
                            group.complete = YES;
                            groups[path] = group;
                        }
                        if (!target.recursive) {
                            fts_set(fts, e, FTS_SKIP);
                            break;
                        }
                    }
                    if (skipped.count && [skipped containsObject:PathFromEntry(e->fts_path, e->fts_pathlen)]) {
                        fts_set(fts, e, FTS_SKIP);
                        group.complete = NO;
                    }
                    break;
                }
                case FTS_DNR:
                case FTS_ERR:
                case FTS_NS:
                    if (e->fts_level == 0) {
                        if (e->fts_errno == EACCES || e->fts_errno == EPERM) result.accessDenied = YES;
                        else result.error = [NSString stringWithUTF8String:strerror(e->fts_errno)];
                    } else {
                        group.complete = NO;
                    }
                    break;
                case FTS_DC:
                    group.complete = NO;
                    break;
                case FTS_F: {
                    if (e->fts_level == 1 && target.excludedNames && MatchesAny(target.excludedNames, e->fts_name)) break;
                    if (target.filePatterns && !MatchesAny(target.filePatterns, e->fts_name)) {
                        group.complete = NO;
                        break;
                    }
                    if (cutoff && e->fts_statp->st_mtime > cutoff) {
                        group.complete = NO;
                        break;
                    }

                    long long length = e->fts_statp->st_size;
                    NSString *path = PathFromEntry(e->fts_path, e->fts_pathlen);
                    [result.files addObject:path];
                    [result.sizes appendBytes:&length length:sizeof length];
                    totalBytes += length;
                    fileCount++;

                    CCEntry *owner = group;
                    if (e->fts_level == 1) {
                        owner = [CCEntry new];
                        owner.path = path;
                        owner.name = PathFromEntry(e->fts_name, e->fts_namelen);
                        owner.complete = YES;
                        groups[path] = owner;
                    }
                    owner.bytes += length;
                    owner.files++;

                    pending += length;
                    if (pending >= 4 * 1024 * 1024 && onBytes) {
                        onBytes(pending);
                        pending = 0;
                    }
                    break;
                }
                default:
                    // symlinks, sockets and the like are neither counted nor followed
                    break;
            }
        }
        fts_close(fts);
    }

    if (pending > 0 && onBytes) onBytes(pending);

    result.totalBytes = totalBytes;
    result.fileCount = fileCount;
    NSArray *sorted = [[groups.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"files > 0"]]
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
    NSInteger keep = MIN((NSInteger)sorted.count, MAX(options.maxTopEntries, 0));
    result.topEntries = [sorted subarrayWithRange:NSMakeRange(0, (NSUInteger)keep)];
    result.elapsed = CFAbsoluteTimeGetCurrent() - start;
    return result;
}

@end

// ───────────── cleaning ─────────────

@implementation CCCleanOptions
- (instancetype)init {
    if ((self = [super init])) _useTrash = YES;
    return self;
}
@end

@implementation CCTargetCleanResult
@end

@implementation CCCleanEvent
@end

@implementation CCCleanReport
- (instancetype)init {
    if ((self = [super init])) _targets = [NSMutableDictionary dictionary];
    return self;
}
@end

/// Checks that the directory a file sits in really is underneath a root, with symlinks resolved, so a directory
/// swapped for a link after the scan can never redirect a deletion. Results are cached per directory.
@interface CCParentCheck : NSObject
- (instancetype)initWithRoots:(NSArray<NSString *> *)roots;
- (BOOL)allows:(NSString *)file;
@end

@implementation CCParentCheck {
    NSArray<NSString *> *_roots;
    NSString *_lastDir;
    BOOL _lastAnswer;
}

- (instancetype)initWithRoots:(NSArray<NSString *> *)roots {
    if ((self = [super init])) {
        NSMutableArray *normalized = [NSMutableArray array];
        for (NSString *r in roots) [normalized addObject:[CCPathGuard normalize:r]];
        _roots = normalized;
    }
    return self;
}

- (BOOL)allows:(NSString *)file {
    NSString *dir = file.stringByDeletingLastPathComponent;
    if (_lastDir && [dir isEqualToString:_lastDir]) return _lastAnswer;
    _lastDir = dir;

    char resolved[PATH_MAX];
    if (!realpath(dir.fileSystemRepresentation, resolved)) return (_lastAnswer = NO);
    NSString *real = [NSString stringWithUTF8String:resolved];
    _lastAnswer = NO;
    for (NSString *root in _roots) {
        if ([real isEqualToString:root] || [real hasPrefix:[root stringByAppendingString:@"/"]]) {
            _lastAnswer = YES;
            break;
        }
    }
    return _lastAnswer;
}

@end

static BOOL RemoveFile(NSString *path) {
    const char *p = path.fileSystemRepresentation;
    if (unlink(p) == 0 || errno == ENOENT) return YES;
    if (errno == EPERM || errno == EACCES) {
        // Locked ("uchg") files are unlocked first; anything still refusing is left alone.
        if (chflags(p, 0) == 0 && unlink(p) == 0) return YES;
    }
    return NO;
}

static BOOL MoveToTrash(NSString *path) {
    NSError *error;
    if ([NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:nil error:&error]) return YES;
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) != 0 && errno == ENOENT;
}

/// Removes empty directories underneath dir (deepest first), then dir itself when it became empty.
static void PruneEmpty(NSString *dir, NSSet<NSString *> *keep, CCCancelToken *cancel) {
    char *paths[] = { (char *)dir.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (cancel.isCancelled) break;
        if (e->fts_info == FTS_D && keep.count && [keep containsObject:PathFromEntry(e->fts_path, e->fts_pathlen)]) {
            fts_set(fts, e, FTS_SKIP);
        } else if (e->fts_info == FTS_DP) {
            rmdir(e->fts_path); // fails harmlessly unless empty
        }
    }
    fts_close(fts);
}

@implementation CCCleanEngine

- (CCCleanReport *)clean:(NSArray<CCScanResult *> *)scans
                 options:(CCCleanOptions *)options
                  cancel:(CCCancelToken *)cancel
                progress:(void (^)(CCCleanEvent *))progress {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    CCCleanReport *report = [CCCleanReport new];
    NSUInteger count = scans.count;
    long long *liveFreed = calloc(MAX(count, 1), sizeof(long long));
    NSInteger *liveDeleted = calloc(MAX(count, 1), sizeof(NSInteger));
    NSInteger *liveFailed = calloc(MAX(count, 1), sizeof(NSInteger));
    __block NSInteger done = 0;
    NSObject *lock = [NSObject new];

    void (^publish)(NSString *, CCTargetCleanResult *) = ^(NSString *targetId, CCTargetCleanResult *result) {
        if (!progress) return;
        CCCleanEvent *event = [CCCleanEvent new];
        event.targetId = targetId;
        event.targetDone = result != nil;
        event.targetResult = result;
        event.targetsTotal = (NSInteger)count;
        @synchronized (lock) {
            for (NSUInteger k = 0; k < count; k++) {
                event.bytesFreed += liveFreed[k];
                event.filesDeleted += liveDeleted[k];
                event.failed += liveFailed[k];
            }
            event.targetsDone = done;
        }
        progress(event);
    };

    // A few targets at once; each one spreads its own files over the cores.
    dispatch_semaphore_t slots = dispatch_semaphore_create(4);
    dispatch_apply(count, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        if (cancel.isCancelled) return;
        dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
        CCScanResult *scan = scans[i];
        CCTargetCleanResult *result = [self cleanTarget:scan options:options cancel:cancel
                                             onProgress:^(long long freed, NSInteger deleted, NSInteger failed) {
            @synchronized (lock) {
                liveFreed[i] = freed;
                liveDeleted[i] = deleted;
                liveFailed[i] = failed;
            }
            publish(scan.target.identifier, nil);
        }];
        dispatch_semaphore_signal(slots);
        @synchronized (lock) {
            liveFreed[i] = result.bytesFreed;
            liveDeleted[i] = result.filesDeleted;
            liveFailed[i] = result.failed;
            done++;
            report.bytesFreed += result.bytesFreed;
            report.filesDeleted += result.filesDeleted;
            report.failed += result.failed;
            report.targets[scan.target.identifier] = result;
        }
        publish(scan.target.identifier, result);
    });

    free(liveFreed);
    free(liveDeleted);
    free(liveFailed);
    report.cancelled = cancel.isCancelled;
    report.elapsed = CFAbsoluteTimeGetCurrent() - start;
    return report;
}

- (CCTargetCleanResult *)cleanTarget:(CCScanResult *)scan
                             options:(CCCleanOptions *)options
                              cancel:(CCCancelToken *)cancel
                          onProgress:(void (^)(long long, NSInteger, NSInteger))onProgress {
    CCTargetCleanResult *result = [CCTargetCleanResult new];
    result.targetId = scan.target.identifier;
    NSArray<NSString *> *roots = scan.roots;
    BOOL trash = options.useTrash && !scan.target.alwaysPermanent;

    __block long long freed = 0;
    __block NSInteger deleted = 0, failed = 0;
    __block CFAbsoluteTime lastReport = 0;
    NSObject *lock = [NSObject new];
    void (^report)(BOOL) = ^(BOOL force) {
        long long f;
        NSInteger d, x;
        @synchronized (lock) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (!force && now - lastReport < 0.04) return;
            lastReport = now;
            f = freed;
            d = deleted;
            x = failed;
        }
        if (onProgress) onProgress(f, d, x);
    };
    CCTargetCleanResult * (^finish)(void) = ^CCTargetCleanResult * {
        result.bytesFreed = freed;
        result.filesDeleted = deleted;
        result.failed = failed;
        result.bytesRemaining = MAX(0, scan.totalBytes - freed);
        result.filesRemaining = MAX(0, scan.fileCount - deleted);
        report(YES);
        return result;
    };

    if (options.dryRun) {
        for (NSUInteger i = 0; i < scan.files.count; i++) {
            if ([CCPathGuard isPath:scan.files[i] insideRoots:roots]) {
                deleted++;
                freed += [scan sizeAtIndex:i];
            } else {
                failed++;
            }
        }
        return finish();
    }

    NSMutableSet<NSString *> *handled = [NSMutableSet set];
    NSMutableSet<NSString *> *touched = [NSMutableSet set];

    // Moving 100 000 cache files to the Trash one by one takes minutes, so a first-level folder whose every file
    // was scanned goes to the Trash as one item (it is still underneath the scanned root).
    if (trash) {
        CCParentCheck *parents = [[CCParentCheck alloc] initWithRoots:roots];
        for (CCEntry *entry in scan.topEntries) {
            if (cancel.isCancelled) break;
            if (!entry.isDirectory || !entry.complete || entry.files == 0) continue;
            if (![CCPathGuard isPath:entry.path insideRoots:roots] || ![parents allows:entry.path]) continue;
            struct stat st;
            if (lstat(entry.path.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) continue;
            if (MoveToTrash(entry.path)) {
                [handled addObject:entry.path];
                @synchronized (lock) {
                    deleted += entry.files;
                    freed += entry.bytes;
                }
                report(NO);
            }
        }
    }

    // The remaining files in parallel chunks; each chunk keeps its own resolved-parent cache.
    NSUInteger total = scan.files.count, chunk = 256;
    NSUInteger chunks = (total + chunk - 1) / chunk;
    dispatch_apply(chunks, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t c) {
        CCParentCheck *parents = [[CCParentCheck alloc] initWithRoots:roots];
        NSMutableSet<NSString *> *owners = [NSMutableSet set];
        NSUInteger end = MIN(total, (c + 1) * chunk);
        for (NSUInteger i = c * chunk; i < end; i++) {
            if (cancel.isCancelled) break;
            NSString *file = scan.files[i];
            long long length = [scan sizeAtIndex:i];

            NSString *owner = nil;
            for (NSString *root in roots) {
                if ([file hasPrefix:[root stringByAppendingString:@"/"]]) {
                    NSString *relative = [file substringFromIndex:root.length + 1];
                    NSRange slash = [relative rangeOfString:@"/"];
                    if (slash.location != NSNotFound)
                        owner = [root stringByAppendingPathComponent:[relative substringToIndex:slash.location]];
                    break;
                }
            }
            if (owner && [handled containsObject:owner]) continue;

            BOOL ok = [CCPathGuard isPath:file insideRoots:roots] && [parents allows:file] && (trash ? MoveToTrash(file) : RemoveFile(file));
            @synchronized (lock) {
                if (ok) {
                    deleted++;
                    freed += length;
                } else {
                    failed++;
                }
            }
            if (ok && owner) [owners addObject:owner];
            report(NO);
        }
        @synchronized (lock) { [touched unionSet:owners]; }
    });

    // Folders emptied by the clean are removed too; roots themselves and other targets' roots are kept.
    for (NSString *dir in touched) {
        if (cancel.isCancelled) break;
        PruneEmpty(dir, scan.skippedRoots, cancel);
    }

    return finish();
}

- (CCTargetCleanResult *)removeEntry:(CCEntry *)entry fromScan:(CCScanResult *)scan options:(CCCleanOptions *)options {
    NSArray<NSString *> *roots = scan.roots;
    if (![CCPathGuard isPath:entry.path insideRoots:roots]) return nil;
    if (![[[CCParentCheck alloc] initWithRoots:roots] allows:entry.path]) return nil;
    struct stat st;
    if (lstat(entry.path.fileSystemRepresentation, &st) != 0) return nil;

    BOOL trash = options.useTrash && !scan.target.alwaysPermanent;
    BOOL removed = trash ? MoveToTrash(entry.path)
                 : S_ISDIR(st.st_mode) ? [NSFileManager.defaultManager removeItemAtPath:entry.path error:nil] // never follows links
                 : RemoveFile(entry.path);
    if (!removed) return nil;

    // Take the entry's files out of the scan, so the totals and a later clean match what is left on disk.
    NSString *prefix = [entry.path stringByAppendingString:@"/"];
    NSMutableArray<NSString *> *files = [NSMutableArray arrayWithCapacity:scan.files.count];
    NSMutableData *sizes = [NSMutableData dataWithCapacity:scan.sizes.length];
    long long total = 0;
    for (NSUInteger i = 0; i < scan.files.count; i++) {
        NSString *file = scan.files[i];
        if ([file isEqualToString:entry.path] || [file hasPrefix:prefix]) continue;
        long long size = [scan sizeAtIndex:i];
        [files addObject:file];
        [sizes appendBytes:&size length:sizeof size];
        total += size;
    }
    CCTargetCleanResult *result = [CCTargetCleanResult new];
    result.targetId = scan.target.identifier;
    result.bytesFreed = scan.totalBytes - total;
    result.filesDeleted = scan.fileCount - (NSInteger)files.count;
    [scan.files setArray:files];
    [scan.sizes setData:sizes];
    scan.totalBytes = total;
    scan.fileCount = (NSInteger)files.count;
    NSMutableArray *entries = [scan.topEntries mutableCopy];
    [entries removeObject:entry];
    scan.topEntries = entries;
    result.bytesRemaining = total;
    result.filesRemaining = scan.fileCount;
    return result;
}

@end

// ───────────── disk map ─────────────

NSString *CCSpaceSegmentName(CCSpaceSegment segment) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = @[ @"System", @"Apps", @"Caches", @"Developer", @"Models", @"VirtualMachines", @"Files", @"Other" ]; });
    return segment >= 0 && segment < CCSpaceSegmentCount ? names[(NSUInteger)segment] : @"Other";
}

NSString *CCSpaceRiskName(CCSpaceRisk risk) {
    switch (risk) {
        case CCSpaceRiskSafe: return @"Safe";
        case CCSpaceRiskModerate: return @"Moderate";
        case CCSpaceRiskCareful: return @"Careful";
        case CCSpaceRiskKeep: return @"Keep";
    }
    return @"Keep";
}

@implementation CCSpacePart
+ (instancetype)kind:(NSString *)kind pattern:(NSString *)pattern risk:(CCSpaceRisk)risk {
    CCSpacePart *p = [self new];
    p->_kind = [kind copy];
    p->_pattern = [pattern copy];
    p->_risk = risk;
    return p;
}
@end

@implementation CCSpaceRule
- (instancetype)init {
    if ((self = [super init])) {
        _risk = CCSpaceRiskKeep;
        _paths = @[];
        _parts = @[];
        _symbol = @"folder";
    }
    return self;
}
@end

@interface CCSpaceEntry ()
/// First-level names a cache target leaves alone (Apple's own caches); not counted as cleanable.
@property (nonatomic, copy, nullable) NSArray<NSString *> *excludedNames;
@end

@implementation CCSpaceEntry
- (instancetype)init {
    if ((self = [super init])) {
        _children = [NSMutableArray array];
        _paths = @[];
        _symbol = @"folder";
    }
    return self;
}
- (NSString *)path { return self.paths.firstObject ?: @""; }
@end

@implementation CCSpaceReport {
    long long _segments[CCSpaceSegmentCount];
}
- (instancetype)init {
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        _volumeName = @"";
    }
    return self;
}
- (long long)used { return MAX(0, self.total - self.free); }
- (long long *)segments { return _segments; }
- (long long)measured {
    long long sum = 0;
    for (CCSpaceEntry *e in self.items) sum += e.bytes;
    return sum;
}
@end

@implementation CCSpaceRoot
+ (instancetype)pattern:(NSString *)pattern segment:(CCSpaceSegment)segment keep:(BOOL)keep {
    CCSpaceRoot *r = [self new];
    r->_pattern = [pattern copy];
    r->_segment = segment;
    r->_keep = keep;
    return r;
}
@end

@implementation CCSpaceScope
- (instancetype)init {
    if ((self = [super init])) {
        _rules = @[];
        _roots = @[];
        _containers = @[];
        _filed = @{};
        _personal = @[];
        _skipped = @[];
        _guarded = @[];
        _volumePath = CCHomeDirectory();
        _smallFolder = 64LL * 1024 * 1024;
        _folderSymbol = @"folder";
        _personalSymbol = @"person.crop.square";
        _cachesSymbol = @"sparkles";
    }
    return self;
}
@end

static CCSpaceRule *Rule(NSString *identifier, CCSpaceSegment segment, NSString *symbol, CCSpaceRisk risk, NSArray<NSString *> *paths) {
    CCSpaceRule *r = [CCSpaceRule new];
    r.identifier = identifier;
    r.segment = segment;
    r.symbol = symbol;
    r.risk = risk;
    r.paths = paths;
    return r;
}

static CCSpaceRule *Listed(CCSpaceRule *r, NSString *kind) {
    r.listKind = kind;
    return r;
}

static CCSpaceRule *Command(CCSpaceRule *r, NSString *command) {
    r.command = command;
    return r;
}

static CCSpaceRule *Guarded(CCSpaceRule *r) {
    r.needsFullDiskAccess = YES;
    return r;
}

@implementation CCSpaceCatalog

+ (NSArray<CCSpaceRule *> *)rules {
    static NSArray<CCSpaceRule *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Hermes Agent (Nous Research): its caches and pre-restore backups can go; its runtimes, code, history,
        // memories and skills are the agent itself.
        CCSpaceRule *hermes = Rule(@"hermes", CCSpaceDeveloper, @"brain.head.profile", CCSpaceRiskKeep, @[ @"~/.hermes" ]);
        hermes.parts = @[
            [CCSpacePart kind:@"cache" pattern:@"cache" risk:CCSpaceRiskSafe],
            [CCSpacePart kind:@"cache" pattern:@"hermes-agent/.cache" risk:CCSpaceRiskSafe],
            [CCSpacePart kind:@"cache" pattern:@"image_cache" risk:CCSpaceRiskSafe],
            [CCSpacePart kind:@"cache" pattern:@"audio_cache" risk:CCSpaceRiskSafe],
            [CCSpacePart kind:@"backups" pattern:@"backups" risk:CCSpaceRiskCareful],
            [CCSpacePart kind:@"logs" pattern:@"logs" risk:CCSpaceRiskModerate],
            [CCSpacePart kind:@"app" pattern:@"installs" risk:CCSpaceRiskKeep],
            [CCSpacePart kind:@"app" pattern:@"hermes-agent" risk:CCSpaceRiskKeep],
            [CCSpacePart kind:@"app" pattern:@"tools" risk:CCSpaceRiskKeep],
        ];
        // One row per downloaded model or dataset; the shared blob store and locks stay with the item.
        CCSpaceRule *huggingface = Listed(Rule(@"huggingface", CCSpaceModels, @"brain", CCSpaceRiskCareful, @[ @"~/.cache/huggingface/hub" ]), @"model");
        huggingface.listPattern = @"*--*";
        // Claude Code's scratch output, one folder per project; the running sessions write into it.
        NSString *claudeTmp = [NSString stringWithFormat:@"/private/tmp/claude-%u", getuid()];
        NSString *aerial = @"/Library/Application Support/com.apple.idleassetsd/Customer";
        NSString *installData = @"/System/Volumes/Data/macOS Install Data";

        all = @[
            // ── AI agents and models ──
            hermes,
            huggingface,
            Command(Rule(@"ollama", CCSpaceModels, @"brain", CCSpaceRiskCareful, @[ @"~/.ollama/models" ]), @"ollama rm <model>"),
            Listed(Rule(@"lmstudio", CCSpaceModels, @"brain", CCSpaceRiskCareful, @[ @"~/.lmstudio/models", @"~/.cache/lm-studio/models" ]), @"model"),
            Listed(Rule(@"mac.claudetmp", CCSpaceDeveloper, @"terminal", CCSpaceRiskModerate, @[ claudeTmp ]), @"session"),

            // ── emulators and virtual machines ──
            Listed(Rule(@"android.images", CCSpaceVirtualMachines, @"square.stack.3d.up", CCSpaceRiskModerate,
                        @[ @"~/Library/Android/sdk/system-images/*/*" ]), @"image"),
            Listed(Rule(@"android.avd", CCSpaceVirtualMachines, @"iphone", CCSpaceRiskCareful, @[ @"~/.android/avd" ]), @"vm"),
            Command(Listed(Rule(@"mac.lima", CCSpaceVirtualMachines, @"server.rack", CCSpaceRiskKeep, @[ @"~/.lima" ]), @"vm"),
                    @"limactl list && limactl delete <name>"),
            Command(Rule(@"mac.simulators", CCSpaceVirtualMachines, @"ipad.and.iphone", CCSpaceRiskCareful,
                         @[ @"~/Library/Developer/CoreSimulator/Devices" ]), @"xcrun simctl delete unavailable"),
            Listed(Rule(@"mac.vms", CCSpaceVirtualMachines, @"desktopcomputer", CCSpaceRiskCareful,
                        @[ @"~/Parallels", @"~/Virtual Machines.localized", @"~/VirtualBox VMs" ]), @"vm"),

            // ── developer runtimes ──
            Command(Rule(@"mac.uv", CCSpaceDeveloper, @"terminal", CCSpaceRiskKeep, @[ @"~/.local/share/uv" ]),
                    @"uv python list --only-installed && uv tool list"),

            // ── apps ──
            Listed(Rule(@"mac.applications", CCSpaceApps, @"square.grid.2x2", CCSpaceRiskKeep, @[ @"/Applications" ]), @"app"),

            // ── system: belongs to root, so a command removes it ──
            Command(Rule(@"mac.aerial", CCSpaceSystem, @"photo.on.rectangle", CCSpaceRiskModerate, @[ aerial ]),
                    [NSString stringWithFormat:@"sudo rm -rf \"%@\"", aerial]),
            Command(Rule(@"mac.installdata", CCSpaceSystem, @"arrow.down.circle", CCSpaceRiskModerate, @[ installData ]),
                    [NSString stringWithFormat:@"sudo rm -rf \"%@\"", installData]),

            // ── readable only with Full Disk Access ──
            Guarded(Listed(Rule(@"mac.iosbackups", CCSpaceFiles, @"iphone", CCSpaceRiskCareful,
                                @[ @"~/Library/Application Support/MobileSync/Backup" ]), @"device")),
            Guarded(Rule(@"mac.trash", CCSpaceOther, @"trash", CCSpaceRiskKeep, @[ @"~/.Trash" ])),
        ];
    });
    return all;
}

+ (CCSpaceScope *)scopeWithFullDiskAccess:(BOOL)fullDiskAccess {
    CCSpaceScope *scope = [CCSpaceScope new];
    scope.rules = [self rules];
    // ~/Library first: its folders are items of their own, so it is never one big "Library" row under the home folder.
    scope.roots = @[
        [CCSpaceRoot pattern:@"~/Library" segment:CCSpaceApps keep:NO],
        [CCSpaceRoot pattern:@"~" segment:CCSpaceOther keep:NO],
        [CCSpaceRoot pattern:@"/Library/Application Support" segment:CCSpaceSystem keep:YES],
    ];
    scope.containers = @[ @"~/Library/Application Support", @"~/Library/Developer", @"~/.cache", @"~/.local", @"~/.config" ];
    NSMutableDictionary *filed = [NSMutableDictionary dictionary];
    for (NSString *p in @[ @"~/Library/Developer", @"~/Library/Android", @"~/.npm", @"~/.cargo", @"~/.rustup", @"~/.gradle", @"~/.m2",
                           @"~/.nvm", @"~/.bun", @"~/.pyenv", @"~/.conda", @"~/miniconda3", @"~/anaconda3", @"~/miniforge3",
                           @"~/.docker", @"~/.vscode", @"~/.cursor", @"~/.codex", @"~/.claude", @"~/go", @"~/.swiftpm",
                           @"~/.dotnet", @"~/.nuget", @"~/.android", @"~/.gem", @"~/.cocoapods" ])
        filed[p] = @(CCSpaceDeveloper);
    for (NSString *p in @[ @"~/.local", @"~/.config", @"~/Applications" ]) filed[p] = @(CCSpaceApps);
    scope.filed = filed;
    scope.personal = @[ @"~/Desktop", @"~/Documents", @"~/Downloads", @"~/Movies", @"~/Music", @"~/Pictures", @"~/Public",
                        @"~/Library/Mobile Documents", @"~/Library/CloudStorage" ];
    // Opening another app's sandbox container makes macOS 15 ask "would like to access data from other apps": they are
    // never entered, and what they hold stays in "System and other".
    scope.skipped = @[ @"~/Library/Containers", @"~/Library/Group Containers" ];
    // Desktop, Documents, Downloads and iCloud Drive make macOS ask for each folder; mail and messages are refused.
    scope.guarded = @[ @"~/Desktop", @"~/Documents", @"~/Downloads", @"~/Library/Mobile Documents", @"~/Library/CloudStorage",
                       @"~/Library/Mail", @"~/Library/Messages", @"~/Library/Safari", @"~/Library/Calendars",
                       @"~/Library/Reminders", @"~/Library/Cookies", @"~/Library/HomeKit", @"~/Library/IdentityServices",
                       @"~/Library/Suggestions", @"~/Library/Metadata/CoreSpotlight" ];
    scope.hasFullDiskAccess = fullDiskAccess;
    scope.volumePath = CCHomeDirectory();
    return scope;
}

@end

// ── helpers ──

static BOOL IsInsidePath(NSString *path, NSString *root) {
    return path.length > root.length + 1 && [path hasPrefix:root] && [path characterAtIndex:root.length] == '/';
}

/// Whether the path or one of its parents is in the set.
static BOOL WithinAny(NSString *path, NSSet<NSString *> *set) {
    for (NSString *p = path; p.length > 1; p = p.stringByDeletingLastPathComponent)
        if ([set containsObject:p]) return YES;
    return NO;
}

static BOOL IsLink(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode);
}

/// Existing folders a pattern names; links are left out (what they point to is measured where it lives).
static NSArray<NSString *> *ExpandFolders(NSString *pattern) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *p in CCExpandPattern(pattern))
        if (!IsLink(p)) [result addObject:p];
    return result;
}

static NSArray<NSString *> *SubFolders(NSString *root) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) [result addObject:path];
    }
    return result;
}

static long long MeasureTree(NSString *path, NSSet<NSString *> *excluded, NSArray<NSString *> *excludedNames,
                             CCCancelToken *cancel, BOOL *unreadable) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return 0;
    if (S_ISREG(st.st_mode)) return (long long)st.st_blocks * 512;
    if (!S_ISDIR(st.st_mode)) return 0;

    char *paths[] = { (char *)path.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) {
        if (unreadable) *unreadable = YES;
        return 0;
    }
    long long bytes = 0;
    // A file with several hard links is counted once.
    NSMutableSet<NSNumber *> *linked = nil;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (cancel.isCancelled) break;
        switch (e->fts_info) {
            case FTS_D:
                if (e->fts_level == 0) break;
                if (e->fts_level == 1 && excludedNames && MatchesAny(excludedNames, e->fts_name)) {
                    fts_set(fts, e, FTS_SKIP);
                    break;
                }
                if (excluded.count && [excluded containsObject:PathFromEntry(e->fts_path, e->fts_pathlen)]) fts_set(fts, e, FTS_SKIP);
                break;
            case FTS_F:
                if (e->fts_level == 1 && excludedNames && MatchesAny(excludedNames, e->fts_name)) break;
                if (e->fts_statp->st_nlink > 1) {
                    if (!linked) linked = [NSMutableSet set];
                    NSNumber *inode = @(e->fts_statp->st_ino);
                    if ([linked containsObject:inode]) break;
                    [linked addObject:inode];
                }
                bytes += (long long)e->fts_statp->st_blocks * 512;
                break;
            case FTS_DNR:
            case FTS_ERR:
            case FTS_NS:
                if (unreadable) *unreadable = YES;
                break;
            default:
                // links, sockets and the like are neither counted nor followed
                break;
        }
    }
    fts_close(fts);
    return bytes;
}

static CCSpaceEntry *SpaceEntry(NSString *identifier, CCSpaceSegment segment, CCSpaceRisk risk, NSString *symbol,
                                NSString *key, NSString *name, NSArray<NSString *> *paths) {
    CCSpaceEntry *e = [CCSpaceEntry new];
    e.identifier = identifier;
    e.segment = segment;
    e.risk = risk;
    e.symbol = symbol;
    e.key = key;
    e.name = name;
    e.paths = paths;
    return e;
}

/// The literal part of a pattern, up to its first wildcard segment.
static NSString *FixedPrefix(NSString *pattern) {
    NSMutableArray *fixed = [NSMutableArray array];
    for (NSString *segment in [pattern componentsSeparatedByString:@"/"]) {
        if ([segment rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?["]].location != NSNotFound) break;
        [fixed addObject:segment];
    }
    return [fixed componentsJoinedByString:@"/"];
}

static BOOL EntryCanDelete(CCSpaceEntry *e) {
    return e.risk != CCSpaceRiskKeep && !e.command && !e.targetId && !e.needsAccess && e.paths.count == 1
        && [CCPathGuard isAllowedRoot:e.paths.firstObject];
}

@implementation CCDiskMapEngine

+ (long long)measure:(NSString *)path excluding:(NSSet<NSString *> *)excluded cancel:(CCCancelToken *)cancel unreadable:(BOOL *)unreadable {
    return MeasureTree(path, excluded ?: [NSSet set], nil, cancel, unreadable);
}

- (CCSpaceReport *)analyze:(CCSpaceScope *)scope
                   targets:(NSArray<CCTarget *> *)targets
                    cancel:(CCCancelToken *)cancel
                  progress:(void (^)(NSString *))progress {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    CCSpaceReport *report = [CCSpaceReport new];
    NSURL *volume = [NSURL fileURLWithPath:scope.volumePath];
    NSDictionary *v = [volume resourceValuesForKeys:@[ NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey,
                                                       NSURLVolumeAvailableCapacityKey, NSURLVolumeLocalizedNameKey ] error:nil];
    report.total = [v[NSURLVolumeTotalCapacityKey] longLongValue];
    report.free = [v[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue] ?: [v[NSURLVolumeAvailableCapacityKey] longLongValue];
    report.volumeName = [v[NSURLVolumeLocalizedNameKey] length] ? v[NSURLVolumeLocalizedNameKey] : @"/";

    NSMutableArray<CCSpaceEntry *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *claimed = [NSMutableSet set];
    BOOL (^taken)(NSString *) = ^BOOL(NSString *p) { return WithinAny(p, claimed); };

    // 0. Folders that are never entered (other apps' containers), and without Full Disk Access the guarded ones.
    NSMutableSet<NSString *> *guarded = [NSMutableSet set], *private = [NSMutableSet set];
    for (NSString *pattern in scope.skipped) [claimed addObjectsFromArray:ExpandFolders(pattern)];
    for (NSString *pattern in scope.guarded) [private addObjectsFromArray:ExpandFolders(pattern)];
    if (!scope.hasFullDiskAccess) [guarded unionSet:private];

    // 1. Known items and their parts.
    for (CCSpaceRule *rule in scope.rules) {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (NSString *pattern in rule.paths)
            for (NSString *p in ExpandFolders(pattern))
                if (!taken(p) && ![paths containsObject:p]) [paths addObject:p];
        if (paths.count == 0) continue;
        [claimed addObjectsFromArray:paths];

        CCSpaceEntry *entry = SpaceEntry(rule.identifier, rule.segment, rule.risk, rule.symbol,
                                         [@"space." stringByAppendingString:rule.identifier], nil, paths);
        entry.command = rule.command;
        entry.needsAccess = rule.needsFullDiskAccess && !scope.hasFullDiskAccess;
        for (NSString *root in paths) {
            if (entry.needsAccess) break;
            for (CCSpacePart *part in rule.parts)
                for (NSString *p in ExpandFolders([root stringByAppendingPathComponent:part.pattern]))
                    [entry.children addObject:SpaceEntry([NSString stringWithFormat:@"%@/%@", rule.identifier, part.pattern], rule.segment,
                                                         part.risk, rule.symbol, [@"space.kind." stringByAppendingString:part.kind], nil, @[ p ])];
        }
        if (rule.listKind && !entry.needsAccess) {
            // A pattern with wildcards lists what it matched ("android-34/google_apis"); a plain folder lists its subfolders.
            NSMutableArray<NSString *> *listed = [NSMutableArray array];
            NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
            for (NSString *pattern in rule.paths) {
                NSString *prefix = FixedPrefix(pattern);
                BOOL wild = ![prefix isEqualToString:pattern];
                NSString *base = wild ? CCExpandPattern(prefix).firstObject : nil;
                for (NSString *root in paths) {
                    if (wild) {
                        if (base && IsInsidePath(root, base)) {
                            [listed addObject:root];
                            names[root] = [root substringFromIndex:base.length + 1];
                        }
                    } else if ([ExpandFolders(pattern) containsObject:root]) {
                        for (NSString *sub in SubFolders(root)) {
                            NSString *name = sub.lastPathComponent;
                            if ([name hasPrefix:@"."] || [name hasPrefix:@"_"] || [claimed containsObject:sub]) continue;
                            if (rule.listPattern && fnmatch(rule.listPattern.fileSystemRepresentation, name.fileSystemRepresentation, 0) != 0) continue;
                            [listed addObject:sub];
                            names[sub] = name;
                        }
                    }
                }
            }
            // One match is the item itself, not a part of it.
            if (listed.count == 1 && paths.count == 1 && [listed.firstObject isEqualToString:paths.firstObject]) [listed removeAllObjects];
            for (NSString *p in listed)
                [entry.children addObject:SpaceEntry([NSString stringWithFormat:@"%@/%@", rule.identifier, names[p]], rule.segment, rule.risk,
                                                     rule.symbol, [@"space.kind." stringByAppendingString:rule.listKind], names[p], @[ p ])];
        }
        [entries addObject:entry];
    }

    // 2. What the cleaner can clean, one child per target. Deeper roots first, so a target inside another one's root
    // (Homebrew inside ~/Library/Caches) keeps its own row and the outer one leaves it out.
    CCSpaceEntry *caches = SpaceEntry(@"caches", CCSpaceCaches, CCSpaceRiskSafe, scope.cachesSymbol, @"space.caches", nil, @[]);
    NSMutableArray *rootsByTarget = [NSMutableArray array];
    for (CCTarget *target in targets)
        for (NSString *root in [target resolveRoots]) [rootsByTarget addObject:@[ root, target ]];
    [rootsByTarget sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSUInteger da = [a[0] pathComponents].count, db = [b[0] pathComponents].count;
        return da > db ? NSOrderedAscending : da < db ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *targetRoots = [NSMutableDictionary dictionary];
    for (NSArray *pair in rootsByTarget) {
        NSString *root = pair[0];
        CCTarget *target = pair[1];
        if (taken(root) || [guarded containsObject:root] || IsLink(root)) continue;
        [claimed addObject:root];
        NSMutableArray *list = targetRoots[target.identifier] ?: (targetRoots[target.identifier] = [NSMutableArray array]);
        [list addObject:root];
    }
    for (CCTarget *target in targets) {
        NSArray *roots = targetRoots[target.identifier];
        if (!roots.count) continue;
        CCSpaceEntry *child = SpaceEntry(target.identifier, CCSpaceCaches, (CCSpaceRisk)target.risk, target.symbol,
                                         target.displayName ? nil : [@"target." stringByAppendingString:target.identifier],
                                         target.displayName, roots);
        child.targetId = target.identifier;
        child.excludedNames = target.excludedNames;
        [caches.children addObject:child];
    }
    if (caches.children.count) [entries addObject:caches];

    // 3. Everything else under the roots, folder by folder.
    NSMutableSet<NSString *> *rootPaths = [NSMutableSet set];
    for (CCSpaceRoot *root in scope.roots) [rootPaths addObjectsFromArray:ExpandFolders(root.pattern)];
    NSMutableSet<NSString *> *personal = [NSMutableSet set], *containers = [NSMutableSet set];
    for (NSString *p in scope.personal) [personal addObjectsFromArray:ExpandFolders(p)];
    for (NSString *p in scope.containers) [containers addObjectsFromArray:ExpandFolders(p)];
    NSMutableDictionary<NSString *, NSNumber *> *filed = [NSMutableDictionary dictionary];
    [scope.filed enumerateKeysAndObjectsUsingBlock:^(NSString *pattern, NSNumber *segment, BOOL *stop) {
        for (NSString *p in ExpandFolders(pattern)) filed[p] = segment;
    }];
    CCSpaceEntry * (^discovered)(NSString *, CCSpaceSegment, BOOL, BOOL) = ^CCSpaceEntry *(NSString *dir, CCSpaceSegment segment, BOOL isPersonal, BOOL keep) {
        // Your own files and data, protected and system folders are shown only; anything else may go, at your discretion.
        CCSpaceRisk risk = isPersonal || keep || [private containsObject:dir] || ![CCPathGuard isAllowedRoot:dir] ? CCSpaceRiskKeep : CCSpaceRiskCareful;
        CCSpaceEntry *e = SpaceEntry([@"folder:" stringByAppendingString:dir], segment, risk,
                                     isPersonal ? scope.personalSymbol : scope.folderSymbol,
                                     isPersonal ? @"space.personal" : @"space.folder", dir.lastPathComponent, @[ dir ]);
        e.needsAccess = [guarded containsObject:dir];
        return e;
    };
    for (CCSpaceRoot *root in scope.roots) {
        for (NSString *rootPath in ExpandFolders(root.pattern)) {
            for (NSString *dir in SubFolders(rootPath)) {
                if ([claimed containsObject:dir] || [rootPaths containsObject:dir]) continue;
                BOOL isPersonal = [personal containsObject:dir];
                // Mail, Messages, Safari and the like stay out of the list (and in "System and other") until they can be read.
                if ([guarded containsObject:dir] && !isPersonal) continue;
                CCSpaceSegment band = isPersonal ? CCSpaceFiles : filed[dir] ? (CCSpaceSegment)filed[dir].integerValue : root.segment;
                CCSpaceEntry *entry = discovered(dir, band, isPersonal, root.keep);
                if ([containers containsObject:dir] && !entry.needsAccess)
                    for (NSString *sub in SubFolders(dir))
                        if (![claimed containsObject:sub] && ![guarded containsObject:sub])
                            [entry.children addObject:discovered(sub, band, isPersonal, root.keep)];
                [entries addObject:entry];
                [claimed addObject:dir];
            }
        }
    }
    // Guarded folders are left out of whatever holds them, measured or not.
    if (!scope.hasFullDiskAccess) [claimed unionSet:guarded];

    // 4. Measure every entry and part, skipping what another entry owns.
    NSMutableArray<CCSpaceEntry *> *all = [NSMutableArray array];
    NSMapTable<CCSpaceEntry *, NSSet<NSString *> *> *siblings = [NSMapTable strongToStrongObjectsMapTable];
    for (CCSpaceEntry *e in entries) {
        if (e.needsAccess) continue;
        if (e != caches) [all addObject:e];
        NSMutableSet *parts = [NSMutableSet set];
        for (CCSpaceEntry *c in e.children) [parts addObjectsFromArray:c.paths];
        for (CCSpaceEntry *c in e.children) {
            if (c.needsAccess) continue;
            [all addObject:c];
            // A part leaves out the parts inside it ("hermes-agent" without "hermes-agent/.cache").
            NSMutableSet *inner = [NSMutableSet set];
            for (NSString *p in parts)
                if (IsInsidePath(p, c.path)) [inner addObject:p];
            if (inner.count) [siblings setObject:inner forKey:c];
        }
    }
    NSSet<NSString *> *owned = [claimed copy];
    dispatch_apply(all.count, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        if (cancel.isCancelled) return;
        CCSpaceEntry *entry = all[i];
        NSSet *extra = [siblings objectForKey:entry];
        NSSet *excluded = extra ? [owned setByAddingObjectsFromSet:extra] : owned;
        long long bytes = 0;
        BOOL unreadable = NO;
        for (NSString *p in entry.paths) bytes += MeasureTree(p, excluded, entry.excludedNames, cancel, &unreadable);
        entry.bytes = bytes;
        entry.unreadable = unreadable;
        if (progress) progress(entry.path);
    });
    if (cancel.isCancelled) return report;

    // Parts lie inside their item, whose own measurement already holds them; the cache entry, which has no folder of
    // its own, is the sum of its targets.
    for (CCSpaceEntry *e in entries) {
        if (e == caches) {
            long long sum = 0;
            for (CCSpaceEntry *c in e.children) sum += c.bytes;
            e.bytes = sum;
        }
        [e.children filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CCSpaceEntry *c, NSDictionary *b) { return c.bytes > 0 || c.needsAccess; }]];
        [e.children sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
    }

    // 5. Small discovered folders fold into one entry per band.
    for (NSInteger segment = 0; segment < CCSpaceSegmentCount; segment++) {
        NSMutableArray<CCSpaceEntry *> *small = [NSMutableArray array];
        for (CCSpaceEntry *e in entries)
            if (e.segment == segment && [e.identifier hasPrefix:@"folder:"] && !e.needsAccess && e.bytes < scope.smallFolder) [small addObject:e];
        if (!small.count) continue;
        [entries removeObjectsInArray:small];
        CCSpaceEntry *rest = SpaceEntry([NSString stringWithFormat:@"small:%@", CCSpaceSegmentName(segment)], segment, CCSpaceRiskKeep,
                                        scope.folderSymbol, @"space.small", nil, @[]);
        long long sum = 0;
        for (CCSpaceEntry *e in small) {
            sum += e.bytes;
            if (e.bytes > 0) [rest.children addObject:e];
        }
        rest.bytes = sum;
        [rest.children sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
        if (sum > 0) [entries addObject:rest];
    }

    for (CCSpaceEntry *e in entries) {
        e.canDelete = EntryCanDelete(e);
        for (CCSpaceEntry *c in e.children) {
            c.canDelete = EntryCanDelete(c);
            for (CCSpaceEntry *g in c.children) g.canDelete = EntryCanDelete(g);
        }
    }
    [entries filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CCSpaceEntry *e, NSDictionary *b) { return e.bytes > 0 || e.needsAccess; }]];
    [entries sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
    [report.items addObjectsFromArray:entries];
    for (CCSpaceEntry *e in entries) report.segments[e.segment] += e.bytes;
    // Used but not measured: the operating system, swap, snapshots and whatever could not be read.
    report.segments[CCSpaceSystem] += MAX(0, report.used - report.measured);
    report.elapsed = CFAbsoluteTimeGetCurrent() - start;
    return report;
}

- (long long)removeEntry:(CCSpaceEntry *)entry useTrash:(BOOL)useTrash {
    if (!EntryCanDelete(entry)) return 0;
    NSString *path = entry.path;
    // The path must be what it says: no link in its place or among its parents.
    if (![[CCPathGuard normalize:path] isEqualToString:path]) return 0;
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode)) return 0;

    BOOL removed = useTrash ? MoveToTrash(path)
                 : S_ISDIR(st.st_mode) ? [NSFileManager.defaultManager removeItemAtPath:path error:nil] // never follows links
                 : RemoveFile(path);
    if (removed || lstat(path.fileSystemRepresentation, &st) != 0) return entry.bytes;
    // Partly removed: what is left stays counted.
    long long left = MeasureTree(path, [NSSet set], nil, nil, NULL);
    return MAX(0, entry.bytes - left);
}

@end
