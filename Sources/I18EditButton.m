//
//  I18EditButton.m
//  iOS18Customization
//
//  iOS 18 replaces the "+" button of jiggle mode with an "Edit" pill that
//  opens a small menu: "Add Widget" and "Customize". Here the stock "+"
//  button is kept (so SpringBoard still animates and positions it), its
//  glyph is hidden and the pill is placed inside it. "Add Widget" simply
//  fires the stock button's own action.
//

#import "I18Shared.h"

static const void *kPillKey = &kPillKey;
static const void *kHostRefKey = &kHostRefKey;
static const void *kFallbackPillKey = &kFallbackPillKey;
static const void *kLastSearchKey = &kLastSearchKey;
static const void *kHostBackgroundKey = &kHostBackgroundKey;
static const void *kDoneRefKey = &kDoneRefKey;

#pragma mark - Pill

@interface I18EditPill : UIButton
@property (nonatomic, weak) UIControl *host;
@property (nonatomic) CGFloat preferredHeight;
@property (nonatomic, strong) UIVisualEffectView *plate;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic) BOOL styleMatched;
- (void)matchStyleOfButton:(UIView *)button;
- (void)rebuildMenu;
@end

@interface I18WeakBox : NSObject
@property (nonatomic, weak) id object;
@property (nonatomic) CFTimeInterval searchedAt;
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

@implementation I18EditPill

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _plate = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        _plate.userInteractionEnabled = NO;
        _plate.clipsToBounds = YES;
        _plate.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_plate];

        _caption = [[UILabel alloc] init];
        _caption.text = I18L(@"Edit");
        _caption.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        _caption.textColor = UIColor.labelColor;
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.userInteractionEnabled = NO;
        [self addSubview:_caption];

        self.accessibilityLabel = I18L(@"Edit");
        self.showsMenuAsPrimaryAction = YES;
        [self rebuildMenu];
    }
    return self;
}

- (void)rebuildMenu {
    __weak I18EditPill *weakSelf = self;
    UIImage *widgetImage = [UIImage systemImageNamed:@"plus.square.on.square"];
    UIImage *brushImage = [UIImage systemImageNamed:@"paintbrush.pointed"] ?: [UIImage systemImageNamed:@"paintbrush"];

    UIAction *addWidget = [UIAction actionWithTitle:I18L(@"AddWidget") image:widgetImage identifier:nil handler:^(__unused UIAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIControl *host = weakSelf.host;
            if (!host) return;
            if (I18ControlHasActions(host, UIControlEventTouchUpInside)) {
                [host sendActionsForControlEvents:UIControlEventTouchUpInside];
            } else {
                [host sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            }
        });
    }];
    UIAction *customize = [UIAction actionWithTitle:I18L(@"Customize") image:brushImage identifier:nil handler:^(__unused UIAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[I18Panel shared] show];
        });
    }];
    NSArray<UIMenuElement *> *children = self.host ? @[addWidget, customize] : @[customize];
    self.menu = [UIMenu menuWithTitle:@"" children:children];
}

- (void)setHost:(UIControl *)host {
    _host = host;
    [self rebuildMenu];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize text = [self.caption sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat height = self.preferredHeight > 0 ? self.preferredHeight : 30.0;
    return CGSizeMake(ceil(text.width) + 26.0, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.plate.frame = self.bounds;
    self.plate.layer.cornerRadius = self.bounds.size.height * 0.5;
    self.caption.frame = self.bounds;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:highlighted ? 0.08 : 0.2 animations:^{
        self.alpha = highlighted ? 0.55 : 1.0;
    }];
}

static id I18FirstSubviewOfClass(UIView *root, Class cls, int depth) {
    if (!root || depth > 4) return nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:cls]) {
            if (cls != [UILabel class] || ((UILabel *)sub).text.length > 0) return sub;
        }
        id found = I18FirstSubviewOfClass(sub, cls, depth + 1);
        if (found) return found;
    }
    return nil;
}

