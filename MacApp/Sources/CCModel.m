#import "CCModel.h"
#import <Cocoa/Cocoa.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <unistd.h>

NSNotificationName const CCModelDidChangeNotification = @"CCModelDidChange";
NSNotificationName const CCModelScanStateNotification = @"CCModelScanState";
NSNotificationName const CCModelCleanStateNotification = @"CCModelCleanState";
NSNotificationName const CCModelInsightsNotification = @"CCModelInsights";
NSNotificationName const CCModelPageNotification = @"CCModelPage";
NSNotificationName const CCModelToastNotification = @"CCModelToast";
NSNotificationName const CCModelCustomFoldersNotification = @"CCModelCustomFolders";
NSNotificationName const CCModelDetailsNotification = @"CCModelDetails";

static BOOL HasFullDiskAccess(void) {
    // The TCC database is readable only with Full Disk Access; it exists on every Mac.
    NSString *path = [CCHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/com.apple.TCC/TCC.db"];
    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return NO;
    close(fd);
    return YES;
}

@implementation CCTargetItem

- (instancetype)initWithTarget:(CCTarget *)target enabled:(BOOL)enabled {
    if ((self = [super init])) {
        _target = target;
        _identifier = target.identifier;
        _roots = [target resolveRoots];
        _isPresent = _roots.count > 0;
        _enabled = enabled && _isPresent;
        _topEntries = @[];
    }
    return self;
}

- (void)refreshPresence {
    _roots = [self.target resolveRoots];
    _isPresent = _roots.count > 0;
    if (!_isPresent) _enabled = NO;
}

- (NSString *)name { return self.target.displayName ?: L(self.target.nameKey); }
- (NSString *)details { return self.target.isCustom ? L(@"target.custom.desc") : L(self.target.descriptionKey); }
- (NSString *)riskText { return L([@"risk." stringByAppendingString:CCRiskName(self.target.risk)]); }
- (NSString *)riskHint { return L([NSString stringWithFormat:@"risk.%@.desc", CCRiskName(self.target.risk)]); }
- (BOOL)showsAccessBadge { return self.target.needsFullDiskAccess && !CCModel.shared.hasFullDiskAccess; }

- (NSString *)rootsText {
    if (self.roots.count == 0) return self.target.needsFullDiskAccess ? @"" : L(@"targets.notPresent");
    NSString *home = CCHomeDirectory();
    NSMutableArray *shown = [NSMutableArray array];
    for (NSString *root in self.roots)
        [shown addObject:[root hasPrefix:[home stringByAppendingString:@"/"]] ? [@"~" stringByAppendingString:[root substringFromIndex:home.length]] : root];
    return [shown componentsJoinedByString:@"   ·   "];
}

- (NSString *)statusText {
    switch (self.state) {
        case CCTargetScanning: return L(@"targets.scanning");
        case CCTargetDenied: return L(@"targets.needsAdmin");
        case CCTargetError: return LF(@"targets.error", self.error ?: @"");
        case CCTargetDone:
            if (self.target.sharesBlocks && self.lastResult.sharedBytes > 0 && self.fileCount > 0)
                return LF(@"targets.shared", CCFormatBytes(self.lastResult.sharedBytes));
            return self.bytes == 0 ? L(@"targets.empty") : @"";
        case CCTargetIdle: return self.isPresent ? L(@"targets.notScanned") : L(@"targets.notPresent");
    }
    return @"";
}

- (void)resetForScan {
    if (!self.isPresent) return;
    self.state = CCTargetScanning;
    self.bytes = 0;
    self.fileCount = 0;
    self.error = nil;
    self.topEntries = @[];
}

- (BOOL)isTrash { return self.target.alwaysPermanent; }

- (void)applyResult:(CCScanResult *)result {
    _hasLeftovers = NO;
    self.lastResult = result;
    if (result.roots.count) self.roots = result.roots;
    self.bytes = result.totalBytes;
    self.fileCount = result.fileCount;
    self.error = result.error;
    self.state = result.accessDenied && result.totalBytes == 0 ? CCTargetDenied
               : result.error && result.totalBytes == 0 ? CCTargetError
               : CCTargetDone;
    NSUInteger keep = MIN((NSUInteger)100, result.topEntries.count);
    self.topEntries = [result.topEntries subarrayWithRange:NSMakeRange(0, keep)];
}

- (void)applyClean:(CCTargetCleanResult *)clean {
    _hasLeftovers = clean.bytesRemaining > 0;
    self.bytes = clean.bytesRemaining;
    self.fileCount = clean.filesRemaining;
    self.topEntries = @[];
    if (clean.error) {
        self.error = clean.error;
        self.state = CCTargetError;
    }
}

@end

@implementation CCCategoryItem

- (instancetype)initWithCategory:(CCCategory)category {
    if ((self = [super init])) {
        _category = category;
        _targets = @[];
    }
    return self;
}

- (NSString *)name { return L([@"cat." stringByAppendingString:CCCategoryName(self.category)]); }

- (NSString *)symbol {
    switch (self.category) {
        case CCCategorySystem: return @"laptopcomputer";
        case CCCategoryBrowsers: return @"globe";
        case CCCategoryDeveloper: return @"curlybraces";
        case CCCategoryApps: return @"square.grid.2x2";
        case CCCategoryGaming: return @"gamecontroller";
        case CCCategoryCustom: return @"folder";
    }
    return @"folder";
}

- (void)recalc:(long long)grandTotal {
    long long bytes = 0, files = 0, selected = 0;
    NSInteger present = 0;
    BOOL anyEnabled = NO;
    for (CCTargetItem *t in self.targets) {
        // The Trash is shown on its own line of the dashboard, not as junk of its category.
        if (!t.isPresent || t.isTrash) continue;
        present++;
        bytes += t.bytes;
        files += t.fileCount;
        anyEnabled |= t.enabled;
        if (t.enabled) selected += t.bytes;
    }
    self.bytes = bytes;
    self.selectedBytes = selected;
    self.fileCount = files;
    self.presentCount = present;
    self.share = grandTotal > 0 ? (double)bytes / grandTotal : 0;
    self.enabled = anyEnabled;
}

@end

@implementation CCCleanLogItem
@end

@interface CCModel ()
@property (nonatomic, strong, readwrite) CCTargetItem *detailsTarget;
@property (nonatomic, readwrite) BOOL scanning, hasResults, nothingFound, overlayVisible, cleaning, cleanDone, cleanStopping, hasFullDiskAccess;
@property (nonatomic, readwrite) NSString *statusText, *currentTargetName, *cleanCurrent, *cleanSummary, *diskName;
@property (nonatomic, readwrite) long long displayBytes, foundBytes, selectedBytes, diskUsed, diskTotal, diskFree, lifetimeFreed, cleanFreed;
@property (nonatomic, readwrite) long long trashBytes;
@property (nonatomic, readwrite) NSInteger selectedCount, presentCount;
@property (nonatomic, readwrite) double ringAngle, cleanProgress;
@end

@implementation CCModel {
    NSMutableArray<CCTargetItem *> *_targets;
    NSMutableArray<CCCategoryItem *> *_categories;
    NSArray<CCTargetItem *> *_topTargets;
    NSArray<CCInsight *> *_insights;
    NSArray<CCStuckProcess *> *_stuck;
    NSMutableArray<CCCleanLogItem *> *_cleanLog;
    CCCancelToken *_scanToken;
    CCCancelToken *_cleanToken;
    /// Bytes found so far per target while scanning, so the counter only adds up selected targets.
    NSMutableDictionary<NSString *, NSNumber *> *_liveBytes;
    NSString *(^_status)(void);
    NSInteger _scanCompleted, _scanTotal;
    BOOL _suppressSave;
    BOOL _changePending;
}

+ (CCModel *)shared {
    static CCModel *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [CCModel new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _settings = [CCSettings load];
        _targets = [NSMutableArray array];
        _liveBytes = [NSMutableDictionary dictionary];
        _categories = [NSMutableArray array];
        _cleanLog = [NSMutableArray array];
        _topTargets = @[];
        _insights = @[];
        _stuck = @[];
        _searchText = @"";
        _filter = @"All";
        _statusText = @"";
        _currentTargetName = @"";
        _cleanCurrent = @"";
        _cleanSummary = @"";
        _diskName = @"Macintosh HD";
        _hasFullDiskAccess = HasFullDiskAccess();

        for (CCTarget *t in CCCatalog.allTargets) [_targets addObject:[self itemForTarget:t]];
        for (NSString *folder in _settings.customFolders) [_targets addObject:[self itemForTarget:[CCCatalog customTargetForFolder:folder]]];
        for (NSInteger c = 0; c < CCCategoryCount; c++) [_categories addObject:[[CCCategoryItem alloc] initWithCategory:c]];
        [self rebuildCategories];

        _lifetimeFreed = _settings.lifetimeBytesFreed;
        [self refreshDisk];
        [self setStatus:^NSString *{ return L(@"dash.notScanned"); }];
        [self recalc];

        [NSNotificationCenter.defaultCenter addObserverForName:CCLanguageDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            self.statusText = self->_status();
            [self changed];
        }];
    }
    return self;
}

