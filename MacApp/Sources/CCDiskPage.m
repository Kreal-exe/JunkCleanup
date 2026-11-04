#import "CCDiskPage.h"
#import "CCModel.h"
#import "CCSettings.h"

static CCModel *M(void) { return CCModel.shared; }
static CCDiskModel *D(void) { return CCDiskModel.shared; }

static CCLabel *Muted(NSString *text, CGFloat size) { return [CCLabel text:text size:size weight:NSFontWeightRegular role:CCRoleMuted]; }
static CCLabel *Caption(NSString *text) { return [CCLabel text:text size:11.5 weight:NSFontWeightRegular role:CCRoleFaint]; }

/// Makes a stack child as wide as the stack. A label stretched this way must not hug its text: labels hug at 750, above
/// the priority a window resize drags with, so a hugging label would hold the whole window at its own width.
static void Stretch(NSStackView *stack, NSView *child) {
    [child.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [child setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
}

static void Stagger(NSArray<NSView *> *views, double step, double base) {
    NSInteger i = 0;
    for (NSView *v in views) {
        if (v.hidden) continue;
        CCEntrance(v, base + i * step, 18);
        // Rows far below the fold appear together.
        if (++i >= 14) step = 0;
    }
}

// ───────────── colours and names ─────────────

/// The bands' colours are the same in both themes (SpaceColors in DiskViewModel.cs).
static NSColor *SegmentColor(CCSpaceSegment segment, CGFloat alpha) {
    static const uint32_t colors[CCSpaceSegmentCount] = { 0x8E96AB, 0x34D399, 0x22D3EE, 0xA78BFA, 0xF472B6, 0xF59E0B, 0x60A5FA, 0xFB7185 };
    return CCHex(colors[MAX(0, MIN(CCSpaceSegmentCount - 1, segment))], alpha);
}

static NSColor *RiskColor(CCSpaceRisk risk) {
    return risk == CCSpaceRiskKeep ? CCHex(0x8E96AB, 1) : [CCTheme riskColor:(CCRisk)risk];
}

static NSColor *RiskSoft(CCSpaceRisk risk) {
    return risk == CCSpaceRiskKeep ? CCHex(0x8E96AB, 0.16) : [CCTheme riskSoft:(CCRisk)risk];
}

static NSString *Shorten(NSString *path) {
    NSString *home = CCHomeDirectory();
    if ([path isEqualToString:home]) return @"~";
    return [path hasPrefix:[home stringByAppendingString:@"/"]] ? [@"~" stringByAppendingString:[path substringFromIndex:home.length]] : path;
}

/// One app in the Applications row: its icon and name are enough, the row above says what the trash icon does.
static BOOL IsAppRow(CCSpaceEntry *e) {
    return [e.identifier hasPrefix:@"mac.applications/"] && [e.path hasSuffix:@".app"];
}

/// A listed folder (a model, a VM) keeps its own name; parts and known items use their localized one.
static NSString *EntryName(CCSpaceEntry *e) {
    if (IsAppRow(e)) {
        NSString *name = [NSFileManager.defaultManager displayNameAtPath:e.path];
        return [name hasSuffix:@".app"] ? [name substringToIndex:name.length - 4] : name;
    }
    if (e.name) return e.name;
    if (!e.key) return Shorten(e.path);
    NSString *name = L([e.key stringByAppendingString:@".name"]);
    // A part says which folder it is ("The app itself · installs"): an item may have several of one kind.
    return [e.key hasPrefix:@"space.kind."] && e.paths.count == 1 ? [NSString stringWithFormat:@"%@ · %@", name, e.path.lastPathComponent] : name;
}

static NSString *EntryDescription(CCSpaceEntry *e) {
    if (IsAppRow(e)) return @"";
    if (e.uninstallable) return L(@"disk.uninstall.row");
    NSString *key = [e.key stringByAppendingString:@".desc"];
    return key && [CCLocalization.shared hasKey:key] ? L(key) : @"";
}

static BOOL IsCleanable(CCSpaceEntry *e) { return [e.identifier isEqualToString:@"caches"] || e.targetId != nil; }

// ═════════════════════════════ model ═════════════════════════════

@implementation CCDiskModel {
    BOOL _wasScanning, _wasCleaning, _reanalyze;
    CCCancelToken *_token;
    NSString *(^_status)(void);
    NSMutableSet<CCSpaceEntry *> *_busy;
}

+ (CCDiskModel *)shared {
    static CCDiskModel *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [CCDiskModel new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _busy = [NSMutableSet set];
        _filter = -1;
        [self setStatus:^NSString *{ return @""; }];
        [self refreshVolumes];
        __weak CCDiskModel *weak = self;
        // A drive plugged in or ejected: the picker follows, and the map of a drive that left goes with it.
        for (NSNotificationName name in @[ NSWorkspaceDidMountNotification, NSWorkspaceDidUnmountNotification ])
            [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                                    usingBlock:^(NSNotification *n) { [weak volumesChanged]; }];
        [NSNotificationCenter.defaultCenter addObserverForName:CCLanguageDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *n) {
            CCDiskModel *s = weak;
            if (s) s->_statusText = s->_status();
        }];
        // A scan (at launch or "Scan again") measures the disk too, and a finished clean measures it again, so the
        // Disk page is already up to date when it opens.
        [NSNotificationCenter.defaultCenter addObserverForName:CCModelScanStateNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *n) {
            CCDiskModel *s = weak;
            BOOL scanning = M().scanning;
            if (s && scanning && !s->_wasScanning && M().settings.measureDiskWithScan) [s analyze];
            if (s) s->_wasScanning = scanning;
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:CCModelCleanStateNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *n) {
            CCDiskModel *s = weak;
            BOOL cleaning = M().cleaning;
            if (s && !cleaning && s->_wasCleaning && M().settings.measureDiskWithScan) [s analyze];
            if (s) s->_wasCleaning = cleaning;
        }];
    }
    return self;
}

- (void)setStatus:(NSString * (^)(void))status {
    _status = [status copy];
    _statusText = status();
}

/// The window refreshes the visible page on every model change.
- (void)changed {
    [NSNotificationCenter.defaultCenter postNotificationName:CCModelDidChangeNotification object:M()];
}

// ───────────── which disk ─────────────