- (void)matchStyleOfButton:(UIView *)button {
    if (!button || self.styleMatched || button.bounds.size.height < 1.0) return;
    self.styleMatched = YES;
    UIVisualEffectView *effectView = I18FirstSubviewOfClass(button, [UIVisualEffectView class], 0);
    if (effectView.effect) self.plate.effect = effectView.effect;
    UILabel *label = I18FirstSubviewOfClass(button, [UILabel class], 0);
    if (label.font) {
        // The stock "Done" is bold, iOS 18's "Edit" is one weight lighter.
        UIFontDescriptor *descriptor = label.font.fontDescriptor;
        CGFloat size = descriptor.pointSize > 0 ? descriptor.pointSize : 15.0;
        self.caption.font = [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    }
    if (label.textColor) self.caption.textColor = label.textColor;
    if (button.bounds.size.height >= 24.0) self.preferredHeight = button.bounds.size.height;
}

@end

#pragma mark - Finding the stock buttons

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
    if (![view isKindOfClass:[UIControl class]] || [view isKindOfClass:[I18EditPill class]]) return NO;
    if (I18ClassNameContains(view, @"Widget")) return YES;
    for (NSString *action in I18ActionNames((UIControl *)view)) {
        if ([action rangeOfString:@"idget"].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL I18LooksLikeDoneButton(UIView *view) {
    if (![view isKindOfClass:[UIControl class]] || [view isKindOfClass:[I18EditPill class]]) return NO;
    if (I18ClassNameContains(view, @"Done")) return YES;
    for (NSString *action in I18ActionNames((UIControl *)view)) {
        if ([action rangeOfString:@"done" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static UIView *I18Search(UIView *root, BOOL (*match)(UIView *), int depth) {
    if (!root || depth > 6) return nil;
    for (UIView *sub in root.subviews) {
        if (match(sub)) return sub;
    }
    for (UIView *sub in root.subviews) {
        // Pages of icons never contain the editing buttons, skip them.
        if (I18ClassNameContains(sub, @"IconListView") || I18ClassNameContains(sub, @"SBIconView")) continue;
        UIView *found = I18Search(sub, match, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIControl *I18FindWidgetButton(UIView *root) {
    for (NSString *key in @[@"widgetButton", @"addWidgetButton", @"_widgetButton", @"_addWidgetButton"]) {
        id value = I18ValueForKey(root, key);
        if ([value isKindOfClass:[UIControl class]]) return value;
    }
    return (UIControl *)I18Search(root, I18LooksLikeWidgetButton, 0);
}

static UIView *I18FindDoneButton(UIView *root) {
    for (NSString *key in @[@"doneButton", @"_doneButton"]) {
        id value = I18ValueForKey(root, key);
        if ([value isKindOfClass:[UIView class]]) return value;
    }
    return I18Search(root, I18LooksLikeDoneButton, 0);
}

#pragma mark - Host subclass

static BOOL I18IsHostClass(Class cls) {
    return cls && strncmp(class_getName(cls), "I18EditHost_", 12) == 0;
}

static Class I18HostSuperclass(id object) {
    Class cls = object_getClass(object);
    while (cls && !I18IsHostClass(cls)) cls = class_getSuperclass(cls);
    return cls ? class_getSuperclass(cls) : [UIControl class];
}

#pragma mark - Hit area of small containers

// If SpringBoard ever puts the "+" button into a container that is just as
// small as the button, touches on the wider pill would never get through
// that container. Such containers get a pointInside: that knows the pill.

static const void *kHitAreaPillKey = &kHitAreaPillKey;

static Class I18HitAreaSuperclass(id object) {
    Class cls = object_getClass(object);
    while (cls && strncmp(class_getName(cls), "I18HitArea_", 11) != 0) cls = class_getSuperclass(cls);
    return cls ? class_getSuperclass(cls) : [UIView class];
}

static BOOL I18HitArea_pointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    struct objc_super sup = {self, I18HitAreaSuperclass(self)};
    if (((BOOL (*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, point, event)) return YES;
    I18WeakBox *box = objc_getAssociatedObject(self, kHitAreaPillKey);
    UIView *pill = box.object;
    if (!pill || pill.hidden || !pill.window || ![pill isDescendantOfView:self]) return NO;
    CGRect area = CGRectInset([pill convertRect:pill.bounds toView:self], -6.0, -6.0);
    return CGRectContainsPoint(area, point);
}

static Class I18HitArea_class(id self, SEL _cmd) {
    return I18HitAreaSuperclass(self);
}

static void I18ExtendHitArea(UIView *container, UIView *pill) {
    I18WeakBox *box = objc_getAssociatedObject(container, kHitAreaPillKey);
    if (!box) {
        Class base = object_getClass(container);
        if (strncmp(class_getName(base), "NSKVONotifying_", 15) == 0) return;
        if (strncmp(class_getName(base), "I18", 3) != 0) {
            NSString *name = [@"I18HitArea_" stringByAppendingString:NSStringFromClass(base)];
            Class sub = objc_getClass(name.UTF8String);
            if (!sub) {
                sub = objc_allocateClassPair(base, name.UTF8String, 0);
                if (!sub) return;
                Method pointMethod = class_getInstanceMethod([UIView class], @selector(pointInside:withEvent:));
                const char *types = pointMethod ? method_getTypeEncoding(pointMethod) : "B@:{CGPoint=dd}@";
                class_addMethod(sub, @selector(pointInside:withEvent:), (IMP)I18HitArea_pointInside, types);
                class_addMethod(sub, @selector(class), (IMP)I18HitArea_class, "#@:");
                objc_registerClassPair(sub);
            }
            object_setClass(container, sub);
        }
        box = [[I18WeakBox alloc] init];
        objc_setAssociatedObject(container, kHitAreaPillKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    box.object = pill;
}

static void I18MakePillReachable(UIView *host, UIView *pill) {
    int depth = 0;
    for (UIView *container = host.superview; container && depth < 4; container = container.superview, depth++) {
        CGRect rect = [pill convertRect:pill.bounds toView:container];
        if (CGRectContainsRect(container.bounds, rect)) break;
        I18ExtendHitArea(container, pill);
        if (container.clipsToBounds) container.clipsToBounds = NO;
    }
}

static void I18LayoutPillInHost(UIView *host) {
    I18EditPill *pill = objc_getAssociatedObject(host, kPillKey);
    if (!pill) return;

    for (UIView *sub in host.subviews) {
        if (sub != pill && sub.alpha != 0.0) sub.alpha = 0.0;
    }
    if (host.backgroundColor && !objc_getAssociatedObject(host, kHostBackgroundKey)) {
        objc_setAssociatedObject(host, kHostBackgroundKey, host.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        host.backgroundColor = UIColor.clearColor;
    }

    CGSize size = [pill sizeThatFits:CGSizeZero];
    CGFloat y = round((host.bounds.size.height - size.height) * 0.5);
    CGRect frame = CGRectMake(0.0, y, size.width, size.height);
    if (!CGRectEqualToRect(pill.frame, frame)) pill.frame = frame;
    if (host.subviews.lastObject != pill) [host bringSubviewToFront:pill];
    if (host.window) I18MakePillReachable(host, pill);
}

static void I18Host_layoutSubviews(UIView *self, SEL _cmd) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    I18LayoutPillInHost(self);
}

static BOOL I18Host_pointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    struct objc_super sup = {self, I18HostSuperclass(self)};
    BOOL inside = ((BOOL (*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, point, event);
    if (inside) return YES;
    I18EditPill *pill = objc_getAssociatedObject(self, kPillKey);
    return pill && !pill.hidden && CGRectContainsPoint(CGRectInset(pill.frame, -6.0, -6.0), point);
}

static Class I18Host_class(id self, SEL _cmd) {
    return I18HostSuperclass(self);
}

static Class I18HostClassFor(Class base) {
    NSString *name = [@"I18EditHost_" stringByAppendingString:NSStringFromClass(base)];
    Class host = objc_getClass(name.UTF8String);
    if (host) return host;
    host = objc_allocateClassPair(base, name.UTF8String, 0);
    if (!host) return Nil;
    class_addMethod(host, @selector(layoutSubviews), (IMP)I18Host_layoutSubviews, "v@:");
    Method pointMethod = class_getInstanceMethod([UIView class], @selector(pointInside:withEvent:));
    const char *pointTypes = pointMethod ? method_getTypeEncoding(pointMethod) : "B@:{CGPoint=dd}@";
    class_addMethod(host, @selector(pointInside:withEvent:), (IMP)I18Host_pointInside, pointTypes);
    class_addMethod(host, @selector(class), (IMP)I18Host_class, "#@:");
    objc_registerClassPair(host);
    return host;
}

static void I18ConvertHost(UIControl *host, UIView *doneButton) {
    I18EditPill *pill = objc_getAssociatedObject(host, kPillKey);
    if (!pill) {
        if (I18ClassNameContains(host, @"NSKVONotifying_")) return;
        Class hostClass = I18IsHostClass(object_getClass(host)) ? Nil : I18HostClassFor(object_getClass(host));
        pill = [[I18EditPill alloc] initWithFrame:CGRectZero];
        pill.host = host;
        [host addSubview:pill];
        objc_setAssociatedObject(host, kPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (hostClass) object_setClass(host, hostClass);
        host.clipsToBounds = NO;
    }
    if (doneButton) [pill matchStyleOfButton:doneButton];
    [host setNeedsLayout];
}

#pragma mark - Fallback

static void I18SyncFallbackPill(UIView *root, BOOL editing, UIView *doneButton) {
    I18EditPill *pill = objc_getAssociatedObject(root, kFallbackPillKey);
    if (!pill) {
        if (!editing) return;
        pill = [[I18EditPill alloc] initWithFrame:CGRectZero];
        pill.alpha = 0.0;
        [root addSubview:pill];
        objc_setAssociatedObject(root, kFallbackPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (doneButton) [pill matchStyleOfButton:doneButton];

    CGSize size = [pill sizeThatFits:CGSizeZero];
    CGFloat top = MAX(root.safeAreaInsets.top, 20.0) + 6.0;
    if (doneButton.superview) {
        CGRect done = [doneButton.superview convertRect:doneButton.frame toView:root];
        top = CGRectGetMidY(done) - size.height * 0.5;
    }
    pill.frame = CGRectMake(16.0, round(top), size.width, size.height);
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

    if (!host) {
        // Searching is not free, do it in edit mode and at most twice a second.
        if (!editing) {
            I18SyncFallbackPill(root, NO, nil);
            return;
        }
        NSNumber *last = objc_getAssociatedObject(root, kLastSearchKey);
        CFTimeInterval now = CACurrentMediaTime();
        if (last && now - last.doubleValue < 0.5) return;
        objc_setAssociatedObject(root, kLastSearchKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        host = I18FindWidgetButton(root);
        if (host) {
            box = [[I18WeakBox alloc] init];
            box.object = host;
            objc_setAssociatedObject(root, kHostRefKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    UIView *doneButton = nil;
    if (editing) {
        I18WeakBox *doneBox = objc_getAssociatedObject(root, kDoneRefKey);
        doneButton = doneBox.object;
        CFTimeInterval now = CACurrentMediaTime();
        BOOL searchedRecently = doneBox && now - doneBox.searchedAt < 1.0;
        if ((!doneButton || ![doneButton isDescendantOfView:root]) && !searchedRecently) {
            doneButton = I18FindDoneButton(root);
            doneBox = [[I18WeakBox alloc] init];
            doneBox.object = doneButton;
            doneBox.searchedAt = now;
            objc_setAssociatedObject(root, kDoneRefKey, doneBox, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (host) {
        I18ConvertHost(host, doneButton);
        I18EditPill *fallback = objc_getAssociatedObject(root, kFallbackPillKey);
        if (fallback) fallback.alpha = 0.0;
        return;
    }
    I18SyncFallbackPill(root, editing, doneButton);
}
