//
//  I18HomeScreen.m
//  iOS18Customization
//
//  SpringBoard hooks:
//   - SBIconImageView: adopt its layers (dark / tinted contents), colour
//     matrix for Tinted, clock hands, large icon geometry.
//   - SBIconView: labels / badges / delete buttons for large icons, widget and
//     badge tint.
//   - SBRootFolderView: the "Edit" button in jiggle mode.
//
//  Every class and selector is looked up at runtime; anything missing on a
//  particular 15.x build simply turns that part off.
//

#import "I18Shared.h"

static Class gIconViewClass;
static Class gIconImageViewClass;

static NSHashTable<UIView *> *gIconViews;
static NSHashTable<UIView *> *gImageViews;

static NSUInteger gStyleGeneration = 1;   // bumped on every look / tint change

static const CGFloat kLargeIconScale = 1.16;

static const void *kGeometryKey = &kGeometryKey;
static const void *kEligibleKey = &kEligibleKey;
static const void *kStyledGenerationKey = &kStyledGenerationKey;
static const void *kImageGenerationKey = &kImageGenerationKey;
static const void *kLabelMaskKey = &kLabelMaskKey;
static const void *kShiftKey = &kShiftKey;
static const void *kDarkOverrideKey = &kDarkOverrideKey;
static const void *kOriginalGravityKey = &kOriginalGravityKey;

static NSString *const kOriginalBackgroundKey = @"i18OriginalBackground";
static NSString *const kOriginalFillKey = @"i18OriginalFill";

#pragma mark - Geometry record

/// What SpringBoard asked for, before the large-icon scale is applied, and
/// what was really set.
///
/// App icons are made larger through their bounds, not a transform: the
/// layer then really is that big, so the launch / close zoom, snapshots and
/// portals of the icon show all of it (with a transform they were cut off).
/// Folder and clock icons keep the transform (see I18GeometryOf).
@interface I18Geometry : NSObject
@property (nonatomic) CGSize size;
@property (nonatomic) CGPoint center;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic) CGSize outSize;
@property (nonatomic) CGPoint outCenter;
@property (nonatomic) BOOL valid;
@property (nonatomic) BOOL transformMode;
@property (nonatomic) CGFloat applied;
@end

@implementation I18Geometry
- (instancetype)init {
    if ((self = [super init])) {
        _transform = CGAffineTransformIdentity;
        _applied = 1.0;
    }
    return self;
}
@end

static I18Geometry *I18GeometryOf(UIView *view) {
    I18Geometry *geometry = objc_getAssociatedObject(view, kGeometryKey);
    if (!geometry) {
        geometry = [[I18Geometry alloc] init];
        // Only the plain app icon image view is resized through its bounds.
        // Folders (mini grid), the clock (hands) and other special icons
        // lay out their parts for one size, they keep the transform.
        NSString *name = NSStringFromClass(object_getClass(view));
        if ([name hasPrefix:@"NSKVONotifying_"]) name = [name substringFromIndex:15];
        geometry.transformMode = ![name isEqualToString:@"SBIconImageView"];
        objc_setAssociatedObject(view, kGeometryKey, geometry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return geometry;
}

#pragma mark - Small helpers

static UIView *I18IconViewContaining(UIView *view) {
    UIView *current = view.superview;
    for (int depth = 0; current && depth < 5; depth++, current = current.superview) {
        if (gIconViewClass && [current isKindOfClass:gIconViewClass]) return current;
    }
    return nil;
}

static BOOL I18BoolCall(id target, NSString *selectorName) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:sel]) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:sel];
    if (signature.numberOfArguments != 2 || signature.methodReturnLength != sizeof(BOOL)) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(target, sel);
}

static const void *kWidgetKey = &kWidgetKey;

static BOOL I18DetectWidget(UIView *iconView) {
    id icon = I18Call(iconView, @"icon");
    if (icon) {
        if (I18BoolCall(icon, @"isWidgetIcon") || I18BoolCall(icon, @"isWidgetStackIcon")) return YES;
        if (I18ClassNameContains(icon, @"Widget")) return YES;
    }
    // Widgets are shown through a custom view controller instead of an image.
    if (I18Call(iconView, @"customIconImageViewController")) return YES;
    if (I18ClassNameContains(iconView, @"Widget")) return YES;
    // A home screen icon is never wider than ~90 pt; widgets are.
    if (iconView.bounds.size.width > 110.0) return YES;
    return NO;
}

