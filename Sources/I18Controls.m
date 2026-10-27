//
//  I18Controls.m
//  iOS18Customization
//

#import "I18Controls.h"

static UIColor *I18Dynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

#pragma mark - Capsule segment

@implementation I18CapsuleSegment {
    NSArray<UILabel *> *_labels;
    UIView *_track;
    UIView *_pill;
    UISelectionFeedbackGenerator *_haptic;
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles {
    if ((self = [super initWithFrame:CGRectZero])) {
        _track = [[UIView alloc] init];
        _track.userInteractionEnabled = NO;
        _track.backgroundColor = I18Dynamic([UIColor colorWithWhite:0.0 alpha:0.07], [UIColor colorWithWhite:1.0 alpha:0.10]);
        [self addSubview:_track];

        _pill = [[UIView alloc] init];
        _pill.userInteractionEnabled = NO;
        _pill.backgroundColor = I18Dynamic(UIColor.whiteColor, [UIColor colorWithWhite:1.0 alpha:0.24]);
        _pill.layer.shadowColor = UIColor.blackColor.CGColor;
        _pill.layer.shadowOffset = CGSizeMake(0, 1);
        _pill.layer.shadowRadius = 3;
        [self addSubview:_pill];

        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        for (NSString *title in titles) {
            UILabel *label = [[UILabel alloc] init];
            label.text = title;
            label.textAlignment = NSTextAlignmentCenter;
            label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.75;
            label.userInteractionEnabled = NO;
            [self addSubview:label];
            [labels addObject:label];
        }
        _labels = labels;
        _haptic = [[UISelectionFeedbackGenerator alloc] init];
        [self updateLabels];
        [self updateShadow];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(170.0, 32.0);
}

- (CGRect)pillFrameForIndex:(NSInteger)index {
    if (_labels.count == 0) return CGRectZero;
    CGFloat width = self.bounds.size.width / _labels.count;
    return CGRectInset(CGRectMake(width * index, 0, width, self.bounds.size.height), 2.0, 2.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.bounds.size.height;
    _track.frame = self.bounds;
    _track.layer.cornerRadius = height * 0.5;
    _pill.frame = [self pillFrameForIndex:_selectedIndex];
    _pill.layer.cornerRadius = _pill.bounds.size.height * 0.5;
    CGFloat width = self.bounds.size.width / MAX(1, (NSInteger)_labels.count);
    [_labels enumerateObjectsUsingBlock:^(UILabel *label, NSUInteger index, __unused BOOL *stop) {
        label.frame = CGRectInset(CGRectMake(width * index, 0, width, height), 6.0, 0.0);
    }];
}

- (void)updateLabels {
    [_labels enumerateObjectsUsingBlock:^(UILabel *label, NSUInteger index, __unused BOOL *stop) {
        label.textColor = (NSInteger)index == self->_selectedIndex ? UIColor.labelColor : UIColor.secondaryLabelColor;
    }];
}

- (void)updateShadow {
    _pill.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.0f : 0.12f;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self updateShadow];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    [self setSelectedIndex:selectedIndex animated:NO];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated {
    selectedIndex = MAX(0, MIN((NSInteger)_labels.count - 1, selectedIndex));
    _selectedIndex = selectedIndex;
    void (^changes)(void) = ^{
        self->_pill.frame = [self pillFrameForIndex:selectedIndex];
    };
    if (animated) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState animations:changes completion:nil];
        [UIView transitionWithView:self duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent
                        animations:^{ [self updateLabels]; } completion:nil];
    } else {
        changes();
        [self updateLabels];
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_haptic prepare];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];
    if (!touch || _labels.count == 0) return;
    CGPoint point = [touch locationInView:self];
    if (!CGRectContainsPoint(CGRectInset(self.bounds, -10, -14), point)) return;
    NSInteger index = (NSInteger)floor(point.x / (self.bounds.size.width / _labels.count));
    index = MAX(0, MIN((NSInteger)_labels.count - 1, index));
    if (index == _selectedIndex) return;
    [self setSelectedIndex:index animated:YES];
    [_haptic selectionChanged];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - Gradient slider

static const CGFloat kTrackHeight = 26.0;
static const CGFloat kThumbSize = 30.0;

@implementation I18GradientSlider {
    CAGradientLayer *_track;
    UIView *_thumb;
    CGFloat _grabOffset;
    UIImpactFeedbackGenerator *_impact;
    BOOL _pinned;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _track = [CAGradientLayer layer];
        _track.startPoint = CGPointMake(0.0, 0.5);
        _track.endPoint = CGPointMake(1.0, 0.5);
        _track.cornerCurve = kCACornerCurveContinuous;
        [self.layer addSublayer:_track];

        _thumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kThumbSize, kThumbSize)];
        _thumb.userInteractionEnabled = NO;
        _thumb.layer.cornerRadius = kThumbSize * 0.5;
        _thumb.layer.borderWidth = 3.5;
        _thumb.layer.borderColor = UIColor.whiteColor.CGColor;
        _thumb.layer.shadowColor = UIColor.blackColor.CGColor;
        _thumb.layer.shadowOpacity = 0.28f;
        _thumb.layer.shadowRadius = 4.0;
        _thumb.layer.shadowOffset = CGSizeMake(0, 1.5);
        [self addSubview:_thumb];

        _impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    }
    return self;
}

