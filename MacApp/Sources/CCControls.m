#import "CCControls.h"
#import "CCSettings.h"

// ───────────── layout helpers ─────────────

@implementation NSView (CC)

- (void)cc_broadcastTheme {
    if ([self respondsToSelector:@selector(applyTheme)]) [(id<CCLive>)self applyTheme];
    for (NSView *v in self.subviews) [v cc_broadcastTheme];
}

- (void)cc_broadcastLanguage {
    if ([self respondsToSelector:@selector(applyLanguage)]) [(id<CCLive>)self applyLanguage];
    for (NSView *v in self.subviews) [v cc_broadcastLanguage];
}

@end

__kindof NSView *CCAuto(__kindof NSView *view) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

void CCPin(NSView *view, NSView *container, NSEdgeInsets insets) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
    ]];
}

void CCSize(NSView *view, CGFloat width, CGFloat height) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    if (width > 0) [view.widthAnchor constraintEqualToConstant:width].active = YES;
    if (height > 0) [view.heightAnchor constraintEqualToConstant:height].active = YES;
}

NSStackView *CCHStack(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    s.distribution = NSStackViewDistributionFill;
    s.alignment = NSLayoutAttributeCenterY;
    s.spacing = spacing;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    s.detachesHiddenViews = YES;
    return s;
}

NSStackView *CCVStack(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationVertical;
    s.distribution = NSStackViewDistributionFill;
    s.alignment = NSLayoutAttributeLeading;
    s.spacing = spacing;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    s.detachesHiddenViews = YES;
    return s;
}