static BOOL I18IsWidgetIconView(UIView *iconView) {
    if (!iconView) return NO;
    BOOL widget = I18DetectWidget(iconView);
    objc_setAssociatedObject(iconView, kWidgetKey, @(widget), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return widget;
}

/// Cheap check for hot paths (frame hooks): uses the last detection.
static BOOL I18KnownWidget(UIView *iconView) {
    NSNumber *value = objc_getAssociatedObject(iconView, kWidgetKey);
    return value ? value.boolValue : I18IsWidgetIconView(iconView);
}

static BOOL I18IsLabel(UIView *view) {
    return I18ClassNameContains(view, @"Label");
}

static BOOL I18IsBadge(UIView *view) {
    return I18ClassNameContains(view, @"Badge") || I18ClassNameContains(view, @"AccessoryView");
}

static BOOL I18IsCloseBox(UIView *view) {
    return I18ClassNameContains(view, @"CloseBox") || I18ClassNameContains(view, @"Delete");
}

static BOOL I18IsChrome(UIView *view) {
    return I18IsLabel(view) || I18IsBadge(view) || I18IsCloseBox(view);
}

/// Large size applies to icons and widgets that live on the home screen
/// pages and in the dock - like iOS 18. Copies of an icon that SpringBoard
/// makes for its animations (app launch / close, drag) live elsewhere and
/// stay as they are, so they match the frame SpringBoard animates them in.
static BOOL I18ComputeLargeEligible(UIView *iconView) {
    BOOL widget = I18IsWidgetIconView(iconView);
    // An icon that is being dragged (or its drag preview) stays large.
    id dragLocation = I18Call(iconView, @"location") ?: I18Call(iconView, @"iconLocation");
    if ([dragLocation isKindOfClass:[NSString class]] && [(NSString *)dragLocation rangeOfString:@"Drag"].location != NSNotFound) return !widget || [objc_getAssociatedObject(iconView, kEligibleKey) boolValue];
    if (I18BoolCall(iconView, @"isDragging") || I18BoolCall(iconView, @"isGrabbed")) {
        NSNumber *previous = objc_getAssociatedObject(iconView, kEligibleKey);
        if (previous) return previous.boolValue;
    }
    // Exclusions first (anywhere above), then the closest list or drag
    // container decides.
    int depth = 0;
    for (UIView *view = iconView.superview; view && depth < 14; view = view.superview, depth++) {
        if (I18ClassNameContains(view, @"Library") || I18ClassNameContains(view, @"Switcher") ||
            I18ClassNameContains(view, @"Gallery") || I18ClassNameContains(view, @"Today") ||
            I18ClassNameContains(view, @"Spotlight")) {
            return NO;
        }
    }
    depth = 0;
    for (UIView *view = iconView.superview; view && depth < 12; view = view.superview, depth++) {
        if (I18ClassNameContains(view, @"Drag") || I18ClassNameContains(view, @"Lift")) {
            // A dragged icon keeps what it had on its page.
            NSNumber *previous = objc_getAssociatedObject(iconView, kEligibleKey);
            return previous ? previous.boolValue : !widget;
        }
        if (I18ClassNameContains(view, @"Library") || I18ClassNameContains(view, @"Switcher") ||
            I18ClassNameContains(view, @"Floating") || I18ClassNameContains(view, @"Gallery") ||
            I18ClassNameContains(view, @"Today") || I18ClassNameContains(view, @"Spotlight")) {
            return NO;
        }
        if (I18ClassNameContains(view, @"RootIconListView")) return YES;
        if (I18ClassNameContains(view, @"DockIconListView")) return !widget;
        if (I18ClassNameContains(view, @"IconListView")) {
            // Plain list views: a page of the home screen on some builds,
            // a folder or the Today view on others - the location decides.
            id location = I18Call(iconView, @"location") ?: I18Call(iconView, @"iconLocation");
            if (![location isKindOfClass:[NSString class]]) return NO;
            NSString *name = location;
            if ([name hasPrefix:@"SBIconLocationRoot"]) return YES;
            return !widget && [name rangeOfString:@"Dock"].location != NSNotFound;
        }
    }
    // Not in any list: an icon that is being dragged, or one lifted for an
    // animation. It keeps what it was, so a dragged large icon stays large
    // and without its label.
    NSNumber *previous = objc_getAssociatedObject(iconView, kEligibleKey);
    return previous.boolValue;
}

/// Home screen pages, dock and Today view. The widget gallery, App Library
/// and other sheets are excluded from widget tinting.
static BOOL I18IsHomeLocation(UIView *iconView) {
    id location = I18Call(iconView, @"location") ?: I18Call(iconView, @"iconLocation");
    if ([location isKindOfClass:[NSString class]]) {
        NSString *name = location;
        return [name hasPrefix:@"SBIconLocationRoot"] || [name rangeOfString:@"Dock"].location != NSNotFound ||
               [name rangeOfString:@"Today"].location != NSNotFound;
    }
    for (UIView *view = iconView.superview; view; view = view.superview) {
        if (I18ClassNameContains(view, @"AddWidget") || I18ClassNameContains(view, @"Gallery") || I18ClassNameContains(view, @"Library")) return NO;
    }
    return YES;
}

static BOOL I18IsLargeEligible(UIView *iconView) {
    NSNumber *value = objc_getAssociatedObject(iconView, kEligibleKey);
    return value.boolValue;
}

static void I18RefreshEligibility(UIView *iconView) {
    objc_setAssociatedObject(iconView, kEligibleKey, @(I18ComputeLargeEligible(iconView)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *I18ImageViewOf(UIView *iconView) {
    id candidate = I18ValueForKey(iconView, @"_iconImageView");
    if (gIconImageViewClass && [candidate isKindOfClass:gIconImageViewClass]) return candidate;
    for (UIView *sub in iconView.subviews) {
        if ([sub isKindOfClass:gIconImageViewClass]) return sub;
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:gIconImageViewClass]) return inner;
        }
    }
    return nil;
}

/// Direct children of the icon view plus children of plain containers
/// (iOS 15 sometimes nests the label / accessory one level deeper).
static NSArray<UIView *> *I18IconViewParts(UIView *iconView, UIView *imageView) {
    NSMutableArray<UIView *> *parts = [NSMutableArray array];
    for (UIView *sub in iconView.subviews) {
        if (sub == imageView) continue;
        [parts addObject:sub];
        if (!I18IsChrome(sub) && ![sub isKindOfClass:gIconImageViewClass]) {
            for (UIView *inner in sub.subviews) {
                if (inner != imageView && I18IsChrome(inner)) [parts addObject:inner];
            }
        }
    }
    return parts;
}

#pragma mark - Large icons: geometry

static CGFloat I18TargetScale(UIView *imageView) {
    if (![I18Settings shared].largeIcons) return 1.0;
    UIView *iconView = I18IconViewContaining(imageView);
    if (!iconView || I18KnownWidget(iconView)) return 1.0;
    return I18IsLargeEligible(iconView) ? kLargeIconScale : 1.0;
}

static IMP oIV_setFrame, oIV_setBounds, oIV_setCenter, oIV_setTransform;
static BOOL gGeometryPassthrough;
static CGFloat gTypicalIconWidth = 60.0;

static void I18CallSetBounds(UIView *view, CGRect bounds) {
    if (oIV_setBounds) ((void (*)(id, SEL, CGRect))oIV_setBounds)(view, @selector(setBounds:), bounds);
    else view.bounds = bounds;
}

static void I18CallSetCenter(UIView *view, CGPoint center) {
    if (oIV_setCenter) ((void (*)(id, SEL, CGPoint))oIV_setCenter)(view, @selector(setCenter:), center);
    else view.center = center;
}

static void I18CallSetTransform(UIView *view, CGAffineTransform transform) {
    if (oIV_setTransform) ((void (*)(id, SEL, CGAffineTransform))oIV_setTransform)(view, @selector(setTransform:), transform);
    else view.transform = transform;
}

static BOOL I18SizeClose(CGSize a, CGSize b) {
    return fabs(a.width - b.width) < 0.3 && fabs(a.height - b.height) < 0.3;
}

static BOOL I18PointClose(CGPoint a, CGPoint b) {
    return fabs(a.x - b.x) < 0.3 && fabs(a.y - b.y) < 0.3;
}

/// Size of the frame the icon has on screen right now.
static CGSize I18ShownSize(I18Geometry *geometry) {
    if (geometry.transformMode) return CGSizeMake(geometry.size.width * geometry.applied, geometry.size.height * geometry.applied);
    return geometry.outSize;
}

static void I18ApplyGeometry(UIView *view, I18Geometry *geometry, CGFloat scale) {
    if (!geometry.valid) return;
    gGeometryPassthrough = YES;

    CGRect bounds = view.bounds;
    bounds.size = geometry.transformMode ? geometry.size : CGSizeMake(geometry.size.width * scale, geometry.size.height * scale);
    I18CallSetBounds(view, bounds);

    // The icon grows around its own middle. Every animation of SpringBoard
    // (launch, close, unlock, jiggle) moves icons by their middle, so a large
    // icon stays exactly where SpringBoard expects it and never slides.
    I18CallSetCenter(view, geometry.center);

    if (geometry.transformMode) {
        CGAffineTransform transform = geometry.transform;
        if (fabs(scale - 1.0) > 0.001) {
            transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), geometry.transform);
        }
        I18CallSetTransform(view, transform);
    }

    gGeometryPassthrough = NO;
    geometry.applied = scale;
    geometry.outSize = view.bounds.size;
    geometry.outCenter = view.center;
    if (scale <= 1.001 && geometry.size.width > 30.0 && geometry.size.width < 100.0 && !geometry.transformMode) {
        gTypicalIconWidth = geometry.size.width;
    }

    // Once an icon has been large, its picture always fills the bounds:
    // switching the gravity back at the start of the shrink animation made
    // the picture jump to its small size before the frame got there.
    CALayer *layer = view.layer;
    if (scale > 1.001 || objc_getAssociatedObject(layer, kOriginalGravityKey)) {
        if (!objc_getAssociatedObject(layer, kOriginalGravityKey)) {
            objc_setAssociatedObject(layer, kOriginalGravityKey, layer.contentsGravity ?: kCAGravityResize, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        layer.minificationFilter = kCAFilterTrilinear;
        if (![layer.contentsGravity isEqualToString:kCAGravityResize]) layer.contentsGravity = kCAGravityResize;
    }
}

static void I18EnsureGeometryBase(UIView *view, I18Geometry *geometry) {
    if (geometry.valid) return;
    geometry.size = view.bounds.size;
    geometry.center = view.center;
    geometry.transform = view.transform;
    geometry.outSize = geometry.size;
    geometry.outCenter = geometry.center;
    geometry.valid = YES;
    geometry.applied = 1.0;
}

static void I18UpdateGeometry(UIView *imageView, BOOL force) {
    I18Geometry *geometry = I18GeometryOf(imageView);
    I18EnsureGeometryBase(imageView, geometry);
    CGFloat scale = I18TargetScale(imageView);
    if (!force && fabs(scale - geometry.applied) < 0.001) return;
    I18ApplyGeometry(imageView, geometry, scale);
}

static void hIV_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !oIV_setBounds || !oIV_setCenter || !oIV_setTransform) {
        ((void (*)(id, SEL, CGRect))oIV_setFrame)(self, _cmd, frame);
        return;
    }
    CGFloat scale = I18TargetScale(self);
    BOOL scaled = geometry && geometry.valid && geometry.applied > 1.001;
    if (!scaled && scale <= 1.001) {
        ((void (*)(id, SEL, CGRect))oIV_setFrame)(self, _cmd, frame);
        if (geometry) {
            geometry.size = self.bounds.size;
            geometry.center = self.center;
            geometry.outSize = geometry.size;
            geometry.outCenter = geometry.center;
            geometry.valid = YES;
        }
        return;
    }

    geometry = I18GeometryOf(self);
    if (!geometry.valid) geometry.transform = self.transform;
    CGPoint middle = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (scaled && I18SizeClose(frame.size, I18ShownSize(geometry))) {
        // The large frame was read back (and maybe moved): keep the size
        // SpringBoard asked for, only follow the move.
        if (I18PointClose(middle, geometry.outCenter)) return;
        geometry.center = CGPointMake(middle.x - (geometry.outCenter.x - geometry.center.x),
                                      middle.y - (geometry.outCenter.y - geometry.center.y));
    } else {
        geometry.size = frame.size;
        geometry.center = middle;
    }
    geometry.valid = YES;
    I18ApplyGeometry(self, geometry, scale);
}

