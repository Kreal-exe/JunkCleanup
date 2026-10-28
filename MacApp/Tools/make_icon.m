// Draws the 1024×1024 app icon: the logo of Views/Logo.xaml (gradient tile, two sparkles) on Apple's icon grid.
// Resources/AppIcon.icns is made from it by hand, only when the icon changes:
//   clang -fobjc-arc -framework Cocoa MacApp/Tools/make_icon.m -o /tmp/make-icon && /tmp/make-icon /tmp/icon.png
//   mkdir /tmp/AppIcon.iconset; for s in 16 32 128 256 512; do sips -z $s $s /tmp/icon.png --out /tmp/AppIcon.iconset/icon_${s}x$s.png;
//     sips -z $((s*2)) $((s*2)) /tmp/icon.png --out /tmp/AppIcon.iconset/icon_${s}x$s@2x.png; done
//   iconutil -c icns /tmp/AppIcon.iconset -o MacApp/Resources/AppIcon.icns
#import <Cocoa/Cocoa.h>

static NSColor *Hex(uint32_t rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: make-icon output.png\n");
            return 1;
        }
        const CGFloat size = 1024;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size pixelsHigh:size
                                                                        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        NSGraphicsContext.currentContext = context;

        // Apple's grid: an 824 pt rounded square centred on the canvas, with a soft drop shadow.
        NSRect plate = NSMakeRect(100, 100, 824, 824);
        NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:plate xRadius:185 yRadius:185];
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [NSShadow new];
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.3];
        shadow.shadowOffset = NSMakeSize(0, -12);
        shadow.shadowBlurRadius = 28;
        [shadow set];
        [Hex(0x5B8CFF) setFill];
        [shape fill];
        [NSGraphicsContext restoreGraphicsState];

        CGFloat locations[] = { 0, 0.55, 1 };
        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[ Hex(0x8B7CFF), Hex(0x5B8CFF), Hex(0x22D3EE) ]
                                                      atLocations:locations colorSpace:NSColorSpace.sRGBColorSpace];
        [gradient drawInBezierPath:shape angle:-45];

        // The sparkles in the logo's 64-unit, top-down space, mapped onto the plate.
        NSAffineTransform *t = [NSAffineTransform transform];
        [t translateXBy:100 yBy:924];
        [t scaleXBy:824 / 64.0 yBy:-824 / 64.0];
        NSBezierPath *big = [NSBezierPath bezierPath];
        [big moveToPoint:NSMakePoint(30, 12)];
        [big curveToPoint:NSMakePoint(47, 29) controlPoint1:NSMakePoint(31.5, 23) controlPoint2:NSMakePoint(36, 27.5)];
        [big curveToPoint:NSMakePoint(30, 46) controlPoint1:NSMakePoint(36, 30.5) controlPoint2:NSMakePoint(31.5, 35)];
        [big curveToPoint:NSMakePoint(13, 29) controlPoint1:NSMakePoint(28.5, 35) controlPoint2:NSMakePoint(24, 30.5)];
        [big curveToPoint:NSMakePoint(30, 12) controlPoint1:NSMakePoint(24, 27.5) controlPoint2:NSMakePoint(28.5, 23)];
        [big closePath];
        NSBezierPath *small = [NSBezierPath bezierPath];
        [small moveToPoint:NSMakePoint(45, 38)];
        [small curveToPoint:NSMakePoint(51, 44) controlPoint1:NSMakePoint(45.6, 42) controlPoint2:NSMakePoint(47.2, 43.6)];
        [small curveToPoint:NSMakePoint(45, 50) controlPoint1:NSMakePoint(47.2, 44.4) controlPoint2:NSMakePoint(45.6, 46)];
        [small curveToPoint:NSMakePoint(39, 44) controlPoint1:NSMakePoint(44.4, 46) controlPoint2:NSMakePoint(42.8, 44.4)];
        [small curveToPoint:NSMakePoint(45, 38) controlPoint1:NSMakePoint(42.8, 43.6) controlPoint2:NSMakePoint(44.4, 42)];
        [small closePath];
        [big transformUsingAffineTransform:t];
        [small transformUsingAffineTransform:t];

        [NSGraphicsContext saveGraphicsState];
        NSShadow *glow = [NSShadow new];
        glow.shadowColor = [NSColor colorWithWhite:1 alpha:0.45];
        glow.shadowBlurRadius = 36;
        [glow set];
        [[NSColor colorWithWhite:1 alpha:0.98] setFill];
        [big fill];
        [[NSColor colorWithWhite:1 alpha:0.9] setFill];
        [small fill];
        [NSGraphicsContext restoreGraphicsState];

        [context flushGraphics];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
