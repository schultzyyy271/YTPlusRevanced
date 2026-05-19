// Settings.x — YTPlus settings panel
// Adapted from YTLite open-source by dayanch96, modded by Schultzy.

#import "YTPlus.h"

@interface YTSettingsGroupData : NSObject
@property (nonatomic, assign) NSInteger type;
- (NSArray <NSNumber *> *)orderedCategories;
@end

@interface YTSettingsSectionItem (BrokenToggle)
@property (nonatomic, assign) BOOL enabled;
@end

@interface YTSettingsSectionItemManager (YTPlus)
- (void)updateYTPlusSectionWithEntry:(id)entry;
- (void)updateYTPlusTweaksSectionWithSettingsVC:(YTSettingsViewController *)settingsVC;
- (YTSettingsSectionItem *)brokenSwitchWithTitle:(NSString *)title key:(NSString *)key;
@end

static const NSInteger YTPlusSection = 9001; // 790 conflicts with YouTube 21.x internal category

static NSString *GetCacheSize() {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:cachePath error:nil];

    unsigned long long int folderSize = 0;
    for (NSString *fileName in filesArray) {
        NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        folderSize += [fileAttributes fileSize];
    }

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:folderSize];
}

// ─── Inject YTPlus section into settings ─────────────────────────────────────

%hook YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder {
    NSArray *order = %orig;
    NSMutableArray *mutableOrder = [order mutableCopy];
    [mutableOrder removeObject:@(YTPlusSection)];
    NSUInteger insertIndex = [order indexOfObject:@(1)];
    if (insertIndex != NSNotFound)
        [mutableOrder insertObject:@(YTPlusSection) atIndex:insertIndex + 1];
    return mutableOrder;
}
%end

%hook YTSettingsGroupData
- (NSArray <NSNumber *> *)orderedCategories {
    if (self.type != 1 || class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks)))
        return %orig;
    NSMutableArray *mutableCategories = %orig.mutableCopy;
    [mutableCategories removeObject:@(YTPlusSection)];
    [mutableCategories insertObject:@(YTPlusSection) atIndex:0];
    return mutableCategories.copy;
}
%end

%hook YTSettingsSectionController
- (void)setSelectedItem:(NSUInteger)selectedItem {
    if (selectedItem != NSNotFound) %orig;
}
%end

// ─── Purple accent for YTPlus cells ──────────────────────────────────────────

%hook YTSettingsCell
- (void)layoutSubviews {
    %orig;
    BOOL isYTPlus = [self.accessibilityIdentifier isEqualToString:@"YTPlusSectionItem"];
    YTTouchFeedbackController *feedback = [self valueForKey:@"_touchFeedbackController"];
    ABCSwitch *abcSwitch = [self valueForKey:@"_switch"];
    if (isYTPlus) {
        feedback.feedbackColor = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
        abcSwitch.onTintColor  = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
    }
}
%end

// ─── Settings section builder ─────────────────────────────────────────────────

%hook YTSettingsSectionItemManager

// NOTE on +registerTweak:metadata: -- The real implementation lives in
// Tweaks/YTVideoOverlay/Tweak.x (added via %new on the metaclass). It stores
// each tweak's metadata into a dictionary that YTVideoOverlay reads when
// rendering the player overlay buttons. YouPiP and YouQuality call this
// during their %ctor's via Tweaks/YTVideoOverlay/Init.x. As long as
// YTVideoOverlay/Tweak.x is in the Makefile's _FILES list and ordered BEFORE
// its consumers (YouPiP, YouQuality), the call resolves cleanly. Do not add a
// no-op stub here -- it would race the real registry's class_addMethod and
// could win, silently breaking button registration.

%new
- (YTSettingsSectionItem *)switchWithTitle:(NSString *)title key:(NSString *)key {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    NSString *descKey = [NSString stringWithFormat:@"%@Desc", title];
    YTSettingsSectionItem *item = [YTSettingsSectionItemClass switchItemWithTitle:LOC(title)
        titleDescription:LOC(descKey)
        accessibilityIdentifier:@"YTPlusSectionItem"
        switchOn:ytpBool(key)
        switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
            if ([key isEqualToString:@"shortsOnlyMode"]) {
                BOOL enabledCopy = enabled;
                YTSettingsCell *cellCopy = cell;
                __block YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                    ytpSetBool(enabledCopy, @"shortsOnlyMode");
                }
                actionTitle:LOC(@"Yes")
                cancelAction:^{
                    [cellCopy setSwitchOn:!enabledCopy animated:YES];
                }
                cancelTitle:LOC(@"No")];
                alertView.title = LOC(@"Warning");
                alertView.subtitle = LOC(@"ShortsOnlyWarning");
                [alertView show];
            } else {
                ytpSetBool(enabled, key);
                if ([key isEqualToString:@"noAds"]) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
                        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
                    });
                    [[%c(YTToastResponderEvent) eventWithMessage:@"Cache cleared — restart YouTube to apply" firstResponder:[self parentResponder]] send];
                }
                NSArray *tabKeys = @[@"removeLabels", @"removeIndicators", @"reExplore", @"addExplore",
                                     @"removeShorts", @"removeSubscriptions", @"removeUploads", @"removeLibrary"];
                if ([tabKeys containsObject:key]) {
                    [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
                }
            }
            return YES;
        }
        settingItemId:0];

    return item;
}