NSView *CCSpacer(void) {
    NSView *v = CCAuto([NSView new]);
    [v setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [v setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    return v;
}

BOOL CCLayerYDown(CALayer *layer) {
    // AppKit gives each view's layer the view's own coordinate system; sublayers follow the view that owns them.
    for (CALayer *l = layer; l; l = l.superlayer)
        if ([l.delegate isKindOfClass:NSView.class]) return ((NSView *)l.delegate).isFlipped;
    return NO;
}

@implementation CCFlippedView
- (BOOL)isFlipped { return YES; }
@end

// ───────────── text ─────────────

@implementation CCLabel

static const NSLayoutPriority CCLabelKeepsWidth = NSLayoutPriorityDragThatCanResizeWindow - 10;

+ (instancetype)text:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role {
    CCLabel *l = [[self alloc] initWithFrame:NSZeroRect];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.editable = NO;
    l.selectable = NO;
    l.bezeled = NO;
    l.bordered = NO;
    l.drawsBackground = NO;
    l.usesSingleLineMode = YES;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.cell.truncatesLastVisibleLine = YES;
    l.font = CCFont(size, weight);
    l.role = role;
    l.stringValue = text ?: @"";
    // Just under the priority of dragging the window's edge: a narrow window cuts a long line with "…" instead of
    // refusing to get narrower. Still above everything that only fills space, so it never gives way to a spacer.
    [l setContentCompressionResistancePriority:CCLabelKeepsWidth forOrientation:NSLayoutConstraintOrientationHorizontal];
    [l setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    return l;
}

+ (instancetype)key:(NSString *)locKey size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role {
    CCLabel *l = [self text:L(locKey) size:size weight:weight role:role];
    l.locKey = locKey;
    return l;
}

- (NSView *)hitTest:(NSPoint)point {
    // Labels never take clicks: the card or button underneath gets them.
    return nil;
}

- (void)setRole:(CCRole)role {
    _role = role;
    [self applyTheme];
}

- (void)setColorBlock:(CCColorBlock)colorBlock {
    _colorBlock = [colorBlock copy];
    [self applyTheme];
}

- (void)applyTheme {
    self.textColor = self.colorBlock ? self.colorBlock() : [CCTheme colorForRole:self.role];
    if (self.lineHeight > 0) [self refreshAttributes];
}

- (void)applyLanguage {
    if (self.locKey) self.stringValue = L(self.locKey);
}

- (void)setLocKey:(NSString *)locKey {
    _locKey = [locKey copy];
    if (locKey) self.stringValue = L(locKey);
}

- (void)setWraps:(BOOL)wraps {
    _wraps = wraps;
    self.usesSingleLineMode = !wraps;
    self.lineBreakMode = wraps ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
    self.cell.wraps = wraps;
    self.maximumNumberOfLines = wraps ? 0 : 1;
    [self setContentCompressionResistancePriority:wraps ? NSLayoutPriorityRequired - 1 : NSLayoutPriorityDefaultHigh
                                   forOrientation:NSLayoutConstraintOrientationVertical];
    // A wrapping label takes the width it is given rather than insisting on one long line.
    if (wraps) {
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
}

- (void)setLineHeight:(CGFloat)lineHeight {
    _lineHeight = lineHeight;
    [self refreshAttributes];
}

- (void)setStringValue:(NSString *)stringValue {
    [super setStringValue:stringValue ?: @""];
    if (self.lineHeight > 0) [self refreshAttributes];
}

- (void)refreshAttributes {
    NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
    p.minimumLineHeight = self.lineHeight;
    p.maximumLineHeight = self.lineHeight;
    p.alignment = self.alignment;
    p.lineBreakMode = self.lineBreakMode;
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font ?: CCFont(13, NSFontWeightRegular),
        NSForegroundColorAttributeName: self.textColor ?: CCTheme.text,
        NSParagraphStyleAttributeName: p,
    };
    [super setAttributedStringValue:[[NSAttributedString alloc] initWithString:self.stringValue attributes:attributes]];
}

- (void)layout {
    [super layout];
    if (self.wraps && fabs(self.preferredMaxLayoutWidth - NSWidth(self.bounds)) > 0.5) {
        self.preferredMaxLayoutWidth = NSWidth(self.bounds);
        [self invalidateIntrinsicContentSize];
    }
}

@end

@implementation CCCounter {
    double _current;
    BOOL _initialized;
    CCTween *_tween;
}

+ (instancetype)text:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role {
    CCCounter *c = [super text:text size:size weight:weight role:role];
    c.font = CCDigitsFont(size, weight);
    c.duration = 700;
    [c setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [c render];
    return c;
}

- (void)setPart:(CCCounterPart)part {
    _part = part;
    [self render];
}

- (void)setBytes:(long long)bytes {
    _bytes = bytes;
    double to = (double)bytes;
    BOOL first = !_initialized;
    _initialized = YES;
    if (first || !CCMotionEnabled() || !self.window) {
        [_tween stop];
        _tween = nil;
        _current = to;
        [self render];
        return;
    }
    if (fabs(_current - to) < 0.5) return;
    [_tween stop];
    __weak CCCounter *weakSelf = self;
    _tween = [CCTween from:_current to:to duration:self.duration delay:0 ease:CCEaseOutStrong update:^(double v) {
        CCCounter *s = weakSelf;
        if (!s) return;
        s->_current = v;
        [s render];
    } completion:nil];
}

- (void)render {
    NSString *number, *unit;
    switch (self.part) {
        case CCCounterInteger: super.stringValue = CCFormatCount(llround(_current)); break;
        case CCCounterNumber: CCSplitBytes(_current, &number, NULL); super.stringValue = number; break;
        case CCCounterUnit: CCSplitBytes(_current, NULL, &unit); super.stringValue = unit; break;
        case CCCounterAll: super.stringValue = CCFormatBytes(_current); break;
    }
    if (self.onRender) self.onRender();
}

- (void)applyLanguage { [self render]; }

@end

@implementation CCIcon

+ (instancetype)symbol:(NSString *)symbol size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role {
    CCIcon *icon = [[self alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    icon.symbol = symbol;
    icon.role = role;
    return icon;
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)setSymbol:(NSString *)symbol {
    _symbol = [symbol copy];
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
                     ?: [NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:nil];
    self.image = image;
}

- (void)setRole:(CCRole)role {
    _role = role;
    [self applyTheme];
}

- (void)setColorBlock:(CCColorBlock)colorBlock {
    _colorBlock = [colorBlock copy];
    [self applyTheme];
}

- (void)applyTheme { self.contentTintColor = self.colorBlock ? self.colorBlock() : [CCTheme colorForRole:self.role]; }

@end

// ───────────── surfaces ─────────────

@implementation CCBox {
    CAGradientLayer *_gradientLayer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)setFill:(CCColorBlock)fill { _fill = [fill copy]; [self applyBoxColors]; }
- (void)setStroke:(CCColorBlock)stroke { _stroke = [stroke copy]; [self applyBoxColors]; }
- (void)setRadius:(CGFloat)radius { _radius = radius; [self applyBoxColors]; }
- (void)setStrokeWidth:(CGFloat)strokeWidth { _strokeWidth = strokeWidth; [self applyBoxColors]; }

- (void)setGradient:(NSArray<NSColor *> *(^)(void))gradient {
    _gradient = [gradient copy];
    if (gradient && !_gradientLayer) {
        _gradientLayer = [CAGradientLayer layer];
        [self.layer insertSublayer:_gradientLayer atIndex:0];
    }
    [self applyBoxColors];
}

- (void)applyTheme { [self applyBoxColors]; }

- (void)applyBoxColors {
    CALayer *layer = self.layer;
    CCWithoutAnimation(^{
        layer.cornerRadius = MIN(self.radius, MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2 ?: self.radius);
        layer.backgroundColor = self.fill ? self.fill().CGColor : NSColor.clearColor.CGColor;
        layer.borderColor = self.stroke ? self.stroke().CGColor : NSColor.clearColor.CGColor;
        layer.borderWidth = self.stroke ? (self.strokeWidth ?: 1) : 0;
        if (self->_gradientLayer) {
            self->_gradientLayer.colors = CCCGColors(self.gradient());
            BOOL down = CCLayerYDown(layer);
            self->_gradientLayer.startPoint = CGPointMake(0, down ? 0 : 1);
            self->_gradientLayer.endPoint = CGPointMake(1, down ? 1 : 0);
            self->_gradientLayer.cornerRadius = layer.cornerRadius;
        }
    });
}

- (void)updateLayer { [self applyBoxColors]; }

- (void)layout {
    [super layout];
    CCWithoutAnimation(^{ self->_gradientLayer.frame = self.layer.bounds; });
    [self applyBoxColors];
    CCXformRelayout(self);
}

@end

@implementation CCCard {
    NSTrackingArea *_tracking;
    CALayer *_shimmerClip;
    CAGradientLayer *_shimmer;
    BOOL _pressed;
}

+ (instancetype)card {
    CCCard *c = [[self alloc] initWithFrame:NSZeroRect];
    c.radius = 18;
    c.fill = ^NSColor *{ return CCTheme.card; };
    c.stroke = ^NSColor *{ return CCTheme.cardBorder; };
    return c;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)resetCursorRects {
    if (self.onClick) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

static void ForEachTile(NSView *view, void (^block)(CCIconTile *)) {
    for (NSView *v in view.subviews) {
        if ([v isKindOfClass:CCIconTile.class]) block((CCIconTile *)v);
        if (![v isKindOfClass:CCCard.class]) ForEachTile(v, block);
    }
}

- (void)setHovered:(BOOL)hovered {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (self.hoverable) {
        CCTransformView(self, hovered ? CCXformMake(1.012, -4, 0) : CCXformIdentity(), hovered ? 220 : 300, CCEaseCubicOut);
        [self applyBoxColors];
    }
    ForEachTile(self, ^(CCIconTile *tile) {
        if (tile.bounces) [tile setBounced:hovered];
    });
}

- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; }

- (void)mouseDown:(NSEvent *)event {
    if (!self.onClick) {
        [super mouseDown:event];
        return;
    }
    _pressed = YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (!_pressed) return;
    _pressed = NO;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.bounds) && self.onClick) self.onClick();
}

- (void)applyBoxColors {
    if (self.hoverable && self.hovered) {
        CCWithoutAnimation(^{
            self.layer.backgroundColor = CCTheme.cardHover.CGColor;
            self.layer.borderColor = CCTheme.cardBorderHover.CGColor;
            self.layer.borderWidth = 1;
            self.layer.cornerRadius = self.radius;
        });
        return;
    }
    [super applyBoxColors];
}

- (void)setShimmering:(BOOL)shimmering {
    if (_shimmering == shimmering) return;
    _shimmering = shimmering;
    if (!_shimmerClip) {
        _shimmerClip = [CALayer layer];
        _shimmerClip.masksToBounds = YES;
        _shimmerClip.opacity = 0;
        _shimmer = [CAGradientLayer layer];
        _shimmer.startPoint = CGPointMake(0, 0.5);
        _shimmer.endPoint = CGPointMake(1, 0.5);
        _shimmer.colors = CCCGColors(@[ CCHex(0xFFFFFF, 0), CCHex(0xFFFFFF, 0x14 / 255.0), CCHex(0xFFFFFF, 0x1F / 255.0),
                                        CCHex(0xFFFFFF, 0x14 / 255.0), CCHex(0xFFFFFF, 0) ]);
        _shimmer.locations = @[ @0, @0.45, @0.5, @0.55, @1 ];
        [_shimmerClip addSublayer:_shimmer];
        [self.layer insertSublayer:_shimmerClip atIndex:0];
        [self layoutShimmer];
    }
    CCAnimateNumber(_shimmerClip, @"opacity", shimmering ? 1 : 0, 300, CCEaseLinear, 0);
    if (shimmering && CCMotionEnabled()) {
        CAKeyframeAnimation *move = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        NSMutableArray *values = [NSMutableArray array];
        double w = NSWidth(self.bounds);
        for (int i = 0; i <= 96; i++) [values addObject:@(-w + 2 * w * CCEaseSine(i / 96.0))];
        move.values = values;
        move.duration = 1.6;
        move.repeatCount = HUGE_VALF;
        [_shimmer addAnimation:move forKey:@"run"];
    } else if (!shimmering) {
        CALayer *s = _shimmer;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self->_shimmering) [s removeAnimationForKey:@"run"];
        });
    }
}

- (void)layoutShimmer {
    CCWithoutAnimation(^{
        self->_shimmerClip.frame = self.layer.bounds;
        self->_shimmerClip.cornerRadius = self.radius;
        self->_shimmer.frame = self.layer.bounds;
    });
}

- (void)layout {
    [super layout];
    if (_shimmerClip) [self layoutShimmer];
}

@end

@implementation CCIconTile

+ (instancetype)tileWithSymbol:(NSString *)symbol size:(CGFloat)size radius:(CGFloat)radius iconSize:(CGFloat)iconSize {
    CCIconTile *tile = [[self alloc] initWithFrame:NSZeroRect];
    tile.radius = radius;
    CCSize(tile, size, size);
    tile->_icon = [CCIcon symbol:symbol size:iconSize weight:NSFontWeightRegular role:CCRoleAccent];
    [tile addSubview:tile->_icon];
    [NSLayoutConstraint activateConstraints:@[
        [tile->_icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [tile->_icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

- (void)setBounced:(BOOL)bounced {
    if (bounced) CCTransformView(self, CCXformMake(1.12, 0, 0), 350, CCEaseBack(0.9));
    else CCTransformView(self, CCXformIdentity(), 250, CCEaseLinear);
}

@end

@implementation CCPill

+ (instancetype)pillWithText:(NSString *)text symbol:(NSString *)symbol color:(CCColorBlock)color soft:(CCColorBlock)soft {
    CCPill *pill = [[self alloc] initWithFrame:NSZeroRect];
    pill.radius = 999;
    pill.fill = soft;
    pill->_label = [CCLabel text:text size:11 weight:NSFontWeightSemibold role:CCRoleCustom];
    pill->_label.colorBlock = color;
    NSMutableArray *views = [NSMutableArray array];
    if (symbol) {
        CCIcon *icon = [CCIcon symbol:symbol size:9.5 weight:NSFontWeightSemibold role:CCRoleCustom];
        icon.colorBlock = color;
        [views addObject:icon];
    }
    [views addObject:pill->_label];
    NSStackView *stack = CCHStack(views, 5);
    [pill addSubview:stack];
    CCPin(stack, pill, NSEdgeInsetsMake(3, 9, 3, 9));
    [pill setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return pill;
}

@end

// ───────────── buttons ─────────────

@implementation CCButton {
    NSTrackingArea *_tracking;
    BOOL _hovered, _pressed;
    CAGradientLayer *_glow, *_bg;
    CALayer *_shine;
    CCBox *_box;
    NSStackView *_content;
    CCLabel *_label;
    NSLayoutConstraint *_top, *_bottom, *_minWidth;
    NSLayoutConstraint *_leading, *_trailing;
}

+ (instancetype)buttonWithStyle:(CCButtonStyle)style title:(NSString *)title symbol:(NSString *)symbol {
    CCButton *b = [[self alloc] initWithFrame:NSZeroRect];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b->_style = style;
    b->_enabled = YES;
    b->_title = [title copy];
    b->_symbol = [symbol copy];
    [b build];
    return b;
}

- (BOOL)isFlipped { return YES; }

- (BOOL)isGradient { return self.style == CCButtonPrimary || self.style == CCButtonDanger || self.style == CCButtonSuccess; }

- (void)build {
    self.wantsLayer = YES;
    self.layerUsesCoreImageFilters = YES;
    switch (self.style) {
        case CCButtonPrimary:
        case CCButtonDanger:
        case CCButtonSuccess:
            _padding = NSEdgeInsetsMake(12, 22, 12, 22);
            _fontSize = 15;
            _symbolSize = 15;
            break;
        case CCButtonGhost:
            _padding = NSEdgeInsetsMake(9, 16, 9, 16);
            _fontSize = 14;
            _symbolSize = 12;
            break;
        case CCButtonSubtle:
            _padding = NSEdgeInsetsMake(6, 10, 6, 10);
            _fontSize = 13;
            _symbolSize = 13;
            break;
        case CCButtonIcon:
            _padding = NSEdgeInsetsMake(0, 0, 0, 0);
            _fontSize = 14;
            _symbolSize = 14;
            break;
    }

    if (self.isGradient) {
        _glow = [CAGradientLayer layer];
        _glow.cornerRadius = 14;
        _glow.opacity = 0.45;
        CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
        [blur setValue:@11 forKey:kCIInputRadiusKey];
        _glow.filters = @[ blur ];
        _bg = [CAGradientLayer layer];
        _bg.cornerRadius = 14;
        _shine = [CALayer layer];
        _shine.cornerRadius = 14;
        _shine.backgroundColor = NSColor.whiteColor.CGColor;
        _shine.opacity = 0;
        [self.layer addSublayer:_glow];
        [self.layer addSublayer:_bg];
    } else {
        _box = [[CCBox alloc] initWithFrame:NSZeroRect];
        _box.radius = self.style == CCButtonGhost ? 12 : self.style == CCButtonSubtle ? 9 : 10;
        [self addSubview:_box];
        CCPin(_box, self, NSEdgeInsetsMake(0, 0, 0, 0));
    }

    _iconView = [CCIcon symbol:self.symbol ?: @"circle" size:self.symbolSize weight:NSFontWeightMedium role:CCRoleText];
    _iconView.hidden = self.symbol == nil;
    _label = [CCLabel text:self.title ?: @"" size:self.fontSize weight:NSFontWeightSemibold role:CCRoleText];
    _label.hidden = self.title.length == 0;
    [_label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    _content = CCHStack(@[ _iconView, _label ], self.style == CCButtonGhost || self.style == CCButtonSubtle ? 7 : 10);
    // Above the button's own hug (650): in a button wider than its text, the icon and the title keep their own widths
    // and stay together in the middle. The stack has no size of its own, so its parts are what must hug.
    [_iconView setContentHuggingPriority:700 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_label setContentHuggingPriority:700 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_content setHuggingPriority:700 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_content];
    if (_shine) [self.layer addSublayer:_shine];

    if (self.style == CCButtonIcon) {
        CCSize(self, 34, 34);
        [NSLayoutConstraint activateConstraints:@[
            [_content.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_content.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    } else {
        _top = [_content.topAnchor constraintEqualToAnchor:self.topAnchor constant:self.padding.top];
        _bottom = [self.bottomAnchor constraintEqualToAnchor:_content.bottomAnchor constant:self.padding.bottom];
        _leading = [_content.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:self.padding.left];
        _trailing = [self.trailingAnchor constraintGreaterThanOrEqualToAnchor:_content.trailingAnchor constant:self.padding.right];
        NSLayoutConstraint *hug = [self.widthAnchor constraintEqualToAnchor:_content.widthAnchor constant:self.padding.left + self.padding.right];
        // Above a settings row's pull on its control (600), so a button keeps its own width; a required width still wins.
        hug.priority = 650;
        [NSLayoutConstraint activateConstraints:@[
            _top, _bottom, _leading, _trailing, hug,
            [_content.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityButtonRole;
    [self applyTheme];
}

- (void)setPadding:(NSEdgeInsets)padding {
    _padding = padding;
    _top.constant = padding.top;
    _bottom.constant = padding.bottom;
    _leading.constant = padding.left;
    _trailing.constant = padding.right;
}

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    _label.font = CCFont(fontSize, NSFontWeightSemibold);
}

- (void)setSymbolSize:(CGFloat)symbolSize {
    _symbolSize = symbolSize;
    _iconView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:symbolSize weight:NSFontWeightMedium];
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.stringValue = title ?: @"";
    _label.hidden = title.length == 0;
    self.accessibilityLabel = title;
}

- (void)setLocKey:(NSString *)locKey {
    _locKey = [locKey copy];
    self.title = L(locKey);
}

- (void)applyLanguage {
    if (self.locKey) self.title = L(self.locKey);
}

- (void)setSymbol:(NSString *)symbol {
    _symbol = [symbol copy];
    _iconView.symbol = symbol ?: @"circle";
    _iconView.hidden = symbol == nil;
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
        _hovered = NO;
        _pressed = NO;
        CCTransformView(self, CCXformIdentity(), 200, CCEaseCubicOut);
    }
    [self applyTheme];
    [self updatePulse];
    [self.window invalidateCursorRectsForView:self];
}

- (void)setPulsing:(BOOL)pulsing {
    _pulsing = pulsing;
    [self updatePulse];
}

- (void)updatePulse {
    if (!_glow) return;
    if (self.pulsing && self.enabled && CCMotionEnabled()) {
        if ([_glow animationForKey:@"pulse"]) return;
        CAKeyframeAnimation *breathe = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        NSMutableArray *values = [NSMutableArray array];
        for (int i = 0; i <= 84; i++) [values addObject:@(0.45 + 0.5 * CCEaseSine(i / 84.0))];
        breathe.values = values;
        breathe.duration = 1.4;
        breathe.autoreverses = YES;
        breathe.repeatCount = HUGE_VALF;
        [_glow addAnimation:breathe forKey:@"pulse"];
    } else {
        [_glow removeAnimationForKey:@"pulse"];
    }
}

- (NSArray<NSColor *> *)gradientColors {
    return self.style == CCButtonDanger ? CCTheme.dangerGradient : self.style == CCButtonSuccess ? CCTheme.successGradient : CCTheme.accentGradient;
}

- (void)applyTheme {
    CCRole textRole;
    switch (self.style) {
        case CCButtonPrimary:
        case CCButtonDanger:
        case CCButtonSuccess: textRole = CCRoleOnAccent; break;
        case CCButtonGhost: textRole = CCRoleText; break;
        default: textRole = _hovered && self.enabled ? CCRoleText : CCRoleMuted; break;
    }
    _label.role = textRole;
    if (self.iconColor) _iconView.colorBlock = self.iconColor;
    else _iconView.role = textRole;

    if (self.isGradient) {
        NSArray *colors = CCCGColors(self.gradientColors);
        BOOL down = CCLayerYDown(self.layer);
        CCWithoutAnimation(^{
            for (CAGradientLayer *g in @[ self->_glow, self->_bg ]) {
                g.colors = colors;
                g.locations = self.style == CCButtonPrimary ? CCTheme.accentGradientLocations : nil;
                g.startPoint = CGPointMake(0, down ? 0 : 1);
                g.endPoint = CGPointMake(1, down ? 1 : 0);
            }
            self->_bg.opacity = self.enabled ? 1 : 0.4;
            if (!self.enabled) self->_glow.opacity = 0;
            else if (!self->_hovered && ![self->_glow animationForKey:@"pulse"]) self->_glow.opacity = 0.45;
        });
        return;
    }

    _box.fill = ^NSColor *{
        if (self->_pressed && self.enabled) return CCTheme.pressed;
        if (self->_hovered && self.enabled) return CCTheme.hover;
        return self.style == CCButtonGhost ? CCTheme.input : NSColor.clearColor;
    };
    _box.stroke = self.style != CCButtonGhost ? nil : ^NSColor *{
        return self->_hovered && self.enabled ? CCTheme.cardBorderHover : CCTheme.inputBorder;
    };
    self.alphaValue = self.enabled || self.style != CCButtonGhost ? 1 : 0.4;
}

- (void)layout {
    [super layout];
    if (!self.isGradient) {
        CCXformRelayout(self);
        return;
    }
    NSRect b = self.layer.bounds;
    BOOL down = CCLayerYDown(self.layer);
    // The glow sits 10 pt below the top and spills 4 pt under the button, 6 pt in from each side (Margin="6,10,6,-4").
    CGRect glow = CGRectMake(6, down ? 10 : -4, b.size.width - 12, b.size.height - 6);
    CCWithoutAnimation(^{
        self->_glow.frame = glow;
        self->_bg.frame = b;
        self->_shine.frame = b;
    });
    CCXformRelayout(self);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)resetCursorRects {
    if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)setHovered:(BOOL)hovered {
    if (_hovered == hovered) return;
    _hovered = hovered && self.enabled;
    if (self.isGradient && self.enabled) {
        CCAnimateNumber(_shine, @"opacity", _hovered ? 0.12 : 0, _hovered ? 150 : 200, CCEaseLinear, 0);
        if (![_glow animationForKey:@"pulse"]) CCAnimateNumber(_glow, @"opacity", _hovered ? 0.7 : 0.45, _hovered ? 200 : 250, CCEaseLinear, 0);
        CCTransformView(self, _hovered ? CCXformMake(1.03, 0, 0) : CCXformIdentity(), _hovered ? 180 : 250, _hovered ? CCEaseCubicOut : CCEaseLinear);
    }
    [self applyTheme];
}

- (void)mouseEntered:(NSEvent *)event { [self setHovered:YES]; }
- (void)mouseExited:(NSEvent *)event { [self setHovered:NO]; }

- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) return;
    _pressed = YES;
    if (self.isGradient) CCTransformView(self, CCXformMake(0.97, 0, 0), 80, CCEaseLinear);
    [self applyTheme];
}

- (void)mouseUp:(NSEvent *)event {
    if (!_pressed) return;
    _pressed = NO;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL inside = NSPointInRect(p, self.bounds);
    if (self.isGradient) CCTransformView(self, inside ? CCXformMake(1.03, 0, 0) : CCXformIdentity(), 200, CCEaseBack(0.6));
    [self applyTheme];
    if (inside && self.enabled && self.onClick) self.onClick();
}

- (BOOL)accessibilityPerformPress {
    if (self.enabled && self.onClick) self.onClick();
    return YES;
}

@end

@implementation CCChip {
    NSTrackingArea *_tracking;
    BOOL _hovered;
    CCBox *_box;
    CCLabel *_label;
}

+ (instancetype)chipWithTitle:(NSString *)title {
    CCChip *chip = [[self alloc] initWithFrame:NSZeroRect];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.wantsLayer = YES;
    chip->_box = [[CCBox alloc] initWithFrame:NSZeroRect];
    chip->_box.radius = 999;
    [chip addSubview:chip->_box];
    CCPin(chip->_box, chip, NSEdgeInsetsMake(0, 0, 0, 0));
    chip->_label = [CCLabel text:title size:13 weight:NSFontWeightMedium role:CCRoleMuted];
    [chip->_label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [chip addSubview:chip->_label];
    CCPin(chip->_label, chip, NSEdgeInsetsMake(7, 13, 7, 13));
    chip.title = title;
    chip.accessibilityElement = YES;
    chip.accessibilityRole = NSAccessibilityRadioButtonRole;
    [chip applyTheme];
    return chip;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.stringValue = title;
    self.accessibilityLabel = title;
}

- (void)setLocKey:(NSString *)locKey {
    _locKey = [locKey copy];
    self.title = L(locKey);
}

- (void)applyLanguage {
    if (self.locKey) self.title = L(self.locKey);
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    self.accessibilityValue = @(checked);
    [self applyTheme];
}

- (void)applyTheme {
    BOOL checked = self.checked, hovered = _hovered;
    _box.fill = ^NSColor *{ return checked ? CCTheme.accentSoft : hovered ? CCTheme.hover : CCTheme.input; };
    _box.stroke = ^NSColor *{ return checked ? CCTheme.accent : CCTheme.inputBorder; };
    _label.role = checked || hovered ? CCRoleText : CCRoleMuted;
}

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
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.bounds) && self.onClick) self.onClick();
}
- (BOOL)accessibilityPerformPress {
    if (self.onClick) self.onClick();
    return YES;
}

@end

@implementation CCToggle {
    CALayer *_track, *_knob;
    CAGradientLayer *_onLayer;
    NSTrackingArea *_tracking;
    BOOL _hovered;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        _enabled = YES;
        CCSize(self, 46, 26);
        _track = [CALayer layer];
        _track.cornerRadius = 13;
        _track.borderWidth = 1;
        _onLayer = [CAGradientLayer layer];
        _onLayer.cornerRadius = 13;
        _onLayer.opacity = 0;
        _knob = [CALayer layer];
        _knob.bounds = CGRectMake(0, 0, 18, 18);
        _knob.cornerRadius = 9;
        [self.layer addSublayer:_track];
        [self.layer addSublayer:_onLayer];
        [self.layer addSublayer:_knob];
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityCheckBoxRole;
        [self applyTheme];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)layout {
    [super layout];
    CCWithoutAnimation(^{
        self->_track.frame = self.layer.bounds;
        self->_onLayer.frame = self.layer.bounds;
        self->_knob.position = CGPointMake(self.on ? 33 : 13, 13);
    });
    [self applyTheme];
}

- (void)applyTheme {
    BOOL down = CCLayerYDown(self.layer);
    CCWithoutAnimation(^{
        self->_track.backgroundColor = CCTheme.track.CGColor;
        self->_track.borderColor = self.on ? NSColor.clearColor.CGColor
                                   : (self->_hovered ? CCTheme.cardBorderHover : CCTheme.inputBorder).CGColor;
        self->_onLayer.colors = CCCGColors(CCTheme.accentGradient);
        self->_onLayer.locations = CCTheme.accentGradientLocations;
        self->_onLayer.startPoint = CGPointMake(0, down ? 0 : 1);
        self->_onLayer.endPoint = CGPointMake(1, down ? 1 : 0);
        self->_knob.backgroundColor = (self.on ? CCTheme.knob : CCTheme.textMuted).CGColor;
    });
    self.alphaValue = self.enabled ? 1 : 0.4;
}

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    self.accessibilityValue = @(on);
    double ms = animated ? 1 : 0;
    CCAnimateNumber(_onLayer, @"opacity", on ? 1 : 0, 180 * ms, CCEaseLinear, 0);
    CCAnimateNumber(_knob, @"position.x", on ? 33 : 13, 280 * ms, CCEaseBack(0.4), 0);
    [self applyTheme];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self applyTheme];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)resetCursorRects {
    if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self applyTheme]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self applyTheme]; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (!self.enabled || !NSPointInRect(p, self.bounds)) return;
    [self toggle];
}
- (void)toggle {
    [self setOn:!self.on animated:YES];
    if (self.onChange) self.onChange(self.on);
}
- (BOOL)accessibilityPerformPress {
    if (self.enabled) [self toggle];
    return YES;
}

@end

@implementation CCCheck {
    CALayer *_box;
    CAGradientLayer *_fill;
    CAShapeLayer *_mark;
    NSTrackingArea *_tracking;
    BOOL _hovered;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        _enabled = YES;
        CCSize(self, 22, 22);
        _box = [CALayer layer];
        _box.cornerRadius = 7;
        _box.borderWidth = 1.5;
        _fill = [CAGradientLayer layer];
        _fill.cornerRadius = 7;
        _fill.opacity = 0;
        _mark = [CAShapeLayer layer];
        _mark.bounds = CGRectMake(0, 0, 22, 22);
        _mark.fillColor = NSColor.clearColor.CGColor;
        _mark.strokeColor = NSColor.whiteColor.CGColor;
        _mark.lineWidth = 2;
        _mark.lineCap = kCALineCapRound;
        _mark.lineJoin = kCALineJoinRound;
        _mark.opacity = 0;
        _mark.transform = CATransform3DMakeScale(0.4, 0.4, 1);
        [self.layer addSublayer:_box];
        [self.layer addSublayer:_fill];
        [self.layer addSublayer:_mark];
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityCheckBoxRole;
        [self applyTheme];
    }
    return self;
}

- (void)layout {
    [super layout];
    BOOL down = CCLayerYDown(self.layer);
    CGMutablePathRef path = CGPathCreateMutable();
    CGFloat (^Y)(CGFloat) = ^CGFloat(CGFloat y) { return down ? y : 22 - y; };
    CGPathMoveToPoint(path, NULL, 6.5, Y(11.5));
    CGPathAddLineToPoint(path, NULL, 9.5, Y(14.5));
    CGPathAddLineToPoint(path, NULL, 15.5, Y(8));
    CCWithoutAnimation(^{
        self->_box.frame = self.layer.bounds;
        self->_fill.frame = self.layer.bounds;
        self->_mark.position = CGPointMake(11, 11);
        self->_mark.path = path;
    });
    CGPathRelease(path);
    [self applyTheme];
}

- (void)applyTheme {
    BOOL down = CCLayerYDown(self.layer);
    CCWithoutAnimation(^{
        self->_box.backgroundColor = CCTheme.input.CGColor;
        self->_box.borderColor = (self->_hovered && self.enabled ? CCTheme.accent : CCTheme.inputBorder).CGColor;
        self->_fill.colors = CCCGColors(CCTheme.accentGradient);
        self->_fill.locations = CCTheme.accentGradientLocations;
        self->_fill.startPoint = CGPointMake(0, down ? 0 : 1);
        self->_fill.endPoint = CGPointMake(1, down ? 1 : 0);
    });
    self.alphaValue = self.enabled ? 1 : 0.4;
}

- (void)setChecked:(BOOL)checked { [self setChecked:checked animated:NO]; }

- (void)setChecked:(BOOL)checked animated:(BOOL)animated {
    _checked = checked;
    self.accessibilityValue = @(checked);
    double k = animated ? 1 : 0;
    CCAnimateNumber(_fill, @"opacity", checked ? 1 : 0, 150 * k, CCEaseLinear, 0);
    CCAnimateNumber(_mark, @"opacity", checked ? 1 : 0, (checked ? 120 : 100) * k, CCEaseLinear, 0);
    CCAnimateNumber(_mark, @"transform.scale", checked ? 1 : 0.4, (checked ? 300 : 150) * k, checked ? CCEaseBack(0.8) : CCEaseLinear, 0);
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self applyTheme];
    [self.window invalidateCursorRectsForView:self];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)resetCursorRects {
    if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self applyTheme]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self applyTheme]; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (!self.enabled || !NSPointInRect(p, self.bounds)) return;
    [self toggle];
}
- (void)toggle {
    [self setChecked:!self.checked animated:YES];
    if (self.onChange) self.onChange(self.checked);
}
- (BOOL)accessibilityPerformPress {
    if (self.enabled) [self toggle];
    return YES;
}

