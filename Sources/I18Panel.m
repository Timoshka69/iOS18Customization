//
//  I18Panel.m
//  iOS18Customization
//
//  The small "Customize" sheet at the bottom of the home screen:
//
//    [sun]      ( Small | Large )      [eyedropper]
//    [Light]   [Dark]   [Auto]   [Tinted]
//    ==== hue ====================o=====
//    o=== tone ==========================
//
//  Tapping outside or swiping it down closes it. Everything is applied live.
//

#import "I18Controls.h"
#include <dlfcn.h>

#pragma mark - Windows

@interface I18PanelWindow : UIWindow
@end

@implementation I18PanelWindow
- (BOOL)_canAffectStatusBarAppearance {
    return NO;
}
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

#pragma mark - Screen capture for the eyedropper

static UIImage *I18CaptureScreen(UIWindowScene *scene, UIWindow *exclude) {
    static void *(*createScreenImage)(void);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        createScreenImage = (void *(*)(void))dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
    });
    if (createScreenImage) {
        void *raw = createScreenImage();
        if (raw) return (__bridge_transfer UIImage *)raw;
    }

    // Fallback: draw the windows ourselves, bottom to top.
    if (!scene) return nil;
    NSArray<UIWindow *> *windows = [scene.windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel == b.windowLevel) return NSOrderedSame;
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGRect bounds = scene.coordinateSpace.bounds;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:bounds.size format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        for (UIWindow *window in windows) {
            if (window == exclude || window.hidden || window.alpha < 0.01) continue;
            [window drawViewHierarchyInRect:window.frame afterScreenUpdates:NO];
        }
    }];
}

#pragma mark - Loupe

@interface I18Loupe : UIView
- (instancetype)initWithScreenshot:(UIImage *)screenshot;
- (UIColor *)pickedColor;
@end

@implementation I18Loupe {
    NSData *_pixels;
    size_t _width;
    size_t _height;
    size_t _bytesPerRow;
    CGFloat _scale;
}

static const NSInteger kLoupeCells = 9;

- (instancetype)initWithScreenshot:(UIImage *)screenshot {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 124, 124)])) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.35f;
        self.layer.shadowRadius = 10.0;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        CGImageRef image = screenshot.CGImage;
        _scale = screenshot.scale > 0 ? screenshot.scale : UIScreen.mainScreen.scale;
        if (image) {
            _width = CGImageGetWidth(image);
            _height = CGImageGetHeight(image);
            _bytesPerRow = _width * 4;
            NSMutableData *data = [NSMutableData dataWithLength:_bytesPerRow * _height];
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(data.mutableBytes, _width, _height, 8, _bytesPerRow, space,
                                                         kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(space);
            if (context) {
                CGContextDrawImage(context, CGRectMake(0, 0, _width, _height), image);
                CGContextRelease(context);
                _pixels = data;
            }
        }
    }
    return self;
}

- (void)setCenter:(CGPoint)center {
    [super setCenter:center];
    [self setNeedsDisplay];
}

- (BOOL)readPixelX:(NSInteger)x y:(NSInteger)y rgb:(CGFloat *)rgb {
    if (!_pixels || _width == 0 || _height == 0) return NO;
    x = MAX(0, MIN((NSInteger)_width - 1, x));
    y = MAX(0, MIN((NSInteger)_height - 1, y));
    const uint8_t *p = (const uint8_t *)_pixels.bytes + (size_t)y * _bytesPerRow + (size_t)x * 4;
    rgb[0] = p[0] / 255.0;
    rgb[1] = p[1] / 255.0;
    rgb[2] = p[2] / 255.0;
    return YES;
}

- (CGPoint)samplePixel {
    // The loupe lives in a full screen window, so its centre is a screen point.
    return CGPointMake(floor(self.center.x * _scale), floor(self.center.y * _scale));
}