- (NSArray<CCTargetItem *> *)targets { return _targets; }
- (NSArray<CCCategoryItem *> *)categories { return _categories; }
- (NSArray<CCTargetItem *> *)topTargets { return _topTargets; }
- (NSArray<CCInsight *> *)insights { return _insights; }
- (NSArray<CCStuckProcess *> *)stuckProcesses { return _stuck; }
- (NSArray<CCCleanLogItem *> *)cleanLog { return _cleanLog; }

- (CCSelectionMode)selectionMode { return CCSelectionModeFromName(self.settings.selectionMode); }

/// The tick a target gets in the current mode: from its risk, or what was set by hand.
- (BOOL)tickFor:(CCTarget *)target {
    if (self.selectionMode != CCSelectionManual) return CCAutoSelects(target, self.selectionMode);
    NSNumber *saved = self.settings.targetStates[target.identifier];
    // A target never ticked or unticked by hand (one added in a later version) gets what Safe mode would give it.
    return saved ? saved.boolValue : CCAutoSelects(target, CCSelectionSafe);
}

- (CCTargetItem *)itemForTarget:(CCTarget *)target {
    return [[CCTargetItem alloc] initWithTarget:target enabled:[self tickFor:target]];
}

- (void)applySelection {
    for (CCTargetItem *t in _targets) t.enabled = t.isPresent && [self tickFor:t.target];
}

