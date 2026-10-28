//
//  I18Contents.m
//  iOS18Customization
//
//  Instead of fighting SpringBoard's icon caches (which differ between 15.x
//  builds) the tweak works one level lower: the layers of SBIconImageView get
//  a private subclass that converts every CGImage put into them. SpringBoard
//  keeps its untouched images in its caches, so switching back to "Light"
//  restores the stock icons instantly and nothing has to be invalidated.
//
//  The same subclass also adopts sublayers added later (cross-fade layers,
//  the pressed-state overlay, folder mini grids), which is what keeps the
//  icon from flashing its stock colours when it is pressed.
//

#import "I18Shared.h"

static const void *kOriginalContentsKey = &kOriginalContentsKey;
static const void *kClockFaceKey = &kClockFaceKey;
static const void *kSourceImageKey = &kSourceImageKey;
static const void *kDesiredFilterKey = &kDesiredFilterKey;

static NSString *const kManagedPrefix = @"I18Managed_";
static NSString *const kFilterName = @"i18ColorMatrix";

static NSHashTable<CALayer *> *gManagedLayers;
static NSCache *gImageCache;
static I18Look gCurrentLook = I18LookStock;

#pragma mark - Look

I18Look I18CurrentLook(void) {
    return gCurrentLook;
}

void I18SetCurrentLook(I18Look look) {
    gCurrentLook = look;
}

#pragma mark - Image conversion

static BOOL I18IsCGImage(id object) {
    return object && CFGetTypeID((__bridge CFTypeRef)object) == CGImageGetTypeID();
}

/// If `contents` is an image this file produced, returns the image it was
/// made from, otherwise returns `contents` itself.
static id I18SourceContents(id contents) {
    if (!I18IsCGImage(contents)) return contents;
    id source = objc_getAssociatedObject(contents, kSourceImageKey);
    return source ?: contents;
}

static id I18ConvertedImage(id source, I18Look look, BOOL clockFace, BOOL busyDark) {
    if (look == I18LookStock || !I18IsCGImage(source)) return source;

    CGImageRef image = (__bridge CGImageRef)source;
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width < 8 || height < 8 || width > 1400 || height > 1400) return source;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gImageCache = [[NSCache alloc] init];
        gImageCache.countLimit = 900;
    });
    BOOL tinted = look == I18LookTinted;
    NSString *key = [NSString stringWithFormat:@"%p:%d:%d:%d", image, tinted, clockFace, busyDark];
    id cached = [gImageCache objectForKey:key];
    if ([cached isKindOfClass:[NSArray class]]) return source; // known to need no change
    if (cached) return cached;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return source;

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    uint8_t *pixels = CGBitmapContextGetData(context);
    int bytesPerRow = (int)CGBitmapContextGetBytesPerRow(context);

    int flags = (clockFace ? I18FXFlagClock : 0) | (tinted ? I18FXFlagStrongDim : 0) | (busyDark ? I18FXFlagBusyDark : 0);
    I18FXResult result = I18FXMakeDarkWithFlags(pixels, (int)width, (int)height, bytesPerRow, flags);
    if (tinted) {
        // Icons with a plate: dark plate, glyph in the tint. Pictures without
        // one: only recoloured (still a dark tile), never cut apart.
        if (result == I18FXUnsupported) I18FXMakeTintReadyArt(pixels, (int)width, (int)height, bytesPerRow);
        else I18FXMakeTintReady(pixels, (int)width, (int)height, bytesPerRow);
    } else if (result == I18FXUntouched || result == I18FXUnsupported) {
        // Dark look: an icon without a clean plate stays exactly as it is.
        CGContextRelease(context);
        // Keep the source alive together with the entry (see below).
        [gImageCache setObject:@[source] forKey:key];
        return source;
    }

    CGImageRef converted = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!converted) return source;

    id output = (__bridge_transfer id)converted;
    // The converted image keeps its source alive, so the pointer used in the
    // cache key can never be reused while the entry exists.
    objc_setAssociatedObject(output, kSourceImageKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gImageCache setObject:output forKey:key];
    return output;
}

#pragma mark - Managed layer subclass

static BOOL I18IsManagedClass(Class cls) {
    return cls && strncmp(class_getName(cls), "I18Managed_", 11) == 0;
}