- (CGFloat)inset {
    return kTrackHeight * 0.5;
}

- (CGFloat)xForValue:(CGFloat)value {
    CGFloat inset = [self inset];
    return inset + value * MAX(1.0, self.bounds.size.width - 2.0 * inset);
}

- (CGFloat)valueForX:(CGFloat)x {
    CGFloat inset = [self inset];
    CGFloat value = (x - inset) / MAX(1.0, self.bounds.size.width - 2.0 * inset);
    return MAX(0.0, MIN(1.0, value));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.frame = CGRectMake(0, round((self.bounds.size.height - kTrackHeight) * 0.5), self.bounds.size.width, kTrackHeight);
    _track.cornerRadius = kTrackHeight * 0.5;
    [CATransaction commit];
    [self placeThumb];
}

- (void)placeThumb {
    _thumb.center = CGPointMake([self xForValue:_value], self.bounds.size.height * 0.5);
}

- (void)setValue:(CGFloat)value {
    _value = isnan(value) ? 0.0 : MAX(0.0, MIN(1.0, value));
    [self placeThumb];
    [self refreshThumbColor];
}

- (void)setTrackColors:(NSArray<UIColor *> *)trackColors {
    _trackColors = [trackColors copy];
    NSMutableArray *colors = [NSMutableArray array];
    for (UIColor *color in trackColors) [colors addObject:(__bridge id)color.CGColor];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.colors = colors;
    [CATransaction commit];
}

- (void)refreshThumbColor {
    UIColor *color = self.thumbColorForValue ? self.thumbColorForValue(_value) : nil;
    _thumb.backgroundColor = color ?: UIColor.whiteColor;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -6.0, -10.0), point);
}

- (void)notifyFinished:(BOOL)finished {
    if (self.onChange) self.onChange(_value, finished);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)setThumbLifted:(BOOL)lifted {
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_thumb.transform = lifted ? CGAffineTransformMakeScale(1.14, 1.14) : CGAffineTransformIdentity;
    } completion:nil];
}

- (void)checkEdgeHaptic {
    BOOL pinned = _value <= 0.0 || _value >= 1.0;
    if (pinned && !_pinned) [_impact impactOccurred];
    _pinned = pinned;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point = [touch locationInView:self];
    _dragging = YES;
    [_impact prepare];
    if (fabs(point.x - _thumb.center.x) <= kThumbSize * 0.75) {
        _grabOffset = point.x - _thumb.center.x;
    } else {
        _grabOffset = 0.0;
        self.value = [self valueForX:point.x];
        [self notifyFinished:NO];
    }
    _pinned = _value <= 0.0 || _value >= 1.0;
    [self setThumbLifted:YES];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point = [touch locationInView:self];
    CGFloat value = [self valueForX:point.x - _grabOffset];
    if (fabs(value - _value) > 0.0005) {
        self.value = value;
        [self checkEdgeHaptic];
        [self notifyFinished:NO];
    }
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];
    _dragging = NO;
    [self setThumbLifted:NO];
    [self notifyFinished:YES];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [super cancelTrackingWithEvent:event];
    _dragging = NO;
    [self setThumbLifted:NO];
    [self notifyFinished:YES];
}

@end

#pragma mark - Style preview

static void I18FillGradient(CGContextRef context, UIBezierPath *path, UIColor *top, UIColor *bottom, CGRect area) {
    CGContextSaveGState(context);
    [path addClip];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(__bridge id)top.CGColor, (__bridge id)bottom.CGColor];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, CGRectGetMinY(area)), CGPointMake(0, CGRectGetMaxY(area)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(context);
}