// Broken toggles — disabled with clear label indicating non-functional
%new
- (YTSettingsSectionItem *)brokenSwitchWithTitle:(NSString *)title key:(NSString *)key {
    NSString *brokenTitle = [NSString stringWithFormat:@"%@ (N/A)", title];
    YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) switchItemWithTitle:brokenTitle
        titleDescription:@"⚠️ Not working on YouTube 21.16.2"
        accessibilityIdentifier:@"YTPlusBrokenItem"
        switchOn:NO
        switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
            // Do nothing — toggle is non-functional
            return NO;
        }
        settingItemId:0];
    return item;
}

%new
- (YTSettingsSectionItem *)linkWithTitle:(NSString *)title description:(NSString *)description link:(NSString *)link {
    return [%c(YTSettingsSectionItem) itemWithTitle:title
        titleDescription:description
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:nil
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            return [%c(YTUIUtils) openURL:[NSURL URLWithString:link]];
        }];
}

%new
- (UIImage *)resizedImageNamed:(NSString *)iconName {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[NSBundle.ytp_defaultBundle pathForResource:iconName ofType:@"png"]]];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.clipsToBounds = YES;
        iv.frame = CGRectMake(0, 0, 32, 32);
        [iv.layer renderInContext:ctx.CGContext];
    }];
    return image;
}

%new
- (id)parentResponder {
    for (NSString *key in @[@"_settingsViewControllerDelegate", @"_dataDelegate", @"_delegate"]) {
        id vc = nil;
        @try { vc = [self valueForKey:key]; } @catch (...) { vc = nil; }
        if (vc && [vc isKindOfClass:%c(YTSettingsViewController)]) return vc;
    }
    return nil;
}

// ─── Tweaks sub-section builder ───────────────────────────────────────────────
// Returns a settings row for each bundled tweak, using NSUserDefaults keys that
// each tweak's own code already reads.  This avoids any dependency on the tweaks'
// internal headers and works even if a tweak's own settings hook is disabled.

