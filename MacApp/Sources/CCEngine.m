#import "CCEngine.h"
#include <sys/mount.h>
#include <errno.h>
#include <fnmatch.h>
#include <fts.h>
#include <sys/stat.h>
#include <sys/attr.h>
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

/// The bytes of a file no clone shares (APFS): what deleting it frees now. Falls back to the allocated size.
static long long PrivateSize(const char *path, const struct stat *st) {
    struct attrlist request = { .bitmapcount = ATTR_BIT_MAP_COUNT, .commonattr = ATTR_CMN_RETURNED_ATTRS, .forkattr = ATTR_CMNEXT_PRIVATESIZE };
    struct {
        uint32_t length;
        attribute_set_t returned;
        off_t privateSize;
    } __attribute__((packed)) reply;
    if (getattrlist(path, &request, &reply, sizeof reply, FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) == 0
        && (reply.returned.forkattr & ATTR_CMNEXT_PRIVATESIZE))
        return reply.privateSize;
    return (long long)st->st_blocks * 512;
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
    long long totalBytes = 0, sharedBytes = 0;
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
                    if (target.sharesBlocks) {
                        long long allocated = (long long)e->fts_statp->st_blocks * 512;
                        length = PrivateSize(e->fts_path, e->fts_statp);
                        sharedBytes += MAX(0, allocated - length);
                    }
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
    result.sharedBytes = sharedBytes;
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

    // A root that is junk as a whole goes in one piece: an app's copy is full of framework links, which a file-by-file
    // clean never follows and so would leave behind as an empty tree.
    if (scan.target.deletesWholeRoots) {
        // The scan may be hours old: only what is still junk now goes (Cowork opened since, a session resumed).
        NSSet *still = [NSSet setWithArray:[scan.target freshRoots]];
        NSMutableArray<NSString *> *now = [NSMutableArray array];
        for (NSString *root in roots)
            if ([still containsObject:root]) [now addObject:root];
            else {
                NSString *prefix = [root stringByAppendingString:@"/"];
                for (NSString *file in scan.files)
                    if ([file isEqualToString:root] || [file hasPrefix:prefix]) failed++;
            }
        if (scan.target.beforeClean && now.count) scan.target.beforeClean(now);
        for (NSString *root in now) {
            if (cancel.isCancelled) break;
            long long bytes = 0;
            NSInteger files = 0;
            NSString *prefix = [root stringByAppendingString:@"/"];
            for (NSUInteger i = 0; i < scan.files.count; i++)
                if ([scan.files[i] isEqualToString:root] || [scan.files[i] hasPrefix:prefix]) {
                    bytes += [scan sizeAtIndex:i];
                    files++;
                }
            struct stat st;
            // The root must still be what was scanned: allowed, not a link, no link among its parents.
            if (![CCPathGuard isAllowedRoot:root] || ![[CCPathGuard normalize:root] isEqualToString:root]
                || lstat(root.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode) || st.st_uid != getuid()) {
                @synchronized (lock) { failed += files; }
                continue;
            }
            BOOL removed = trash ? MoveToTrash(root)
                         : S_ISDIR(st.st_mode) ? [NSFileManager.defaultManager removeItemAtPath:root error:nil] // never follows links
                         : RemoveFile(root);
            if (!removed && lstat(root.fileSystemRepresentation, &st) == 0) {
                @synchronized (lock) { failed += files; }
                continue;
            }
            @synchronized (lock) {
                freed += bytes;
                deleted += files;
            }
            report(NO);
        }
        return finish();
    }

    if (scan.target.beforeClean && roots.count) scan.target.beforeClean(roots);

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
    // A root that is itself the junk (an old project's node_modules) goes too once it is empty.
    if (scan.target.removesRoots && !options.dryRun)
        for (NSString *root in roots) rmdir(root.fileSystemRepresentation);

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
    // These are what no file accounts for, not something that was measured.
    for (CCSpaceEntry *e in self.items)
        if (![@[ @"mac.noaccess", @"unknown" ] containsObject:e.identifier]) sum += e.bytes;
    return sum;
}
@end

