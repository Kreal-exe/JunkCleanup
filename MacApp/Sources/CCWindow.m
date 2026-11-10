#import "CCWindow.h"
#import "CCControls.h"
#import "CCPages.h"
#import "CCDiskPage.h"
#include <dlfcn.h>

static CCModel *M(void) { return CCModel.shared; }

// ───────────── ambient background ─────────────

/// The background colour plus three soft colour blobs that drift slowly (StartAmbientAnimation).
@interface CCBackgroundView : NSView <CCLive>
@property (nonatomic) BOOL translucent;
@end

@implementation CCBackgroundView {
    NSArray<CAGradientLayer *> *_blobs;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        NSMutableArray *blobs = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            CAGradientLayer *blob = [CAGradientLayer layer];
            blob.type = kCAGradientLayerRadial;
            blob.startPoint = CGPointMake(0.5, 0.5);
            blob.endPoint = CGPointMake(1, 1);
            [self.layer addSublayer:blob];
            [blobs addObject:blob];
        }
        _blobs = blobs;
        [self applyTheme];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)setTranslucent:(BOOL)translucent {
    _translucent = translucent;
    [self applyTheme];
}

- (void)applyTheme {
    NSArray *colors = CCTheme.blobColors;
    CCWithoutAnimation(^{
        self.layer.backgroundColor = (self.translucent ? CCTheme.bgTranslucent : CCTheme.bg).CGColor;
        for (NSUInteger i = 0; i < 3; i++) {
            NSColor *c = colors[i];
            self->_blobs[i].colors = CCCGColors(@[ c, [c colorWithAlphaComponent:0] ]);
        }
    });
}

- (void)layout {
    [super layout];
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    BOOL down = CCLayerYDown(self.layer);
    // Frames in top-left coordinates, mirroring the XAML margins.
    NSArray<NSValue *> *frames = @[
        [NSValue valueWithRect:NSMakeRect(-220, -320, 820, 820)],
        [NSValue valueWithRect:NSMakeRect(w + 200 - 720, -260, 720, 720)],
        [NSValue valueWithRect:NSMakeRect(w - 120 - 640, h + 380 - 640, 640, 640)],
    ];
    CCWithoutAnimation(^{
        for (NSUInteger i = 0; i < 3; i++) {
            NSRect f = frames[i].rectValue;
            if (!down) f.origin.y = h - f.origin.y - f.size.height;
            self->_blobs[i].frame = f;
        }
    });
}

- (void)startDrifting {
    if (!CCMotionEnabled()) return;
    double drift[3][3] = { { 70, 40, 26 }, { -60, 50, 31 }, { 40, -60, 37 } };
    double sign = CCLayerYDown(self.layer) ? 1 : -1;
    for (int i = 0; i < 3; i++) {
        for (int axis = 0; axis < 2; axis++) {
            double distance = drift[i][axis] * (axis == 1 ? sign : 1);
            double seconds = drift[i][2] * (axis == 1 ? 1.3 : 1);
            CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:axis == 0 ? @"transform.translation.x" : @"transform.translation.y"];
            NSMutableArray *values = [NSMutableArray array];
            for (int k = 0; k <= 120; k++) [values addObject:@(distance * CCEaseSine(k / 120.0))];
            a.values = values;
            a.duration = seconds;
            a.autoreverses = YES;
            a.repeatCount = HUGE_VALF;
            [_blobs[i] addAnimation:a forKey:axis == 0 ? @"x" : @"y"];
        }
    }
}

@end

// ───────────── sidebar ─────────────

@interface CCNavItem : NSView <CCLive>
@property (nonatomic) BOOL selected;
/// A figure at the trailing edge (what the page holds), like Finder's sidebar counts; nil hides it.
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) void (^onClick)(void);
@end

@implementation CCNavItem {
    CCBox *_box;
    CCIcon *_icon;
    CCLabel *_label, *_detail;
    NSTrackingArea *_tracking;
    BOOL _hovered;
}