%new
- (void)updateYTPlusTweaksSectionWithSettingsVC:(YTSettingsViewController *)settingsVC {
    NSMutableArray *rows = [NSMutableArray array];
    Class item = %c(YTSettingsSectionItem);

    // ── 1. iSponsorBlock ──────────────────────────────────────────────────────
    // iSponsorBlock stores prefs in ~/Documents/iSponsorBlock.plist.
    // Writing to the same file makes changes picked up immediately by the dylib.
    NSString *isbPlistPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                               stringByAppendingPathComponent:@"iSponsorBlock.plist"];
    YTSettingsSectionItem *iSB = [item itemWithTitle:@"iSponsorBlock"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            NSMutableDictionary *p = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
            return (p[@"enabled"] ? [p[@"enabled"] boolValue] : YES) ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableDictionary *p = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
            NSArray *isbRows = @[
                [item switchItemWithTitle:@"Enable iSponsorBlock"
                    titleDescription:@"Auto-skip sponsored segments on YouTube"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:(p[@"enabled"] ? [p[@"enabled"] boolValue] : YES)
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
                        prefs[@"enabled"] = @(enabled);
                        [prefs writeToURL:[NSURL fileURLWithPath:isbPlistPath isDirectory:NO] error:nil];
                        return YES;
                    }
                    settingItemId:0],
                [item switchItemWithTitle:@"Show Skip Notification"
                    titleDescription:@"Display a toast when a segment is skipped"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:(p[@"showSkipNotice"] ? [p[@"showSkipNotice"] boolValue] : YES)
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
                        prefs[@"showSkipNotice"] = @(enabled);
                        [prefs writeToURL:[NSURL fileURLWithPath:isbPlistPath isDirectory:NO] error:nil];
                        return YES;
                    }
                    settingItemId:0],
                [item switchItemWithTitle:@"Player Buttons"
                    titleDescription:@"Show start/end segment buttons in the player"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:(p[@"showButtonsInPlayer"] ? [p[@"showButtonsInPlayer"] boolValue] : YES)
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
                        prefs[@"showButtonsInPlayer"] = @(enabled);
                        [prefs writeToURL:[NSURL fileURLWithPath:isbPlistPath isDirectory:NO] error:nil];
                        return YES;
                    }
                    settingItemId:0],
                [item switchItemWithTitle:@"Track Skip Count"
                    titleDescription:@"Report skipped segments back to SponsorBlock"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:(p[@"enableSkipCountTracking"] ? [p[@"enableSkipCountTracking"] boolValue] : YES)
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
                        prefs[@"enableSkipCountTracking"] = @(enabled);
                        [prefs writeToURL:[NSURL fileURLWithPath:isbPlistPath isDirectory:NO] error:nil];
                        return YES;
                    }
                    settingItemId:0],
                [item switchItemWithTitle:@"Skip Audio Notification"
                    titleDescription:@"Play a sound when a segment is skipped"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:(p[@"skipAudioNotification"] ? [p[@"skipAudioNotification"] boolValue] : NO)
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:isbPlistPath] ?: [NSMutableDictionary dictionary];
                        prefs[@"skipAudioNotification"] = @(enabled);
                        [prefs writeToURL:[NSURL fileURLWithPath:isbPlistPath isDirectory:NO] error:nil];
                        return YES;
                    }
                    settingItemId:0],
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"iSponsorBlock" pickerSectionTitle:nil rows:isbRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [rows addObject:iSB];

    // ── 2. YouPiP ─────────────────────────────────────────────────────────────
    YTSettingsSectionItem *youPiP = [item itemWithTitle:@"YouPiP"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            return [[NSUserDefaults standardUserDefaults] boolForKey:@"YouPiPEnabled"] ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *pipRows = [NSMutableArray array];

            [pipRows addObject:[item switchItemWithTitle:@"Enable YouPiP"
                titleDescription:@"Picture-in-Picture for YouTube"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YouPiPEnabled"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YouPiPEnabled"];
                    return YES;
                }
                settingItemId:0]];

            [pipRows addObject:[item switchItemWithTitle:@"PiP Button in Player"
                titleDescription:@"Show a dedicated PiP activation button"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"PiPActivationMethodKey"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"PiPActivationMethodKey"];
                    return YES;
                }
                settingItemId:0]];

            [pipRows addObject:[item switchItemWithTitle:@"PiP Button in Tab Bar"
                titleDescription:@"Show PiP button in the tab bar"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"PiPActivationMethod2Key"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"PiPActivationMethod2Key"];
                    return YES;
                }
                settingItemId:0]];

            [pipRows addObject:[item switchItemWithTitle:@"Activate All PiP Methods"
                titleDescription:@"Use every available PiP activation path"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"PiPAllActivationMethodKey"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"PiPAllActivationMethodKey"];
                    return YES;
                }
                settingItemId:0]];

            [pipRows addObject:[item switchItemWithTitle:@"Disable Mini-Player PiP"
                titleDescription:@"Stop the mini-player from triggering PiP"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"NoMiniPlayerPiPKey"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"NoMiniPlayerPiPKey"];
                    return YES;
                }
                settingItemId:0]];

            [pipRows addObject:[item switchItemWithTitle:@"Legacy PiP Mode"
                titleDescription:@"Use iOS 13-era PiP implementation"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"CompatibilityModeKey"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"CompatibilityModeKey"];
                    return YES;
                }
                settingItemId:0]];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"YouPiP" pickerSectionTitle:nil rows:pipRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [rows addObject:youPiP];

    // ── 3. DontEatMyContent ───────────────────────────────────────────────────
    YTSettingsSectionItem *demc = [item itemWithTitle:@"DontEatMyContent"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            return [[NSUserDefaults standardUserDefaults] boolForKey:@"DEMC_enabled"] ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *demcRows = @[
                [item switchItemWithTitle:@"Enable DontEatMyContent"
                    titleDescription:@"Prevent YouTube from hiding content behind notch/home bar"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"DEMC_enabled"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"DEMC_enabled"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Disable Ambient Mode"
                    titleDescription:@"Turn off the ambient background colour effect"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"DEMC_disableAmbientMode"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"DEMC_disableAmbientMode"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Enable for All Videos"
                    titleDescription:@"Apply safe-area fix even on non-affected devices"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"DEMC_enableForAllVideos"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"DEMC_enableForAllVideos"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Color Debug Views"
                    titleDescription:@"Tint safe-area views to visualise the adjustment"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"DEMC_colorViewsEnabled"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"DEMC_colorViewsEnabled"];
                        return YES;
                    }
                    settingItemId:0],
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"DontEatMyContent" pickerSectionTitle:nil rows:demcRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [rows addObject:demc];

    // ── 4. Return YouTube Dislikes ────────────────────────────────────────────
    // Reads/writes the same NSUserDefaults keys that RYD's own TweakSettings.x uses,
    // so changes take effect without needing RYD's internal headers.
    YTSettingsSectionItem *ryd = [item itemWithTitle:@"Return YouTube Dislikes"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            NSNumber *v = [[NSUserDefaults standardUserDefaults] objectForKey:@"RYD-ENABLED"];
            return (v ? [v boolValue] : YES) ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            NSArray *rydRows = @[
                [item switchItemWithTitle:@"Enable Return YouTube Dislikes"
                    titleDescription:@"Show dislike counts restored from the RYD API"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:(([[ud objectForKey:@"RYD-ENABLED"] boolValue]) || ![ud objectForKey:@"RYD-ENABLED"])
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"RYD-ENABLED"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Submit Votes"
                    titleDescription:@"Send your like/dislike votes to the RYD API"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"RYD-VOTE-SUBMISSION"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"RYD-VOTE-SUBMISSION"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Exact Dislike Number"
                    titleDescription:@"Show the full dislike count instead of a shortened number"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"RYD-EXACT-NUMBER"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"RYD-EXACT-NUMBER"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Exact Like Number"
                    titleDescription:@"Show the full like count instead of a shortened number"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"RYD-EXACT-LIKE-NUMBER"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"RYD-EXACT-LIKE-NUMBER"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Use Raw Data"
                    titleDescription:@"Display unformatted numbers directly from the RYD API"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"RYD-USE-RAW-DATA"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"RYD-USE-RAW-DATA"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Show RYD Like Count"
                    titleDescription:@"Replace YouTube's like count with RYD's crowd-sourced value"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"RYD-USE-LIKE-DATA"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"RYD-USE-LIKE-DATA"];
                        return YES;
                    }
                    settingItemId:0],
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"Return YouTube Dislikes" pickerSectionTitle:nil rows:rydRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [rows addObject:ryd];

    // ── 5. YTUHD ──────────────────────────────────────────────────────────────
    // Reads/writes the same NSUserDefaults keys defined in YTUHD's Header.h.
    YTSettingsSectionItem *ytuhd = [item itemWithTitle:@"YTUHD"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            return [[NSUserDefaults standardUserDefaults] boolForKey:@"EnableVP9"] ? @"VP9 On" : @"VP9 Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            NSArray *uhdRows = @[
                [item switchItemWithTitle:@"Use VP9 / AV1"
                    titleDescription:@"Prefer VP9/AV1 streams for higher quality video"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"EnableVP9"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"EnableVP9"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Force All VP9"
                    titleDescription:@"Use VP9 streams for every video regardless of resolution"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"AllVP9"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"AllVP9"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Disable Server ABR"
                    titleDescription:@"Bypass server-side adaptive bitrate to allow 4K on all devices"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"DisableServerABR"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"DisableServerABR"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Skip Loop Filter"
                    titleDescription:@"Skip the VP9 loop filter for faster decoding (lower quality)"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"VP9SkipLoopFilter"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"VP9SkipLoopFilter"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Loop Filter Optimisation"
                    titleDescription:@"Enable VP9 loop filter optimisation for better performance"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"VP9LoopFilterOptimization"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"VP9LoopFilterOptimization"];
                        return YES;
                    }
                    settingItemId:0],

                [item switchItemWithTitle:@"Row Threading"
                    titleDescription:@"Enable multi-threaded row-based VP9 decoding"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[ud boolForKey:@"VP9RowThreading"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [ud setBool:enabled forKey:@"VP9RowThreading"];
                        return YES;
                    }
                    settingItemId:0],
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"YTUHD" pickerSectionTitle:nil rows:uhdRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [rows addObject:ytuhd];

    // ── 6. YouQuality ─────────────────────────────────────────────────────────
    // YouQuality uses the @"YouQuality" key in NSUserDefaults to store its enabled state.
    YTSettingsSectionItem *youQuality = [item itemWithTitle:@"YouQuality"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            return [[NSUserDefaults standardUserDefaults] boolForKey:@"YouQuality"] ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *yqRows = @[
                [item switchItemWithTitle:@"Enable YouQuality"
                    titleDescription:@"Show a quality button in the player with compact labels (4K, 2K, HD)"
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YouQuality"]
                    switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YouQuality"];
                        return YES;
                    }
                    settingItemId:0],
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"YouQuality" pickerSectionTitle:nil rows:yqRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [rows addObject:youQuality];


    // ── 7. Gonerino ───────────────────────────────────────────────────────────
    YTSettingsSectionItem *gonerino = [item itemWithTitle:@"Gonerino"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            return [[NSUserDefaults standardUserDefaults] boolForKey:@"GonerinoEnabled"] ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *gonRows = [NSMutableArray array];
            [gonRows addObject:[item switchItemWithTitle:@"Enable Gonerino"
                titleDescription:@"Block channels and videos from feed"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] objectForKey:@"GonerinoEnabled"] == nil ? NO : [[NSUserDefaults standardUserDefaults] boolForKey:@"GonerinoEnabled"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"GonerinoEnabled"];
                    return YES;
                } settingItemId:0]];
            [gonRows addObject:[item switchItemWithTitle:@"Show Nav Button"
                titleDescription:@"Show Gonerino toggle button in navigation bar"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] objectForKey:@"GonerinoShowButton"] == nil ? NO : [[NSUserDefaults standardUserDefaults] boolForKey:@"GonerinoShowButton"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"GonerinoShowButton"];
                    return YES;
                } settingItemId:0]];
            YTSettingsPickerViewController *gPicker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"Gonerino" pickerSectionTitle:nil rows:gonRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:gPicker];
            return YES;
        }];
    [rows addObject:gonerino];

    // ── 8. VolumeBoostYT ─────────────────────────────────────────────────────
    YTSettingsSectionItem *volBoost = [item itemWithTitle:@"VolumeBoostYT"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{
            return [[NSUserDefaults standardUserDefaults] boolForKey:@"VolumeBoostEnabled"] ? @"On" : @"Off";
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *vbRows = [NSMutableArray array];
            [vbRows addObject:[item switchItemWithTitle:@"Enable Volume Boost"
                titleDescription:@"Swipe right edge to boost volume beyond 100%"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"VolumeBoostEnabled"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"VolumeBoostEnabled"];
                    return YES;
                } settingItemId:0]];
            YTSettingsPickerViewController *vbPicker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"VolumeBoostYT" pickerSectionTitle:nil rows:vbRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:vbPicker];
            return YES;
        }];
    [rows addObject:volBoost];

    // ── 9. YTweaks ───────────────────────────────────────────────────────────
    YTSettingsSectionItem *ytweaks = [item itemWithTitle:@"YTweaks"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *ytRows = [NSMutableArray array];
            [ytRows addObject:[item switchItemWithTitle:@"Force Dark Mode"
                titleDescription:@"Override YouTube theme to dark/night mode"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YTweaksDarkMode"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YTweaksDarkMode"];
                    return YES;
                } settingItemId:0]];
            [ytRows addObject:[item switchItemWithTitle:@"Force Fullscreen"
                titleDescription:@"Always open videos in fullscreen"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YTweaksForceFullscreen"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YTweaksForceFullscreen"];
                    return YES;
                } settingItemId:0]];
            [ytRows addObject:[item switchItemWithTitle:@"Hide AI Summaries"
                titleDescription:@"Remove AI-generated video summaries from feed"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YTweaksHideAISummaries"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YTweaksHideAISummaries"];
                    return YES;
                } settingItemId:0]];
            [ytRows addObject:[item switchItemWithTitle:@"Virtual Bezel"
                titleDescription:@"Show a virtual device bezel around the video"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YTweaksVirtualBezel"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YTweaksVirtualBezel"];
                    return YES;
                } settingItemId:0]];
            YTSettingsPickerViewController *ytPicker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"YTweaks" pickerSectionTitle:nil rows:ytRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:ytPicker];
            return YES;
        }];
    [rows addObject:ytweaks];

    // ── 10. YTABConfig ───────────────────────────────────────────────────────
    YTSettingsSectionItem *ytabconfig = [item itemWithTitle:@"A/B Config"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *abRows = [NSMutableArray array];
            [abRows addObject:[item switchItemWithTitle:@"Enable A/B Override"
                titleDescription:@"Override YouTube A/B experiment flags"
                accessibilityIdentifier:@"YTPlusSectionItem"
                switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"YTABConfigEnabled"]
                switchBlock:^BOOL(YTSettingsCell *c, BOOL enabled) {
                    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"YTABConfigEnabled"];
                    return YES;
                } settingItemId:0]];
            YTSettingsPickerViewController *abPicker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"A/B Config" pickerSectionTitle:nil rows:abRows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:abPicker];
            return YES;
        }];
    [rows addObject:ytabconfig];

    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
        initWithNavTitle:@"Tweaks" pickerSectionTitle:nil rows:rows
        selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
    [settingsVC pushViewController:picker];
}