- (void)setSelectionMode:(CCSelectionMode)mode {
    self.settings.selectionMode = CCSelectionModeName(mode);
    [self applySelection];
    [self saveSettings];
    [self recalc];
    [self changed];
}

/// Before a change by hand: what the app picked becomes the starting point of the user's own choice.
- (void)leaveAutoSelection {
    CCSelectionMode mode = self.selectionMode;
    if (mode == CCSelectionManual) return;
    for (CCTargetItem *t in _targets)
        self.settings.targetStates[t.identifier] = @(t.isPresent ? t.enabled : CCAutoSelects(t.target, mode));
    self.settings.selectionMode = CCSelectionModeName(CCSelectionManual);
}

- (void)includeTarget:(NSString *)identifier {
    CCTargetItem *item = [self itemWithId:identifier];
    if (!item) return;
    if (!item.isPresent) [item refreshPresence];
    if (!item.isPresent || item.enabled) return;
    [self setTarget:item enabled:YES];
}

- (void)cleanFromDisk:(NSString *)targetId {
    if (targetId) [self includeTarget:targetId];
    self.page = CCPageDashboard;
    CCTargetItem *item = targetId ? [self itemWithId:targetId] : nil;
    if (!self.scanning && !self.cleaning && (!self.hasResults || (item && !item.lastResult))) [self startScan];
}

- (void)rebuildCategories {
    for (CCCategoryItem *c in _categories)
        c.targets = [_targets filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CCTargetItem *t, NSDictionary *b) {
            return t.target.category == c.category;
        }]];
}

// Several changes in one run-loop turn become one notification.
- (void)changed {
    if (_changePending) return;
    _changePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_changePending = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:CCModelDidChangeNotification object:self];
    });
}

- (void)post:(NSNotificationName)name {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:self];
}

- (void)setStatus:(NSString * (^)(void))status {
    _status = [status copy];
    self.statusText = status();
}

- (void)setPage:(CCPage)page {
    if (_page == page) return;
    _page = page;
    [self post:CCModelPageNotification];
}

- (void)setSearchText:(NSString *)searchText {
    _searchText = [searchText copy];
    [self changed];
}

- (void)setFilter:(NSString *)filter {
    _filter = [filter copy];
    [self changed];
}

