//
//  I18Settings.m
//  iOS18Customization
//
//  Settings live in SpringBoard's own preferences domain
//  (/var/mobile/Library/Preferences/com.timoshka69.ios18customization.plist),
//  there is no Settings pane - everything is changed from the home screen.
//

#import "I18Shared.h"
#include <notify.h>

NSString *const I18SettingsDidChangeNotification = @"I18SettingsDidChangeNotification";

static NSString *const kStyleKey = @"Style";
static NSString *const kHueKey = @"TintHue";
static NSString *const kToneKey = @"TintTone";
static NSString *const kLargeKey = @"LargeIcons";
static NSString *const kDimKey = @"DimWallpaper";

@implementation I18Settings {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static I18Settings *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        settings = [[I18Settings alloc] init];
    });
    return settings;
}

- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:I18_BUNDLE_ID];
        [_defaults registerDefaults:@{
            kStyleKey: @(I18StyleLight),
            kHueKey: @(0.62),
            kToneKey: @(0.10),
            kLargeKey: @NO,
            kDimKey: @NO,
        }];
        [self readValues];
    }
    return self;
}

- (void)readValues {
    NSInteger style = [_defaults integerForKey:kStyleKey];
    _style = (style >= I18StyleLight && style <= I18StyleTinted) ? (I18Style)style : I18StyleLight;
    _hue = [self clamp:[_defaults doubleForKey:kHueKey]];
    _tone = [self clamp:[_defaults doubleForKey:kToneKey]];
    _largeIcons = [_defaults boolForKey:kLargeKey];
    _dimWallpaper = [_defaults boolForKey:kDimKey];
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)I18_BUNDLE_ID);
    [_defaults synchronize];
    [self readValues];
}

- (CGFloat)clamp:(CGFloat)value {
    if (isnan(value)) return 0.0;
    return MAX(0.0, MIN(1.0, value));
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:I18SettingsDidChangeNotification object:self];
}

- (void)setStyle:(I18Style)style {
    if (_style == style) return;
    _style = style;
    [_defaults setInteger:style forKey:kStyleKey];
    [self changed];
}

- (void)setHue:(CGFloat)hue {
    _hue = [self clamp:hue];
    [_defaults setDouble:_hue forKey:kHueKey];
    [self changed];
}

- (void)setTone:(CGFloat)tone {
    _tone = [self clamp:tone];
    [_defaults setDouble:_tone forKey:kToneKey];
    [self changed];
}

- (void)setLargeIcons:(BOOL)largeIcons {
    if (_largeIcons == largeIcons) return;
    _largeIcons = largeIcons;
    [_defaults setBool:largeIcons forKey:kLargeKey];
    [self changed];
}

- (void)setDimWallpaper:(BOOL)dimWallpaper {
    if (_dimWallpaper == dimWallpaper) return;
    _dimWallpaper = dimWallpaper;
    [_defaults setBool:dimWallpaper forKey:kDimKey];
    [self changed];
}

static UIUserInterfaceStyle gObservedStyle = UIUserInterfaceStyleUnspecified;

- (void)noteSystemStyle:(UIUserInterfaceStyle)style {
    gObservedStyle = style;
}

- (BOOL)systemIsDark {
    UIUserInterfaceStyle style = gObservedStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleDark;
}

- (I18Look)look {
    switch (_style) {
        case I18StyleLight: return I18LookStock;
        case I18StyleDark: return I18LookDark;
        case I18StyleAuto: return self.systemIsDark ? I18LookDark : I18LookStock;
        case I18StyleTinted: return I18LookTinted;
    }
    return I18LookStock;
}

- (void)tintRGB:(float[3])rgb {
    I18FXTintColor((float)_hue, (float)_tone, rgb);
}

- (UIColor *)colorForHue:(CGFloat)hue tone:(CGFloat)tone {
    float rgb[3];
    I18FXTintColor((float)hue, (float)tone, rgb);
    return [UIColor colorWithRed:rgb[0] green:rgb[1] blue:rgb[2] alpha:1.0];
}

- (UIColor *)tintColor {
    return [self colorForHue:_hue tone:_tone];
}

- (void)setColorFromPickedColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&a]) return;
        r = g = b = white;
    }
    float rgb[3] = {(float)r, (float)g, (float)b};
    float hue = 0, tone = 0;
    I18FXHueToneFromRGB(rgb, &hue, &tone);
    _hue = [self clamp:hue];
    _tone = [self clamp:tone];
    [_defaults setDouble:_hue forKey:kHueKey];
    [_defaults setDouble:_tone forKey:kToneKey];
    [self changed];
}

@end

void I18PostChangedNotification(void) {
    // Coalesced: the sliders call this many times a second.
    static BOOL pending;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pending = NO;
        CFPreferencesAppSynchronize((__bridge CFStringRef)I18_BUNDLE_ID);
        notify_post(I18_CHANGED_NOTIFICATION);
    });
}

#pragma mark - Localisation

NSString *I18L(NSString *key) {
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *language = NSLocale.preferredLanguages.firstObject.lowercaseString ?: @"en";
        BOOL russian = [language hasPrefix:@"ru"] || [language hasPrefix:@"uk"] || [language hasPrefix:@"be"] || [language hasPrefix:@"kk"];
        if (russian) {
            table = @{
                @"Edit": @"Изменить",
                @"AddWidget": @"Добавить виджет",
                @"Customize": @"Настроить",
                @"Small": @"Малые",
                @"Large": @"Крупные",
                @"Light": @"Светлые",
                @"Dark": @"Тёмные",
                @"Auto": @"Авто",
                @"Tinted": @"Цвет",
                @"DimWallpaper": @"Затемнить обои",
                @"PickColor": @"Пипетка",
            };
        } else {
            table = @{
                @"Edit": @"Edit",
                @"AddWidget": @"Add Widget",
                @"Customize": @"Customize",
                @"Small": @"Small",
                @"Large": @"Large",
                @"Light": @"Light",
                @"Dark": @"Dark",
                @"Auto": @"Automatic",
                @"Tinted": @"Tinted",
                @"DimWallpaper": @"Dim Wallpaper",
                @"PickColor": @"Eyedropper",
            };
        }
    });
    return table[key] ?: key;
}