- (void)refreshVolumes {
    NSArray<CCVolume *> *volumes = [CCVolume mounted];
    _volumes = volumes;
    NSString *path = _selectedVolume.path;
    CCVolume *same = nil;
    for (CCVolume *v in volumes)
        if ([v.path isEqualToString:path]) same = v;
    _selectedVolume = same ?: volumes.firstObject;
}

- (void)volumesChanged {
    NSString *before = _selectedVolume.path;
    [self refreshVolumes];
    if (before && ![before isEqualToString:_selectedVolume.path]) [self mapSelected];
    else [self changed];
}

- (void)selectVolume:(CCVolume *)volume {
    if ([volume.path isEqualToString:_selectedVolume.path]) return;
    [M() refreshAccess];
    if (volume.isHome || M().hasFullDiskAccess) {
        _selectedVolume = volume;
        [self mapSelected];
        return;
    }
    // Opening an external drive would make macOS ask on its own: Full Disk Access first. Declined, macOS asks after all.
    __weak CCDiskModel *weak = self;
    [M() askForFullDiskAccessDeclined:^{
        CCDiskModel *s = weak;
        if (!s) return;
        s->_selectedVolume = volume;
        [s mapSelected];
    }];
    [self changed]; // the picker goes back to the disk still mapped
}

- (void)preselectVolume:(NSString *)nameOrPath {
    for (CCVolume *v in _volumes)
        if ([v.path isEqualToString:nameOrPath] || [v.name caseInsensitiveCompare:nameOrPath] == NSOrderedSame) _selectedVolume = v;
}

- (void)mapSelected {
    _report = nil;
    _filter = -1;
    if (self.analyzing) {
        _reanalyze = YES;
        [self cancel];
    } else {
        [self analyze];
    }
    [self changed];
}

// ───────────── the band picked ─────────────

- (void)pickSegment:(NSInteger)segment {
    _filter = segment == _filter ? -1 : segment;
    [self changed];
}

- (void)clearFilter {
    _filter = -1;
    [self changed];
}

// ───────────── measuring ─────────────

- (void)toggleAnalyze {
    if (self.analyzing) [self cancel];
    else [self analyze];
}

- (void)cancel { [_token cancel]; }

- (void)analyze {
    if (self.analyzing) return;
    [M() refreshAccess];
    CCCancelToken *token = [CCCancelToken new];
    _token = token;
    _analyzing = YES;
    [self setStatus:^NSString *{ return L(@"disk.analyzing"); }];
    [self changed];

    NSMutableArray<CCTarget *> *targets = [NSMutableArray array];
    // Every target: the engine finds their roots itself, off the main thread, including those a scan has yet to find.
    for (CCTargetItem *t in M().targets) [targets addObject:t.target];
    [self refreshVolumes];
    CCSpaceScope *scope = _selectedVolume ? [CCSpaceCatalog scopeForVolume:_selectedVolume fullDiskAccess:M().hasFullDiskAccess]
                                          : [CCSpaceCatalog scopeWithFullDiskAccess:M().hasFullDiskAccess];
    __weak CCDiskModel *weak = self;
    __block CFAbsoluteTime last = 0;
    NSObject *lock = [NSObject new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CCSpaceReport *report = [[CCDiskMapEngine new] analyze:scope targets:targets cancel:token progress:^(NSString *path) {
            // A dozen updates a second is plenty for a status line.
            @synchronized (lock) {
                CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                if (now - last < 0.08) return;
                last = now;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                CCDiskModel *s = weak;
                if (!s || s->_token != token || token.isCancelled) return;
                NSString *shown = Shorten(path);
                [s setStatus:^NSString *{ return LF(@"disk.measuring", shown); }];
                [s changed];
            });
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ [weak finish:report token:token]; });
    });
}

- (void)finish:(CCSpaceReport *)report token:(CCCancelToken *)token {
    if (token != _token) return;
    _token = nil;
    _analyzing = NO;
    if (_reanalyze) {
        // The disk was changed while the old one was being measured.
        _reanalyze = NO;
        [self analyze];
        return;
    }
    if (token.isCancelled) {
        [self setStatus:^NSString *{ return L(@"dash.cancelled"); }];
    } else {
        _report = report;
        long long measured = report.measured;
        double seconds = report.elapsed;
        [self setStatus:^NSString *{ return LF(@"disk.analyzed", CCFormatBytes(measured), CCFormatDecimal(seconds)); }];
    }
    [self changed];
}

// ───────────── what can go ─────────────

+ (NSArray<CCSpaceEntry *> *)safePartsOf:(CCSpaceEntry *)entry {
    BOOL (^safe)(CCSpaceEntry *) = ^BOOL(CCSpaceEntry *e) { return e.risk == CCSpaceRiskSafe && e.canDelete && e.bytes > 0; };
    if (safe(entry)) return @[ entry ];
    NSMutableArray *parts = [NSMutableArray array];
    for (CCSpaceEntry *c in entry.children)
        if (safe(c)) [parts addObject:c];
    return parts;
}

- (BOOL)isBusy:(CCSpaceEntry *)entry { return [_busy containsObject:entry]; }

// ───────────── removing ─────────────

- (void)remove:(CCSpaceEntry *)entry completion:(void (^)(BOOL))completion {
    if (!self.report || self.analyzing || [_busy containsObject:entry] || !entry.canDelete) {
        if (completion) completion(NO);
        return;
    }
    BOOL trash = M().settings.useTrash;
    CCSpaceReport *report = self.report;
    [_busy addObject:entry];
    [self changed];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        long long freed = [[CCDiskMapEngine new] removeEntry:entry useTrash:trash];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_busy removeObject:entry];
            if (freed > 0 && report == self.report) [self account:entry freed:freed trash:trash];
            if (freed > 0) {
                [self finishRemoval:freed trash:trash];
                NSString *text = LF(trash ? @"details.trashed" : @"details.deleted", EntryName(entry), CCFormatBytes(freed));
                [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:M()
                                                                userInfo:@{ @"symbol": @"checkmark", @"text": text }];
            }
            [self changed];
            if (completion) completion(freed > 0);
        });
    });
}

/// The items holding an entry, innermost first.
- (NSArray<CCSpaceEntry *> *)ancestorsOf:(CCSpaceEntry *)entry {
    for (CCSpaceEntry *item in self.report.items) {
        if ([item.children containsObject:entry]) return @[ item ];
        for (CCSpaceEntry *child in item.children)
            if ([child.children containsObject:entry]) return @[ child, item ];
    }
    return @[];
}

