//
//  I18EditButton.m
//  iOS18Customization
//
//  Like iOS 18, the "+" of jiggle mode is replaced by a bold "Edit" pill
//  (styled after SpringBoard's own "Done" pill and mirrored to the other
//  side). Tapping it opens a small menu:
//
//      Add Widget   -> runs the stock "+" action (widget gallery)
//      Customize    -> opens the customization panel
//
//  The stock "+" stays in the hierarchy (invisible), so its action and its
//  appear / disappear animations keep working; the pill follows them.
//

#import "I18Shared.h"

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
    if ([view isKindOfClass:[UIControl class]] && !I18ClassNameContains(view, @"I18EditPill")) {
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

static BOOL gFiringStock;

static void I18AddWidget(UIView *stock) {
    gFiringStock = YES;
    @try {
        if (!I18FireStockAction(stock, 0)) {
            // The action may live on a container of the "+" view.
            UIView *parent = stock.superview;
            for (int level = 0; parent && level < 2; level++, parent = parent.superview) {
                if (I18FireGestures(parent)) break;
                if ([parent isKindOfClass:[UIControl class]]) {
                    [(UIControl *)parent sendActionsForControlEvents:UIControlEventTouchUpInside];
                    break;
                }
            }
        }
    } @finally {
        gFiringStock = NO;
    }
}

#pragma mark - The menu

/// Small menu in the style of the iOS context menu that opens on a single
/// tap (a UIButton menu needed a long press inside SpringBoard's edit mode,
/// because SpringBoard's own gestures swallow the short tap).
@interface I18PlusMenu : NSObject
+ (instancetype)shared;
- (void)showBelowView:(UIView *)anchor stock:(nullable UIView *)stock;
- (void)dismiss;
- (void)dismissAnimated:(BOOL)animated;
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
    CFTimeInterval _shownAt;
}

+ (instancetype)shared {
    static I18PlusMenu *menu;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        menu = [[I18PlusMenu alloc] init];
    });
    return menu;
}

