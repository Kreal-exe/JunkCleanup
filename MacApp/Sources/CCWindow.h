// The main window of Views/MainWindow.xaml: ambient background, title bar, sidebar, page host, overlays.
#import <Cocoa/Cocoa.h>
#import "CCModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface CCWindowController : NSWindowController <NSWindowDelegate>
- (instancetype)init;
- (void)showPage:(CCPage)page;
- (void)applyAppearance;
/// Writes PNGs of every page into a folder, then quits (README screenshots).
/// --tour: scan, Disk page, a band, another disk, at set moments for recording the README animation (each moment goes to
/// stdout as "tour <name> <unix seconds>"), then quit. Nothing is cleaned or removed.
- (void)runTour;
- (void)captureInto:(NSString *)folder;
@end

NS_ASSUME_NONNULL_END
