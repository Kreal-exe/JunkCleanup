#import "CCPages.h"
#import "CCSettings.h"

static CCModel *M(void) { return CCModel.shared; }

static CCLabel *H1(NSString *key) { return [CCLabel key:key size:28 weight:NSFontWeightSemibold role:CCRoleText]; }
static CCLabel *H2(NSString *key) { return [CCLabel key:key size:18 weight:NSFontWeightSemibold role:CCRoleText]; }
static CCLabel *Muted(NSString *text, CGFloat size) { return [CCLabel text:text size:size weight:NSFontWeightRegular role:CCRoleMuted]; }
static CCLabel *Caption(NSString *text) { return [CCLabel text:text size:11.5 weight:NSFontWeightRegular role:CCRoleFaint]; }

/// Makes a stack child as wide as the stack. A label stretched this way must not hug its text: labels hug at 750, above
/// the priority a window resize drags with, so a hugging label would hold the whole window at its own width.
static void Stretch(NSStackView *stack, NSView *child) {
    [child.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [child setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
}

static CCColorBlock CategoryColor(CCCategory c) {
    return ^NSColor *{ return [CCTheme categoryColor:c]; };
}
static CCColorBlock CategorySoft(CCCategory c) {
    return ^NSColor *{ return [CCTheme categorySoft:c]; };
}

static CCCard *Card(NSView *content, NSEdgeInsets padding) {
    CCCard *card = [CCCard card];
    [card addSubview:content];
    CCPin(content, card, padding);
    return card;
}

static void Stagger(NSArray<NSView *> *views, double step, double base) {
    NSInteger i = 0;
    for (NSView *v in views) {
        if (v.hidden) continue;
        CCEntrance(v, base + i * step, 18);
        i++;
    }
}

@implementation CCScrollPage

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.drawsBackground = NO;
        self.hasVerticalScroller = YES;
        self.autohidesScrollers = YES;
        self.scrollerStyle = NSScrollerStyleOverlay;
        self.borderType = NSNoBorder;
        self.contentView.drawsBackground = NO;
        _document = CCAuto([CCFlippedView new]);
        self.documentView = _document;
        [NSLayoutConstraint activateConstraints:@[
            [_document.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_document.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_document.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor],
        ]];
    }
    return self;
}

@end

@implementation CCPageView

- (void)refresh {}
- (void)playEntrance { self.entrancePlayed = YES; }
- (void)applyLanguage { [self refresh]; }

@end

// ═════════════════════════════ dashboard ═════════════════════════════

@interface CCCategoryCard : CCCard
@property (nonatomic, strong) CCCategoryItem *item;
@property (nonatomic, strong) CCLabel *name, *count, *files, *selected;
@property (nonatomic, strong) CCCounter *bytes;
@property (nonatomic, strong) CCToggle *toggle;
@property (nonatomic, strong) CCSmoothBar *bar;
@end

@implementation CCCategoryCard

