export TARGET=iphone:latest:2.0
include framework/makefiles/common.mk

TWEAK_NAME = PreferenceLoader
PreferenceLoader_FILES = Tweak.xm
PreferenceLoader_FRAMEWORKS = UIKit
PreferenceLoader_PRIVATE_FRAMEWORKS = Preferences
PreferenceLoader_CFLAGS = -I.

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	find $(THEOS_STAGING_DIR) -iname '*.plist' -exec plutil -convert binary1 {} \;
	$(FAKEROOT) chown -R 0:80 $(THEOS_STAGING_DIR)