static void hIV_setBounds(UIView *self, SEL _cmd, CGRect bounds) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !geometry || !geometry.valid || geometry.applied <= 1.001) {
        ((void (*)(id, SEL, CGRect))oIV_setBounds)(self, _cmd, bounds);
        if (!gGeometryPassthrough && geometry) {
            geometry.size = bounds.size;
            geometry.outSize = bounds.size;
        }
        return;
    }
    if (!geometry.transformMode && I18SizeClose(bounds.size, geometry.outSize)) {
        ((void (*)(id, SEL, CGRect))oIV_setBounds)(self, _cmd, bounds); // read back
        return;
    }
    BOOL sizeChanged = !I18SizeClose(geometry.size, bounds.size);
    geometry.size = bounds.size;
    if (geometry.transformMode) ((void (*)(id, SEL, CGRect))oIV_setBounds)(self, _cmd, bounds);
    // The large-icon offset depends on the height, keep it in sync.
    if (sizeChanged || !geometry.transformMode) I18ApplyGeometry(self, geometry, geometry.applied);
}

static void hIV_setCenter(UIView *self, SEL _cmd, CGPoint center) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !geometry || !geometry.valid || geometry.applied <= 1.001) {
        ((void (*)(id, SEL, CGPoint))oIV_setCenter)(self, _cmd, center);
        if (!gGeometryPassthrough && geometry) {
            geometry.center = center;
            geometry.outCenter = center;
        }
        return;
    }
    if (I18PointClose(center, geometry.outCenter) || I18PointClose(center, self.center)) return;
    geometry.center = center;
    I18ApplyGeometry(self, geometry, geometry.applied);
}

static void hIV_setTransform(UIView *self, SEL _cmd, CGAffineTransform transform) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !geometry || !geometry.valid || !geometry.transformMode || geometry.applied <= 1.001) {
        ((void (*)(id, SEL, CGAffineTransform))oIV_setTransform)(self, _cmd, transform);
        if (!gGeometryPassthrough && geometry) geometry.transform = transform;
        return;
    }
    if (CGAffineTransformEqualToTransform(transform, self.transform)) return;
    geometry.transform = transform;
    I18ApplyGeometry(self, geometry, geometry.applied);
}

/// Animations and badges ask the icon view where its image is. For a large
/// icon that is the large frame (same middle, bigger size).
static IMP oV_iconImageFrame;

static CGRect hV_iconImageFrame(UIView *self, SEL _cmd) {
    CGRect frame = ((CGRect (*)(id, SEL))oV_iconImageFrame)(self, _cmd);
    UIView *imageView = I18ImageViewOf(self);
    I18Geometry *geometry = imageView ? objc_getAssociatedObject(imageView, kGeometryKey) : nil;
    if (!geometry.valid || geometry.applied <= 1.001) return frame;
    if (!I18SizeClose(frame.size, geometry.size)) return frame; // already the large one
    CGFloat scale = geometry.applied;
    return CGRectMake(frame.origin.x - frame.size.width * (scale - 1.0) * 0.5, frame.origin.y - frame.size.height * (scale - 1.0) * 0.5,
                      frame.size.width * scale, frame.size.height * scale);
}

#pragma mark - Large widgets

static const void *kWidgetScaleKey = &kWidgetScaleKey;