/// The allocation unit where each file takes whole clusters (exFAT, FAT); 0 elsewhere, where st_blocks is the truth
/// (APFS files can be sparse or cloned).
static long long ClusterSizeAt(NSString *path) {
    struct statfs fs;
    if (statfs(path.fileSystemRepresentation, &fs) != 0) return 0;
    BOOL fat = strcasecmp(fs.f_fstypename, "exfat") == 0 || strcasecmp(fs.f_fstypename, "msdos") == 0;
    return fat ? (long long)fs.f_bsize : 0;
}

@implementation CCVolume

/// The mount point the home folder lives on. The startup disk's data volume counts as "/".
static NSString *HomeMount(void) {
    struct statfs fs;
    if (statfs(CCHomeDirectory().fileSystemRepresentation, &fs) != 0) return @"/";
    NSString *mount = [NSFileManager.defaultManager stringWithFileSystemRepresentation:fs.f_mntonname length:strlen(fs.f_mntonname)];
    return [mount hasPrefix:@"/Volumes/"] ? mount : @"/";
}

static NSArray<NSURLResourceKey> *VolumeKeys(void) {
    return @[ NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeAvailableCapacityKey,
              NSURLVolumeLocalizedNameKey, NSURLVolumeIsLocalKey, NSURLVolumeIsBrowsableKey, NSURLVolumeIsReadOnlyKey ];
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        NSDictionary *v = [url resourceValuesForKeys:VolumeKeys() error:nil];
        _path = url.path.length ? url.path : @"/";
        _total = [v[NSURLVolumeTotalCapacityKey] longLongValue];
        _free = [v[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue] ?: [v[NSURLVolumeAvailableCapacityKey] longLongValue];
        _name = [v[NSURLVolumeLocalizedNameKey] length] ? v[NSURLVolumeLocalizedNameKey] : _path.lastPathComponent;
        _isHome = [_path isEqualToString:HomeMount()];
        struct statfs fs;
        _format = statfs(_path.fileSystemRepresentation, &fs) == 0 ? @(fs.f_fstypename) : @"";
        _isFAT = [_format caseInsensitiveCompare:@"exfat"] == NSOrderedSame || [_format caseInsensitiveCompare:@"msdos"] == NSOrderedSame;
    }
    return self;
}

+ (NSArray<CCVolume *> *)mounted {
    NSMutableArray<CCVolume *> *list = [NSMutableArray array];
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager mountedVolumeURLsIncludingResourceValuesForKeys:VolumeKeys()
                                                                                                   options:NSVolumeEnumerationSkipHiddenVolumes];
    for (NSURL *url in urls) {
        NSDictionary *v = [url resourceValuesForKeys:VolumeKeys() error:nil];
        CCVolume *volume = [[CCVolume alloc] initWithURL:url];
        if (volume.total <= 0) continue;
        // The startup disk's system volume is sealed read-only; it stands for the disk the home folder is on.
        if (!volume.isHome && (![v[NSURLVolumeIsLocalKey] boolValue] || ![v[NSURLVolumeIsBrowsableKey] boolValue] || [v[NSURLVolumeIsReadOnlyKey] boolValue])) continue;
        if (volume.isHome) [list insertObject:volume atIndex:0];
        else [list addObject:volume];
    }
    return list;
}