- (instancetype)initWithSymbol:(NSString *)symbol key:(NSString *)key {
    if ((self = [super initWithFrame:NSZeroRect])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        CCSize(self, 0, 44);
        _box = [[CCBox alloc] initWithFrame:NSZeroRect];
        _box.radius = 12;
        _icon = [CCIcon symbol:symbol size:17 weight:NSFontWeightRegular role:CCRoleMuted];
        _label = [CCLabel key:key size:14 weight:NSFontWeightMedium role:CCRoleMuted];
        NSStackView *row = CCHStack(@[ _icon, _label ], 14);
        _detail = [CCLabel text:@"" size:12 weight:NSFontWeightMedium role:CCRoleFaint];
        _detail.hidden = YES;
        [self addSubview:_box];
        [self addSubview:row];
        [self addSubview:_detail];
        CCPin(_box, self, NSEdgeInsetsMake(0, 0, 0, 0));
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_detail.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_detail.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_detail.leadingAnchor constraintGreaterThanOrEqualToAnchor:row.trailingAnchor constant:8],
            [_icon.widthAnchor constraintEqualToConstant:22],
        ]];
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityRadioButtonRole;
        self.accessibilityLabel = L(key);
        [self applyTheme];
    }
    return self;
}

- (void)setDetail:(NSString *)detail {
    _detail.stringValue = detail ?: @"";
    _detail.hidden = detail.length == 0;
    self.accessibilityValueDescription = detail;
}

- (NSString *)detail { return _detail.hidden ? nil : _detail.stringValue; }

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.accessibilityValue = @(selected);
    [self applyTheme];
}

- (void)applyTheme {
    BOOL selected = self.selected, hovered = _hovered;
    _box.fill = ^NSColor *{ return selected ? CCTheme.accentSoft : hovered ? CCTheme.hover : NSColor.clearColor; };
    _label.role = selected || hovered ? CCRoleText : CCRoleMuted;
    _label.font = CCFont(14, selected ? NSFontWeightSemibold : NSFontWeightMedium);
    _icon.role = selected ? CCRoleAccent : hovered ? CCRoleText : CCRoleMuted;
}

- (void)applyLanguage { self.accessibilityLabel = _label.stringValue; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self applyTheme]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self applyTheme]; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds) && self.onClick) self.onClick();
}
- (BOOL)accessibilityPerformPress {
    if (self.onClick) self.onClick();
    return YES;
}

@end

// ───────────── window ─────────────

@interface CCWindow : NSWindow
@property (nonatomic, copy) void (^onEscape)(void);
@end

@implementation CCWindow
- (void)cancelOperation:(id)sender {
    if (self.onEscape) self.onEscape();
}
@end

@implementation CCWindowController {
    NSVisualEffectView *_vibrancy;
    CCBackgroundView *_background;
    NSView *_chrome;
    NSArray<CCNavItem *> *_navItems;
    CCBox *_indicator;
    NSLayoutConstraint *_indicatorTop;
    CCTween *_indicatorTween;
    NSView *_pageHost;
    NSArray<CCPageView *> *_pages;
    CCPage _shownPage;
    CCButton *_themeButton, *_accessButton;
    CCPill *_accessPill;
    CCLabel *_diskName, *_diskFree, *_diskText, *_lifetime;
    CCSmoothBar *_diskBar;
    CCCleanOverlay *_cleanOverlay;
    CCDetailsSheet *_details;
    CCConfirmDialog *_confirm;
    CCToast *_toast;
    BOOL _wasDark;
}