+ (instancetype)cardFor:(CCCategoryItem *)item {
    CCCategoryCard *card = [self card];
    card.item = item;
    card.hoverable = YES;
    CCCategory c = item.category;

    CCIconTile *tile = [CCIconTile tileWithSymbol:item.symbol size:40 radius:12 iconSize:18];
    tile.fill = CategorySoft(c);
    tile.icon.colorBlock = CategoryColor(c);
    tile.bounces = YES;
    card.name = [CCLabel text:item.name size:15 weight:NSFontWeightSemibold role:CCRoleText];
    card.count = Caption(@"");
    NSStackView *titles = CCVStack(@[ card.name, card.count ], 2);
    card.toggle = [CCToggle new];
    __weak CCCategoryCard *weak = card;
    card.toggle.onChange = ^(BOOL on) { [M() setCategory:weak.item enabled:on]; };
    NSStackView *top = CCHStack(@[ tile, titles, CCSpacer(), card.toggle ], 14);
    [top setCustomSpacing:0 afterView:titles];

    card.bytes = [CCCounter text:@"" size:26 weight:NSFontWeightSemibold role:CCRoleText];
    card.files = Muted(@"", 13);
    NSStackView *middle = CCHStack(@[ card.bytes, card.files ], 10);
    middle.alignment = NSLayoutAttributeLastBaseline;

    card.bar = [CCSmoothBar new];
    card.bar.fillColor = CategoryColor(c);
    CCSize(card.bar, 0, 6);
    // Three cards share a row: at the narrowest window their labels give way, never the window.
    card.name.wraps = YES;
    for (CCLabel *l in @[ card.name, card.count, card.files ])
        [l setContentCompressionResistancePriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // Shown when only part of the category is ticked, so its total never reads as what a clean would free.
    card.selected = [CCLabel text:@"" size:12 weight:NSFontWeightSemibold role:CCRoleAccent];
    [card.selected setContentCompressionResistancePriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *amount = CCVStack(@[ middle, card.selected ], 4);

    NSStackView *stack = CCVStack(@[ top, amount, card.bar ], 18);
    [stack setCustomSpacing:14 afterView:amount];
    Stretch(stack, top);
    Stretch(stack, card.bar);
    [card addSubview:stack];
    CCPin(stack, card, NSEdgeInsetsMake(18, 20, 18, 20));
    card.onClick = ^{ [M() openCategory:weak.item]; };
    return card;
}

- (void)refresh {
    self.name.stringValue = self.item.name;
    self.count.stringValue = LF(@"dash.targetsCount", @(self.item.presentCount));
    self.bytes.bytes = self.item.bytes;
    self.files.stringValue = LF(@"dash.filesCount", CCFormatCount(self.item.fileCount));
    self.selected.stringValue = LF(@"dash.selectedBytes", CCFormatBytes(self.item.selectedBytes));
    self.selected.hidden = self.item.selectedBytes >= self.item.bytes;
    if (self.toggle.on != self.item.enabled) [self.toggle setOn:self.item.enabled animated:self.window != nil];
    self.bar.value = self.item.share;
    self.shimmering = M().scanning;
}

@end

@interface CCLargestRow : CCBox
@property (nonatomic, strong) CCTargetItem *item;
@property (nonatomic, strong) CCCounter *bytes;
@property (nonatomic, strong) CCLabel *name, *desc, *files;
@property (nonatomic, strong) CCSmoothBar *bar;
@end

@implementation CCLargestRow

+ (instancetype)rowFor:(CCTargetItem *)item {
    CCLargestRow *row = [[self alloc] initWithFrame:NSZeroRect];
    row.item = item;
    row.radius = 12;
    row.toolTip = L(@"details.open");
    CCCategory c = item.target.category;
    CCIconTile *tile = [CCIconTile tileWithSymbol:item.target.symbol size:34 radius:10 iconSize:15];
    tile.fill = CategorySoft(c);
    tile.icon.colorBlock = CategoryColor(c);
    row.name = [CCLabel text:item.name size:14 weight:NSFontWeightSemibold role:CCRoleText];
    row.desc = Caption(item.details);
    [row.desc setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *text = CCVStack(@[ row.name, row.desc ], 2);
    row.bytes = [CCCounter text:@"" size:15 weight:NSFontWeightSemibold role:CCRoleText];
    row.files = Caption(@"");
    NSStackView *right = CCVStack(@[ row.bytes, row.files ], 0);
    right.alignment = NSLayoutAttributeTrailing;
    row.bar = [CCSmoothBar new];
    row.bar.fillColor = CategoryColor(c);
    CCSize(row.bar, 0, 5);
    CCIcon *chevron = [CCIcon symbol:@"chevron.right" size:11 weight:NSFontWeightSemibold role:CCRoleFaint];
    for (NSView *v in @[ tile, text, right, row.bar, chevron ]) [row addSubview:v];
    [text setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10],
        [tile.topAnchor constraintEqualToAnchor:row.topAnchor constant:9],
        [text.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:14],
        [text.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [right.leadingAnchor constraintGreaterThanOrEqualToAnchor:text.trailingAnchor constant:16],
        [right.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-12],
        [right.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [chevron.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [row.bar.leadingAnchor constraintEqualToAnchor:text.leadingAnchor],
        [row.bar.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [row.bar.topAnchor constraintEqualToAnchor:tile.bottomAnchor constant:10],
        [row.bottomAnchor constraintEqualToAnchor:row.bar.bottomAnchor constant:9],
    ]];
    return row;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                         owner:self userInfo:nil]];
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseEntered:(NSEvent *)event { self.fill = ^NSColor *{ return CCTheme.hover; }; }
- (void)mouseExited:(NSEvent *)event { self.fill = nil; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) [M() openDetails:self.item];
}

- (void)refresh {
    self.name.stringValue = self.item.name;
    self.desc.stringValue = self.item.details;
    self.bytes.bytes = self.item.bytes;
    self.files.stringValue = LF(@"dash.filesCount", CCFormatCount(self.item.fileCount));
    self.bar.value = self.item.share;
}

@end

@interface CCInsightRow : CCBox
@property (nonatomic, strong) CCInsight *insight;
@property (nonatomic, strong) CCLabel *title, *detail, *size;
@property (nonatomic, strong) CCButton *action;
@end

@implementation CCInsightRow

+ (instancetype)rowFor:(CCInsight *)insight {
    CCInsightRow *row = [[self alloc] initWithFrame:NSZeroRect];
    row.insight = insight;
    row.radius = 14;
    row.fill = ^NSColor *{ return CCTheme.inset; };
    CCIconTile *tile = [CCIconTile tileWithSymbol:insight.symbol size:38 radius:11 iconSize:16];
    tile.fill = ^NSColor *{ return CCTheme.warningSoft; };
    tile.icon.role = CCRoleWarning;
    row.title = [CCLabel text:@"" size:14 weight:NSFontWeightSemibold role:CCRoleText];
    row.detail = Muted(@"", 12.5);
    row.detail.wraps = YES;
    NSStackView *text = CCVStack(@[ row.title, row.detail ], 3);
    Stretch(text, row.detail);
    row.size = [CCLabel text:CCFormatBytes(insight.bytes) size:16 weight:NSFontWeightSemibold role:CCRoleText];
    row.size.font = CCDigitsFont(16, NSFontWeightSemibold);
    [row.size setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    row.action = [CCButton buttonWithStyle:CCButtonGhost title:@"" symbol:insight.action == CCInsightActionCopyCommand ? @"doc.on.doc" : @"arrow.up.forward.app"];
    row.action.padding = NSEdgeInsetsMake(8, 12, 8, 12);
    row.action.fontSize = 12.5;
    row.action.hidden = insight.action == CCInsightActionNone;
    __weak CCInsightRow *weak = row;
    row.action.onClick = ^{ [M() runInsightAction:weak.insight]; };
    for (NSView *v in @[ tile, text, row.size, row.action ]) [row addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [tile.topAnchor constraintEqualToAnchor:row.topAnchor constant:14],
        [text.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:14],
        [text.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:14],
        [text.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.bottomAnchor constraintGreaterThanOrEqualToAnchor:text.bottomAnchor constant:14],
        [row.bottomAnchor constraintGreaterThanOrEqualToAnchor:tile.bottomAnchor constant:14],
        [row.size.leadingAnchor constraintEqualToAnchor:text.trailingAnchor constant:16],
        [row.size.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.action.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.action.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
    ]];
    NSLayoutConstraint *sizeToAction = [row.action.leadingAnchor constraintEqualToAnchor:row.size.trailingAnchor constant:16];
    NSLayoutConstraint *sizeToEdge = [row.size.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16];
    sizeToAction.active = !row.action.hidden;
    sizeToEdge.active = row.action.hidden;
    [row refresh];
    return row;
}

- (void)refresh {
    self.title.stringValue = L(self.insight.titleKey);
    NSMutableArray *args = [NSMutableArray arrayWithObject:CCFormatBytes(self.insight.bytes)];
    [args addObjectsFromArray:self.insight.extra];
    self.detail.stringValue = CCLF(self.insight.detailKey, args);
    self.action.title = L(self.insight.action == CCInsightActionCopyCommand ? @"insight.copyCommand" : @"insight.open");
}

@end

/// A card that says when it has been laid out (the hero decides there how its parts are arranged).
@interface CCLayoutCard : CCCard
@property (nonatomic, copy, nullable) void (^onLayout)(void);
@end

@implementation CCLayoutCard
- (void)layout {
    [super layout];
    if (self.onLayout) self.onLayout();
}
@end

@implementation CCDashboardPage {
    CCScrollPage *_scroll;
    CCCard *_hero, *_largestCard, *_insightsCard;
    NSView *_categoriesHeader;
    CCRing *_ring;
    CCCounter *_number, *_unit;
    CCLabel *_reclaimable, *_foundSoFar, *_status, *_current, *_modeText;
    CCIcon *_modeIcon;
    CCSegmentBar *_segments;
    NSStackView *_heroRight, *_heroSummary, *_grid;
    NSUInteger _gridColumns;
    CCFlowView *_legend;
    NSMutableArray<CCCounter *> *_legendBytes;
    NSMutableArray<CCLabel *> *_legendNames;
    CCButton *_scanButton, *_cleanButton;
    NSMutableArray<CCCategoryCard *> *_categoryCards;
    NSStackView *_largestRows, *_insightRows;
    CCLabel *_allClean;
    NSArray<CCTargetItem *> *_shownTop;
    NSArray<CCInsight *> *_shownInsights;
    BOOL _hadResults, _hadInsights;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self build];
    return self;
}

- (void)build {
    _scroll = [CCScrollPage new];
    [self addSubview:_scroll];
    CCPin(_scroll, self, NSEdgeInsetsMake(0, 0, 0, 0));

    // ── hero ──
    _ring = [CCRing new];
    _number = [CCCounter text:@"" size:42 weight:NSFontWeightBold role:CCRoleText];
    _number.part = CCCounterNumber;
    _number.duration = 900;
    _unit = [CCCounter text:@"" size:15 weight:NSFontWeightSemibold role:CCRoleMuted];
    _unit.part = CCCounterUnit;
    _unit.duration = 900;
    NSStackView *value = CCHStack(@[ _number, _unit ], 6);
    value.alignment = NSLayoutAttributeLastBaseline;
    _reclaimable = Caption(L(@"dash.reclaimable"));
    _reclaimable.locKey = @"dash.reclaimable";
    _foundSoFar = Caption(L(@"dash.foundSoFar"));
    _foundSoFar.locKey = @"dash.foundSoFar";
    NSStackView *center = CCVStack(@[ value, _reclaimable, _foundSoFar ], 0);
    center.alignment = NSLayoutAttributeCenterX;
    [_ring addSubview:center];
    [NSLayoutConstraint activateConstraints:@[
        [center.centerXAnchor constraintEqualToAnchor:_ring.centerXAnchor],
        [center.centerYAnchor constraintEqualToAnchor:_ring.centerYAnchor],
    ]];

    CCLabel *title = H1(@"dash.title");
    title.wraps = YES;
    _status = Muted(@"", 13);
    _status.wraps = YES;
    _current = Caption(@"");
    [_current setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _segments = [CCSegmentBar new];
    CCSize(_segments, 0, 12);
    _legend = [CCFlowView new];
    _legendBytes = [NSMutableArray array];
    _legendNames = [NSMutableArray array];
    NSMutableArray *legendItems = [NSMutableArray array];
    for (CCCategoryItem *c in M().categories) {
        CCBox *dot = [[CCBox alloc] initWithFrame:NSZeroRect];
        dot.radius = 4;
        dot.fill = CategoryColor(c.category);
        CCSize(dot, 8, 8);
        CCLabel *name = Muted(c.name, 12.5);
        CCCounter *bytes = [CCCounter text:@"" size:12.5 weight:NSFontWeightSemibold role:CCRoleText];
        __weak CCFlowView *legend = _legend;
        bytes.onRender = ^{ [legend itemsChanged]; };
        [_legendNames addObject:name];
        [_legendBytes addObject:bytes];
        NSStackView *item = CCHStack(@[ dot, name, bytes ], 7);
        [item setCustomSpacing:6 afterView:name];
        [legendItems addObject:item];
    }
    [_legend setItems:legendItems];
    NSStackView *summary = CCVStack(@[ title, _status, _current, _segments, _legend ], 0);
    [summary setCustomSpacing:6 afterView:title];
    [summary setCustomSpacing:4 afterView:_status];
    [summary setCustomSpacing:24 afterView:_current];
    [summary setCustomSpacing:14 afterView:_segments];
    for (NSView *v in @[ title, _status, _segments, _legend ]) Stretch(summary, v);

    _scanButton = [CCButton buttonWithStyle:CCButtonPrimary title:@"" symbol:@"play"];
    _scanButton.onClick = ^{ [M() toggleScan]; };
    _cleanButton = [CCButton buttonWithStyle:CCButtonDanger title:@"" symbol:@"trash"];
    _cleanButton.onClick = ^{ [M() clean]; };
    _modeIcon = [CCIcon symbol:@"trash" size:12 weight:NSFontWeightRegular role:CCRoleFaint];
    _modeText = Caption(@"");
    NSStackView *mode = CCHStack(@[ _modeIcon, _modeText ], 7);
    NSStackView *actions = CCVStack(@[ _scanButton, _cleanButton, mode ], 14);
    actions.alignment = NSLayoutAttributeCenterX;
    [actions setCustomSpacing:16 afterView:_cleanButton];
    Stretch(actions, _scanButton);
    Stretch(actions, _cleanButton);
    CCSize(actions, 220, 0);

    // The buttons sit beside the summary when there is room and drop under it in a narrow window (see -layout).
    _heroRight = CCHStack(@[ summary, actions ], 32);
    _heroRight.alignment = NSLayoutAttributeCenterY;
    _heroSummary = summary;
    [_heroRight setClippingResistancePriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *heroRow = CCHStack(@[ _ring, _heroRight ], 36);
    [summary setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_heroRight setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    // Under each other, the summary still takes the whole width (beside the buttons this cannot hold, and gives way).
    NSLayoutConstraint *summaryFill = [summary.widthAnchor constraintEqualToAnchor:_heroRight.widthAnchor];
    summaryFill.priority = 480;
    summaryFill.active = YES;
    CCLayoutCard *hero = [CCLayoutCard card];
    [hero addSubview:heroRow];
    CCPin(heroRow, hero, NSEdgeInsetsMake(30, 32, 30, 32));
    __weak CCDashboardPage *weakPage = self;
    hero.onLayout = ^{ [weakPage arrangeHero]; };
    _hero = hero;

    // ── categories ──
    CCLabel *categoriesTitle = H2(@"dash.categories");
    _categoriesHeader = CCHStack(@[ categoriesTitle, CCSpacer(), [self selectButtons] ], 4);

    _categoryCards = [NSMutableArray array];
    for (CCCategoryItem *c in M().categories) [_categoryCards addObject:[CCCategoryCard cardFor:c]];
    NSStackView *grid = CCVStack(@[], 12);
    _grid = grid;
    [self arrangeGrid:3];

    // ── largest ──
    _largestRows = CCVStack(@[], 0);
    _allClean = Muted(L(@"dash.allClean"), 13);
    _allClean.locKey = @"dash.allClean";
    NSStackView *largest = CCVStack(@[ H2(@"dash.largest"), _largestRows, _allClean ], 7);
    _largestRows.spacing = 2;
    Stretch(largest, _largestRows);
    _largestCard = Card(largest, NSEdgeInsetsMake(22, 24, 22, 24));

    // ── insights ──
    _insightRows = CCVStack(@[], 8);
    CCLabel *insightSubtitle = Muted(L(@"insight.subtitle"), 12.5);
    insightSubtitle.locKey = @"insight.subtitle";
    NSStackView *insights = CCVStack(@[ H2(@"insight.title"), insightSubtitle, _insightRows ], 4);
    [insights setCustomSpacing:12 afterView:insightSubtitle];
    Stretch(insights, _insightRows);
    _insightsCard = Card(insights, NSEdgeInsetsMake(22, 24, 22, 24));

    NSStackView *page = CCVStack(@[ _hero, _categoriesHeader, grid, _largestCard, _insightsCard ], 0);
    [page setCustomSpacing:30 afterView:_hero];
    [page setCustomSpacing:12 afterView:_categoriesHeader];
    [page setCustomSpacing:22 afterView:grid];
    [page setCustomSpacing:16 afterView:_largestCard];
    for (NSView *v in @[ _hero, grid, _largestCard, _insightsCard ]) Stretch(page, v);
    [_categoriesHeader.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:4].active = YES;
    [_categoriesHeader.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-4].active = YES;

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
    _largestCard.hidden = YES;
    _insightsCard.hidden = YES;
}

// The ring (204), the summary and the buttons (220) need about 860 pt side by side; in a narrower window the summary
// would be squeezed until its title breaks mid-word, so the buttons go under it.
/// Three cards a row, or two when a card would be too narrow for its name.
- (void)arrangeGrid:(NSUInteger)columns {
    if (columns == _gridColumns) return;
    _gridColumns = columns;
    for (NSView *row in [_grid.arrangedSubviews copy]) [row removeFromSuperview];
    for (NSUInteger start = 0; start < _categoryCards.count; start += columns) {
        NSMutableArray *cards = [NSMutableArray array];
        for (NSUInteger i = start; i < MIN(start + columns, _categoryCards.count); i++) {
            [_categoryCards[i] removeFromSuperview];
            [cards addObject:_categoryCards[i]];
        }
        NSStackView *row = CCHStack(cards, 12);
        row.distribution = NSStackViewDistributionFillEqually;
        row.alignment = NSLayoutAttributeTop;
        [_grid addArrangedSubview:row];
        Stretch(_grid, row);
    }
}

- (void)arrangeHero {
    CGFloat width = NSWidth(_hero.bounds);
    if (width <= 0) return;
    [self arrangeGrid:(width - 24) / 3 >= 260 ? 3 : 2];
    BOOL fits = width - 64 - 204 - 36 >= 300 + 32 + 220;
    NSUserInterfaceLayoutOrientation orientation = fits ? NSUserInterfaceLayoutOrientationHorizontal : NSUserInterfaceLayoutOrientationVertical;
    if (_heroRight.orientation == orientation) return;
    _heroRight.orientation = orientation;
    _heroRight.alignment = fits ? NSLayoutAttributeCenterY : NSLayoutAttributeLeading;
    [_heroRight setCustomSpacing:fits ? 32 : 22 afterView:_heroSummary];
    _hero.needsLayout = YES;
}

- (NSView *)selectButtons {
    CCLabel *select = Caption(L(@"dash.select"));
    select.locKey = @"dash.select";
    CCButton *safe = [CCButton buttonWithStyle:CCButtonSubtle title:nil symbol:nil];
    safe.locKey = @"dash.selectSafe";
    safe.onClick = ^{ [M() selectSafe]; };
    CCButton *all = [CCButton buttonWithStyle:CCButtonSubtle title:nil symbol:nil];
    all.locKey = @"dash.selectAll";
    all.onClick = ^{ [M() selectAll]; };
    CCButton *none = [CCButton buttonWithStyle:CCButtonSubtle title:nil symbol:nil];
    none.locKey = @"dash.selectNone";
    none.onClick = ^{ [M() selectNone]; };
    NSStackView *s = CCHStack(@[ select, safe, all, none ], 0);
    [s setCustomSpacing:4 afterView:select];
    return s;
}

- (void)refresh {
    CCModel *m = M();
    BOOL scanning = m.scanning;
    // The angle first, so the spinner's last lap already knows where to land.
    [_ring setAngle:m.ringAngle animated:YES];
    _ring.spinning = scanning;
    _number.bytes = m.displayBytes;
    _unit.bytes = m.displayBytes;
    _reclaimable.hidden = scanning;
    _foundSoFar.hidden = !scanning;
    _status.stringValue = m.statusText;
    _current.stringValue = m.currentTargetName;
    _current.hidden = !scanning;

    NSMutableArray *weights = [NSMutableArray array], *colors = [NSMutableArray array];
    for (NSUInteger i = 0; i < m.categories.count; i++) {
        CCCategoryItem *c = m.categories[i];
        [weights addObject:@(c.bytes)];
        [colors addObject:[CCTheme categoryColor:c.category]];
        _legendNames[i].stringValue = c.name;
        _legendBytes[i].bytes = c.bytes;
        _legendBytes[i].hidden = c.bytes == 0;
    }
    [_segments setWeights:weights colors:colors];
    [_legend itemsChanged];

    _scanButton.title = scanning ? L(@"dash.stop") : m.hasResults ? L(@"dash.rescan") : L(@"dash.scan");
    _scanButton.symbol = scanning ? @"stop" : @"play";
    _cleanButton.title = m.selectedBytes > 0 ? LF(@"dash.clean", CCFormatBytes(m.selectedBytes)) : L(@"dash.cleanEmpty");
    _cleanButton.enabled = m.canClean;
    _cleanButton.pulsing = m.canClean;
    _modeText.stringValue = m.settings.useTrash ? L(@"dash.modeRecycle") : L(@"dash.modePermanent");
    _modeIcon.symbol = m.settings.useTrash ? @"trash" : @"flame";

    for (CCCategoryCard *card in _categoryCards) [card refresh];

    // Largest targets: rebuilt when the set changes, replayed when results arrive.
    BOOL showLargest = m.hasResults;
    if (![_shownTop isEqualToArray:m.topTargets]) {
        _shownTop = m.topTargets;
        for (NSView *v in [_largestRows.arrangedSubviews copy]) [v removeFromSuperview];
        for (CCTargetItem *t in m.topTargets) {
            CCLargestRow *row = [CCLargestRow rowFor:t];
            [_largestRows addArrangedSubview:row];
            Stretch(_largestRows, row);
        }
    }
    for (CCLargestRow *row in _largestRows.arrangedSubviews) [row refresh];
    _allClean.hidden = !m.nothingFound;
    _largestCard.hidden = !showLargest;
    if (showLargest && !_hadResults) {
        CCEntrance(_largestCard, 0, 18);
        Stagger(_largestRows.arrangedSubviews, 50, 0);
    }
    _hadResults = showLargest;

    BOOL showInsights = m.insights.count > 0;
    if (![_shownInsights isEqualToArray:m.insights]) {
        _shownInsights = m.insights;
        for (NSView *v in [_insightRows.arrangedSubviews copy]) [v removeFromSuperview];
        for (CCInsight *i in m.insights) {
            CCInsightRow *row = [CCInsightRow rowFor:i];
            [_insightRows addArrangedSubview:row];
            Stretch(_insightRows, row);
        }
        if (showInsights && _hadInsights) Stagger(_insightRows.arrangedSubviews, 60, 0);
    }
    for (CCInsightRow *row in _insightRows.arrangedSubviews) [row refresh];
    _insightsCard.hidden = !showInsights;
    if (showInsights && !_hadInsights) {
        CCEntrance(_insightsCard, 0, 18);
        Stagger(_insightRows.arrangedSubviews, 60, 0);
    }
    _hadInsights = showInsights;
}

- (void)playEntrance {
    [super playEntrance];
    CCEntrance(_hero, 0, 18);
    CCEntrance(_categoriesHeader, 90, 18);
    Stagger(_categoryCards, 60, 0);
}

@end

// ═════════════════════════════ targets ═════════════════════════════

@implementation CCCollapsible {
    NSLayoutConstraint *_height, *_top;
    double _progress;
    CCTween *_tween;
}

- (instancetype)initWithContent:(NSView *)content {
    if ((self = [super initWithFrame:NSZeroRect])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        _content = content;
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        _height = [self.heightAnchor constraintEqualToConstant:0];
        _top = [content.topAnchor constraintEqualToAnchor:self.topAnchor constant:-12];
        [NSLayoutConstraint activateConstraints:@[
            _height, _top,
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
        content.alphaValue = 0;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)apply {
    double p = MAX(0, MIN(1, _progress));
    CGFloat full = self.content.fittingSize.height;
    _height.constant = round(full * p);
    _top.constant = (1 - p) * -12;
    self.content.alphaValue = p;
}

- (void)setOpen:(BOOL)open { [self setOpen:open animated:NO]; }

- (void)setOpen:(BOOL)open animated:(BOOL)animated {
    _open = open;
    [_tween stop];
    double to = open ? 1 : 0;
    if (!animated || !self.window) {
        _progress = to;
        [self apply];
        return;
    }
    __weak CCCollapsible *weak = self;
    _tween = [CCTween from:_progress to:to duration:open ? 420 : 260 delay:0 ease:open ? CCEaseOutStrong : CCEaseIn
                    update:^(double v) {
        CCCollapsible *s = weak;
        if (!s) return;
        s->_progress = v;
        [s apply];
    } completion:nil];
}

- (void)contentChanged {
    if (_tween.running) return;
    [self apply];
}

@end

@interface CCTargetRow : CCCard
@property (nonatomic, strong) CCTargetItem *item;
@property (nonatomic, strong) CCCheck *check;
@property (nonatomic, strong) CCLabel *name, *desc, *roots, *status, *files;
@property (nonatomic, strong) CCPill *risk, *access;
@property (nonatomic, strong) CCCounter *bytes;
@property (nonatomic, strong) CCButton *chevron;
@property (nonatomic, strong) CCCollapsible *details;
@property (nonatomic, strong) NSStackView *entries;
@property (nonatomic, strong) NSStackView *openButtons;
@property (nonatomic, strong) CCLabel *noEntries;
@property (nonatomic, copy) NSArray<CCEntry *> *shownEntries;
@property (nonatomic) BOOL wasExpanded;
@end

@implementation CCTargetRow

+ (instancetype)rowFor:(CCTargetItem *)item {
    CCTargetRow *row = [self card];
    row.item = item;
    row.radius = 16;
    CCCategory c = item.target.category;
    __weak CCTargetRow *weak = row;

    row.check = [CCCheck new];
    row.check.onChange = ^(BOOL on) { [M() setTarget:weak.item enabled:on]; };
    CCIconTile *tile = [CCIconTile tileWithSymbol:item.target.symbol size:38 radius:11 iconSize:16];
    tile.fill = CategorySoft(c);
    tile.icon.colorBlock = CategoryColor(c);
    tile.bounces = YES;

    row.name = [CCLabel text:item.name size:14.5 weight:NSFontWeightSemibold role:CCRoleText];
    // Just below the window's own size priority: a long name or status gives way before the window does.
    [row.name setContentCompressionResistancePriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    CCRisk risk = item.target.risk;
    row.risk = [CCPill pillWithText:item.riskText symbol:nil color:^NSColor *{ return [CCTheme riskColor:risk]; }
                               soft:^NSColor *{ return [CCTheme riskSoft:risk]; }];
    row.risk.toolTip = item.riskHint;
    row.access = [CCPill pillWithText:L(@"targets.admin") symbol:@"lock.shield" color:^NSColor *{ return CCTheme.warning; }
                                 soft:^NSColor *{ return CCTheme.warningSoft; }];
    row.access.toolTip = L(@"titlebar.adminHint");
    NSStackView *titleRow = CCHStack(@[ row.name, row.risk, row.access ], 10);
    [titleRow setCustomSpacing:6 afterView:row.risk];
    row.desc = Muted(item.details, 12.5);
    [row.desc setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    row.roots = [CCLabel text:item.rootsText size:11 weight:NSFontWeightRegular role:CCRoleFaint];
    [row.roots setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    row.roots.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSStackView *text = CCVStack(@[ titleRow, row.desc, row.roots ], 3);
    [text setCustomSpacing:4 afterView:row.desc];
    Stretch(text, row.desc);
    Stretch(text, row.roots);

    row.status = Caption(@"");
    [row.status setContentCompressionResistancePriority:NSLayoutPriorityWindowSizeStayPut - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
    row.bytes = [CCCounter text:@"" size:16 weight:NSFontWeightSemibold role:CCRoleText];
    row.files = Caption(@"");
    NSStackView *size = CCVStack(@[ row.bytes, row.files ], 0);
    size.alignment = NSLayoutAttributeTrailing;
    [size.widthAnchor constraintGreaterThanOrEqualToConstant:96].active = YES;
    row.chevron = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"chevron.down"];
    row.chevron.iconView.wantsLayer = YES;
    row.chevron.onClick = ^{ [M() toggleExpanded:weak.item]; };

    NSStackView *line = CCHStack(@[ row.check, tile, text, row.status, size, row.chevron ], 16);
    [line setCustomSpacing:14 afterView:tile];
    [line setCustomSpacing:16 afterView:text];
    [line setCustomSpacing:18 afterView:row.status];
    [line setCustomSpacing:12 afterView:size];
    [text setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    row.details = [[CCCollapsible alloc] initWithContent:[row buildDetails]];
    NSStackView *stack = CCVStack(@[ line, row.details ], 0);
    Stretch(stack, line);
    Stretch(stack, row.details);
    [row addSubview:stack];
    CCPin(stack, row, NSEdgeInsetsMake(14, 18, 14, 18));
    row.alphaValue = item.isPresent ? 1 : 0.45;
    row.toolTip = L(@"details.open");
    row.onClick = ^{ [M() openDetails:weak.item]; };
    return row;
}

- (NSView *)buildDetails {
    CCLabel *heading = [CCLabel key:@"targets.topEntries" size:11.5 weight:NSFontWeightSemibold role:CCRoleFaint];
    self.openButtons = CCHStack(@[], 4);
    NSStackView *header = CCHStack(@[ heading, CCSpacer(), self.openButtons ], 8);
    self.entries = CCVStack(@[], 4);
    self.noEntries = [CCLabel key:@"targets.noEntries" size:11.5 weight:NSFontWeightRegular role:CCRoleFaint];
    NSStackView *body = CCVStack(@[ header, self.entries, self.noEntries ], 8);
    Stretch(body, header);
    Stretch(body, self.entries);
    NSView *container = CCAuto([CCFlippedView new]);
    [container addSubview:body];
    CCPin(body, container, NSEdgeInsetsMake(16, 68, 4, 0));
    return container;
}

- (void)rebuildEntries {
    for (NSView *v in [self.entries.arrangedSubviews copy]) [v removeFromSuperview];
    for (NSView *v in [self.openButtons.arrangedSubviews copy]) [v removeFromSuperview];
    for (NSString *root in self.item.roots) {
        CCButton *open = [CCButton buttonWithStyle:CCButtonSubtle title:L(@"targets.openFolder") symbol:@"folder"];
        open.padding = NSEdgeInsetsMake(4, 8, 4, 8);
        open.fontSize = 12;
        open.symbolSize = 12;
        open.toolTip = root;
        open.onClick = ^{ [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:root]]; };
        [self.openButtons addArrangedSubview:open];
    }
    for (CCEntry *e in self.item.topEntries) {
        NSView *entry = CCAuto([CCFlippedView new]);
        CCSize(entry, 0, 30);
        CCSmoothBar *bar = [CCSmoothBar new];
        bar.duration = 600;
        bar.fillColor = ^NSColor *{ return CCTheme.accentSoft; };
        bar.trackColor = ^NSColor *{ return CCTheme.inset; };
        CCIcon *icon = [CCIcon symbol:e.isDirectory ? @"folder" : @"doc" size:12 weight:NSFontWeightRegular role:CCRoleMuted];
        CCLabel *name = [CCLabel text:e.name size:12.5 weight:NSFontWeightRegular role:CCRoleText];
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        name.toolTip = e.path;
        [name setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        CCLabel *files = Caption(LF(@"dash.filesCount", CCFormatCount(e.files)));
        CCLabel *bytes = [CCLabel text:CCFormatBytes(e.bytes) size:12.5 weight:NSFontWeightSemibold role:CCRoleText];
        bytes.alignment = NSTextAlignmentRight;
        for (NSView *v in @[ bar, icon, name, files, bytes ]) [entry addSubview:v];
        CCPin(bar, entry, NSEdgeInsetsMake(0, 0, 0, 0));
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:entry.leadingAnchor constant:10],
            [icon.centerYAnchor constraintEqualToAnchor:entry.centerYAnchor],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
            [name.centerYAnchor constraintEqualToAnchor:entry.centerYAnchor],
            [files.leadingAnchor constraintGreaterThanOrEqualToAnchor:name.trailingAnchor constant:10],
            [files.centerYAnchor constraintEqualToAnchor:entry.centerYAnchor],
            [bytes.leadingAnchor constraintEqualToAnchor:files.trailingAnchor constant:14],
            [bytes.widthAnchor constraintEqualToConstant:90],
            [bytes.trailingAnchor constraintEqualToAnchor:entry.trailingAnchor constant:-10],
            [bytes.centerYAnchor constraintEqualToAnchor:entry.centerYAnchor],
        ]];
        [self.entries addArrangedSubview:entry];
        Stretch(self.entries, entry);
        [bar setValue:self.item.bytes > 0 ? (double)e.bytes / self.item.bytes : 0 animated:NO];
    }
    self.noEntries.hidden = self.item.topEntries.count > 0;
}

- (void)refresh {
    CCTargetItem *t = self.item;
    self.name.stringValue = t.name;
    self.desc.stringValue = t.details;
    self.roots.stringValue = t.rootsText;
    self.roots.toolTip = t.rootsText;
    self.risk.label.stringValue = t.riskText;
    self.risk.toolTip = t.riskHint;
    self.access.label.stringValue = L(@"targets.admin");
    self.access.hidden = !t.showsAccessBadge;
    if (self.check.checked != t.enabled) [self.check setChecked:t.enabled animated:self.window != nil];
    self.check.enabled = t.isPresent;
    self.status.stringValue = t.statusText;
    self.status.role = t.state == CCTargetDenied ? CCRoleWarning : t.state == CCTargetScanning ? CCRoleAccent : CCRoleFaint;
    self.status.hidden = t.statusText.length == 0;
    self.bytes.bytes = t.bytes;
    self.files.stringValue = LF(@"dash.filesCount", CCFormatCount(t.fileCount));

    if (![self.shownEntries isEqualToArray:t.topEntries]) {
        self.shownEntries = t.topEntries;
        if (t.expanded || self.details.open) [self rebuildEntries];
    }
    if (t.expanded != self.wasExpanded) {
        self.wasExpanded = t.expanded;
        if (t.expanded) [self rebuildEntries];
        [self.details setOpen:t.expanded animated:YES];
        CCTransformView(self.chevron.iconView, CCXformMake(1, 0, t.expanded ? 180 : 0), 300, CCEaseCubicOut);
    } else {
        [self.details contentChanged];
    }
}

@end

@implementation CCTargetsPage {
    NSView *_header;
    CCLabel *_subtitle, *_notFound;
    CCSearchField *_search;
    NSMutableArray<CCChip *> *_chips;
    NSArray<NSString *> *_filters;
    CCScrollPage *_scroll;
    NSStackView *_list;
    NSMutableDictionary<NSString *, CCTargetRow *> *_rows;
    NSString *_shownFilter, *_shownSearch;
    NSStackView *_filterRow, *_chipRow, *_selectRow;
    NSView *_filterSpacer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self build];
    return self;
}

- (void)build {
    _subtitle = Muted(@"", 13);
    NSStackView *titles = CCVStack(@[ H1(@"targets.title"), _subtitle ], 4);
    _search = [CCSearchField new];
    _search.placeholderKey = @"targets.search";
    _search.onChange = ^(NSString *text) { M().searchText = text; };
    [_search.widthAnchor constraintEqualToConstant:320].active = YES;
    NSStackView *top = CCHStack(@[ titles, CCSpacer(), _search ], 12);

    _filters = @[ @"All", @"System", @"Browsers", @"Developer", @"Apps", @"Gaming", @"Custom" ];
    _chips = [NSMutableArray array];
    for (NSString *f in _filters) {
        CCChip *chip = [CCChip chipWithTitle:@""];
        chip.locKey = [f isEqualToString:@"All"] ? @"cat.all" : [@"cat." stringByAppendingString:f];
        chip.onClick = ^{ M().filter = f; };
        [_chips addObject:chip];
    }
    NSStackView *chips = CCHStack(_chips, 8);
    CCLabel *select = Caption(L(@"dash.select"));
    select.locKey = @"dash.select";
    NSMutableArray *buttons = [NSMutableArray arrayWithObject:select];
    NSArray *keys = @[ @"dash.selectSafe", @"dash.selectAll", @"dash.selectNone" ];
    NSArray *actions = @[ ^{ [M() selectSafe]; }, ^{ [M() selectAll]; }, ^{ [M() selectNone]; } ];
    for (NSUInteger i = 0; i < 3; i++) {
        CCButton *b = [CCButton buttonWithStyle:CCButtonSubtle title:nil symbol:nil];
        b.locKey = keys[i];
        b.onClick = actions[i];
        [buttons addObject:b];
    }
    NSStackView *selectRow = CCHStack(buttons, 0);
    [selectRow setCustomSpacing:4 afterView:select];
    _filterSpacer = CCSpacer();
    NSStackView *filterRow = CCHStack(@[ chips, _filterSpacer, selectRow ], 12);
    _filterRow = filterRow;
    // Below the window's own priority: in one row it would otherwise hold the window too wide to ever reach the width
    // at which -layout drops the select buttons to a second line.
    [filterRow setClippingResistancePriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _chipRow = chips;
    _selectRow = selectRow;

    NSStackView *header = CCVStack(@[ top, filterRow ], 18);
    Stretch(header, top);
    Stretch(header, filterRow);
    _header = header;
    [self addSubview:header];

    _scroll = [CCScrollPage new];
    [self addSubview:_scroll];
    _list = CCVStack(@[], 10);
    _notFound = Muted(L(@"targets.notFound"), 13);
    _notFound.locKey = @"targets.notFound";
    NSStackView *content = CCVStack(@[ _list, _notFound ], 12);
    Stretch(content, _list);
    [_scroll.document addSubview:content];
    CCPin(content, _scroll.document, NSEdgeInsetsMake(2, 32, 28, 26));

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
        [_scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _rows = [NSMutableDictionary dictionary];
    [self syncRows];
}

- (void)syncRows {
    NSMutableArray *wanted = [NSMutableArray array];
    for (CCTargetItem *t in M().targets) {
        CCTargetRow *row = _rows[t.identifier];
        if (!row) {
            row = [CCTargetRow rowFor:t];
            _rows[t.identifier] = row;
        }
        [wanted addObject:row];
    }
    if (![_list.arrangedSubviews isEqualToArray:wanted]) {
        for (NSView *v in [_list.arrangedSubviews copy]) [v removeFromSuperview];
        for (CCTargetRow *row in wanted) {
            [_list addArrangedSubview:row];
            Stretch(_list, row);
        }
        NSSet *keep = [NSSet setWithArray:[M().targets valueForKey:@"identifier"]];
        for (NSString *key in _rows.allKeys)
            if (![keep containsObject:key]) [_rows removeObjectForKey:key];
    }
}

- (void)refresh {
    CCModel *m = M();
    [self syncRows];
    _subtitle.stringValue = LF(@"targets.subtitle", @(m.presentCount), @(m.selectedCount), CCFormatBytes(m.selectedBytes));
    for (NSUInteger i = 0; i < _chips.count; i++) _chips[i].checked = [_filters[i] isEqualToString:m.filter];

    BOOL filterChanged = ![_shownFilter isEqualToString:m.filter] || ![_shownSearch isEqualToString:m.searchText];
    _shownFilter = m.filter;
    _shownSearch = m.searchText;
    NSInteger visible = 0;
    for (CCTargetRow *row in _list.arrangedSubviews) {
        BOOL show = [m targetMatchesFilter:row.item];
        row.hidden = !show;
        visible += show;
        [row refresh];
    }
    _notFound.hidden = visible > 0;
    if (filterChanged && self.entrancePlayed && !self.hidden) Stagger(_list.arrangedSubviews, 28, 0);
}

// Seven chips and the select buttons need about 1150 pt in Russian: in one row they would hold the window
// wider than a 1280 pt screen, so the buttons drop to a second line when the page is narrower than that.
- (void)layout {
    BOOL fits = NSWidth(self.bounds) - 64 >= _chipRow.fittingSize.width + 12 + _selectRow.fittingSize.width;
    NSUserInterfaceLayoutOrientation orientation = fits ? NSUserInterfaceLayoutOrientationHorizontal : NSUserInterfaceLayoutOrientationVertical;
    if (_filterRow.orientation != orientation) {
        _filterRow.orientation = orientation;
        _filterRow.alignment = fits ? NSLayoutAttributeCenterY : NSLayoutAttributeLeading;
        _filterSpacer.hidden = !fits;
    }
    [super layout];
}

- (void)playEntrance {
    [super playEntrance];
    CCEntrance(_header, 0, 18);
    Stagger(_list.arrangedSubviews, 28, 0);
}

@end

// ═════════════════════════════ settings ═════════════════════════════

@implementation CCSettingsPage {
    NSMutableArray<NSView *> *_cards;
    CCLabel *_title;
    CCPopupField *_language;
    NSArray<CCChip *> *_themeChips, *_skipChips;
    CCToggle *_animations, *_translucency, *_scanOnStartup, *_useTrash, *_diskWithScan, *_confirmClean;
    CCSettingRow *_deleteRow;
    NSStackView *_folders;
    CCLabel *_noFolders;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self build];
    return self;
}

- (void)save { [M() saveSettings]; }

- (void)build {
    CCScrollPage *scroll = [CCScrollPage new];
    [self addSubview:scroll];
    CCPin(scroll, self, NSEdgeInsetsMake(0, 0, 0, 0));
    CCSettings *s = M().settings;
    __weak CCSettingsPage *weak = self;

    // ── general ──
    _language = [CCPopupField new];
    _language.onSelect = ^(NSInteger index) {
        NSString *code = index == 0 ? @"auto" : CCLocalization.languages[(NSUInteger)index - 1].code;
        M().settings.language = code;
        [weak save];
        [CCLocalization.shared setLanguage:code];
    };
    NSMutableArray *themeChips = [NSMutableArray array];
    for (NSString *mode in @[ @"dark", @"light", @"system" ]) {
        CCChip *chip = [CCChip chipWithTitle:@""];
        chip.locKey = [@"settings.theme." stringByAppendingString:mode];
        chip.onClick = ^{
            M().settings.theme = mode;
            [weak save];
            [CCTheme applyMode:mode];
            [weak refresh];
        };
        [themeChips addObject:chip];
    }
    _themeChips = themeChips;
    _animations = [CCToggle new];
    _animations.onChange = ^(BOOL on) {
        M().settings.animations = on;
        CCSetMotionEnabled(on);
        [weak save];
    };
    _translucency = [CCToggle new];
    _translucency.onChange = ^(BOOL on) {
        M().settings.translucency = on;
        [weak save];
        if (weak.applyAppearance) weak.applyAppearance();
    };
    _scanOnStartup = [CCToggle new];
    _scanOnStartup.onChange = ^(BOOL on) {
        M().settings.scanOnStartup = on;
        [weak save];
    };
    NSArray *general = @[
        [CCSettingRow rowWithSymbol:@"globe" titleKey:@"settings.language" descKey:@"settings.language.desc" control:_language],
        [CCSettingRow rowWithSymbol:@"paintpalette" titleKey:@"settings.theme" descKey:@"settings.theme.desc" control:CCHStack(themeChips, 8)],
        [CCSettingRow rowWithSymbol:@"bolt" titleKey:@"settings.animations" descKey:@"settings.animations.desc" control:_animations],
        [CCSettingRow rowWithSymbol:@"square.on.square" titleKey:@"settings.backdrop" descKey:@"settings.backdrop.desc" control:_translucency],
        [CCSettingRow rowWithSymbol:@"play" titleKey:@"settings.scanOnStartup" descKey:@"settings.scanOnStartup.desc" control:_scanOnStartup],
    ];
    CCCard *generalCard = [self sectionCard:@"settings.general" rows:general padding:NSEdgeInsetsMake(18, 24, 10, 24)];

    // ── cleaning ──
    _useTrash = [CCToggle new];
    _useTrash.onChange = ^(BOOL on) {
        M().settings.useTrash = on;
        [weak save];
        [weak refresh];
        [NSNotificationCenter.defaultCenter postNotificationName:CCModelDidChangeNotification object:M()];
    };
    _deleteRow = [CCSettingRow rowWithSymbol:@"trash" titleKey:nil descKey:nil control:_useTrash];
    NSMutableArray *skipChips = [NSMutableArray array];
    for (NSNumber *hours in @[ @0, @6, @24, @72, @168 ]) {
        CCChip *chip = [CCChip chipWithTitle:@""];
        chip.onClick = ^{
            M().settings.skipRecentHours = hours.integerValue;
            [weak save];
            [weak refresh];
        };
        [skipChips addObject:chip];
    }
    _skipChips = skipChips;
    CCSettingRow *skipRow = [CCSettingRow rowWithSymbol:@"clock" titleKey:@"settings.skipRecent" descKey:@"settings.skipRecent.desc"
                                                control:CCHStack(skipChips, 8)];
    _confirmClean = [CCToggle new];
    _confirmClean.onChange = ^(BOOL on) {
        M().settings.confirmClean = on;
        [weak save];
    };
    _diskWithScan = [CCToggle new];
    _diskWithScan.onChange = ^(BOOL on) {
        M().settings.measureDiskWithScan = on;
        [weak save];
    };
    CCSettingRow *confirmRow = [CCSettingRow rowWithSymbol:@"checkmark.circle" titleKey:@"settings.confirmClean" descKey:@"settings.confirmClean.desc"
                                                   control:_confirmClean];
    CCSettingRow *diskRow = [CCSettingRow rowWithSymbol:@"chart.pie" titleKey:@"settings.diskWithScan" descKey:@"settings.diskWithScan.desc"
                                                control:_diskWithScan];
    CCCard *cleaningCard = [self sectionCard:@"settings.cleaning" rows:@[ _deleteRow, skipRow, confirmRow, diskRow ] padding:NSEdgeInsetsMake(18, 24, 10, 24)];

    // ── custom folders ──
    CCLabel *foldersTitle = H2(@"settings.customFolders");
    CCLabel *foldersDesc = [CCLabel key:@"settings.customFolders.desc" size:12.5 weight:NSFontWeightRegular role:CCRoleMuted];
    foldersDesc.wraps = YES;
    NSStackView *foldersText = CCVStack(@[ foldersTitle, foldersDesc ], 4);
    Stretch(foldersText, foldersDesc);
    CCButton *add = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"plus"];
    add.locKey = @"settings.customFolders.add";
    add.onClick = ^{ [weak addFolder]; };
    NSStackView *foldersHeader = CCHStack(@[ foldersText, add ], 16);
    foldersHeader.alignment = NSLayoutAttributeTop;
    [foldersText setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _folders = CCVStack(@[], 8);
    _noFolders = [CCLabel key:@"settings.customFolders.empty" size:11.5 weight:NSFontWeightRegular role:CCRoleFaint];
    NSStackView *foldersBody = CCVStack(@[ foldersHeader, _folders, _noFolders ], 14);
    Stretch(foldersBody, foldersHeader);
    Stretch(foldersBody, _folders);
    CCCard *foldersCard = Card(foldersBody, NSEdgeInsetsMake(18, 24, 20, 24));

    // ── reset ──
    CCButton *reset = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:nil];
    reset.locKey = @"settings.reset.button";
    reset.onClick = ^{ [weak reset]; };
    CCSettingRow *resetRow = [CCSettingRow rowWithSymbol:@"arrow.counterclockwise" titleKey:@"settings.reset" descKey:@"settings.reset.desc" control:reset];
    resetRow.showsDivider = NO;
    CCCard *resetCard = Card(resetRow, NSEdgeInsetsMake(10, 24, 10, 24));

    _title = H1(@"settings.title");
    _cards = [@[ generalCard, cleaningCard, foldersCard, resetCard ] mutableCopy];
    NSStackView *page = CCVStack(@[ _title, generalCard, cleaningCard, foldersCard, resetCard ], 16);
    [page setCustomSpacing:20 afterView:_title];
    for (NSView *card in _cards) Stretch(page, card);
    NSView *doc = scroll.document;
    [doc addSubview:page];
    // See the dashboard: bounded by the window, filling it below the window's own size priority.
    [page.trailingAnchor constraintLessThanOrEqualToAnchor:doc.trailingAnchor constant:-32].active = YES;
    NSLayoutConstraint *fill = [page.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-32];
    fill.priority = NSLayoutPriorityWindowSizeStayPut - 1;
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:doc.topAnchor constant:6],
        [page.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:32],
        [page.widthAnchor constraintLessThanOrEqualToConstant:960],
        [doc.bottomAnchor constraintEqualToAnchor:page.bottomAnchor constant:28],
        fill,
    ]];
    [self rebuildFolders];
    (void)s;
}

- (CCCard *)sectionCard:(NSString *)titleKey rows:(NSArray<NSView *> *)rows padding:(NSEdgeInsets)padding {
    CCLabel *title = H2(titleKey);
    NSStackView *stack = CCVStack([@[ title ] arrayByAddingObjectsFromArray:rows], 0);
    [stack setCustomSpacing:4 afterView:title];
    for (NSView *row in rows) Stretch(stack, row);
    return Card(stack, padding);
}

- (void)rebuildFolders {
    for (NSView *v in [_folders.arrangedSubviews copy]) [v removeFromSuperview];
    for (NSString *folder in M().settings.customFolders) {
        CCBox *row = [[CCBox alloc] initWithFrame:NSZeroRect];
        row.radius = 12;
        row.fill = ^NSColor *{ return CCTheme.inset; };
        CCIcon *icon = [CCIcon symbol:@"folder" size:15 weight:NSFontWeightRegular role:CCRoleCustom];
        icon.colorBlock = CategoryColor(CCCategoryCustom);
        CCLabel *path = [CCLabel text:folder size:13 weight:NSFontWeightRegular role:CCRoleText];
        path.lineBreakMode = NSLineBreakByTruncatingMiddle;
        path.toolTip = folder;
        [path setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        CCButton *remove = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"trash"];
        remove.toolTip = L(@"settings.customFolders.remove");
        remove.onClick = ^{ [M() removeCustomFolder:folder]; };
        NSStackView *line = CCHStack(@[ icon, path, CCSpacer(), remove ], 12);
        [row addSubview:line];
        CCPin(line, row, NSEdgeInsetsMake(10, 14, 10, 14));
        [_folders addArrangedSubview:row];
        Stretch(_folders, row);
    }
    _noFolders.hidden = M().settings.customFolders.count > 0;
}

- (void)addFolder {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    __weak CCSettingsPage *weak = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        [M() addCustomFolder:panel.URL.path refused:^{
            if (weak.alert) weak.alert(L(@"settings.customFolders"), L(@"settings.customFolders.refused"));
        }];
    }];
}

- (void)reset {
    [M() resetSettings];
    CCSettings *s = M().settings;
    [CCTheme applyMode:s.theme];
    CCSetMotionEnabled(s.animations);
    [CCLocalization.shared setLanguage:s.language];
    if (self.applyAppearance) self.applyAppearance();
    [self rebuildFolders];
    [self refresh];
}

- (void)refresh {
    CCSettings *s = M().settings;
    NSMutableArray *items = [NSMutableArray array];
    NSString *systemCode = [CCLocalization systemLanguageCode];
    NSString *systemName = systemCode;
    for (CCLanguage *l in CCLocalization.languages)
        if ([l.code isEqualToString:systemCode]) systemName = l.nativeName;
    [items addObject:LF(@"settings.language.auto", systemName)];
    NSInteger selected = 0;
    for (NSUInteger i = 0; i < CCLocalization.languages.count; i++) {
        CCLanguage *l = CCLocalization.languages[i];
        [items addObject:l.nativeName];
        if ([s.language isEqualToString:l.code]) selected = (NSInteger)i + 1;
    }
    _language.items = items;
    _language.selectedIndex = selected;

    NSArray *modes = @[ @"dark", @"light", @"system" ];
    for (NSUInteger i = 0; i < 3; i++) _themeChips[i].checked = [s.theme isEqualToString:modes[i]];
    if (_animations.on != s.animations) [_animations setOn:s.animations animated:self.window != nil];
    if (_translucency.on != s.translucency) [_translucency setOn:s.translucency animated:self.window != nil];
    if (_scanOnStartup.on != s.scanOnStartup) [_scanOnStartup setOn:s.scanOnStartup animated:self.window != nil];
    if (_useTrash.on != s.useTrash) [_useTrash setOn:s.useTrash animated:self.window != nil];
    if (_confirmClean.on != s.confirmClean) [_confirmClean setOn:s.confirmClean animated:self.window != nil];
    if (_diskWithScan.on != s.measureDiskWithScan) [_diskWithScan setOn:s.measureDiskWithScan animated:self.window != nil];
    _deleteRow.titleLabel.stringValue = L(s.useTrash ? @"settings.deleteMode.recycle" : @"settings.deleteMode.permanent");
    _deleteRow.descLabel.stringValue = L(s.useTrash ? @"settings.deleteMode.recycle.desc" : @"settings.deleteMode.permanent.desc");

    NSArray *hours = @[ @0, @6, @24, @72, @168 ];
    NSArray *titles = @[ L(@"settings.skipRecent.off"), LF(@"settings.hours", @6), LF(@"settings.hours", @24), LF(@"settings.days", @3), LF(@"settings.days", @7) ];
    for (NSUInteger i = 0; i < 5; i++) {
        _skipChips[i].title = titles[i];
        _skipChips[i].checked = s.skipRecentHours == [hours[i] integerValue];
    }
    if (_folders.arrangedSubviews.count != s.customFolders.count) [self rebuildFolders];
}

- (void)playEntrance {
    [super playEntrance];
    CCEntrance(_title, 0, 18);
    for (NSUInteger i = 0; i < _cards.count; i++) CCEntrance(_cards[i], 60 * (i + 1), 18);
}

@end

// ═════════════════════════════ about ═════════════════════════════

@implementation CCAboutPage {
    NSArray<NSView *> *_sections;
    CCLabel *_version, *_targetsText, *_languagesText, *_builtWith;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self build];
    return self;
}

- (void)build {
    CCScrollPage *scroll = [CCScrollPage new];
    [self addSubview:scroll];
    CCPin(scroll, self, NSEdgeInsetsMake(0, 0, 0, 0));

    NSView *logoHost = CCAuto([CCFlippedView new]);
    logoHost.wantsLayer = YES;
    logoHost.layerUsesCoreImageFilters = YES;
    CCSize(logoHost, 96, 96);
    CCBox *glow = [[CCBox alloc] initWithFrame:NSZeroRect];
    glow.radius = 28;
    glow.gradient = ^NSArray<NSColor *> *{ return CCTheme.accentGradient; };
    glow.alphaValue = 0.55;
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:@14 forKey:kCIInputRadiusKey];
    glow.contentFilters = @[ blur ];
    CCLogoView *logo = CCAuto([CCLogoView new]);
    [logoHost addSubview:glow];
    [logoHost addSubview:logo];
    CCPin(glow, logoHost, NSEdgeInsetsMake(10, 4, -2, 4));
    CCPin(logo, logoHost, NSEdgeInsetsMake(0, 0, 0, 0));

    CCLabel *name = [CCLabel key:@"app.name" size:32 weight:NSFontWeightBold role:CCRoleText];
    CCLabel *tagline = [CCLabel key:@"app.tagline" size:14 weight:NSFontWeightRegular role:CCRoleMuted];
    _version = [CCLabel text:@"" size:12 weight:NSFontWeightSemibold role:CCRoleAccent];
    CCBox *versionPill = [[CCBox alloc] initWithFrame:NSZeroRect];
    versionPill.radius = 999;
    versionPill.fill = ^NSColor *{ return CCTheme.accentSoft; };
    [versionPill addSubview:_version];
    CCPin(_version, versionPill, NSEdgeInsetsMake(4, 12, 4, 12));
    CCLabel *description = [CCLabel key:@"about.description" size:13 weight:NSFontWeightRegular role:CCRoleMuted];
    description.wraps = YES;
    description.alignment = NSTextAlignmentCenter;
    description.lineHeight = 22;
    [description.widthAnchor constraintLessThanOrEqualToConstant:580].active = YES;
    NSLayoutConstraint *descriptionWidth = [description.widthAnchor constraintEqualToConstant:580];
    descriptionWidth.priority = NSLayoutPriorityDefaultHigh - 1;
    descriptionWidth.active = YES;

    CCButton *github = [CCButton buttonWithStyle:CCButtonPrimary title:nil symbol:@"chevron.left.forwardslash.chevron.right"];
    github.locKey = @"about.github";
    github.symbolSize = 14;
    github.onClick = ^{ [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/Kreal-exe/JunkCleanup"]]; };
    CCButton *issues = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:nil];
    issues.locKey = @"about.issues";
    issues.padding = NSEdgeInsetsMake(12, 18, 12, 18);
    issues.onClick = ^{ [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/Kreal-exe/JunkCleanup/issues"]]; };
    CCButton *folder = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:nil];
    folder.locKey = @"about.openSettingsFolder";
    folder.padding = NSEdgeInsetsMake(12, 18, 12, 18);
    folder.onClick = ^{
        NSString *dir = [CCSettings filePath].stringByDeletingLastPathComponent;
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:dir]];
    };
    NSStackView *buttons = CCHStack(@[ github, issues, folder ], 12);

    NSStackView *hero = CCVStack(@[ logoHost, name, tagline, versionPill, description, buttons ], 0);
    hero.alignment = NSLayoutAttributeCenterX;
    [hero setCustomSpacing:22 afterView:logoHost];
    [hero setCustomSpacing:4 afterView:name];
    [hero setCustomSpacing:14 afterView:tagline];
    [hero setCustomSpacing:22 afterView:versionPill];
    [hero setCustomSpacing:28 afterView:description];
    CCCard *heroCard = Card(hero, NSEdgeInsetsMake(44, 40, 44, 40));

    _targetsText = [CCLabel text:@"" size:14 weight:NSFontWeightSemibold role:CCRoleText];
    _languagesText = [CCLabel text:@"" size:14 weight:NSFontWeightSemibold role:CCRoleText];
    _builtWith = [CCLabel text:@"" size:14 weight:NSFontWeightSemibold role:CCRoleText];
    NSArray *stats = @[ @[ @"list.bullet", @(CCCategorySystem), _targetsText ], @[ @"globe", @(CCCategoryCustom), _languagesText ],
                        @[ @"hammer", @(CCCategoryDeveloper), _builtWith ] ];
    NSMutableArray *statCards = [NSMutableArray array];
    for (NSArray *s in stats) {
        CCIcon *icon = [CCIcon symbol:s[0] size:20 weight:NSFontWeightRegular role:CCRoleCustom];
        icon.colorBlock = CategoryColor([s[1] integerValue]);
        CCLabel *text = s[2];
        text.wraps = YES;
        NSStackView *v = CCVStack(@[ icon, text ], 12);
        Stretch(v, text);
        [statCards addObject:Card(v, NSEdgeInsetsMake(18, 20, 18, 20))];
    }
    NSStackView *statRow = CCHStack(statCards, 12);
    statRow.distribution = NSStackViewDistributionFillEqually;
    statRow.alignment = NSLayoutAttributeTop;

    CCIconTile *shield = [CCIconTile tileWithSymbol:@"checkmark.shield" size:44 radius:14 iconSize:20];
    shield.fill = ^NSColor *{ return CCTheme.successSoft; };
    shield.icon.role = CCRoleSuccess;
    CCLabel *safetyDesc = [CCLabel key:@"about.safety.desc" size:13 weight:NSFontWeightRegular role:CCRoleMuted];
    safetyDesc.wraps = YES;
    safetyDesc.lineHeight = 21;
    NSStackView *safetyText = CCVStack(@[ H2(@"about.safety"), safetyDesc ], 6);
    Stretch(safetyText, safetyDesc);
    NSStackView *safety = CCHStack(@[ shield, safetyText ], 16);
    safety.alignment = NSLayoutAttributeTop;
    CCCard *safetyCard = Card(safety, NSEdgeInsetsMake(20, 24, 20, 24));

    CCLabel *license = [CCLabel key:@"about.license" size:11.5 weight:NSFontWeightRegular role:CCRoleFaint];

    NSStackView *page = CCVStack(@[ heroCard, statRow, safetyCard, license ], 10);
    page.alignment = NSLayoutAttributeCenterX;
    [page setCustomSpacing:18 afterView:safetyCard];
    for (NSView *v in @[ heroCard, statRow, safetyCard ]) Stretch(page, v);
    _sections = @[ heroCard, statRow, safetyCard, license ];
    NSView *doc = scroll.document;
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
        [page.widthAnchor constraintLessThanOrEqualToConstant:820],
        fill,
    ]];
}

