ifeq ($(ROOTLESS),1)
export THEOS_PACKAGE_SCHEME = rootless
endif

export ARCHS = arm64
TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iSponsorBlock

iSponsorBlock_FILES = iSponsorBlock.xm $(wildcard *.m)
# Removed: iSponsorBlock_LIBRARIES = colorpicker  (no Alderis/libcolorpicker needed)
iSponsorBlock_CFLAGS = -fobjc-arc \
    -Wno-deprecated-declarations \
    -Wno-module-import-in-extern-c \
    -Wno-unknown-warning-option \
    -Wno-vla-cxx-extension \
    -Wno-vla-extension \
    -I../../
iSponsorBlock_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-no_implicit_dylibs

include $(THEOS_MAKE_PATH)/tweak.mk
