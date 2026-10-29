# Settings page of iOS18Customization (Settings app -> iOS18Customization).
# Built as a sub-project of the tweak, see the Makefile one level up.

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = iOS18CustomizationPrefs

iOS18CustomizationPrefs_FILES = I18PRootListController.m
iOS18CustomizationPrefs_FRAMEWORKS = UIKit QuartzCore
iOS18CustomizationPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOS18CustomizationPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new

include $(THEOS_MAKE_PATH)/bundle.mk

# The entry in the Settings list (PreferenceLoader). Theos moves the staging
# folder under /var/jb itself for rootless, so no prefix here.
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/iOS18Customization.plist"$(ECHO_END)