- (instancetype)init {
    CCSettings *s = M().settings;
    NSRect visible = NSScreen.mainScreen.visibleFrame;
    CGFloat width = s.windowWidth >= 980 ? s.windowWidth : 1240;
    CGFloat height = s.windowHeight >= 480 ? s.windowHeight : 800;
    width = MAX(980, MIN(width, visible.size.width - 16));
    height = MAX(MIN(480, visible.size.height - 16), MIN(height, visible.size.height - 16));
    NSRect frame = NSMakeRect(NSMidX(visible) - width / 2, NSMidY(visible) - height / 2, width, height);

    CCWindow *window = [[CCWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"JunkCleanup";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"main"];
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.contentMinSize = NSMakeSize(980, 480);
    window.releasedWhenClosed = NO;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    if ((self = [super initWithWindow:window])) {
        window.delegate = self;
        __weak CCWindowController *weak = self;
        window.onEscape = ^{ [weak escape]; };
        [self build];
        [self observe];
        // Created now, so it hears the first scan and measures the disk alongside it.
        (void)CCDiskModel.shared;
        [self applyAppearance];
        _shownPage = (CCPage)-1;
        [self showPage:M().page];
        [self refresh];
    }
    return self;
}

- (void)build {
    NSView *root = CCAuto([CCFlippedView new]);
    root.wantsLayer = YES;
    self.window.contentView = root;

    _vibrancy = CCAuto([NSVisualEffectView new]);
    _vibrancy.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _vibrancy.material = NSVisualEffectMaterialUnderWindowBackground;
    _vibrancy.state = NSVisualEffectStateActive;
    [root addSubview:_vibrancy];
    CCPin(_vibrancy, root, NSEdgeInsetsMake(0, 0, 0, 0));

    _background = CCAuto([CCBackgroundView new]);
    [root addSubview:_background];
    CCPin(_background, root, NSEdgeInsetsMake(0, 0, 0, 0));

    _chrome = CCAuto([CCFlippedView new]);
    _chrome.wantsLayer = YES;
    [root addSubview:_chrome];
    CCPin(_chrome, root, NSEdgeInsetsMake(0, 0, 0, 0));

    NSView *titlebar = [self buildTitlebar];
    NSView *sidebar = [self buildSidebar];
    _pageHost = CCAuto([CCFlippedView new]);
    [_chrome addSubview:titlebar];
    [_chrome addSubview:sidebar];
    [_chrome addSubview:_pageHost];
    [NSLayoutConstraint activateConstraints:@[
        [titlebar.topAnchor constraintEqualToAnchor:_chrome.topAnchor],
        [titlebar.leadingAnchor constraintEqualToAnchor:_chrome.leadingAnchor],
        [titlebar.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor],
        [titlebar.heightAnchor constraintEqualToConstant:52],
        [sidebar.topAnchor constraintEqualToAnchor:titlebar.bottomAnchor constant:4],
        [sidebar.leadingAnchor constraintEqualToAnchor:_chrome.leadingAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:_chrome.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:236],
        [_pageHost.topAnchor constraintEqualToAnchor:titlebar.bottomAnchor constant:4],
        [_pageHost.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [_pageHost.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor],
        [_pageHost.bottomAnchor constraintEqualToAnchor:_chrome.bottomAnchor],
    ]];

    CCSettingsPage *settings = [CCSettingsPage new];
    __weak CCWindowController *weak = self;
    settings.applyAppearance = ^{ [weak applyAppearance]; };
    settings.alert = ^(NSString *title, NSString *body) { [weak alert:title body:body]; };
    _pages = @[ [CCDashboardPage new], [CCTargetsPage new], [CCDiskPage new], settings, [CCAboutPage new] ];
    for (CCPageView *page in _pages) {
        page.translatesAutoresizingMaskIntoConstraints = NO;
        page.wantsLayer = YES;
        page.hidden = YES;
        [_pageHost addSubview:page];
        CCPin(page, _pageHost, NSEdgeInsetsMake(0, 0, 0, 0));
    }

    _cleanOverlay = CCAuto([CCCleanOverlay new]);
    _details = CCAuto([CCDetailsSheet new]);
    _confirm = CCAuto([CCConfirmDialog new]);
    _toast = [CCToast new];
    [root addSubview:_cleanOverlay];
    [root addSubview:_details];
    [root addSubview:_confirm];
    [root addSubview:_toast];
    CCPin(_cleanOverlay, root, NSEdgeInsetsMake(0, 0, 0, 0));
    CCPin(_details, root, NSEdgeInsetsMake(0, 0, 0, 0));
    CCPin(_confirm, root, NSEdgeInsetsMake(0, 0, 0, 0));
    [NSLayoutConstraint activateConstraints:@[
        [_toast.topAnchor constraintEqualToAnchor:root.topAnchor constant:64],
        [_toast.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-28],
    ]];

    M().confirm = ^(NSString *title, NSString *body, NSString *okText, BOOL danger, void (^answer)(BOOL)) {
        CCWindowController *s = weak;
        [s->_confirm showTitle:title body:body ok:okText danger:danger answer:answer];
    };
}

- (NSView *)buildTitlebar {
    NSView *bar = CCAuto([CCFlippedView new]);
    CCLogoView *logo = CCAuto([CCLogoView new]);
    CCSize(logo, 24, 24);
    CCLabel *name = [CCLabel key:@"app.name" size:14.5 weight:NSFontWeightSemibold role:CCRoleText];
    NSStackView *brand = CCHStack(@[ logo, name ], 10);
    [bar addSubview:brand];

    _themeButton = [CCButton buttonWithStyle:CCButtonIcon title:nil symbol:CCTheme.isDark ? @"moon" : @"sun.max"];
    _themeButton.symbolSize = 15;
    _themeButton.iconView.wantsLayer = YES;
    _themeButton.onClick = ^{
        CCSettings *s = M().settings;
        s.theme = CCTheme.isDark ? @"light" : @"dark";
        [M() saveSettings];
        [CCTheme applyMode:s.theme];
    };
    _accessButton = [CCButton buttonWithStyle:CCButtonSubtle title:nil symbol:@"lock.shield"];
    _accessButton.locKey = @"titlebar.runAsAdmin";
    _accessButton.fontSize = 12.5;
    _accessButton.iconColor = ^NSColor *{ return CCTheme.warning; };
    _accessButton.onClick = ^{ [M() openFullDiskAccessSettings]; };
    _accessPill = [CCPill pillWithText:L(@"titlebar.admin") symbol:@"lock.shield" color:^NSColor *{ return CCTheme.success; }
                                  soft:^NSColor *{ return CCTheme.successSoft; }];
    NSStackView *actions = CCHStack(@[ _themeButton, _accessButton, _accessPill ], 10);
    [bar addSubview:actions];
    [NSLayoutConstraint activateConstraints:@[
        // after the traffic lights
        [brand.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:86],
        [brand.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [actions.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-18],
        [actions.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    ]];
    return bar;
}

- (NSView *)buildSidebar {
    NSView *sidebar = CCAuto([CCFlippedView new]);
    NSArray *symbols = @[ @"house", @"list.bullet", @"chart.pie", @"gearshape", @"info.circle" ];
    NSArray *keys = @[ @"nav.dashboard", @"nav.targets", @"nav.disk", @"nav.settings", @"nav.about" ];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < symbols.count; i++) {
        CCNavItem *item = [[CCNavItem alloc] initWithSymbol:symbols[i] key:keys[i]];
        CCPage page = (CCPage)i;
        item.onClick = ^{ M().page = page; };
        [items addObject:item];
    }
    _navItems = items;
    NSStackView *nav = CCVStack(items, 4);
    for (NSView *item in items) [item.widthAnchor constraintEqualToAnchor:nav.widthAnchor].active = YES;
    [sidebar addSubview:nav];

    _indicator = [[CCBox alloc] initWithFrame:NSZeroRect];
    _indicator.radius = 2;
    _indicator.gradient = ^NSArray<NSColor *> *{ return CCTheme.accentGradient; };
    _indicator.layer.shadowOpacity = 0.8;
    _indicator.layer.shadowRadius = 6;
    _indicator.layer.shadowOffset = CGSizeZero;
    [sidebar addSubview:_indicator];
    _indicatorTop = [_indicator.topAnchor constraintEqualToAnchor:nav.topAnchor constant:11];

    // disk card
    CCIcon *drive = [CCIcon symbol:@"internaldrive" size:14 weight:NSFontWeightRegular role:CCRoleAccent];
    _diskName = [CCLabel text:@"" size:13 weight:NSFontWeightSemibold role:CCRoleText];
    [_diskName setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _diskFree = [CCLabel text:@"" size:11.5 weight:NSFontWeightRegular role:CCRoleFaint];
    // The volume's whole name on the first line; how much is free goes under what is used.
    _diskName.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSStackView *diskTop = CCHStack(@[ drive, _diskName, CCSpacer() ], 8);
    _diskBar = [CCSmoothBar new];
    _diskBar.fillGradient = ^NSArray<NSColor *> *{ return CCTheme.accentGradient; };
    CCSize(_diskBar, 0, 6);
    _diskText = [CCLabel text:@"" size:11.5 weight:NSFontWeightRegular role:CCRoleFaint];
    // Wraps rather than lose the figure: a long translation takes two lines.
    _lifetime = [CCLabel text:@"" size:11.5 weight:NSFontWeightRegular role:CCRoleSuccess];
    _lifetime.wraps = YES;
    NSStackView *disk = CCVStack(@[ diskTop, _diskBar, _diskText, _diskFree, _lifetime ], 0);
    [disk setCustomSpacing:2 afterView:_diskText];
    [disk setCustomSpacing:12 afterView:diskTop];
    [disk setCustomSpacing:8 afterView:_diskBar];
    [disk setCustomSpacing:4 afterView:_diskText];
    [disk setCustomSpacing:4 afterView:_diskFree];
    for (NSView *v in @[ diskTop, _diskBar, _lifetime ]) [v.widthAnchor constraintEqualToAnchor:disk.widthAnchor].active = YES;
    CCCard *diskCard = [CCCard card];
    diskCard.radius = 16;
    [diskCard addSubview:disk];
    CCPin(disk, diskCard, NSEdgeInsetsMake(16, 16, 16, 16));
    [sidebar addSubview:diskCard];

    [NSLayoutConstraint activateConstraints:@[
        [nav.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:8],
        [nav.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:12],
        [nav.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-12],
        _indicatorTop,
        [_indicator.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:4],
        [_indicator.widthAnchor constraintEqualToConstant:4],
        [_indicator.heightAnchor constraintEqualToConstant:22],
        [diskCard.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [diskCard.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-16],
        [diskCard.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-20],
    ]];
    return sidebar;
}

- (void)observe {
    NSNotificationCenter *c = NSNotificationCenter.defaultCenter;
    __weak CCWindowController *weak = self;
    [c addObserverForName:CCModelDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) { [weak refresh]; }];
    [c addObserverForName:CCModelPageNotification object:nil queue:nil usingBlock:^(NSNotification *n) { [weak showPage:M().page]; }];
    [c addObserverForName:CCModelCleanStateNotification object:nil queue:nil usingBlock:^(NSNotification *n) { [weak cleanStateChanged]; }];
    [c addObserverForName:CCModelDetailsNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        CCWindowController *s = weak;
        if (M().detailsTarget) [s->_details show];
        else [s->_details hide];
    }];
    [c addObserverForName:CCModelToastNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        CCWindowController *s = weak;
        [s->_toast showSymbol:n.userInfo[@"symbol"] text:n.userInfo[@"text"]];
    }];
    [c addObserverForName:CCThemeDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) { [weak themeChanged]; }];
    [c addObserverForName:CCLanguageDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        CCWindowController *s = weak;
        [s.window.contentView cc_broadcastLanguage];
        [s refresh];
    }];
    [c addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        [M() refreshAccess];
        [M() refreshDisk];
    }];
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"AppleInterfaceThemeChangedNotification" object:nil queue:nil
                                                           usingBlock:^(NSNotification *n) {
        dispatch_async(dispatch_get_main_queue(), ^{ [CCTheme systemAppearanceChanged]; });
    }];
    _wasDark = CCTheme.isDark;
}

