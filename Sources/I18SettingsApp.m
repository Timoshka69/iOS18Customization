//
//  I18SettingsApp.m
//  iOS18Customization
//
//  The small icons in the list of the Settings app follow the look chosen on
//  the home screen: dark icons in Dark (and in Auto at night), tinted icons
//  in Tinted, stock icons in Light. The same pixel routines as for the home
//  screen are used, the tint colour is baked into the image (the list icons
//  are tiny, so there is no need for a live filter here).
//
//  Runs inside com.apple.Preferences. The settings are read from the shared
//  preferences file and re-read whenever SpringBoard posts a change.
//

#import "I18Shared.h"
#include <notify.h>

static const void *kSourceIconKey = &kSourceIconKey;

static NSHashTable<UITableViewCell *> *gCells;
static NSCache *gIconCache;
static NSUInteger gIconGeneration = 1;
static IMP oCell_layoutSubviews;

#pragma mark - Converting one icon

static BOOL I18IsSettingsIcon(UIImage *image) {
    if (!image.CGImage) return NO;
    if (image.renderingMode == UIImageRenderingModeAlwaysTemplate) return NO; // glyphs, not icons
    CGSize size = image.size;
    // List icons are 29 pt squares; profile pictures and banners are not.
    return size.width >= 20.0 && size.width <= 40.0 && fabs(size.width - size.height) < 1.5;
}

static UIImage *I18SettingsIconForLook(UIImage *source, I18Look look) {
    if (look == I18LookStock) return source;
    CGImageRef image = source.CGImage;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width < 16 || height < 16 || width > 400 || height > 400) return source;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gIconCache = [[NSCache alloc] init];
        gIconCache.countLimit = 400;
    });
    NSString *key = [NSString stringWithFormat:@"%p:%ld:%lu", image, (long)look, (unsigned long)(look == I18LookTinted ? gIconGeneration : 0)];
    id cached = [gIconCache objectForKey:key];
    if ([cached isKindOfClass:[NSArray class]]) return source; // needs no change
    if ([cached isKindOfClass:[UIImage class]]) return cached;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return source;
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    uint8_t *pixels = CGBitmapContextGetData(context);
    int bytesPerRow = (int)CGBitmapContextGetBytesPerRow(context);

    BOOL tinted = look == I18LookTinted;
    I18FXResult result = I18FXMakeDarkWithFlags(pixels, (int)width, (int)height, bytesPerRow, tinted ? I18FXFlagStrongDim : 0);
    if (tinted) {
        I18FXMakeTintReady(pixels, (int)width, (int)height, bytesPerRow);
        float rgb[3];
        [[I18Settings shared] tintRGB:rgb];
        I18FXMatrix matrix = I18FXIconTintMatrix(rgb);
        I18FXApplyMatrix(pixels, (int)width, (int)height, bytesPerRow, &matrix);
    } else if (result == I18FXUntouched) {
        CGContextRelease(context);
        [gIconCache setObject:@[source] forKey:key];
        return source;
    }

    CGImageRef converted = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!converted) return source;
    UIImage *output = [UIImage imageWithCGImage:converted scale:source.scale orientation:source.imageOrientation];
    CGImageRelease(converted);
    output = [output imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    // The output remembers its source: it is never converted twice, and the
    // source (whose address is in the key) lives as long as the entry.
    objc_setAssociatedObject(output, kSourceIconKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gIconCache setObject:output forKey:key];
    return output;
}

static void I18StyleSettingsImageView(UIImageView *imageView) {
    if (![imageView isKindOfClass:[UIImageView class]]) return;
    UIImage *shown = imageView.image;
    if (!shown) return;
    UIImage *source = objc_getAssociatedObject(shown, kSourceIconKey) ?: shown;
    if (!I18IsSettingsIcon(source)) return;
    UIImage *wanted = I18SettingsIconForLook(source, [I18Settings shared].look);
    if (wanted != shown) imageView.image = wanted;
}

#pragma mark - Cells

/// The icon view of a cell, without creating one for cells that have none.
static NSArray<UIImageView *> *I18IconViewsOfCell(UITableViewCell *cell) {
    NSMutableArray<UIImageView *> *views = [NSMutableArray array];
    static Ivar imageIvar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imageIvar = class_getInstanceVariable([UITableViewCell class], "_imageView");
    });
    if (imageIvar) {
        id value = object_getIvar(cell, imageIvar);
        if ([value isKindOfClass:[UIImageView class]]) [views addObject:value];
    }
    SEL iconSel = NSSelectorFromString(@"iconImageView");
    if ([cell respondsToSelector:iconSel]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(cell, iconSel);
        if ([value isKindOfClass:[UIImageView class]] && ![views containsObject:value]) [views addObject:value];
    }
    if (views.count == 0 && !imageIvar) {
        UIImageView *imageView = cell.imageView;
        if (imageView) [views addObject:imageView];
    }
    return views;
}

static void I18StyleSettingsCell(UITableViewCell *cell) {
    if (!gCells) gCells = [NSHashTable weakObjectsHashTable];
    [gCells addObject:cell];
    for (UIImageView *imageView in I18IconViewsOfCell(cell)) {
        I18StyleSettingsImageView(imageView);
    }
}

static void hCell_layoutSubviews(UITableViewCell *self, SEL _cmd) {
    ((void (*)(id, SEL))oCell_layoutSubviews)(self, _cmd);
    I18StyleSettingsCell(self);
}

static void I18RestyleAllCells(void) {
    gIconGeneration++;
    for (UITableViewCell *cell in gCells.allObjects) {
        I18StyleSettingsCell(cell);
        [cell setNeedsLayout];
    }
}

#pragma mark - Install

void I18InstallSettingsAppHooks(void) {
    Class cellClass = objc_getClass("PSTableCell");
    if (!cellClass) return;
    I18HookMethod(cellClass, @selector(layoutSubviews), (IMP)hCell_layoutSubviews, &oCell_layoutSubviews);

    // The look was changed on the home screen.
    int token = 0;
    notify_register_dispatch(I18_CHANGED_NOTIFICATION, &token, dispatch_get_main_queue(), ^(__unused int t) {
        [[I18Settings shared] reload];
        I18RestyleAllCells();
    });

    // Auto: light / dark of the system changed while Settings is open.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [[I18Settings shared] reload];
        I18RestyleAllCells();
    }];
}
