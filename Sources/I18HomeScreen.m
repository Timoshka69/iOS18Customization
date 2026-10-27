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
static const void *kLabelMaskKey = &kLabelMaskKey;
static const void *kShiftKey = &kShiftKey;
static const void *kOriginalGravityKey = &kOriginalGravityKey;

static NSString *const kOriginalBackgroundKey = @"i18OriginalBackground";
static NSString *const kOriginalFillKey = @"i18OriginalFill";

#pragma mark - Geometry record

/// What SpringBoard asked for, before the large-icon scale is applied.
@interface I18Geometry : NSObject
@property (nonatomic) CGSize size;
@property (nonatomic) CGPoint center;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic) BOOL valid;
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

static BOOL I18IsWidgetIconView(UIView *iconView) {
    id icon = I18Call(iconView, @"icon");
    if (!icon) return NO;
    if (I18BoolCall(icon, @"isWidgetIcon") || I18BoolCall(icon, @"isWidgetStackIcon")) return YES;
    return I18ClassNameContains(icon, @"Widget");
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

static BOOL I18ComputeLargeEligible(UIView *iconView) {
    if (I18IsWidgetIconView(iconView)) return NO;
    id location = I18Call(iconView, @"location") ?: I18Call(iconView, @"iconLocation");
    if ([location isKindOfClass:[NSString class]]) {
        NSString *name = location;
        if ([name hasPrefix:@"SBIconLocationRoot"]) return YES;
        if ([name rangeOfString:@"Dock"].location != NSNotFound) return YES;
        return NO;
    }
    for (UIView *view = iconView.superview; view; view = view.superview) {
        if (I18ClassNameContains(view, @"RootIconListView") || I18ClassNameContains(view, @"DockIconListView")) return YES;
        if (I18ClassNameContains(view, @"Library")) return NO;
    }
    return NO;
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
    return (iconView && I18IsLargeEligible(iconView)) ? kLargeIconScale : 1.0;
}

static IMP oIV_setFrame, oIV_setBounds, oIV_setCenter, oIV_setTransform;
static BOOL gGeometryPassthrough;

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

static void I18ApplyGeometry(UIView *view, I18Geometry *geometry, CGFloat scale) {
    if (!geometry.valid) return;
    gGeometryPassthrough = YES;

    CGRect bounds = view.bounds;
    bounds.size = geometry.size;
    I18CallSetBounds(view, bounds);

    // Grow downwards into the (now hidden) label area, top edge stays put.
    CGPoint center = geometry.center;
    center.y += geometry.size.height * (scale - 1.0) * 0.5;
    I18CallSetCenter(view, center);

    CGAffineTransform transform = geometry.transform;
    if (fabs(scale - 1.0) > 0.001) {
        transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), geometry.transform);
    }
    I18CallSetTransform(view, transform);

    gGeometryPassthrough = NO;
    geometry.applied = scale;

    CALayer *layer = view.layer;
    if (scale > 1.001) {
        layer.minificationFilter = kCAFilterTrilinear;
        if (!objc_getAssociatedObject(layer, kOriginalGravityKey)) {
            objc_setAssociatedObject(layer, kOriginalGravityKey, layer.contentsGravity ?: kCAGravityResize, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        layer.contentsGravity = kCAGravityResize;
    } else {
        NSString *gravity = objc_getAssociatedObject(layer, kOriginalGravityKey);
        if (gravity) {
            layer.contentsGravity = gravity;
            objc_setAssociatedObject(layer, kOriginalGravityKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }
}

static void I18EnsureGeometryBase(UIView *view, I18Geometry *geometry) {
    if (geometry.valid) return;
    geometry.size = view.bounds.size;
    geometry.center = view.center;
    geometry.transform = view.transform;
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

static BOOL I18RectsClose(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.25 && fabs(a.origin.y - b.origin.y) < 0.25 &&
           fabs(a.size.width - b.size.width) < 0.25 && fabs(a.size.height - b.size.height) < 0.25;
}

static void hIV_setFrame(UIView *self, SEL _cmd, CGRect frame) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !oIV_setBounds || !oIV_setCenter || !oIV_setTransform) {
        ((void (*)(id, SEL, CGRect))oIV_setFrame)(self, _cmd, frame);
        return;
    }
    CGFloat scale = I18TargetScale(self);
    BOOL scaled = geometry && geometry.applied > 1.001;
    if (!scaled && scale <= 1.001) {
        ((void (*)(id, SEL, CGRect))oIV_setFrame)(self, _cmd, frame);
        if (geometry) {
            geometry.size = self.bounds.size;
            geometry.center = self.center;
            geometry.valid = YES;
        }
        return;
    }
    // Someone re-assigning the frame they just read back: nothing changes.
    if (scaled && I18RectsClose(frame, self.frame)) return;

    geometry = I18GeometryOf(self);
    if (!geometry.valid) geometry.transform = self.transform;
    geometry.size = frame.size;
    geometry.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    geometry.valid = YES;
    I18ApplyGeometry(self, geometry, scale);
}

static void hIV_setBounds(UIView *self, SEL _cmd, CGRect bounds) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !geometry || !geometry.valid) {
        ((void (*)(id, SEL, CGRect))oIV_setBounds)(self, _cmd, bounds);
        if (!gGeometryPassthrough && geometry) geometry.size = bounds.size;
        return;
    }
    BOOL sizeChanged = !CGSizeEqualToSize(geometry.size, bounds.size);
    geometry.size = bounds.size;
    ((void (*)(id, SEL, CGRect))oIV_setBounds)(self, _cmd, bounds);
    // The large-icon offset depends on the height, keep it in sync.
    if (sizeChanged && geometry.applied > 1.001) I18ApplyGeometry(self, geometry, geometry.applied);
}