static Class I18UnmanagedSuperclass(id object) {
    Class cls = object_getClass(object);
    while (cls && !I18IsManagedClass(cls)) cls = class_getSuperclass(cls);
    return cls ? class_getSuperclass(cls) : [CALayer class];
}

static const void *kBusyDarkKey = &kBusyDarkKey;

void I18SetLayerBusyDark(CALayer *layer, BOOL busyDark) {
    if (!layer) return;
    BOOL current = [objc_getAssociatedObject(layer, kBusyDarkKey) boolValue];
    if (current == busyDark) return;
    objc_setAssociatedObject(layer, kBusyDarkKey, busyDark ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id I18DisplayContentsForLayer(CALayer *layer, id original) {
    if (!I18IsCGImage(original)) return original;
    BOOL clockFace = [objc_getAssociatedObject(layer, kClockFaceKey) boolValue];
    BOOL busyDark = [objc_getAssociatedObject(layer, kBusyDarkKey) boolValue] ||
                    (layer.superlayer && [objc_getAssociatedObject(layer.superlayer, kBusyDarkKey) boolValue]);
    return I18ConvertedImage(original, gCurrentLook, clockFace, busyDark);
}

static void I18Managed_setContents(CALayer *self, SEL _cmd, id contents) {
    id original = I18SourceContents(contents);
    objc_setAssociatedObject(self, kOriginalContentsKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id shown = I18DisplayContentsForLayer(self, original);
    struct objc_super sup = {self, I18UnmanagedSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, shown);
}

static void I18AdoptLayer(CALayer *layer, BOOL clock);

static void I18AdoptInsertedLayer(CALayer *parent, CALayer *child) {
    if (!child || ![NSThread isMainThread]) return;
    BOOL clock = [objc_getAssociatedObject(parent, kClockFaceKey) boolValue];
    I18AdoptLayerTree(child, clock);
}

static void I18Managed_addSublayer(CALayer *self, SEL _cmd, CALayer *layer) {
    struct objc_super sup = {self, I18UnmanagedSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, CALayer *))objc_msgSendSuper)(&sup, _cmd, layer);
    I18AdoptInsertedLayer(self, layer);
}

static void I18Managed_insertAtIndex(CALayer *self, SEL _cmd, CALayer *layer, unsigned int index) {
    struct objc_super sup = {self, I18UnmanagedSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, CALayer *, unsigned int))objc_msgSendSuper)(&sup, _cmd, layer, index);
    I18AdoptInsertedLayer(self, layer);
}

static void I18Managed_insertRelative(CALayer *self, SEL _cmd, CALayer *layer, CALayer *sibling) {
    struct objc_super sup = {self, I18UnmanagedSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, CALayer *, CALayer *))objc_msgSendSuper)(&sup, _cmd, layer, sibling);
    I18AdoptInsertedLayer(self, layer);
}

static Class I18Managed_class(id self, SEL _cmd) {
    return I18UnmanagedSuperclass(self);
}

static Class I18ManagedClassFor(Class base) {
    NSString *name = [kManagedPrefix stringByAppendingString:NSStringFromClass(base)];
    Class managed = objc_getClass(name.UTF8String);
    if (managed) return managed;

    managed = objc_allocateClassPair(base, name.UTF8String, 0);
    if (!managed) return Nil;

    class_addMethod(managed, @selector(setContents:), (IMP)I18Managed_setContents, "v@:@");
    class_addMethod(managed, @selector(addSublayer:), (IMP)I18Managed_addSublayer, "v@:@");
    class_addMethod(managed, @selector(insertSublayer:atIndex:), (IMP)I18Managed_insertAtIndex, "v@:@I");
    class_addMethod(managed, @selector(insertSublayer:below:), (IMP)I18Managed_insertRelative, "v@:@@");
    class_addMethod(managed, @selector(insertSublayer:above:), (IMP)I18Managed_insertRelative, "v@:@@");
    class_addMethod(managed, @selector(class), (IMP)I18Managed_class, "#@:");
    objc_registerClassPair(managed);
    return managed;
}

