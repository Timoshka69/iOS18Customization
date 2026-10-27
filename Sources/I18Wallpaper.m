//
//  I18Wallpaper.m
//  iOS18Customization
//
//  The sun button of the panel dims the home screen wallpaper like iOS 18.
//  A non-interactive window is slotted between SpringBoard's wallpaper window
//  and the home screen window, so icons, the lock screen and apps are never
//  affected.
//
//  The same window carries a tiny view that reports light / dark appearance
//  changes, which "Auto" and the widget tint depend on.
//

#import "I18Shared.h"

@interface I18PassthroughWindow : UIWindow
@end

@implementation I18PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
- (BOOL)_canAffectStatusBarAppearance {
    return NO;
}
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

@interface I18TraitWatcher : UIView
@end

@implementation I18TraitWatcher
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [[I18Settings shared] noteSystemStyle:self.traitCollection.userInterfaceStyle];
    if (previous && previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    // The first call happens when the watcher is attached: SpringBoard may
    // not have known the appearance yet when the tweak loaded, so resolve
    // "Auto" once without animation. Later calls are real switches.
    BOOL animated = previous != nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        // "Auto" follows the system, the widget tint depends on it as well.
        I18ApplyLook(animated);
    });
}
@end

static I18PassthroughWindow *gDimWindow;
static UIView *gDimView;
static __weak UIWindow *gHomeWindow;

static UIWindow *I18WallpaperWindowBelow(UIWindow *home) {
    UIWindowScene *scene = home.windowScene;
    UIWindow *best = nil;
    for (UIWindow *window in scene.windows) {
        if (window == home || window == gDimWindow) continue;
        if (!I18ClassNameContains(window, @"Wallpaper")) continue;
        if (window.windowLevel >= home.windowLevel) continue;
        if (!best || window.windowLevel > best.windowLevel) best = window;
    }
    return best;
}

static BOOL I18PlaceDimWindow(void) {
    UIWindow *home = gHomeWindow;
    UIWindowScene *scene = home.windowScene;
    if (!home || !scene) return NO;
    UIWindow *wallpaper = I18WallpaperWindowBelow(home);

    if (!gDimWindow) {
        gDimWindow = [[I18PassthroughWindow alloc] initWithWindowScene:scene];
        gDimWindow.backgroundColor = UIColor.clearColor;
        gDimWindow.userInteractionEnabled = NO;

        gDimView = [[UIView alloc] initWithFrame:gDimWindow.bounds];
        gDimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        gDimView.backgroundColor = UIColor.blackColor;
        gDimView.alpha = 0.0;
        gDimView.userInteractionEnabled = NO;
        [gDimWindow addSubview:gDimView];

        I18TraitWatcher *watcher = [[I18TraitWatcher alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        watcher.userInteractionEnabled = NO;
        watcher.alpha = 0.0;
        [gDimWindow addSubview:watcher];
    }
    gDimWindow.frame = home.screen.bounds;

    if (wallpaper) {
        gDimWindow.windowLevel = (wallpaper.windowLevel + home.windowLevel) * 0.5;
        gDimView.hidden = NO;
    } else {
        // No separate wallpaper window: never risk dimming the icons.
        gDimWindow.windowLevel = home.windowLevel - 1.0;
        gDimView.hidden = YES;
    }
    gDimWindow.hidden = NO;
    return YES;
}

void I18WallpaperDimUpdate(BOOL animated) {
    if (!I18PlaceDimWindow()) return;
    CGFloat alpha = [I18Settings shared].dimWallpaper ? 0.36 : 0.0;
    if (!animated) {
        gDimView.alpha = alpha;
        return;
    }
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        gDimView.alpha = alpha;
    } completion:nil];
}

void I18InstallSceneHelpers(UIWindow *homeScreenWindow) {
    if (!homeScreenWindow || !homeScreenWindow.windowScene) return;
    // Only the window that hosts root / dock icons counts as the home screen.
    UIWindow *current = gHomeWindow;
    if (current == homeScreenWindow && gDimWindow) return;
    if (current && current != homeScreenWindow && !current.hidden) return;
    gHomeWindow = homeScreenWindow;
    dispatch_async(dispatch_get_main_queue(), ^{
        I18WallpaperDimUpdate(NO);
    });
}
