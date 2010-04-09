TWEAK_NAME = PreferenceLoader
PreferenceLoader_OBJCC_FILES = Tweak.mm
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