- (void)refresh {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    _version.stringValue = LF(@"about.version", version);
    _targetsText.stringValue = LF(@"about.targets", @(CCCatalog.allTargets.count));
    _languagesText.stringValue = LF(@"about.languages", @(CCLocalization.languages.count));
    _builtWith.stringValue = LF(@"about.builtWith", @"");
}

- (void)playEntrance {
    [super playEntrance];
    NSArray *delays = @[ @0, @110, @190, @260 ];
    for (NSUInteger i = 0; i < _sections.count; i++) CCEntrance(_sections[i], [delays[i] doubleValue], 18);
}

@end

// ═════════════════════════════ overlays ═════════════════════════════

@implementation CCCleanOverlay {
    CCBox *_card;
    CALayer *_confetti;
    CCIconTile *_doneTile;
    NSView *_busyTile;
    CCLabel *_title, *_doneTitle, *_current, *_summary;
    CCCounter *_number, *_unit;
    CCSmoothBar *_bar;
    NSStackView *_log;
    NSScrollView *_logScroll;
    NSLayoutConstraint *_logHeight;
    CCButton *_close, *_stop;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.hidden = YES;
        [self build];
    }
    return self;
}

- (void)build {
    _confetti = [CALayer layer];
    [self.layer addSublayer:_confetti];

    _card = [[CCBox alloc] initWithFrame:NSZeroRect];
    _card.radius = 24;
    _card.fill = ^NSColor *{ return CCTheme.cardSolid; };
    _card.stroke = ^NSColor *{ return CCTheme.cardBorder; };
    _card.layer.shadowColor = NSColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.5;
    _card.layer.shadowRadius = 28;

    _busyTile = [CCIconTile tileWithSymbol:@"circle" size:44 radius:14 iconSize:1];
    ((CCIconTile *)_busyTile).icon.hidden = YES;
    ((CCIconTile *)_busyTile).fill = ^NSColor *{ return CCTheme.accentSoft; };
    CCSpinner *spinner = [[CCSpinner alloc] initWithDiameter:22 lineWidth:3 sweep:270 period:0.9];
    [_busyTile addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:_busyTile.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:_busyTile.centerYAnchor],
    ]];
    _doneTile = [CCIconTile tileWithSymbol:@"checkmark" size:44 radius:14 iconSize:18];
    _doneTile.icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightBold];
    _doneTile.fill = ^NSColor *{ return CCTheme.successSoft; };
    _doneTile.icon.role = CCRoleSuccess;

    _title = [CCLabel key:@"clean.title" size:22 weight:NSFontWeightSemibold role:CCRoleText];
    _doneTitle = [CCLabel key:@"clean.done" size:22 weight:NSFontWeightSemibold role:CCRoleText];
    _current = Caption(@"");
    NSStackView *titles = CCVStack(@[ _title, _doneTitle, _current ], 2);
    NSStackView *header = CCHStack(@[ _busyTile, _doneTile, titles ], 16);

    _number = [CCCounter text:@"" size:52 weight:NSFontWeightBold role:CCRoleText];
    _number.part = CCCounterNumber;
    _number.duration = 500;
    _unit = [CCCounter text:@"" size:18 weight:NSFontWeightSemibold role:CCRoleMuted];
    _unit.part = CCCounterUnit;
    _unit.duration = 500;
    CCLabel *freed = [CCLabel key:@"clean.freed" size:13 weight:NSFontWeightRegular role:CCRoleMuted];
    NSStackView *amount = CCHStack(@[ _number, _unit, freed ], 8);
    amount.alignment = NSLayoutAttributeLastBaseline;
    [amount setCustomSpacing:10 afterView:_unit];

    _bar = [CCSmoothBar new];
    _bar.duration = 450;
    _bar.fillGradient = ^NSArray<NSColor *> *{ return CCTheme.accentGradient; };
    CCSize(_bar, 0, 8);
    _summary = Muted(@"", 13);
    _summary.wraps = YES;

    _log = CCVStack(@[], 8);
    _logScroll = [NSScrollView new];
    _logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _logScroll.drawsBackground = NO;
    _logScroll.hasVerticalScroller = YES;
    _logScroll.autohidesScrollers = YES;
    _logScroll.scrollerStyle = NSScrollerStyleOverlay;
    _logScroll.contentView.drawsBackground = NO;
    CCFlippedView *logDoc = CCAuto([CCFlippedView new]);
    _logScroll.documentView = logDoc;
    [logDoc addSubview:_log];
    CCPin(_log, logDoc, NSEdgeInsetsMake(4, 0, 4, 0));
    [NSLayoutConstraint activateConstraints:@[
        [logDoc.leadingAnchor constraintEqualToAnchor:_logScroll.contentView.leadingAnchor],
        [logDoc.topAnchor constraintEqualToAnchor:_logScroll.contentView.topAnchor],
        [logDoc.widthAnchor constraintEqualToAnchor:_logScroll.contentView.widthAnchor],
    ]];
    // Below required, so on a short window the log gives way before the card outgrows it.
    _logHeight = [_logScroll.heightAnchor constraintEqualToConstant:0];
    _logHeight.priority = NSLayoutPriorityDefaultHigh - 1;
    _logHeight.active = YES;

    _close = [CCButton buttonWithStyle:CCButtonPrimary title:nil symbol:nil];
    _close.locKey = @"clean.close";
    [_close.widthAnchor constraintGreaterThanOrEqualToConstant:130].active = YES;
    _close.onClick = ^{ [M() closeCleanOverlay]; };
    _stop = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"stop"];
    _stop.locKey = @"clean.stop";
    _stop.padding = NSEdgeInsetsMake(11, 18, 11, 18);
    [_stop.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
    _stop.onClick = ^{ [M() cancelClean]; };
    NSStackView *buttons = CCHStack(@[ CCSpacer(), _stop, _close ], 12);

    NSStackView *stack = CCVStack(@[ header, amount, _bar, _summary, _logScroll, buttons ], 0);
    [stack setCustomSpacing:22 afterView:header];
    [stack setCustomSpacing:18 afterView:amount];
    [stack setCustomSpacing:14 afterView:_bar];
    [stack setCustomSpacing:16 afterView:_summary];
    [stack setCustomSpacing:24 afterView:_logScroll];
    for (NSView *v in @[ _bar, _summary, _logScroll ]) Stretch(stack, v);
    [buttons.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    [_card addSubview:stack];
    CCPin(stack, _card, NSEdgeInsetsMake(32, 36, 32, 36));
    [self addSubview:_card];
    [NSLayoutConstraint activateConstraints:@[
        [_card.widthAnchor constraintEqualToConstant:560],
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor constant:-32],
    ]];
    [self applyTheme];
}