static UIBezierPath *I18CloudPath(CGFloat s) {
    CGRect r = CGRectMake(s * 0.15, s * 0.40, s * 0.64, s * 0.38);
    CGFloat w = r.size.width, h = r.size.height, x = r.origin.x, y = r.origin.y;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y + h * 0.42, w, h * 0.58) cornerRadius:h * 0.29];
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x + w * 0.10, y + h * 0.20, w * 0.40, w * 0.40)]];
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x + w * 0.34, y - h * 0.08, w * 0.52, w * 0.52)]];
    return path;
}

static UIColor *I18Scale(UIColor *color, CGFloat factor, CGFloat lift) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [UIColor colorWithRed:MIN(1, r * factor + lift) green:MIN(1, g * factor + lift) blue:MIN(1, b * factor + lift) alpha:a];
}

static UIColor *I18Mix(UIColor *color, UIColor *other, CGFloat amount) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1, r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    [color getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [other getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * amount green:g1 + (g2 - g1) * amount blue:b1 + (b2 - b1) * amount alpha:1.0];
}

@implementation I18StylePreview

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        _tint = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0];
    }
    return self;
}

- (void)setStyle:(I18Style)style {
    _style = style;
    [self setNeedsDisplay];
}

- (void)setTint:(UIColor *)tint {
    _tint = tint;
    if (_style == I18StyleTinted) [self setNeedsDisplay];
}

- (void)drawVariant:(I18Style)variant inContext:(CGContextRef)context size:(CGFloat)s {
    CGRect area = CGRectMake(0, 0, s, s);
    UIBezierPath *plate = [UIBezierPath bezierPathWithRect:area];
    UIBezierPath *sun = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(s * 0.47, s * 0.20, s * 0.34, s * 0.34)];
    UIBezierPath *cloud = I18CloudPath(s);

    UIColor *plateTop, *plateBottom, *sunTop, *sunBottom, *cloudTop, *cloudBottom;
    switch (variant) {
        case I18StyleTinted: {
            UIColor *tint = self.tint ?: UIColor.systemBlueColor;
            plateTop = I18Scale(tint, 0.22, 0.05);
            plateBottom = I18Scale(tint, 0.08, 0.02);
            sunTop = I18Scale(tint, 0.62, 0.0);
            sunBottom = I18Scale(tint, 0.48, 0.0);
            cloudTop = I18Mix(tint, UIColor.whiteColor, 0.18);
            cloudBottom = I18Scale(tint, 0.86, 0.0);
            break;
        }
        case I18StyleDark:
            plateTop = [UIColor colorWithWhite:0.20 alpha:1.0];
            plateBottom = [UIColor colorWithWhite:0.08 alpha:1.0];
            sunTop = [UIColor colorWithRed:1.0 green:0.85 blue:0.28 alpha:1.0];
            sunBottom = [UIColor colorWithRed:0.98 green:0.66 blue:0.10 alpha:1.0];
            cloudTop = [UIColor colorWithWhite:0.96 alpha:1.0];
            cloudBottom = [UIColor colorWithWhite:0.70 alpha:1.0];
            break;
        default:
            plateTop = [UIColor colorWithRed:0.36 green:0.70 blue:1.0 alpha:1.0];
            plateBottom = [UIColor colorWithRed:0.10 green:0.43 blue:0.96 alpha:1.0];
            sunTop = [UIColor colorWithRed:1.0 green:0.88 blue:0.30 alpha:1.0];
            sunBottom = [UIColor colorWithRed:1.0 green:0.70 blue:0.10 alpha:1.0];
            cloudTop = UIColor.whiteColor;
            cloudBottom = [UIColor colorWithRed:0.86 green:0.90 blue:0.97 alpha:1.0];
            break;
    }

    I18FillGradient(context, plate, plateTop, plateBottom, area);
    I18FillGradient(context, sun, sunTop, sunBottom, sun.bounds);

    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0, s * 0.02), s * 0.05, [UIColor colorWithWhite:0 alpha:0.25].CGColor);
    [cloudBottom setFill];
    [cloud fill];
    CGContextRestoreGState(context);
    I18FillGradient(context, cloud, cloudTop, cloudBottom, cloud.bounds);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    CGFloat s = MIN(self.bounds.size.width, self.bounds.size.height);
    UIBezierPath *squircle = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:s * 0.225];
    CGContextSaveGState(context);
    [squircle addClip];

    if (_style == I18StyleAuto) {
        CGContextSaveGState(context);
        UIBezierPath *lightHalf = [UIBezierPath bezierPath];
        [lightHalf moveToPoint:CGPointMake(0, 0)];
        [lightHalf addLineToPoint:CGPointMake(s, 0)];
        [lightHalf addLineToPoint:CGPointMake(0, s)];
        [lightHalf closePath];
        [lightHalf addClip];
        [self drawVariant:I18StyleLight inContext:context size:s];
        CGContextRestoreGState(context);

        CGContextSaveGState(context);
        UIBezierPath *darkHalf = [UIBezierPath bezierPath];
        [darkHalf moveToPoint:CGPointMake(s, 0)];
        [darkHalf addLineToPoint:CGPointMake(s, s)];
        [darkHalf addLineToPoint:CGPointMake(0, s)];
        [darkHalf closePath];
        [darkHalf addClip];
        [self drawVariant:I18StyleDark inContext:context size:s];
        CGContextRestoreGState(context);
    } else {
        [self drawVariant:_style inContext:context size:s];
    }
    CGContextRestoreGState(context);
}