- (BOOL)targetMatchesFilter:(CCTargetItem *)t {
    if (![self.filter isEqualToString:@"All"] && ![CCCategoryName(t.target.category) isEqualToString:self.filter]) return NO;
    NSString *q = [self.searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (q.length == 0) return YES;
    NSStringCompareOptions o = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    return [t.name rangeOfString:q options:o].location != NSNotFound || [t.details rangeOfString:q options:o].location != NSNotFound
        || [t.rootsText rangeOfString:q options:o].location != NSNotFound;
}

/// Selected targets with something in them. What a clean could not remove is left out until the next scan: pressing
/// Clean again would not remove it either.
- (NSArray<CCTargetItem *> *)selectable {
    NSMutableArray<CCTargetItem *> *list = [NSMutableArray array];
    for (CCTargetItem *t in _targets) {
        // Clones that share all their blocks free nothing today, but they are still junk: removed with the rest.
        BOOL hasSomething = t.bytes > 0 || (t.target.sharesBlocks && t.fileCount > 0);
        if (t.isPresent && t.enabled && t.lastResult && hasSomething && !t.hasLeftovers) [list addObject:t];
    }
    return list;
}

- (long long)cleanableBytes {
    long long sum = 0;
    for (CCTargetItem *t in [self selectable]) sum += t.bytes;
    return sum;
}

- (BOOL)onlyTrashLeft {
    NSArray<CCTargetItem *> *list = [self selectable];
    if (list.count == 0) return NO;
    for (CCTargetItem *t in list)
        if (!t.isTrash) return NO;
    return YES;
}

- (BOOL)showsTrashLine { return self.trashBytes > 0 && !(self.onlyTrashLeft && !self.scanning); }

- (NSString *)trashLine {
    for (CCTargetItem *t in _targets)
        if (t.isTrash && t.enabled) return [NSString stringWithFormat:@"%@: %@", t.name, CCFormatBytes(self.trashBytes)];
    return LF(@"dash.binLine", CCFormatBytes(self.trashBytes));
}

- (NSString *)ringCaption {
    if (self.scanning || self.diskTotal <= 0 || self.displayBytes <= 0) return L(@"dash.reclaimable");
    double percent = 100.0 * self.displayBytes / self.diskTotal;
    NSString *share = percent < 0.1 ? @"<0.1%" : percent < 10 ? [CCFormatDecimal(percent) stringByAppendingString:@"%"] : [NSString stringWithFormat:@"%.0f%%", percent];
    NSString *caption = LF(@"dash.ofDisk", share, CCFormatBytes(self.diskTotal));
    return self.onlyTrashLeft ? [NSString stringWithFormat:@"%@ · %@", caption, L(@"dash.inBin")] : caption;
}

- (BOOL)canClean { return self.hasResults && !self.scanning && !self.cleaning && [self selectable].count > 0; }

// ───────────── scanning ─────────────

- (void)toggleScan {
    if (self.scanning) [self cancelScan];
    else [self startScan];
}

- (void)cancelScan { [_scanToken cancel]; }

- (void)startScan {
    if (self.scanning || self.cleaning) return;
    [self refreshAccess];
    CCCancelToken *token = [CCCancelToken new];
    _scanToken = token;
    self.scanning = YES;
    self.hasResults = NO;
    self.nothingFound = NO;
    self.displayBytes = 0;
    [_liveBytes removeAllObjects];
    _scanCompleted = 0;
    NSMutableArray<CCTarget *> *targets = [NSMutableArray array];
    NSMutableSet<NSString *> *allRoots = [NSMutableSet set];
    for (CCTargetItem *t in _targets) [t refreshPresence];
    [self applySelection];
    for (CCTargetItem *t in _targets) {
        [t resetForScan];
        if (t.isPresent) [targets addObject:t.target];
        [allRoots addObjectsFromArray:[t.target resolveRoots]];
    }
    _scanTotal = (NSInteger)targets.count;
    self.currentTargetName = @"";
    [self recalc];
    __weak CCModel *weakSelf = self;
    [self setStatus:^NSString *{
        CCModel *s = weakSelf;
        return LF(@"dash.scanningProgress", @(s->_scanCompleted), @(s->_scanTotal));
    }];
    [self post:CCModelScanStateNotification];

    CCScanOptions *options = [CCScanOptions new];
    options.skipNewerThanHours = self.settings.skipRecentHours;
    options.excludedRoots = allRoots;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [[CCScanEngine new] scanTargets:targets options:options cancel:token progress:^(CCScanEvent *event) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf onScanEvent:event]; });
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishScan:token seconds:CFAbsoluteTimeGetCurrent() - start count:targets.count];
        });
    });
}