- (void)applyTheme { self.layer.backgroundColor = CCTheme.overlay.CGColor; }

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden) return nil;
    NSView *hit = [super hitTest:point];
    return hit ?: self;
}

- (void)mouseDown:(NSEvent *)event {}

- (void)layout {
    [super layout];
    CCWithoutAnimation(^{ self->_confetti.frame = self.layer.bounds; });
}

- (void)refresh {
    CCModel *m = M();
    BOOL done = m.cleanDone;
    _busyTile.hidden = done;
    _doneTile.hidden = !done;
    _title.hidden = done;
    _doneTitle.hidden = !done;
    _current.stringValue = m.cleanCurrent;
    _current.hidden = done;
    _number.bytes = m.cleanFreed;
    _unit.bytes = m.cleanFreed;
    _bar.value = m.cleanProgress;
    _summary.stringValue = m.cleanSummary;
    _summary.hidden = !done;
    _close.hidden = !done;
    _stop.hidden = done;
    _stop.enabled = !m.cleanStopping;

    if (_log.arrangedSubviews.count != m.cleanLog.count) {
        for (NSView *v in [_log.arrangedSubviews copy]) [v removeFromSuperview];
        for (CCCleanLogItem *item in m.cleanLog) {
            CCIcon *check = [CCIcon symbol:@"checkmark" size:12 weight:NSFontWeightSemibold role:CCRoleSuccess];
            CCLabel *name = [CCLabel text:item.name size:13 weight:NSFontWeightRegular role:CCRoleText];
            CCLabel *skipped = [CCLabel text:[NSString stringWithFormat:@"%@ %@", CCFormatCount(item.failed), L(@"clean.skipped")]
                                        size:11.5 weight:NSFontWeightRegular role:CCRoleWarning];
            skipped.hidden = item.failed == 0;
            CCLabel *bytes = [CCLabel text:CCFormatBytes(item.bytes) size:13 weight:NSFontWeightSemibold role:CCRoleText];
            bytes.alignment = NSTextAlignmentRight;
            [bytes.widthAnchor constraintGreaterThanOrEqualToConstant:70].active = YES;
            NSStackView *row = CCHStack(@[ check, name, CCSpacer(), skipped, bytes ], 12);
            [_log addArrangedSubview:row];
            Stretch(_log, row);
        }
        // Fade only: rising from below would cross the row underneath.
        if (m.cleanLog.count) CCEntrance(_log.arrangedSubviews.firstObject, 0, 0);
    }
    _logHeight.constant = MIN(220, m.cleanLog.count ? m.cleanLog.count * 25.0 + 8 : 0);
    _logScroll.hidden = m.cleanLog.count == 0;
}