static BOOL I18LayerCanBeAdopted(CALayer *layer) {
    const char *name = object_getClassName(layer);
    if (!name) return NO;
    // Layers that never carry an icon bitmap or that must not be subclassed.
    static const char *const skipped[] = {
        "NSKVONotifying_", "Backdrop", "Portal", "LayerHost", "Emitter", "Replicator", "Transform", "MTMaterial",
    };
    for (size_t i = 0; i < sizeof(skipped) / sizeof(skipped[0]); i++) {
        if (strstr(name, skipped[i])) return NO;
    }
    return YES;
}

static void I18AdoptLayer(CALayer *layer, BOOL clock) {
    if (I18IsManagedClass(object_getClass(layer))) {
        if (clock) objc_setAssociatedObject(layer, kClockFaceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!I18LayerCanBeAdopted(layer)) return;

    Class managed = I18ManagedClassFor(object_getClass(layer));
    if (!managed) return;

    id current = layer.contents;
    object_setClass(layer, managed);
    if (clock) objc_setAssociatedObject(layer, kClockFaceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (!gManagedLayers) gManagedLayers = [NSHashTable weakObjectsHashTable];
    [gManagedLayers addObject:layer];

    if (current) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.contents = current; // goes through I18Managed_setContents
        [CATransaction commit];
    }
}

void I18AdoptLayerTree(CALayer *layer, BOOL clock) {
    if (!layer) return;
    I18AdoptLayer(layer, clock);
    NSArray<CALayer *> *sublayers = [layer.sublayers copy];
    for (CALayer *sublayer in sublayers) {
        I18AdoptLayerTree(sublayer, clock);
    }
}

static void I18VerifyTintFilter(CALayer *layer);

static void I18VerifyLayer(CALayer *layer, int depth) {
    if (!layer || depth > 6) return;
    if (I18IsManagedClass(object_getClass(layer))) {
        id shown = layer.contents;
        if (I18IsCGImage(shown)) {
            id wanted = I18DisplayContentsForLayer(layer, I18SourceContents(shown));
            // Something put contents in without going through -setContents:,
            // or they belong to another look: run them through again.
            if (wanted != shown) layer.contents = shown;
        }
    }
    // Any layer that carries our tint (the icon itself, an old image view
    // SpringBoard keeps inside a cross-fade, a copy for an animation) must
    // show the current colour, never the one it was given earlier.
    I18VerifyTintFilter(layer);
    for (CALayer *sublayer in [layer.sublayers copy]) {
        I18VerifyLayer(sublayer, depth + 1);
    }
}

void I18VerifyLayerTree(CALayer *root) {
    if (!root) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    I18VerifyLayer(root, 0);
    [CATransaction commit];
}

void I18ReprocessAllContents(BOOL animated) {
    NSArray<CALayer *> *layers = gManagedLayers.allObjects;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in layers) {
        id original = objc_getAssociatedObject(layer, kOriginalContentsKey);
        if (!original) continue;
        if (animated && layer.superlayer) {
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = 0.32;
            fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [layer addAnimation:fade forKey:@"i18.contents"];
        }
        layer.contents = original;
    }
    [CATransaction commit];
}

#pragma mark - Colour matrix filter

// Same memory layout and type encoding as Core Animation's CAColorMatrix.
typedef struct CAColorMatrix {
    float m11, m12, m13, m14, m15;
    float m21, m22, m23, m24, m25;
    float m31, m32, m33, m34, m35;
    float m41, m42, m43, m44, m45;
} CAColorMatrix;

static const void *kTintKindKey = &kTintKindKey;
static const void *kTintGenerationKey = &kTintGenerationKey;
static const void *kOurFilterKey = &kOurFilterKey;

static NSHashTable<CALayer *> *gTintedLayers;
static NSUInteger gTintGeneration = 1;
static BOOL gFilterPassthrough;
static IMP oL_setFilters;

static NSValue *I18ColorMatrixValue(I18FXMatrix matrix) {
    CAColorMatrix cm;
    memcpy(&cm, matrix.m, sizeof(cm));
    SEL sel = NSSelectorFromString(@"valueWithCAColorMatrix:");
    if ([NSValue respondsToSelector:sel]) {
        return ((NSValue * (*)(Class, SEL, CAColorMatrix))objc_msgSend)([NSValue class], sel, cm);
    }
    return [NSValue valueWithBytes:&cm objCType:@encode(CAColorMatrix)];
}

