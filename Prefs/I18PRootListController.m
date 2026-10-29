//
//  I18PRootListController.m
//  iOS18Customization - Settings page
//
//  Settings app -> iOS18Customization. A purple banner on top and three
//  switches:
//
//      Tint Icons          (home screen icons follow the chosen look)
//      Tint Widgets        (widgets follow the chosen look)
//      Tint Settings App   (the icons in this list follow the chosen look)
//
//  The look itself (Light / Dark / Auto / Tinted) is chosen on the home
//  screen, like in iOS 18. Changes apply at once, no respring.
//
//  The controller is a subclass of PSListController made at runtime, so the
//  bundle does not link against the private Preferences framework (the
//  Settings app has it loaded anyway). That keeps the build independent of
//  which SDK / headers are installed.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kRootClassName = @"I18PRootListController";
static NSString *const kRepoURL = @"https://github.com/Timoshka69/iOS18Customization";

static UIColor *I18PPurple(void) {
    return [UIColor colorWithRed:0x7B / 255.0 green:0x5C / 255.0 blue:0xFF / 255.0 alpha:1.0];
}

static NSBundle *I18PBundle(void) {
    return [NSBundle bundleForClass:NSClassFromString(@"I18PBannerView")];
}

static NSString *I18PLocalized(NSString *key) {
    return [I18PBundle() localizedStringForKey:key value:key table:@"Root"];
}

#pragma mark - Banner

@interface I18PBannerView : UIView
@end

@implementation I18PBannerView {
    UIView *_card;
    CAGradientLayer *_gradient;
    CAShapeLayer *_glowA;
    CAShapeLayer *_glowB;
    UIImageView *_icon;
    UILabel *_title;
    UILabel *_subtitle;
    UILabel *_version;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _card = [[UIView alloc] init];
        _card.layer.cornerRadius = 24.0;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.clipsToBounds = YES;
        [self addSubview:_card];

        // Purple to violet, like the Sileo page of the tweak.
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[
            (id)[UIColor colorWithRed:0.62 green:0.44 blue:1.00 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.48 green:0.36 blue:1.00 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.30 green:0.18 blue:0.82 alpha:1.0].CGColor,
        ];
        _gradient.startPoint = CGPointMake(0.0, 0.0);
        _gradient.endPoint = CGPointMake(1.0, 1.0);
        [_card.layer addSublayer:_gradient];

        // Two soft circles for depth.
        _glowA = [CAShapeLayer layer];
        _glowA.fillColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
        [_card.layer addSublayer:_glowA];
        _glowB = [CAShapeLayer layer];
        _glowB.fillColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
        [_card.layer addSublayer:_glowB];

        _icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"BannerIcon" inBundle:I18PBundle() compatibleWithTraitCollection:nil]];
        _icon.contentMode = UIViewContentModeScaleAspectFill;
        _icon.layer.cornerRadius = 15.0;
        _icon.layer.cornerCurve = kCACornerCurveContinuous;
        _icon.clipsToBounds = YES;
        _icon.layer.borderWidth = 1.0;
        _icon.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        [_card addSubview:_icon];

        _title = [[UILabel alloc] init];
        _title.text = @"iOS18Customization";
        _title.font = [UIFont systemFontOfSize:23.0 weight:UIFontWeightHeavy];
        _title.textColor = UIColor.whiteColor;
        _title.adjustsFontSizeToFitWidth = YES;
        _title.minimumScaleFactor = 0.7;
        [_card addSubview:_title];

        _subtitle = [[UILabel alloc] init];
        _subtitle.text = I18PLocalized(@"BANNER_SUBTITLE");
        _subtitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        _subtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
        _subtitle.numberOfLines = 2;
        [_card addSubview:_subtitle];

        NSString *version = [I18PBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        _version = [[UILabel alloc] init];
        _version.text = version.length ? [NSString stringWithFormat:@"v%@", version] : @"";
        _version.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        _version.textColor = UIColor.whiteColor;
        _version.textAlignment = NSTextAlignmentCenter;
        _version.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
        _version.layer.cornerRadius = 10.0;
        _version.clipsToBounds = YES;
        _version.hidden = version.length == 0;
        [_card addSubview:_version];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _card.frame = CGRectInset(bounds, 16.0, 10.0);
    CGSize size = _card.bounds.size;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gradient.frame = _card.bounds;
    _glowA.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(size.width - 150.0, -70.0, 220.0, 220.0)].CGPath;
    _glowB.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(size.width - 90.0, size.height - 60.0, 140.0, 140.0)].CGPath;
    [CATransaction commit];

    CGFloat iconSize = 68.0;
    _icon.frame = CGRectMake(20.0, (size.height - iconSize) * 0.5, iconSize, iconSize);
    CGFloat textX = CGRectGetMaxX(_icon.frame) + 16.0;
    CGFloat textWidth = size.width - textX - 18.0;
    _title.frame = CGRectMake(textX, size.height * 0.5 - 40.0, textWidth, 30.0);
    _subtitle.frame = CGRectMake(textX, CGRectGetMaxY(_title.frame) + 2.0, textWidth, 38.0);
    CGSize versionSize = [_version sizeThatFits:CGSizeMake(200.0, 20.0)];
    _version.frame = CGRectMake(size.width - versionSize.width - 30.0, 14.0, versionSize.width + 16.0, 20.0);
}