+ (instancetype)volumeAtPath:(NSString *)path {
    for (CCVolume *v in [self mounted])
        if ([v.path isEqualToString:path]) return v;
    return nil;
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
        _keepNames = @[];
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
            [CCSpacePart kind:@"cache" pattern:@"cache/uv" risk:CCSpaceRiskSafe],
            [CCSpacePart kind:@"cache" pattern:@"cache/pnpm" risk:CCSpaceRiskSafe],
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
            Listed(Rule(@"mac.applications", CCSpaceApps, @"square.grid.2x2", CCSpaceRiskKeep, @[ @"/Applications", @"~/Applications" ]), @"app"),

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
        [CCSpaceRoot pattern:@"~" segment:CCSpaceFiles keep:NO],
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
    // Desktop, Documents, Downloads, Pictures, Music, Movies, contacts and iCloud Drive make macOS ask for each one; mail
    // and messages are refused. None is opened until Full Disk Access covers them all with one switch.
    scope.guarded = @[ @"~/Desktop", @"~/Documents", @"~/Downloads", @"~/Pictures", @"~/Music", @"~/Movies",
                       @"~/Library/Photos", @"~/Library/Application Support/AddressBook", @"~/Library/Application Support/CallHistoryDB",
                       @"~/Library/Application Support/Knowledge", @"~/Library/Mobile Documents", @"~/Library/CloudStorage",
                       @"~/Library/Mail", @"~/Library/Messages", @"~/Library/Safari", @"~/Library/Calendars",
                       @"~/Library/Reminders", @"~/Library/Cookies", @"~/Library/HomeKit", @"~/Library/IdentityServices",
                       @"~/Library/Suggestions", @"~/Library/Metadata/CoreSpotlight" ];
    scope.hasFullDiskAccess = fullDiskAccess;
    scope.volumePath = CCHomeDirectory();
    return scope;
}