- (void)show {
    self.hidden = NO;
    for (CALayer *l in [_confetti.sublayers copy]) [l removeFromSuperlayer];
    [self refresh];
    if (!CCMotionEnabled()) return;
    CCWithoutAnimation(^{ self.layer.opacity = 0; });
    CCAnimateNumber(self.layer, @"opacity", 1, 220, CCEaseOut, 0);
    CCTransformView(_card, CCXformMake(0.92, 24, 0), 0, nil);
    CCTransformView(_card, CCXformIdentity(), 480, CCEaseSpring);
}

- (void)hide {
    if (!CCMotionEnabled()) {
        self.hidden = YES;
        return;
    }
    CCAnimateNumber(self.layer, @"opacity", 0, 180, CCEaseIn, 0);
    CCTransformView(_card, CCXformMake(0.96, 0, 0), 180, CCEaseIn);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.19 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (M().overlayVisible) return;
        self.hidden = YES;
        CCWithoutAnimation(^{ self.layer.opacity = 1; });
        CCTransformView(self->_card, CCXformIdentity(), 0, nil);
        for (CALayer *l in [self->_confetti.sublayers copy]) [l removeFromSuperlayer];
    });
}

/// A confetti burst from above the card (CleanOverlay.xaml.cs).
- (void)celebrate {
    if (!CCMotionEnabled() || self.hidden) return;
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    if (w <= 0 || h <= 0) return;
    BOOL down = CCLayerYDown(self.layer);
    CGFloat (^Y)(CGFloat) = ^CGFloat(CGFloat y) { return down ? y : h - y; };
    NSArray *palette = @[ CCHex(0x7C6CFF, 1), CCHex(0x22D3EE, 1), CCHex(0xF472B6, 1), CCHex(0x34D399, 1), CCHex(0xFBBF24, 1), CCHex(0x60A5FA, 1) ];
    CGFloat originX = w / 2, originY = h / 2 - 160;
    double now = CACurrentMediaTime();

    for (int i = 0; i < 90; i++) {
        NSColor *color = palette[arc4random_uniform((uint32_t)palette.count)];
        CGFloat size = 6 + drand48() * 6;
        CALayer *piece = [CALayer layer];
        BOOL round = arc4random_uniform(3) == 0;
        piece.bounds = CGRectMake(0, 0, size, round ? size : size * 1.6);
        piece.cornerRadius = round ? size / 2 : 2;
        piece.backgroundColor = color.CGColor;
        piece.position = CGPointMake(originX, Y(h + 60));
        [_confetti addSublayer:piece];

        double spread = (drand48() - 0.5) * 2;
        double dx = spread * (260 + drand48() * 260);
        double peak = originY - (120 + drand48() * 260);
        double seconds = (1500 + arc4random_uniform(900)) / 1000.0;
        double startAngle = drand48() * 2 * M_PI;
        double spin = (drand48() - 0.5) * 6 * M_PI;

        NSUInteger n = (NSUInteger)(seconds * 60);
        NSMutableArray *positions = [NSMutableArray array], *angles = [NSMutableArray array], *alphas = [NSMutableArray array];
        for (NSUInteger k = 0; k <= n; k++) {
            double t = (double)k / n;
            double x = originX + dx * CCEaseCubicOut(t);
            double y = t < 0.32 ? originY + (peak - originY) * CCEaseCubicOut(t / 0.32)
                                : peak + (h + 40 - peak) * pow((t - 0.32) / 0.68, 2);
            [positions addObject:[NSValue valueWithPoint:NSMakePoint(x, Y(y))]];
            [angles addObject:@(startAngle + spin * t)];
            [alphas addObject:@(t < 0.65 ? 1 : 1 - (t - 0.65) / 0.35)];
        }
        CAKeyframeAnimation *move = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        move.values = positions;
        CAKeyframeAnimation *rotate = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
        rotate.values = angles;
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = alphas;
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[ move, rotate, fade ];
        group.duration = seconds;
        group.beginTime = now;
        group.fillMode = kCAFillModeBoth;
        group.removedOnCompletion = NO;
        [piece addAnimation:group forKey:@"fly"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((seconds + 0.1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [piece removeFromSuperlayer];
        });
    }
}

@end

@implementation CCConfirmDialog {
    CCBox *_card;
    CCIconTile *_tile;
    CCLabel *_title, *_body;
    CCButton *_cancel, *_okPrimary, *_okDanger;
    void (^_answer)(BOOL);
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.hidden = YES;
        _card = [[CCBox alloc] initWithFrame:NSZeroRect];
        _card.radius = 22;
        _card.fill = ^NSColor *{ return CCTheme.cardSolid; };
        _card.stroke = ^NSColor *{ return CCTheme.cardBorder; };
        _card.layer.shadowColor = NSColor.blackColor.CGColor;
        _card.layer.shadowOpacity = 0.5;
        _card.layer.shadowRadius = 28;
        _tile = [CCIconTile tileWithSymbol:@"trash" size:48 radius:15 iconSize:20];
        _title = [CCLabel text:@"" size:22 weight:NSFontWeightSemibold role:CCRoleText];
        _title.wraps = YES;
        _body = Muted(@"", 13);
        _body.wraps = YES;
        _body.lineHeight = 21;
        _cancel = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:nil];
        _cancel.locKey = @"common.cancel";
        _cancel.padding = NSEdgeInsetsMake(11, 18, 11, 18);
        [_cancel.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
        _okPrimary = [CCButton buttonWithStyle:CCButtonPrimary title:@"" symbol:nil];
        _okDanger = [CCButton buttonWithStyle:CCButtonDanger title:@"" symbol:nil];
        for (CCButton *b in @[ _okPrimary, _okDanger ]) [b.widthAnchor constraintGreaterThanOrEqualToConstant:130].active = YES;
        __weak CCConfirmDialog *weak = self;
        _cancel.onClick = ^{ [weak closeWith:NO]; };
        _okPrimary.onClick = ^{ [weak closeWith:YES]; };
        _okDanger.onClick = ^{ [weak closeWith:YES]; };
        NSStackView *buttons = CCHStack(@[ CCSpacer(), _cancel, _okPrimary, _okDanger ], 12);
        NSStackView *stack = CCVStack(@[ _tile, _title, _body, buttons ], 0);
        [stack setCustomSpacing:18 afterView:_tile];
        [stack setCustomSpacing:10 afterView:_title];
        [stack setCustomSpacing:28 afterView:_body];
        Stretch(stack, _title);
        Stretch(stack, _body);
        [buttons.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
        [_card addSubview:stack];
        CCPin(stack, _card, NSEdgeInsetsMake(30, 32, 30, 32));
        [self addSubview:_card];
        [NSLayoutConstraint activateConstraints:@[
            [_card.widthAnchor constraintEqualToConstant:500],
            [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        [self applyTheme];
    }
    return self;
}

- (BOOL)isOpen { return _answer != nil; }

- (void)applyTheme { self.layer.backgroundColor = CCTheme.overlay.CGColor; }

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden) return nil;
    return [super hitTest:point] ?: self;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [_card convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(p, _card.bounds)) [self closeWith:NO];
}

- (void)showTitle:(NSString *)title body:(NSString *)body ok:(NSString *)okText danger:(BOOL)danger answer:(void (^)(BOOL))answer {
    if (_answer) _answer(NO);
    _answer = [answer copy];
    _title.stringValue = title;
    _body.stringValue = body;
    _okPrimary.title = okText;
    _okDanger.title = okText;
    _okPrimary.hidden = danger;
    _okDanger.hidden = !danger;
    _cancel.hidden = [okText isEqualToString:L(@"common.ok")];
    _tile.fill = ^NSColor *{ return danger ? CCTheme.dangerSoft : CCTheme.accentSoft; };
    _tile.icon.role = danger ? CCRoleDanger : CCRoleAccent;
    _tile.icon.symbol = [okText isEqualToString:L(@"common.ok")] ? @"info.circle" : @"trash";
    self.hidden = NO;
    [self.window makeFirstResponder:self];
    if (!CCMotionEnabled()) return;
    CCWithoutAnimation(^{ self.layer.opacity = 0; });
    CCAnimateNumber(self.layer, @"opacity", 1, 200, CCEaseOut, 0);
    CCTransformView(_card, CCXformMake(0.94, 18, 0), 0, nil);
    CCTransformView(_card, CCXformIdentity(), 420, CCEaseSpring);
}

- (void)closeWith:(BOOL)result {
    void (^answer)(BOOL) = _answer;
    _answer = nil;
    if (!CCMotionEnabled()) {
        self.hidden = YES;
    } else {
        CCAnimateNumber(self.layer, @"opacity", 0, 160, CCEaseIn, 0);
        CCTransformView(_card, CCXformMake(0.96, 0, 0), 160, CCEaseIn);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.17 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_answer) return;
            self.hidden = YES;
            CCWithoutAnimation(^{ self.layer.opacity = 1; });
        });
    }
    if (answer) answer(result);
}

