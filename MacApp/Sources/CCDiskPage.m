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

/// A listed folder (a model, a VM) keeps its own name; parts and known items use their localized one.
static NSString *EntryName(CCSpaceEntry *e) {
    if (e.name) return e.name;
    if (!e.key) return Shorten(e.path);
    NSString *name = L([e.key stringByAppendingString:@".name"]);
    // A part says which folder it is ("The app itself · installs"): an item may have several of one kind.
    return [e.key hasPrefix:@"space.kind."] && e.paths.count == 1 ? [NSString stringWithFormat:@"%@ · %@", name, e.path.lastPathComponent] : name;
}

static NSString *EntryDescription(CCSpaceEntry *e) {
    NSString *key = [e.key stringByAppendingString:@".desc"];
    return key && [CCLocalization.shared hasKey:key] ? L(key) : @"";
}

static BOOL IsCleanable(CCSpaceEntry *e) { return [e.identifier isEqualToString:@"caches"] || e.targetId != nil; }

// ═════════════════════════════ model ═════════════════════════════

@implementation CCDiskModel {
    BOOL _wasScanning, _wasCleaning;
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
        [self setStatus:^NSString *{ return @""; }];
        __weak CCDiskModel *weak = self;
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
    for (CCTargetItem *t in M().targets)
        if (t.isPresent) [targets addObject:t.target];
    CCSpaceScope *scope = [CCSpaceCatalog scopeWithFullDiskAccess:M().hasFullDiskAccess];
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

- (NSArray<CCSpaceEntry *> *)safeParts {
    NSMutableArray *parts = [NSMutableArray array];
    for (CCSpaceEntry *item in self.report.items)
        if (!IsCleanable(item)) [parts addObjectsFromArray:[CCDiskModel safePartsOf:item]];
    return parts;
}

- (long long)safeBytes {
    long long sum = 0;
    for (CCSpaceEntry *e in [self safeParts]) sum += e.bytes;
    return sum;
}

- (BOOL)isBusy:(CCSpaceEntry *)entry { return [_busy containsObject:entry]; }

// ───────────── removing ─────────────

- (void)removeSafe {
    NSArray<CCSpaceEntry *> *parts = [self safeParts];
    if (parts.count == 0 || self.analyzing) return;
    long long bytes = 0;
    for (CCSpaceEntry *e in parts) bytes += e.bytes;
    NSString *title = LF(@"disk.removeSafe.title", CCFormatBytes(bytes));
    NSString *body = LF(@"disk.removeSafe.body", @(parts.count));
    __weak CCDiskModel *weak = self;
    void (^go)(BOOL) = ^(BOOL ok) {
        if (ok) [weak removeAll:parts];
    };
    if (M().confirm) M().confirm(title, body, L(@"disk.removeSafe"), NO, go);
}

- (void)removeAll:(NSArray<CCSpaceEntry *> *)parts {
    if (!self.report || self.analyzing) return;
    BOOL trash = M().settings.useTrash;
    CCSpaceReport *report = self.report;
    [_busy addObjectsFromArray:parts];
    [self changed];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CCDiskMapEngine *engine = [CCDiskMapEngine new];
        NSMutableArray<NSNumber *> *freed = [NSMutableArray array];
        for (CCSpaceEntry *e in parts) [freed addObject:@([engine removeEntry:e useTrash:trash])];
        dispatch_async(dispatch_get_main_queue(), ^{
            long long total = 0;
            for (NSUInteger i = 0; i < parts.count; i++) {
                [self->_busy removeObject:parts[i]];
                if (report == self.report) [self account:parts[i] freed:freed[i].longLongValue trash:trash];
                total += freed[i].longLongValue;
            }
            [self finishRemoval:total trash:trash];
            if (total > 0)
                [NSNotificationCenter.defaultCenter postNotificationName:CCModelToastNotification object:M()
                                                                userInfo:@{ @"symbol": @"checkmark", @"text": LF(@"toast.freed", CCFormatBytes(total)) }];
            [self changed];
        });
    });
}

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
    if (!trash && self.report && M().diskTotal > 0) self.report.free = M().diskFree;
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
    CCButton *_clean, *_copy, *_reveal, *_trash, *_confirm, *_chevron;
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

    CCIconTile *tile = [CCIconTile tileWithSymbol:e.symbol size:38 radius:11 iconSize:16];
    tile.fill = ^NSColor *{ return SegmentColor(segment, 0.16); };
    tile.icon.colorBlock = ^NSColor *{ return SegmentColor(segment, 1); };

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
    for (CCButton *b in @[ _clean, _copy ]) {
        b.padding = NSEdgeInsetsMake(6, 10, 6, 10);
        b.fontSize = 12;
        b.symbolSize = 12;
    }
    _clean.onClick = ^{ M().page = CCPageDashboard; };
    _copy.onClick = ^{ [D() copyCommand:weak.entry]; };
    _reveal = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"folder"];
    _reveal.onClick = ^{ [M() revealPath:weak.entry.path]; };
    _trash = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"trash"];
    _trash.onClick = ^{ [weak askToConfirm]; };
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
    [actions setViews:@[ _clean, _copy, _reveal, _trash, _confirm, _chevron ] inGravity:NSStackViewGravityTrailing];
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

