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

static id I18ConvertedImage(id source, I18Look look, BOOL clockFace) {
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
    NSString *key = [NSString stringWithFormat:@"%p:%d:%d", image, tinted, clockFace];
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

    int flags = (clockFace ? I18FXFlagClock : 0) | (tinted ? I18FXFlagStrongDim : 0);
    I18FXResult result = I18FXMakeDarkWithFlags(pixels, (int)width, (int)height, bytesPerRow, flags);
    if (tinted) {
        I18FXMakeTintReady(pixels, (int)width, (int)height, bytesPerRow);
    } else if (result == I18FXUntouched) {
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

static id I18DisplayContentsForLayer(CALayer *layer, id original) {
    if (!I18IsCGImage(original)) return original;
    BOOL clockFace = [objc_getAssociatedObject(layer, kClockFaceKey) boolValue];
    return I18ConvertedImage(original, gCurrentLook, clockFace);
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
    return filter;
}

void I18SetMatrixFilter(CALayer *layer, const I18FXMatrix *matrix) {
    if (!layer) return;
    NSArray *current = I18ValueForKey(layer, @"filters");
    if (!matrix && current.count == 0) return;

    NSMutableArray *filters = [NSMutableArray array];
    for (id filter in current) {
        if (![I18ValueForKey(filter, @"name") isEqual:kFilterName]) [filters addObject:filter];
    }
    if (matrix) {
        id filter = I18MakeMatrixFilter(*matrix);
        if (filter) [filters addObject:filter];
    }
    if (!matrix && filters.count == current.count) return; // nothing of ours was there

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        [layer setValue:(filters.count ? filters : nil) forKey:@"filters"];
    } @catch (__unused NSException *exception) {
    }
    [CATransaction commit];
}