@end

// ───────────── inputs ─────────────

@interface CCFocusField : NSTextField
@property (nonatomic, copy) void (^onFocus)(BOOL focused);
@end

@implementation CCFocusField
- (BOOL)becomeFirstResponder {
    BOOL ok = [super becomeFirstResponder];
    if (ok && self.onFocus) self.onFocus(YES);
    return ok;
}
@end

@implementation CCSearchField {
    CCFocusField *_field;
    CCIcon *_icon;
    NSTrackingArea *_tracking;
    BOOL _hovered, _focused;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.radius = 12;
        CCSize(self, 0, 40);
        _icon = [CCIcon symbol:@"magnifyingglass" size:14 weight:NSFontWeightRegular role:CCRoleMuted];
        _field = CCAuto([CCFocusField new]);
        _field.bezeled = NO;
        _field.bordered = NO;
        _field.drawsBackground = NO;
        _field.focusRingType = NSFocusRingTypeNone;
        _field.font = CCFont(14, NSFontWeightRegular);
        _field.delegate = self;
        _field.cell.scrollable = YES;
        _field.usesSingleLineMode = YES;
        __weak CCSearchField *weakSelf = self;
        _field.onFocus = ^(BOOL focused) {
            CCSearchField *s = weakSelf;
            if (!s) return;
            s->_focused = focused;
            [s applyTheme];
        };
        [self addSubview:_icon];
        [self addSubview:_field];
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:10],
            [_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_field.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        [self applyTheme];
    }
    return self;
}