- (BOOL)acceptsFirstResponder { return !self.hidden; }

- (void)keyDown:(NSEvent *)event {
    if (!_answer) return [super keyDown:event];
    if (event.keyCode == 53) [self closeWith:NO];                              // Esc
    else if (event.keyCode == 36 || event.keyCode == 76) [self closeWith:YES]; // Return, Enter
    else [super keyDown:event];
}

@end

// ═════════════════════════════ details ═════════════════════════════

/// The icon and colour for an entry, by what it most likely is.
static void EntryLook(CCEntry *e, NSString **symbol, NSColor **color) {
    NSString *name = e.name.lowercaseString;
    NSString *ext = name.pathExtension;
    NSDictionary<NSString *, NSArray *> *kinds = @{
        @"brain": @[ @[ @"safetensors", @"gguf", @"ggml", @"bin", @"pt", @"pth", @"onnx", @"ckpt", @"h5", @"tflite", @"mlmodel", @"mlpackage", @"npz" ], CCHex(0xA78BFA, 1) ],
        @"shippingbox": @[ @[ @"zip", @"tar", @"gz", @"tgz", @"xz", @"zst", @"7z", @"rar", @"dmg", @"pkg", @"whl", @"jar", @"nupkg", @"crate", @"bottle" ], CCHex(0xF59E0B, 1) ],
        @"photo": @[ @[ @"png", @"jpg", @"jpeg", @"gif", @"webp", @"heic", @"svg", @"tiff", @"bmp", @"ico" ], CCHex(0x34D399, 1) ],
        @"film": @[ @[ @"mp4", @"mov", @"mkv", @"webm", @"avi", @"m4v" ], CCHex(0xF472B6, 1) ],
        @"music.note": @[ @[ @"mp3", @"wav", @"m4a", @"flac", @"ogg", @"aac" ], CCHex(0x22D3EE, 1) ],
        @"curlybraces": @[ @[ @"js", @"ts", @"py", @"pyc", @"json", @"map", @"wasm", @"so", @"dylib", @"node", @"class", @"o", @"a" ], CCHex(0x60A5FA, 1) ],
        @"cylinder": @[ @[ @"db", @"sqlite", @"sqlite3", @"ldb", @"leveldb", @"idx", @"pack" ], CCHex(0xFBBF24, 1) ],
        @"doc.text": @[ @[ @"log", @"txt", @"md", @"csv", @"xml", @"plist" ], CCHex(0x8E96AB, 1) ],
    };
    if (e.isDirectory) {
        BOOL model = [name hasPrefix:@"models--"] || [name hasPrefix:@"datasets--"] || [name hasPrefix:@"spaces--"];
        *symbol = model ? @"brain" : @"folder.fill";
        *color = model ? CCHex(0xA78BFA, 1) : CCHex(0x7C6CFF, 1);
        return;
    }
    for (NSString *key in kinds) {
        if ([kinds[key][0] containsObject:ext]) {
            *symbol = key;
            *color = kinds[key][1];
            return;
        }
    }
    *symbol = @"doc";
    *color = CCHex(0x8E96AB, 1);
}