/// Takes what was removed out of its item, its band and the totals.
- (void)account:(CCSpaceEntry *)entry freed:(long long)freed trash:(BOOL)trash {
    CCSpaceReport *r = self.report;
    entry.bytes = MAX(0, entry.bytes - freed);
    NSArray<CCSpaceEntry *> *ancestors = [self ancestorsOf:entry];
    for (CCSpaceEntry *a in ancestors) a.bytes = MAX(0, a.bytes - freed);
    if (entry.bytes == 0) {
        if (ancestors.count) [ancestors.firstObject.children removeObject:entry];
        else [r.items removeObject:entry];
    }
    for (CCSpaceEntry *a in ancestors)
        if (a.bytes == 0) [r.items removeObject:a];
    r.segments[entry.segment] = MAX(0, r.segments[entry.segment] - freed);
    if (trash) {
        // Still on the disk until the Trash is emptied: it moves to the Trash's row.
        r.segments[CCSpaceOther] += freed;
        for (CCSpaceEntry *item in r.items)
            if ([item.identifier isEqualToString:@"mac.trash"] && !item.needsAccess) item.bytes += freed;
    }
}

- (void)finishRemoval:(long long)freed trash:(BOOL)trash {
    if (freed <= 0) return;
    [M() addFreed:freed];
    if (trash || !self.report) return;
    CCVolume *volume = [CCVolume volumeAtPath:_selectedVolume.path];
    if (volume) self.report.free = volume.free;
}

// ───────────── uninstalling an app ─────────────

- (void)toast:(NSString *)text symbol:(NSString *)symbol {
    [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:M() userInfo:@{ @"symbol": symbol, @"text": text }];
}

- (void)uninstall:(CCSpaceEntry *)entry {
    if (!entry.uninstallable || self.analyzing || [_busy containsObject:entry]) return;
    NSString *appPath = entry.path, *name = appPath.lastPathComponent.stringByDeletingPathExtension;
    // Without this macOS would ask about each app's container, or refuse: one switch first.
    [M() refreshAccess];
    if (!M().hasFullDiskAccess) {
        [M() askForFullDiskAccessDeclined:nil];
        return;
    }
    NSString *identifier = [CCAppLeftovers bundleIdOfApp:appPath];
    if (identifier && [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].count) {
        [self toast:LF(@"disk.uninstall.running", name) symbol:@"exclamationmark.triangle"];
        return;
    }
    [_busy addObject:entry];
    [self changed];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *leftovers = [CCAppLeftovers leftoversOfApp:appPath otherApps:[CCAppLeftovers installedApps]];
        NSMutableArray<NSNumber *> *sizes = [NSMutableArray array];
        long long total = entry.bytes;
        for (NSString *path in leftovers) {
            long long bytes = [CCDiskMapEngine measure:path excluding:nil cancel:nil unreadable:NULL];
            [sizes addObject:@(bytes)];
            total += bytes;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_busy removeObject:entry];
            [self changed];
            NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@ · %@", appPath.lastPathComponent, CCFormatBytes(entry.bytes)]];
            // The largest first; a long list is cut, with how many more.
            NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
            for (NSUInteger i = 0; i < leftovers.count; i++) [indexes addObject:@(i)];
            NSArray<NSNumber *> *order = [indexes sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
                return [sizes[b.unsignedIntegerValue] compare:sizes[a.unsignedIntegerValue]];
            }];
            for (NSUInteger i = 0; i < MIN((NSUInteger)8, order.count); i++) {
                NSUInteger at = order[i].unsignedIntegerValue;
                [lines addObject:[NSString stringWithFormat:@"%@ · %@", Shorten(leftovers[at]), CCFormatBytes(sizes[at].longLongValue)]];
            }
            if (order.count > 8) [lines addObject:LF(@"disk.uninstall.more", @(order.count - 8))];
            __weak CCDiskModel *weak = self;
            M().confirm(LF(@"disk.uninstall.title", name, CCFormatBytes(total)),
                        LF(@"disk.uninstall.body", [lines componentsJoinedByString:@"\n"]),
                        L(@"disk.uninstall.ok"), YES, ^(BOOL ok) {
                if (ok) [weak moveApp:entry leftovers:leftovers total:total];
            });
        });
    });
}

- (void)moveApp:(CCSpaceEntry *)entry leftovers:(NSArray<NSString *> *)leftovers total:(long long)total {
    NSString *appPath = entry.path, *name = appPath.lastPathComponent.stringByDeletingPathExtension;
    CCSpaceReport *report = self.report;
    [_busy addObject:entry];
    [self changed];
    // The app first, through the system, which asks for the password when an app store installed it as root. If it stays,
    // its data stays too.
    [NSWorkspace.sharedWorkspace recycleURLs:@[ [NSURL fileURLWithPath:appPath] ] completionHandler:^(NSDictionary<NSURL *, NSURL *> *moved, NSError *error) {
        if (error || moved.count == 0 || [NSFileManager.defaultManager fileExistsAtPath:appPath]) {
            [self->_busy removeObject:entry];
            [self toast:LF(@"disk.uninstall.failed", name) symbol:@"exclamationmark.triangle"];
            [self changed];
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSInteger left = 0;
            for (NSString *path in leftovers)
                if (![CCAppLeftovers moveToTrash:path]) left++;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_busy removeObject:entry];
                if (report == self.report) [self account:entry freed:entry.bytes trash:YES];
                [self toast:left ? LF(@"disk.uninstall.partly", name, @(left)) : LF(@"disk.uninstall.done", name, CCFormatBytes(total))
                     symbol:left ? @"exclamationmark.triangle" : @"checkmark"];
                [self changed];
            });
        });
    }];
}

- (void)copyCommand:(CCSpaceEntry *)entry {
    if (!entry.command) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:entry.command forType:NSPasteboardTypeString];
    [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:M()
                                                    userInfo:@{ @"symbol": @"doc.on.doc", @"text": LF(@"insight.copied", entry.command) }];
}

@end

// ═════════════════════════════ a row ═════════════════════════════

/// One item, a part of one or a discovered folder: tile, name, risk, what it is, where, its size and what can be
/// done with it; its parts fold out underneath.
@interface CCDiskRow : CCBox
@property (nonatomic, strong, readonly) CCSpaceEntry *entry;
- (instancetype)initWithEntry:(CCSpaceEntry *)entry depth:(NSInteger)depth;
- (void)refresh;
- (void)toggle;
@end

