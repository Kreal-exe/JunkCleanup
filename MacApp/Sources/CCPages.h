// The pages of the Windows app's Views/*.xaml, and the overlays laid over them.
#import <Cocoa/Cocoa.h>
#import "CCControls.h"
#import "CCModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface CCPageView : CCFlippedView <CCLive>
/// Pulls everything it shows from CCModel.
- (void)refresh;
/// The once-only entrance animations (Entrance.Delay / Entrance.Stagger).
- (void)playEntrance;
@property (nonatomic) BOOL entrancePlayed;
@end

@interface CCDashboardPage : CCPageView
@end

@interface CCTargetsPage : CCPageView
@end

@interface CCSettingsPage : CCPageView
/// Window-level services the page needs.
@property (nonatomic, copy, nullable) void (^applyAppearance)(void);
@property (nonatomic, copy, nullable) void (^alert)(NSString *title, NSString *body);
@end

@interface CCAboutPage : CCPageView
@end

/// Reveals its content by animating height and opacity (Controls/Collapsible.cs).
@interface CCCollapsible : NSView
- (instancetype)initWithContent:(NSView *)content;
@property (nonatomic, strong) NSView *content;
@property (nonatomic) BOOL open;
- (void)setOpen:(BOOL)open animated:(BOOL)animated;
/// The content changed size; follow it (unless a tween is running).
- (void)contentChanged;
@end

/// A scroll view with a flipped document whose width follows the clip view.
@interface CCScrollPage : NSScrollView
@property (nonatomic, readonly) CCFlippedView *document;
@end

@interface CCCleanOverlay : CCFlippedView <CCLive>
- (void)show;
- (void)hide;
- (void)refresh;
- (void)celebrate;
@end

@interface CCConfirmDialog : CCFlippedView <CCLive>
- (void)showTitle:(NSString *)title body:(NSString *)body ok:(NSString *)okText danger:(BOOL)danger answer:(void (^)(BOOL ok))answer;
@property (nonatomic, readonly) BOOL isOpen;
- (void)closeWith:(BOOL)result;
@end

/// A target's entries, largest first, each removable or revealable on its own.
@interface CCDetailsSheet : CCFlippedView <CCLive>
- (void)show;
- (void)hide;
@property (nonatomic, readonly) BOOL isOpen;
@end

@interface CCToast : CCBox
- (void)showSymbol:(NSString *)symbol text:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