- (UIColor *)pickedColor {
    CGPoint p = [self samplePixel];
    CGFloat sum[3] = {0, 0, 0};
    NSInteger count = 0;
    for (NSInteger dy = -1; dy <= 1; dy++) {
        for (NSInteger dx = -1; dx <= 1; dx++) {
            CGFloat rgb[3];
            if ([self readPixelX:(NSInteger)p.x + dx y:(NSInteger)p.y + dy rgb:rgb]) {
                sum[0] += rgb[0];
                sum[1] += rgb[1];
                sum[2] += rgb[2];
                count++;
            }
        }
    }
    if (count == 0) return nil;
    return [UIColor colorWithRed:sum[0] / count green:sum[1] / count blue:sum[2] / count alpha:1.0];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    CGRect circle = CGRectInset(self.bounds, 3.0, 3.0);
    CGFloat cell = circle.size.width / kLoupeCells;
    CGPoint p = [self samplePixel];

    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithOvalInRect:circle] addClip];
    for (NSInteger row = 0; row < kLoupeCells; row++) {
        for (NSInteger column = 0; column < kLoupeCells; column++) {
            CGFloat rgb[3] = {0, 0, 0};
            [self readPixelX:(NSInteger)p.x + column - kLoupeCells / 2 y:(NSInteger)p.y + row - kLoupeCells / 2 rgb:rgb];
            CGContextSetRGBFillColor(context, rgb[0], rgb[1], rgb[2], 1.0);
            CGContextFillRect(context, CGRectMake(circle.origin.x + column * cell, circle.origin.y + row * cell, cell + 0.5, cell + 0.5));
        }
    }
    // Grid
    CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 0.32);
    CGContextSetLineWidth(context, 1.0 / UIScreen.mainScreen.scale);
    for (NSInteger i = 1; i < kLoupeCells; i++) {
        CGFloat x = circle.origin.x + i * cell;
        CGFloat y = circle.origin.y + i * cell;
        CGContextMoveToPoint(context, x, CGRectGetMinY(circle));
        CGContextAddLineToPoint(context, x, CGRectGetMaxY(circle));
        CGContextMoveToPoint(context, CGRectGetMinX(circle), y);
        CGContextAddLineToPoint(context, CGRectGetMaxX(circle), y);
    }
    CGContextStrokePath(context);
    // Centre cell
    CGRect centre = CGRectMake(circle.origin.x + (kLoupeCells / 2) * cell, circle.origin.y + (kLoupeCells / 2) * cell, cell, cell);
    CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextSetLineWidth(context, 2.0);
    CGContextStrokeRect(context, CGRectInset(centre, 1.0, 1.0));
    CGContextRestoreGState(context);

    // Ring
    CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextSetLineWidth(context, 4.5);
    CGContextStrokeEllipseInRect(context, CGRectInset(circle, 2.25, 2.25));
    CGContextSetRGBStrokeColor(context, 0.0, 0.0, 0.0, 0.18);
    CGContextSetLineWidth(context, 1.0);
    CGContextStrokeEllipseInRect(context, CGRectInset(circle, -0.5, -0.5));
}

@end

#pragma mark - Panel

// Metrics follow the iOS 18 customization sheet.
static const CGFloat kCardRadius = 32.0;
static const CGFloat kSide = 18.0;          // inner padding of the sheet
static const CGFloat kTopRowY = 14.0;
static const CGFloat kTopRowHeight = 36.0;
static const CGFloat kTilesGap = 20.0;
static const CGFloat kCaptionHeight = 22.0;   // gap + 15 pt caption
static const CGFloat kSliderHeight = 30.0;
static const CGFloat kSliderGap = 16.0;
static const CGFloat kBottomPadding = 24.0;

@interface I18Panel () <UIGestureRecognizerDelegate>
@end

@implementation I18Panel {
    I18PanelWindow *_window;
    UIView *_root;
    UIView *_card;
    UIVisualEffectView *_material;

    I18SunButton *_sunButton;
    I18GlyphButton *_eyedropperButton;
    I18CapsuleSegment *_sizeSegment;
    NSArray<I18ModeTile *> *_tiles;
    I18GradientSlider *_hueSlider;
    I18GradientSlider *_toneSlider;

    UITapGestureRecognizer *_tap;
    UIPanGestureRecognizer *_rootPan;
    UIPanGestureRecognizer *_cardPan;

    I18Loupe *_loupe;
    BOOL _picking;
    BOOL _visible;
    CGFloat _cardHeight;
    NSTimer *_watchdog;
    UISelectionFeedbackGenerator *_selection;
}