- (void)themeChanged {
    [self.window.contentView cc_broadcastTheme];
    BOOL dark = CCTheme.isDark;
    if (dark != _wasDark) {
        _wasDark = dark;
        _themeButton.symbol = dark ? @"moon" : @"sun.max";
        CCTransformView(_themeButton.iconView, CCXformMake(1, 0, dark ? -180 : 180), 0, nil);
        CCTransformView(_themeButton.iconView, CCXformIdentity(), 500, CCEaseBack(0.5));
    }
    [self applyAppearance];
    [self refresh];
}

- (void)applyAppearance {
    BOOL translucent = M().settings.translucency;
    _vibrancy.hidden = !translucent;
    _background.translucent = translucent;
    self.window.opaque = !translucent;
    self.window.backgroundColor = translucent ? NSColor.clearColor : CCTheme.bg;
}

- (void)refresh {
    CCModel *m = M();
    _diskName.stringValue = m.diskName;
    _diskFree.stringValue = LF(@"disk.free", CCFormatBytes(m.diskFree));
    _diskText.stringValue = LF(@"disk.used", CCFormatBytes(m.diskUsed), CCFormatBytes(m.diskTotal));
    _diskBar.value = m.diskTotal > 0 ? (double)m.diskUsed / m.diskTotal : 0;
    _lifetime.stringValue = LF(@"disk.lifetime", CCFormatBytes(m.lifetimeFreed));
    _lifetime.hidden = m.lifetimeFreed <= 0;
    _accessButton.hidden = m.hasFullDiskAccess;
    _accessButton.toolTip = L(@"titlebar.adminHint");
    _accessPill.hidden = !m.hasFullDiskAccess;
    _accessPill.label.stringValue = L(@"titlebar.admin");
    _themeButton.toolTip = L(@"titlebar.theme");
    // One number at the edge of the sidebar: what a press of Clean frees, the same on Overview and the Disk page.
    long long cleanable = m.hasResults && !m.scanning ? m.cleanableBytes : 0;
    _navItems[CCPageDashboard].detail = cleanable > 0 ? CCFormatBytes(cleanable) : nil;
    _navItems[CCPageTargets].detail = nil;
    _navItems[CCPageDisk].detail = nil;
    for (CCPageView *page in _pages)
        if (!page.hidden) [page refresh];
    if (m.overlayVisible) [_cleanOverlay refresh];
}

