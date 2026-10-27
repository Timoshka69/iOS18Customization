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
//  A transparent tap area is laid over the "+" for that; the menu opens on a
//  single tap.
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

static void I18AddWidget(UIView *stock) {
    if (I18FireStockAction(stock, 0)) return;
    // The action may live on a container of the "+" view.
    UIView *parent = stock.superview;
    for (int level = 0; parent && level < 2; level++, parent = parent.superview) {
        if (I18FireGestures(parent)) return;
        if ([parent isKindOfClass:[UIControl class]]) {
            [(UIControl *)parent sendActionsForControlEvents:UIControlEventTouchUpInside];
            return;
        }
    }
}

#pragma mark - The menu

/// Small menu in the style of the iOS context menu that opens on a single
/// tap (a UIButton menu needed a long press inside SpringBoard's edit mode,
/// because SpringBoard's own gestures swallow the short tap).
@interface I18PlusMenu : NSObject
+ (instancetype)shared;
- (void)showBelowView:(UIView *)anchor;
- (void)dismiss;
@end

@interface I18PlusMenuWindow : UIWindow
@end

@implementation I18PlusMenuWindow
- (BOOL)_canAffectStatusBarAppearance {
    return NO;
}
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

@interface I18PlusMenuRow : UIControl
@property (nonatomic, copy) void (^action)(void);
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol;
@end

@implementation I18PlusMenuRow {
    UILabel *_title;
    UIImageView *_icon;
    UIView *_highlight;
}

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol {
    if ((self = [super initWithFrame:CGRectZero])) {
        _highlight = [[UIView alloc] init];
        _highlight.userInteractionEnabled = NO;
        _highlight.alpha = 0.0;
        _highlight.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.12] : [UIColor colorWithWhite:0.0 alpha:0.08];
        }];
        [self addSubview:_highlight];

        _title = [[UILabel alloc] init];
        _title.text = title;
        _title.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
        _title.textColor = UIColor.labelColor;
        _title.userInteractionEnabled = NO;
        [self addSubview:_title];

        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightRegular];
        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
        _icon.tintColor = UIColor.labelColor;
        _icon.contentMode = UIViewContentModeCenter;
        _icon.userInteractionEnabled = NO;
        [self addSubview:_icon];
        self.accessibilityLabel = title;
        [self addTarget:self action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _highlight.frame = self.bounds;
    _icon.frame = CGRectMake(size.width - 16.0 - 26.0, 0, 26.0, size.height);
    _title.frame = CGRectMake(16.0, 0, size.width - 16.0 - 50.0, size.height);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _highlight.alpha = highlighted ? 1.0 : 0.0;
}

- (void)fire {
    if (self.action) self.action();
}
@end

@implementation I18PlusMenu {
    I18PlusMenuWindow *_window;
    UIView *_card;
    __weak UIView *_anchor;
}

+ (instancetype)shared {
    static I18PlusMenu *menu;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        menu = [[I18PlusMenu alloc] init];
    });
    return menu;
}

- (void)showBelowView:(UIView *)anchor {
    UIWindow *home = anchor.window;
    UIWindowScene *scene = home.windowScene;
    if (!home || !scene) return;
    if (_window) [self dismissAnimated:NO];
    _anchor = anchor;

    _window = [[I18PlusMenuWindow alloc] initWithWindowScene:scene];
    _window.frame = home.screen.bounds;
    _window.windowLevel = home.windowLevel + 4.0;
    _window.backgroundColor = UIColor.clearColor;

    UIControl *catcher = [[UIControl alloc] initWithFrame:_window.bounds];
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [catcher addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchDown];
    [_window addSubview:catcher];

    CGFloat rowHeight = 44.0;
    CGFloat width = MIN(250.0, _window.bounds.size.width - 32.0);
    _card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, rowHeight * 2.0 + 0.5)];
    _card.layer.shadowColor = UIColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.22f;
    _card.layer.shadowRadius = 18.0;
    _card.layer.shadowOffset = CGSizeMake(0, 6);

    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    material.frame = _card.bounds;
    material.layer.cornerRadius = 13.0;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.clipsToBounds = YES;
    [_card addSubview:material];

    __weak I18PlusMenu *weakSelf = self;
    __weak UIView *weakAnchor = anchor;
    I18PlusMenuRow *addWidget = [[I18PlusMenuRow alloc] initWithTitle:I18L(@"AddWidget") symbol:@"plus.square.on.square"];
    addWidget.frame = CGRectMake(0, 0, width, rowHeight);
    addWidget.action = ^{
        [weakSelf dismissAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            I18AddWidget(weakAnchor);
        });
    };
    [material.contentView addSubview:addWidget];

    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, rowHeight, width, 0.5)];
    separator.backgroundColor = UIColor.separatorColor;
    [material.contentView addSubview:separator];

    NSString *brush = [UIImage systemImageNamed:@"paintbrush.pointed"] ? @"paintbrush.pointed" : @"paintbrush";
    I18PlusMenuRow *customize = [[I18PlusMenuRow alloc] initWithTitle:I18L(@"Customize") symbol:brush];
    customize.frame = CGRectMake(0, rowHeight + 0.5, width, rowHeight);
    customize.action = ^{
        [weakSelf dismissAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[I18Panel shared] show];
        });
    };
    [material.contentView addSubview:customize];
    [_window addSubview:_card];

    // Below the "+", left aligned with it, kept on screen.
    CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:nil];
    anchorFrame = [home convertRect:anchorFrame toWindow:nil];
    CGFloat x = MAX(12.0, MIN(CGRectGetMinX(anchorFrame), _window.bounds.size.width - width - 12.0));
    CGFloat y = CGRectGetMaxY(anchorFrame) + 8.0;
    _card.layer.anchorPoint = CGPointMake(0.1, 0.0);
    _card.center = CGPointMake(x + width * 0.1, y);

    _window.hidden = NO;
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    _card.alpha = 0.0;
    _card.transform = CGAffineTransformMakeScale(0.4, 0.4);
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_card.alpha = 1.0;
        self->_card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated {
    UIWindow *window = _window;
    UIView *card = _card;
    _window = nil;
    _card = nil;
    if (!window) return;
    if (!animated) {
        window.hidden = YES;
        return;
    }
    [UIView animateWithDuration:0.18 animations:^{
        card.alpha = 0.0;
        card.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(__unused BOOL finished) {
        window.hidden = YES;
    }];
}
@end

#pragma mark - Transparent tap area over the "+"

@interface I18MenuOverlay : UIView <UIGestureRecognizerDelegate>
- (instancetype)initWithHost:(UIView *)host;
@end

@implementation I18MenuOverlay {
    __weak UIView *_host;
}

- (instancetype)initWithHost:(UIView *)host {
    if ((self = [super initWithFrame:host.bounds])) {
        _host = host;
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.accessibilityLabel = host.accessibilityLabel;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)tapped {
    UIView *anchor = _host ?: self;
    [[I18PlusMenu shared] showBelowView:anchor];
}

// SpringBoard has its own tap and long-press recognizers on the home screen.
// Ours has to win on the "+", so the others wait for it to fail.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
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
