export TARGET = iphone:clang:16.5:16.0
export ARCHS = arm64

DEBUG = 0
FINALPACKAGE = 1

# ── Version ───────────────────────────────────────────────────────────────────
ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 21.16.2
endif
PACKAGE_VERSION = $(YOUTUBE_VERSION)

# ── Package metadata ──────────────────────────────────────────────────────────
TWEAK_NAME       = YouTubePlusRevanced
DISPLAY_NAME     = YouTube
BUNDLE_ID        = com.google.ios.youtube
INSTALL_TARGET_PROCESSES = YouTube

ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

# ── iSponsorBlock subproject ──────────────────────────────────────────────────
SUBPROJECTS += Tweaks/iSponsorBlock

include $(THEOS)/makefiles/common.mk

# ── Sources ───────────────────────────────────────────────────────────────────
$(TWEAK_NAME)_FILES = \
	YTPlus.x \
	Settings.x \
	YTNativeShare.x \
	Sideloading.x \
	Utils/NSBundle+YTPlus.m \
	Utils/YTPUserDefaults.m \
	Utils/Reachability.m

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation SystemConfiguration Photos
$(TWEAK_NAME)_CFLAGS     = -fobjc-arc -DTWEAK_VERSION=$(PACKAGE_VERSION)

# ── iSponsorBlock dylib + bundle injection ────────────────────────────────────
ifeq ($(FINALPACKAGE),1)
$(TWEAK_NAME)_INJECT_DYLIBS = Tweaks/iSponsorBlock/.theos/obj/iSponsorBlock.dylib
else
$(TWEAK_NAME)_INJECT_DYLIBS = Tweaks/iSponsorBlock/.theos/obj/debug/iSponsorBlock.dylib
endif
$(TWEAK_NAME)_EMBED_BUNDLES = Tweaks/iSponsorBlock/layout/Library/Application\ Support/iSponsorBlock.bundle

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# ── IPA injection (theos-jailed) ──────────────────────────────────────────────
REMOVE_EXTENSIONS = 1
CODESIGN_IPA      = 0

# IPA is injected via:  make package IPA=Payload/YouTube.app FINALPACKAGE=1
# Omit IPA= for a plain .deb (jailbreak install).
