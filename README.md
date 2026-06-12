# YouTube Plus Revanced (ex. YTLite)
A flexible enhancer for YouTube on iOS, featuring over a hundred customizable options.

## Supported YouTube Version

| | |
|---|---|
| **Latest confirmed** | 21.16.2 |
| **Date tested** | June 12, 2026 |
| **YouTube Plus Revanced version** | beta5 |

---

## Main Features

* Ad blocking (video ads, banner ads, interstitials, promossheet ads)
* Download videos, audio (including audio track selection), thumbnails, posts, and profile pictures
* Copy video, comment, and post information
* Interface customization: Remove feed elements, reorder tabs, enable OLED mode, and use Shorts-only mode
* Player settings: Gestures, default quality, preferred audio track, auto-speed, auto-fullscreen
* Shorts controls: Stop doom scrolling, open shorts as regular videos, hide shorts elements, shorts progress bar
* Save, Load and Restore settings. Clear cache once or automatically on app startup
* Built-in SponsorBlock
* And much, much more

> YouTube Plus preferences can be found in the YouTube Settings

---

## Integrated Tweaks

| Tweak | Author | Description |
|---|---|---|
| **YouPiP** | [PoomSmart](https://github.com/PoomSmart) | Native Picture-in-Picture for YouTube videos |
| **YTUHD** | [PoomSmart](https://github.com/PoomSmart) | Unlocks 1440p (2K) and 2160p (4K) resolutions |
| **Return YouTube Dislikes** | [PoomSmart](https://github.com/PoomSmart) | Restores dislike counts via the ReturnYoutubeDislike API |
| **YouQuality** | [PoomSmart](https://github.com/PoomSmart) | Video quality picker directly in the video overlay |
| **YTVideoOverlay** | [PoomSmart](https://github.com/PoomSmart) | Player overlay button registry (used by YouPiP/YouQuality) |
| **DontEatMyContent** | [PoomSmart](https://github.com/PoomSmart) | Prevents notch/Dynamic Island from covering video content |
| **Gonerino** | [castdrian](https://github.com/castdrian) | Block channels and videos by keyword |
| **VolumeBoostYT** | [VasirakCalgux](https://github.com/VasirakCalgux) | Volume boost beyond 100% |
| **YTweaks** | [PoomSmart](https://github.com/PoomSmart) | Dark mode, force fullscreen, hide AI summaries, virtual bezel |
| **YouGroupSettings** | [PoomSmart](https://github.com/PoomSmart) | Settings grouping |
| **iSponsorBlock** | [Galactic-Dev](https://github.com/Galactic-Dev) | Auto-skip sponsored segments (separate dylib) |

---

## Known Non-Functional Toggles (YouTube 21.16.2)

The following toggles are present in settings but do not work because YouTube 21.16.2 removed the underlying methods they hooked. They are marked with `❌ BROKEN` in the source code.

| Toggle | Feature | Reason |
|---|---|---|
| `noFreeZoom` | Disable pinch-to-zoom | `videoZoomFreeZoomEnabledGlobalConfig` removed from YTColdConfig |
| `hideSortComments` | Hide comment sort chips | `enableChipsInTheCommentsHeaderIos` removed |
| `stockVolumeHUD` | Use stock iOS volume slider | `iosUseSystemVolumeControlInFullscreen` removed |
| `hideShortsLike` | Hide like button on shorts | Shorts buttons moved to new ShortsBottomActionBar system |
| `hideShortsDislike` | Hide dislike on shorts | Same |
| `hideShortsComments` | Hide comments on shorts | Same |
| `hideShortsRemix` | Hide remix on shorts | Same |
| `hideShortsAvatars` | Hide avatars on shorts | Same |
| `disableRTL` | Disable right-to-left text | `NSParagraphStyle` methods removed |

---

## Build Instructions

Requires macOS with [Theos](https://theos.dev) installed.

```bash
THEOS_PACKAGE_SCHEME=rootless make clean package DEBUG=0 FINALPACKAGE=1
```

After building, verify the dylib:

```bash
python3 VERIFY_FIX.py .theos/obj/YouTubePlusRevanced.dylib
```

## Sideloading

Use [Sideloadly](https://sideloadly.io) to inject the dylibs and bundles into a decrypted YouTube 21.16.2 IPA. The `.deb` contains:

* `YouTubePlusRevanced.dylib` + `.plist` — main tweak
* `YouTubePlusRevanced.bundle` — localization and assets

---

## Credits

Based on [YTLite](https://github.com/dayanch96/YTLite) by [@dayanch96](https://github.com/dayanch96). Tweak sources by [PoomSmart](https://github.com/PoomSmart) and community contributors.
