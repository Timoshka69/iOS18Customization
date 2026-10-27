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

/// Fires the stock "+" action, whatever kind of view the "+" is.
static BOOL I18FireGestures(UIView *view) {
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:[UITapGestureRecognizer class]]) continue;
        NSArray *targets = I18ValueForKey(recognizer, @"_targets");
        for (id entry in targets) {
            id target = I18ValueForKey(entry, @"_target");
            Ivar actionIvar = class_getInstanceVariable(object_getClass(entry), "_action");
            if (!target || !actionIvar) continue;
            SEL action = *(SEL *)((uint8_t *)(__bridge void *)entry + ivar_getOffset(actionIvar));
            if (action && [target respondsToSelector:action]) {
                ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
                return YES;
            }
        }
    }
    return NO;
}

static BOOL I18FireStockAction(UIView *view, int depth) {
    if (!view || depth > 3) return NO;
    if ([view isKindOfClass:[UIControl class]] && !I18ClassNameContains(view, @"I18MenuOverlay")) {
        UIControl *control = (UIControl *)view;
        if (I18ControlHasActions(control, UIControlEventTouchUpInside)) {
            [control sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
        if (I18ControlHasActions(control, UIControlEventPrimaryActionTriggered) || control.allTargets.count == 0) {
            [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            return YES;
        }
    }
    if (I18FireGestures(view)) return YES;
    for (UIView *sub in view.subviews) {
        if (I18FireStockAction(sub, depth + 1)) return YES;
    }
    return NO;
}

static UIMenu *I18MakeMenu(UIView *host) {
    __weak UIView *weakHost = host;
    UIImage *widgetImage = [UIImage systemImageNamed:@"plus.square.on.square"];
    UIImage *brushImage = [UIImage systemImageNamed:@"paintbrush.pointed"] ?: [UIImage systemImageNamed:@"paintbrush"];

    UIAction *addWidget = [UIAction actionWithTitle:I18L(@"AddWidget") image:widgetImage identifier:nil handler:^(__unused UIAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *stock = weakHost;
            if (I18FireStockAction(stock, 0)) return;
            // The action may live on a container of the "+" view.
            UIView *parent = stock.superview;
            for (int level = 0; parent && level < 2; level++, parent = parent.superview) {
                if ([parent isKindOfClass:[UIControl class]] || parent.gestureRecognizers.count) {
                    if (I18FireGestures(parent)) return;
                    if ([parent isKindOfClass:[UIControl class]]) {
                        [(UIControl *)parent sendActionsForControlEvents:UIControlEventTouchUpInside];
                        return;
                    }
                }
            }
        });
    }];
    UIAction *customize = [UIAction actionWithTitle:I18L(@"Customize") image:brushImage identifier:nil handler:^(__unused UIAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[I18Panel shared] show];
        });
    }];
    return [UIMenu menuWithTitle:@"" children:@[addWidget, customize]];
}

#pragma mark - Transparent menu button over the "+"

@interface I18MenuOverlay : UIButton
@end

@implementation I18MenuOverlay
- (instancetype)initWithHost:(UIView *)host {
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

static BOOL I18IsOurs(UIView *view) {
    return I18ClassNameContains(view, @"I18MenuOverlay") || I18ClassNameContains(view, @"I18Panel");
}

/// SpringBoard's own class names for the "+" (iOS 14 - 16).
static BOOL I18HasWidgetButtonName(UIView *view) {
    return I18ClassNameContains(view, @"AddWidgetButton") || I18ClassNameContains(view, @"EditingWidgetButton") ||
           I18ClassNameContains(view, @"WidgetButton");
}

static BOOL I18HasWidgetAction(UIView *view) {
    if (![view isKindOfClass:[UIControl class]]) return NO;
    for (NSString *action in I18ActionNames((UIControl *)view)) {
        if ([action rangeOfString:@"idget"].location != NSNotFound) return YES;
    }
    return NO;
}

/// Last resort: in jiggle mode the only small button in the top-left corner
/// of the screen (outside the icons) is the "+".
static BOOL I18IsTopLeftButton(UIView *view, UIWindow *window) {
    if (![view isKindOfClass:[UIControl class]] && !I18ClassNameContains(view, @"Button")) return NO;
    if (view.hidden || view.alpha < 0.01 || !window) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGFloat width = window.bounds.size.width;
    return frame.size.width >= 20.0 && frame.size.width <= 140.0 && frame.size.height >= 20.0 && frame.size.height <= 64.0 &&
           CGRectGetMinY(frame) < 90.0 && CGRectGetMaxX(frame) < width * 0.45 && CGRectGetMinX(frame) >= 0.0;
}

typedef BOOL (*I18Matcher)(UIView *view, UIWindow *window);

static BOOL I18MatchName(UIView *view, __unused UIWindow *window) { return I18HasWidgetButtonName(view); }
static BOOL I18MatchAction(UIView *view, __unused UIWindow *window) { return I18HasWidgetAction(view); }
static BOOL I18MatchPosition(UIView *view, UIWindow *window) { return I18IsTopLeftButton(view, window); }

static UIView *I18Search(UIView *root, I18Matcher match, UIWindow *window, int depth) {
    if (!root || depth > 9) return nil;
    for (UIView *sub in root.subviews) {
        if (I18IsOurs(sub)) continue;
        // Pages of icons never contain the editing buttons (and their "-"
        // buttons must not be mistaken for the "+").
        if (I18ClassNameContains(sub, @"IconListView") || I18ClassNameContains(sub, @"SBIconView")) continue;
        if (match(sub, window)) return sub;
        UIView *found = I18Search(sub, match, window, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIView *I18FindWidgetButton(UIView *root) {
    for (NSString *key in @[@"widgetButton", @"addWidgetButton", @"_widgetButton", @"_addWidgetButton"]) {
        id value = I18ValueForKey(root, key);
        if ([value isKindOfClass:[UIView class]]) return value;
    }
    UIWindow *window = root.window;
    UIView *scope = window ?: root;
    I18Matcher matchers[3] = {I18MatchName, I18MatchAction, I18MatchPosition};
    for (int i = 0; i < 3; i++) {
        UIView *found = I18Search(scope, matchers[i], window, 0);
        if (!found) continue;
        // Prefer the outer button view when we landed on its inner control.
        UIView *outer = found.superview;
        if (outer && I18HasWidgetButtonName(outer) && ![found isKindOfClass:[UIControl class]]) found = outer;
        return found;
    }
    return nil;
}

#pragma mark - Keeping the overlay on top

static BOOL I18IsHostClass(Class cls) {
    return cls && strncmp(class_getName(cls), "I18PlusHost_", 12) == 0;
}

static Class I18HostSuperclass(id object) {
    Class cls = object_getClass(object);
    while (cls && !I18IsHostClass(cls)) cls = class_getSuperclass(cls);
    return cls ? class_getSuperclass(cls) : [UIView class];
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

static void I18AttachMenu(UIView *host) {
    // Blur views only accept subviews in their content view.
    if ([host isKindOfClass:[UIVisualEffectView class]]) host = ((UIVisualEffectView *)host).contentView;
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

#pragma mark - Entry point

void I18SyncEditButton(UIView *root) {
    if (!root) return;
    BOOL editing = [I18ValueForKey(root, @"editing") boolValue];

    I18WeakBox *box = objc_getAssociatedObject(root, kHostRefKey);
    UIView *host = box.object;
    if (host && editing && host.window && root.window && host.window != root.window) host = nil;

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
    if (host) I18AttachMenu(host);
}
