// Settings.x — YTPlus settings panel
// Adapted from YTLite open-source by dayanch96, modded by Schultzy.

#import "YTPlus.h"

@interface YTSettingsGroupData : NSObject
@property (nonatomic, assign) NSInteger type;
- (NSArray <NSNumber *> *)orderedCategories;
@end
@interface YTSettingsSectionItemManager (YTPlus)
- (void)updateYTPlusSectionWithEntry:(id)entry;
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
    // Remove if already present (safety), then insert at the very top so YTPlus
    // appears as the first item in the Tweaks section above Account/General.
    [mutableOrder removeObject:@(YTPlusSection)];
    [mutableOrder insertObject:@(YTPlusSection) atIndex:0];
    // Support YTUHD section (its own hook is broken in YouTube 21.x)
    static const NSInteger YTUHDSection = 'ythd';
    if (objc_getClass("MLHAMQueuePlayer") != nil) {
        [mutableOrder removeObject:@(YTUHDSection)];
        [mutableOrder insertObject:@(YTUHDSection) atIndex:1];
    }
    return mutableOrder;
}
%end

%hook YTSettingsGroupData

- (NSArray <NSNumber *> *)orderedCategories {
    if (class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks)))
        return %orig;
    NSMutableArray *mutableCategories = %orig.mutableCopy;
    [mutableCategories insertObject:@(YTPlusSection) atIndex:0];
    // Support YTUHD section (its self.type != 1 guard breaks in YouTube 21.x)
    static const NSInteger YTUHDSection = 'ythd';
    if (objc_getClass("MLHAMQueuePlayer") != nil) {
        [mutableCategories insertObject:@(YTUHDSection) atIndex:1];
    }
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
                // When ad blocking is toggled, clear YouTube's response cache so
                // cached ad data doesn't survive the toggle change
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