- (NSString *)text { return _field.stringValue; }

- (void)setPlaceholderKey:(NSString *)placeholderKey {
    _placeholderKey = [placeholderKey copy];
    [self applyTheme];
}

- (void)applyLanguage { [self applyTheme]; }

- (void)applyTheme {
    BOOL focused = _focused, hovered = _hovered;
    self.fill = ^NSColor *{ return CCTheme.input; };
    self.stroke = ^NSColor *{ return focused ? CCTheme.accent : hovered ? CCTheme.cardBorderHover : CCTheme.inputBorder; };
    _field.textColor = CCTheme.text;
    if (self.placeholderKey)
        _field.placeholderAttributedString = [[NSAttributedString alloc] initWithString:L(self.placeholderKey)
            attributes:@{ NSForegroundColorAttributeName: CCTheme.textFaint, NSFontAttributeName: CCFont(14, NSFontWeightRegular) }];
    [_icon applyTheme];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (self.onChange) self.onChange(_field.stringValue);
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    _focused = NO;
    [self applyTheme];
}

- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:_field]; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self applyTheme]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self applyTheme]; }

@end

@implementation CCPopupField {
    CCLabel *_label;
    CCIcon *_chevron;
    NSTrackingArea *_tracking;
    BOOL _hovered, _open;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.radius = 12;
        CCSize(self, 0, 40);
        [self.widthAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
        NSLayoutConstraint *preferred = [self.widthAnchor constraintEqualToConstant:240];
        preferred.priority = NSLayoutPriorityDefaultHigh;
        preferred.active = YES;
        _label = [CCLabel text:@"" size:14 weight:NSFontWeightRegular role:CCRoleText];
        _chevron = [CCIcon symbol:@"chevron.down" size:11 weight:NSFontWeightMedium role:CCRoleMuted];
        [self addSubview:_label];
        [self addSubview:_chevron];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_label.trailingAnchor constraintLessThanOrEqualToAnchor:_chevron.leadingAnchor constant:-12],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityPopUpButtonRole;
        [self applyTheme];
    }
    return self;
}