+ (CCSpaceScope *)scopeForVolume:(CCVolume *)volume fullDiskAccess:(BOOL)fullDiskAccess {
    NSString *root = volume.path;
    NSString *inside = [root stringByAppendingString:@"/"];
    if (volume.isHome) {
        CCSpaceScope *scope = [self scopeWithFullDiskAccess:fullDiskAccess];
        // A custom folder on another drive belongs to that drive's map.
        scope.listsSystemSpace = YES;
        scope.namesUnaccounted = YES;
        if (![root isEqualToString:@"/"]) scope.includes = ^BOOL(NSString *path) { return [path hasPrefix:inside] || ![path hasPrefix:@"/Volumes/"]; };
        else scope.includes = ^BOOL(NSString *path) { return ![path hasPrefix:@"/Volumes/"]; };
        return scope;
    }
    CCSpaceScope *scope = [CCSpaceScope new];
    scope.rules = [self rules];
    scope.includes = ^BOOL(NSString *path) { return [path hasPrefix:inside]; };
    scope.roots = @[ [CCSpaceRoot pattern:root segment:CCSpaceFiles keep:NO] ];
    // The file system's own folders, here or left by Windows, are shown and never removed.
    NSArray *system = @[ @".Trashes", @".Spotlight-V100", @".fseventsd", @".TemporaryItems", @".DocumentRevisions-V100", @".PKInstallSandboxManager",
                         @"$RECYCLE.BIN", @"System Volume Information", @"Recovery" ];
    NSMutableDictionary *filed = [NSMutableDictionary dictionary];
    for (NSString *name in system) filed[[root stringByAppendingPathComponent:name]] = @(CCSpaceSystem);
    scope.filed = filed;
    scope.keepNames = system;
    scope.hasFullDiskAccess = fullDiskAccess;
    scope.volumePath = root;
    scope.looseFilesRoot = root;
    scope.namesUnaccounted = YES;
    if (volume.isFAT) scope.clusterSize = ClusterSizeAt(root);
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
    // A path that exists as written is itself, even with a bracket in a drive's name.
    struct stat literal;
    if ([pattern hasPrefix:@"/"] && lstat(pattern.fileSystemRepresentation, &literal) == 0) return S_ISLNK(literal.st_mode) ? @[] : @[ pattern ];
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

/// What a file takes on disk. Where files take whole clusters, its length rounded up to them: a file system without
/// real block counts would otherwise read short, and half a million small files on exFAT take tens of gigabytes more
/// than their content.
static long long OnDisk(const struct stat *st, long long cluster) {
    long long allocated = (long long)st->st_blocks * 512;
    if (cluster <= 0) return allocated;
    long long length = MAX(allocated, (long long)st->st_size);
    return (length + cluster - 1) / cluster * cluster;
}

static long long MeasureTree(NSString *path, NSSet<NSString *> *excluded, NSArray<NSString *> *excludedNames,
                             long long cluster, CCCancelToken *cancel, BOOL *unreadable) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return 0;
    if (S_ISREG(st.st_mode)) return OnDisk(&st, cluster);
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
                bytes += OnDisk(e->fts_statp, cluster);
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

/// What each of macOS's own volumes takes (the system, Preboot, Recovery, VM…): every volume but the data one in the
/// startup disk's APFS container. statfs reports the whole container's figures for each, so diskutil is asked; it needs no
/// rights and opens nothing. Empty if it cannot answer in time, and the space then stays in the unaccounted row.
static NSDictionary<NSString *, NSNumber *> *SystemVolumes(void) {
    struct statfs data;
    if (statfs("/System/Volumes/Data", &data) != 0) return @{};
    NSString *device = @(data.f_mntfromname).lastPathComponent;

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/diskutil"];
    task.arguments = @[ @"apfs", @"list", @"-plist" ];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:nil]) return @{};
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (task.isRunning) [task terminate];
    });
    NSData *output = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    NSDictionary *list = output.length ? [NSPropertyListSerialization propertyListWithData:output options:0 format:nil error:nil] : nil;
    if (![list isKindOfClass:NSDictionary.class]) return @{};

    for (NSDictionary *container in list[@"Containers"]) {
        NSArray<NSDictionary *> *volumes = container[@"Volumes"];
        BOOL startup = NO;
        for (NSDictionary *v in volumes) startup |= [v[@"DeviceIdentifier"] isEqual:device];
        if (!startup) continue;
        NSMutableDictionary *sizes = [NSMutableDictionary dictionary];
        for (NSDictionary *v in volumes) {
            long long used = [v[@"CapacityInUse"] longLongValue];
            if ([v[@"DeviceIdentifier"] isEqual:device] || used <= 0 || [v[@"Name"] length] == 0) continue;
            sizes[v[@"Name"]] = @(used);
        }
        return sizes;
    }
    return @{};
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

@implementation CCAppLeftovers

+ (NSString *)bundleIdOfApp:(NSString *)appPath {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *identifier = info[@"CFBundleIdentifier"];
    return [identifier isKindOfClass:NSString.class] && identifier.length ? identifier : nil;
}

+ (BOOL)canUninstall:(NSString *)appPath {
    if (![appPath hasSuffix:@".app"] || ![CCPathGuard isAllowedRoot:appPath] || IsLink(appPath)) return NO;
    NSString *identifier = [self bundleIdOfApp:appPath];
    if (!identifier) return NO;
    return ![identifier hasPrefix:@"com.apple."] && ![identifier hasPrefix:@"io.github.kreal-exe."];
}

/// Every app bundle in /Applications and ~/Applications, also inside folders there (Utilities, a vendor's folder,
/// Chrome's web apps), two levels deep; never inside another app.
+ (NSArray<NSString *> *)installedApps {
    NSMutableArray *apps = [NSMutableArray array];
    NSMutableArray<NSArray *> *queue = [NSMutableArray array];
    for (NSString *folder in @[ @"/Applications", [CCHomeDirectory() stringByAppendingPathComponent:@"Applications"] ])
        [queue addObject:@[ folder, @0 ]];
    for (NSUInteger i = 0; i < queue.count; i++) {
        NSString *folder = queue[i][0];
        NSInteger depth = [queue[i][1] integerValue];
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
            if ([name hasPrefix:@"."]) continue;
            NSString *path = [folder stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            if ([name hasSuffix:@".app"]) [apps addObject:path];
            else if (depth < 2 && !IsLink(path) && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir) [queue addObject:@[ path, @(depth + 1) ]];
        }
    }
    return apps;
}