/// iOS 18 makes widgets a little bigger too, so their edges stay in line
/// with the large icons around them. The widget's layers are scaled as a
/// whole (its content is drawn by another process and must not re-layout).
static void I18ApplyWidgetScale(UIView *iconView, BOOL large, BOOL animated) {
    CALayer *layer = iconView.layer;
    CGSize size = iconView.bounds.size;
    CGFloat scale = 1.0;
    if (large && size.width > 40.0) {
        scale = 1.0 + gTypicalIconWidth * (kLargeIconScale - 1.0) / size.width;
        scale = MIN(MAX(scale, 1.0), 1.12);
    }
    NSNumber *applied = objc_getAssociatedObject(iconView, kWidgetScaleKey);
    if (!applied && scale <= 1.001 && CATransform3DEqualToTransform(layer.sublayerTransform, CATransform3DIdentity)) return;
    // SpringBoard animating the widget's size must not make the scale jitter.
    if (applied && scale > 1.001 && fabs(applied.doubleValue - scale) < 0.01) scale = applied.doubleValue;

    // Around the middle, like the icons, so rows and columns stay in line.
    CATransform3D target = scale > 1.001 ? CATransform3DMakeScale(scale, scale, 1.0) : CATransform3DIdentity;
    CATransform3D current = layer.sublayerTransform;
    if (CATransform3DEqualToTransform(current, target)) return;
    // A transform that is neither ours nor none belongs to a SpringBoard
    // animation: leave it, ours comes back with the next layout pass.
    CATransform3D ours = applied ? CATransform3DMakeScale(applied.doubleValue, applied.doubleValue, 1.0) : CATransform3DIdentity;
    if (!CATransform3DEqualToTransform(current, CATransform3DIdentity) && !CATransform3DEqualToTransform(current, ours)) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (animated && iconView.window) {
        CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"sublayerTransform"];
        // Same curve as the UIView spring the icons use (0.62 s, damping
        // 0.92), so widgets and icons grow together.
        spring.damping = 18.6;
        spring.stiffness = 102.7;
        spring.mass = 1.0;
        spring.fromValue = [NSValue valueWithCATransform3D:(layer.presentationLayer ?: layer).sublayerTransform];
        spring.toValue = [NSValue valueWithCATransform3D:target];
        spring.duration = spring.settlingDuration;
        [layer addAnimation:spring forKey:@"i18.widgetScale"];
    }
    layer.sublayerTransform = target;
    [CATransaction commit];
    objc_setAssociatedObject(iconView, kWidgetScaleKey, scale > 1.001 ? @(scale) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Large icons: label, badge, delete button

static void I18SetLabelHidden(UIView *label, BOOL hidden, BOOL animated) {
    CALayer *layer = label.layer;
    CALayer *mask = objc_getAssociatedObject(label, kLabelMaskKey);
    if (!mask) {
        if (!hidden) return;
        if (layer.mask) return; // SpringBoard uses its own mask here, don't touch
        mask = [CALayer layer];
        mask.backgroundColor = UIColor.blackColor.CGColor;
        objc_setAssociatedObject(label, kLabelMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = CGRectInset(layer.bounds, -60.0, -30.0);
    if (layer.mask != mask) layer.mask = mask;
    float target = hidden ? 0.0f : 1.0f;
    if (animated) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(mask.presentationLayer ? mask.presentationLayer.opacity : mask.opacity);
        fade.toValue = @(target);
        fade.duration = 0.28;
        [mask addAnimation:fade forKey:@"i18.fade"];
    }
    mask.opacity = target;
    [CATransaction commit];

    if (!hidden) {
        __weak UIView *weakLabel = label;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((animated ? 0.32 : 0.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *strongLabel = weakLabel;
            CALayer *currentMask = objc_getAssociatedObject(strongLabel, kLabelMaskKey);
            if (strongLabel && currentMask && currentMask.opacity >= 1.0f && strongLabel.layer.mask == currentMask) {
                strongLabel.layer.mask = nil;
                objc_setAssociatedObject(strongLabel, kLabelMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        });
    }
}

/// Badges and delete buttons sit on the corners of the icon. When
/// SpringBoard positions them from the unscaled icon frame they are moved
/// out to the corner of the large icon.
static void I18ShiftCornerView(UIView *view, UIView *imageView, BOOL rightCorner) {
    CGAffineTransform current = view.transform;
    NSValue *ours = objc_getAssociatedObject(view, kShiftKey);
    BOOL oursActive = ours && CGAffineTransformEqualToTransform(current, ours.CGAffineTransformValue);
    if (!CGAffineTransformIsIdentity(current) && !oursActive) return; // SpringBoard is animating it

    CGFloat dx = 0.0, dy = 0.0;
    I18Geometry *geometry = objc_getAssociatedObject(imageView, kGeometryKey);
    if (geometry.valid && geometry.applied > 1.001 && view.superview && imageView.superview) {
        CGFloat half = geometry.size.width * (geometry.applied - 1.0) * 0.5;
        CGFloat baseEdge = geometry.center.x + (rightCorner ? 0.5 : -0.5) * geometry.size.width;
        CGFloat largeEdge = baseEdge + (rightCorner ? half : -half);
        CGPoint center = [view.superview convertPoint:view.center toView:imageView.superview];
        if (fabs(center.x - baseEdge) < fabs(center.x - largeEdge)) {
            // Out to the corner of the large icon (it grew to all sides).
            dx = rightCorner ? half : -half;
            dy = -geometry.size.height * (geometry.applied - 1.0) * 0.5;
        }
    }

    CGAffineTransform shift = CGAffineTransformMakeTranslation(dx, dy);
    if (!CGAffineTransformEqualToTransform(shift, current)) view.transform = shift;
    if (dx == 0.0) objc_setAssociatedObject(view, kShiftKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    else objc_setAssociatedObject(view, kShiftKey, [NSValue valueWithCGAffineTransform:shift], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Look: icons, clock, widgets, badges

/// Luma of a neutral (grey) colour, or -1 for coloured / transparent ones.
static CGFloat I18NeutralLuma(CGColorRef color) {
    if (!color) return -1.0;
    UIColor *ui = [UIColor colorWithCGColor:color];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![ui getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if (![ui getWhite:&white alpha:&a]) return -1.0;
        r = g = b = white;
    }
    CGFloat mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
    if (a < 0.05 || (mx - mn) > 0.25) return -1.0;
    return 0.299 * r + 0.587 * g + 0.114 * b;
}

/// Colour a part of the live clock should have in the current look
/// (+1, caller releases). Thin dark parts (hands, centre dot) turn white,
/// a big light part (a drawn dial) turns dark. Everything else keeps its colour.
static CGColorRef I18CopyClockPartColor(CGColorRef original, BOOL dark, CGFloat areaRatio) {
    if (dark) {
        CGFloat luma = I18NeutralLuma(original);
        if (luma >= 0.0 && luma < 0.45 && areaRatio < 0.15) {
            return CGColorCreateSRGB(0.95, 0.95, 0.95, CGColorGetAlpha(original));
        }
        if (luma > 0.75 && areaRatio > 0.30) {
            return CGColorCreateSRGB(0.11, 0.11, 0.12, CGColorGetAlpha(original));
        }
    }
    return CGColorRetain(original);
}

/// Clock hands are plain coloured layers. In the dark looks the black hands
/// become white (the dial itself is flipped by the contents conversion).
static void I18StyleClockParts(CALayer *layer, CGFloat rootArea, BOOL dark, int depth) {
    if (!layer || depth > 4 || rootArea <= 0.0) return;
    for (CALayer *sublayer in layer.sublayers) {
        if (!sublayer.contents) {
            CGFloat areaRatio = (sublayer.bounds.size.width * sublayer.bounds.size.height) / rootArea;
            CGColorRef background = sublayer.backgroundColor;
            id stored = [sublayer valueForKey:kOriginalBackgroundKey];
            if (!stored && background) {
                [sublayer setValue:(__bridge id)background forKey:kOriginalBackgroundKey];
                stored = (__bridge id)background;
            }
            if (stored) {
                CGColorRef wanted = I18CopyClockPartColor((__bridge CGColorRef)stored, dark, areaRatio);
                if (!CGColorEqualToColor(sublayer.backgroundColor, wanted)) sublayer.backgroundColor = wanted;
                CGColorRelease(wanted);
            }
            if ([sublayer isKindOfClass:[CAShapeLayer class]]) {
                CAShapeLayer *shape = (CAShapeLayer *)sublayer;
                id storedFill = [shape valueForKey:kOriginalFillKey];
                if (!storedFill && shape.fillColor) {
                    [shape setValue:(__bridge id)shape.fillColor forKey:kOriginalFillKey];
                    storedFill = (__bridge id)shape.fillColor;
                }
                if (storedFill) {
                    CGColorRef wanted = I18CopyClockPartColor((__bridge CGColorRef)storedFill, dark, areaRatio);
                    if (!CGColorEqualToColor(shape.fillColor, wanted)) shape.fillColor = wanted;
                    CGColorRelease(wanted);
                }
            }
        }
        I18StyleClockParts(sublayer, rootArea, dark, depth + 1);
    }
}

/// Widgets are drawn by another process; they pick light or dark from the
/// traits of their host view controller. Overriding only the view is not
/// enough, so the override goes onto every view controller in the widget.
static void I18SetStyle(id object, BOOL dark) {
    if (![object respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) return;
    UIUserInterfaceStyle current = ((UIUserInterfaceStyle (*)(id, SEL))objc_msgSend)(object, @selector(overrideUserInterfaceStyle));
    if (dark) {
        if (current != UIUserInterfaceStyleDark) {
            ((void (*)(id, SEL, UIUserInterfaceStyle))objc_msgSend)(object, @selector(setOverrideUserInterfaceStyle:), UIUserInterfaceStyleDark);
            objc_setAssociatedObject(object, kDarkOverrideKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (objc_getAssociatedObject(object, kDarkOverrideKey)) {
        ((void (*)(id, SEL, UIUserInterfaceStyle))objc_msgSend)(object, @selector(setOverrideUserInterfaceStyle:), UIUserInterfaceStyleUnspecified);
        objc_setAssociatedObject(object, kDarkOverrideKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void I18ForceWidgetAppearanceIn(UIView *view, BOOL dark, int depth) {
    if (!view || depth > 7) return;
    UIResponder *next = view.nextResponder;
    if ([next isKindOfClass:[UIViewController class]]) I18SetStyle(next, dark);
    for (UIView *sub in view.subviews) {
        I18ForceWidgetAppearanceIn(sub, dark, depth + 1);
    }
}

static void I18ForceWidgetAppearance(UIView *part, BOOL dark) {
    I18SetStyle(part, dark);
    I18ForceWidgetAppearanceIn(part, dark, 0);
}

static NSString *I18BundleIDOfImageView(UIView *imageView) {
    UIView *iconView = I18IconViewContaining(imageView);
    id icon = I18Call(iconView, @"icon");
    id bundle = I18Call(icon, @"applicationBundleID");
    return [bundle isKindOfClass:[NSString class]] ? bundle : nil;
}

/// Apps whose icon is a picture (no plate) but has a dark version in iOS 18.
static BOOL I18IsBusyDarkApp(UIView *imageView) {
    NSString *bundle = I18BundleIDOfImageView(imageView);
    if (!bundle) return NO;
    static NSSet<NSString *> *apps;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        apps = [NSSet setWithArray:@[@"com.apple.Maps"]];
    });
    return [apps containsObject:bundle];
}

static void I18StyleImageView(UIView *imageView) {
    if (!imageView) return;
    // The token lives on the image view itself: SpringBoard recycles image
    // views between icons, so a token on the icon view would go stale.
    objc_setAssociatedObject(imageView, kImageGenerationKey, @(gStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    I18Look look = I18CurrentLook();
    BOOL clock = I18ClassNameContains(imageView, @"Clock");

    // Only a real app icon image view stands for one app (pack icon, Maps).
    // Folder icons show several apps, other image views (badges, switcher
    // icons) none that can be told for sure.
    BOOL appIcon = gIconImageViewClass && [imageView isKindOfClass:gIconImageViewClass] && !I18ClassNameContains(imageView, @"Folder");
    I18SetLayerBusyDark(imageView.layer, appIcon && I18IsBusyDarkApp(imageView));
    I18SetLayerBundleID(imageView.layer, appIcon ? I18BundleIDOfImageView(imageView) : nil);
    I18AdoptLayerTree(imageView.layer, clock);
    I18SetTintFilter(imageView.layer, look == I18LookTinted ? I18TintIcon : I18TintNone);
    // After the filter: the check also refreshes the tint of layers below
    // (an old image view SpringBoard keeps inside a cross-fade).
    I18VerifyLayerTree(imageView.layer);

    if (clock) {
        CGSize size = imageView.layer.bounds.size;
        I18StyleClockParts(imageView.layer, size.width * size.height, look != I18LookStock, 0);
    }

    if (I18ClassNameContains(imageView, @"Folder")) {
        imageView.overrideUserInterfaceStyle = look == I18LookStock ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleDark;
    }
}

/// Widgets that draw a picture behind white text and have no dark look
/// (Weather): in Tinted the picture must become the dark plate.
static BOOL I18IsLightOnlyWidget(UIView *iconView) {
    static const void *kLightOnlyKey = &kLightOnlyKey;
    id icon = I18Call(iconView, @"icon");
    if (!icon) return NO;
    NSNumber *cached = objc_getAssociatedObject(icon, kLightOnlyKey);
    if (cached) return cached.boolValue;
    NSMutableArray *candidates = [NSMutableArray arrayWithObject:icon];
    for (NSString *key in @[@"activeWidget", @"widget", @"firstWidget"]) {
        id widget = I18Call(icon, key);
        if (widget) [candidates addObject:widget];
    }
    BOOL lightOnly = NO;
    for (id candidate in candidates) {
        id extension = I18Call(candidate, @"extensionBundleIdentifier");
        NSString *text = [extension isKindOfClass:[NSString class]] ? extension : [candidate description];
        if ([text rangeOfString:@"com.apple.weather"].location != NSNotFound) lightOnly = YES;
    }
    objc_setAssociatedObject(icon, kLightOnlyKey, @(lightOnly), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return lightOnly;
}

#pragma mark - Labels through SpringBoard itself

// SBIconView has its own "label hidden" switch. When it is there, the large
// size uses it: SpringBoard then keeps the label hidden through drags,
// drops and re-layouts itself, instead of us masking a label it keeps
// re-creating.
static IMP oV_setLabelHidden;
static const void *kRequestedLabelHiddenKey = &kRequestedLabelHiddenKey;

static BOOL I18WantsLabelHidden(UIView *iconView) {
    return [I18Settings shared].largeIcons && I18IsLargeEligible(iconView);
}

static void hV_setLabelHidden(UIView *self, SEL _cmd, BOOL hidden) {
    objc_setAssociatedObject(self, kRequestedLabelHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, BOOL))oV_setLabelHidden)(self, _cmd, hidden || I18WantsLabelHidden(self));
}

static BOOL I18NativeLabelHidden(UIView *iconView) {
    for (NSString *name in @[@"isLabelHidden", @"labelHidden"]) {
        SEL sel = NSSelectorFromString(name);
        if ([iconView respondsToSelector:sel]) return ((BOOL (*)(id, SEL))objc_msgSend)(iconView, sel);
    }
    return NO;
}

static NSArray<UIView *> *I18LabelsOf(UIView *iconView) {
    NSMutableArray<UIView *> *labels = [NSMutableArray array];
    for (UIView *part in I18IconViewParts(iconView, nil)) {
        if (I18IsLabel(part)) [labels addObject:part];
    }
    return labels;
}

/// Returns NO when SpringBoard has no such switch (the mask is used then).
static BOOL I18ApplyNativeLabel(UIView *iconView, BOOL animated) {
    if (!oV_setLabelHidden) return NO;
    BOOL requested = [objc_getAssociatedObject(iconView, kRequestedLabelHiddenKey) boolValue];
    BOOL want = requested || I18WantsLabelHidden(iconView);
    if (I18NativeLabelHidden(iconView) == want) return YES;
    SEL sel = NSSelectorFromString(@"setLabelHidden:");
    if (!animated || !iconView.window) {
        ((void (*)(id, SEL, BOOL))oV_setLabelHidden)(iconView, sel, want);
        return YES;
    }
    NSArray<UIView *> *labels = I18LabelsOf(iconView);
    if (want) {
        // Fade out, then hide.
        [UIView animateWithDuration:0.30 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            for (UIView *label in labels) label.alpha = 0.0;
        } completion:^(__unused BOOL finished) {
            ((void (*)(id, SEL, BOOL))oV_setLabelHidden)(iconView, sel, I18WantsLabelHidden(iconView) ||
                [objc_getAssociatedObject(iconView, kRequestedLabelHiddenKey) boolValue]);
            for (UIView *label in labels) label.alpha = 1.0;
        }];
    } else {
        ((void (*)(id, SEL, BOOL))oV_setLabelHidden)(iconView, sel, NO);
        NSArray<UIView *> *shown = I18LabelsOf(iconView);
        for (UIView *label in shown) label.alpha = 0.0;
        [UIView animateWithDuration:0.40 delay:0.12 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            for (UIView *label in shown) label.alpha = 1.0;
        } completion:nil];
    }
    return YES;
}

static void I18StyleIconViewParts(UIView *iconView, UIView *imageView, BOOL animated) {
    I18Settings *settings = [I18Settings shared];
    I18Look look = I18CurrentLook();
    BOOL tinted = look == I18LookTinted;
    BOOL widget = I18IsWidgetIconView(iconView);
    // Large size hides the labels of icons and widgets alike (iOS 18).
    BOOL large = settings.largeIcons && I18IsLargeEligible(iconView);

    // Widgets are switched to their dark appearance in the dark looks (like
    // iOS 18) and tinted by brightness, never inverted: inverting turned
    // photos into negatives and flipped night-time weather widgets.
    BOOL homeWidget = widget && I18IsHomeLocation(iconView);
    BOOL darkWidget = homeWidget && look != I18LookStock;
    if (widget) I18ApplyWidgetScale(iconView, large && homeWidget, animated);
    BOOL nativeLabels = I18ApplyNativeLabel(iconView, animated);

    for (UIView *part in I18IconViewParts(iconView, imageView)) {
        if (I18IsLabel(part)) {
            // With SpringBoard's own switch a mask from earlier is taken off.
            // Both ways at once: SpringBoard's own switch and our mask. While
            // an icon is dragged SpringBoard shows its label again on its own.
            (void)nativeLabels;
            I18SetLabelHidden(part, large, animated);
        } else if (I18IsBadge(part)) {
            I18SetTintFilter(part.layer, tinted ? I18TintBadge : I18TintNone);
            if (imageView) I18ShiftCornerView(part, imageView, YES);
        } else if (I18IsCloseBox(part)) {
            if (imageView) I18ShiftCornerView(part, imageView, NO);
        } else if (widget) {
            I18TintKind kind = I18IsLightOnlyWidget(iconView) ? I18TintWidgetLight : I18TintWidget;
            I18SetTintFilter(part.layer, (tinted && homeWidget) ? kind : I18TintNone);
            I18ForceWidgetAppearance(part, darkWidget);
        }
    }
}

static BOOL I18ImageViewIsCurrent(UIView *imageView) {
    NSNumber *token = objc_getAssociatedObject(imageView, kImageGenerationKey);
    return token && token.unsignedIntegerValue == gStyleGeneration;
}

static void I18StyleIconView(UIView *iconView, BOOL force, BOOL animated) {
    if (!iconView) return;
    I18RefreshEligibility(iconView);
    UIView *imageView = I18ImageViewOf(iconView);
    if (imageView) {
        [gImageViews addObject:imageView];
        I18UpdateGeometry(imageView, NO);
        if (force || !I18ImageViewIsCurrent(imageView)) {
            I18StyleImageView(imageView);
        } else {
            // Contents or filters may have been replaced behind our back.
            I18VerifyLayerTree(imageView.layer);
        }
    }
    objc_setAssociatedObject(iconView, kStyledGenerationKey, @(gStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Cheap, and SpringBoard re-creates labels and badges on its own.
    I18StyleIconViewParts(iconView, imageView, animated);
}

/// Walks every window of SpringBoard's scene and styles each icon it finds,
/// including ones that never passed through the hooks above. It goes all
/// the way down: SpringBoard sometimes keeps an old image view inside the
/// current one while it cross-fades.
static void I18SweepView(UIView *view, int depth) {
    if (!view || depth > 40) return;
    if (gIconViewClass && [view isKindOfClass:gIconViewClass]) {
        [gIconViews addObject:view];
        I18StyleIconView(view, YES, NO);
    } else if (gIconImageViewClass && [view isKindOfClass:gIconImageViewClass]) {
        [gImageViews addObject:view];
        I18StyleImageView(view);
    }
    for (UIView *sub in view.subviews) {
        I18SweepView(sub, depth + 1);
    }
}

void I18SweepHomeScreen(void) {
    UIWindow *home = I18HomeScreenWindow();
    UIWindowScene *scene = home.windowScene;
    NSArray<UIWindow *> *windows = scene ? scene.windows : (home ? @[home] : @[]);
    for (UIWindow *window in windows) {
        if (window.hidden || I18ClassNameContains(window, @"I18")) continue;
        I18SweepView(window, 0);
        // Layers SpringBoard copied (snapshots, animation copies) carry a
        // copy of our filter that nothing else would ever update.
        I18FixTintFiltersInTree(window.layer);
    }
}

static NSUInteger gSweepToken;

void I18ScheduleSweep(NSTimeInterval delay) {
    NSUInteger token = ++gSweepToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != gSweepToken) return; // something newer is pending
        I18SweepHomeScreen();
    });
}

#pragma mark - Public entry points

void I18ApplyLook(BOOL animated) {
    I18SetCurrentLook([I18Settings shared].look);
    gStyleGeneration++;

    // One cross-fade per icon covers contents, filters and clock hands.
    if (animated) {
        for (UIView *iconView in gIconViews.allObjects) {
            if (!iconView.window) continue;
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = 0.32;
            fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [iconView.layer addAnimation:fade forKey:@"i18.look"];
        }
    }

    I18ReprocessAllContents(NO);
    // Every layer that was ever tinted, wherever it is now: tint on or off.
    I18RefreshTintFilters();
    for (UIView *imageView in gImageViews.allObjects) {
        I18StyleImageView(imageView);
    }
    for (UIView *iconView in gIconViews.allObjects) {
        objc_setAssociatedObject(iconView, kStyledGenerationKey, @(gStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        I18StyleIconViewParts(iconView, I18ImageViewOf(iconView), NO);
    }
    I18SweepHomeScreen();
    I18ScheduleSweep(0.6);
    I18PostChangedNotification();
}

void I18ApplyTint(void) {
    if (I18CurrentLook() != I18LookTinted) return;
    // Called for every slider movement: only the filters are swapped here,
    // on every layer that carries the tint (not just the ones we can find
    // through the icon views right now).
    I18RefreshTintFilters();
    I18PostChangedNotification();
    // Once the slider rests, a full pass catches anything that was off screen.
    I18ScheduleSweep(0.35);
}

void I18ApplyIconSize(BOOL animated) {
    NSArray<UIView *> *iconViews = gIconViews.allObjects;
    void (^changes)(void) = ^{
        for (UIView *iconView in iconViews) {
            I18RefreshEligibility(iconView);
            UIView *imageView = I18ImageViewOf(iconView);
            if (imageView) I18UpdateGeometry(imageView, NO);
            I18StyleIconViewParts(iconView, imageView, animated);
        }
    };
    if (!animated) {
        changes();
        return;
    }
    // iOS 18 grows and shrinks the icons with a soft, unhurried spring.
    [UIView animateWithDuration:0.62
                          delay:0.0
         usingSpringWithDamping:0.92
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:changes
                     completion:^(__unused BOOL finished) {
        // Icon views that were laid out again during the animation.
        I18ScheduleSweep(0.1);
    }];
}

UIWindow *I18HomeScreenWindow(void) {
    UIWindow *fallback = nil;
    for (UIView *iconView in gIconViews.allObjects) {
        UIWindow *window = iconView.window;
        if (!window || window.hidden) continue;
        if (I18IsLargeEligible(iconView)) return window;
        if (!fallback) fallback = window;
    }
    return fallback;
}

static __weak UIWindow *gHiddenWindow;

void I18SetHomeScreenContentHidden(BOOL hidden, BOOL animated) {
    UIWindow *window = hidden ? I18HomeScreenWindow() : (gHiddenWindow ?: I18HomeScreenWindow());
    if (!window) return;
    if (hidden) gHiddenWindow = window;
    CGFloat alpha = hidden ? 0.0 : 1.0;
    if (!animated) {
        window.alpha = alpha;
        return;
    }
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        window.alpha = alpha;
    } completion:nil];
}

static void I18SendBool(id target, NSString *selectorName, BOOL value) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(target, NSSelectorFromString(selectorName), value);
}

static void I18SendBoolBool(id target, NSString *selectorName, BOOL first, BOOL second) {
    ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(target, NSSelectorFromString(selectorName), first, second);
}

void I18EndHomeScreenEditing(void) {
    Class controllerClass = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    id controller = [controllerClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(controllerClass, shared) : nil;
    id manager = I18Call(controller, @"iconManager");

    NSMutableArray *targets = [NSMutableArray array];
    if (manager) [targets addObject:manager];
    if (controller) [targets addObject:controller];
    for (id target in targets) {
        if ([target respondsToSelector:NSSelectorFromString(@"setEditing:animated:")]) {
            I18SendBoolBool(target, @"setEditing:animated:", NO, YES);
            return;
        }
        if ([target respondsToSelector:NSSelectorFromString(@"setEditing:")]) {
            I18SendBool(target, @"setEditing:", NO);
            return;
        }
        if ([target respondsToSelector:NSSelectorFromString(@"setIsEditing:animated:")]) {
            I18SendBoolBool(target, @"setIsEditing:animated:", NO, YES);
            return;
        }
        if ([target respondsToSelector:NSSelectorFromString(@"setIsEditing:")]) {
            I18SendBool(target, @"setIsEditing:", NO);
            return;
        }
    }
}

#pragma mark - Hooks: SBIconImageView

static IMP oIV_didMoveToWindow, oIV_updateImageAnimated, oIV_didAddSubview;

static void hIV_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oIV_didMoveToWindow)(self, _cmd);
    if (!self.window) return;
    [gImageViews addObject:self];
    I18StyleImageView(self);
    UIView *iconView = I18IconViewContaining(self);
    if (iconView) {
        I18RefreshEligibility(iconView);
        I18UpdateGeometry(self, NO);
    }
}

static IMP oIV_didMoveToSuperview;

static void hIV_didMoveToSuperview(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oIV_didMoveToSuperview)(self, _cmd);
    // Recycled image views change parents without leaving the window.
    if (self.window && self.superview) {
        [gImageViews addObject:self];
        I18StyleImageView(self);
    }
}

static void hIV_updateImageAnimated(UIView *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))oIV_updateImageAnimated)(self, _cmd, animated);
    if (self.window) I18StyleImageView(self);
}

static void hIV_didAddSubview(UIView *self, SEL _cmd, UIView *subview) {
    ((void (*)(id, SEL, UIView *))oIV_didAddSubview)(self, _cmd, subview);
    if (subview) I18AdoptLayerTree(subview.layer, I18ClassNameContains(self, @"Clock"));
}

#pragma mark - Hooks: SBIconView

static IMP oV_layoutSubviews, oV_didMoveToWindow;

static void hV_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oV_layoutSubviews)(self, _cmd);
    I18StyleIconView(self, NO, NO);
}

static void hV_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oV_didMoveToWindow)(self, _cmd);
    UIWindow *window = self.window;
    if (!window) return;
    [gIconViews addObject:self];
    I18StyleIconView(self, NO, NO);
    if (I18IsLargeEligible(self)) I18InstallSceneHelpers(window);
}

