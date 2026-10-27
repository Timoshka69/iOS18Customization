//
//  I18Shared.h
//  iOS18Customization
//
//  Declarations shared by all parts of the tweak.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "I18ImageFX.h"

NS_ASSUME_NONNULL_BEGIN

#define I18_BUNDLE_ID @"com.timoshka69.ios18customization"

#ifdef DEBUG
#define I18Log(fmt, ...) NSLog(@"[iOS18Customization] " fmt, ##__VA_ARGS__)
#else
#define I18Log(fmt, ...) do {} while (0)
#endif

#pragma mark - Settings

typedef NS_ENUM(NSInteger, I18Style) {
    I18StyleLight = 0,
    I18StyleDark = 1,
    I18StyleAuto = 2,
    I18StyleTinted = 3,
};

/// What the icons currently look like after "Auto" has been resolved.
typedef NS_ENUM(NSInteger, I18Look) {
    I18LookStock = 0,
    I18LookDark = 1,
    I18LookTinted = 2,
};

extern NSString *const I18SettingsDidChangeNotification;

@interface I18Settings : NSObject
+ (instancetype)shared;

@property (nonatomic) I18Style style;
@property (nonatomic) CGFloat hue;      // 0...1, first slider
@property (nonatomic) CGFloat tone;     // 0...1, second slider
@property (nonatomic) BOOL largeIcons;  // "Крупные"
@property (nonatomic) BOOL dimWallpaper;

@property (nonatomic, readonly) I18Look look;
@property (nonatomic, readonly) BOOL systemIsDark;

- (void)tintRGB:(float[_Nonnull 3])rgb;
- (UIColor *)tintColor;
- (UIColor *)colorForHue:(CGFloat)hue tone:(CGFloat)tone;
- (void)setColorFromPickedColor:(UIColor *)color;
/// Light / dark as reported by a view inside SpringBoard's own scene.
- (void)noteSystemStyle:(UIUserInterfaceStyle)style;
/// Reads the values again (another process changed them).
- (void)reload;
@end

#pragma mark - Hooking helpers (I18Runtime.m)

/// Hooks an instance method. Works for methods the class only inherits as
/// well (an override that calls the inherited implementation is added).
/// Returns NO and leaves `original` untouched when the selector is missing,
/// so every hook in the tweak is optional.
BOOL I18HookMethod(Class _Nullable cls, SEL sel, IMP replacement, IMP _Nullable * _Nonnull original);

/// Safe KVC read that never throws.
id _Nullable I18ValueForKey(id _Nullable object, NSString *key);

/// Calls a selector that takes and returns nothing / an object, if present.
id _Nullable I18Call(id _Nullable target, NSString *selectorName);

BOOL I18ClassNameContains(id _Nullable object, NSString *needle);

#pragma mark - Icon contents (I18Contents.m)

/// Marks a layer tree as ours: every CGImage that is put into these layers
/// is passed through the dark / tinted conversion from now on.
void I18AdoptLayerTree(CALayer *layer, BOOL clock);

/// Puts the right contents into every adopted layer again (after a style
/// change). With `animated` the change is cross-faded.
void I18ReprocessAllContents(BOOL animated);

/// Re-checks one icon's layers: contents in the right look, tint filter in
/// place. Cheap; used whenever SpringBoard re-lays out an icon.
void I18VerifyLayerTree(CALayer *root);

/// The resolved look used by the layer subclass (kept in a plain global so it
/// can be read from any thread).
I18Look I18CurrentLook(void);
void I18SetCurrentLook(I18Look look);

/// What a tinted layer is: decides which colour matrix it gets.
typedef NS_ENUM(NSInteger, I18TintKind) {
    I18TintNone = 0,
    I18TintIcon = 1,
    I18TintWidget = 2,
    I18TintBadge = 3,
};

/// Builds the colour matrix filter used for tinted icons, widgets, badges.
id _Nullable I18MakeMatrixFilter(I18FXMatrix matrix);
I18FXMatrix I18MatrixForTintKind(I18TintKind kind);
void I18TintBadgeColor(float rgb[_Nonnull 3]);
/// Gives a layer the tint of `kind` (only shown while the look is Tinted).
/// Every such layer is remembered, so a colour change reaches all of them.
void I18SetTintFilter(CALayer *layer, I18TintKind kind);
/// The colour changed: every tinted layer gets the new matrix.
void I18RefreshTintFilters(void);
void I18InstallFilterHooks(void);

#pragma mark - Home screen (I18HomeScreen.m)

void I18InstallHomeScreenHooks(void);
void I18ApplyLook(BOOL animated);        // style changed
void I18ApplyTint(void);                 // only the colour changed
void I18ApplyIconSize(BOOL animated);    // Small / Large changed
UIWindow * _Nullable I18HomeScreenWindow(void);
void I18SetHomeScreenContentHidden(BOOL hidden, BOOL animated);
void I18EndHomeScreenEditing(void);
/// Finds and restyles every icon on screen (after lock / unlock, style changes).
void I18SweepHomeScreen(void);
/// Sweep once the user stops changing things (sliders, eyedropper).
void I18ScheduleSweep(NSTimeInterval delay);

#pragma mark - Edit button (I18EditButton.m)

void I18SyncEditButton(UIView *rootFolderView);
void I18InstallEditButtonHooks(void);
/// Edit mode just started: look for the "+" a few times while it animates in.
void I18EditModeChanged(UIView *rootFolderView, BOOL editing);

#pragma mark - Settings app (I18SettingsApp.m)

void I18InstallSettingsAppHooks(void);
/// Darwin notification posted by SpringBoard whenever the look changes.
#define I18_CHANGED_NOTIFICATION "com.timoshka69.ios18customization/changed"
void I18PostChangedNotification(void);

#pragma mark - Wallpaper dim (I18Wallpaper.m)

void I18WallpaperDimUpdate(BOOL animated);
void I18InstallSceneHelpers(UIWindow *homeScreenWindow);

#pragma mark - Panel (I18Panel.m)

@interface I18Panel : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
- (void)show;
- (void)dismissAnimated:(BOOL)animated;
@end

#pragma mark - Localisation (I18Settings.m)

NSString *I18L(NSString *key);

NS_ASSUME_NONNULL_END