@end

#pragma mark - Mode tile

@implementation I18ModeTile {
    UILabel *_caption;
    CAShapeLayer *_ring;
}

- (instancetype)initWithStyle:(I18Style)style title:(NSString *)title {
    if ((self = [super initWithFrame:CGRectZero])) {
        _style = style;
        _iconSize = 64.0;

        _ring = [CAShapeLayer layer];
        _ring.fillColor = UIColor.clearColor.CGColor;
        _ring.lineWidth = 2.0;
        _ring.opacity = 0.0f;
        [self.layer addSublayer:_ring];

        _preview = [[I18StylePreview alloc] initWithFrame:CGRectZero];
        _preview.style = style;
        _preview.userInteractionEnabled = NO;
        [self addSubview:_preview];

        _caption = [[UILabel alloc] init];
        _caption.text = title;
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.adjustsFontSizeToFitWidth = YES;
        _caption.minimumScaleFactor = 0.7;
        _caption.userInteractionEnabled = NO;
        [self addSubview:_caption];

        self.accessibilityLabel = title;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self updateAppearance:NO];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat s = _iconSize;
    CGFloat x = round((self.bounds.size.width - s) * 0.5);
    _preview.frame = CGRectMake(x, 4.0, s, s);
    _caption.frame = CGRectMake(0, CGRectGetMaxY(_preview.frame) + 8.0, self.bounds.size.width, 18.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect ringRect = CGRectInset(_preview.frame, -3.5, -3.5);
    _ring.frame = self.bounds;
    _ring.path = [UIBezierPath bezierPathWithRoundedRect:ringRect cornerRadius:s * 0.225 + 3.5].CGPath;
    _ring.strokeColor = [UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    [CATransaction commit];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self setNeedsLayout];
}

- (void)setIconSize:(CGFloat)iconSize {
    _iconSize = iconSize;
    [self setNeedsLayout];
}

- (void)setChosen:(BOOL)chosen {
    if (_chosen == chosen) return;
    _chosen = chosen;
    [self updateAppearance:YES];
}

- (void)updateAppearance:(BOOL)animated {
    _caption.font = [UIFont systemFontOfSize:12.5 weight:_chosen ? UIFontWeightSemibold : UIFontWeightRegular];
    _caption.textColor = _chosen ? UIColor.labelColor : UIColor.secondaryLabelColor;
    float target = _chosen ? 0.32f : 0.0f;
    if (animated) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(_ring.presentationLayer ? _ring.presentationLayer.opacity : _ring.opacity);
        fade.toValue = @(target);
        fade.duration = 0.2;
        [_ring addAnimation:fade forKey:@"fade"];
    }
    _ring.opacity = target;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:highlighted ? 0.1 : 0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_preview.transform = highlighted ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - Glyph button

@implementation I18GlyphButton

- (instancetype)initWithSymbol:(NSString *)symbol {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.tintColor = UIColor.labelColor;
        [self setSymbol:symbol];
    }
    return self;
}

- (void)setSymbol:(NSString *)symbol {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightRegular];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:configuration];
    [self setImage:image forState:UIControlStateNormal];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.45 : 1.0;
}

@end