- (CCTargetItem *)itemWithId:(NSString *)identifier {
    for (CCTargetItem *t in _targets)
        if ([t.identifier isEqualToString:identifier]) return t;
    return nil;
}

- (void)onScanEvent:(CCScanEvent *)event {
    if (!self.scanning) return;
    if (event.phase != CCScanPhaseStarted) _liveBytes[event.targetId] = @(event.targetBytes);
    self.displayBytes = [self selectedLiveBytes];
    [self updateRingAngle];
    _scanCompleted = MAX(_scanCompleted, event.completed);
    self.statusText = _status();
    CCTargetItem *item = [self itemWithId:event.targetId];
    if (event.phase == CCScanPhaseStarted && item) self.currentTargetName = item.name;
    if (event.result && item) {
        [item applyResult:event.result];
        [self recalc];
    }
    [self changed];
}

- (void)finishScan:(CCCancelToken *)token seconds:(double)seconds count:(NSUInteger)count {
    if (token != _scanToken) return;
    BOOL cancelled = token.isCancelled;
    _scanToken = nil;
    self.scanning = NO;
    for (CCTargetItem *t in _targets)
        if (t.state == CCTargetScanning) t.state = CCTargetIdle;
    [self recalc];
    self.hasResults = !cancelled;
    self.nothingFound = !cancelled && self.foundBytes == 0;
    if (cancelled) {
        [self setStatus:^NSString *{ return L(@"dash.cancelled"); }];
    } else {
        long long files = 0;
        for (CCTargetItem *t in _targets) files += t.isPresent ? t.fileCount : 0;
        [self setStatus:^NSString *{ return LF(@"dash.lastScan", @(count), CCFormatDecimal(seconds), CCFormatCount(files)); }];
    }
    [self post:CCModelScanStateNotification];
    if (!cancelled) [self refreshInsights];
    [self changed];
}

// ───────────── cleaning ─────────────

- (void)clean {
    if (self.scanning || self.cleaning) return;
    NSArray<CCTargetItem *> *selected = [self selectable];
    if (selected.count == 0) return;
    long long bytes = 0, files = 0;
    for (CCTargetItem *t in selected) {
        bytes += t.bytes;
        files += t.fileCount;
    }
    // Caches and temporary files are deleted for good, like every cleaner does: apps rebuild them, and in the Trash they
    // would free nothing. The Trash setting is for what is removed by hand.
    BOOL emptyingTrash = self.onlyTrashLeft;
    NSString *title = LF(emptyingTrash ? @"clean.binTitle" : @"clean.confirmTitle", CCFormatBytes(bytes));
    NSString *body = emptyingTrash ? LF(@"clean.binBody", CCFormatCount(files)) : LF(@"clean.confirmPermanent", CCFormatCount(files), @(selected.count));
    void (^go)(BOOL) = ^(BOOL ok) {
        if (ok) [self runClean:selected trash:NO];
    };
    if (self.confirm && self.settings.confirmClean) self.confirm(title, body, L(emptyingTrash ? @"clean.binConfirm" : @"clean.confirm"), emptyingTrash, go);
    else go(YES);
}

- (void)runClean:(NSArray<CCTargetItem *> *)selected trash:(BOOL)trash {
    self.cleaning = YES;
    self.cleanDone = NO;
    self.cleanStopping = NO;
    self.cleanFreed = 0;
    self.cleanProgress = 0;
    self.cleanCurrent = @"";
    self.cleanSummary = @"";
    [_cleanLog removeAllObjects];
    self.overlayVisible = YES;
    [self post:CCModelCleanStateNotification];
    [self changed];

    NSMutableArray<CCScanResult *> *scans = [NSMutableArray array];
    for (CCTargetItem *t in selected) [scans addObject:t.lastResult];
    CCCleanOptions *options = [CCCleanOptions new];
    options.useTrash = trash;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    __weak CCModel *weakSelf = self;
    CCCancelToken *token = [CCCancelToken new];
    _cleanToken = token;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CCCleanReport *report = [[CCCleanEngine new] clean:scans options:options cancel:token progress:^(CCCleanEvent *event) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf onCleanEvent:event]; });
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishClean:report seconds:CFAbsoluteTimeGetCurrent() - start]; });
    });
}

