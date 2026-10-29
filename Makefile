# iOS18Customization - iOS 18 style home screen customization for iOS 15
#
#   make package                               rootless .deb (Dopamine, palera1n rootless)
#   make package THEOS_PACKAGE_SCHEME=         rootful .deb  (palera1n rootful, checkra1n...)
#   make package FINALPACKAGE=1                release build without debug suffix

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS18Customization

iOS18Customization_FILES = $(wildcard Sources/*.m)
iOS18Customization_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-error
iOS18Customization_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

# The page in the Settings app.
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