- (void)setItems:(NSArray<NSString *> *)items {
    _items = [items copy];
    [self refresh];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self refresh];
}

- (void)refresh {
    _label.stringValue = self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.items.count ? self.items[self.selectedIndex] : @"";
    self.accessibilityValue = _label.stringValue;
}

- (void)applyTheme {
    BOOL accent = _open, hovered = _hovered;
    self.fill = ^NSColor *{ return CCTheme.input; };
    self.stroke = ^NSColor *{ return accent ? CCTheme.accent : hovered ? CCTheme.cardBorderHover : CCTheme.inputBorder; };
}

- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }

- (void)mouseDown:(NSEvent *)event { [self openMenu]; }

- (BOOL)accessibilityPerformPress {
    [self openMenu];
    return YES;
}

- (void)openMenu {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    for (NSUInteger i = 0; i < self.items.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:self.items[i] action:@selector(pick:) keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
        item.state = (NSInteger)i == self.selectedIndex ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    menu.minimumWidth = NSWidth(self.bounds);
    _open = YES;
    [self applyTheme];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(self.bounds) + 6) inView:self];
    _open = NO;
    [self applyTheme];
}

- (void)pick:(NSMenuItem *)item {
    self.selectedIndex = item.tag;
    if (self.onSelect) self.onSelect(item.tag);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self applyTheme]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self applyTheme]; }

@end

// ───────────── data visuals ─────────────