- (void)onCleanEvent:(CCCleanEvent *)event {
    if (!self.cleaning) return;
    self.cleanFreed = event.bytesFreed;
    self.cleanProgress = event.targetsTotal > 0 ? (double)event.targetsDone / event.targetsTotal : 0;
    CCTargetItem *item = [self itemWithId:event.targetId];
    if (item) self.cleanCurrent = LF(@"clean.current", item.name);
    if (event.targetDone && event.targetResult && item) {
        [item applyClean:event.targetResult];
        CCCleanLogItem *log = [CCCleanLogItem new];
        log.name = item.name;
        log.bytes = event.targetResult.bytesFreed;
        log.failed = event.targetResult.failed;
        [_cleanLog insertObject:log atIndex:0];
    }
    [self changed];
}

- (void)finishClean:(CCCleanReport *)report seconds:(double)seconds {
    self.cleanProgress = 1;
    self.cleanFreed = report.bytesFreed;
    self.cleanCurrent = @"";
    BOOL stopped = report.cancelled;
    _cleanToken = nil;
    self.cleanSummary = stopped ? LF(@"clean.stopped", CCFormatCount(report.filesDeleted))
        : report.failed > 0
        ? LF(@"clean.summary", CCFormatCount(report.filesDeleted), CCFormatCount(report.failed))
        : LF(@"clean.summaryOk", CCFormatCount(report.filesDeleted), CCFormatDecimal(seconds));
    self.settings.lifetimeBytesFreed += report.bytesFreed;
    self.lifetimeFreed = self.settings.lifetimeBytesFreed;
    [self saveSettings];
    self.cleaning = NO;
    self.cleanDone = YES;
    [self recalc];
    [self refreshDisk];
    long long freed = report.bytesFreed;
    [self setStatus:^NSString *{ return LF(@"dash.cleaned", CCFormatBytes(freed)); }];
    [self post:CCModelCleanStateNotification];
    [self changed];
}

- (void)cancelClean {
    if (!self.cleaning || self.cleanStopping) return;
    self.cleanStopping = YES;
    [_cleanToken cancel];
    [self changed];
}

- (void)closeCleanOverlay {
    self.overlayVisible = NO;
    [self post:CCModelCleanStateNotification];
    if (self.cleanDone && self.cleanFreed > 0)
        [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:self
                                                        userInfo:@{ @"symbol": @"checkmark", @"text": LF(@"toast.freed", CCFormatBytes(self.cleanFreed)) }];
    [self refreshInsights];
}

// ───────────── selection ─────────────

- (void)bulkSelect:(BOOL (^)(CCTargetItem *t))predicate {
    [self leaveAutoSelection];
    for (CCTargetItem *t in _targets) {
        t.enabled = t.isPresent && predicate(t);
        self.settings.targetStates[t.identifier] = @(t.enabled);
    }
    [self saveSettings];
    [self recalc];
    [self changed];
}

- (long long)selectedLiveBytes {
    long long sum = 0;
    for (CCTargetItem *t in _targets)
        if (t.enabled) sum += [_liveBytes[t.identifier] longLongValue];
    return sum;
}

- (void)selectNone { [self bulkSelect:^BOOL(CCTargetItem *t) { return NO; }]; }

- (void)setTarget:(CCTargetItem *)target enabled:(BOOL)enabled {
    [self leaveAutoSelection];
    target.enabled = enabled && target.isPresent;
    self.settings.targetStates[target.identifier] = @(target.enabled);
    [self saveSettings];
    [self recalc];
    [self changed];
}

- (void)setCategory:(CCCategoryItem *)category enabled:(BOOL)enabled {
    [self bulkSelect:^BOOL(CCTargetItem *t) {
        if (t.target.category != category.category) return t.enabled;
        return enabled && (t.target.risk != CCRiskCareful || t.enabled);
    }];
}

- (void)openCategory:(CCCategoryItem *)category {
    self.filter = CCCategoryName(category.category);
    self.page = CCPageTargets;
}

- (void)toggleExpanded:(CCTargetItem *)target {
    target.expanded = !target.expanded;
    [self changed];
}

// ───────────── details ─────────────

- (void)openDetails:(CCTargetItem *)target {
    self.detailsTarget = target;
    [self post:CCModelDetailsNotification];
}

- (void)closeDetails {
    if (!self.detailsTarget) return;
    self.detailsTarget = nil;
    [self post:CCModelDetailsNotification];
}

- (void)revealPath:(NSString *)path {
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
}