@implementation CCDiskRow {
    NSInteger _depth;
    CCLabel *_name, *_desc, *_path, *_safe, *_access;
    CCPill *_risk, *_accessPill;
    NSStackView *_safeRow;
    CCCounter *_bytes;
    CCSmoothBar *_bar;
    CCButton *_clean, *_grant, *_uninstall, *_copy, *_reveal, *_trash, *_confirm, *_chevron;
    CCCollapsible *_details;
    NSStackView *_children;
    NSTimer *_revert;
    BOOL _expanded;
}

- (instancetype)initWithEntry:(CCSpaceEntry *)entry depth:(NSInteger)depth {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _entry = entry;
        _depth = depth;
        self.radius = 14;
        self.fill = ^NSColor *{ return CCTheme.inset; };
        [self build];
        [self refresh];
    }
    return self;
}

- (void)build {
    CCSpaceEntry *e = self.entry;
    CCSpaceSegment segment = e.segment;
    __weak CCDiskRow *weak = self;

    NSView *tile;
    if (IsAppRow(e)) {
        // An app shows its own icon, like Finder, instead of the band's symbol.
        NSImageView *icon = [NSImageView imageViewWithImage:[NSWorkspace.sharedWorkspace iconForFile:e.path]];
        icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [icon.widthAnchor constraintEqualToConstant:38].active = YES;
        [icon.heightAnchor constraintEqualToConstant:38].active = YES;
        tile = icon;
    } else {
        CCIconTile *symbolTile = [CCIconTile tileWithSymbol:e.symbol size:38 radius:11 iconSize:16];
        symbolTile.fill = ^NSColor *{ return SegmentColor(segment, 0.16); };
        symbolTile.icon.colorBlock = ^NSColor *{ return SegmentColor(segment, 1); };
        tile = symbolTile;
    }

    // Names wrap onto a second line rather than lose letters.
    _name = [CCLabel text:@"" size:14 weight:NSFontWeightSemibold role:CCRoleText];
    _name.wraps = YES;
    // As wide as its text, so the pill sits right after it; it wraps only when the line runs out. Below the page's fill
    // (499), or the name would pull the whole page narrower than the window.
    [_name setContentHuggingPriority:490 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_name setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    CCSpaceRisk risk = e.risk;
    _risk = [CCPill pillWithText:@"" symbol:nil color:^NSColor *{ return RiskColor(risk); } soft:^NSColor *{ return RiskSoft(risk); }];
    _accessPill = [CCPill pillWithText:@"" symbol:@"lock.shield" color:^NSColor *{ return CCTheme.warning; }
                                  soft:^NSColor *{ return CCTheme.warningSoft; }];
    _accessPill.hidden = !e.needsAccess;
    _risk.hidden = IsAppRow(e);
    NSStackView *titleRow = CCHStack(@[ _name, _risk, _accessPill, CCSpacer() ], 8);
    titleRow.alignment = NSLayoutAttributeCenterY;
    _desc = Muted(@"", 12.5);
    _desc.wraps = YES;
    _path = [CCLabel text:@"" size:11 weight:NSFontWeightRegular role:CCRoleFaint];
    _path.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_path setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    CCIcon *shield = [CCIcon symbol:@"checkmark.shield" size:12 weight:NSFontWeightSemibold role:CCRoleSuccess];
    _safe = [CCLabel text:@"" size:12 weight:NSFontWeightSemibold role:CCRoleSuccess];
    _safeRow = CCHStack(@[ shield, _safe ], 6);
    NSStackView *body = CCVStack(@[ _desc, _path, _safeRow ], 3);
    [body setCustomSpacing:6 afterView:_path];
    Stretch(body, _desc);
    Stretch(body, _path);

    _bytes = [CCCounter text:@"" size:15 weight:NSFontWeightSemibold role:CCRoleText];
    _bytes.alignment = NSTextAlignmentRight;
    _bar = [CCSmoothBar new];
    _bar.duration = 700;
    _bar.fillColor = ^NSColor *{ return SegmentColor(segment, 1); };
    CCSize(_bar, 110, 5);
    _access = [CCLabel text:@"" size:12 weight:NSFontWeightSemibold role:CCRoleWarning];
    _access.alignment = NSTextAlignmentRight;
    NSStackView *size = CCVStack(@[ _bytes, _bar, _access ], 7);
    size.alignment = NSLayoutAttributeTrailing;
    [size.widthAnchor constraintEqualToConstant:110].active = YES;
    _bytes.hidden = _bar.hidden = e.needsAccess;
    _access.hidden = !e.needsAccess;

    _clean = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"sparkles"];
    _clean.locKey = @"disk.clean";
    _copy = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"doc.on.doc"];
    _copy.locKey = @"insight.copyCommand";
    _copy.toolTip = e.command;
    _grant = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"lock.shield"];
    _grant.locKey = @"titlebar.runAsAdmin";
    _grant.toolTip = L(@"titlebar.adminHint");
    _grant.onClick = ^{ [M() openFullDiskAccessSettings]; };
    _grant.hidden = ![e.identifier isEqualToString:@"mac.noaccess"];
    for (CCButton *b in @[ _clean, _grant, _copy ]) {
        b.padding = NSEdgeInsetsMake(6, 10, 6, 10);
        b.fontSize = 12;
        b.symbolSize = 12;
    }
    _clean.onClick = ^{ [M() cleanFromDisk:weak.entry.targetId]; };
    _copy.onClick = ^{ [D() copyCommand:weak.entry]; };
    _reveal = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"folder"];
    _reveal.onClick = ^{ [M() revealPath:weak.entry.path]; };
    _trash = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"trash"];
    _trash.onClick = ^{ [weak askToConfirm]; };
    _uninstall = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"trash"];
    _uninstall.toolTip = L(@"disk.uninstall.tip");
    _uninstall.hidden = !e.uninstallable;
    _uninstall.onClick = ^{ [D() uninstall:weak.entry]; };
    _confirm = [CCButton buttonWithStyle:CCButtonDanger title:@"" symbol:@"trash"];
    _confirm.padding = NSEdgeInsetsMake(6, 12, 6, 12);
    _confirm.fontSize = 12.5;
    _confirm.symbolSize = 12;
    _confirm.hidden = YES;
    _confirm.onClick = ^{ [weak delete]; };
    _chevron = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"chevron.down"];
    _chevron.iconView.wantsLayer = YES;
    _chevron.onClick = ^{ [weak toggle]; };

    _clean.hidden = !IsCleanable(e);
    _copy.hidden = e.command == nil;
    BOOL exists = e.paths.count > 0 && [NSFileManager.defaultManager fileExistsAtPath:e.path];
    _reveal.hidden = !exists;
    _chevron.hidden = e.children.count == 0;
    // Buttons sit at the trailing edge of a slot that always fits Show, Delete and the chevron, so the sizes line up
    // in one column whether or not a row has all three.
    NSStackView *actions = CCHStack(@[], 2);
    [actions setViews:@[ _clean, _copy, _reveal, _uninstall, _trash, _confirm, _chevron ] inGravity:NSStackViewGravityTrailing];
    [actions insertView:_grant atIndex:0 inGravity:NSStackViewGravityTrailing];
    [actions setCustomSpacing:8 afterView:_grant];
    [actions setCustomSpacing:8 afterView:_clean];
    [actions setCustomSpacing:8 afterView:_copy];
    [actions.widthAnchor constraintGreaterThanOrEqualToConstant:3 * 34 + 2 * 2].active = YES;

    // The name, the size and the buttons share the first line; what it is and where it lives run underneath across the
    // whole row, so a description takes one or two lines rather than five.
    NSStackView *head = CCHStack(@[ titleRow, size, actions ], 16);
    head.alignment = NSLayoutAttributeCenterY;
    [head setCustomSpacing:12 afterView:size];
    [titleRow setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [titleRow setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [titleRow setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *text = CCVStack(@[ head, body ], 4);
    Stretch(text, head);
    Stretch(text, body);
    NSStackView *line = CCHStack(@[ tile, text ], 14);
    line.alignment = NSLayoutAttributeTop;
    [text setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView *content = CCAuto([CCFlippedView new]);
    _children = CCVStack(@[], 8);
    [content addSubview:_children];
    CCPin(_children, content, NSEdgeInsetsMake(12, 52, 0, 0));
    _details = [[CCCollapsible alloc] initWithContent:content];

    NSStackView *stack = CCVStack(@[ line, _details ], 0);
    Stretch(stack, line);
    Stretch(stack, _details);
    [self addSubview:stack];
    CCPin(stack, self, NSEdgeInsetsMake(12, 14, 12, 14));
}

- (void)refresh {
    CCSpaceEntry *e = self.entry;
    CCSpaceReport *report = D().report;
    _name.stringValue = EntryName(e);
    _name.toolTip = EntryName(e);
    _risk.label.stringValue = L([@"risk." stringByAppendingString:CCSpaceRiskName(e.risk)]);
    _risk.toolTip = L([NSString stringWithFormat:@"risk.%@.desc", CCSpaceRiskName(e.risk)]);
    _accessPill.label.stringValue = L(@"targets.admin");
    _accessPill.toolTip = L(@"titlebar.adminHint");
    _access.stringValue = L(@"targets.needsAdmin");
    NSString *desc = EntryDescription(e);
    _desc.stringValue = desc;
    _desc.hidden = desc.length == 0;
    NSMutableArray *shown = [NSMutableArray array];
    for (NSString *p in e.paths) [shown addObject:Shorten(p)];
    _path.stringValue = [shown componentsJoinedByString:@"   ·   "];
    _path.toolTip = [e.paths componentsJoinedByString:@"\n"];
    _path.hidden = e.paths.count == 0;
    long long safe = 0;
    for (CCSpaceEntry *p in [CCDiskModel safePartsOf:e]) safe += p.bytes;
    _safe.stringValue = LF(@"disk.safe", CCFormatBytes(safe));
    _safeRow.hidden = e.children.count == 0 || safe == 0;
    _bytes.bytes = e.bytes;
    _bar.value = report.used > 0 ? MIN(1, (double)e.bytes / report.used) : 0;
    _reveal.toolTip = L(@"details.reveal");
    _trash.toolTip = L(@"details.delete");
    _confirm.title = L(@"details.confirm");

    BOOL busy = [D() isBusy:e];
    BOOL deletable = e.canDelete && e.bytes > 0 && !D().analyzing;
    if (!deletable && !busy) [self cancelConfirm];
    _trash.hidden = !deletable || !_confirm.hidden;
    _trash.enabled = !busy;
    _confirm.enabled = !busy;
    _uninstall.enabled = !busy && !D().analyzing;
    _chevron.hidden = e.children.count == 0;
    self.alphaValue = busy ? 0.6 : 1;

    if (_expanded) [self syncChildren];
    else [_details contentChanged];
}

// ── parts ──

- (void)toggle {
    _expanded = !_expanded;
    if (_expanded) [self syncChildren];
    [_details setOpen:_expanded animated:YES];
    CCTransformView(_chevron.iconView, CCXformMake(1, 0, _expanded ? 180 : 0), 300, CCEaseCubicOut);
    if (_expanded) Stagger(_children.arrangedSubviews, 30, 60);
}

/// Built when first opened (a container may hold hundreds of folders); rows of removed parts go.
- (void)syncChildren {
    NSArray<CCDiskRow *> *rows = (NSArray<CCDiskRow *> *)_children.arrangedSubviews;
    NSArray *shown = [rows valueForKey:@"entry"];
    if (![shown isEqualToArray:self.entry.children]) {
        NSMutableDictionary<NSValue *, CCDiskRow *> *existing = [NSMutableDictionary dictionary];
        for (CCDiskRow *r in rows) existing[[NSValue valueWithNonretainedObject:r.entry]] = r;
        for (NSView *v in [rows copy]) [v removeFromSuperview];
        for (CCSpaceEntry *c in self.entry.children) {
            CCDiskRow *row = existing[[NSValue valueWithNonretainedObject:c]] ?: [[CCDiskRow alloc] initWithEntry:c depth:_depth + 1];
            [_children addArrangedSubview:row];
            Stretch(_children, row);
        }
    }
    for (CCDiskRow *r in _children.arrangedSubviews) [r refresh];
    [_children layoutSubtreeIfNeeded];
    [_details contentChanged];
}

// ── delete: the trash icon asks, the red button removes ──

- (void)askToConfirm {
    _trash.hidden = YES;
    _confirm.hidden = NO;
    CCEntrance(_confirm, 0, 0);
    [_revert invalidate];
    __weak CCDiskRow *weak = self;
    _revert = [NSTimer scheduledTimerWithTimeInterval:3.5 repeats:NO block:^(NSTimer *t) {
        CCDiskRow *s = weak;
        if (s && ![D() isBusy:s.entry]) [s cancelConfirm];
    }];
}

- (void)cancelConfirm {
    [_revert invalidate];
    _confirm.hidden = YES;
    _trash.hidden = !(self.entry.canDelete && self.entry.bytes > 0);
}

- (void)delete {
    [_revert invalidate];
    __weak CCDiskRow *weak = self;
    [D() remove:self.entry completion:^(BOOL ok) { [weak cancelConfirm]; }];
}

@end

// ═════════════════════════════ a legend entry ═════════════════════════════

/// A band's dot, name and size; clicking it narrows the list to that band.
@interface CCLegendChip : CCBox
@property (nonatomic) BOOL picked;
@property (nonatomic, copy) void (^onClick)(void);
- (instancetype)initWithContent:(NSView *)content;
@end

@implementation CCLegendChip {
    NSTrackingArea *_tracking;
    BOOL _hovered;
}

- (instancetype)initWithContent:(NSView *)content {
    if ((self = [super initWithFrame:NSZeroRect])) {
        self.radius = 9;
        [self addSubview:content];
        CCPin(content, self, NSEdgeInsetsMake(4, 8, 4, 8));
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityButtonRole;
        [self applyFill];
    }
    return self;
}

- (void)applyFill {
    BOOL picked = _picked, hovered = _hovered;
    self.fill = ^NSColor *{ return picked ? CCTheme.accentSoft : hovered ? CCTheme.inset : NSColor.clearColor; };
}

- (void)setPicked:(BOOL)picked {
    if (picked == _picked) return;
    _picked = picked;
    [self applyFill];
}

- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseDown:(NSEvent *)event { if (self.onClick) self.onClick(); }
- (BOOL)accessibilityPerformPress {
    if (self.onClick) self.onClick();
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self applyFill]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self applyFill]; }

@end

// ═════════════════════════════ the page ═════════════════════════════

@implementation CCDiskPage {
    CCScrollPage *_scroll;
    NSView *_header;
    CCCard *_mapCard, *_listCard;
    CCLabel *_subtitle, *_free, *_status, *_notice, *_safeText, *_listDesc, *_filterText, *_filterEmpty;
    CCButton *_analyze, *_removeSafe, *_showAll;
    CCPopupField *_drive;
    NSStackView *_filterRow;
    NSArray<CCVolume *> *_shownVolumes;
    CCSpinner *_spinner;
    CCSegmentBar *_bar;
    CCFlowView *_legend;
    NSMutableArray<CCLegendChip *> *_legendItems;
    NSMutableArray<CCLabel *> *_legendNames;
    NSMutableArray<CCCounter *> *_legendBytes;
    NSStackView *_safeGroup, *_rows;
    CCSpaceReport *_shownReport;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self build];
    return self;
}