@implementation CCSmoothBar {
    CALayer *_track;
    CAGradientLayer *_fill;
    double _shown;
    BOOL _initialized;
    CCTween *_tween;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _duration = 800;
        _trackColor = ^NSColor *{ return CCTheme.track; };
        _track = [CALayer layer];
        _fill = [CAGradientLayer layer];
        [self.layer addSublayer:_track];
        [self.layer addSublayer:_fill];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setFillColor:(CCColorBlock)fillColor { _fillColor = [fillColor copy]; [self applyTheme]; }
- (void)setFillGradient:(NSArray<NSColor *> *(^)(void))fillGradient { _fillGradient = [fillGradient copy]; [self applyTheme]; }
- (void)setTrackColor:(CCColorBlock)trackColor { _trackColor = [trackColor copy]; [self applyTheme]; }

- (void)applyTheme {
    BOOL down = CCLayerYDown(self.layer);
    CCWithoutAnimation(^{
        self->_track.backgroundColor = self.trackColor().CGColor;
        if (self.fillGradient) {
            NSArray *colors = self.fillGradient();
            self->_fill.colors = CCCGColors(colors);
            self->_fill.locations = colors.count == 3 ? CCTheme.accentGradientLocations : nil;
        } else {
            NSColor *c = self.fillColor ? self.fillColor() : CCTheme.accent;
            self->_fill.colors = CCCGColors(@[ c, c ]);
            self->_fill.locations = nil;
        }
        // The XAML gradient runs corner to corner; on a thin bar that reads as left to right.
        self->_fill.startPoint = CGPointMake(0, down ? 0 : 1);
        self->_fill.endPoint = CGPointMake(1, down ? 1 : 0);
    });
}

- (void)setValue:(double)value { [self setValue:value animated:YES]; }

- (void)setValue:(double)value animated:(BOOL)animated {
    _value = MAX(0, MIN(1, isnan(value) ? 0 : value));
    BOOL first = !_initialized;
    _initialized = YES;
    [_tween stop];
    if (first || !animated || !self.window || !CCMotionEnabled()) {
        _shown = _value;
        [self needsLayout];
        self.needsLayout = YES;
        return;
    }
    __weak CCSmoothBar *weakSelf = self;
    _tween = [CCTween from:_shown to:_value duration:self.duration delay:0 ease:CCEaseOutStrong update:^(double v) {
        CCSmoothBar *s = weakSelf;
        if (!s) return;
        s->_shown = v;
        [s layoutFill];
    } completion:nil];
}

- (void)layoutFill {
    NSRect b = self.layer.bounds;
    CGFloat h = b.size.height, w = b.size.width;
    double v = MAX(0, MIN(1, _shown));
    CCWithoutAnimation(^{
        self->_track.frame = b;
        self->_track.cornerRadius = h / 2;
        self->_fill.hidden = v <= 0;
        self->_fill.frame = CGRectMake(0, 0, MAX(h, v * w), h);
        self->_fill.cornerRadius = h / 2;
    });
}

- (void)layout {
    [super layout];
    [self layoutFill];
    [self applyTheme];
}

@end

@implementation CCSegmentBar {
    NSMutableArray<NSValue *> *_bands;
    NSMutableArray<NSNumber *> *_bandIndexes;
    NSArray<NSNumber *> *_from, *_to;
    NSArray<NSColor *> *_colors;
    double _progress;
    CCTween *_tween;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _progress = 1;
        _to = @[];
        _colors = @[];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)applyTheme { self.needsDisplay = YES; }

static double EaseQuint(double t) { return 1 - pow(1 - t, 5); }

- (NSArray<NSNumber *> *)currentWidths {
    double eased = EaseQuint(MAX(0, MIN(1, _progress)));
    NSMutableArray *widths = [NSMutableArray array];
    for (NSUInteger i = 0; i < _to.count; i++) {
        double from = i < _from.count ? _from[i].doubleValue : 0;
        [widths addObject:@(MAX(0, from + (_to[i].doubleValue - from) * eased))];
    }
    return widths;
}

- (void)setWeights:(NSArray<NSNumber *> *)weights colors:(NSArray<NSColor *> *)colors {
    if ([weights isEqualToArray:_to] && [colors isEqualToArray:_colors]) return;
    _from = [self currentWidths];
    _to = [weights copy];
    _colors = [colors copy];
    [_tween stop];
    if (!self.window || !CCMotionEnabled()) {
        _progress = 1;
        self.needsDisplay = YES;
        return;
    }
    __weak CCSegmentBar *weakSelf = self;
    _tween = [CCTween from:0 to:1 duration:900 delay:0 ease:CCEaseLinear update:^(double v) {
        CCSegmentBar *s = weakSelf;
        if (!s) return;
        s->_progress = v;
        s.needsDisplay = YES;
    } completion:nil];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect b = self.bounds;
    CGFloat w = NSWidth(b), h = NSHeight(b), radius = h / 2, gap = 3;
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:b xRadius:radius yRadius:radius];
    [CCTheme.track setFill];
    [track fill];

    NSArray<NSNumber *> *widths = [self currentWidths];
    double total = 0;
    for (NSNumber *n in widths) total += n.doubleValue;
    _bands = [NSMutableArray array];
    _bandIndexes = [NSMutableArray array];
    if (total <= 0) return;
    // Against a capacity the bands keep their true share and the rest of the bar stays empty.
    double whole = self.capacity > 0 ? MAX(self.capacity, total) : total;
    NSInteger visible = 0;
    for (NSNumber *n in widths) visible += n.doubleValue / whole * w >= 1;
    double available = w - gap * MAX(0, visible - 1);
    if (available <= 0) return;

    [NSGraphicsContext saveGraphicsState];
    [track addClip];
    double x = 0;
    for (NSUInteger i = 0; i < widths.count; i++) {
        double segment = widths[i].doubleValue / whole * available;
        if (segment < 1) continue;
        [(i < _colors.count ? _colors[i] : NSColor.grayColor) setFill];
        NSRect band = NSMakeRect(x, 0, segment, h);
        [_bands addObject:[NSValue valueWithRect:band]];
        [_bandIndexes addObject:@(i)];
        if (self.roundedSegments) {
            CGFloat r = MIN(radius, segment / 2);
            [[NSBezierPath bezierPathWithRoundedRect:band xRadius:r yRadius:r] fill];
        } else {
            NSRectFill(band);
        }
        x += segment + gap;
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)resetCursorRects {
    if (self.onPick) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.onPick) {
        [super mouseDown:event];
        return;
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSUInteger i = 0; i < _bands.count; i++) {
        NSRect band = _bands[i].rectValue;
        // The gap between two bands belongs to the band on its left.
        if (p.x >= NSMinX(band) && p.x <= NSMaxX(band) + 3) {
            self.onPick(_bandIndexes[i].integerValue);
            return;
        }
    }
}

@end

static CGPathRef CreateArcPath(CGFloat diameter, CGFloat inset, double sweepDegrees, BOOL down) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGFloat r = diameter / 2 - inset;
    double sweep = sweepDegrees * M_PI / 180;
    // Starts at twelve o'clock and runs clockwise on screen.
    if (down) CGPathAddArc(path, NULL, diameter / 2, diameter / 2, r, -M_PI_2, -M_PI_2 + sweep, false);
    else CGPathAddArc(path, NULL, diameter / 2, diameter / 2, r, M_PI_2, M_PI_2 - sweep, true);
    return path;
}

@implementation CCRing {
    CAShapeLayer *_track;
    CALayer *_valueGroup, *_spinGroup;
    CAGradientLayer *_valueGradient, *_spinGradient;
    CAShapeLayer *_valueMask, *_spinMask;
    double _angle;
    BOOL _braking;
    NSInteger _brakeToken;
    double _brakeEnd;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        CCSize(self, 204, 204);
        _track = [CAShapeLayer layer];
        _track.fillColor = NSColor.clearColor.CGColor;
        _track.lineWidth = 14;

        _valueGroup = [CALayer layer];
        _valueGroup.shadowOffset = CGSizeZero;
        _valueGroup.shadowRadius = 14;
        _valueGroup.shadowOpacity = 0.55;
        _valueGradient = [CAGradientLayer layer];
        _valueMask = [CAShapeLayer layer];
        _valueMask.fillColor = NSColor.clearColor.CGColor;
        _valueMask.strokeColor = NSColor.blackColor.CGColor;
        _valueMask.lineWidth = 14;
        _valueMask.lineCap = kCALineCapRound;
        _valueMask.strokeEnd = 0;
        _valueGradient.mask = _valueMask;
        [_valueGroup addSublayer:_valueGradient];

        _spinGroup = [CALayer layer];
        _spinGroup.shadowOffset = CGSizeZero;
        _spinGroup.shadowRadius = 14;
        _spinGroup.shadowOpacity = 0.6;
        _spinGroup.opacity = 0;
        _spinGradient = [CAGradientLayer layer];
        _spinMask = [CAShapeLayer layer];
        _spinMask.fillColor = NSColor.clearColor.CGColor;
        _spinMask.strokeColor = NSColor.blackColor.CGColor;
        _spinMask.lineWidth = 14;
        _spinMask.lineCap = kCALineCapRound;
        _spinGradient.mask = _spinMask;
        [_spinGroup addSublayer:_spinGradient];

        [self.layer addSublayer:_track];
        [self.layer addSublayer:_valueGroup];
        [self.layer addSublayer:_spinGroup];
        [self applyTheme];
    }
    return self;
}