- (void)deleteEntry:(CCEntry *)entry ofTarget:(CCTargetItem *)target completion:(void (^)(BOOL))completion {
    CCScanResult *scan = target.lastResult;
    if (!scan || self.scanning || self.cleaning) {
        completion(NO);
        return;
    }
    CCCleanOptions *options = [CCCleanOptions new];
    options.useTrash = self.settings.useTrash;
    BOOL trash = options.useTrash && !target.target.alwaysPermanent;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CCTargetCleanResult *result = [[CCCleanEngine new] removeEntry:entry fromScan:scan options:options];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!result) {
                completion(NO);
                return;
            }
            target.bytes = result.bytesRemaining;
            target.fileCount = result.filesRemaining;
            NSUInteger keep = MIN((NSUInteger)100, scan.topEntries.count);
            target.topEntries = [scan.topEntries subarrayWithRange:NSMakeRange(0, keep)];
            self.settings.lifetimeBytesFreed += result.bytesFreed;
            self.lifetimeFreed = self.settings.lifetimeBytesFreed;
            [self saveSettings];
            [self recalc];
            [self refreshDisk];
            NSString *text = LF(trash ? @"details.trashed" : @"details.deleted", entry.name, CCFormatBytes(result.bytesFreed));
            [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:self
                                                            userInfo:@{ @"symbol": @"checkmark", @"text": text }];
            [self changed];
            completion(YES);
        });
    });
}

/// The ring is the share of the whole disk, live while scanning; a sliver stays visible however small the share.
- (void)updateRingAngle {
    self.ringAngle = self.diskTotal > 0 && self.displayBytes > 0 ? MAX(4, 360.0 * self.displayBytes / self.diskTotal) : 0;
}

- (void)recalc {
    long long found = 0, selectedBytes = 0, maxBytes = 0, trash = 0;
    NSInteger selected = 0, present = 0;
    for (CCTargetItem *t in _targets) {
        if (!t.isPresent) continue;
        present++;
        found += t.bytes;
        if (t.isTrash) trash += t.bytes;
        maxBytes = MAX(maxBytes, t.bytes);
        if (t.enabled) {
            selected++;
            selectedBytes += t.bytes;
        }
    }
    self.foundBytes = found;
    self.selectedBytes = selectedBytes;
    self.selectedCount = selected;
    self.presentCount = present;
    self.trashBytes = trash;
    for (CCCategoryItem *c in _categories) [c recalc:found - trash];
    self.displayBytes = self.scanning ? [self selectedLiveBytes] : self.cleanableBytes;
    [self updateRingAngle];
    for (CCTargetItem *t in _targets) t.share = maxBytes > 0 ? (double)t.bytes / maxBytes : 0;

    NSArray *present6 = [[_targets filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isPresent == YES AND bytes > 0"]]
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"bytes" ascending:NO] ]];
    _topTargets = [present6 subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)6, present6.count))];
}

// ───────────── disk, access, insights ─────────────

- (void)refreshDisk {
    NSURL *home = [NSURL fileURLWithPath:CCHomeDirectory()];
    NSDictionary *v = [home resourceValuesForKeys:@[ NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey,
                                                     NSURLVolumeAvailableCapacityKey, NSURLVolumeLocalizedNameKey ] error:nil];
    long long total = [v[NSURLVolumeTotalCapacityKey] longLongValue];
    long long available = [v[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue] ?: [v[NSURLVolumeAvailableCapacityKey] longLongValue];
    self.diskTotal = total;
    self.diskFree = available;
    self.diskUsed = MAX(0, total - available);
    if ([v[NSURLVolumeLocalizedNameKey] length]) self.diskName = v[NSURLVolumeLocalizedNameKey];
    [self changed];
}

- (void)addFreed:(long long)bytes {
    if (bytes <= 0) return;
    self.settings.lifetimeBytesFreed += bytes;
    self.lifetimeFreed = self.settings.lifetimeBytesFreed;
    [self saveSettings];
    [self refreshDisk];
}

- (void)refreshAccess {
    BOOL access = HasFullDiskAccess();
    if (access == self.hasFullDiskAccess) return;
    self.hasFullDiskAccess = access;
    [self changed];
}

- (void)openFullDiskAccessSettings {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]];
}

- (void)askForFullDiskAccessDeclined:(void (^)(void))declined {
    [self refreshAccess];
    if (self.hasFullDiskAccess || !self.confirm) return;
    self.confirmSymbol = @"lock.shield";
    self.confirm(L(@"access.ask.title"), L(@"access.ask.body"), L(@"titlebar.runAsAdmin"), NO, ^(BOOL ok) {
        if (ok) [self openFullDiskAccessSettings];
        else if (declined) declined();
    });
}