- (void)showBelowView:(UIView *)anchor stock:(UIView *)stock {
    UIWindow *home = anchor.window;
    UIWindowScene *scene = home.windowScene;
    if (!home || !scene) return;
    // One tap can reach us twice (touch down and touch up of the stock control).
    CFTimeInterval now = CACurrentMediaTime();
    if (_window && now - _shownAt < 0.6) return;
    _shownAt = now;
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
    __weak UIView *weakAnchor = stock ?: anchor;
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

#pragma mark - The "Edit" pill

@interface I18EditPill : UIControl <UIGestureRecognizerDelegate>
- (void)adoptStyleFrom:(nullable UIView *)done;
@property (nonatomic, copy, nullable) void (^onTap)(void);
@end

static UIView *I18FirstSubviewOfClass(UIView *view, Class cls, int depth) {
    if (!view || depth > 5) return nil;
    if ([view isKindOfClass:cls]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = I18FirstSubviewOfClass(sub, cls, depth + 1);
        if (found) return found;
    }
    return nil;
}

@implementation I18EditPill {
    UIVisualEffectView *_material;
    UILabel *_label;
    __weak UIView *_styledFrom;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        _material.userInteractionEnabled = NO;
        _material.clipsToBounds = YES;
        [self addSubview:_material];

        // A plain tap must open the menu at once. SpringBoard's own
        // recognizers on the home screen (tap to leave jiggle mode, long
        // press) would otherwise take the touch first, so they wait for this
        // one to fail.
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        _label = [[UILabel alloc] init];
        _label.text = I18L(@"Edit");
        _label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
        _label.textColor = UIColor.labelColor;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.userInteractionEnabled = NO;
        [_material.contentView addSubview:_label];
        self.accessibilityLabel = _label.text;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)tapped {
    if (self.onTap) self.onTap();
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

/// Same material and text colour as SpringBoard's "Done" pill, but a bold
/// title (iOS 18). Its size is not copied: the pill keeps its own compact one.
- (void)adoptStyleFrom:(UIView *)done {
    if (!done || done == _styledFrom) return;
    _styledFrom = done;
    UIVisualEffectView *material = (UIVisualEffectView *)I18FirstSubviewOfClass(done, [UIVisualEffectView class], 0);
    if (material.effect) _material.effect = material.effect;
    UILabel *label = (UILabel *)I18FirstSubviewOfClass(done, [UILabel class], 0);
    if (label.font && label.font.pointSize >= 12.0 && label.font.pointSize <= 17.0) {
        _label.font = [UIFont systemFontOfSize:label.font.pointSize weight:UIFontWeightBold];
    }
    if (label.textColor) _label.textColor = label.textColor;
    [self setNeedsLayout];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize text = [_label sizeThatFits:CGSizeMake(300.0, 100.0)];
    return CGSizeMake(ceil(text.width) + 24.0, 26.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _material.frame = self.bounds;
    _material.layer.cornerRadius = self.bounds.size.height * 0.5;
    _label.frame = _material.contentView.bounds;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:highlighted ? 0.08 : 0.25 animations:^{
        self->_material.alpha = highlighted ? 0.55 : 1.0;
    }];
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
    return I18ClassNameContains(view, @"I18EditPill") || I18ClassNameContains(view, @"I18Panel");
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

#pragma mark - SpringBoard's "Done" pill

/// The "Done" pill in the top right corner of jiggle mode.
static BOOL I18IsDoneButton(UIView *view, UIWindow *window) {
    if (I18IsOurs(view) || view.hidden || view.alpha < 0.01) return NO;
    if (![view isKindOfClass:[UIControl class]] && !I18ClassNameContains(view, @"Button")) return NO;
    if (I18HasWidgetButtonName(view)) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGFloat width = window.bounds.size.width;
    return frame.size.width >= 40.0 && frame.size.width <= 160.0 && frame.size.height >= 20.0 && frame.size.height <= 50.0 &&
           CGRectGetMinY(frame) < 90.0 && CGRectGetMinX(frame) > width * 0.55 && CGRectGetMaxX(frame) <= width + 0.5;
}

static UIView *I18SearchDone(UIView *root, UIWindow *window, int depth) {
    if (!root || depth > 9) return nil;
    for (UIView *sub in root.subviews) {
        if (I18IsOurs(sub) || I18ClassNameContains(sub, @"IconListView") || I18ClassNameContains(sub, @"SBIconView")) continue;
        if (I18IsDoneButton(sub, window)) return sub;
        UIView *found = I18SearchDone(sub, window, depth + 1);
        if (found) return found;
    }
    return nil;
}

#pragma mark - The "+" as host of the pill

static const void *kPillKey = &kPillKey;
static const void *kDoneRefKey = &kDoneRefKey;

static BOOL I18IsHostClass(Class cls) {
    return cls && strncmp(class_getName(cls), "I18PlusHost_", 12) == 0;
}

static Class I18HostSuperclass(id object) {
    Class cls = object_getClass(object);
    while (cls && !I18IsHostClass(cls)) cls = class_getSuperclass(cls);
    return cls ? class_getSuperclass(cls) : [UIView class];
}

static UIView *I18DoneFor(UIView *host) {
    I18WeakBox *box = objc_getAssociatedObject(host, kDoneRefKey);
    UIView *done = box.object;
    if (done && done.window && done.window == host.window) return done;
    // Not found yet: look again at most twice a second.
    NSNumber *last = objc_getAssociatedObject(host, kLastSearchKey);
    CFTimeInterval now = CACurrentMediaTime();
    if (box && last && now - last.doubleValue < 0.5) return nil;
    objc_setAssociatedObject(host, kLastSearchKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIWindow *window = host.window;
    done = window ? I18SearchDone(window, window, 0) : nil;
    box = [[I18WeakBox alloc] init];
    box.object = done;
    objc_setAssociatedObject(host, kDoneRefKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return done;
}

/// Puts the pill where iOS 18 has it: mirrored to the "Done" pill (same
/// height, same distance from the edge), else where the "+" is.
static void I18LayoutPill(UIView *host) {
    I18EditPill *pill = objc_getAssociatedObject(host, kPillKey);
    UIView *container = host.superview;
    if (!pill || !container) return;
    if (pill.superview != container) [container addSubview:pill];
    else if (container.subviews.lastObject != pill) [container bringSubviewToFront:pill];

    // The stock "+" stays (its action and animations are SpringBoard's),
    // it is just not drawn.
    if (!host.maskView) host.maskView = [[UIView alloc] initWithFrame:CGRectZero];

    UIView *done = I18DoneFor(host);
    [pill adoptStyleFrom:done];
    CGSize size = [pill sizeThatFits:CGSizeZero];
    UIWindow *window = host.window;
    CGPoint center;
    if (window) {
        // Always on screen: 16 pt from the left edge, level with the "+"
        // (and so with "Done"), whatever the "+" or its container look like.
        CGRect plus = [host convertRect:host.bounds toView:nil];
        CGFloat midY = CGRectGetMidY(plus);
        if (done.window == window) midY = CGRectGetMidY([done convertRect:done.bounds toView:nil]);
        CGFloat left = 16.0 + window.safeAreaInsets.left;
        center = [container convertPoint:CGPointMake(left + size.width * 0.5, midY) fromView:nil];
    } else {
        CGRect frame = host.frame;
        center = CGPointMake(CGRectGetMinX(frame) + size.width * 0.5, CGRectGetMidY(frame));
    }
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    if (!CGRectEqualToRect(pill.bounds, bounds)) pill.bounds = bounds;
    if (fabs(pill.center.x - center.x) > 0.25 || fabs(pill.center.y - center.y) > 0.25) pill.center = center;
    pill.alpha = host.alpha;
    pill.hidden = host.hidden;
}

static void I18Host_layoutSubviews(UIView *self, SEL _cmd) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    I18LayoutPill(self);
}

// SpringBoard fades the "+" in and out with jiggle mode: the pill does the
// same, inside the same animation.
static void I18Host_setAlpha(UIView *self, SEL _cmd, CGFloat alpha) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, CGFloat))objc_msgSendSuper)(&sup, _cmd, alpha);
    UIView *pill = objc_getAssociatedObject(self, kPillKey);
    pill.alpha = alpha;
}