- (void)layout {
    [super layout];
    CGRect b = CGRectMake(0, 0, 204, 204);
    BOOL down = CCLayerYDown(self.layer);
    CGPathRef full = CreateArcPath(204, 7, 359.999, down);
    CGPathRef sweep = CreateArcPath(204, 7, 110, down);
    CCWithoutAnimation(^{
        for (CALayer *l in @[ self->_track, self->_valueGroup, self->_spinGroup, self->_valueGradient, self->_spinGradient,
                              self->_valueMask, self->_spinMask ])
            l.frame = b;
        self->_track.path = full;
        self->_valueMask.path = full;
        self->_spinMask.path = sweep;
    });
    CGPathRelease(full);
    CGPathRelease(sweep);
    [self applyTheme];
}

- (void)applyTheme {
    BOOL down = CCLayerYDown(self.layer);
    CCWithoutAnimation(^{
        self->_track.strokeColor = CCTheme.track.CGColor;
        for (CAGradientLayer *g in @[ self->_valueGradient, self->_spinGradient ]) {
            g.colors = CCCGColors(CCTheme.ringGradient);
            g.locations = @[ @0, @0.5, @1 ];
            g.startPoint = CGPointMake(0, down ? 0 : 1);
            g.endPoint = CGPointMake(1, down ? 1 : 0);
        }
        self->_valueGroup.shadowColor = CCTheme.accent.CGColor;
        self->_spinGroup.shadowColor = CCTheme.accent2.CGColor;
    });
}

// One arc does both jobs. A scan starts from a short dash that spins up and grows with what is found: its length is
// always the share of the whole disk found so far. When the scan ends it runs one last lap, braking to twelve o'clock
// while its length eases to the real share, and settles exactly in place. Speed and length never jump.
static const double kSpinDash = 0.012;
static const double kSpinGrowMs = 400;
static const double kSpinSpeed = 2 * M_PI / 1.1; // radians per second
static const double kSpinUpMs = 600;

- (double)currentRotation {
    return [[(_valueGroup.presentationLayer ?: _valueGroup) valueForKeyPath:@"transform.rotation.z"] doubleValue];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    // A scan started before the window appeared (--scan) begins spinning once there is something to see.
    if (self.window && _spinning && ![_valueGroup animationForKey:@"spin"]) {
        _spinning = NO;
        [self setSpinning:YES];
    }
}

- (void)showAngle:(BOOL)animated {
    BOOL motion = animated && self.window && CCMotionEnabled();
    CCAnimateNumber(_valueMask, @"strokeEnd", _angle / 360.0, motion ? 1100 : 0, CCEaseOutStrong, 0);
    CCAnimateNumber(_valueMask, @"opacity", _angle > 0.01 ? 1 : 0, motion ? 300 : 0, CCEaseLinear, _angle > 0.01 ? 0 : 900);
}

- (void)setAngle:(double)angle animated:(BOOL)animated {
    double previous = _angle;
    _angle = MAX(0, MIN(360, angle));
    if (_spinning) {
        if (fabs(previous - _angle) > 0.01) {
            BOOL motion = animated && self.window && CCMotionEnabled();
            CCAnimateNumber(_valueMask, @"strokeEnd", MAX(kSpinDash, _angle / 360.0), motion ? kSpinGrowMs : 0, CCEaseOut, 0);
        }
        return;
    }
    if (_braking) {
        // The result arrived during the last lap: keep easing towards it and still land with the brake.
        double remaining = MAX(0, _brakeEnd - CACurrentMediaTime()) * 1000;
        if (fabs(previous - _angle) > 0.01) CCAnimateNumber(_valueMask, @"strokeEnd", _angle / 360.0, remaining, CCEaseOut, 0);
        return;
    }
    [self showAngle:animated];
}

- (void)setSpinning:(BOOL)spinning {
    if (_spinning == spinning) return;
    _spinning = spinning;
    _brakeToken++;
    double direction = CCLayerYDown(self.layer) ? 1 : -1;
    BOOL motion = CCMotionEnabled() && self.window;

    double angle = [self currentRotation];
    [_valueGroup removeAnimationForKey:@"spin"];
    [_valueGroup removeAnimationForKey:@"spinUp"];
    [_valueGroup removeAnimationForKey:@"transform.rotation.z"];
    CCWithoutAnimation(^{ [self->_valueGroup setValue:@(angle) forKeyPath:@"transform.rotation.z"]; });

    if (spinning) {
        _braking = NO;
        CCAnimateNumber(_valueMask, @"opacity", 1, motion ? 200 : 0, CCEaseOut, 0);
        double length = MAX(kSpinDash, _angle / 360.0);
        if (!motion) {
            CCAnimateNumber(_valueMask, @"strokeEnd", length, 0, nil, 0);
            return;
        }
        // Down to what is found so far: nothing yet, so a short dash.
        CCAnimateNumber(_valueMask, @"strokeEnd", length, 200, CCEaseInOut, 0);

        // Spin up: a quadratic ease-in reaches full speed after covering half of what full speed would.
        double spinUp = kSpinSpeed * kSpinUpMs / 1000 / 2;
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @(angle + spinUp * direction);
        spin.toValue = @(angle + (spinUp + 2 * M_PI) * direction);
        spin.duration = 1.1;
        spin.repeatCount = HUGE_VALF;
        spin.beginTime = CACurrentMediaTime() + kSpinUpMs / 1000;
        [_valueGroup addAnimation:spin forKey:@"spin"];

        CAKeyframeAnimation *up = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
        NSMutableArray *values = [NSMutableArray array];
        for (int i = 0; i <= 36; i++) {
            double t = i / 36.0;
            [values addObject:@(angle + spinUp * t * t * direction)];
        }
        up.values = values;
        up.duration = kSpinUpMs / 1000;
        [_valueGroup addAnimation:up forKey:@"spinUp"];
        return;
    }

    // The last lap: brake to the next twelve o'clock at least half a turn ahead (a quadratic ease-out starts at
    // twice its average speed, so the duration follows from the distance and the speed stays continuous) while the
    // length eases from the spinner's to the real share.
    double turn = 2 * M_PI;
    double target = direction > 0 ? ceil((angle + M_PI) / turn) * turn : floor((angle - M_PI) / turn) * turn;
    double distance = fabs(target - angle);
    double brakeMs = motion ? distance / kSpinSpeed * 2 * 1000 : 0;
    CCEase quadOut = ^double(double t) { return 1 - (1 - t) * (1 - t); };
    CCAnimateNumber(_valueGroup, @"transform.rotation.z", target, brakeMs, quadOut, 0);
    CCAnimateNumber(_valueMask, @"strokeEnd", _angle / 360.0, brakeMs, CCEaseInOut, 0);
    _braking = YES;
    _brakeEnd = CACurrentMediaTime() + brakeMs / 1000;
    NSInteger token = _brakeToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(brakeMs / 1000 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self->_brakeToken) return;
        self->_braking = NO;
        CCWithoutAnimation(^{ [self->_valueGroup setValue:@0 forKeyPath:@"transform.rotation.z"]; });
        [self showAngle:YES];
    });
}

@end

@implementation CCSpinner {
    CAShapeLayer *_arc;
    CGFloat _diameter;
    double _sweep, _period;
}