/// "com.foo.app", "com.foo.app.helper", "com.foo.app.plist", "com.foo.app.savedState" and the like.
static BOOL NamedAfterId(NSString *name, NSString *identifier) {
    NSString *lower = name.lowercaseString, *wanted = identifier.lowercaseString;
    return [lower isEqualToString:wanted] || [lower hasPrefix:[wanted stringByAppendingString:@"."]];
}

+ (NSArray<NSString *> *)leftoversOfApp:(NSString *)appPath otherApps:(NSArray<NSString *> *)otherApps {
    NSString *identifier = [self bundleIdOfApp:appPath];
    if (!identifier || identifier.length < 5) return @[];
    NSString *library = [CCHomeDirectory() stringByAppendingPathComponent:@"Library"];

    NSMutableArray<NSString *> *otherIds = [NSMutableArray array];
    NSMutableSet<NSString *> *otherNames = [NSMutableSet set];
    for (NSString *other in otherApps) {
        if ([other isEqualToString:appPath]) continue;
        NSString *otherId = [self bundleIdOfApp:other];
        if (otherId) [otherIds addObject:otherId];
        [otherNames addObject:other.lastPathComponent.stringByDeletingPathExtension.lowercaseString];
    }
    // Longer ids of other apps own what they name: com.google.Chrome.canary is not Chrome's.
    BOOL (^othersOwn)(NSString *) = ^BOOL(NSString *name) {
        for (NSString *otherId in otherIds)
            if (otherId.length >= identifier.length && NamedAfterId(name, otherId)) return YES;
        return NO;
    };

    NSMutableOrderedSet<NSString *> *found = [NSMutableOrderedSet orderedSet];
    void (^add)(NSString *) = ^(NSString *path) {
        if ([CCPathGuard isAllowedRoot:path] && !IsLink(path)) [found addObject:path];
    };
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *folder in @[ @"Application Support", @"Caches", @"Preferences", @"Preferences/ByHost", @"Saved Application State", @"Logs",
                                @"HTTPStorages", @"WebKit", @"Containers", @"Application Scripts", @"Cookies", @"LaunchAgents" ]) {
        NSString *base = [library stringByAppendingPathComponent:folder];
        for (NSString *name in [fm contentsOfDirectoryAtPath:base error:nil])
            if (NamedAfterId(name, identifier) && !othersOwn(name)) add([base stringByAppendingPathComponent:name]);
    }
    // Group containers carry a team or "group." in front of the id.
    NSString *groups = [library stringByAppendingPathComponent:@"Group Containers"];
    NSString *suffix = [@"." stringByAppendingString:identifier.lowercaseString];
    for (NSString *name in [fm contentsOfDirectoryAtPath:groups error:nil])
        if ([name.lowercaseString hasSuffix:suffix]) add([groups stringByAppendingPathComponent:name]);

    // By name: only the exact name, only where apps keep folders under it, and never one another app is called.
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSetWithObject:appPath.lastPathComponent.stringByDeletingPathExtension];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if ([info[@"CFBundleName"] isKindOfClass:NSString.class]) [names addObject:info[@"CFBundleName"]];
    for (NSString *folder in @[ @"Application Support", @"Caches", @"Logs" ]) {
        NSString *base = [library stringByAppendingPathComponent:folder];
        NSArray *present = [fm contentsOfDirectoryAtPath:base error:nil];
        for (NSString *name in names) {
            if (name.length < 3 || [otherNames containsObject:name.lowercaseString]) continue;
            for (NSString *item in present)
                if ([item caseInsensitiveCompare:name] == NSOrderedSame) add([base stringByAppendingPathComponent:item]);
            // "Google Chrome" keeps its data in Google/Chrome; the vendor's folder itself stays.
            NSRange space = [name rangeOfString:@" "];
            if (space.location != NSNotFound && space.location > 0) {
                NSString *inner = [[base stringByAppendingPathComponent:[name substringToIndex:space.location]]
                                   stringByAppendingPathComponent:[name substringFromIndex:space.location + 1]];
                if ([fm fileExistsAtPath:inner]) add(inner);
            }
        }
    }
    return found.array;
}