id I18MakeMatrixFilter(I18FXMatrix matrix) {
    static Class filterClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        filterClass = NSClassFromString(@"CAFilter");
    });
    SEL make = NSSelectorFromString(@"filterWithType:");
    if (!filterClass || ![filterClass respondsToSelector:make]) return nil;
    id filter = ((id (*)(Class, SEL, NSString *))objc_msgSend)(filterClass, make, @"colorMatrix");
    if (!filter) return nil;
    @try {
        [filter setValue:kFilterName forKey:@"name"];
        [filter setValue:I18ColorMatrixValue(matrix) forKey:@"inputColorMatrix"];
    } @catch (__unused NSException *exception) {
        return nil;
    }
    objc_setAssociatedObject(filter, kOurFilterKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return filter;
}

static BOOL I18IsOurFilter(id filter) {
    if (!filter) return NO;
    if (objc_getAssociatedObject(filter, kOurFilterKey)) return YES;
    // Core Animation may hand back copies of the filter objects.
    SEL nameSel = @selector(name);
    if (![filter respondsToSelector:nameSel]) return NO;
    id name = ((id (*)(id, SEL))objc_msgSend)(filter, nameSel);
    return [name isKindOfClass:[NSString class]] && [name isEqualToString:kFilterName];
}

void I18TintBadgeColor(float rgb[3]) {
    float tint[3];
    [[I18Settings shared] tintRGB:tint];
    float h, s, v;
    I18FXRGBToHSV(tint, &h, &s, &v);
    I18FXHSVToRGB(h, MIN(s, 0.85f), MAX(v, 0.82f), rgb);
}

I18FXMatrix I18MatrixForTintKind(I18TintKind kind) {
    float rgb[3];
    [[I18Settings shared] tintRGB:rgb];
    switch (kind) {
        case I18TintWidget:
            return I18FXWidgetTintMatrix(rgb, false);
        case I18TintBadge: {
            float badge[3];
            I18TintBadgeColor(badge);
            return I18FXBadgeTintMatrix(badge);
        }
        default:
            return I18FXIconTintMatrix(rgb);
    }
}

static I18TintKind I18TintKindOf(CALayer *layer) {
    NSNumber *kind = objc_getAssociatedObject(layer, kTintKindKey);
    return kind ? (I18TintKind)kind.integerValue : I18TintNone;
}

static void I18CallSetFilters(CALayer *layer, NSArray *filters) {
    gFilterPassthrough = YES;
    @try {
        if (oL_setFilters) ((void (*)(id, SEL, NSArray *))oL_setFilters)(layer, NSSelectorFromString(@"setFilters:"), filters);
        else [layer setValue:filters forKey:@"filters"];
    } @catch (__unused NSException *exception) {
    }
    gFilterPassthrough = NO;
}