static void I18Host_setHidden(UIView *self, SEL _cmd, BOOL hidden) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&sup, _cmd, hidden);
    UIView *pill = objc_getAssociatedObject(self, kPillKey);
    pill.hidden = hidden;
}

static void I18Host_didMoveToSuperview(UIView *self, SEL _cmd) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    UIView *pill = objc_getAssociatedObject(self, kPillKey);
    if (!self.superview) [pill removeFromSuperview];
    else I18LayoutPill(self);
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
    class_addMethod(host, @selector(setAlpha:), (IMP)I18Host_setAlpha, "v@:d");
    class_addMethod(host, @selector(setHidden:), (IMP)I18Host_setHidden, "v@:B");
    class_addMethod(host, @selector(didMoveToSuperview), (IMP)I18Host_didMoveToSuperview, "v@:");
    class_addMethod(host, @selector(class), (IMP)I18Host_class, "#@:");
    objc_registerClassPair(host);
    return host;
}


/// The whole "+" (its blur circle included): the found view and its parents
/// of the same size.
static UIView *I18VisualPlus(UIView *found) {
    UIView *host = found;
    for (int level = 0; level < 3; level++) {
        UIView *parent = host.superview;
        if (!parent || parent.subviews.count > 3) break;
        CGSize a = host.bounds.size, b = parent.bounds.size;
        if (fabs(a.width - b.width) > 3.0 || fabs(a.height - b.height) > 3.0) break;
        host = parent;
    }
    return host;
}