static IMP oV_didMoveToSuperview;

/// An icon view moved between a page and somewhere else (drag, folder):
/// large size follows where it is now.
static void hV_didMoveToSuperview(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oV_didMoveToSuperview)(self, _cmd);
    if (!self.window || !self.superview) return;
    BOOL before = I18IsLargeEligible(self);
    I18RefreshEligibility(self);
    if (before == I18IsLargeEligible(self)) return;
    UIView *imageView = I18ImageViewOf(self);
    if (imageView) I18UpdateGeometry(imageView, NO);
    I18StyleIconViewParts(self, imageView, NO);
}

#pragma mark - Hooks: app switcher icons

/// The small app icons above the cards of the app switcher are plain image
/// views. They get the same layer treatment as home screen icons, so they
/// show the chosen look too.
static IMP oUIV_didMoveToWindow;
static const void *kSwitcherCheckedKey = &kSwitcherCheckedKey;

static BOOL I18InSwitcher(UIView *view) {
    // Parts of an app icon (its badge, its delete button) are never one of
    // the switcher's own icons, even while the icon itself is shown inside
    // the switcher for the launch / close animation.
    if (I18ClassNameContains(view, @"Badge") || I18ClassNameContains(view, @"Accessory")) return NO;
    BOOL switcher = NO;
    int depth = 0;
    for (UIView *current = view.superview; current && depth < 12; current = current.superview, depth++) {
        if (gIconViewClass && [current isKindOfClass:gIconViewClass]) return NO;
        if (gIconImageViewClass && [current isKindOfClass:gIconImageViewClass]) return NO;
        if (I18ClassNameContains(current, @"Badge") || I18ClassNameContains(current, @"Accessory")) return NO;
        if (I18ClassNameContains(current, @"Switcher")) switcher = YES;
    }
    return switcher;
}

