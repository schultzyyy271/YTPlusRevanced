# YouTube Plus Revanced (ex. YTLite)
A flexible enhancer for YouTube on iOS, featuring over a hundred customizable options.

## Table of Contents

* [Screenshots](#screenshots)
* [Main Features](#main-features)
* [FAQ](#faq)
* [Reviews](#reviews)
* [How to build a YouTube Plus app using GitHub Actions](#how-to-build-a-youtube-plus-app-using-github-actions)
* [Supported YouTube Version](#supported-youtube-version)
* [Tweak Integration Details](#tweak-integration-details)

---

## Main Features

* Download videos, audio (including audio track selection), thumbnails, posts, and profile pictures
* Copy video, comment, and post information
* Interface customization: Remove feed elements, reorder tabs, enable OLED mode, and use Shorts-only mode
* Player settings: Gestures, default quality, preferred audio track
* Save, Load and Restore settings. Clear cache once or automatically on app startup
* Built-in SponsorBlock
* And much, much more

> YouTube Plus preferences can be found in the YouTube Settings

All contributors are listed in the Contributors section. Used open-source libraries are listed in the Open Source Libraries section.

> [!NOTE]
> Starting from version 5.2, YouTube Plus requires a subscription. The last free version is [5.2b4](https://github.com/dayanch96/YTLite/releases/tag/v5.2b4).

---

## FAQ

* [🇺🇸 English FAQ](FAQs/FAQ_EN.md)
* [🇷🇺 ЧаВо на Русском](FAQs/FAQ_RU.md)
* [🇮🇹 FAQ in Italiano](FAQs/FAQ_IT.md)
* [🇵🇱 FAQ po polsku](FAQs/FAQ_PL.md)

---

## Reviews

Review by [@qbap](https://github.com/qbap) on ONE Jailbreak: https://onejailbreak.com/blog/youtube-plus/

---

## How to build a YouTube Plus app using GitHub Actions

> [!NOTE]
> If this is your first time, complete the following steps before starting:
> 1. Fork this repository using the Fork button on the top right.
> 2. On your forked repository, go to **Repository Settings → Actions** and enable **Read and Write permissions**.

### How to build the YouTube Plus app

1. Click on **Sync fork**, and if your branch is out-of-date, click **Update branch**.
2. Navigate to the **Actions** tab in your forked repository.
3. Select **Create YouTube Plus app** from the left sidebar.
4. Click the **Run workflow** button on the right side.
5. Mark or unmark the tweaks you want to integrate. Learn more in the [Tweak Integration Details](#tweak-integration-details) section.
6. Prepare a decrypted `.ipa` file (we cannot provide this due to legal reasons), then upload it to a file provider (e.g., [filebin.net](https://filebin.net), [filemail.com](https://filemail.com), or Dropbox is recommended).
7. Paste the URL of the decrypted IPA file in the provided field. **Make sure to provide a direct download link, not a link to a webpage — otherwise the process will fail.**
8. Make sure all inputs are correct, then click **Run workflow** to start the process.
9. Wait for the build to finish. You can download the YouTube Plus app from the **Releases** section of your forked repo. *(If you can't find it, add `/releases` to your repo URL — e.g., `github.com/yourusername/YouTubePlusRevanced/releases`.)*

---

### How to build the YouTube Plus app with your own link for the YouTube Plus tweak

> [!NOTE]
> This option is primarily intended for building based on a beta `.deb` file you already have. In most cases it is not needed.

1. Click on **Sync fork**, and if your branch is out-of-date, click **Update branch**.
2. Navigate to the **Actions** tab in your forked repository.
3. Select **[BETA] Build YouTube Plus app** from the left sidebar.
4. Click the **Run workflow** button on the right side.
5. Mark or unmark the tweaks you want to integrate. Learn more in the [Tweak Integration Details](#tweak-integration-details) section.
6. Prepare a decrypted `.ipa` file (we cannot provide this due to legal reasons), then upload it to a file provider (e.g., [filebin.net](https://filebin.net), [filemail.com](https://filemail.com), or Dropbox is recommended).
7. Paste the URL of the decrypted IPA file in the provided field. **Make sure to provide a direct download link, not a link to a webpage — otherwise the process will fail.**
8. Paste the direct download URL of your YouTube Plus `.deb` beta file into the tweak URL field.
9. You can also change the **BundleID** and **Display Name** if desired.
10. Make sure all inputs are correct, then click **Run workflow** to start the process. Wait for the build to finish. You can download the result from the **Releases → Drafts** section of your forked repo.

---

## Supported YouTube Version

| | |
|---|---|
| **Latest confirmed** | 21.16.2 |
| **Date tested** | Apr 23, 2026 |
| **YouTube Plus Revanced version** | 1.0 |

---

## Tweak Integration Details

### YouPiP
YouPiP is a tweak developed by [PoomSmart](https://github.com/PoomSmart) that enables the native Picture-in-Picture feature for videos in the iOS YouTube app. YouPiP preferences are available in the YouTube settings. [Source code and additional information →](https://github.com/PoomSmart/YouPiP)

### YTUHD
YTUHD is a tweak developed by [PoomSmart](https://github.com/PoomSmart) that unlocks 1440p (2K) and 2160p (4K) resolutions in the iOS YouTube app. YTUHD preferences are available in the Video quality preferences section under YouTube settings. [Source code and additional information →](https://github.com/PoomSmart/YTUHD)

### Return YouTube Dislikes
Return YouTube Dislikes is a tweak developed by [PoomSmart](https://github.com/PoomSmart) that brings back dislike counts on YouTube videos using the ReturnYoutubeDislike API. Preferences are available in the YouTube settings. [Source code and additional information →](https://github.com/PoomSmart/Return-YouTube-Dislikes)

### YouQuality
YouQuality is a tweak developed by [PoomSmart](https://github.com/PoomSmart) that allows you to view and change video quality directly from the video overlay. Can be enabled in the Video overlay section under YouTube settings. [Source code and additional information →](https://github.com/PoomSmart/YouQuality)

### DontEatMyContent
DontEatMyContent prevents the notch or Dynamic Island from covering 2:1 video content in the YouTube app. [Source code and additional information →](https://github.com/PoomSmart/DontEatMyContent)