static void I18AttachPill(UIView *host) {
    // Blur views take subviews only in their content view; the pill goes
    // next to the "+" anyway, so the outer view is the host.
    if (I18ClassNameContains(host, @"NSKVONotifying_")) return;
    I18EditPill *pill = objc_getAssociatedObject(host, kPillKey);
    if (!pill) {
        pill = [[I18EditPill alloc] initWithFrame:CGRectZero];
        __weak I18EditPill *weakPill = pill;
        __weak UIView *weakHost = host;
        pill.onTap = ^{
            I18EditPill *strongPill = weakPill;
            if (strongPill) [[I18PlusMenu shared] showBelowView:strongPill stock:weakHost];
        };
        objc_setAssociatedObject(host, kPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!I18IsHostClass(object_getClass(host))) {
        Class hostClass = I18HostClassFor(object_getClass(host));
        if (hostClass) object_setClass(host, hostClass);
    }
    I18LayoutPill(host);
}

static UIView *I18PillOfHost(UIView *host) {
    return host ? objc_getAssociatedObject(host, kPillKey) : nil;
}

#pragma mark - Entry point

static BOOL I18IsTopLeftOfScreen(UIView *view) {
    UIWindow *window = view.window;
    if (!window || I18ClassNameContains(window, @"I18")) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    return CGRectGetMinY(frame) < 120.0 && CGRectGetMaxX(frame) < window.bounds.size.width * 0.5;
}

/// The "+" of jiggle mode, recognised when it fires its action.
static BOOL I18IsStockPlus(UIControl *control, SEL action) {
    if (I18IsOurs(control) || [control isKindOfClass:[I18PlusMenuRow class]]) return NO;
    BOOL named = I18HasWidgetButtonName(control) || I18HasWidgetButtonName(control.superview);
    BOOL widgetAction = action && [NSStringFromSelector(action) rangeOfString:@"idget"].location != NSNotFound;
    if (!named && !widgetAction) return NO;
    // The widget gallery has an "Add Widget" button too, at the bottom.
    return I18IsTopLeftOfScreen(control);
}

static IMP oC_sendAction;

/// Safety net for the very first tap: if the stock "+" fires before our tap
/// area is on top of it, the menu is shown instead of the widget gallery.
static void hC_sendAction(UIControl *self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if (!gFiringStock && I18IsStockPlus(self, action)) {
        UIView *anchor = I18PillOfHost(self) ?: I18PillOfHost(self.superview) ?: I18PillOfHost(self.superview.superview) ?: self;
        [[I18PlusMenu shared] showBelowView:anchor stock:self];
        return;
    }
    ((void (*)(id, SEL, SEL, id, UIEvent *))oC_sendAction)(self, _cmd, action, target, event);
}

void I18InstallEditButtonHooks(void) {
    I18HookMethod([UIControl class], @selector(sendAction:to:forEvent:), (IMP)hC_sendAction, &oC_sendAction);
}

/// Edit mode starts with an animation and the "+" is added during it, often
/// after the last layout pass of the root folder view. Look for it a few
/// times while it appears, so the tap area is there before the first tap.
void I18EditModeChanged(UIView *root, BOOL editing) {
    if (!root) return;
    if (!editing) {
        [[I18PlusMenu shared] dismissAnimated:YES];
        I18SyncEditButton(root);
        return;
    }
    objc_setAssociatedObject(root, kLastSearchKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    I18SyncEditButton(root);
    __weak UIView *weakRoot = root;
    for (NSNumber *delay in @[@0.05, @0.2, @0.45, @0.8, @1.4]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *strongRoot = weakRoot;
            if (!strongRoot) return;
            objc_setAssociatedObject(strongRoot, kLastSearchKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            I18SyncEditButton(strongRoot);
        });
    }
}

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
    if (host) I18AttachPill(I18VisualPlus(host));
}