static BOOL I18LooksLikeAppIcon(UIImageView *view) {
    UIImage *image = view.image;
    CGSize size = image ? image.size : view.bounds.size;
    if (image && image.renderingMode == UIImageRenderingModeAlwaysTemplate) return NO; // symbols
    return size.width >= 16.0 && size.width <= 72.0 && fabs(size.width - size.height) < 2.0;
}

static void I18CheckSwitcherImageView(UIImageView *view, BOOL retry) {
    if (!view.window || I18ClassNameContains(view.window, @"I18")) return;
    if (!I18InSwitcher(view)) return;
    if (!I18LooksLikeAppIcon(view)) {
        // Image or size not there yet: look once more on the next pass.
        if (retry) {
            __weak UIImageView *weakView = view;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageView *strongView = weakView;
                if (strongView) I18CheckSwitcherImageView(strongView, NO);
            });
        }
        return;
    }
    objc_setAssociatedObject(view, kSwitcherCheckedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gImageViews addObject:view];
    I18StyleImageView(view);
}

static void hUIV_didMoveToWindow(UIImageView *self, SEL _cmd) {
    ((void (*)(id, SEL))oUIV_didMoveToWindow)(self, _cmd);
    if (!self.window) return;
    if (objc_getAssociatedObject(self, kSwitcherCheckedKey)) {
        if (I18InSwitcher(self)) I18StyleImageView(self);
        return;
    }
    I18CheckSwitcherImageView(self, YES);
}

