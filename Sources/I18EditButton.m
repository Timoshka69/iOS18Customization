//
//  I18EditButton.m
//  iOS18Customization
//
//  The stock "+" button of jiggle mode stays exactly where and how it is.
//  Tapping it now opens a small menu, like the "Edit" menu of iOS 18:
//
//      Add Widget   -> runs the stock "+" action (widget gallery)
//      Customize    -> opens the customization panel
//
//  A transparent menu button is laid over the "+" for that. If the "+" can
//  not be found on some build, a small "Customize" pill is shown instead so
//  the panel is always reachable.
//

#import "I18Shared.h"

static const void *kOverlayKey = &kOverlayKey;
static const void *kHostRefKey = &kHostRefKey;
static const void *kFallbackPillKey = &kFallbackPillKey;
static const void *kLastSearchKey = &kLastSearchKey;

@interface I18WeakBox : NSObject
@property (nonatomic, weak) id object;
@end

@implementation I18WeakBox
@end

static BOOL I18ControlHasActions(UIControl *control, UIControlEvents event) {
    for (id target in control.allTargets) {
        id realTarget = [target isKindOfClass:[NSNull class]] ? nil : target;
        if ([control actionsForTarget:realTarget forControlEvent:event].count > 0) return YES;
    }
    return NO;
}

static UIMenu *I18MakeMenu(UIControl *host) {
    __weak UIControl *weakHost = host;
    UIImage *widgetImage = [UIImage systemImageNamed:@"plus.square.on.square"];
    UIImage *brushImage = [UIImage systemImageNamed:@"paintbrush.pointed"] ?: [UIImage systemImageNamed:@"paintbrush"];

    UIAction *customize = [UIAction actionWithTitle:I18L(@"Customize") image:brushImage identifier:nil handler:^(__unused UIAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[I18Panel shared] show];
        });
    }];
    if (!host) return [UIMenu menuWithTitle:@"" children:@[customize]];

    UIAction *addWidget = [UIAction actionWithTitle:I18L(@"AddWidget") image:widgetImage identifier:nil handler:^(__unused UIAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIControl *stock = weakHost;
            if (!stock) return;
            if (I18ControlHasActions(stock, UIControlEventTouchUpInside)) {
                [stock sendActionsForControlEvents:UIControlEventTouchUpInside];
            } else {
                [stock sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            }
        });
    }];
    return [UIMenu menuWithTitle:@"" children:@[addWidget, customize]];
}

#pragma mark - Transparent menu button over the "+"

@interface I18MenuOverlay : UIButton
@end

@implementation I18MenuOverlay
- (instancetype)initWithHost:(UIControl *)host {
    if ((self = [super initWithFrame:host.bounds])) {
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.showsMenuAsPrimaryAction = YES;
        self.menu = I18MakeMenu(host);
        self.accessibilityLabel = host.accessibilityLabel;
    }
    return self;
}

// Show the stock "+" pressed state while the finger is down.
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if ([self.superview isKindOfClass:[UIControl class]]) {
        ((UIControl *)self.superview).highlighted = highlighted;
    }
}
@end

#pragma mark - Finding the stock "+"

static NSArray<NSString *> *I18ActionNames(UIControl *control) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id target in control.allTargets) {
        id realTarget = [target isKindOfClass:[NSNull class]] ? nil : target;
        NSArray<NSString *> *actions = [control actionsForTarget:realTarget forControlEvent:UIControlEventAllEvents];
        if (actions) [names addObjectsFromArray:actions];
    }
    return names;
}

static BOOL I18LooksLikeWidgetButton(UIView *view) {
    if (![view isKindOfClass:[UIControl class]] || [view isKindOfClass:[I18MenuOverlay class]]) return NO;
    if (I18ClassNameContains(view, @"I18")) return NO;
    if (I18ClassNameContains(view, @"Widget")) return YES;
    for (NSString *action in I18ActionNames((UIControl *)view)) {
        if ([action rangeOfString:@"idget"].location != NSNotFound) return YES;
    }
    return NO;
}

static UIView *I18Search(UIView *root, int depth) {
    if (!root || depth > 6) return nil;
    for (UIView *sub in root.subviews) {
        if (I18LooksLikeWidgetButton(sub)) return sub;
    }
    for (UIView *sub in root.subviews) {
        // Pages of icons never contain the editing buttons, skip them.
        if (I18ClassNameContains(sub, @"IconListView") || I18ClassNameContains(sub, @"SBIconView")) continue;
        UIView *found = I18Search(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIControl *I18FindWidgetButton(UIView *root) {
    for (NSString *key in @[@"widgetButton", @"addWidgetButton", @"_widgetButton", @"_addWidgetButton"]) {
        id value = I18ValueForKey(root, key);
        if ([value isKindOfClass:[UIControl class]]) return value;
    }
    return (UIControl *)I18Search(root, 0);
}

#pragma mark - Keeping the overlay on top

static BOOL I18IsHostClass(Class cls) {
    return cls && strncmp(class_getName(cls), "I18PlusHost_", 12) == 0;
}

static Class I18HostSuperclass(id object) {
    Class cls = object_getClass(object);
    while (cls && !I18IsHostClass(cls)) cls = class_getSuperclass(cls);
    return cls ? class_getSuperclass(cls) : [UIControl class];
}

static void I18LayoutOverlay(UIView *host) {
    UIView *overlay = objc_getAssociatedObject(host, kOverlayKey);
    if (!overlay) return;
    if (!CGRectEqualToRect(overlay.frame, host.bounds)) overlay.frame = host.bounds;
    if (host.subviews.lastObject != overlay) [host bringSubviewToFront:overlay];
}

static void I18Host_layoutSubviews(UIView *self, SEL _cmd) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    I18LayoutOverlay(self);
}

static void I18Host_didAddSubview(UIView *self, SEL _cmd, UIView *subview) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, UIView *))objc_msgSendSuper)(&sup, _cmd, subview);
    if (![subview isKindOfClass:[I18MenuOverlay class]]) I18LayoutOverlay(self);
}

