# YouTube Plus Revanced (ex. YTLite)
A flexible enhancer for YouTube on iOS, featuring over a hundred customizable options.

## Supported YouTube Version

| | |
|---|---|
| **Latest confirmed** | 21.24.3 |
| **Date tested** | June 17, 2026 |
| **YouTube Plus Revanced version** | beta6 |

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

## Toggle Status (YouTube 21.24.3)

The toggles below broke on 21.16.2 when YouTube removed the methods they hooked. They were re-fixed for 21.24.3 by re-deriving the new hook points from the binary (IDA). Status:

| Toggle | Feature | 21.24.3 fix |
|---|---|---|
| `noFreeZoom` | Disable pinch-to-zoom | ✅ Config renamed → now hooks `YTColdConfig.videoZoomFreeZoomEnabled` |
| `hideSortComments` | Hide comment sort chips | ✅ Hides `YTCommentsHeaderView.sortMenuButton` (config gone) |
| `stockVolumeHUD` | Use stock iOS volume HUD | ✅ Forces `YTWatchLayerViewController.volumeBarViewCanDisplayVolumeBar:` → NO, suppressing YT's custom bar |
| `disableRTL` | Disable right-to-left text | 🟡 Partial — hooks `YTFormattedStringLabel.forceRTLTextAlignment` (covers YT formatted labels only; `NSParagraphStyle` methods stay removed) |
| `hideShortsLike` | Hide like button on shorts | 🟠 Best-effort — see note below |
| `hideShortsDislike` | Hide dislike on shorts | 🟠 Best-effort |
| `hideShortsComments` | Hide comments on shorts | 🟠 Best-effort |
| `hideShortsRemix` | Hide remix on shorts | 🟠 Best-effort |
| `hideShortsAvatars` | Hide avatars on shorts | 🟠 Best-effort |

**Shorts buttons (🟠):** The Shorts action bar is now a Swift component (`YTReelBottomActionBarView`) with no per-button ObjC selectors. The fix walks the view tree in `layoutSubviews` and hides buttons by `accessibilityLabel`. The match substrings are best-effort guesses and are locale-dependent — capture the real labels with a diagnostic build (see below). These remain marked `⚠️` in Settings until verified.

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

Use [Sideloadly](https://sideloadly.io) to inject the dylibs and bundles into a decrypted YouTube 21.24.3 IPA. The `.deb` contains:

* `YouTubePlusRevanced.dylib` + `.plist` — main tweak
* `YouTubePlusRevanced.bundle` — localization and assets

---

## Diagnostic build (verifying runtime-dependent features)

Some fixes (Shorts button hiding, RYD Shorts dislikes, the comments/volume hooks) depend on
runtime behavior that can't be confirmed from the binary alone. Instead of rebuild-and-guess
cycles, build **once** with diagnostics on:

```bash
THEOS_PACKAGE_SCHEME=rootless make clean package DEBUG=0 FINALPACKAGE=1 DIAG=1
```

Then, in a single session:

1. Open a normal video, open its **comments**, open a **Short**, and open **YouTube Settings**.
2. **Shake the device.** An alert confirms how many diagnostic lines were copied to the
   clipboard. Paste that text back to the dev.

The diagnostics include:

* **Hook binding self-check** (runs ~4s after launch): iterates every app hook in the project
  (`YTPDiagHooks.h`, auto-generated) and verifies each `(class, selector)` still resolves to a
  method in the installed YouTube binary. Prints `UNBOUND`/`MISSING CLASS` for any dead hook and
  a `bound / unbound / missing-class` summary. ⚠️ Intentional version-fallback hooks (old
  `MLPlayerPoolImpl` signatures, `YTLikeService`, the pre-21.24.3 init variants, etc.) appear
  `UNBOUND` *by design* — what matters is that each feature's **current-signature** hook binds.
* **Fire logs** for the behaviorally-uncertain hooks (noFreeZoom, hideSortComments, stockVolumeHUD,
  disableRTL, RYD Shorts, YouPiP autonav) with their key values.
* **Shorts action-bar dump**: every button's class / `accessibilityLabel` / `accessibilityIdentifier`,
  so the Shorts-hide match strings can be set to the real values.

All output is also written to `<app sandbox>/Documents/YTPlusDiag.log` and `NSLog`'d with `[YTPDIAG]`.

`DIAG=1` is opt-in; normal builds compile the diagnostics out entirely (zero overhead).

To regenerate `YTPDiagHooks.h` after adding/removing hooks, re-run the awk extractor over the
project sources (the same one used to audit hooks) and rebuild the `kYTPHookPairs` array.

---

## Credits

Based on [YTLite](https://github.com/dayanch96/YTLite) by [@dayanch96](https://github.com/dayanch96). Tweak sources by [PoomSmart](https://github.com/PoomSmart) and community contributors.