- (void)refreshInsights {
    BOOL trashEnabled = NO;
    for (CCTargetItem *t in _targets)
        if (t.target.alwaysPermanent && t.enabled) trashEnabled = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *found = [CCInsights scanWithTrashTargetEnabled:trashEnabled];
        NSArray *stuck = [CCProcesses stuckIn:[CCProcesses snapshot] hermesIdleMinutes:[CCProcesses hermesIdleMinutes]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_insights = found;
            self->_stuck = stuck;
            [self post:CCModelInsightsNotification];
            [self changed];
        });
    });
}

- (void)runInsightAction:(CCInsight *)insight {
    if (insight.action == CCInsightActionCopyCommand && insight.payload) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:insight.payload forType:NSPasteboardTypeString];
        [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:self
                                                        userInfo:@{ @"symbol": @"doc.on.doc", @"text": LF(@"insight.copied", insight.payload) }];
    } else if (insight.action == CCInsightActionOpenURL && insight.payload) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:insight.payload]];
    }
}

- (BOOL)canTerminate:(CCStuckProcess *)process {
    return process.kind != CCStuckHermesTab || [CCProcesses hermesStopScript] != nil;
}

- (void)terminateStuck:(CCStuckProcess *)process {
    if (![self canTerminate:process]) return;
    NSString *what = L([NSString stringWithFormat:@"stuck.%@.name", process.kindName]);
    void (^go)(BOOL) = ^(BOOL ok) {
        if (!ok) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            // Hermes' Chrome is closed by its own script, which waits for whoever is using it; a tab is never killed.
            if (process.kind == CCStuckHermesTab) [CCProcesses stopHermesBecause:@"JunkCleanup: Hermes tab is stuck"];
            else [CCProcesses terminate:@[ @(process.pid) ]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:self
                                                                userInfo:@{ @"symbol": @"checkmark", @"text": LF(@"stuck.done", what) }];
                [self refreshInsights];
            });
        });
    };
    if (self.confirm) {
        self.confirmSymbol = @"xmark.octagon";
        self.confirm(LF(@"stuck.confirmTitle", what), L([NSString stringWithFormat:@"stuck.%@.confirm", process.kindName]), L(@"stuck.terminate"), YES, go);
    } else {
        go(YES);
    }
}

// ───────────── settings ─────────────

- (void)saveSettings {
    if (_suppressSave) return;
    [self.settings save];
}

- (void)addCustomFolder:(NSString *)folder refused:(void (^)(void))refused {
    NSString *normalized = [CCPathGuard normalize:folder];
    if (![CCPathGuard isAllowedRoot:normalized]) {
        if (refused) refused();
        return;
    }
    NSString *identifier = [CCCatalog customIdForFolder:normalized];
    if ([self itemWithId:identifier]) return;
    [self.settings.customFolders addObject:normalized];
    CCTargetItem *item = [self itemForTarget:[CCCatalog customTargetForFolder:normalized]];
    item.enabled = item.isPresent;
    self.settings.targetStates[identifier] = @(item.enabled);
    [_targets addObject:item];
    [self rebuildCategories];
    [self saveSettings];
    [self recalc];
    [self post:CCModelCustomFoldersNotification];
    [self changed];
}

- (void)removeCustomFolder:(NSString *)folder {
    NSString *identifier = [CCCatalog customIdForFolder:folder];
    CCTargetItem *item = [self itemWithId:identifier];
    [self.settings.customFolders removeObject:folder];
    [self.settings.targetStates removeObjectForKey:identifier];
    if (item) [_targets removeObject:item];
    [self rebuildCategories];
    [self saveSettings];
    [self recalc];
    [self post:CCModelCustomFoldersNotification];
    [self changed];
}

- (void)resetSettings {
    _suppressSave = YES;
    for (NSString *folder in [self.settings.customFolders copy]) [self removeCustomFolder:folder];
    double width = self.settings.windowWidth, height = self.settings.windowHeight;
    long long lifetime = self.settings.lifetimeBytesFreed;
    [self.settings resetToDefaults];
    self.settings.windowWidth = width;
    self.settings.windowHeight = height;
    self.settings.lifetimeBytesFreed = lifetime;
    [self applySelection];
    _suppressSave = NO;
    [self saveSettings];
    [self recalc];
    [self changed];
}

@end
