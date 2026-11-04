// JunkCleanup for macOS: the app delegate, the menu bar and the command line (App.xaml.cs).
//
//   --scan             start scanning immediately
//   --page <name>      open on dashboard, targets, disk, settings or about; with --capture, shoot only that page
//   --theme <mode>     dark, light or system for this run
//   --lang <code>      interface language for this run
//   --capture <dir>    scan, save a PNG of every page into <dir>, quit
//   --drive <disk>     map this disk (a name or a mount point) on the Disk page
//   --tour             the README animation's moves, timed, then quit; nothing is cleaned
//   --capture-clean    with --capture: also run the clean, which DELETES the selected caches for good, and shoot it
#import <Cocoa/Cocoa.h>
#import "CCControls.h"
#import "CCDiskPage.h"
#import "CCModel.h"
#import "CCWindow.h"

@interface CCAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation CCAppDelegate {
    CCWindowController *_window;
}

static NSString *Argument(NSString *name) {
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger i = [args indexOfObject:name];
    return i != NSNotFound && i + 1 < args.count ? args[i + 1] : nil;
}

static BOOL Flag(NSString *name) { return [NSProcessInfo.processInfo.arguments containsObject:name]; }

static NSMenuItem *Item(NSString *key, SEL action, NSString *keyEquivalent) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:L(key) action:action keyEquivalent:keyEquivalent];
    item.representedObject = key;
    return item;
}

- (void)buildMenu {
    NSMenu *bar = [NSMenu new];

    NSMenu *app = [NSMenu new];
    [app addItem:Item(@"menu.about", @selector(showAbout:), @"")];
    [app addItem:NSMenuItem.separatorItem];
    [app addItem:Item(@"menu.settings", @selector(showSettings:), @",")];
    [app addItem:NSMenuItem.separatorItem];
    [app addItem:Item(@"menu.hide", @selector(hide:), @"h")];
    NSMenuItem *hideOthers = Item(@"menu.hideOthers", @selector(hideOtherApplications:), @"h");
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [app addItem:hideOthers];
    [app addItem:Item(@"menu.showAll", @selector(unhideAllApplications:), @"")];
    [app addItem:NSMenuItem.separatorItem];
    [app addItem:Item(@"menu.quit", @selector(terminate:), @"q")];
    NSMenuItem *appItem = [NSMenuItem new];
    appItem.submenu = app;
    [bar addItem:appItem];

    NSMenu *edit = [[NSMenu alloc] initWithTitle:L(@"menu.edit")];
    [edit addItem:Item(@"menu.undo", @selector(undo:), @"z")];
    NSMenuItem *redo = Item(@"menu.redo", @selector(redo:), @"z");
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [edit addItem:redo];
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItem:Item(@"menu.cut", @selector(cut:), @"x")];
    [edit addItem:Item(@"menu.copy", @selector(copy:), @"c")];
    [edit addItem:Item(@"menu.paste", @selector(paste:), @"v")];
    [edit addItem:Item(@"menu.selectAll", @selector(selectAll:), @"a")];
    NSMenuItem *editItem = [NSMenuItem new];
    editItem.submenu = edit;
    editItem.representedObject = @"menu.edit";
    [bar addItem:editItem];

    NSMenu *view = [[NSMenu alloc] initWithTitle:L(@"menu.view")];
    NSArray *pages = @[ @"nav.dashboard", @"nav.targets", @"nav.disk", @"nav.settings", @"nav.about" ];
    for (NSUInteger i = 0; i < pages.count; i++) {
        NSMenuItem *item = Item(pages[i], @selector(showPageFromMenu:), [NSString stringWithFormat:@"%lu", (unsigned long)i + 1]);
        item.tag = (NSInteger)i;
        [view addItem:item];
    }
    [view addItem:NSMenuItem.separatorItem];
    [view addItem:Item(@"menu.scan", @selector(toggleScan:), @"r")];
    NSMenuItem *viewItem = [NSMenuItem new];
    viewItem.submenu = view;
    viewItem.representedObject = @"menu.view";
    [bar addItem:viewItem];

    NSMenu *window = [[NSMenu alloc] initWithTitle:L(@"menu.window")];
    [window addItem:Item(@"menu.minimize", @selector(performMiniaturize:), @"m")];
    [window addItem:Item(@"menu.zoom", @selector(performZoom:), @"")];
    [window addItem:Item(@"menu.close", @selector(performClose:), @"w")];
    NSMenuItem *windowItem = [NSMenuItem new];
    windowItem.submenu = window;
    windowItem.representedObject = @"menu.window";
    [bar addItem:windowItem];
    NSApp.windowsMenu = window;

    NSApp.mainMenu = bar;
}

- (void)relabel:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.representedObject isKindOfClass:NSString.class]) {
            item.title = L(item.representedObject);
            item.submenu.title = item.title;
        }
        if (item.submenu) [self relabel:item.submenu];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    CCModel *model = CCModel.shared;
    CCSettings *settings = model.settings;
    [CCLocalization.shared setLanguage:Argument(@"--lang") ?: settings.language];
    CCSetMotionEnabled(settings.animations);
    [CCTheme applyMode:Argument(@"--theme") ?: settings.theme];

    NSString *page = Argument(@"--page").lowercaseString;
    NSArray *pages = @[ @"dashboard", @"targets", @"disk", @"settings", @"about" ];
    if (page && [pages containsObject:page]) model.page = (CCPage)[pages indexOfObject:page];

    if (Argument(@"--drive")) [CCDiskModel.shared preselectVolume:Argument(@"--drive")];

    [self buildMenu];
    [NSNotificationCenter.defaultCenter addObserverForName:CCLanguageDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { [self relabel:NSApp.mainMenu]; }];

    _window = [CCWindowController new];
    [_window showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [model refreshInsights];

    NSString *capture = Argument(@"--capture");
    if (capture) [_window captureInto:capture.stringByStandardizingPath];
    else if (Flag(@"--tour")) [_window runTour];
    else {
        if (Flag(@"--scan") || settings.scanOnStartup) [model startScan];
        // One switch instead of a macOS question per folder; nothing protected is opened until it is on.
        [model askForFullDiskAccessDeclined:nil];
    }
}

/// Back from System Settings with the access granted: everything that was closed can be measured now.
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    CCModel *model = CCModel.shared;
    BOOL before = model.hasFullDiskAccess;
    [model refreshAccess];
    if (!before && model.hasFullDiskAccess) [model startScan];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)showAbout:(id)sender { CCModel.shared.page = CCPageAbout; }
- (void)showSettings:(id)sender { CCModel.shared.page = CCPageSettings; }
- (void)showPageFromMenu:(NSMenuItem *)sender { CCModel.shared.page = (CCPage)sender.tag; }
- (void)toggleScan:(id)sender { [CCModel.shared toggleScan]; }

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        CCAppDelegate *delegate = [CCAppDelegate new];
        app.delegate = delegate;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        [app run];
    }
    return 0;
}