- (void)cleanStateChanged {
    CCModel *m = M();
    if (m.overlayVisible && _cleanOverlay.hidden) [_cleanOverlay show];
    else if (!m.overlayVisible && !_cleanOverlay.hidden) [_cleanOverlay hide];
    [_cleanOverlay refresh];
    if (m.cleanDone && m.cleanFreed > 0 && m.overlayVisible) [_cleanOverlay celebrate];
}

// ───────────── navigation ─────────────

- (void)showPage:(CCPage)page {
    if (page == _shownPage) return;
    BOOL forward = (NSInteger)page >= (NSInteger)_shownPage;
    CCPageView *previous = (NSInteger)_shownPage >= 0 ? _pages[_shownPage] : nil;
    CCPageView *next = _pages[page];
    BOOL first = previous == nil;
    _shownPage = page;
    M().page = page;
    for (NSUInteger i = 0; i < _navItems.count; i++) _navItems[i].selected = i == (NSUInteger)page;
    [self moveIndicator:!first];

    next.hidden = NO;
    [next refresh];
    [_pageHost addSubview:next positioned:NSWindowAbove relativeTo:nil];
    if (!next.entrancePlayed) {
        [next.superview layoutSubtreeIfNeeded];
        [next playEntrance];
    }
    if (!first) CCSlideIn(next, forward ? 24 : -24, 60);

    if (previous) {
        if (!CCMotionEnabled()) {
            previous.hidden = YES;
            return;
        }
        CCAnimateNumber(previous.layer, @"opacity", 0, 160, CCEaseIn, 0);
        CCTransformView(previous, CCXformMake(1, forward ? -12 : 12, 0), 160, CCEaseIn);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.17 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_pages[self->_shownPage] == previous) return;
            previous.hidden = YES;
            CCWithoutAnimation(^{ previous.layer.opacity = 1; });
            CCTransformView(previous, CCXformIdentity(), 0, nil);
        });
    }
}