+ (instancetype)shared {
    static I18Panel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        panel = [[I18Panel alloc] init];
    });
    return panel;
}

- (BOOL)isVisible {
    return _visible;
}

#pragma mark Building

- (void)buildInScene:(UIWindowScene *)scene frame:(CGRect)frame level:(UIWindowLevel)level {
    if (!_window || _window.windowScene != scene) {
        _window = [[I18PanelWindow alloc] initWithWindowScene:scene];
        _window.backgroundColor = UIColor.clearColor;

        _root = [[UIView alloc] initWithFrame:frame];
        _root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_window addSubview:_root];

        _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rootTapped:)];
        _tap.delegate = self;
        [_root addGestureRecognizer:_tap];

        _rootPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(loupePanned:)];
        _rootPan.delegate = self;
        _rootPan.maximumNumberOfTouches = 1;
        [_root addGestureRecognizer:_rootPan];

        [self buildCard];
        _selection = [[UISelectionFeedbackGenerator alloc] init];
    }
    _window.frame = frame;
    _window.windowLevel = level;
}

- (void)buildCard {
    _card = [[UIView alloc] init];
    _card.clipsToBounds = NO;
    [_root addSubview:_card];

    _material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    _material.clipsToBounds = YES;
    _material.layer.cornerRadius = kCardRadius;
    _material.layer.cornerCurve = kCACornerCurveContinuous;
    _material.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [_card addSubview:_material];

    _cardPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(cardPanned:)];
    _cardPan.delegate = self;
    [_card addGestureRecognizer:_cardPan];

    _sunButton = [[I18SunButton alloc] initWithFrame:CGRectZero];
    _sunButton.on = [I18Settings shared].dimWallpaper;
    _sunButton.accessibilityLabel = I18L(@"DimWallpaper");
    [_sunButton addTarget:self action:@selector(sunTapped) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_sunButton];

    _eyedropperButton = [[I18GlyphButton alloc] initWithSymbol:@"eyedropper"];
    _eyedropperButton.accessibilityLabel = I18L(@"PickColor");
    [_eyedropperButton addTarget:self action:@selector(eyedropperTapped) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_eyedropperButton];

    _sizeSegment = [[I18CapsuleSegment alloc] initWithTitles:@[I18L(@"Small"), I18L(@"Large")]];
    [_sizeSegment addTarget:self action:@selector(sizeChanged) forControlEvents:UIControlEventValueChanged];
    [_card addSubview:_sizeSegment];

    NSArray *styles = @[@(I18StyleLight), @(I18StyleDark), @(I18StyleAuto), @(I18StyleTinted)];
    NSArray *titles = @[I18L(@"Light"), I18L(@"Dark"), I18L(@"Auto"), I18L(@"Tinted")];
    NSMutableArray<I18ModeTile *> *tiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < styles.count; i++) {
        I18ModeTile *tile = [[I18ModeTile alloc] initWithStyle:(I18Style)[styles[i] integerValue] title:titles[i]];
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:tile];
        [tiles addObject:tile];
    }
    _tiles = tiles;

    __weak I18Panel *weakSelf = self;
    _hueSlider = [[I18GradientSlider alloc] initWithFrame:CGRectZero];
    NSMutableArray<UIColor *> *rainbow = [NSMutableArray array];
    for (int i = 0; i <= 12; i++) {
        [rainbow addObject:[UIColor colorWithHue:i / 12.0 saturation:1.0 brightness:1.0 alpha:1.0]];
    }
    _hueSlider.trackColors = rainbow;
    _hueSlider.thumbColorForValue = ^UIColor *(CGFloat value) {
        return [UIColor colorWithHue:value saturation:1.0 brightness:1.0 alpha:1.0];
    };
    _hueSlider.onChange = ^(CGFloat value, __unused BOOL finished) {
        [weakSelf hueChanged:value];
    };
    [_card addSubview:_hueSlider];

    _toneSlider = [[I18GradientSlider alloc] initWithFrame:CGRectZero];
    _toneSlider.thumbColorForValue = ^UIColor *(CGFloat value) {
        return [[I18Settings shared] colorForHue:[I18Settings shared].hue tone:value];
    };
    _toneSlider.onChange = ^(CGFloat value, __unused BOOL finished) {
        [weakSelf toneChanged:value];
    };
    [_card addSubview:_toneSlider];
}