- (void)build {
    _scroll = [CCScrollPage new];
    [self addSubview:_scroll];
    CCPin(_scroll, self, NSEdgeInsetsMake(0, 0, 0, 0));

    // ── header ──
    CCLabel *title = [CCLabel key:@"disk.title" size:28 weight:NSFontWeightSemibold role:CCRoleText];
    _subtitle = Muted(@"", 13);
    [_subtitle setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *titles = CCVStack(@[ title, _subtitle ], 4);
    _analyze = [CCButton buttonWithStyle:CCButtonPrimary title:@"" symbol:@"chart.pie"];
    _analyze.onClick = ^{ [D() toggleAnalyze]; };
    [_analyze.widthAnchor constraintGreaterThanOrEqualToConstant:190].active = YES;
    // Which disk to map, when there is more than one.
    _drive = [CCPopupField new];
    // Wide enough for "Macintosh HD  ·  123.4 GB free".
    NSLayoutConstraint *driveWidth = [_drive.widthAnchor constraintEqualToConstant:280];
    driveWidth.priority = NSLayoutPriorityDefaultHigh + 1;
    driveWidth.active = YES;
    _drive.onSelect = ^(NSInteger index) {
        NSArray<CCVolume *> *volumes = D().volumes;
        if (index >= 0 && index < (NSInteger)volumes.count) [D() selectVolume:volumes[index]];
    };
    NSStackView *header = CCHStack(@[ titles, CCSpacer(), _drive, _analyze ], 16);
    [header setCustomSpacing:12 afterView:_drive];
    [titles setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _header = header;

    // ── the whole disk, band by band ──
    CCLabel *mapTitle = [CCLabel key:@"disk.map" size:18 weight:NSFontWeightSemibold role:CCRoleText];
    _free = Muted(@"", 13);
    NSStackView *mapHeader = CCHStack(@[ mapTitle, CCSpacer(), _free ], 12);
    _bar = [CCSegmentBar new];
    _bar.roundedSegments = YES;
    CCSize(_bar, 0, 26);
    _bar.onPick = ^(NSInteger segment) { [D() pickSegment:segment]; };
    _legend = [CCFlowView new];
    // Each entry has its own padding for the click area.
    _legend.hSpacing = 6;
    _legend.vSpacing = 2;
    _legendItems = [NSMutableArray array];
    _legendNames = [NSMutableArray array];
    _legendBytes = [NSMutableArray array];
    for (NSInteger s = 0; s < CCSpaceSegmentCount; s++) {
        CCBox *dot = [[CCBox alloc] initWithFrame:NSZeroRect];
        dot.radius = 3;
        dot.fill = ^NSColor *{ return SegmentColor(s, 1); };
        CCSize(dot, 10, 10);
        CCLabel *name = Muted(@"", 13);
        CCCounter *bytes = [CCCounter text:@"" size:13 weight:NSFontWeightSemibold role:CCRoleText];
        __weak CCFlowView *legend = _legend;
        bytes.onRender = ^{ [legend itemsChanged]; };
        NSStackView *item = CCHStack(@[ dot, name, bytes ], 8);
        [item setCustomSpacing:7 afterView:name];
        CCLegendChip *chip = [[CCLegendChip alloc] initWithContent:item];
        chip.onClick = ^{ [D() pickSegment:s]; };
        chip.hidden = YES;
        [_legendItems addObject:chip];
        [_legendNames addObject:name];
        [_legendBytes addObject:bytes];
    }
    [_legend setItems:_legendItems];
    _notice = [CCLabel key:@"disk.mac.needsAccess" size:12 weight:NSFontWeightRegular role:CCRoleWarning];
    _notice.wraps = YES;

    _spinner = [[CCSpinner alloc] initWithDiameter:14 lineWidth:2.5 sweep:270 period:0.9];
    // The status wraps rather than cut a number; the safe total and its button get a line of their own.
    _status = Caption(@"");
    _status.wraps = YES;
    NSStackView *status = CCHStack(@[ _spinner, _status ], 8);
    status.alignment = NSLayoutAttributeTop;
    CCIcon *shield = [CCIcon symbol:@"checkmark.shield" size:14 weight:NSFontWeightSemibold role:CCRoleSuccess];
    _safeText = [CCLabel text:@"" size:13 weight:NSFontWeightSemibold role:CCRoleSuccess];
    _removeSafe = [CCButton buttonWithStyle:CCButtonSuccess title:nil symbol:@"sparkles"];
    _removeSafe.locKey = @"disk.cleanNow";
    _removeSafe.padding = NSEdgeInsetsMake(10, 16, 10, 16);
    _removeSafe.fontSize = 13;
    _removeSafe.symbolSize = 13;
    // The same clean as Overview's button, of what Overview shows: one number for what the app can clean.
    _removeSafe.onClick = ^{ [M() cleanFromDisk:nil]; };
    _safeGroup = CCHStack(@[ shield, _safeText, CCSpacer(), _removeSafe ], 6);
    [_safeGroup setCustomSpacing:14 afterView:_safeText];

    NSStackView *map = CCVStack(@[ mapHeader, _bar, _legend, _notice, status, _safeGroup ], 0);
    [map setCustomSpacing:18 afterView:mapHeader];
    [map setCustomSpacing:18 afterView:_bar];
    [map setCustomSpacing:10 afterView:_legend];
    [map setCustomSpacing:12 afterView:_notice];
    [map setCustomSpacing:12 afterView:status];
    for (NSView *v in @[ mapHeader, _bar, _legend, _notice, status, _safeGroup ]) Stretch(map, v);
    _mapCard = [CCCard card];
    [_mapCard addSubview:map];
    CCPin(map, _mapCard, NSEdgeInsetsMake(26, 28, 24, 28));

    // ── what takes the space ──
    CCLabel *listTitle = [CCLabel key:@"disk.whatsTaking" size:18 weight:NSFontWeightSemibold role:CCRoleText];
    CCLabel *listDesc = [CCLabel key:@"disk.whatsTaking.desc" size:12.5 weight:NSFontWeightRegular role:CCRoleMuted];
    listDesc.wraps = YES;
    _listDesc = listDesc;
    _rows = CCVStack(@[], 8);
    // The band picked in the bar, with a way back to everything.
    _filterText = [CCLabel text:@"" size:13 weight:NSFontWeightSemibold role:CCRoleText];
    _showAll = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"xmark"];
    _showAll.locKey = @"disk.filter.all";
    _showAll.padding = NSEdgeInsetsMake(5, 10, 5, 10);
    _showAll.fontSize = 12;
    _showAll.symbolSize = 11;
    _showAll.onClick = ^{ [D() clearFilter]; };
    _filterRow = CCHStack(@[ _filterText, _showAll, CCSpacer() ], 12);
    _filterRow.hidden = YES;
    _filterEmpty = [CCLabel key:@"disk.filter.empty" size:12.5 weight:NSFontWeightRegular role:CCRoleMuted];
    _filterEmpty.wraps = YES;
    _filterEmpty.hidden = YES;
    NSStackView *list = CCVStack(@[ listTitle, listDesc, _filterRow, _filterEmpty, _rows ], 4);
    [list setCustomSpacing:16 afterView:listDesc];
    [list setCustomSpacing:12 afterView:_filterRow];
    [list setCustomSpacing:12 afterView:_filterEmpty];
    Stretch(list, listDesc);
    Stretch(list, _filterRow);
    Stretch(list, _filterEmpty);
    Stretch(list, _rows);
    _listCard = [CCCard card];
    [_listCard addSubview:list];
    CCPin(list, _listCard, NSEdgeInsetsMake(22, 24, 24, 24));
    _listCard.hidden = YES;

    NSStackView *page = CCVStack(@[ header, _mapCard, _listCard ], 0);
    [page setCustomSpacing:20 afterView:header];
    [page setCustomSpacing:16 afterView:_mapCard];
    for (NSView *v in @[ header, _mapCard, _listCard ]) Stretch(page, v);
    NSView *doc = _scroll.document;
    [doc addSubview:page];
    // Never wider than the window allows; as wide as it allows below the window's own size priority, so the page
    // follows the window instead of holding it (hidden pages keep their constraints too).
    [page.widthAnchor constraintLessThanOrEqualToAnchor:doc.widthAnchor constant:-64].active = YES;
    NSLayoutConstraint *fill = [page.widthAnchor constraintEqualToAnchor:doc.widthAnchor constant:-64];
    fill.priority = NSLayoutPriorityWindowSizeStayPut - 1;
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:doc.topAnchor constant:6],
        [doc.bottomAnchor constraintEqualToAnchor:page.bottomAnchor constant:28],
        [page.centerXAnchor constraintEqualToAnchor:doc.centerXAnchor],
        [page.widthAnchor constraintLessThanOrEqualToConstant:1320],
        fill,
    ]];
}

