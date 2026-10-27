//
//  Tweak.m
//  iOS18Customization
//
//  iOS 18 home screen customization for iOS 15:
//  Light / Dark / Auto / Tinted icons, tinted widgets and badges,
//  small or large icons, wallpaper dimming and the iOS 18 "+" menu.
//  In the Settings app the list icons follow the chosen look.
//

#import "I18Shared.h"
#include <notify.h>

__attribute__((constructor)) static void I18Initialize(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if ([bundle isEqualToString:@"com.apple.Preferences"]) {
            I18InstallSettingsAppHooks();
            return;
        }
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;

        I18InstallHomeScreenHooks();

        // Close the panel when the device locks.
        int lockToken = 0;
        notify_register_dispatch("com.apple.springboard.lockcomplete", &lockToken, dispatch_get_main_queue(), ^(__unused int t) {
            [[I18Panel shared] dismissAnimated:NO];
        });

        // SpringBoard reloads icons when the screen goes off and on. Once it
        // is done, walk the home screen and put every icon back into the
        // current look, so no icon is left stock or in an old colour.
        void (^resync)(int) = ^(__unused int t) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                I18SweepHomeScreen();
            });
        };
        int blankToken = 0, stateToken = 0;
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blankToken, dispatch_get_main_queue(), resync);
        notify_register_dispatch("com.apple.springboard.lockstate", &stateToken, dispatch_get_main_queue(), resync);
    }
}