static Class I18Host_class(id self, SEL _cmd) {
    return I18HostSuperclass(self);
}

static Class I18HostClassFor(Class base) {
    NSString *name = [@"I18PlusHost_" stringByAppendingString:NSStringFromClass(base)];
    Class host = objc_getClass(name.UTF8String);
    if (host) return host;
    host = objc_allocateClassPair(base, name.UTF8String, 0);
    if (!host) return Nil;
    class_addMethod(host, @selector(layoutSubviews), (IMP)I18Host_layoutSubviews, "v@:");
    class_addMethod(host, @selector(didAddSubview:), (IMP)I18Host_didAddSubview, "v@:@");
    class_addMethod(host, @selector(class), (IMP)I18Host_class, "#@:");
    objc_registerClassPair(host);
    return host;
}

static void I18AttachMenu(UIControl *host) {
    if (objc_getAssociatedObject(host, kOverlayKey)) {
        I18LayoutOverlay(host);
        return;
    }
    if (I18ClassNameContains(host, @"NSKVONotifying_")) return;
    I18MenuOverlay *overlay = [[I18MenuOverlay alloc] initWithHost:host];
    objc_setAssociatedObject(host, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [host addSubview:overlay];
    if (!I18IsHostClass(object_getClass(host))) {
        Class hostClass = I18HostClassFor(object_getClass(host));
        if (hostClass) object_setClass(host, hostClass);
    }
    I18LayoutOverlay(host);
}

#pragma mark - Fallback pill

@interface I18CustomizePill : UIButton
@end

@implementation I18CustomizePill {
    UIVisualEffectView *_plate;
    UILabel *_caption;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _plate = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        _plate.userInteractionEnabled = NO;
        _plate.clipsToBounds = YES;
        [self addSubview:_plate];
        _caption = [[UILabel alloc] init];
        _caption.text = I18L(@"Customize");
        _caption.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _caption.textColor = UIColor.labelColor;
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.userInteractionEnabled = NO;
        [self addSubview:_caption];
        self.showsMenuAsPrimaryAction = YES;
        self.menu = I18MakeMenu(nil);
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize text = [_caption sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    return CGSizeMake(ceil(text.width) + 28.0, 30.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _plate.frame = self.bounds;
    _plate.layer.cornerRadius = self.bounds.size.height * 0.5;
    _caption.frame = self.bounds;
}
@end

static void I18SyncFallbackPill(UIView *root, BOOL editing) {
    I18CustomizePill *pill = objc_getAssociatedObject(root, kFallbackPillKey);
    if (!pill) {
        if (!editing) return;
        pill = [[I18CustomizePill alloc] initWithFrame:CGRectZero];
        pill.alpha = 0.0;
        [root addSubview:pill];
        objc_setAssociatedObject(root, kFallbackPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGSize size = [pill sizeThatFits:CGSizeZero];
    CGFloat top = MAX(root.safeAreaInsets.top, 20.0) + 8.0;
    pill.frame = CGRectMake(16.0, top, size.width, size.height);
    [root bringSubviewToFront:pill];
    CGFloat alpha = editing ? 1.0 : 0.0;
    if (pill.alpha != alpha) {
        [UIView animateWithDuration:0.25 animations:^{
            pill.alpha = alpha;
        }];
    }
}

#pragma mark - Entry point

void I18SyncEditButton(UIView *root) {
    if (!root) return;
    BOOL editing = [I18ValueForKey(root, @"editing") boolValue];

    I18WeakBox *box = objc_getAssociatedObject(root, kHostRefKey);
    UIControl *host = box.object;
    if (host && ![host isDescendantOfView:root]) host = nil;

    if (!host && editing) {
        // Searching is not free: only in edit mode and at most twice a second.
        NSNumber *last = objc_getAssociatedObject(root, kLastSearchKey);
        CFTimeInterval now = CACurrentMediaTime();
        if (!last || now - last.doubleValue >= 0.5) {
            objc_setAssociatedObject(root, kLastSearchKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            host = I18FindWidgetButton(root);
            if (host) {
                box = [[I18WeakBox alloc] init];
                box.object = host;
                objc_setAssociatedObject(root, kHostRefKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }

    if (host) {
        I18AttachMenu(host);
        UIView *fallback = objc_getAssociatedObject(root, kFallbackPillKey);
        fallback.alpha = 0.0;
        return;
    }
    I18SyncFallbackPill(root, editing);
}