- (void)refresh {
    CCDiskModel *d = D();
    CCSpaceReport *r = d.report;
    BOOL analyzing = d.analyzing;

    _subtitle.stringValue = r ? LF(@"disk.subtitle", r.volumeName, CCFormatBytes(r.used), CCFormatBytes(r.total)) : L(@"disk.subtitle.none");
    _analyze.title = analyzing ? L(@"dash.stop") : r ? L(@"disk.reanalyze") : L(@"disk.analyze");
    _analyze.symbol = analyzing ? @"stop" : @"chart.pie";
    _free.stringValue = r ? LF(@"disk.free", CCFormatBytes(r.free)) : @"";

    NSArray<CCVolume *> *volumes = d.volumes;
    NSMutableArray<NSString *> *driveNames = [NSMutableArray array];
    for (CCVolume *v in volumes) [driveNames addObject:[NSString stringWithFormat:@"%@  ·  %@", v.name, LF(@"disk.free", CCFormatBytes(v.free))]];
    if (![driveNames isEqualToArray:_drive.items]) _drive.items = driveNames;
    NSInteger driveIndex = 0;
    for (NSUInteger i = 0; i < volumes.count; i++)
        if ([volumes[i].path isEqualToString:d.selectedVolume.path]) driveIndex = (NSInteger)i;
    if (driveIndex != _drive.selectedIndex) _drive.selectedIndex = driveIndex;
    _drive.hidden = volumes.count <= 1;
    _drive.toolTip = L(@"disk.drive");
    _bar.toolTip = L(@"disk.pickBand");

    NSMutableArray *weights = [NSMutableArray array], *colors = [NSMutableArray array];
    for (NSInteger s = 0; s < CCSpaceSegmentCount; s++) {
        long long bytes = r ? r.segments[s] : 0;
        [weights addObject:@(bytes)];
        BOOL dimmed = d.filter >= 0 && d.filter != s;
        [colors addObject:SegmentColor(s, dimmed ? 0.22 : 1)];
        _legendItems[s].picked = d.filter == s;
        _legendItems[s].alphaValue = dimmed ? 0.45 : 1;
        _legendNames[s].stringValue = L([@"disk.seg." stringByAppendingString:CCSpaceSegmentName(s)]);
        _legendBytes[s].bytes = bytes;
        _legendItems[s].hidden = bytes <= 0;
    }
    _bar.capacity = r ? (double)r.total : 0;
    [_bar setWeights:weights colors:colors];
    [_legend itemsChanged];
    _legend.hidden = !r;
    _notice.hidden = !r || M().hasFullDiskAccess || !d.selectedVolume.isHome;

    _status.stringValue = d.statusText;
    _spinner.hidden = !analyzing;
    CCModel *m = M();
    long long cleanable = m.hasResults && !m.scanning ? m.diskCleanableBytes : 0;
    _safeText.stringValue = LF(@"disk.cleanable", CCFormatBytes(cleanable));
    _safeGroup.hidden = !r || analyzing || cleanable == 0 || m.cleaning;

    [self syncRows:r];
    [self applyFilter:r];
    if (_listCard.hidden && r) {
        _listCard.hidden = NO;
        // Laid out while hidden, the description still wraps at its old width: measure it again once shown.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_listCard layoutSubtreeIfNeeded];
            self->_listDesc.preferredMaxLayoutWidth = NSWidth(self->_listDesc.bounds);
            [self->_listDesc invalidateIntrinsicContentSize];
        });
    }
    _listCard.hidden = !r;
}