// ═════════════════════════════ the page ═════════════════════════════

@implementation CCDiskPage {
    CCScrollPage *_scroll;
    NSView *_header;
    CCCard *_mapCard, *_listCard;
    CCLabel *_subtitle, *_free, *_status, *_notice, *_safeText, *_listDesc;
    CCButton *_analyze, *_removeSafe;
    CCSpinner *_spinner;
    CCSegmentBar *_bar;
    CCFlowView *_legend;
    NSMutableArray<NSView *> *_legendItems;
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
    NSStackView *header = CCHStack(@[ titles, CCSpacer(), _analyze ], 16);
    [titles setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _header = header;

    // ── the whole disk, band by band ──
    CCLabel *mapTitle = [CCLabel key:@"disk.map" size:18 weight:NSFontWeightSemibold role:CCRoleText];
    _free = Muted(@"", 13);
    NSStackView *mapHeader = CCHStack(@[ mapTitle, CCSpacer(), _free ], 12);
    _bar = [CCSegmentBar new];
    _bar.roundedSegments = YES;
    CCSize(_bar, 0, 26);
    _legend = [CCFlowView new];
    _legend.hSpacing = 22;
    _legend.vSpacing = 8;
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
        item.hidden = YES;
        [_legendItems addObject:item];
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
    _removeSafe = [CCButton buttonWithStyle:CCButtonSuccess title:nil symbol:@"trash"];
    _removeSafe.locKey = @"disk.removeSafe";
    _removeSafe.padding = NSEdgeInsetsMake(10, 16, 10, 16);
    _removeSafe.fontSize = 13;
    _removeSafe.symbolSize = 13;
    _removeSafe.onClick = ^{ [D() removeSafe]; };
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
    NSStackView *list = CCVStack(@[ listTitle, listDesc, _rows ], 4);
    [list setCustomSpacing:16 afterView:listDesc];
    Stretch(list, listDesc);
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

    NSMutableArray *weights = [NSMutableArray array], *colors = [NSMutableArray array];
    for (NSInteger s = 0; s < CCSpaceSegmentCount; s++) {
        long long bytes = r ? r.segments[s] : 0;
        [weights addObject:@(bytes)];
        [colors addObject:SegmentColor(s, 1)];
        _legendNames[s].stringValue = L([@"disk.seg." stringByAppendingString:CCSpaceSegmentName(s)]);
        _legendBytes[s].bytes = bytes;
        _legendItems[s].hidden = bytes <= 0;
    }
    _bar.capacity = r ? (double)r.total : 0;
    [_bar setWeights:weights colors:colors];
    [_legend itemsChanged];
    _legend.hidden = !r;
    _notice.hidden = !r || M().hasFullDiskAccess;

    _status.stringValue = d.statusText;
    _spinner.hidden = !analyzing;
    long long safe = [d safeBytes];
    _safeText.stringValue = LF(@"disk.safe", CCFormatBytes(safe));
    _safeGroup.hidden = !r || analyzing || safe <= 0;

    [self syncRows:r];
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