static void hIV_setCenter(UIView *self, SEL _cmd, CGPoint center) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !geometry || !geometry.valid || geometry.applied <= 1.001) {
        ((void (*)(id, SEL, CGPoint))oIV_setCenter)(self, _cmd, center);
        if (!gGeometryPassthrough && geometry) geometry.center = center;
        return;
    }
    CGPoint current = self.center;
    if (fabs(current.x - center.x) < 0.25 && fabs(current.y - center.y) < 0.25) return;
    geometry.center = center;
    I18ApplyGeometry(self, geometry, geometry.applied);
}

static void hIV_setTransform(UIView *self, SEL _cmd, CGAffineTransform transform) {
    I18Geometry *geometry = objc_getAssociatedObject(self, kGeometryKey);
    if (gGeometryPassthrough || !geometry || !geometry.valid || geometry.applied <= 1.001) {
        ((void (*)(id, SEL, CGAffineTransform))oIV_setTransform)(self, _cmd, transform);
        if (!gGeometryPassthrough && geometry) geometry.transform = transform;
        return;
    }
    if (CGAffineTransformEqualToTransform(transform, self.transform)) return;
    geometry.transform = transform;
    I18ApplyGeometry(self, geometry, geometry.applied);
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

    CGFloat dx = 0.0;
    I18Geometry *geometry = objc_getAssociatedObject(imageView, kGeometryKey);
    if (geometry.valid && geometry.applied > 1.001 && view.superview && imageView.superview) {
        CGFloat half = geometry.size.width * (geometry.applied - 1.0) * 0.5;
        CGFloat baseEdge = geometry.center.x + (rightCorner ? 0.5 : -0.5) * geometry.size.width;
        CGFloat largeEdge = baseEdge + (rightCorner ? half : -half);
        CGPoint center = [view.superview convertPoint:view.center toView:imageView.superview];
        if (fabs(center.x - baseEdge) < fabs(center.x - largeEdge)) dx = rightCorner ? half : -half;
    }

    CGAffineTransform shift = CGAffineTransformMakeTranslation(dx, 0.0);
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

static void I18TintBadgeColor(float rgb[3]) {
    I18Settings *settings = [I18Settings shared];
    float tint[3];
    [settings tintRGB:tint];
    float h, s, v;
    I18FXRGBToHSV(tint, &h, &s, &v);
    I18FXHSVToRGB(h, MIN(s, 0.85f), MAX(v, 0.82f), rgb);
}

static void I18StyleImageView(UIView *imageView) {
    if (!imageView) return;
    I18Look look = I18CurrentLook();
    BOOL clock = I18ClassNameContains(imageView, @"Clock");

    I18AdoptLayerTree(imageView.layer, clock);

    if (look == I18LookTinted) {
        float rgb[3];
        [[I18Settings shared] tintRGB:rgb];
        I18FXMatrix matrix = I18FXIconTintMatrix(rgb);
        I18SetMatrixFilter(imageView.layer, &matrix);
    } else {
        I18SetMatrixFilter(imageView.layer, NULL);
    }

    if (clock) {
        CGSize size = imageView.layer.bounds.size;
        I18StyleClockParts(imageView.layer, size.width * size.height, look != I18LookStock, 0);
    }

    if (I18ClassNameContains(imageView, @"Folder")) {
        imageView.overrideUserInterfaceStyle = look == I18LookStock ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleDark;
    }
}

static void I18StyleIconViewParts(UIView *iconView, UIView *imageView, BOOL animated) {
    I18Settings *settings = [I18Settings shared];
    I18Look look = I18CurrentLook();
    BOOL tinted = look == I18LookTinted;
    BOOL large = settings.largeIcons && I18IsLargeEligible(iconView);
    BOOL widget = I18IsWidgetIconView(iconView);

    float rgb[3];
    [settings tintRGB:rgb];
    float badgeRGB[3];
    I18TintBadgeColor(badgeRGB);
    I18FXMatrix badgeMatrix = I18FXBadgeTintMatrix(badgeRGB);
    I18FXMatrix widgetMatrix = I18FXWidgetTintMatrix(rgb, !settings.systemIsDark);

    for (UIView *part in I18IconViewParts(iconView, imageView)) {
        if (I18IsLabel(part)) {
            I18SetLabelHidden(part, large, animated);
        } else if (I18IsBadge(part)) {
            I18SetMatrixFilter(part.layer, tinted ? &badgeMatrix : NULL);
            if (imageView) I18ShiftCornerView(part, imageView, YES);
        } else if (I18IsCloseBox(part)) {
            if (imageView) I18ShiftCornerView(part, imageView, NO);
        } else if (widget) {
            I18SetMatrixFilter(part.layer, tinted ? &widgetMatrix : NULL);
        }
    }
}

static void I18StyleIconView(UIView *iconView, BOOL force, BOOL animated) {
    if (!iconView) return;
    I18RefreshEligibility(iconView);
    UIView *imageView = I18ImageViewOf(iconView);
    if (imageView) {
        [gImageViews addObject:imageView];
        I18UpdateGeometry(imageView, NO);
    }

    NSNumber *styled = objc_getAssociatedObject(iconView, kStyledGenerationKey);
    if (force || styled.unsignedIntegerValue != gStyleGeneration) {
        objc_setAssociatedObject(iconView, kStyledGenerationKey, @(gStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        I18StyleImageView(imageView);
    }
    // Cheap, and SpringBoard re-creates labels and badges on its own.
    I18StyleIconViewParts(iconView, imageView, animated);
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
    for (UIView *imageView in gImageViews.allObjects) {
        I18StyleImageView(imageView);
    }
    for (UIView *iconView in gIconViews.allObjects) {
        objc_setAssociatedObject(iconView, kStyledGenerationKey, @(gStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        I18StyleIconViewParts(iconView, I18ImageViewOf(iconView), NO);
    }
}

void I18ApplyTint(void) {
    if (I18CurrentLook() != I18LookTinted) return;
    gStyleGeneration++;
    // Called for every slider movement: only the filters are swapped here.
    float rgb[3];
    [[I18Settings shared] tintRGB:rgb];
    I18FXMatrix matrix = I18FXIconTintMatrix(rgb);
    for (UIView *imageView in gImageViews.allObjects) {
        I18SetMatrixFilter(imageView.layer, &matrix);
    }
    for (UIView *iconView in gIconViews.allObjects) {
        objc_setAssociatedObject(iconView, kStyledGenerationKey, @(gStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        I18StyleIconViewParts(iconView, I18ImageViewOf(iconView), NO);
    }
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
    [UIView animateWithDuration:0.5
                          delay:0.0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:changes
                     completion:nil];
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

#pragma mark - Hooks: SBRootFolderView

static IMP oRF_layoutSubviews, oRF_setEditingAnimated;

static void hRF_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))oRF_layoutSubviews)(self, _cmd);
    I18SyncEditButton(self);
}

static void hRF_setEditingAnimated(UIView *self, SEL _cmd, BOOL editing, BOOL animated) {
    ((void (*)(id, SEL, BOOL, BOOL))oRF_setEditingAnimated)(self, _cmd, editing, animated);
    I18SyncEditButton(self);
}

#pragma mark - Install

void I18InstallHomeScreenHooks(void) {
    gIconViews = [NSHashTable weakObjectsHashTable];
    gImageViews = [NSHashTable weakObjectsHashTable];
    gIconViewClass = objc_getClass("SBIconView");
    gIconImageViewClass = objc_getClass("SBIconImageView");
    I18SetCurrentLook([I18Settings shared].look);

    Class imageView = gIconImageViewClass;
    I18HookMethod(imageView, @selector(didMoveToWindow), (IMP)hIV_didMoveToWindow, &oIV_didMoveToWindow);
    I18HookMethod(imageView, NSSelectorFromString(@"updateImageAnimated:"), (IMP)hIV_updateImageAnimated, &oIV_updateImageAnimated);
    I18HookMethod(imageView, @selector(didAddSubview:), (IMP)hIV_didAddSubview, &oIV_didAddSubview);

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

    Class rootFolderView = objc_getClass("SBRootFolderView");
    I18HookMethod(rootFolderView, @selector(layoutSubviews), (IMP)hRF_layoutSubviews, &oRF_layoutSubviews);
    I18HookMethod(rootFolderView, NSSelectorFromString(@"setEditing:animated:"), (IMP)hRF_setEditingAnimated, &oRF_setEditingAnimated);
}