/// Only the rows of the band picked; a band no folder accounts for says so.
- (void)applyFilter:(CCSpaceReport *)report {
    NSInteger filter = D().filter;
    BOOL any = NO;
    for (CCDiskRow *row in _rows.arrangedSubviews) {
        BOOL shown = filter < 0 || row.entry.segment == filter;
        BOOL wasHidden = row.hidden;
        row.hidden = !shown;
        any |= shown;
        // Laid out while hidden, its text still wraps at the old width.
        if (shown && wasHidden) dispatch_async(dispatch_get_main_queue(), ^{ [row refresh]; });
    }
    _filterRow.hidden = filter < 0;
    _filterText.stringValue = filter >= 0 ? LF(@"disk.filter", L([@"disk.seg." stringByAppendingString:CCSpaceSegmentName(filter)])) : @"";
    BOOL wasEmptyHidden = _filterEmpty.hidden;
    _filterEmpty.hidden = filter < 0 || any || !report;
    if (wasEmptyHidden && !_filterEmpty.hidden)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_listCard layoutSubtreeIfNeeded];
            self->_filterEmpty.preferredMaxLayoutWidth = NSWidth(self->_filterEmpty.bounds);
            [self->_filterEmpty invalidateIntrinsicContentSize];
        });
}

- (void)syncRows:(CCSpaceReport *)report {
    if (report != _shownReport) {
        // A new analysis: new rows, played in.
        BOOL first = _shownReport == nil;
        _shownReport = report;
        for (NSView *v in [_rows.arrangedSubviews copy]) [v removeFromSuperview];
        for (CCSpaceEntry *e in report.items) {
            CCDiskRow *row = [[CCDiskRow alloc] initWithEntry:e depth:0];
            [_rows addArrangedSubview:row];
            Stretch(_rows, row);
        }
        if (report && first && self.entrancePlayed) CCEntrance(_listCard, 0, 18);
        if (report) Stagger(_rows.arrangedSubviews, 40, first ? 80 : 0);
        return;
    }
    // A removal: rows of items that are gone fade out.
    for (CCDiskRow *row in [_rows.arrangedSubviews copy]) {
        if ([report.items containsObject:row.entry]) {
            [row refresh];
            continue;
        }
        if (!CCMotionEnabled()) {
            [row removeFromSuperview];
            continue;
        }
        if (row.layer.opacity < 0.99) continue;
        CCAnimateNumber(row.layer, @"opacity", 0, 220, CCEaseIn, 0);
        CCTransformView(row, CCXformMake(0.97, 0, 0), 220, CCEaseIn);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.23 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [row removeFromSuperview]; });
    }
}

- (void)revealPartsForCapture {
    for (CCDiskRow *row in _rows.arrangedSubviews) {
        if ([CCDiskModel safePartsOf:row.entry].count == 0 || row.entry.children.count == 0) continue;
        [row toggle];
        [_scroll.document layoutSubtreeIfNeeded];
        NSRect frame = [_scroll.document convertRect:row.bounds fromView:row];
        [_scroll.document scrollPoint:NSMakePoint(0, MAX(0, NSMinY(frame) - 24))];
        return;
    }
}

- (void)playEntrance {
    [super playEntrance];
    CCEntrance(_header, 0, 18);
    CCEntrance(_mapCard, 70, 18);
    if (!_listCard.hidden) CCEntrance(_listCard, 140, 18);
    // The first time the page opens, when no scan has measured the disk yet.
    if (!D().report && !D().analyzing) [D() analyze];
}

@end
