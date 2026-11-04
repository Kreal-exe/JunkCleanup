// The controls of the Windows app's Themes/Styles.xaml and Controls/*.cs, drawn with Core Animation.
#import <Cocoa/Cocoa.h>
#import "CCCore.h"
#import "CCMotion.h"
#import "CCTheme.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSColor *_Nonnull (^CCColorBlock)(void);

/// Views that restyle themselves when the theme or the language changes.
@protocol CCLive <NSObject>
@optional
- (void)applyTheme;
- (void)applyLanguage;
@end

@interface NSView (CC)
- (void)cc_broadcastTheme;
- (void)cc_broadcastLanguage;
@end

/// translatesAutoresizingMaskIntoConstraints = NO.
__kindof NSView *CCAuto(__kindof NSView *view);
/// Whether y grows downwards inside this layer (an odd number of flipped layers on the way to the root).
BOOL CCLayerYDown(CALayer *layer);
void CCPin(NSView *view, NSView *container, NSEdgeInsets insets);
void CCSize(NSView *view, CGFloat width, CGFloat height);
NSStackView *CCHStack(NSArray<NSView *> *views, CGFloat spacing);
NSStackView *CCVStack(NSArray<NSView *> *views, CGFloat spacing);
/// A stretchable gap for stack views.
NSView *CCSpacer(void);

@interface CCFlippedView : NSView
@end

// ───────────── text & icons ─────────────

@interface CCLabel : NSTextField <CCLive>
+ (instancetype)text:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role;
+ (instancetype)key:(NSString *)locKey size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role;
@property (nonatomic) CCRole role;
@property (nonatomic, copy, nullable) CCColorBlock colorBlock;
@property (nonatomic, copy, nullable) NSString *locKey;
/// Wraps onto several lines (otherwise one line, truncated with an ellipsis).
@property (nonatomic) BOOL wraps;
@property (nonatomic) CGFloat lineHeight;
@end

typedef NS_ENUM(NSInteger, CCCounterPart) { CCCounterAll, CCCounterNumber, CCCounterUnit, CCCounterInteger };

/// Tweens between byte values like Controls/Counter.cs.
@interface CCCounter : CCLabel
@property (nonatomic) CCCounterPart part;
@property (nonatomic) double duration;
@property (nonatomic, readonly) long long bytes;
/// Called after each repaint, for containers that lay out by fitting size (the legend's flow).
@property (nonatomic, copy, nullable) void (^onRender)(void);
- (void)setBytes:(long long)bytes;
/// Re-renders the current value (after a language change).
- (void)render;
@end

@interface CCIcon : NSImageView <CCLive>
+ (instancetype)symbol:(NSString *)symbol size:(CGFloat)size weight:(NSFontWeight)weight role:(CCRole)role;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic) CCRole role;
@property (nonatomic, copy, nullable) CCColorBlock colorBlock;
@end

// ───────────── surfaces ─────────────

/// A rounded, layer-backed rectangle whose colours are re-resolved on theme changes.
@interface CCBox : NSView <CCLive>
@property (nonatomic, copy, nullable) CCColorBlock fill;
@property (nonatomic, copy, nullable) CCColorBlock stroke;
@property (nonatomic, copy, nullable) NSArray<NSColor *> *_Nonnull (^gradient)(void);
@property (nonatomic) CGFloat radius;
@property (nonatomic) CGFloat strokeWidth;
/// Pushes the colour blocks into the layer; subclasses with state-dependent colours override this.
- (void)applyBoxColors;
@end

/// The "Card" / "CardHover" styles: hover lifts by 4 pt and grows 1.2 %, icon tiles inside bounce.
@interface CCCard : CCBox
+ (instancetype)card;
@property (nonatomic) BOOL hoverable;
@property (nonatomic, copy, nullable) void (^onClick)(void);
@property (nonatomic, readonly) BOOL hovered;
/// The moving highlight laid over category cards while scanning.
@property (nonatomic) BOOL shimmering;
@end

@interface CCIconTile : CCBox
+ (instancetype)tileWithSymbol:(NSString *)symbol size:(CGFloat)size radius:(CGFloat)radius iconSize:(CGFloat)iconSize;
@property (nonatomic, readonly) CCIcon *icon;
/// Pops to 112 % while the card around it is hovered.
@property (nonatomic) BOOL bounces;
- (void)setBounced:(BOOL)bounced;
@end

@interface CCPill : CCBox
+ (instancetype)pillWithText:(NSString *)text symbol:(nullable NSString *)symbol color:(CCColorBlock)color soft:(CCColorBlock)soft;
@property (nonatomic, readonly) CCLabel *label;
@end

// ───────────── buttons ─────────────

typedef NS_ENUM(NSInteger, CCButtonStyle) { CCButtonPrimary, CCButtonDanger, CCButtonGhost, CCButtonSubtle, CCButtonIcon, CCButtonSuccess };

