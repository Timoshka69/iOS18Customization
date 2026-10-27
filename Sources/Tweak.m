//
//  Tweak.m
//  iOS18Customization
//
//  iOS 18 home screen customization for iOS 15:
//  Light / Dark / Auto / Tinted icons, tinted widgets and badges,
//  small or large icons, wallpaper dimming and the iOS 18 "Edit" menu.
//

#import "I18Shared.h"
#include <notify.h>

__attribute__((constructor)) static void I18Initialize(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;

        I18InstallHomeScreenHooks();

        // Close the panel when the device locks.
        int token = 0;
        notify_register_dispatch("com.apple.springboard.lockcomplete", &token, dispatch_get_main_queue(), ^(__unused int t) {
            [[I18Panel shared] dismissAnimated:NO];
        });
    }
}