- (void)moveIndicator:(BOOL)animated {
    CGFloat to = 11 + (CGFloat)_shownPage * 48;
    [_indicatorTween stop];
    if (!animated) {
        _indicatorTop.constant = to;
        return;
    }
    __weak CCWindowController *weak = self;
    _indicatorTween = [CCTween from:_indicatorTop.constant to:to duration:420 delay:0 ease:CCEaseSpring update:^(double v) {
        CCWindowController *s = weak;
        if (s) s->_indicatorTop.constant = v;
    } completion:nil];
}

- (void)escape {
    if (_confirm.isOpen) [_confirm closeWith:NO];
    else if (_details.isOpen) [M() closeDetails];
    else if (M().cleaning) [M() cancelClean];
    else if (M().overlayVisible) [M() closeCleanOverlay];
    else if (M().scanning) [M() cancelScan];
    else if (CCDiskModel.shared.analyzing) [CCDiskModel.shared cancel];
}

- (void)alert:(NSString *)title body:(NSString *)body {
    [_confirm showTitle:title body:body ok:L(@"common.ok") danger:NO answer:^(BOOL ok) {}];
}

// ───────────── window events ─────────────

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [(CCBackgroundView *)_background startDrifting];
    if (!CCMotionEnabled()) return;
    CCWithoutAnimation(^{ self->_chrome.layer.opacity = 0; });
    CCAnimateNumber(_chrome.layer, @"opacity", 1, 380, CCEaseOut, 0);
    CCTransformView(_chrome, CCXformMake(0.985, 0, 0), 0, nil);
    CCTransformView(_chrome, CCXformIdentity(), 650, CCEaseOutStrong);
}

- (void)windowWillClose:(NSNotification *)notification {
    NSSize size = self.window.frame.size;
    M().settings.windowWidth = size.width;
    M().settings.windowHeight = size.height;
    [M() saveSettings];
    [NSApp terminate:nil];
}

- (void)windowDidResize:(NSNotification *)notification {
    CCXformRelayout(_chrome);
}

// ───────────── screenshots ─────────────

typedef CGImageRef (*CreateWindowImage)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);

