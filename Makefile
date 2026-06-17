export TARGET = iphone:clang:16.5:16.0
export ARCHS = arm64
# Always export THEOS_PACKAGE_SCHEME so sub-makes inherit it.
export THEOS_PACKAGE_SCHEME

DEBUG = 0
FINALPACKAGE = 1

# ── Version ───────────────────────────────────────────────────────────────────
ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 21.24.3
endif
PACKAGE_VERSION = $(YOUTUBE_VERSION)

# ── Diagnostic build ──────────────────────────────────────────────────────────
# Build with `DIAG=1` to enable the one-shot diagnostic logger (see YTPDiag.h).
# Shake the device after testing to copy all diagnostics to the clipboard.
ifeq ($(DIAG),1)
DIAG_CFLAG = -DYTP_DIAG=1
endif

# ── Package metadata ──────────────────────────────────────────────────────────
TWEAK_NAME       = YouTubePlusRevanced
DISPLAY_NAME     = YouTube
BUNDLE_ID        = com.google.ios.youtube
INSTALL_TARGET_PROCESSES = YouTube

ifeq ($(ROOTLESS),1)
export THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
export THEOS_PACKAGE_SCHEME = roothide
endif

# ── Subprojects ───────────────────────────────────────────────────────────────
# (iSponsorBlock is now compiled inline — no subprojects needed)

include $(THEOS)/makefiles/common.mk

# ── Sources ───────────────────────────────────────────────────────────────────
# NOTE: GNU Make terminates a `\`-continued variable at the first comment
# line in the continuation, even if the comment also ends with `\`. Do NOT
# splice `# ...` lines into this list — they will silently truncate it.
# YTABConfig is currently disabled; if you re-enable it, just add the lines
# back to the list — don't keep them as comments inside the continuation.
#
# YTVideoOverlay/Tweak.x is the registry that owns +registerTweak:metadata:
# and adds -buttonImage: to YTMainAppControlsOverlayView/YTInlinePlayerBarContainerView.
# It MUST appear before YouPiP and YouQuality so its %ctor (which class_addMethod's
# those selectors) runs first.
$(TWEAK_NAME)_FILES = \
	YTPlus.x \
	Settings.x \
	YTNativeShare.x \
	Sideloading.x \
	Utils/NSBundle+YTPlus.m \
	Utils/YTPUserDefaults.m \
	Utils/Reachability.m \
	Tweaks/YTVideoOverlay/Tweak.x \
	Tweaks/ReturnYouTubeDislike/TweakSettings.x \
	Tweaks/ReturnYouTubeDislike/API.x \
	Tweaks/ReturnYouTubeDislike/Vote.x \
	Tweaks/ReturnYouTubeDislike/Tweak.x \
	Tweaks/YTUHD/Settings.x \
	Tweaks/YTUHD/Tweak.xm \
	Tweaks/YouPiP/LegacyPiPCompat.x \
	Tweaks/YouPiP/Tweak.x \
	Tweaks/DontEatMyContent/Tweak.x \
	Tweaks/Gonerino/sources/Tweak.x \
	Tweaks/Gonerino/sources/Util.m \
	Tweaks/Gonerino/sources/ChannelManager.m \
	Tweaks/Gonerino/sources/VideoManager.m \
	Tweaks/Gonerino/sources/WordManager.m \
	Tweaks/Gonerino/sources/Sideloading.x \
	Tweaks/YTweaks/Tweak.x \
	Tweaks/YTweaks/Settings.x \
	Tweaks/YouGroupSettings/Tweak.x \
	Tweaks/YouQuality/Tweak.x \
	Tweaks/iSponsorBlock/iSponsorBlock.xm \
	Tweaks/iSponsorBlock/MBProgressHUD.m \
	Tweaks/iSponsorBlock/SponsorBlockRequest.m \
	Tweaks/iSponsorBlock/SponsorBlockSettingsController.m \
	Tweaks/iSponsorBlock/SponsorBlockViewController.m \
	Tweaks/iSponsorBlock/SponsorSegment.m \
	Tweaks/iSponsorBlock/SponsorSegmentView.m

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation SystemConfiguration Photos AVKit VideoToolbox CoreMedia
$(TWEAK_NAME)_CFLAGS = \
	-fobjc-arc \
	-DTWEAK_VERSION=$(PACKAGE_VERSION) \
	-DSIDELOAD=1 \
	$(DIAG_CFLAG) \
	-Wno-deprecated-declarations \
	-Wno-module-import-in-extern-c \
	-Wno-unknown-warning-option \
	-Wno-vla-cxx-extension \
	-Wno-vla-extension \
	-I. \
	-ITweaks/DontEatMyContent \
	-ITweaks/YTVideoOverlay \
	-ITweaks/ReturnYouTubeDislike \
	-ITweaks/YouPiP \
	-ITweaks/YTUHD \
	-ITweaks/Gonerino \
	-ITweaks/Gonerino/headers \
	-ITweaks/Gonerino/sources \
	-ITweaks/YTweaks \
	-ITweaks/iSponsorBlock \
	-ITweaks/iSponsorBlock/Headers
$(TWEAK_NAME)_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-no_implicit_dylibs

# ── iSponsorBlock is now compiled inline — no dylib injection needed ───────────

# ── Embed all tweak bundles ───────────────────────────────────────────────────
# Same comment-in-continuation hazard applies here.
$(TWEAK_NAME)_EMBED_BUNDLES = \
	Tweaks/iSponsorBlock/layout/Library/Application\ Support/iSponsorBlock.bundle \
	Tweaks/YTVideoOverlay/layout/Library/Application\ Support/YTVideoOverlay.bundle \
	Tweaks/ReturnYouTubeDislike/layout/Library/Application\ Support/RYD.bundle \
	Tweaks/YTUHD/layout/Library/Application\ Support/YTUHD.bundle \
	Tweaks/YouPiP/layout/Library/Application\ Support/YouPiP.bundle \
	Tweaks/DontEatMyContent/layout/Library/Application\ Support/DontEatMyContent.bundle \
	Tweaks/YouQuality/layout/Library/Application\ Support/YouQuality.bundle \
	Tweaks/YTweaks/layout/Library/Application\ Support/YTWKS.bundle \
	Tweaks/YouGroupSettings/layout/Library/Application\ Support/YouGroupSettings.bundle

include $(THEOS_MAKE_PATH)/tweak.mk

# ── IPA injection (theos-jailed) ──────────────────────────────────────────────
REMOVE_EXTENSIONS = 1
CODESIGN_IPA      = 0