/// Puts the filter for `kind` (or none) at the end of the layer's filters,
/// keeping whatever SpringBoard has there itself.
static void I18InstallTintFilter(CALayer *layer, I18TintKind kind) {
    NSArray *current = I18ValueForKey(layer, @"filters");
    BOOL tinted = kind != I18TintNone && I18CurrentLook() == I18LookTinted;
    id filter = tinted ? I18MakeMatrixFilter(I18MatrixForTintKind(kind)) : nil;
    objc_setAssociatedObject(layer, kDesiredFilterKey, filter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(layer, kTintGenerationKey, @(gTintGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMutableArray *filters = [NSMutableArray array];
    BOOL hadOurs = NO;
    for (id existing in current) {
        if (I18IsOurFilter(existing)) hadOurs = YES;
        else [filters addObject:existing];
    }
    if (!filter && !hadOurs) return;
    if (filter) [filters addObject:filter];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    I18CallSetFilters(layer, filters.count ? filters : nil);
    [CATransaction commit];
}

void I18SetTintFilter(CALayer *layer, I18TintKind kind) {
    if (!layer) return;
    if (kind == I18TintNone) {
        if (!objc_getAssociatedObject(layer, kTintKindKey) && !objc_getAssociatedObject(layer, kDesiredFilterKey)) {
            // Never tinted by us: only clean up a filter copied onto it.
            NSArray *current = I18ValueForKey(layer, @"filters");
            BOOL ours = NO;
            for (id existing in current) ours = ours || I18IsOurFilter(existing);
            if (!ours) return;
        }
        objc_setAssociatedObject(layer, kTintKindKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gTintedLayers removeObject:layer];
    } else {
        objc_setAssociatedObject(layer, kTintKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gTintedLayers) gTintedLayers = [NSHashTable weakObjectsHashTable];
        [gTintedLayers addObject:layer];
    }
    I18InstallTintFilter(layer, kind);
}

static void I18VerifyTintFilter(CALayer *layer) {
    I18TintKind kind = I18TintKindOf(layer);
    id desired = objc_getAssociatedObject(layer, kDesiredFilterKey);
    if (kind == I18TintNone && !desired) return;
    NSNumber *generation = objc_getAssociatedObject(layer, kTintGenerationKey);
    BOOL stale = generation.unsignedIntegerValue != gTintGeneration;
    BOOL present = !desired;
    if (desired) {
        for (id filter in I18ValueForKey(layer, @"filters")) {
            if (filter == desired) present = YES;
        }
    }
    if (stale || !present) I18InstallTintFilter(layer, kind);
}

void I18RefreshTintFilters(void) {
    gTintGeneration++;
    NSArray<CALayer *> *layers = gTintedLayers.allObjects;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in layers) {
        I18InstallTintFilter(layer, I18TintKindOf(layer));
    }
    [CATransaction commit];
}

/// Every -setFilters: in SpringBoard passes here. SpringBoard replaces the
/// filters of icon layers now and then (screen on / off, pressed state) and
/// copies them onto other layers for its animations. Our tint is always put
/// back at the end of the list in the current colour, and a copy of it that
/// lands on another layer is brought up to date too.
static void hL_setFilters(CALayer *self, SEL _cmd, NSArray *filters) {
    if (gFilterPassthrough) {
        ((void (*)(id, SEL, NSArray *))oL_setFilters)(self, _cmd, filters);
        return;
    }
    id desired = objc_getAssociatedObject(self, kDesiredFilterKey);
    I18TintKind kind = I18TintKindOf(self);
    BOOL hasOurs = NO;
    for (id filter in filters) {
        if (I18IsOurFilter(filter)) {
            hasOurs = YES;
            break;
        }
    }
    if (!desired && kind == I18TintNone && !hasOurs) {
        ((void (*)(id, SEL, NSArray *))oL_setFilters)(self, _cmd, filters);
        return;
    }

    NSMutableArray *list = [NSMutableArray array];
    for (id filter in filters) {
        if (!I18IsOurFilter(filter)) [list addObject:filter];
    }
    // A copy of our filter on a layer we never tinted. SpringBoard copies
    // filters from the icon onto other layers (for example the label after
    // a launch) - those must not be coloured. Only a copy of the icon
    // picture itself (it shows one of our converted images) keeps the tint.
    BOOL showsOurImage = I18IsCGImage(self.contents) && objc_getAssociatedObject(self.contents, kSourceImageKey);
    if (kind == I18TintNone && hasOurs && showsOurImage && I18CurrentLook() == I18LookTinted) {
        // A copy for an animation: give it the current icon colour.
        kind = I18TintIcon;
        objc_setAssociatedObject(self, kTintKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gTintedLayers) gTintedLayers = [NSHashTable weakObjectsHashTable];
        [gTintedLayers addObject:self];
        desired = nil;
    }
    if (kind != I18TintNone && I18CurrentLook() == I18LookTinted) {
        NSNumber *generation = objc_getAssociatedObject(self, kTintGenerationKey);
        if (!desired || generation.unsignedIntegerValue != gTintGeneration) {
            desired = I18MakeMatrixFilter(I18MatrixForTintKind(kind));
            objc_setAssociatedObject(self, kDesiredFilterKey, desired, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, kTintGenerationKey, @(gTintGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (desired) [list addObject:desired];
    }
    ((void (*)(id, SEL, NSArray *))oL_setFilters)(self, _cmd, list.count ? list : nil);
}

void I18InstallFilterHooks(void) {
    I18HookMethod([CALayer class], NSSelectorFromString(@"setFilters:"), (IMP)hL_setFilters, &oL_setFilters);
}
