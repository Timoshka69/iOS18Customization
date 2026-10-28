//
//  I18Controls.h
//  iOS18Customization
//
//  The controls of the customization panel, drawn by hand so they look like
//  iOS 18 on iOS 15 instead of using the iOS 15 system controls.
//

#import "I18Shared.h"

NS_ASSUME_NONNULL_BEGIN

/// "Small | Large" capsule switch.
@interface I18CapsuleSegment : UIControl
- (instancetype)initWithTitles:(NSArray<NSString *> *)titles;
@property (nonatomic) NSInteger selectedIndex;
- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated;
@end

/// Thick gradient track with a round thumb (hue / tone sliders).
@interface I18GradientSlider : UIControl
@property (nonatomic) CGFloat value; // 0...1
@property (nonatomic, copy) NSArray<UIColor *> *trackColors;
@property (nonatomic, copy, nullable) UIColor * (^thumbColorForValue)(CGFloat value);
@property (nonatomic, copy, nullable) void (^onChange)(CGFloat value, BOOL finished);
@property (nonatomic, readonly, getter=isDragging) BOOL dragging;
- (void)refreshThumbColor;
@end

/// The weather-style preview icon of a mode tile.
@interface I18StylePreview : UIView
@property (nonatomic) I18Style style;
@property (nonatomic, strong) UIColor *tint;
@end

/// Preview icon + caption, with the iOS 18 selection ring.
@interface I18ModeTile : UIControl
- (instancetype)initWithStyle:(I18Style)style title:(NSString *)title;
@property (nonatomic, readonly) I18Style style;
@property (nonatomic, readonly) I18StylePreview *preview;
@property (nonatomic, getter=isChosen) BOOL chosen;
@property (nonatomic) CGFloat iconSize;
@end

/// The iOS 18 wallpaper dimming button (drawn sun, half / fully filled).
@interface I18SunButton : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

/// Round icon button (eyedropper).
@interface I18GlyphButton : UIButton
- (instancetype)initWithSymbol:(NSString *)symbol;
- (void)setSymbol:(NSString *)symbol;
@end

NS_ASSUME_NONNULL_END