%new(v@:@)
- (void)updateYTPlusSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    Class item = %c(YTSettingsSectionItem);
    // Get the settings VC via whatever ivar name this YouTube version uses
    YTSettingsViewController *settingsVC = nil;
    for (NSString *key in @[@"_settingsViewControllerDelegate", @"_dataDelegate", @"_delegate"]) {
        @try { settingsVC = [self valueForKey:key]; } @catch (...) { settingsVC = nil; }
        if (settingsVC && [settingsVC isKindOfClass:%c(YTSettingsViewController)]) break;
        settingsVC = nil;
    }
    if (!settingsVC) return;

    YTSettingsSectionItem *space = [item itemWithTitle:nil accessibilityIdentifier:@"YTPlusSectionItem" detailTextBlock:nil selectBlock:nil];

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

    // ── Overlay ───────────────────────────────────────────────────────────
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
                    [self switchWithTitle:@"PersistentProgressBar" key:@"persistentProgressBar"],
                    [self switchWithTitle:@"StockVolumeHUD" key:@"stockVolumeHUD"],
                    [self switchWithTitle:@"NoRelatedVids" key:@"noRelatedVids"],
                    [self switchWithTitle:@"NoPromotionCards" key:@"noPromotionCards"],
                    [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
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

        // ── Player ────────────────────────────────────────────────────────────
        YTSettingsSectionItem *player = [item itemWithTitle:LOC(@"Player")
            accessibilityIdentifier:@"YTPlusSectionItem"
            detailTextBlock:^NSString *{ return @">"; }
            selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
                NSArray *rows = @[
                    [self switchWithTitle:@"Miniplayer" key:@"miniplayer"],
                    [self switchWithTitle:@"PortraitFullscreen" key:@"portraitFullscreen"],
                    [self switchWithTitle:@"CopyWithTimestamp" key:@"copyWithTimestamp"],
                    [self switchWithTitle:@"DisableAutoplay" key:@"disableAutoplay"],
                    [self switchWithTitle:@"DisableAutoCaptions" key:@"disableAutoCaptions"],
                    [self switchWithTitle:@"NoContentWarning" key:@"noContentWarning"],
                    [self switchWithTitle:@"ClassicQuality" key:@"classicQuality"],
                    [self switchWithTitle:@"ExtraSpeedOptions" key:@"extraSpeedOptions"],
                    [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
                    [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
                    [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"],
                    [self switchWithTitle:@"RedProgressBar" key:@"redProgressBar"],
                    [self switchWithTitle:@"NoPlayerRemixButton" key:@"noPlayerRemixButton"],
                    [self switchWithTitle:@"NoPlayerClipButton" key:@"noPlayerClipButton"],
                    [self switchWithTitle:@"NoPlayerDownloadButton" key:@"noPlayerDownloadButton"],
                    [self switchWithTitle:@"NoHints" key:@"noHints"],
                    [self switchWithTitle:@"NoFreeZoom" key:@"noFreeZoom"],
                    [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
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

        // ── Shorts ────────────────────────────────────────────────────────────
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
                    [self switchWithTitle:@"ShortsToRegular" key:@"shortsToRegular"],
                    [self switchWithTitle:@"ResumeShorts" key:@"resumeShorts"],
                    [self switchWithTitle:@"HideShortsLogo" key:@"hideShortsLogo"],
                    [self switchWithTitle:@"HideShortsSearch" key:@"hideShortsSearch"],
                    [self switchWithTitle:@"HideShortsCamera" key:@"hideShortsCamera"],
                    [self switchWithTitle:@"HideShortsMore" key:@"hideShortsMore"],
                    [self switchWithTitle:@"HideShortsSubscriptions" key:@"hideShortsSubscriptions"],
                    [self switchWithTitle:@"HideShortsLike" key:@"hideShortsLike"],
                    [self switchWithTitle:@"HideShortsDislike" key:@"hideShortsDislike"],
                    [self switchWithTitle:@"HideShortsComments" key:@"hideShortsComments"],
                    [self switchWithTitle:@"HideShortsRemix" key:@"hideShortsRemix"],
                    [self switchWithTitle:@"HideShortsShare" key:@"hideShortsShare"],
                    [self switchWithTitle:@"HideShortsAvatars" key:@"hideShortsAvatars"],
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

    // ── Cache ─────────────────────────────────────────────────────────────
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

    // ── Other ─────────────────────────────────────────────────────────────
        YTSettingsSectionItem *other = [item itemWithTitle:LOC(@"Other")
            accessibilityIdentifier:@"YTPlusSectionItem"
            detailTextBlock:^NSString *{ return @">"; }
            selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
                NSArray *rows = @[
                    [self switchWithTitle:@"CopyVideoInfo" key:@"copyVideoInfo"],
                    [self switchWithTitle:@"PostManager" key:@"postManager"],
                    [self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"],
                    [self switchWithTitle:@"CommentManager" key:@"commentManager"],
                    [self switchWithTitle:@"FixAlbums" key:@"fixAlbums"],
                    [self switchWithTitle:@"NativeShare" key:@"nativeShare"],
                    [self switchWithTitle:@"RemovePlayNext" key:@"removePlayNext"],
                    [self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"],
                    [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
                    [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
                    [self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"],
                    [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
                    [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
                    [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"],
                    [self switchWithTitle:@"NoContinueWatching" key:@"noContinueWatching"],
                    [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                    [self switchWithTitle:@"NoRelatedWatchNexts" key:@"noRelatedWatchNexts"],
                    [self switchWithTitle:@"StickSortComments" key:@"stickSortComments"],
                    [self switchWithTitle:@"HideSortComments" key:@"hideSortComments"],
                    [self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"],
                    [self switchWithTitle:@"DisableRTL" key:@"disableRTL"]
                ];
                YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc]
                    initWithNavTitle:LOC(@"Other") pickerSectionTitle:nil rows:rows
                    selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                [settingsVC pushViewController:picker];
                return YES;
            }];
        [sectionItems addObject:other];
        [sectionItems addObject:space];

        // ── Hold-to-speed picker ──────────────────────────────────────────────
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

        // ── Auto speed ────────────────────────────────────────────────────────
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

        // ── WiFi quality ──────────────────────────────────────────────────────
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

        // ── Cell quality ──────────────────────────────────────────────────────
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

        // ── Startup tab ───────────────────────────────────────────────────────
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
    // Try all known ivar names across YouTube versions to get the VC reference.
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
// When the settings screen appears, walk through the section item manager and
// call our builder directly. Catches cases where the category order hook fires
// but the manager->VC delegate ivar is nil at that moment.

%hook YTSettingsViewController
- (void)loadWithModel:(id)model {
    %orig;
    static BOOL ytpRegistered = NO;
    if (!ytpRegistered) {
        // Try several known ivar names for the section item manager across YT versions
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