@interface CCDetailRow : CCBox
@property (nonatomic, strong) CCEntry *entry;
@property (nonatomic, copy) void (^onDelete)(CCDetailRow *row);
- (void)setBusy:(BOOL)busy;
@end

@implementation CCDetailRow {
    NSTrackingArea *_tracking;
    BOOL _confirming;
    CCButton *_trash, *_confirm;
    NSTimer *_revert;
}

+ (instancetype)rowFor:(CCEntry *)entry total:(long long)total category:(CCCategory)category {
    CCDetailRow *row = [[self alloc] initWithFrame:NSZeroRect];
    row.entry = entry;
    row.radius = 12;
    NSString *symbol;
    NSColor *color;
    EntryLook(entry, &symbol, &color);
    CCIconTile *tile = [CCIconTile tileWithSymbol:symbol size:36 radius:10 iconSize:15];
    tile.fill = ^NSColor *{ return [color colorWithAlphaComponent:0.16]; };
    tile.icon.colorBlock = ^NSColor *{ return color; };
    tile.bounces = NO;
    CCLabel *name = [CCLabel text:entry.name size:13.5 weight:NSFontWeightSemibold role:CCRoleText];
    name.lineBreakMode = NSLineBreakByTruncatingMiddle;
    name.toolTip = entry.path;
    [name setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    CCLabel *files = Caption(LF(@"dash.filesCount", CCFormatCount(entry.files)));
    CCSmoothBar *bar = [CCSmoothBar new];
    bar.fillColor = CategoryColor(category);
    CCSize(bar, 0, 4);
    [bar setValue:total > 0 ? (double)entry.bytes / total : 0 animated:NO];
    NSStackView *text = CCVStack(@[ name, files, bar ], 4);
    [text setCustomSpacing:7 afterView:files];
    Stretch(text, name);
    Stretch(text, bar);
    CCLabel *size = [CCLabel text:CCFormatBytes(entry.bytes) size:14 weight:NSFontWeightSemibold role:CCRoleText];
    size.font = CCDigitsFont(14, NSFontWeightSemibold);
    size.alignment = NSTextAlignmentRight;
    [size setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [size.widthAnchor constraintGreaterThanOrEqualToConstant:76].active = YES;

    CCButton *reveal = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"magnifyingglass"];
    reveal.toolTip = L(@"details.reveal");
    reveal.onClick = ^{ [M() revealPath:entry.path]; };
    row->_trash = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"trash"];
    row->_trash.toolTip = L(@"details.delete");
    row->_confirm = [CCButton buttonWithStyle:CCButtonDanger title:L(@"details.confirm") symbol:@"trash"];
    row->_confirm.padding = NSEdgeInsetsMake(6, 12, 6, 12);
    row->_confirm.fontSize = 12.5;
    row->_confirm.symbolSize = 12;
    row->_confirm.hidden = YES;
    __weak CCDetailRow *weak = row;
    row->_trash.onClick = ^{ [weak askToConfirm]; };
    row->_confirm.onClick = ^{
        CCDetailRow *r = weak;
        if (r && r.onDelete) r.onDelete(r);
    };

    NSStackView *line = CCHStack(@[ tile, text, size, reveal, row->_trash, row->_confirm ], 14);
    [line setCustomSpacing:16 afterView:size];
    [line setCustomSpacing:2 afterView:reveal];
    [text setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [text setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    // The name column takes all the room the size and buttons leave, so every share bar has the same length.
    NSLayoutConstraint *fill = [text.trailingAnchor constraintEqualToAnchor:size.leadingAnchor constant:-14];
    fill.active = YES;
    [row addSubview:line];
    CCPin(line, row, NSEdgeInsetsMake(10, 12, 10, 10));
    row.fill = ^NSColor *{ return CCTheme.inset; };
    return row;
}

- (void)askToConfirm {
    _confirming = YES;
    _trash.hidden = YES;
    _confirm.hidden = NO;
    CCEntrance(_confirm, 0, 0);
    [_revert invalidate];
    __weak CCDetailRow *weak = self;
    _revert = [NSTimer scheduledTimerWithTimeInterval:3.5 repeats:NO block:^(NSTimer *t) { [weak cancelConfirm]; }];
}

- (void)cancelConfirm {
    _confirming = NO;
    _confirm.hidden = YES;
    _confirm.enabled = YES;
    _trash.hidden = NO;
}

- (void)setBusy:(BOOL)busy {
    [_revert invalidate];
    _confirm.enabled = !busy;
    if (!busy) [self cancelConfirm];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)event { self.fill = ^NSColor *{ return CCTheme.hover; }; }
- (void)mouseExited:(NSEvent *)event { self.fill = ^NSColor *{ return CCTheme.inset; }; }

@end

@implementation CCDetailsSheet {
    CCBox *_card;
    CCIconTile *_tile;
    CCLabel *_title, *_subtitle, *_empty;
    CCPill *_risk;
    CCButton *_revealRoot;
    NSScrollView *_scroll;
    NSStackView *_list;
    NSLayoutConstraint *_listHeight;
    CCTargetItem *_target;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.hidden = YES;
        [self build];
    }
    return self;
}

- (BOOL)isOpen { return !self.hidden && _target != nil; }

- (void)build {
    _card = [[CCBox alloc] initWithFrame:NSZeroRect];
    _card.radius = 24;
    _card.fill = ^NSColor *{ return CCTheme.cardSolid; };
    _card.stroke = ^NSColor *{ return CCTheme.cardBorder; };
    _card.layer.shadowColor = NSColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.5;
    _card.layer.shadowRadius = 28;

    _tile = [CCIconTile tileWithSymbol:@"folder" size:48 radius:15 iconSize:20];
    _title = [CCLabel text:@"" size:22 weight:NSFontWeightSemibold role:CCRoleText];
    _subtitle = Muted(@"", 13);
    NSStackView *titles = CCVStack(@[ _title, _subtitle ], 3);
    _risk = [CCPill pillWithText:@"" symbol:nil color:^NSColor *{ return CCTheme.accent; } soft:^NSColor *{ return CCTheme.accentSoft; }];
    CCButton *close = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:@"xmark"];
    close.onClick = ^{ [M() closeDetails]; };
    NSStackView *header = CCHStack(@[ _tile, titles, CCSpacer(), _risk, close ], 14);
    [header setCustomSpacing:10 afterView:_risk];
    [titles setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    CCLabel *hint = [CCLabel key:@"details.hint" size:12.5 weight:NSFontWeightRegular role:CCRoleMuted];
    hint.wraps = YES;
    _revealRoot = [CCButton buttonWithStyle:CCButtonGhost title:nil symbol:@"folder"];
    _revealRoot.locKey = @"details.reveal";
    _revealRoot.padding = NSEdgeInsetsMake(7, 12, 7, 12);
    _revealRoot.fontSize = 12.5;
    __weak CCDetailsSheet *weak = self;
    _revealRoot.onClick = ^{
        CCDetailsSheet *s = weak;
        if (s->_target.roots.count) [M() revealPath:s->_target.roots.firstObject];
    };
    NSStackView *hintRow = CCHStack(@[ hint, _revealRoot ], 16);
    [hint setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    _list = CCVStack(@[], 8);
    _scroll = [NSScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.scrollerStyle = NSScrollerStyleOverlay;
    _scroll.contentView.drawsBackground = NO;
    CCFlippedView *doc = CCAuto([CCFlippedView new]);
    _scroll.documentView = doc;
    [doc addSubview:_list];
    CCPin(_list, doc, NSEdgeInsetsMake(0, 0, 0, 0));
    [NSLayoutConstraint activateConstraints:@[
        [doc.leadingAnchor constraintEqualToAnchor:_scroll.contentView.leadingAnchor],
        [doc.topAnchor constraintEqualToAnchor:_scroll.contentView.topAnchor],
        [doc.widthAnchor constraintEqualToAnchor:_scroll.contentView.widthAnchor],
    ]];
    _listHeight = [_scroll.heightAnchor constraintEqualToConstant:0];
    _listHeight.priority = NSLayoutPriorityDefaultHigh;
    _listHeight.active = YES;
    _empty = [CCLabel key:@"details.empty" size:13 weight:NSFontWeightRegular role:CCRoleMuted];

    NSStackView *stack = CCVStack(@[ header, hintRow, _scroll, _empty ], 0);
    [stack setCustomSpacing:18 afterView:header];
    [stack setCustomSpacing:16 afterView:hintRow];
    for (NSView *v in @[ header, hintRow, _scroll ]) Stretch(stack, v);
    [_card addSubview:stack];
    CCPin(stack, _card, NSEdgeInsetsMake(28, 30, 26, 30));
    [self addSubview:_card];
    [NSLayoutConstraint activateConstraints:@[
        [_card.widthAnchor constraintEqualToConstant:700],
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor constant:-96],
    ]];
    [self applyTheme];
}

- (void)applyTheme { self.layer.backgroundColor = CCTheme.overlay.CGColor; }

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden) return nil;
    return [super hitTest:point] ?: self;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [_card convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(p, _card.bounds)) [M() closeDetails];
}