#pragma mark Layout

- (BOOL)showsTintControls {
    return [I18Settings shared].style == I18StyleTinted;
}

- (CGFloat)tilesTop {
    return kTopRowY + kTopRowHeight + kTilesGap;
}

- (CGFloat)contentHeightWithTint:(BOOL)tint iconSize:(CGFloat)iconSize {
    CGFloat tilesBottom = [self tilesTop] + iconSize + 6.0 + kCaptionHeight;  // 6: room for the ring
    if (!tint) return tilesBottom + kBottomPadding;
    return tilesBottom + 18.0 + kSliderHeight + kSliderGap + kSliderHeight + kBottomPadding;
}

- (CGFloat)iconSizeForWidth:(CGFloat)width {
    // Tiles like iOS 18 (about 66 pt on a 375 pt wide screen).
    CGFloat column = (width - 2.0 * kSide) / 4.0;
    return MIN(68.0, floor(column - 18.0));
}

- (void)layoutCard {
    // The sheet spans the full width and sits on the bottom edge of the
    // screen; only its top corners are rounded.
    CGRect bounds = _root.bounds;
    CGFloat bottomInset = _window.safeAreaInsets.bottom;
    CGFloat width = bounds.size.width;
    CGFloat iconSize = [self iconSizeForWidth:width];
    BOOL tint = [self showsTintControls];

    _cardHeight = [self contentHeightWithTint:tint iconSize:iconSize] + bottomInset;
    _card.bounds = CGRectMake(0, 0, width, _cardHeight);
    _card.center = CGPointMake(bounds.size.width * 0.5, bounds.size.height - _cardHeight * 0.5);
    // Runs past the bottom edge, so nothing shows through while dragging down.
    _material.frame = CGRectMake(0, 0, width, _cardHeight + 80.0);

    CGFloat rowMid = kTopRowY + kTopRowHeight * 0.5;
    _sunButton.frame = CGRectMake(kSide - 8.0, rowMid - 20.0, 40.0, 40.0);
    _eyedropperButton.frame = CGRectMake(width - kSide - 32.0, rowMid - 20.0, 40.0, 40.0);
    CGFloat segmentWidth = MIN(180.0, width - 2.0 * (kSide + 56.0));
    _sizeSegment.frame = CGRectMake(round((width - segmentWidth) * 0.5), rowMid - 16.0, segmentWidth, 32.0);

    CGFloat column = (width - 2.0 * kSide) / _tiles.count;
    CGFloat tilesY = [self tilesTop];
    [_tiles enumerateObjectsUsingBlock:^(I18ModeTile *tile, NSUInteger index, __unused BOOL *stop) {
        tile.iconSize = iconSize;
        tile.frame = CGRectMake(kSide + column * index, tilesY, column, iconSize + 6.0 + kCaptionHeight);
    }];

    CGFloat slidersY = tilesY + iconSize + 6.0 + kCaptionHeight + 18.0;
    CGFloat sliderX = kSide + 2.0;
    _hueSlider.frame = CGRectMake(sliderX, slidersY, width - 2.0 * sliderX, kSliderHeight);
    _toneSlider.frame = CGRectMake(sliderX, slidersY + kSliderHeight + kSliderGap, width - 2.0 * sliderX, kSliderHeight);

    CGFloat tintAlpha = tint ? 1.0 : 0.0;
    _hueSlider.alpha = tintAlpha;
    _toneSlider.alpha = tintAlpha;
    _eyedropperButton.alpha = tintAlpha;
}

#pragma mark Sync with settings

- (void)refreshToneTrack {
    I18Settings *settings = [I18Settings shared];
    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    for (int i = 0; i <= 10; i++) {
        [colors addObject:[settings colorForHue:settings.hue tone:i / 10.0]];
    }
    _toneSlider.trackColors = colors;
    [_toneSlider refreshThumbColor];
}

- (void)refreshTintPreview {
    UIColor *tint = [I18Settings shared].tintColor;
    for (I18ModeTile *tile in _tiles) {
        tile.preview.tint = tint;
    }
}