@end

#pragma mark - List controller (made at runtime)

static Class gRootClass;

static void I18PCallSuper(id self, SEL sel) {
    struct objc_super sup = {self, class_getSuperclass(gRootClass)};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel);
}

static void I18PCallSuperBool(id self, SEL sel, BOOL value) {
    struct objc_super sup = {self, class_getSuperclass(gRootClass)};
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&sup, sel, value);
}

static id I18P_specifiers(id self, SEL _cmd) {
    Ivar ivar = class_getInstanceVariable(class_getSuperclass(gRootClass), "_specifiers");
    id specifiers = ivar ? object_getIvar(self, ivar) : nil;
    if (!specifiers) {
        SEL load = NSSelectorFromString(@"loadSpecifiersFromPlistName:target:");
        specifiers = ((id (*)(id, SEL, NSString *, id))objc_msgSend)(self, load, @"Root", self);
        if (ivar) object_setIvarWithStrongDefault(self, ivar, specifiers);
    }
    return specifiers;
}

static UITableView *I18PTable(id self) {
    SEL sel = NSSelectorFromString(@"table");
    if ([self respondsToSelector:sel]) {
        id table = ((id (*)(id, SEL))objc_msgSend)(self, sel);
        if ([table isKindOfClass:[UITableView class]]) return table;
    }
    for (UIView *view in ((UIViewController *)self).view.subviews) {
        if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    }
    return nil;
}

static void I18PUpdateHeader(id self) {
    UITableView *table = I18PTable(self);
    if (!table) return;
    CGFloat width = table.bounds.size.width;
    if (width <= 0.0) return;
    UIView *header = table.tableHeaderView;
    if (![header isKindOfClass:[I18PBannerView class]]) {
        header = [[I18PBannerView alloc] initWithFrame:CGRectMake(0, 0, width, 150.0)];
        table.tableHeaderView = header;
    } else if (fabs(header.bounds.size.width - width) > 0.5) {
        header.frame = CGRectMake(0, 0, width, 150.0);
        table.tableHeaderView = header;
    }
}

static void I18P_viewDidLoad(id self, SEL _cmd) {
    I18PCallSuper(self, _cmd);
    UIViewController *controller = self;
    controller.title = @"iOS18Customization";
    controller.view.tintColor = I18PPurple();
    I18PUpdateHeader(self);
}

static void I18P_viewDidLayoutSubviews(id self, SEL _cmd) {
    I18PCallSuper(self, _cmd);
    I18PUpdateHeader(self);
}

static void I18P_viewWillAppear(id self, SEL _cmd, BOOL animated) {
    I18PCallSuperBool(self, _cmd, animated);
    UIViewController *controller = self;
    controller.navigationController.navigationBar.tintColor = I18PPurple();
}

static void I18P_viewWillDisappear(id self, SEL _cmd, BOOL animated) {
    I18PCallSuperBool(self, _cmd, animated);
    UIViewController *controller = self;
    // The rest of the Settings app keeps its own blue.
    controller.navigationController.navigationBar.tintColor = nil;
}

static void I18POpen(NSString *link) {
    NSURL *url = [NSURL URLWithString:link];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

static void I18P_openGitHub(id self, SEL _cmd) {
    I18POpen(kRepoURL);
}

static void I18P_openIssues(id self, SEL _cmd) {
    I18POpen([kRepoURL stringByAppendingString:@"/issues"]);
}

__attribute__((constructor)) static void I18PRegister(void) {
    Class base = NSClassFromString(@"PSListController");
    if (!base || NSClassFromString(kRootClassName)) return;
    Class cls = objc_allocateClassPair(base, kRootClassName.UTF8String, 0);
    if (!cls) return;
    class_addMethod(cls, NSSelectorFromString(@"specifiers"), (IMP)I18P_specifiers, "@@:");
    class_addMethod(cls, @selector(viewDidLoad), (IMP)I18P_viewDidLoad, "v@:");
    class_addMethod(cls, @selector(viewDidLayoutSubviews), (IMP)I18P_viewDidLayoutSubviews, "v@:");
    class_addMethod(cls, @selector(viewWillAppear:), (IMP)I18P_viewWillAppear, "v@:B");
    class_addMethod(cls, @selector(viewWillDisappear:), (IMP)I18P_viewWillDisappear, "v@:B");
    class_addMethod(cls, NSSelectorFromString(@"openGitHub"), (IMP)I18P_openGitHub, "v@:");
    class_addMethod(cls, NSSelectorFromString(@"openIssues"), (IMP)I18P_openIssues, "v@:");
    objc_registerClassPair(cls);
    gRootClass = cls;

    // Purple switches on this page only.
    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[cls]].onTintColor = I18PPurple();
}