- (void)saveWindowTo:(NSString *)path {
    // Deprecated in the SDK but still present at run time, and an app may always capture its own windows.
    CreateWindowImage create = (CreateWindowImage)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
    if (!create) return;
    CGImageRef image = create(CGRectNull, kCGWindowListOptionIncludingWindow, (CGWindowID)self.window.windowNumber,
                              kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
    if (!image) return;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    CGImageRelease(image);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
// The step block keeps itself alive until the app quits at the end of the run.
- (void)runTour {
    void (^after)(double, dispatch_block_t) = ^(double seconds, dispatch_block_t block) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
    };
    void (^mark)(const char *) = ^(const char *name) {
        printf("tour %s %.3f\n", name, NSDate.date.timeIntervalSince1970);
        fflush(stdout);
    };
    __block void (^whenIdle)(dispatch_block_t);
    whenIdle = ^(dispatch_block_t block) {
        if (M().scanning || CCDiskModel.shared.analyzing) after(0.05, ^{ whenIdle(block); });
        else block();
    };
    CCDiskModel *disk = CCDiskModel.shared;
    after(4.0, ^{
        mark("start");
        after(1.5, ^{
            mark("scan");
            [M() startScan];
            after(0.3, ^{ whenIdle(^{
                mark("scanned");
                after(1.6, ^{
                    mark("disk");
                    M().page = CCPageDisk;
                    after(2.6, ^{
                        mark("band");
                        [disk pickSegment:CCSpaceSystem];
                        after(3.0, ^{
                            mark("clear");
                            [disk clearFilter];
                            after(2.2, ^{
                                mark("pick");
                                for (CCVolume *v in disk.volumes)
                                    if (!v.isHome) { [disk selectVolume:v]; break; }
                                after(0.3, ^{ whenIdle(^{
                                    mark("mapped");
                                    after(2.6, ^{
                                        mark("end");
                                        [NSApp terminate:nil];
                                    });
                                }); });
                            });
                        });
                    });
                });
            }); });
        });
    });
}

- (void)captureInto:(NSString *)folder {
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    __weak CCWindowController *weak = self;
    __block NSInteger step = 0;
    __block BOOL settled = NO, diskSettled = NO;
    NSArray *shots = @[ @"dashboard", @"targets", @"disk", @"settings", @"settings-cleaning", @"about", @"insights", @"light", @"expanded", @"details", @"confirm" ];
    // --capture-clean also runs the clean it asked about (into the Trash by default) and shoots the result.
    // Then Overview and the Disk page once the clean is over, to see the numbers go down together.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--capture-clean"])
        shots = [shots arrayByAddingObjectsFromArray:@[ @"cleaning", @"after", @"after-disk" ]];
    // --page disk shoots only the Disk page: the map, then an item with its parts open. Nothing is scanned or removed.
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger pageArg = [args indexOfObject:@"--page"];
    BOOL diskOnly = pageArg != NSNotFound && pageArg + 1 < args.count && [[args[pageArg + 1] lowercaseString] isEqualToString:@"disk"];
    // It also resizes the window wide and to its minimum, and checks every page lets it grow and shrink (stdout).
    if (diskOnly) shots = @[ @"disk", @"disk-filter", @"disk-parts", @"disk-wide", @"disk-narrow", @"disk-narrow-top", @"resize-check" ];
    void (^resize)(CGFloat) = ^(CGFloat width) {
        CCWindowController *s = weak;
        NSRect visible = s.window.screen.visibleFrame;
        CGFloat height = MIN(900, NSHeight(visible) - 16);
        [s.window setFrame:NSMakeRect(NSMidX(visible) - width / 2, NSMidY(visible) - height / 2, width, height) display:YES];
        [s.window layoutIfNeeded];
    };
    __block void (^next)(void);
    void (^after)(double, void (^)(void)) = ^(double seconds, void (^block)(void)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
    };
    next = ^{
        CCWindowController *s = weak;
        if (!s) return;
        if (M().scanning || M().cleaning || CCDiskModel.shared.analyzing) {
            after(0.3, next);
            diskSettled = NO;
            return;
        }
        // The rows play in after the analysis; shoot them settled.
        if (step > 0 && [shots[step - 1] hasPrefix:@"disk"] && !diskSettled) {
            diskSettled = YES;
            after(1.4, next);
            return;
        }
        // Let the confetti rise above the card before the last shot.
        if (step > 0 && [shots[step - 1] isEqualToString:@"cleaning"] && !settled) {
            settled = YES;
            after(0.7, next);
            return;
        }
        if (step > 0) [s saveWindowTo:[folder stringByAppendingPathComponent:[shots[step - 1] stringByAppendingString:@".png"]]];
        if (step == (NSInteger)shots.count) {
            [s->_confirm closeWith:NO];
            [NSApp terminate:nil];
            return;
        }
        NSString *shot = shots[step++];
        if ([shot isEqualToString:@"dashboard"]) M().page = CCPageDashboard;
        else if ([shot isEqualToString:@"targets"]) M().page = CCPageTargets;
        else if ([shot isEqualToString:@"disk"]) M().page = CCPageDisk;
        else if ([shot isEqualToString:@"disk-filter"]) [CCDiskModel.shared pickSegment:CCSpaceSystem];
        else if ([shot isEqualToString:@"disk-parts"]) {
            [CCDiskModel.shared clearFilter];
            [(CCDiskPage *)s->_pages[CCPageDisk] revealPartsForCapture];
        }
        else if ([shot isEqualToString:@"disk-wide"]) resize(MIN(1600, NSWidth(s.window.screen.visibleFrame) - 16));
        else if ([shot isEqualToString:@"disk-narrow"]) resize(980);
        else if ([shot isEqualToString:@"disk-narrow-top"]) {
            NSScrollView *scroll = s->_pages[CCPageDisk].subviews.firstObject;
            [scroll.documentView scrollPoint:NSZeroPoint];
        }
        else if ([shot isEqualToString:@"resize-check"]) {
            NSArray *names = @[ @"dashboard", @"targets", @"disk", @"settings", @"about" ];
            for (NSUInteger i = 0; i < names.count; i++) {
                M().page = (CCPage)i;
                CGFloat got[2];
                CGFloat want[2] = { MIN(1600, NSWidth(s.window.screen.visibleFrame) - 16), 980 };
                for (int k = 0; k < 2; k++) {
                    resize(want[k]);
                    got[k] = NSWidth(s.window.frame);
                }
                printf("resize %-9s asked %.0f -> %.0f, asked %.0f -> %.0f\n", [names[i] UTF8String], want[0], got[0], want[1], got[1]);
            }
            fflush(stdout);
            M().page = CCPageDisk;
            // The saved window size is the usual one again, not the minimum the check ended on.
            resize(MIN(1240, NSWidth(s.window.screen.visibleFrame) - 16));
        }
        else if ([shot isEqualToString:@"settings"]) M().page = CCPageSettings;
        else if ([shot isEqualToString:@"settings-cleaning"]) {
            NSScrollView *scroll = s->_pages[CCPageSettings].subviews.firstObject;
            [scroll.documentView scrollPoint:NSMakePoint(0, 560)];
        }
        else if ([shot isEqualToString:@"about"]) M().page = CCPageAbout;
        else if ([shot isEqualToString:@"insights"]) {
            M().page = CCPageDashboard;
            NSScrollView *scroll = s->_pages[CCPageDashboard].subviews.firstObject;
            [scroll.documentView scrollPoint:NSMakePoint(0, NSHeight([scroll.documentView bounds]))];
        } else if ([shot isEqualToString:@"light"]) {
            NSScrollView *scroll = s->_pages[CCPageDashboard].subviews.firstObject;
            [scroll.documentView scrollPoint:NSZeroPoint];
            [CCTheme applyMode:@"light"];
        } else if ([shot isEqualToString:@"expanded"]) {
            [CCTheme applyMode:M().settings.theme];
            M().page = CCPageTargets;
            CCTargetItem *biggest = M().topTargets.firstObject;
            if (biggest) {
                M().filter = CCCategoryName(biggest.target.category);
                if (!biggest.expanded) [M() toggleExpanded:biggest];
            }
        } else if ([shot isEqualToString:@"details"]) {
            M().filter = @"All";
            M().page = CCPageDashboard;
            if (M().topTargets.firstObject) [M() openDetails:M().topTargets.firstObject];
        } else if ([shot isEqualToString:@"confirm"]) {
            [M() closeDetails];
            M().page = CCPageDashboard;
            // Only to shoot the question: with "Ask before cleaning" off, Clean would start right away.
            if (M().settings.confirmClean) [M() clean];
        } else if ([shot isEqualToString:@"after"]) {
            [M() closeCleanOverlay];
            M().page = CCPageDashboard;
            NSScrollView *scroll = s->_pages[CCPageDashboard].subviews.firstObject;
            [scroll.documentView scrollPoint:NSZeroPoint];
        } else if ([shot isEqualToString:@"after-disk"]) {
            M().page = CCPageDisk;
        } else if ([shot isEqualToString:@"cleaning"]) {
            [s->_confirm closeWith:YES];
            after(0.5, next);
            return;
        }
        after(1.6, next);
    };
    after(1.0, ^{
        if (!diskOnly) [M() startScan];
        after(0.5, next);
    });
}

#pragma clang diagnostic pop

@end