+ (BOOL)moveToTrash:(NSString *)path { return MoveToTrash(path); }

@end

static BOOL EntryCanDelete(CCSpaceEntry *e) {
    return e.risk != CCSpaceRiskKeep && !e.command && !e.targetId && !e.needsAccess && e.paths.count == 1
        && [CCPathGuard isAllowedRoot:e.paths.firstObject];
}

@implementation CCDiskMapEngine

+ (long long)measure:(NSString *)path excluding:(NSSet<NSString *> *)excluded cancel:(CCCancelToken *)cancel unreadable:(BOOL *)unreadable {
    return MeasureTree(path, excluded ?: [NSSet set], nil, ClusterSizeAt(path), cancel, unreadable);
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
    BOOL (^included)(NSString *) = ^BOOL(NSString *p) { return !scope.includes || scope.includes(p); };

    // 0. Folders that are never entered (other apps' containers), and without Full Disk Access the guarded ones.
    NSMutableSet<NSString *> *guarded = [NSMutableSet set], *private = [NSMutableSet set];
    for (NSString *pattern in scope.skipped) [claimed addObjectsFromArray:ExpandFolders(pattern)];
    for (NSString *pattern in scope.guarded) [private addObjectsFromArray:ExpandFolders(pattern)];
    if (!scope.hasFullDiskAccess) [guarded unionSet:private];

    // A part or listed folder of a known item that is also a cleaner target's root is cleaned as that target, from
    // Overview, so the Disk page and Overview never offer the same bytes twice.
    NSMutableDictionary<NSString *, NSString *> *targetOfRoot = [NSMutableDictionary dictionary];
    for (CCTarget *target in targets)
        for (NSString *root in [target resolveRoots]) targetOfRoot[root] = target.identifier;

    // 1. Known items and their parts.
    for (CCSpaceRule *rule in scope.rules) {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (NSString *pattern in rule.paths)
            for (NSString *p in ExpandFolders(pattern))
                if (included(p) && !taken(p) && ![paths containsObject:p]) [paths addObject:p];
        if (paths.count == 0) continue;
        [claimed addObjectsFromArray:paths];

        CCSpaceEntry *entry = SpaceEntry(rule.identifier, rule.segment, rule.risk, rule.symbol,
                                         [@"space." stringByAppendingString:rule.identifier], nil, paths);
        entry.command = rule.command;
        entry.needsAccess = rule.needsFullDiskAccess && !scope.hasFullDiskAccess;
        for (NSString *root in paths) {
            if (entry.needsAccess) break;
            for (CCSpacePart *part in rule.parts)
                for (NSString *p in ExpandFolders([root stringByAppendingPathComponent:part.pattern])) {
                    CCSpaceEntry *child = SpaceEntry([NSString stringWithFormat:@"%@/%@", rule.identifier, part.pattern], rule.segment,
                                                     part.risk, rule.symbol, [@"space.kind." stringByAppendingString:part.kind], nil, @[ p ]);
                    child.targetId = targetOfRoot[p] ?: targetOfRoot[[CCPathGuard normalize:p]];
                    [entry.children addObject:child];
                }
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
            // Apps are listed one row per app bundle, wherever it sits in the Applications folders (Utilities, a vendor's folder).
            if ([rule.listKind isEqualToString:@"app"]) {
                [listed removeAllObjects];
                for (NSString *app in [CCAppLeftovers installedApps]) {
                    NSString *real = [CCPathGuard normalize:app];
                    if ([claimed containsObject:real] || IsLink(app)) continue;
                    BOOL inside = NO;
                    for (NSString *root in paths) inside |= IsInsidePath(real, root);
                    if (!inside) continue;
                    [listed addObject:real];
                    names[real] = app.lastPathComponent;
                }
            }
            // One match is the item itself, not a part of it.
            if (listed.count == 1 && paths.count == 1 && [listed.firstObject isEqualToString:paths.firstObject]) [listed removeAllObjects];
            for (NSString *p in listed) {
                CCSpaceEntry *child = SpaceEntry([NSString stringWithFormat:@"%@/%@", rule.identifier, names[p]], rule.segment, rule.risk,
                                                 rule.symbol, [@"space.kind." stringByAppendingString:rule.listKind], names[p], @[ p ]);
                child.targetId = targetOfRoot[p] ?: targetOfRoot[[CCPathGuard normalize:p]];
                [entry.children addObject:child];
            }
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
        if (!included(root) || taken(root) || [guarded containsObject:root] || IsLink(root)) continue;
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
                // A root filed as Your files (the home folder, a drive's root) holds the user's own folders, except those
                // the scope files elsewhere and dot folders, which are tools' data.
                BOOL isDot = [dir.lastPathComponent hasPrefix:@"."];
                BOOL isPersonal = [personal containsObject:dir] || (root.segment == CCSpaceFiles && !isDot && !filed[dir]);
                // Mail, Messages, Safari and the like stay out of the list (and in "System and other") until they can be read.
                if ([guarded containsObject:dir] && !isPersonal) continue;
                CCSpaceSegment band = isPersonal ? CCSpaceFiles : filed[dir] ? (CCSpaceSegment)filed[dir].integerValue
                                    : root.segment == CCSpaceFiles ? CCSpaceOther : root.segment;
                BOOL keep = root.keep || [scope.keepNames containsObject:dir.lastPathComponent];
                CCSpaceEntry *entry = discovered(dir, band, isPersonal, keep);
                if ([containers containsObject:dir] && !entry.needsAccess)
                    for (NSString *sub in SubFolders(dir))
                        if (![claimed containsObject:sub] && ![guarded containsObject:sub])
                            [entry.children addObject:discovered(sub, band, isPersonal, keep)];
                [entries addObject:entry];
                [claimed addObject:dir];
            }
        }
    }
    // Files lying at a drive's root are its owner's too; without them they would pass for lost space.
    CCSpaceEntry *loose = nil;
    if (scope.looseFilesRoot) {
        long long sum = 0;
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:scope.looseFilesRoot error:nil]) {
            struct stat st;
            NSString *path = [scope.looseFilesRoot stringByAppendingPathComponent:name];
            if (lstat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode)) sum += OnDisk(&st, scope.clusterSize);
        }
        if (sum > 0) {
            loose = SpaceEntry(@"loose", CCSpaceFiles, CCSpaceRiskKeep, scope.personalSymbol, @"space.personal",
                               scope.looseFilesRoot.lastPathComponent, @[]);
            loose.bytes = sum;
            [entries addObject:loose];
        }
    }
    // What the System band holds on the startup disk, so it is not one unexplained number.
    NSMutableSet<CCSpaceEntry *> *known = [NSMutableSet set];
    if (loose) [known addObject:loose];
    if (scope.listsSystemSpace) {
        NSDictionary<NSString *, NSNumber *> *sizes = SystemVolumes();
        if (sizes.count) {
            CCSpaceEntry *volumes = SpaceEntry(@"mac.sysvolumes", CCSpaceSystem, CCSpaceRiskKeep, @"laptopcomputer", @"space.mac.sysvolumes", nil, @[]);
            for (NSString *name in sizes) {
                [volumes.children addObject:SpaceEntry([@"mac.sysvolumes/" stringByAppendingString:name], CCSpaceSystem, CCSpaceRiskKeep,
                                                       @"laptopcomputer", nil, name, @[])];
                volumes.children.lastObject.bytes = sizes[name].longLongValue;
                volumes.bytes += sizes[name].longLongValue;
            }
            [known addObject:volumes];
            [entries addObject:volumes];
        }
        NSMutableArray<NSString *> *folders = [NSMutableArray array];
        for (NSString *p in @[ @"/Library", @"/private", @"/opt", @"/usr/local" ]) [folders addObjectsFromArray:ExpandFolders(p)];
        if (folders.count)
            [entries addObject:SpaceEntry(@"mac.sysfolders", CCSpaceSystem, CCSpaceRiskKeep, @"gearshape", @"space.mac.sysfolders", nil, folders)];
        // Other apps' containers are opened only with the access that lets the app read them without macOS asking.
        if (scope.hasFullDiskAccess) {
            NSMutableArray<NSString *> *containers = [NSMutableArray array];
            for (NSString *pattern in scope.skipped) [containers addObjectsFromArray:ExpandFolders(pattern)];
            if (containers.count)
                [entries addObject:SpaceEntry(@"mac.appcontainers", CCSpaceSystem, CCSpaceRiskKeep, @"shippingbox", @"space.mac.appcontainers", nil, containers)];
        }
    }
    // Guarded folders are left out of whatever holds them, measured or not.
    if (!scope.hasFullDiskAccess) [claimed unionSet:guarded];

    // 4. Measure every entry and part, skipping what another entry owns.
    NSMutableArray<CCSpaceEntry *> *all = [NSMutableArray array];
    NSMapTable<CCSpaceEntry *, NSSet<NSString *> *> *siblings = [NSMapTable strongToStrongObjectsMapTable];
    for (CCSpaceEntry *e in entries) {
        if (e.needsAccess || [known containsObject:e]) continue;
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
        for (NSString *p in entry.paths) bytes += MeasureTree(p, excluded, entry.excludedNames, scope.clusterSize, cancel, &unreadable);
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
            c.uninstallable = [e.identifier isEqualToString:@"mac.applications"] && [CCAppLeftovers canUninstall:c.path];
            for (CCSpaceEntry *g in c.children) g.canDelete = EntryCanDelete(g);
        }
    }
    [entries filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CCSpaceEntry *e, NSDictionary *b) { return e.bytes > 0 || e.needsAccess; }]];
    [entries sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
    [report.items addObjectsFromArray:entries];
    for (CCSpaceEntry *e in entries) report.segments[e.segment] += e.bytes;
    // Used but not measured: the operating system, swap, snapshots and whatever could not be read.
    long long unaccounted = MAX(0, report.used - report.measured);
    report.segments[CCSpaceSystem] += unaccounted;
    if (scope.namesUnaccounted && unaccounted > 0) {
        // Without Full Disk Access this is mostly the closed folders; with it, what macOS itself keeps out of reach.
        BOOL closed = scope.listsSystemSpace && !scope.hasFullDiskAccess;
        CCSpaceEntry *row = closed ? SpaceEntry(@"mac.noaccess", CCSpaceSystem, CCSpaceRiskKeep, @"lock.shield", @"space.mac.noaccess", nil, @[])
                                   : SpaceEntry(@"unknown", CCSpaceSystem, CCSpaceRiskKeep, @"questionmark.circle", @"space.unknown", nil, @[]);
        row.bytes = unaccounted;
        NSUInteger at = 0;
        while (at < report.items.count && report.items[at].bytes >= unaccounted) at++;
        [report.items insertObject:row atIndex:at];
    }
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
    long long left = MeasureTree(path, [NSSet set], nil, ClusterSizeAt(path), nil, NULL);
    return MAX(0, entry.bytes - left);
}

@end