- (void)fill {
    CCTargetItem *t = _target;
    CCCategory c = t.target.category;
    _tile.icon.symbol = t.target.symbol;
    _tile.fill = CategorySoft(c);
    _tile.icon.colorBlock = CategoryColor(c);
    _title.stringValue = t.name;
    _subtitle.stringValue = [NSString stringWithFormat:@"%@ · %@", CCFormatBytes(t.bytes), LF(@"dash.filesCount", CCFormatCount(t.fileCount))];
    CCRisk risk = t.target.risk;
    _risk.label.stringValue = t.riskText;
    _risk.fill = ^NSColor *{ return [CCTheme riskSoft:risk]; };
    _risk.label.colorBlock = ^NSColor *{ return [CCTheme riskColor:risk]; };
    _revealRoot.hidden = t.roots.count == 0;

    for (NSView *v in [_list.arrangedSubviews copy]) [v removeFromSuperview];
    __weak CCDetailsSheet *weak = self;
    for (CCEntry *e in t.topEntries) {
        CCDetailRow *row = [CCDetailRow rowFor:e total:t.bytes category:c];
        row.onDelete = ^(CCDetailRow *r) { [weak remove:r]; };
        [_list addArrangedSubview:row];
        Stretch(_list, row);
    }
    [self updateHeight];
    _empty.stringValue = t.lastResult ? L(@"details.empty") : L(@"dash.notScanned");
    _empty.hidden = t.topEntries.count > 0;
}

- (void)updateHeight {
    [_list layoutSubtreeIfNeeded];
    _listHeight.constant = MIN(_list.fittingSize.height, 460);
    _scroll.hidden = _list.arrangedSubviews.count == 0;
}

- (void)remove:(CCDetailRow *)row {
    [row setBusy:YES];
    __weak CCDetailsSheet *weak = self;
    [M() deleteEntry:row.entry ofTarget:_target completion:^(BOOL ok) {
        CCDetailsSheet *s = weak;
        if (!ok) {
            [row setBusy:NO];
            return;
        }
        CCAnimateNumber(row.layer, @"opacity", 0, 220, CCEaseIn, 0);
        CCTransformView(row, CCXformMake(0.97, 0, 0), 220, CCEaseIn);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.23 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [row removeFromSuperview];
            if (!s) return;
            s->_subtitle.stringValue = [NSString stringWithFormat:@"%@ · %@", CCFormatBytes(s->_target.bytes),
                                        LF(@"dash.filesCount", CCFormatCount(s->_target.fileCount))];
            [s updateHeight];
            s->_empty.hidden = s->_list.arrangedSubviews.count > 0;
        });
    }];
}

- (void)show {
    _target = M().detailsTarget;
    if (!_target) return;
    [self fill];
    self.hidden = NO;
    [self.window makeFirstResponder:self];
    if (!CCMotionEnabled()) return;
    CCWithoutAnimation(^{ self.layer.opacity = 0; });
    CCAnimateNumber(self.layer, @"opacity", 1, 200, CCEaseOut, 0);
    CCTransformView(_card, CCXformMake(0.94, 18, 0), 0, nil);
    CCTransformView(_card, CCXformIdentity(), 420, CCEaseSpring);
    Stagger(_list.arrangedSubviews.count > 12 ? [_list.arrangedSubviews subarrayWithRange:NSMakeRange(0, 12)] : _list.arrangedSubviews, 30, 80);
}

- (void)hide {
    _target = nil;
    if (!CCMotionEnabled()) {
        self.hidden = YES;
        return;
    }
    CCAnimateNumber(self.layer, @"opacity", 0, 160, CCEaseIn, 0);
    CCTransformView(_card, CCXformMake(0.96, 0, 0), 160, CCEaseIn);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.17 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_target) return;
        self.hidden = YES;
        CCWithoutAnimation(^{ self.layer.opacity = 1; });
    });
}

- (BOOL)acceptsFirstResponder { return !self.hidden; }

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) [M() closeDetails];
    else [super keyDown:event];
}

@end

@implementation CCToast {
    CCIconTile *_tile;
    CCLabel *_text;
    NSTimer *_timer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.radius = 14;
        self.fill = ^NSColor *{ return CCTheme.popup; };
        self.stroke = ^NSColor *{ return CCTheme.cardBorder; };
        self.layer.shadowColor = NSColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 14;
        self.hidden = YES;
        _tile = [CCIconTile tileWithSymbol:@"checkmark" size:30 radius:9 iconSize:13];
        _tile.fill = ^NSColor *{ return CCTheme.successSoft; };
        _tile.icon.role = CCRoleSuccess;
        _text = [CCLabel text:@"" size:13.5 weight:NSFontWeightSemibold role:CCRoleText];
        _text.wraps = YES;
        [_text.widthAnchor constraintLessThanOrEqualToConstant:420].active = YES;
        _text.preferredMaxLayoutWidth = 420;
        NSStackView *row = CCHStack(@[ _tile, _text ], 12);
        [self addSubview:row];
        CCPin(row, self, NSEdgeInsetsMake(12, 16, 12, 20));
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)showSymbol:(NSString *)symbol text:(NSString *)text {
    _tile.icon.symbol = symbol;
    _text.stringValue = text;
    self.hidden = NO;
    if (CCMotionEnabled()) {
        CCWithoutAnimation(^{ self.layer.opacity = 0; });
        CCAnimateNumber(self.layer, @"opacity", 1, 220, CCEaseOut, 0);
        CCTransformView(self, CCXformMake(1, -16, 0), 0, nil);
        CCTransformView(self, CCXformIdentity(), 480, CCEaseSpring);
    }
    [_timer invalidate];
    __weak CCToast *weak = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:3.2 repeats:NO block:^(NSTimer *t) { [weak dismiss]; }];
}

- (void)dismiss {
    if (!CCMotionEnabled()) {
        self.hidden = YES;
        return;
    }
    CCAnimateNumber(self.layer, @"opacity", 0, 240, CCEaseIn, 0);
    CCTransformView(self, CCXformMake(1, -10, 0), 240, CCEaseIn);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.layer.opacity < 0.01) self.hidden = YES;
    });
}

@end