- (void)syncControls {
    I18Settings *settings = [I18Settings shared];
    [_sizeSegment setSelectedIndex:settings.largeIcons ? 1 : 0 animated:NO];
    for (I18ModeTile *tile in _tiles) {
        tile.chosen = tile.style == settings.style;
    }
    if (!_hueSlider.dragging) _hueSlider.value = settings.hue;
    if (!_toneSlider.dragging) _toneSlider.value = settings.tone;
    [self refreshToneTrack];
    [self refreshTintPreview];
    [_sunButton setOn:settings.dimWallpaper animated:NO];
}

#pragma mark Show / hide

- (void)show {
    if (_visible) return;
    UIWindow *home = I18HomeScreenWindow();
    UIWindowScene *scene = home.windowScene;
    if (!home || !scene) return;

    I18EndHomeScreenEditing();
    [self buildInScene:scene frame:home.screen.bounds level:home.windowLevel + 3.0];
    _visible = YES;
    _picking = NO;
    _window.hidden = NO;
    _root.frame = _window.bounds;

    [self syncControls];
    [UIView performWithoutAnimation:^{
        [self layoutCard];
        self->_card.transform = CGAffineTransformMakeTranslation(0, self->_cardHeight + 60.0);
    }];
    [_selection prepare];
    [self startWatchdog];

    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

/// The panel belongs to the home screen. If an app comes to the front while
/// it is open (a notification was tapped, Siri, ...) it closes itself.
- (void)startWatchdog {
    [_watchdog invalidate];
    __weak I18Panel *weakSelf = self;
    _watchdog = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        I18Panel *panel = weakSelf;
        if (!panel || !panel->_visible) {
            [timer invalidate];
            return;
        }
        UIApplication *application = UIApplication.sharedApplication;
        SEL frontmost = NSSelectorFromString(@"_accessibilityFrontMostApplication");
        if ([application respondsToSelector:frontmost] && ((id (*)(id, SEL))objc_msgSend)(application, frontmost)) {
            [panel dismissAnimated:NO];
        }
    }];
}

- (void)dismissAnimated:(BOOL)animated {
    if (!_visible) return;
    _visible = NO;
    [_watchdog invalidate];
    _watchdog = nil;
    if (_picking) [self endPickingWithColor:nil restorePanel:NO];

    void (^finish)(BOOL) = ^(__unused BOOL finished) {
        if (self->_visible) return;
        self->_window.hidden = YES;
        self->_card.transform = CGAffineTransformIdentity;
    };
    if (!animated) {
        finish(YES);
        return;
    }
    [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_card.transform = CGAffineTransformMakeTranslation(0, self->_cardHeight + 60.0);
    } completion:finish];
}

#pragma mark Actions

- (void)tileTapped:(I18ModeTile *)tile {
    I18Settings *settings = [I18Settings shared];
    if (settings.style == tile.style) return;
    BOOL wasTint = [self showsTintControls];
    settings.style = tile.style;
    [_selection selectionChanged];
    for (I18ModeTile *other in _tiles) {
        other.chosen = other == tile;
    }
    I18ApplyLook(YES);

    if (wasTint != [self showsTintControls]) {
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            [self layoutCard];
        } completion:nil];
    }
}

- (void)sizeChanged {
    [I18Settings shared].largeIcons = _sizeSegment.selectedIndex == 1;
    I18ApplyIconSize(YES);
}

- (void)sunTapped {
    I18Settings *settings = [I18Settings shared];
    settings.dimWallpaper = !settings.dimWallpaper;
    [_selection selectionChanged];
    [_sunButton setOn:settings.dimWallpaper animated:YES];
    I18WallpaperDimUpdate(YES);
}

- (void)hueChanged:(CGFloat)value {
    [I18Settings shared].hue = value;
    [self refreshToneTrack];
    [self refreshTintPreview];
    I18ApplyTint();
}

- (void)toneChanged:(CGFloat)value {
    [I18Settings shared].tone = value;
    [self refreshTintPreview];
    I18ApplyTint();
}