- (instancetype)initWithDiameter:(CGFloat)diameter lineWidth:(CGFloat)lineWidth sweep:(double)degrees period:(double)seconds {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, diameter, diameter)])) {
        self.wantsLayer = YES;
        CCSize(self, diameter, diameter);
        _diameter = diameter;
        _sweep = degrees;
        _period = seconds;
        _arc = [CAShapeLayer layer];
        _arc.fillColor = NSColor.clearColor.CGColor;
        _arc.lineWidth = lineWidth;
        _arc.lineCap = kCALineCapRound;
        [self.layer addSublayer:_arc];
        [self applyTheme];
    }
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window || !CCMotionEnabled()) return;
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0;
    spin.toValue = @(2 * M_PI * (CCLayerYDown(self.layer) ? 1 : -1));
    spin.duration = _period;
    spin.repeatCount = HUGE_VALF;
    [_arc addAnimation:spin forKey:@"spin"];
}

- (void)layout {
    [super layout];
    CGPathRef path = CreateArcPath(_diameter, _arc.lineWidth / 2, _sweep, CCLayerYDown(self.layer));
    CCWithoutAnimation(^{
        self->_arc.frame = CGRectMake(0, 0, self->_diameter, self->_diameter);
        self->_arc.path = path;
    });
    CGPathRelease(path);
}

- (void)applyTheme { _arc.strokeColor = CCTheme.accent.CGColor; }

@end

@implementation CCFlowView {
    NSArray<NSView *> *_items;
    CGFloat _lastWidth;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _hSpacing = 20;
        _vSpacing = 6;
        _items = @[];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setItems:(NSArray<NSView *> *)items {
    for (NSView *v in _items) [v removeFromSuperview];
    _items = [items copy];
    for (NSView *v in items) {
        v.translatesAutoresizingMaskIntoConstraints = YES;
        [self addSubview:v];
    }
    [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (CGFloat)arrange:(BOOL)apply width:(CGFloat)width {
    CGFloat x = 0, y = 0, rowHeight = 0;
    for (NSView *v in _items) {
        if (v.hidden) continue;
        NSSize size = v.fittingSize;
        if (x > 0 && x + size.width > width) {
            x = 0;
            y += rowHeight + self.vSpacing;
            rowHeight = 0;
        }
        if (apply) v.frame = NSMakeRect(x, y, size.width, size.height);
        x += size.width + self.hSpacing;
        rowHeight = MAX(rowHeight, size.height);
    }
    return y + rowHeight;
}

- (void)itemsChanged {
    [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (NSSize)intrinsicContentSize {
    CGFloat width = NSWidth(self.bounds) > 0 ? NSWidth(self.bounds) : 10000;
    return NSMakeSize(NSViewNoIntrinsicMetric, [self arrange:NO width:width]);
}

- (void)layout {
    [super layout];
    [self arrange:YES width:NSWidth(self.bounds)];
    if (fabs(_lastWidth - NSWidth(self.bounds)) > 0.5) {
        _lastWidth = NSWidth(self.bounds);
        [self invalidateIntrinsicContentSize];
    }
}

@end

@implementation CCLogoView

- (BOOL)isFlipped { return YES; }
- (void)applyTheme { self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat s = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 64.0;
    NSAffineTransform *t = [NSAffineTransform transform];
    [t scaleBy:s];
    [NSGraphicsContext saveGraphicsState];
    [t concat];

    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 64, 64) xRadius:18 yRadius:18];
    NSArray *colors = CCTheme.accentGradient;
    CGFloat locations[] = { 0, 0.55, 1 };
    NSGradient *g = [[NSGradient alloc] initWithColors:colors atLocations:locations colorSpace:NSColorSpace.sRGBColorSpace];
    [g drawInBezierPath:tile angle:45];

    NSBezierPath *big = [NSBezierPath bezierPath];
    [big moveToPoint:NSMakePoint(30, 12)];
    [big curveToPoint:NSMakePoint(47, 29) controlPoint1:NSMakePoint(31.5, 23) controlPoint2:NSMakePoint(36, 27.5)];
    [big curveToPoint:NSMakePoint(30, 46) controlPoint1:NSMakePoint(36, 30.5) controlPoint2:NSMakePoint(31.5, 35)];
    [big curveToPoint:NSMakePoint(13, 29) controlPoint1:NSMakePoint(28.5, 35) controlPoint2:NSMakePoint(24, 30.5)];
    [big curveToPoint:NSMakePoint(30, 12) controlPoint1:NSMakePoint(24, 27.5) controlPoint2:NSMakePoint(28.5, 23)];
    [big closePath];
    [[NSColor colorWithWhite:1 alpha:0.98] setFill];
    [big fill];

    NSBezierPath *small = [NSBezierPath bezierPath];
    [small moveToPoint:NSMakePoint(45, 38)];
    [small curveToPoint:NSMakePoint(51, 44) controlPoint1:NSMakePoint(45.6, 42) controlPoint2:NSMakePoint(47.2, 43.6)];
    [small curveToPoint:NSMakePoint(45, 50) controlPoint1:NSMakePoint(47.2, 44.4) controlPoint2:NSMakePoint(45.6, 46)];
    [small curveToPoint:NSMakePoint(39, 44) controlPoint1:NSMakePoint(44.4, 46) controlPoint2:NSMakePoint(42.8, 44.4)];
    [small curveToPoint:NSMakePoint(45, 38) controlPoint1:NSMakePoint(42.8, 43.6) controlPoint2:NSMakePoint(44.4, 42)];
    [small closePath];
    [[NSColor colorWithWhite:1 alpha:0.9] setFill];
    [small fill];

    [NSGraphicsContext restoreGraphicsState];
}

@end

@implementation CCSettingRow {
    CALayer *_divider;
}

+ (instancetype)rowWithSymbol:(NSString *)symbol titleKey:(NSString *)titleKey descKey:(NSString *)descKey control:(NSView *)control {
    CCSettingRow *row = [[self alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.wantsLayer = YES;
    row.showsDivider = YES;
    CCIconTile *tile = [CCIconTile tileWithSymbol:symbol size:38 radius:11 iconSize:16];
    tile.fill = ^NSColor *{ return CCTheme.inset; };
    row->_titleLabel = titleKey ? [CCLabel key:titleKey size:14 weight:NSFontWeightSemibold role:CCRoleText]
                                : [CCLabel text:@"" size:14 weight:NSFontWeightSemibold role:CCRoleText];
    row->_descLabel = descKey ? [CCLabel key:descKey size:12.5 weight:NSFontWeightRegular role:CCRoleMuted]
                              : [CCLabel text:@"" size:12.5 weight:NSFontWeightRegular role:CCRoleMuted];
    row->_descLabel.wraps = YES;
    NSStackView *text = CCVStack(@[ row->_titleLabel, row->_descLabel ], 3);
    [row addSubview:tile];
    [row addSubview:text];
    NSMutableArray *constraints = [@[
        [tile.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [tile.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:16],
        [text.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [text.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:14],
        [row.bottomAnchor constraintGreaterThanOrEqualToAnchor:text.bottomAnchor constant:14],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:66],
        [row->_descLabel.leadingAnchor constraintEqualToAnchor:text.leadingAnchor],
        [text.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [row->_descLabel.trailingAnchor constraintEqualToAnchor:text.trailingAnchor],
    ] mutableCopy];
    if (control) {
        control.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:control];
        [constraints addObjectsFromArray:@[
            [control.leadingAnchor constraintGreaterThanOrEqualToAnchor:text.trailingAnchor constant:24],
            ^{
                // The text column takes whatever the control leaves, but never squeezes the control.
                NSLayoutConstraint *fill = [control.leadingAnchor constraintEqualToAnchor:text.trailingAnchor constant:24];
                fill.priority = 600;
                return fill;
            }(),
            [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
        [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        if ([control isKindOfClass:NSStackView.class])
            [(NSStackView *)control setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [row->_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:text.trailingAnchor].active = YES;
    } else {
        [constraints addObject:[text.trailingAnchor constraintEqualToAnchor:row.trailingAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    row->_divider = [CALayer layer];
    [row.layer addSublayer:row->_divider];
    [row applyTheme];
    return row;
}

- (BOOL)isFlipped { return YES; }

- (void)setShowsDivider:(BOOL)showsDivider {
    _showsDivider = showsDivider;
    _divider.hidden = !showsDivider;
}

- (void)applyTheme { _divider.backgroundColor = CCTheme.divider.CGColor; }

- (void)layout {
    [super layout];
    BOOL down = CCLayerYDown(self.layer);
    CCWithoutAnimation(^{
        self->_divider.frame = CGRectMake(0, down ? NSHeight(self.bounds) - 1 : 0, NSWidth(self.bounds), 1);
    });
}

@end