static IMP oUIV_setImage;

/// The switcher sets the icon image after the view is on screen.
static void hUIV_setImage(UIImageView *self, SEL _cmd, UIImage *image) {
    ((void (*)(id, SEL, UIImage *))oUIV_setImage)(self, _cmd, image);
    if (!image || !self.window) return;
    if (objc_getAssociatedObject(self, kSwitcherCheckedKey)) return; // adopted: new images convert by themselves
    CGSize size = image.size;
    if (size.width < 16.0 || size.width > 72.0 || fabs(size.width - size.height) > 2.0) return;
    I18CheckSwitcherImageView(self, NO);
}

static IMP oSWC_didMoveToWindow, oSWC_layoutSubviews;

/// SpringBoard's own icon container in the switcher header.
static void I18StyleSwitcherContainer(UIView *view) {
    if (!view.window) return;
    [gImageViews addObject:view];
    I18StyleImageView(view);
}

static void hSWC_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oSWC_didMoveToWindow)(self, _cmd);
    I18StyleSwitcherContainer(self);
}

static void hSWC_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oSWC_layoutSubviews)(self, _cmd);
    if (!I18ImageViewIsCurrent(self)) I18StyleSwitcherContainer(self);
}

#pragma mark - Hooks: SBRootFolderView

static IMP oRF_layoutSubviews, oRF_setEditingAnimated;