#pragma mark Gestures

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *view = touch.view;
    if (recognizer == _rootPan) return _picking;
    if (recognizer == _tap) {
        if (_picking) return YES;
        return ![view isDescendantOfView:_card];
    }
    if (recognizer == _cardPan) {
        if (_picking) return NO;
        for (UIView *v = view; v && v != _card; v = v.superview) {
            if ([v isKindOfClass:[UIControl class]]) return NO;
        }
        return YES;
    }
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer == _cardPan) {
        CGPoint velocity = [_cardPan velocityInView:_card];
        return fabs(velocity.y) > fabs(velocity.x);
    }
    return YES;
}

- (void)rootTapped:(UITapGestureRecognizer *)recognizer {
    if (_picking) {
        [self endPickingWithColor:[_loupe pickedColor] restorePanel:YES];
        return;
    }
    [self dismissAnimated:YES];
}

- (void)cardPanned:(UIPanGestureRecognizer *)recognizer {
    CGFloat dy = MAX(0.0, [recognizer translationInView:_root].y);
    switch (recognizer.state) {
        case UIGestureRecognizerStateChanged:
            _card.transform = CGAffineTransformMakeTranslation(0, dy);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat velocity = [recognizer velocityInView:_root].y;
            if (dy > _cardHeight * 0.35 || velocity > 700.0) {
                [self dismissAnimated:YES];
            } else {
                [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0
                                    options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                    self->_card.transform = CGAffineTransformIdentity;
                } completion:nil];
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark Eyedropper

- (void)eyedropperTapped {
    if (_picking || ![self showsTintControls]) return;
    _picking = YES;
    [_selection selectionChanged];

    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_card.transform = CGAffineTransformMakeTranslation(0, self->_cardHeight + 60.0);
    } completion:nil];
    I18SetHomeScreenContentHidden(YES, YES);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_picking) return;
        self->_window.hidden = YES;
        UIImage *screenshot = I18CaptureScreen(self->_window.windowScene, self->_window);
        self->_window.hidden = NO;
        if (!screenshot) {
            [self endPickingWithColor:nil restorePanel:YES];
            return;
        }
        self->_loupe = [[I18Loupe alloc] initWithScreenshot:screenshot];
        self->_loupe.center = CGPointMake(CGRectGetMidX(self->_root.bounds), CGRectGetMidY(self->_root.bounds));
        self->_loupe.transform = CGAffineTransformMakeScale(0.5, 0.5);
        self->_loupe.alpha = 0.0;
        [self->_root addSubview:self->_loupe];
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{
            self->_loupe.transform = CGAffineTransformIdentity;
            self->_loupe.alpha = 1.0;
        } completion:nil];
    });
}

- (void)loupePanned:(UIPanGestureRecognizer *)recognizer {
    if (!_picking || !_loupe) return;
    CGPoint translation = [recognizer translationInView:_root];
    [recognizer setTranslation:CGPointZero inView:_root];
    CGRect bounds = _root.bounds;
    CGPoint center = _loupe.center;
    center.x = MAX(0.0, MIN(bounds.size.width - 1.0, center.x + translation.x));
    center.y = MAX(0.0, MIN(bounds.size.height - 1.0, center.y + translation.y));
    _loupe.center = center;

    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self endPickingWithColor:[_loupe pickedColor] restorePanel:YES];
    } else if (recognizer.state == UIGestureRecognizerStateCancelled) {
        [self endPickingWithColor:nil restorePanel:YES];
    }
}

- (void)endPickingWithColor:(UIColor *)color restorePanel:(BOOL)restore {
    if (!_picking) return;
    _picking = NO;

    I18Loupe *loupe = _loupe;
    _loupe = nil;
    [UIView animateWithDuration:0.2 animations:^{
        loupe.alpha = 0.0;
        loupe.transform = CGAffineTransformMakeScale(0.6, 0.6);
    } completion:^(__unused BOOL finished) {
        [loupe removeFromSuperview];
    }];
    I18SetHomeScreenContentHidden(NO, YES);

    if (color) {
        [[I18Settings shared] setColorFromPickedColor:color];
        [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self syncControls];
        I18ApplyTint();
    }
    if (!restore || !_visible) return;
    [UIView animateWithDuration:0.5 delay:0.05 usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