@interface CCButton : NSView <CCLive>
+ (instancetype)buttonWithStyle:(CCButtonStyle)style title:(nullable NSString *)title symbol:(nullable NSString *)symbol;
@property (nonatomic) CCButtonStyle style;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *locKey;
@property (nonatomic, copy, nullable) NSString *symbol;
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSEdgeInsets padding;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) CGFloat symbolSize;
/// The breathing glow of the Clean button (Controls/Pulse.cs).
@property (nonatomic) BOOL pulsing;
@property (nonatomic, copy, nullable) void (^onClick)(void);
@property (nonatomic, readonly) CCIcon *iconView;
/// Overrides the icon colour (the amber shield of "Grant Full Disk Access").
@property (nonatomic, copy, nullable) CCColorBlock iconColor;
@end

@interface CCChip : NSView <CCLive>
+ (instancetype)chipWithTitle:(NSString *)title;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *locKey;
@property (nonatomic) BOOL checked;
@property (nonatomic, copy, nullable) void (^onClick)(void);
@end

@interface CCToggle : NSView <CCLive>
@property (nonatomic) BOOL on;
@property (nonatomic) BOOL enabled;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@property (nonatomic, copy, nullable) void (^onChange)(BOOL on);
@end

@interface CCCheck : NSView <CCLive>
@property (nonatomic) BOOL checked;
@property (nonatomic) BOOL enabled;
- (void)setChecked:(BOOL)checked animated:(BOOL)animated;
@property (nonatomic, copy, nullable) void (^onChange)(BOOL checked);
@end

@interface CCSearchField : CCBox <NSTextFieldDelegate>
@property (nonatomic, copy, nullable) NSString *placeholderKey;
@property (nonatomic, readonly) NSString *text;
@property (nonatomic, copy, nullable) void (^onChange)(NSString *text);
@end

@interface CCPopupField : CCBox
@property (nonatomic, copy) NSArray<NSString *> *items;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index);
@end

// ───────────── data visuals ─────────────

/// A rounded 0…1 bar whose fill eases to its value (Controls/SmoothBar.cs).
@interface CCSmoothBar : NSView <CCLive>
@property (nonatomic) double value;
@property (nonatomic) double duration;
@property (nonatomic, copy, nullable) CCColorBlock fillColor;
@property (nonatomic, copy, nullable) NSArray<NSColor *> *_Nonnull (^fillGradient)(void);
@property (nonatomic, copy) CCColorBlock trackColor;
- (void)setValue:(double)value animated:(BOOL)animated;
@end

/// A stacked proportional bar that tweens from the old layout to the new one (Controls/SegmentBar.cs).
@interface CCSegmentBar : NSView <CCLive>
/// Weights and colours, in order.
- (void)setWeights:(NSArray<NSNumber *> *)weights colors:(NSArray<NSColor *> *)colors;
/// The whole the weights are a share of (a disk's size); what they leave is empty track. 0 fills the bar.
@property (nonatomic) double capacity;
/// Each band is its own rounded pill (the Disk page) instead of one clipped strip.
@property (nonatomic) BOOL roundedSegments;
/// Clicking a band answers with its index in the weights.
@property (nonatomic, copy, nullable) void (^onPick)(NSInteger index);
@end

/// The reclaimable-space ring: a gradient arc with a glow, or a spinning arc while scanning.
@interface CCRing : NSView <CCLive>
@property (nonatomic) BOOL spinning;
/// 0…360.
- (void)setAngle:(double)angle animated:(BOOL)animated;
@end

/// A small spinning arc (the Cleaning… tile).
@interface CCSpinner : NSView <CCLive>
- (instancetype)initWithDiameter:(CGFloat)diameter lineWidth:(CGFloat)lineWidth sweep:(double)degrees period:(double)seconds;
@end

/// Lays its subviews out left to right and wraps them like WPF's WrapPanel.
@interface CCFlowView : NSView
@property (nonatomic) CGFloat hSpacing;
@property (nonatomic) CGFloat vSpacing;
- (void)setItems:(NSArray<NSView *> *)items;
/// An item's content changed size; lay the row out again.
- (void)itemsChanged;
@end

/// The app logo of Views/Logo.xaml: a gradient tile with two sparkles.
@interface CCLogoView : NSView <CCLive>
@end

/// A settings row: icon tile, title, description, control on the right, divider below.
@interface CCSettingRow : NSView <CCLive>
+ (instancetype)rowWithSymbol:(NSString *)symbol titleKey:(nullable NSString *)titleKey descKey:(nullable NSString *)descKey control:(nullable NSView *)control;
@property (nonatomic, readonly) CCLabel *titleLabel;
@property (nonatomic, readonly) CCLabel *descLabel;
@property (nonatomic) BOOL showsDivider;
@end

NS_ASSUME_NONNULL_END