%new(v@:@)
- (void)updateYTPlusSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    Class item = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsVC = nil;
    for (NSString *key in @[@"_settingsViewControllerDelegate", @"_dataDelegate", @"_delegate"]) {
        @try { settingsVC = [self valueForKey:key]; } @catch (...) { settingsVC = nil; }
        if (settingsVC && [settingsVC isKindOfClass:%c(YTSettingsViewController)]) break;
        settingsVC = nil;
    }
    if (!settingsVC) return;

    YTSettingsSectionItem *space = [item itemWithTitle:nil accessibilityIdentifier:@"YTPlusSectionItem" detailTextBlock:nil selectBlock:nil];

    // ── Tweaks ────────────────────────────────────────────────────────────────
    // This row appears ABOVE the "Accounts" section and lets the user configure
    // each bundled tweak (YouPiP, DontEatMyContent, RYD, YTUHD, YouQuality) in one place.
    YTSettingsSectionItem *tweaks = [item itemWithTitle:@"Tweaks"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            [self updateYTPlusTweaksSectionWithSettingsVC:settingsVC];
            return YES;
        }];
    [sectionItems addObject:tweaks];

    // ── General ──────────────────────────────────────────────────────────────
    YTSettingsSectionItem *general = [item itemWithTitle:LOC(@"General")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [self switchWithTitle:@"RemoveAds" key:@"noAds"],
                [self switchWithTitle:@"BackgroundPlayback" key:@"backgroundPlayback"]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"General") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:general];

    // ── Navbar ───────────────────────────────────────────────────────────────
    YTSettingsSectionItem *navbar = [item itemWithTitle:LOC(@"Navbar")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray arrayWithArray:@[
                [self switchWithTitle:@"RemoveCast" key:@"noCast"],
                [self switchWithTitle:@"RemoveNotifications" key:@"noNotifsButton"],
                [self switchWithTitle:@"RemoveSearch" key:@"noSearchButton"],
                [self switchWithTitle:@"RemoveVoiceSearch" key:@"noVoiceSearchButton"]
            ]];
            [rows addObjectsFromArray:@[
                [self switchWithTitle:@"StickyNavbar" key:@"stickyNavbar"],
                [self switchWithTitle:@"NoSubbar" key:@"noSubbar"],
                [self switchWithTitle:@"NoYTLogo" key:@"noYTLogo"],
                [self switchWithTitle:@"PremiumYTLogo" key:@"premiumYTLogo"]
            ]];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Navbar") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:navbar];

    // ── Overlay ───────────────────────────────────────────────────────────────
    YTSettingsSectionItem *overlay = [item itemWithTitle:LOC(@"Overlay")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [self switchWithTitle:@"HideAutoplay" key:@"hideAutoplay"],
                [self switchWithTitle:@"HideSubs" key:@"hideSubs"],
                [self switchWithTitle:@"NoHUDMsgs" key:@"noHUDMsgs"],
                [self switchWithTitle:@"HidePrevNext" key:@"hidePrevNext"],
                [self switchWithTitle:@"ReplacePrevNext" key:@"replacePrevNext"],
                [self switchWithTitle:@"NoDarkBg" key:@"noDarkBg"],
                [self switchWithTitle:@"NoEndScreenCards" key:@"endScreenCards"],
                [self switchWithTitle:@"NoFullscreenActions" key:@"noFullscreenActions"],
                [self switchWithTitle:@"PersistentProgressBar" key:@"persistentProgressBar"],                [self switchWithTitle:@"NoRelatedVids" key:@"noRelatedVids"],                [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
                [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
                [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Overlay") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:overlay];

    // ── Player ────────────────────────────────────────────────────────────────
    YTSettingsSectionItem *player = [item itemWithTitle:LOC(@"Player")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[                [self switchWithTitle:@"PortraitFullscreen" key:@"portraitFullscreen"],
                [self switchWithTitle:@"CopyWithTimestamp" key:@"copyWithTimestamp"],
                [self switchWithTitle:@"DisableAutoplay" key:@"disableAutoplay"],
                [self switchWithTitle:@"DisableAutoCaptions" key:@"disableAutoCaptions"],
                [self switchWithTitle:@"NoContentWarning" key:@"noContentWarning"],                [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
                [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
                [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"],
                [self switchWithTitle:@"RedProgressBar" key:@"redProgressBar"],
                [self switchWithTitle:@"NoPlayerRemixButton" key:@"noPlayerRemixButton"],
                [self switchWithTitle:@"NoPlayerClipButton" key:@"noPlayerClipButton"],
                [self switchWithTitle:@"DownloadManager" key:@"downloadManager"],
                [self switchWithTitle:@"SaveToPhotos" key:@"downloadSaveToPhotos"],
                [self switchWithTitle:@"PreferDRCAudio" key:@"downloadPreferDRC"],
                [self switchWithTitle:@"NoPlayerDownloadButton" key:@"noPlayerDownloadButton"],
                [self switchWithTitle:@"NoHints" key:@"noHints"],                [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
                [self switchWithTitle:@"ExitFullscreen" key:@"exitFullscreen"],
                [self switchWithTitle:@"NoDoubleTap2Seek" key:@"noDoubleTapToSeek"]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Player") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:player];

    // ── Shorts ────────────────────────────────────────────────────────────────
    YTSettingsSectionItem *shorts = [item itemWithTitle:LOC(@"Shorts")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [self switchWithTitle:@"ShortsOnlyMode" key:@"shortsOnlyMode"],
                [self switchWithTitle:@"AutoSkipShorts" key:@"autoSkipShorts"],
                [self switchWithTitle:@"HideShorts" key:@"hideShorts"],
                [self switchWithTitle:@"ShortsProgress" key:@"shortsProgress"],
                [self switchWithTitle:@"PinchToFullscreenShorts" key:@"pinchToFullscreenShorts"],
                [self switchWithTitle:@"ShortsToRegular" key:@"shortsToRegular"],                [self switchWithTitle:@"HideShortsLogo" key:@"hideShortsLogo"],
                [self switchWithTitle:@"HideShortsSearch" key:@"hideShortsSearch"],
                [self switchWithTitle:@"HideShortsCamera" key:@"hideShortsCamera"],
                [self switchWithTitle:@"HideShortsMore" key:@"hideShortsMore"],
                [self switchWithTitle:@"HideShortsSubscriptions" key:@"hideShortsSubscriptions"],
                [self brokenSwitchWithTitle:@"HideShortsLike ⚠️" key:@"hideShortsLike"],
                [self brokenSwitchWithTitle:@"HideShortsDislike ⚠️" key:@"hideShortsDislike"],
                [self brokenSwitchWithTitle:@"HideShortsComments ⚠️" key:@"hideShortsComments"],
                [self brokenSwitchWithTitle:@"HideShortsRemix ⚠️" key:@"hideShortsRemix"],
                [self switchWithTitle:@"HideShortsShare" key:@"hideShortsShare"],
                [self brokenSwitchWithTitle:@"HideShortsAvatars ⚠️" key:@"hideShortsAvatars"],
                [self switchWithTitle:@"HideShortsThanks" key:@"hideShortsThanks"],
                [self switchWithTitle:@"HideShortsSource" key:@"hideShortsSource"],
                [self switchWithTitle:@"HideShortsChannelName" key:@"hideShortsChannelName"],
                [self switchWithTitle:@"HideShortsDescription" key:@"hideShortsDescription"],
                [self switchWithTitle:@"HideShortsAudioTrack" key:@"hideShortsAudioTrack"],
                [self switchWithTitle:@"NoPromotionCards" key:@"hideShortsPromoCards"]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Shorts") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:shorts];

    // ── Tab bar ───────────────────────────────────────────────────────────────
    YTSettingsSectionItem *tabbar = [item itemWithTitle:LOC(@"Tabbar")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [self switchWithTitle:@"RemoveLabels" key:@"removeLabels"],
                [self switchWithTitle:@"RemoveIndicators" key:@"removeIndicators"],
                [self switchWithTitle:@"ReExplore" key:@"reExplore"],
                [self switchWithTitle:@"AddExplore" key:@"addExplore"],
                [self switchWithTitle:@"HideShortsTab" key:@"removeShorts"],
                [self switchWithTitle:@"HideSubscriptionsTab" key:@"removeSubscriptions"],
                [self switchWithTitle:@"HideUploadButton" key:@"removeUploads"],
                [self switchWithTitle:@"HideLibraryTab" key:@"removeLibrary"]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Tabbar") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:tabbar];

    // ── Cache ─────────────────────────────────────────────────────────────────
    YTSettingsSectionItem *cacheSection = [item itemWithTitle:@"Cache"
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [item itemWithTitle:LOC(@"ClearCache") titleDescription:nil
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    detailTextBlock:^NSString *{ return GetCacheSize(); }
                    selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
                            [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
                        });
                        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Done") firstResponder:[self parentResponder]] send];
                        return YES;
                    }],
                [self switchWithTitle:@"ClearCacheOnStartup" key:@"clearCacheOnStartup"],
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:@"Cache" pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:cacheSection];

    // ── Other ─────────────────────────────────────────────────────────────────
    YTSettingsSectionItem *other = [item itemWithTitle:LOC(@"Other")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[                [self switchWithTitle:@"PostManager" key:@"postManager"],
                [self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"],
                [self switchWithTitle:@"CommentManager" key:@"commentManager"],
                [self switchWithTitle:@"FixAlbums" key:@"fixAlbums"],
                [self switchWithTitle:@"NativeShare" key:@"nativeShare"],                [self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"],
                [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
                [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
                [self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"],
                [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
                [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
                [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"],
                [self switchWithTitle:@"NoContinueWatching" key:@"noContinueWatching"],
                [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                [self switchWithTitle:@"NoRelatedWatchNexts" key:@"noRelatedWatchNexts"],
                [self switchWithTitle:@"StickSortComments" key:@"stickSortComments"],                [self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"],            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Other") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:other];
    [sectionItems addObject:space];

    // ── Hold-to-speed picker ──────────────────────────────────────────────────
    NSArray *speedLabels = @[LOC(@"Disabled"), LOC(@"Default"), @"0.25×", @"0.5×", @"0.75×",
                              @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
    NSArray *speedSelectLabels = @[LOC(@"Disable"), LOC(@"Default"), @"0.25×", @"0.5×", @"0.75×",
                                    @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
    YTSettingsSectionItem *holdSpeed = [item itemWithTitle:LOC(@"HoldToSpeed")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return speedLabels[ytpInt(@"speedIndex")]; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray array];
            [speedSelectLabels enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
                [rows addObject:[item checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger idx) {
                    [settingsVC reloadData];
                    ytpSetInt((int)idx, @"speedIndex");
                    return YES;
                }]];
            }];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"HoldToSpeed") pickerSectionTitle:nil rows:rows
                selectedItemIndex:ytpInt(@"speedIndex") parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:holdSpeed];

    // ── Auto speed ────────────────────────────────────────────────────────────
    NSArray *autoSpeedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×",
                                  @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
    YTSettingsSectionItem *autoSpeed = [item itemWithTitle:LOC(@"DefaultPlaybackRate")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return autoSpeedLabels[ytpInt(@"autoSpeedIndex")]; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray array];
            [autoSpeedLabels enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
                [rows addObject:[item checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger idx) {
                    [settingsVC reloadData];
                    ytpSetInt((int)idx, @"autoSpeedIndex");
                    return YES;
                }]];
            }];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"DefaultPlaybackRate") pickerSectionTitle:nil rows:rows
                selectedItemIndex:ytpInt(@"autoSpeedIndex") parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:autoSpeed];

    // ── WiFi quality ──────────────────────────────────────────────────────────
    NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p",
                                @"1440p60", @"1440p", @"1080p60", @"1080p",
                                @"720p60", @"720p", @"480p", @"360p"];
    YTSettingsSectionItem *wifiQ = [item itemWithTitle:LOC(@"PlaybackQualityOnWiFi")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return qualityLabels[ytpInt(@"wiFiQualityIndex")]; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray array];
            [qualityLabels enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
                [rows addObject:[item checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger idx) {
                    [settingsVC reloadData];
                    ytpSetInt((int)idx, @"wiFiQualityIndex");
                    return YES;
                }]];
            }];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows
                selectedItemIndex:ytpInt(@"wiFiQualityIndex") parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:wifiQ];

    // ── Cell quality ──────────────────────────────────────────────────────────
    YTSettingsSectionItem *cellQ = [item itemWithTitle:LOC(@"PlaybackQualityOnCellular")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return qualityLabels[ytpInt(@"cellQualityIndex")]; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray array];
            [qualityLabels enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
                [rows addObject:[item checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger idx) {
                    [settingsVC reloadData];
                    ytpSetInt((int)idx, @"cellQualityIndex");
                    return YES;
                }]];
            }];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows
                selectedItemIndex:ytpInt(@"cellQualityIndex") parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:cellQ];

    // ── Startup tab ───────────────────────────────────────────────────────────
    NSArray *tabLabels = @[LOC(@"Home"), LOC(@"Explore"), LOC(@"ShortsTab"), LOC(@"Subscriptions"), LOC(@"Library")];
    YTSettingsSectionItem *startup = [item itemWithTitle:LOC(@"Startup")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return tabLabels[ytpInt(@"pivotIndex")]; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray *rows = [NSMutableArray array];
            [tabLabels enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
                [rows addObject:[item checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger idx) {
                    if (([title isEqualToString:LOC(@"Explore")] && !ytpBool(@"reExplore") && !ytpBool(@"addExplore")) ||
                        ([title isEqualToString:LOC(@"ShortsTab")] && ytpBool(@"removeShorts")) ||
                        ([title isEqualToString:LOC(@"Subscriptions")] && ytpBool(@"removeSubscriptions")) ||
                        ([title isEqualToString:LOC(@"Library")] && ytpBool(@"removeLibrary"))) {
                        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
                        alertView.title = LOC(@"Warning");
                        alertView.subtitle = LOC(@"TabIsHidden");
                        [alertView show];
                        return NO;
                    }
                    [settingsVC reloadData];
                    ytpSetInt((int)idx, @"pivotIndex");
                    return YES;
                }]];
            }];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"Startup") pickerSectionTitle:nil rows:rows
                selectedItemIndex:ytpInt(@"pivotIndex") parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:startup];

    [sectionItems addObject:space];

    // ── About / Contributors / Version ────────────────────────────────────────
    YTSettingsSectionItem *thanks = [item itemWithTitle:LOC(@"Contributors")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @">"; }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [self linkWithTitle:@"Schultzy" description:@"Mod by Schultzy" link:@"https://github.com/"],
                [self linkWithTitle:@"dayanch96" description:@"Original YTPlus tweak creator" link:@"https://github.com/dayanch96"],
                space,
                [self linkWithTitle:@"PoomSmart" description:@"YouTube-X, YTNoPremium, YTClassicVideoQuality, YTShortsProgress, YTReExplore" link:@"https://github.com/PoomSmart/"],
                [self linkWithTitle:@"MiRO92" description:@"YTNoShorts" link:@"https://github.com/MiRO92/YTNoShorts"],
                [self linkWithTitle:@"Tony Million" description:@"Reachability" link:@"https://github.com/tonymillion/Reachability"],
                [self linkWithTitle:@"jkhsjdhjs" description:@"YouTube Native Share" link:@"https://github.com/jkhsjdhjs/youtube-native-share"]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"About") pickerSectionTitle:LOC(@"Credits") rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:thanks];

    YTSettingsSectionItem *version = [item itemWithTitle:LOC(@"Version")
        accessibilityIdentifier:@"YTPlusSectionItem"
        detailTextBlock:^NSString *{ return @(OS_STRINGIFY(TWEAK_VERSION)); }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *rows = @[
                [self switchWithTitle:@"Advanced" key:@"advancedMode"],

                [item itemWithTitle:LOC(@"ResetSettings") titleDescription:nil
                    accessibilityIdentifier:@"YTPlusSectionItem"
                    detailTextBlock:nil
                    selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                        YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                            [YTPUserDefaults resetUserDefaults];
                            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
                            [NSThread sleepForTimeInterval:1.0];
                            exit(0);
                        }
                        actionTitle:LOC(@"Yes")
                        cancelTitle:LOC(@"No")];
                        alertView.title = LOC(@"Warning");
                        alertView.subtitle = LOC(@"ResetMessage");
                        [alertView show];
                        return YES;
                    }]
            ];
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                initWithNavTitle:LOC(@"About") pickerSectionTitle:nil rows:rows
                selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsVC pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:version];

    // setSectionItems must be called on the YTSettingsViewController (the data delegate).
    YTSettingsViewController *vc = nil;
    for (NSString *key in @[@"_settingsViewControllerDelegate", @"_dataDelegate", @"_delegate"]) {
        @try { vc = [self valueForKey:key]; } @catch (...) { vc = nil; }
        if (vc && [vc isKindOfClass:%c(YTSettingsViewController)]) break;
        vc = nil;
    }
    if (!vc) return;
    BOOL isNew = [vc respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)];
    if (isNew) {
        YTIIcon *icon = [%c(YTIIcon) new];
        icon.iconType = 267;
        [vc setSectionItems:sectionItems forCategory:YTPlusSection title:@"YouTube Plus Revanced" icon:(UIImage *)icon titleDescription:nil headerHidden:NO];
    } else {
        [vc setSectionItems:sectionItems forCategory:YTPlusSection title:@"YouTube Plus Revanced" titleDescription:nil headerHidden:NO];
    }
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == YTPlusSection) {
        [self updateYTPlusSectionWithEntry:entry];
        return;
    }
    %orig;
}

%end

// ─── Belt-and-suspenders: direct hook on YTSettingsViewController ─────────────

%hook YTSettingsViewController
- (void)loadWithModel:(id)model {
    %orig;
    static BOOL ytpRegistered = NO;
    if (!ytpRegistered) {
        YTSettingsSectionItemManager *mgr = nil;
        for (NSString *key in @[@"_sectionItemManager", @"_settingsSectionItemManager", @"_itemManager", @"_manager"]) {
            @try { mgr = [self valueForKey:key]; } @catch (...) {}
            if (mgr && [mgr respondsToSelector:@selector(updateYTPlusSectionWithEntry:)]) break;
            mgr = nil;
        }
        if (mgr) {
            ytpRegistered = YES;
            [mgr updateYTPlusSectionWithEntry:nil];
        }
    }
}
%end