static void hRF_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oRF_layoutSubviews)(self, _cmd);
    I18SyncEditButton(self);
}

static void hRF_setEditingAnimated(UIView *self, SEL _cmd, BOOL editing, BOOL animated) {
    ((void (*)(id, SEL, BOOL, BOOL))oRF_setEditingAnimated)(self, _cmd, editing, animated);
    I18EditModeChanged(self, editing);
}

#pragma mark - Install

void I18InstallHomeScreenHooks(void) {
    gIconViews = [NSHashTable weakObjectsHashTable];
    gImageViews = [NSHashTable weakObjectsHashTable];
    gIconViewClass = objc_getClass("SBIconView");
    gIconImageViewClass = objc_getClass("SBIconImageView");
    I18SetCurrentLook([I18Settings shared].look);
    I18InstallFilterHooks();
    I18InstallEditButtonHooks();

    Class imageView = gIconImageViewClass;
    I18HookMethod(imageView, @selector(didMoveToWindow), (IMP)hIV_didMoveToWindow, &oIV_didMoveToWindow);
    I18HookMethod(imageView, NSSelectorFromString(@"updateImageAnimated:"), (IMP)hIV_updateImageAnimated, &oIV_updateImageAnimated);
    I18HookMethod(imageView, @selector(didAddSubview:), (IMP)hIV_didAddSubview, &oIV_didAddSubview);
    I18HookMethod(imageView, @selector(didMoveToSuperview), (IMP)hIV_didMoveToSuperview, &oIV_didMoveToSuperview);

    // Geometry hooks only make sense as a set.
    if (class_getInstanceMethod(imageView, @selector(setFrame:)) && class_getInstanceMethod(imageView, @selector(setBounds:)) &&
        class_getInstanceMethod(imageView, @selector(setCenter:)) && class_getInstanceMethod(imageView, @selector(setTransform:))) {
        I18HookMethod(imageView, @selector(setBounds:), (IMP)hIV_setBounds, &oIV_setBounds);
        I18HookMethod(imageView, @selector(setCenter:), (IMP)hIV_setCenter, &oIV_setCenter);
        I18HookMethod(imageView, @selector(setTransform:), (IMP)hIV_setTransform, &oIV_setTransform);
        I18HookMethod(imageView, @selector(setFrame:), (IMP)hIV_setFrame, &oIV_setFrame);
    }

    I18HookMethod(gIconViewClass, @selector(layoutSubviews), (IMP)hV_layoutSubviews, &oV_layoutSubviews);
    I18HookMethod(gIconViewClass, @selector(didMoveToWindow), (IMP)hV_didMoveToWindow, &oV_didMoveToWindow);
    I18HookMethod(gIconViewClass, @selector(didMoveToSuperview), (IMP)hV_didMoveToSuperview, &oV_didMoveToSuperview);

    // "- (void)setLabelHidden:(BOOL)" with a matching getter, or nothing.
    SEL labelSel = NSSelectorFromString(@"setLabelHidden:");
    Method labelMethod = gIconViewClass ? class_getInstanceMethod(gIconViewClass, labelSel) : NULL;
    if (labelMethod && method_getNumberOfArguments(labelMethod) == 3 &&
        ([gIconViewClass instancesRespondToSelector:NSSelectorFromString(@"isLabelHidden")] ||
         [gIconViewClass instancesRespondToSelector:NSSelectorFromString(@"labelHidden")])) {
        char argType[16] = {0};
        method_getArgumentType(labelMethod, 2, argType, sizeof(argType));
        if (argType[0] == 'B' || argType[0] == 'c') {
            I18HookMethod(gIconViewClass, labelSel, (IMP)hV_setLabelHidden, &oV_setLabelHidden);
        }
    }

    // Only hooked when it really is "- (CGRect)iconImageFrame".
    SEL frameSel = NSSelectorFromString(@"iconImageFrame");
    Method frameMethod = gIconViewClass ? class_getInstanceMethod(gIconViewClass, frameSel) : NULL;
    if (frameMethod) {
        char returnType[64] = {0};
        method_getReturnType(frameMethod, returnType, sizeof(returnType));
        if (method_getNumberOfArguments(frameMethod) == 2 && strncmp(returnType, "{CGRect=", 8) == 0) {
            I18HookMethod(gIconViewClass, frameSel, (IMP)hV_iconImageFrame, &oV_iconImageFrame);
        }
    }

    I18HookMethod([UIImageView class], @selector(didMoveToWindow), (IMP)hUIV_didMoveToWindow, &oUIV_didMoveToWindow);
    I18HookMethod([UIImageView class], @selector(setImage:), (IMP)hUIV_setImage, &oUIV_setImage);
    for (NSString *name in @[@"SBFluidSwitcherIconImageContainerView", @"SBAppSwitcherIconView", @"SBFluidSwitcherItemContainerHeaderIconView"]) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) continue;
        IMP *window = &oSWC_didMoveToWindow, *layout = &oSWC_layoutSubviews;
        if (*window) break; // one class is enough (they share the IMP slots)
        I18HookMethod(cls, @selector(didMoveToWindow), (IMP)hSWC_didMoveToWindow, window);
        I18HookMethod(cls, @selector(layoutSubviews), (IMP)hSWC_layoutSubviews, layout);
    }

    Class rootFolderView = objc_getClass("SBRootFolderView");
    I18HookMethod(rootFolderView, @selector(layoutSubviews), (IMP)hRF_layoutSubviews, &oRF_layoutSubviews);
    I18HookMethod(rootFolderView, NSSelectorFromString(@"setEditing:animated:"), (IMP)hRF_setEditingAnimated, &oRF_setEditingAnimated);
}
