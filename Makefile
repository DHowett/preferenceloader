TWEAK_NAME = PreferenceLoader
PreferenceLoader_LOGOS_FILES = Tweak.xm
PreferenceLoader_FRAMEWORKS = UIKit
PreferenceLoader_PRIVATE_FRAMEWORKS = Preferences

include framework/makefiles/common.mk
include framework/makefiles/tweak.mk

ifeq ($(FW_TARGET_NAME)$(FW_PLATFORM_NAME),iphonemacosx)
export SDKVERSION = 2.0
TARGET_CC = $(SDKBINPATH)/gcc-4.0
TARGET_CXX = $(SDKBINPATH)/gcc-4.0
ADDITIONAL_CFLAGS = -I.
endif

internal-package::
	find $(FW_STAGING_DIR) -iname '*.plist' -exec plutil -convert binary1 {} \;
	$(FAKEROOT) chown -R 0:80 $(FW_PACKAGE_STAGING_DIR)
