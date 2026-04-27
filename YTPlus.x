// YTPlus.x
// Rebuilt from YTLite open-source by the community.
// Updated for YouTube 21.16.2 (iOS 16+).
// Mod by Schultzy — built on YTLite open-source base.

#import "YTPlus.h"

// ─── Helpers ──────────────────────────────────────────────────────────────────

static UIImage *YTPImageNamed(NSString *imageName) {
    return [UIImage imageNamed:imageName inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
}

// ─── Background Playback (YouTube-X) ─────────────────────────────────────────

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return ytpBool(@"backgroundPlayback") ? YES : NO; }
%end

%hook MLVideo
- (BOOL)playableInBackground { return ytpBool(@"backgroundPlayback") ? YES : NO; }
%end

// ─── Disable Ads ──────────────────────────────────────────────────────────────

%hook YTIPlayerResponse
- (BOOL)isMonetized { return ytpBool(@"noAds") ? NO : YES; }
// Kill in-player ad slots at the proto level (skippable/non-skippable/bumper)
- (NSMutableArray *)adSlotsArray { return ytpBool(@"noAds") ? [NSMutableArray array] : %orig; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary { return ytpBool(@"noAds") ? nil : %orig; }
+ (id)spamSignalsDictionaryWithoutIDFA { return ytpBool(@"noAds") ? nil : %orig; }
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { if (!ytpBool(@"noAds")) %orig; }
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { if (!ytpBool(@"noAds")) %orig; }
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    if (self.hasCompatibilityOptions && self.compatibilityOptions.hasAdLoggingData && ytpBool(@"noAds")) return nil;

    NSString *description = [self description];

    if (ytpBool(@"noAds")) {
        // Keyword-based match covers renamed/new ad renderer types in 21.16.2+
        NSArray *adKeywords = @[@"brand_promo", @"product_carousel", @"product_engagement_panel",
                                @"product_item", @"text_search_ad", @"text_image_button_layout",
                                @"carousel_headered_layout", @"carousel_footered_layout",
                                @"square_image_layout", @"landscape_image_wide_button_layout",
                                @"feed_ad_metadata", @"promoted_sparkles", @"promoted_video",
                                @"promoted_text", @"promoted_app", @"compact_promoted",
                                @"ad_placement", @"ad_slot", @"companion_ad",
                                @"shopping_companion", @"linear_ad"];
        for (NSString *keyword in adKeywords) {
            if ([description containsString:keyword]) return nil;
        }
    }

    NSArray *shortsToRemove = @[@"shorts_shelf.eml", @"shorts_video_cell.eml", @"6Shorts"];
    for (NSString *shorts in shortsToRemove) {
        if (ytpBool(@"hideShorts") && [description containsString:shorts]
            && ![description containsString:@"history*"]) {
            return nil;
        }
    }

    return %orig;
}
%end

%hook YTSectionListViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    if (ytpBool(@"noAds")) {
        NSMutableArray *contents = model.contentsArray;
        NSArray *adKeywords = @[@"brand_promo", @"product_carousel", @"product_engagement_panel",
                                @"product_item", @"text_search_ad", @"text_image_button_layout",
                                @"carousel_headered_layout", @"carousel_footered_layout",
                                @"square_image_layout", @"landscape_image_wide_button_layout",
                                @"feed_ad_metadata", @"promoted_sparkles", @"promoted_video",
                                @"promoted_text", @"promoted_app", @"compact_promoted",
                                @"ad_placement", @"ad_slot", @"companion_ad",
                                @"shopping_companion", @"linear_ad"];
        NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < contents.count; i++) {
            NSString *desc = [contents[i] description];
            for (NSString *keyword in adKeywords) {
                if ([desc containsString:keyword]) {
                    [toRemove addIndex:i];
                    break;
                }
            }
        }
        [contents removeObjectsAtIndexes:toRemove];
    }
    %orig;
}
%end



// ─── No Premium Promos (NOYTPremium) ─────────────────────────────────────────

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTInterstitialPromoEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromosheetEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial { return YES; }
%end

%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {}
%end

%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

// ─── Cast / Navbar Buttons ────────────────────────────────────────────────────

%hook MDXPlaybackRouteButtonController
- (BOOL)isPersistentCastIconEnabled { return ytpBool(@"noCast") ? NO : YES; }
- (void)updateRouteButton:(id)arg1 { if (!ytpBool(@"noCast")) %orig; }
- (void)updateAllRouteButtons { if (!ytpBool(@"noCast")) %orig; }
%end

%hook YTSettings
- (void)setDisableMDXDeviceDiscovery:(BOOL)arg1 { %orig(ytpBool(@"noCast")); }
%end

%hook YTRightNavigationButtons
- (void)layoutSubviews {
    %orig;
    if (ytpBool(@"noNotifsButton")) self.notificationButton.hidden = YES;
    if (ytpBool(@"noSearchButton")) self.searchButton.hidden = YES;
    for (UIView *subview in self.subviews) {
        if (ytpBool(@"noVoiceSearchButton") && [subview.accessibilityLabel isEqualToString:NSLocalizedString(@"search.voice.access", nil)]) subview.hidden = YES;
        if (ytpBool(@"noCast") && [subview.accessibilityIdentifier isEqualToString:@"id.mdx.playbackroute.button"]) subview.hidden = YES;
    }
}
%end

%hook YTSearchViewController
- (void)viewDidLoad {
    %orig;
    if (ytpBool(@"noVoiceSearchButton")) [self setValue:@(NO) forKey:@"_isVoiceSearchAllowed"];
}
- (void)setSuggestions:(id)arg1 { if (!ytpBool(@"noSearchHistory")) %orig; }
%end

%hook YTPersonalizedSuggestionsCacheProvider
- (id)activeCache { return ytpBool(@"noSearchHistory") ? nil : %orig; }
%end

// ─── Remove Related Videos Section Under Player ───────────────────────────────

%hook YTWatchNextResultsViewController
- (void)setVisibleSections:(NSInteger)arg1 {
    arg1 = ytpBool(@"noRelatedWatchNexts") ? 1 : arg1;
    %orig(arg1);
}
%end

// ─── Header / Navbar ──────────────────────────────────────────────────────────

%hook YTHeaderView
- (BOOL)stickyNavHeaderEnabled { return ytpBool(@"stickyNavbar") ? YES : %orig; }
- (void)setCustomTitleView:(UIView *)customTitleView { if (!ytpBool(@"noYTLogo")) %orig; }
- (void)setTitle:(NSString *)title { ytpBool(@"noYTLogo") ? %orig(@"") : %orig; }
%end

// Premium logo swap
%hook UIImageView
- (void)setImage:(UIImage *)image {
    if (!ytpBool(@"premiumYTLogo")) return %orig;

    NSString *resourcesPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Frameworks/Module_Framework.framework/Innertube_Resources.bundle"];
    NSBundle *frameworkBundle = [NSBundle bundleWithPath:resourcesPath];

    if ([[image description] containsString:@"Resources: youtube_logo)"]) {
        image = [UIImage imageNamed:@"youtube_premium_logo" inBundle:frameworkBundle compatibleWithTraitCollection:nil];
    } else if ([[image description] containsString:@"Resources: youtube_logo_dark)"]) {
        image = [UIImage imageNamed:@"youtube_premium_logo_white" inBundle:frameworkBundle compatibleWithTraitCollection:nil];
    }

    %orig(image);
}
%end

// ─── Subbar ───────────────────────────────────────────────────────────────────

%hook YTMySubsFilterHeaderView
- (void)setChipFilterView:(id)arg1 { if (!ytpBool(@"noSubbar")) %orig; }
%end

%hook YTHeaderContentComboView
- (void)enableSubheaderBarWithView:(id)arg1 { if (!ytpBool(@"noSubbar")) %orig; }
- (void)setFeedHeaderScrollMode:(int)arg1 { ytpBool(@"noSubbar") ? %orig(0) : %orig; }
%end

%hook YTChipCloudCell
- (void)layoutSubviews {
    if (self.superview && ytpBool(@"noSubbar")) {
        [self removeFromSuperview];
    }
    %orig;
}
%end

// ─── Player Overlay ───────────────────────────────────────────────────────────

%hook YTMainAppControlsOverlayView
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { if (!ytpBool(@"hideAutoplay")) %orig; }
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { ytpBool(@"hideSubs") ? %orig(NO) : %orig; }
- (void)setOverlayVisible:(BOOL)visible {
    %orig;
    if (!ytpBool(@"pauseOnOverlay")) return;
    visible ? [self.playerViewController pause] : [self.playerViewController play];
}
%end

// ─── HUD Messages ─────────────────────────────────────────────────────────────

%hook YTHUDMessageView
- (id)initWithMessage:(id)arg1 dismissHandler:(id)arg2 { return ytpBool(@"noHUDMsgs") ? nil : %orig; }
%end

// ─── Cold Config Overrides ────────────────────────────────────────────────────

%hook YTColdConfig
- (BOOL)removeNextPaddleForSingletonVideos { return ytpBool(@"hidePrevNext") ? YES : %orig; }
- (BOOL)removePreviousPaddleForSingletonVideos { return ytpBool(@"hidePrevNext") ? YES : %orig; }
- (BOOL)replaceNextPaddleWithFastForwardButtonForSingletonVods { return ytpBool(@"replacePrevNext") ? YES : %orig; }
- (BOOL)replacePreviousPaddleWithRewindButtonForSingletonVods { return ytpBool(@"replacePrevNext") ? YES : %orig; }
- (BOOL)videoZoomFreeZoomEnabledGlobalConfig { return ytpBool(@"noFreeZoom") ? NO : %orig; }
- (BOOL)enableHideChipsInTheCommentsHeaderOnScrollIos { return ytpBool(@"stickSortComments") ? NO : %orig; }
- (BOOL)enableChipsInTheCommentsHeaderIos { return ytpBool(@"hideSortComments") ? NO : %orig; }
- (BOOL)shouldUseAppThemeSetting { return YES; }
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; }
- (BOOL)enableSwipeToRemoveInPlaylistWatchEp { return YES; }
- (BOOL)queueClientGlobalConfigEnableFloatingPlaylistMinibar { return ytpBool(@"playlistOldMinibar") ? NO : %orig; }
// Shorts config
- (BOOL)iosEnableVideoPlayerScrubber { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)mobileShortsTabInlined { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)iosUseSystemVolumeControlInFullscreen { return ytpBool(@"stockVolumeHUD") ? YES : NO; }
%end

%hook YTHotConfig
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return ytpBool(@"shortsProgress") ? YES : NO; }
%end

// ─── Dark Background ──────────────────────────────────────────────────────────

%hook YTMainAppVideoPlayerOverlayView
- (void)setBackgroundVisible:(BOOL)arg1 isGradientBackground:(BOOL)arg2 { ytpBool(@"noDarkBg") ? %orig(NO, arg2) : %orig; }
%end

// ─── End Screen Cards ─────────────────────────────────────────────────────────

%hook YTCreatorEndscreenView
- (void)setHidden:(BOOL)arg1 { ytpBool(@"endScreenCards") ? %orig(YES) : %orig; }
%end

// ─── Fullscreen Actions ───────────────────────────────────────────────────────

%hook YTFullscreenActionsView
- (BOOL)enabled { return ytpBool(@"noFullscreenActions") ? NO : YES; }
- (void)setEnabled:(BOOL)arg1 { ytpBool(@"noFullscreenActions") ? %orig(NO) : %orig; }
%end

// ─── Related Videos on Finish ────────────────────────────────────────────────

%hook YTFullscreenEngagementOverlayController
- (void)setRelatedVideosVisible:(BOOL)arg1 { ytpBool(@"noRelatedVids") ? %orig(NO) : %orig; }
%end

// ─── Paid Promotion Cards ─────────────────────────────────────────────────────

%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data { if (!ytpBool(@"noPromotionCards")) %orig; }
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && ytpBool(@"noPromotionCards")) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data { if (!ytpBool(@"noPromotionCards")) %orig; }
%end

// ─── Persistent Progress Bar ──────────────────────────────────────────────────

%hook YTInlinePlayerBarContainerView
- (void)setPlayerBarAlpha:(CGFloat)alpha { ytpBool(@"persistentProgressBar") ? %orig(1.0) : %orig; }
%end

// ─── Watermarks ───────────────────────────────────────────────────────────────

%hook YTAnnotationsViewController
- (void)loadFeaturedChannelWatermark { if (!ytpBool(@"noWatermarks")) %orig; }
%end

%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isWatermarkEnabled { return ytpBool(@"noWatermarks") ? NO : %orig; }
%end

// ─── Miniplayer ───────────────────────────────────────────────────────────────

%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer { if (!ytpBool(@"miniplayer")) %orig; }
%end

// ─── Portrait Fullscreen ──────────────────────────────────────────────────────

%hook YTWatchViewController
- (unsigned long long)allowedFullScreenOrientations { return ytpBool(@"portraitFullscreen") ? UIInterfaceOrientationMaskAllButUpsideDown : %orig; }
%end

// ─── Disable Autoplay ─────────────────────────────────────────────────────────

%hook YTPlaybackConfig
- (void)setStartPlayback:(BOOL)arg1 { ytpBool(@"disableAutoplay") ? %orig(NO) : %orig; }
%end

// ─── Skip Content Warning ─────────────────────────────────────────────────────

%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { ytpBool(@"noContentWarning") ? [self confirmAlertDidPressConfirm] : %orig; }
%end

// ─── Classic Video Quality ────────────────────────────────────────────────────

%hook YTVideoQualitySwitchControllerFactory
- (id)videoQualitySwitchControllerWithParentResponder:(id)responder {
    Class originalClass = %c(YTVideoQualitySwitchOriginalController);
    return ytpBool(@"classicQuality") && originalClass ? [[originalClass alloc] initWithParentResponder:responder] : %orig;
}
%end

// ─── Extra Speed Options ──────────────────────────────────────────────────────

%hook YTVarispeedSwitchController
- (void)setDelegate:(id)arg1 {
    NSMutableArray *optionsCopy = [[self valueForKey:@"_options"] mutableCopy];
    NSArray *speedTitles = @[@"2.5", @"3", @"3.5", @"4", @"5"];
    for (NSString *title in speedTitles) {
        YTVarispeedSwitchControllerOption *option = [[%c(YTVarispeedSwitchControllerOption) alloc] initWithTitle:title rate:[title floatValue]];
        [optionsCopy addObject:option];
    }
    if (ytpBool(@"extraSpeedOptions")) [self setValue:[optionsCopy copy] forKey:@"_options"];
    return %orig;
}
%end

// Version spoof needed for classic quality & extra speeds
%hook YTVersionUtils
+ (NSString *)appVersion {
    NSString *orig = %orig;
    NSString *fake = @"18.18.2";
    return (!ytpBool(@"classicQuality") && !ytpBool(@"extraSpeedOptions") &&
            [orig compare:fake options:NSNumericSearch] == NSOrderedDescending) ? orig : fake;
}
%end

// Show real version in settings
%hook YTSettingsCell
- (void)setDetailText:(id)arg1 {
    NSString *appVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    if ([arg1 isEqualToString:@"18.18.2"]) arg1 = appVersion;
    %orig(arg1);
}
%end

// ─── Snap To Chapter ──────────────────────────────────────────────────────────

%hook YTSegmentableInlinePlayerBarView
- (void)didMoveToWindow { %orig; if (ytpBool(@"dontSnapToChapter")) self.enableSnapToChapter = NO; }
%end

// ─── Red Progress Bar ─────────────────────────────────────────────────────────

%hook YTInlinePlayerBarContainerView
- (id)quietProgressBarColor { return ytpBool(@"redProgressBar") ? [UIColor redColor] : %orig; }
%end

%hook YTSegmentableInlinePlayerBarView
- (void)setBufferedProgressBarColor:(id)arg1 {
    if (ytpBool(@"redProgressBar"))
        %orig([UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:0.60]);
    else
        %orig;
}
%end

// ─── Hints ───────────────────────────────────────────────────────────────────

%hook YTSettings
- (BOOL)areHintsDisabled { return ytpBool(@"noHints") ? YES : NO; }
- (void)setHintsDisabled:(BOOL)arg1 { ytpBool(@"noHints") ? %orig(YES) : %orig; }
%end

%hook YTUserDefaults
- (BOOL)areHintsDisabled { return ytpBool(@"noHints") ? YES : NO; }
- (void)setHintsDisabled:(BOOL)arg1 { ytpBool(@"noHints") ? %orig(YES) : %orig; }
%end

// ─── Video End Time Helper ────────────────────────────────────────────────────

static void addEndTime(YTPlayerViewController *self, YTSingleVideoController *video, YTSingleVideoTime *time) {
    if (!ytpBool(@"videoEndTime")) return;

    CGFloat rate = video.playbackRate != 0 ? video.playbackRate : 1.0;
    NSTimeInterval remaining = (lround(video.totalMediaTime) - lround(time.time)) / rate;
    NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:remaining];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [fmt setDateFormat:ytpBool(@"24hrFormat") ? @"HH:mm" : @"h:mm a"];
    NSString *endTime = [fmt stringFromDate:endDate];

    YTPlayerView *playerView = (YTPlayerView *)self.view;
    if (![playerView.overlayView isKindOfClass:%c(YTMainAppVideoPlayerOverlayView)]) return;

    YTMainAppVideoPlayerOverlayView *overlay = (YTMainAppVideoPlayerOverlayView *)playerView.overlayView;
    YTLabel *label = overlay.playerBar.durationLabel;
    overlay.playerBar.endTimeString = endTime;

    if (![label.text containsString:endTime]) {
        label.text = [label.text stringByAppendingString:[NSString stringWithFormat:@" • %@", endTime]];
        [label sizeToFit];
    }
}

// ─── Auto Skip Shorts ─────────────────────────────────────────────────────────

static void autoSkipShorts(YTPlayerViewController *self, YTSingleVideoController *video, YTSingleVideoTime *time) {
    if (!ytpBool(@"autoSkipShorts")) return;

    if (floor(time.time) >= floor(video.totalMediaTime)) {
        if ([self.parentViewController isKindOfClass:%c(YTShortsPlayerViewController)]) {
            YTShortsPlayerViewController *shortsVC = (YTShortsPlayerViewController *)self.parentViewController;
            if ([shortsVC respondsToSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)]) {
                [shortsVC performSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)];
            }
        }
    }
}

// ─── Player View Controller ───────────────────────────────────────────────────

%hook YTPlayerViewController
- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;
    if (ytpInt(@"wiFiQualityIndex") != 0 || ytpInt(@"cellQualityIndex") != 0)
        [self performSelector:@selector(autoQuality) withObject:nil afterDelay:1.0];
    if (ytpBool(@"autoFullscreen"))
        [self performSelector:@selector(autoFullscreen) withObject:nil afterDelay:0.75];
    if (ytpBool(@"shortsToRegular"))
        [self performSelector:@selector(shortsToRegular) withObject:nil afterDelay:0.75];
    if (ytpInt(@"autoSpeedIndex") != 3)
        [self performSelector:@selector(setAutoSpeed) withObject:nil afterDelay:0.75];
    if (ytpBool(@"disableAutoCaptions"))
        [self performSelector:@selector(turnOffCaptions) withObject:nil afterDelay:1.0];
}

%new
- (void)autoFullscreen {
    id watchController = [self valueForKey:@"_UIDelegate"];
    if ([watchController respondsToSelector:@selector(showFullScreen)])
        [watchController performSelector:@selector(showFullScreen)];
}

%new
- (void)shortsToRegular {
    if (self.contentVideoID && [self.parentViewController isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")]) {
        NSString *vidLink = [NSString stringWithFormat:@"vnd.youtube://%@", self.contentVideoID];
        NSURL *url = [NSURL URLWithString:vidLink];
        if ([[UIApplication sharedApplication] canOpenURL:url])
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

%new
- (void)turnOffCaptions {
    if ([self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")])
        [self setActiveCaptionTrack:nil];
}

%new
- (void)setAutoSpeed {
    if ([self.activeVideoPlayerOverlay isKindOfClass:NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController")]
        && [self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")]) {
        YTMainAppVideoPlayerOverlayViewController *overlayVC = (YTMainAppVideoPlayerOverlayViewController *)self.activeVideoPlayerOverlay;
        NSArray *speeds = @[@0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @3.0, @4.0, @5.0];
        [overlayVC setPlaybackRate:[speeds[ytpInt(@"autoSpeedIndex")] floatValue]];
    }
}

%new
- (void)autoQuality {
    if (![self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")]) return;

    NetworkStatus status = [[Reachability reachabilityForInternetConnection] currentReachabilityStatus];
    NSInteger kQualityIndex = status == ReachableViaWiFi ? ytpInt(@"wiFiQualityIndex") : ytpInt(@"cellQualityIndex");

    NSString *bestQualityLabel;
    int highestResolution = 0;
    for (MLFormat *format in self.activeVideo.selectableVideoFormats) {
        int reso = format.singleDimensionResolution;
        if (reso > highestResolution) {
            highestResolution = reso;
            bestQualityLabel = format.qualityLabel;
        }
    }

    NSArray *qualityLabels = @[@"Default", bestQualityLabel, @"2160p60", @"2160p",
                                @"1440p60", @"1440p", @"1080p60", @"1080p",
                                @"720p60", @"720p", @"480p", @"360p"];
    NSString *qualityLabel = qualityLabels[kQualityIndex];

    if (![qualityLabel isEqualToString:bestQualityLabel]) {
        BOOL exactMatch = NO;
        NSString *closestLabel = qualityLabel;

        for (MLFormat *format in self.activeVideo.selectableVideoFormats) {
            if ([format.qualityLabel isEqualToString:qualityLabel]) { exactMatch = YES; break; }
        }

        if (!exactMatch) {
            NSInteger bestDiff = NSIntegerMax;
            for (MLFormat *format in self.activeVideo.selectableVideoFormats) {
                NSArray *fComp = [format.qualityLabel componentsSeparatedByString:@"p"];
                NSArray *tComp = [qualityLabel componentsSeparatedByString:@"p"];
                if (fComp.count == 2) {
                    NSInteger diff = labs([fComp.firstObject integerValue] - [tComp.firstObject integerValue]);
                    if (diff < bestDiff) { bestDiff = diff; closestLabel = format.qualityLabel; }
                }
            }
            qualityLabel = closestLabel;
        }
    }

    MLQuickMenuVideoQualitySettingFormatConstraint *fc = [[%c(MLQuickMenuVideoQualitySettingFormatConstraint) alloc] init];
    if ([fc respondsToSelector:@selector(initWithVideoQualitySetting:formatSelectionReason:qualityLabel:)]) {
        [self.activeVideo setVideoFormatConstraint:[fc initWithVideoQualitySetting:3 formatSelectionReason:2 qualityLabel:qualityLabel]];
    }
}

- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    addEndTime(self, video, time);
    autoSkipShorts(self, video, time);
}

- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    addEndTime(self, video, time);
    autoSkipShorts(self, video, time);
}
%end

// Progress bar end time persistence
%hook YTInlinePlayerBarContainerView
%property (nonatomic, strong) NSString *endTimeString;
- (void)setPeekableViewVisible:(BOOL)visible {
    %orig;
    if (!ytpBool(@"videoEndTime")) return;
    if (self.endTimeString && ![self.durationLabel.text containsString:self.endTimeString]) {
        self.durationLabel.text = [self.durationLabel.text stringByAppendingString:[NSString stringWithFormat:@" • %@", self.endTimeString]];
        [self.durationLabel sizeToFit];
    }
}
%end

// ─── Exit Fullscreen on Finish ────────────────────────────────────────────────

%hook YTWatchFlowController
- (BOOL)shouldExitFullScreenOnFinish { return ytpBool(@"exitFullscreen") ? YES : NO; }
%end

// ─── Gesture Overrides ────────────────────────────────────────────────────────

%hook YTMainAppVideoPlayerOverlayViewController
- (BOOL)allowDoubleTapToSeekGestureRecognizer { return ytpBool(@"noDoubleTapToSeek") ? NO : %orig; }
- (BOOL)allowTwoFingerDoubleTapGestureRecognizer { return ytpBool(@"noTwoFingerSnapToChapter") ? NO : %orig; }

- (void)didPressPause:(id)arg1 {
    %orig;
    if (ytpBool(@"copyWithTimestamp")) {
        NSString *link = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&t=%lds", self.videoID, (NSInteger)self.mediaTime];
        [UIPasteboard generalPasteboard].string = link;
    }
}
%end

// ─── Button Label Fixes ───────────────────────────────────────────────────────

%hook YTQTMButton
- (UILabel *)titleLabel {
    UILabel *label = %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.playlist.playall.button"])
        label.adjustsFontSizeToFitWidth = YES;
    return label;
}
%end

%hook YTReelPlayerButton
- (UILabel *)titleLabel {
    UILabel *label = %orig;
    label.adjustsFontSizeToFitWidth = YES;
    return label;
}
%end

%hook YTPlaylistMiniBarView
- (void)setFrame:(CGRect)frame {
    if (frame.size.height < 54.0) frame.size.height = 54.0;
    %orig(frame);
}
%end

// ─── Context Menu Filtering ───────────────────────────────────────────────────

%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    if (ytpBool(@"removePlayNext") && renderer.icon.iconType == 251) return NO;
    return %orig;
}
%end

%hook YTDefaultSheetController
- (void)addAction:(YTActionSheetAction *)action {
    NSString *identifier = [action valueForKey:@"_accessibilityIdentifier"];
    NSDictionary *actionsToRemove = @{
        @"7":  @(ytpBool(@"removeDownloadMenu")),
        @"1":  @(ytpBool(@"removeWatchLaterMenu")),
        @"3":  @(ytpBool(@"removeSaveToPlaylistMenu")),
        @"5":  @(ytpBool(@"removeShareMenu")),
        @"12": @(ytpBool(@"removeNotInterestedMenu")),
        @"31": @(ytpBool(@"removeDontRecommendMenu")),
        @"58": @(ytpBool(@"removeReportMenu"))
    };
    if (![actionsToRemove[identifier] boolValue]) %orig;
}
%end

// ─── Hide Player Action Buttons ───────────────────────────────────────────────

static BOOL findCell(ASNodeController *nodeController, NSArray *identifiers) {
    for (id child in [nodeController children]) {
        if ([child isKindOfClass:%c(ELMNodeController)]) {
            for (ELMComponent *elmChild in [(ELMNodeController *)child children]) {
                for (NSString *identifier in identifiers) {
                    if ([[elmChild description] containsString:identifier]) return YES;
                }
            }
        }
        if ([child isKindOfClass:%c(ASNodeController)]) {
            ASDisplayNode *childNode = ((ASNodeController *)child).node;
            for (ASDisplayNode *dn in childNode.yogaChildren) {
                if ([identifiers containsObject:dn.accessibilityIdentifier]) return YES;
            }
            return findCell(child, identifiers);
        }
        return NO;
    }
    return NO;
}

%hook ASCollectionView
- (CGSize)sizeForElement:(ASCollectionElement *)element {
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"]) {
        ASCellNode *node = [element node];
        ASNodeController *nodeController = [node controller];
        if (ytpBool(@"noPlayerRemixButton") && findCell(nodeController, @[@"id.video.remix.button"])) return CGSizeZero;
        if (ytpBool(@"noPlayerClipButton") && findCell(nodeController, @[@"clip_button.eml"])) return CGSizeZero;
        if (ytpBool(@"noPlayerDownloadButton") && findCell(nodeController, @[@"id.ui.add_to.offline.button"])) return CGSizeZero;
    }
    if (ytpBool(@"hideShorts")) {
        NSString *identifier = [[element node] accessibilityIdentifier];
        if ([identifier isEqualToString:@"eml.shorts-grid"] || [identifier isEqualToString:@"eml.shorts-shelf"]) return CGSizeZero;
    }
    return %orig;
}
%end

// ─── Feed Cell Filtering ──────────────────────────────────────────────────────
// Filters at the renderer/data level (uYouEnhanced approach) so cells are never
// created for filtered content — no blank slots, no lazy-load scroll issues.

// Ad keyword check (same as YTPlus ad filter logic)
static BOOL isAdDescription(NSString *desc) {
    if (!desc) return NO;
    NSArray *adKeywords = @[
        @"ad_badge", @"ad_slot", @"adunit", @"banner_ad",
        @"interstitial", @"promoted_sparkles", @"ad_info_dialog",
        @"ad_impression", @"ads_control", @"brand_safety",
        @"companion_slot", @"google_ad", @"paid_product_placement",
        @"primetime_ad", @"survey_", @"ad_action_interstitial",
        @"ad_text_overlay"
    ];
    for (NSString *kw in adKeywords) {
        if ([desc containsString:kw]) return YES;
    }
    return NO;
}

// Filter sections before cells are created — runs at data pipeline level
%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    if (ytpBool(@"noAds") || ytpBool(@"hideShorts") || ytpBool(@"noContinueWatching")) {
        NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
        if (sectionRenderers) {
            NSIndexSet *removeIdx = [sectionRenderers indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                NSString *desc = [obj description];
                if (ytpBool(@"noAds") && isAdDescription(desc)) return YES;
                if (ytpBool(@"hideShorts") && ([desc containsString:@"shorts_shelf"] || [desc containsString:@"shorts_grid"])) return YES;
                if (ytpBool(@"noContinueWatching") && [desc containsString:@"horizontal_card_list"]) return YES;
                return NO;
            }];
            [sectionRenderers removeObjectsAtIndexes:removeIdx];
            [self setValue:sectionRenderers forKey:@"_sectionRenderers"];
        }
    }
    %orig;
}
- (void)addSectionsFromArray:(NSArray *)array {
    if (ytpBool(@"noAds") || ytpBool(@"hideShorts") || ytpBool(@"noContinueWatching")) {
        NSMutableArray *filtered = [array mutableCopy];
        NSIndexSet *removeIdx = [filtered indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            NSString *desc = [obj description];
            if (ytpBool(@"noAds") && isAdDescription(desc)) return YES;
            if (ytpBool(@"hideShorts") && ([desc containsString:@"shorts_shelf"] || [desc containsString:@"shorts_grid"])) return YES;
            if (ytpBool(@"noContinueWatching") && [desc containsString:@"horizontal_card_list"]) return YES;
            return NO;
        }];
        [filtered removeObjectsAtIndexes:removeIdx];
        %orig(filtered);
        return;
    }
    %orig;
}
%end


// ─── Shorts Progress Bar ──────────────────────────────────────────────────────

%hook YTReelPlayerViewController
- (BOOL)shouldEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldAlwaysEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytpBool(@"shortsProgress") ? NO : YES; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldAlwaysEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytpBool(@"shortsProgress") ? NO : YES; }
%end

%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytpBool(@"shortsProgress") ? NO : YES; }
%end

// ─── Shorts Startup ───────────────────────────────────────────────────────────

%hook YTShortsStartupCoordinator
- (id)evaluateResumeToShorts { return ytpBool(@"resumeShorts") ? nil : %orig; }
%end

// ─── Hide Shorts Elements ─────────────────────────────────────────────────────

%hook YTReelPausedStateCarouselView
- (void)setPausedStateCarouselVisible:(BOOL)arg1 animated:(BOOL)arg2 { ytpBool(@"hideShortsSubscriptions") ? %orig(NO, arg2) : %orig; }
%end

%hook YTReelWatchPlaybackOverlayView
- (void)setReelLikeButton:(id)arg1 { if (!ytpBool(@"hideShortsLike")) %orig; }
- (void)setReelDislikeButton:(id)arg1 { if (!ytpBool(@"hideShortsDislike")) %orig; }
- (void)setViewCommentButton:(id)arg1 { if (!ytpBool(@"hideShortsComments")) %orig; }
- (void)setRemixButton:(id)arg1 { if (!ytpBool(@"hideShortsRemix")) %orig; }
- (void)setShareButton:(id)arg1 { if (!ytpBool(@"hideShortsShare")) %orig; }
- (void)setNativePivotButton:(id)arg1 { if (!ytpBool(@"hideShortsAvatars")) %orig; }
- (void)setPivotButtonElementRenderer:(id)arg1 { if (!ytpBool(@"hideShortsAvatars")) %orig; }
%end

%hook YTReelHeaderView
- (void)setTitleLabelVisible:(BOOL)arg1 animated:(BOOL)arg2 { ytpBool(@"hideShortsLogo") ? %orig(NO, arg2) : %orig; }
%end

%hook YTReelTransparentStackView
- (void)layoutSubviews {
    %orig;
    for (YTQTMButton *button in self.subviews) {
        if ([button respondsToSelector:@selector(buttonRenderer)]) {
            if (ytpBool(@"hideShortsSearch") && button.buttonRenderer.icon.iconType == 1045) button.hidden = YES;
            if (ytpBool(@"hideShortsCamera") && button.buttonRenderer.icon.iconType == 1046) button.hidden = YES;
            if (ytpBool(@"hideShortsMore") && button.buttonRenderer.icon.iconType == 1047) button.hidden = YES;
        }
    }
}
%end

%hook YTReelWatchHeaderView
- (void)setChannelBarElementRenderer:(id)renderer { if (!ytpBool(@"hideShortsChannelName")) %orig; }
- (void)setHeaderRenderer:(id)renderer { if (!ytpBool(@"hideShortsDescription")) %orig; }
- (void)setShortsVideoTitleElementRenderer:(id)renderer { if (!ytpBool(@"hideShortsDescription")) %orig; }
- (void)setSoundMetadataElementRenderer:(id)renderer { if (!ytpBool(@"hideShortsAudioTrack")) %orig; }
- (void)setActionElement:(id)renderer { if (!ytpBool(@"hideShortsPromoCards")) %orig; }
- (void)setBadgeRenderer:(id)renderer { if (!ytpBool(@"hideShortsThanks")) %orig; }
- (void)setMultiFormatLinkElementRenderer:(id)renderer { if (!ytpBool(@"hideShortsSource")) %orig; }
%end

// ─── Pinch to Fullscreen (Shorts) ────────────────────────────────────────────

static BOOL isOverlayShown = YES;

%hook YTPlayerView
- (void)didPinch:(UIPinchGestureRecognizer *)gesture {
    %orig;
    if (ytpBool(@"pinchToFullscreenShorts") && [self.playerViewDelegate.parentViewController isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")]) {
        YTShortsPlayerViewController *shortsVC = (YTShortsPlayerViewController *)self.playerViewDelegate.parentViewController;
        YTReelContentView *contentView = (YTReelContentView *)shortsVC.view;
        UIWindow *mainWindow = [[[UIApplication sharedApplication] delegate] window];
        YTAppViewController *appVC = (YTAppViewController *)mainWindow.rootViewController;

        if (gesture.scale > 1) {
            if (!ytpBool(@"shortsOnlyMode")) [appVC hidePivotBar];
            [UIView animateWithDuration:0.3 animations:^{ contentView.playbackOverlay.alpha = 0; isOverlayShown = 0; }];
        } else {
            if (!ytpBool(@"shortsOnlyMode")) [appVC showPivotBar];
            [UIView animateWithDuration:0.3 animations:^{ contentView.playbackOverlay.alpha = 1; isOverlayShown = 1; }];
        }
    }
}
%end

%hook YTReelContentView
- (void)setPlaybackView:(id)arg1 {
    %orig;
    self.playbackOverlay.alpha = isOverlayShown;

    if (ytpBool(@"shortsOnlyMode")) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(turnShortsOnlyModeOff:)];
        longPress.numberOfTouchesRequired = 2;
        longPress.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPress];
    }
}

%new
- (void)turnShortsOnlyModeOff:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        ytpSetBool(NO, @"shortsOnlyMode");
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"ShortsModeTurnedOff") firstResponder:[%c(YTUIUtils) topViewControllerForPresenting]] send];
        UIWindow *w = [[[UIApplication sharedApplication] delegate] window];
        YTAppViewController *appVC = (YTAppViewController *)w.rootViewController;
        [appVC performSelector:@selector(showPivotBar) withObject:nil afterDelay:1.0];
    }
}
%end

// ─── Image Download Helper ────────────────────────────────────────────────────

static void downloadImageFromURL(UIResponder *responder, NSURL *URL, BOOL download) {
    NSString *URLString = URL.absoluteString;
    if (ytpBool(@"fixAlbums") && [URLString hasPrefix:@"https://yt3."]) {
        URLString = [URLString stringByReplacingOccurrencesOfString:@"https://yt3." withString:@"https://yt4."];
    }
    NSURL *downloadURL = nil;
    NSRange croppedRange = [URLString rangeOfString:@"c-fcrop"];
    if (croppedRange.location != NSNotFound) {
        NSString *newURL = [URLString stringByReplacingOccurrencesOfString:[URLString substringFromIndex:croppedRange.location] withString:@"nd-v1"];
        downloadURL = [NSURL URLWithString:newURL];
    } else {
        downloadURL = URL;
    }
    [[NSURLSession.sharedSession dataTaskWithURL:downloadURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            if (download) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                    [req addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
                } completionHandler:^(BOOL success, NSError *err) {
                    [[%c(YTToastResponderEvent) eventWithMessage:success ? LOC(@"Saved") : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), err.localizedDescription] firstResponder:responder] send];
                }];
            } else {
                [UIPasteboard generalPasteboard].image = [UIImage imageWithData:data];
                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:responder] send];
            }
        } else {
            [[%c(YTToastResponderEvent) eventWithMessage:[NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), error.localizedDescription] firstResponder:responder] send];
        }
    }] resume];
}

static void genImageFromLayer(CALayer *layer, UIColor *bgColor, void (^completion)(UIImage *)) {
    UIGraphicsBeginImageContextWithOptions(layer.frame.size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, bgColor.CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, layer.frame.size.width, layer.frame.size.height));
    [layer renderInContext:ctx];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (completion) completion(img);
}

// ─── Comment/Post Text Storage ────────────────────────────────────────────────

%hook ELMContainerNode
%property (nonatomic, strong) NSString *copiedComment;
%property (nonatomic, strong) NSURL *copiedURL;
%end

%hook ASDisplayNode
- (void)setFrame:(CGRect)frame {
    %orig;

    if (ytpBool(@"commentManager") && [[self valueForKey:@"_accessibilityIdentifier"] isEqualToString:@"id.comment.content.label"]) {
        if ([self isKindOfClass:NSClassFromString(@"ASTextNode")]) {
            ASTextNode *textNode = (ASTextNode *)self;
            NSString *comment = textNode.attributedText ? textNode.attributedText.string : nil;
            for (ELMContainerNode *node in self.supernodes.allObjects) {
                if ([node.description containsString:@"id.ui.comment_cell"] && comment) {
                    node.copiedComment = comment; break;
                }
            }
        }
    }

    if (ytpBool(@"postManager") && [self isKindOfClass:NSClassFromString(@"ELMExpandableTextNode")]) {
        ELMExpandableTextNode *expNode = (ELMExpandableTextNode *)self;
        if ([expNode.currentTextNode isKindOfClass:NSClassFromString(@"ASTextNode")]) {
            ASTextNode *textNode = (ASTextNode *)expNode.currentTextNode;
            NSString *text = textNode.attributedText ? textNode.attributedText.string : nil;
            for (ELMContainerNode *node in self.supernodes.allObjects) {
                if ([node.description containsString:@"id.ui.backstage.original_post"] && text) {
                    node.copiedComment = text; break;
                }
            }
        }
    }
}
%end

%hook YTImageZoomNode
- (BOOL)gestureRecognizer:(id)arg1 shouldRecognizeSimultaneouslyWithGestureRecognizer:(id)arg2 {
    BOOL loaded = [[self valueForKey:@"_didLoadImage"] boolValue];
    if (ytpBool(@"postManager") && loaded) {
        NSURL *URL = ((ASNetworkImageNode *)self).URL;
        for (ELMContainerNode *node in ((ASDisplayNode *)self).supernodes.allObjects) {
            if ([node.description containsString:@"id.ui.backstage.original_post"]) {
                node.copiedURL = URL; break;
            }
        }
    }
    return %orig;
}
%end

%hook _ASDisplayView
- (void)setKeepalive_node:(id)arg1 {
    %orig;
    NSArray *gesturesInfo = @[
        @{@"selector": @"postManager:", @"text": @"id.ui.backstage.original_post", @"key": @(ytpBool(@"postManager"))},
        @{@"selector": @"savePFP:", @"text": @"ELMImageNode-View", @"key": @(ytpBool(@"saveProfilePhoto"))},
        @{@"selector": @"commentManager:", @"text": @"id.ui.comment_cell", @"key": @(ytpBool(@"commentManager"))}
    ];
    for (NSDictionary *info in gesturesInfo) {
        if ([info[@"key"] boolValue] && [[self description] containsString:info[@"text"]]) {
            UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:NSSelectorFromString(info[@"selector"])];
            longPress.minimumPressDuration = 0.3;
            [self addGestureRecognizer:longPress];
            break;
        }
    }
}

%new
- (void)savePFP:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    ASNetworkImageNode *imgNode = (ASNetworkImageNode *)self.keepalive_node;
    NSString *urlStr = imgNode.URL.absoluteString;
    if (!urlStr) return;
    NSRange sizeRange = [urlStr rangeOfString:@"=s"];
    if (sizeRange.location == NSNotFound) return;
    NSRange dashRange = [urlStr rangeOfString:@"-" options:0 range:NSMakeRange(sizeRange.location, urlStr.length - sizeRange.location)];
    if (dashRange.location == NSNotFound) return;
    NSString *newURL = [urlStr stringByReplacingCharactersInRange:NSMakeRange(sizeRange.location + 2, dashRange.location - sizeRange.location - 2) withString:@"1024"];
    UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:newURL]]];
    if (!image) return;
    YTDefaultSheetController *sheet = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SaveProfilePicture") iconImage:YTPImageNamed(@"yt_outline_image_24pt") style:0 handler:^{
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Saved") firstResponder:self.keepalive_node.closestViewController] send];
    }]];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyProfilePicture") iconImage:YTPImageNamed(@"yt_outline_library_image_24pt") style:0 handler:^{
        [UIPasteboard generalPasteboard].image = image;
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:self.keepalive_node.closestViewController] send];
    }]];
    [sheet presentFromViewController:self.keepalive_node.closestViewController animated:YES completion:nil];
}

%new
- (void)postManager:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    ELMContainerNode *containerNode = (ELMContainerNode *)self.keepalive_node;
    ELMContainerNode *nodeForLayer = (ELMContainerNode *)self.keepalive_node.yogaChildren[0];
    NSString *text = containerNode.copiedComment;
    NSURL *URL = containerNode.copiedURL;
    CALayer *layer = nodeForLayer.layer;
    UIColor *bg = containerNode.closestViewController.view.backgroundColor;
    YTDefaultSheetController *sheet = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyPostText") iconImage:YTPImageNamed(@"yt_outline_message_bubble_right_24pt") style:0 handler:^{
        if (text) { [UIPasteboard generalPasteboard].string = text; [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send]; }
    }]];
    if (URL) {
        [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SaveCurrentImage") iconImage:YTPImageNamed(@"yt_outline_image_24pt") style:0 handler:^{ downloadImageFromURL(containerNode.closestViewController, URL, YES); }]];
        [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyCurrentImage") iconImage:YTPImageNamed(@"yt_outline_library_image_24pt") style:0 handler:^{ downloadImageFromURL(containerNode.closestViewController, URL, NO); }]];
    }
    UIColor *accent = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SavePostAsImage") titleColor:accent iconImage:YTPImageNamed(@"yt_outline_image_24pt") iconColor:accent disableAutomaticButtonColor:YES accessibilityIdentifier:nil handler:^{
        genImageFromLayer(layer, bg, ^(UIImage *img) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{ PHAssetCreationRequest *r = [PHAssetCreationRequest creationRequestForAssetFromImage:img]; r.creationDate = [NSDate date]; } completionHandler:^(BOOL success, NSError *err) {
                [[%c(YTToastResponderEvent) eventWithMessage:success ? LOC(@"Saved") : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), err.localizedDescription] firstResponder:containerNode.closestViewController] send];
            }];
        });
    }]];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyPostAsImage") titleColor:accent iconImage:YTPImageNamed(@"yt_outline_library_image_24pt") iconColor:accent disableAutomaticButtonColor:YES accessibilityIdentifier:nil handler:^{
        genImageFromLayer(layer, bg, ^(UIImage *img) { [UIPasteboard generalPasteboard].image = img; [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send]; });
    }]];
    [sheet presentFromViewController:containerNode.closestViewController animated:YES completion:nil];
}

%new
- (void)commentManager:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    ELMContainerNode *containerNode = (ELMContainerNode *)self.keepalive_node;
    NSString *comment = containerNode.copiedComment;
    CALayer *layer = self.layer;
    UIColor *bg = containerNode.closestViewController.view.backgroundColor;
    YTDefaultSheetController *sheet = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyCommentText") iconImage:YTPImageNamed(@"yt_outline_message_bubble_right_24pt") style:0 handler:^{
        if (comment) { [UIPasteboard generalPasteboard].string = comment; [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send]; }
    }]];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SaveCommentAsImage") iconImage:YTPImageNamed(@"yt_outline_image_24pt") style:0 handler:^{
        genImageFromLayer(layer, bg, ^(UIImage *img) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{ PHAssetCreationRequest *r = [PHAssetCreationRequest creationRequestForAssetFromImage:img]; r.creationDate = [NSDate date]; } completionHandler:^(BOOL s, NSError *err) {
                [[%c(YTToastResponderEvent) eventWithMessage:s ? LOC(@"Saved") : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), err.localizedDescription] firstResponder:containerNode.closestViewController] send];
            }];
        });
    }]];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyCommentAsImage") iconImage:YTPImageNamed(@"yt_outline_library_image_24pt") style:0 handler:^{
        genImageFromLayer(layer, bg, ^(UIImage *img) { [UIPasteboard generalPasteboard].image = img; [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send]; });
    }]];
    [sheet presentFromViewController:containerNode.closestViewController animated:YES completion:nil];
}
%end

// ─── Tab Bar ──────────────────────────────────────────────────────────────────

%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    NSMutableArray *items = [renderer itemsArray];

    NSDictionary *toRemove = @{
        @"FEshorts":        @[@(ytpBool(@"removeShorts")), @(ytpBool(@"reExplore"))],
        @"FEsubscriptions": @[@(ytpBool(@"removeSubscriptions"))],
        @"FEuploads":       @[@(ytpBool(@"removeUploads"))],
        @"FElibrary":       @[@(ytpBool(@"removeLibrary"))]
    };

    for (NSString *identifier in toRemove) {
        NSArray *values = toRemove[identifier];
        BOOL shouldRemove = [values containsObject:@YES];
        NSUInteger idx = [items indexOfObjectPassingTest:^BOOL(YTIPivotBarSupportedRenderers *r, NSUInteger i, BOOL *stop) {
            if ([identifier isEqualToString:@"FEuploads"])
                return shouldRemove && [[[r pivotBarIconOnlyItemRenderer] pivotIdentifier] isEqualToString:identifier];
            else
                return shouldRemove && [[[r pivotBarItemRenderer] pivotIdentifier] isEqualToString:identifier];
        }];
        if (idx != NSNotFound) [items removeObjectAtIndex:idx];
    }

    NSUInteger exploreIdx = [items indexOfObjectPassingTest:^BOOL(YTIPivotBarSupportedRenderers *r, NSUInteger i, BOOL *stop) {
        return [[[r pivotBarItemRenderer] pivotIdentifier] isEqualToString:[%c(YTIBrowseRequest) browseIDForExploreTab]];
    }];

    if (exploreIdx == NSNotFound && (ytpBool(@"reExplore") || ytpBool(@"addExplore"))) {
        YTIPivotBarSupportedRenderers *exploreTab = [%c(YTIPivotBarRenderer) pivotSupportedRenderersWithBrowseId:[%c(YTIBrowseRequest) browseIDForExploreTab] title:LOC(@"Explore") iconType:292];
        [items insertObject:exploreTab atIndex:1];
    }

    %orig;
}
%end

%hook YTPivotBarIndicatorView
- (void)setFillColor:(id)arg1 { %orig(ytpBool(@"removeIndicators") ? [UIColor clearColor] : arg1); }
- (void)setBorderColor:(id)arg1 { %orig(ytpBool(@"removeIndicators") ? [UIColor clearColor] : arg1); }
%end

%hook YTPivotBarItemView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    %orig;
    if (ytpBool(@"removeLabels")) {
        [self.navigationButton setTitle:@"" forState:UIControlStateNormal];
        [self.navigationButton setSizeWithPaddingAndInsets:NO];
    }
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(manageTab:)];
    longPress.minimumPressDuration = 0.3;
    if ([self.renderer.pivotIdentifier isEqualToString:@"FEwhat_to_watch"]) [self addGestureRecognizer:longPress];
}

%new
- (void)manageTab:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        ytpBool(@"removeLibrary") ? ytpSetBool(NO, @"removeLibrary") : ytpSetBool(YES, @"removeLibrary");
        [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
        [[%c(YTToastResponderEvent) eventWithMessage:ytpBool(@"removeLibrary") ? LOC(@"LibraryRemoved") : LOC(@"LibraryAdded") firstResponder:self.delegate] send];
    }
}
%end

// ─── Startup Tab ──────────────────────────────────────────────────────────────

BOOL isTabSelected = NO;

%hook YTPivotBarViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isTabSelected && !ytpBool(@"shortsOnlyMode")) {
        NSArray *identifiers = @[@"FEwhat_to_watch", @"FEexplore", @"FEshorts", @"FEsubscriptions", @"FElibrary"];
        [self selectItemWithPivotIdentifier:identifiers[ytpInt(@"pivotIndex")]];
        isTabSelected = YES;
    }
    if (ytpBool(@"shortsOnlyMode")) {
        [self selectItemWithPivotIdentifier:@"FEshorts"];
        [self.parentViewController hidePivotBar];
    }

    // Welcome splash — first launch only
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (ytpBool(@"hasSeenWelcome")) return;

        // Delay so system permission dialogs (notifications etc) don't dismiss us
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ytpBool(@"hasSeenWelcome")) return;

        UIViewController *welcome = [[UIViewController alloc] init];
        welcome.modalPresentationStyle = UIModalPresentationOverFullScreen;
        welcome.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        welcome.view.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];

        UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppIcon60x60"]];
        logo.contentMode = UIViewContentModeScaleAspectFit;
        logo.layer.cornerRadius = 22;
        logo.clipsToBounds = YES;
        logo.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"YouTube Plus Revanced";
        titleLabel.font = [UIFont boldSystemFontOfSize:32];
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        NSArray *features = @[
            @[@"arrow.down.to.line", LOC(@"Welcome.Download"), LOC(@"Welcome.DownloadDesc")],
            @[@"paintbrush",         LOC(@"Welcome.Content"),  LOC(@"Welcome.ContentDesc")],
            @[@"hand.point.up.left", LOC(@"Welcome.Player"),   LOC(@"Welcome.PlayerDesc")],
            @[@"ellipsis",           LOC(@"Welcome.More"),     LOC(@"Welcome.MoreDesc")],
        ];

        UIStackView *featureStack = [[UIStackView alloc] init];
        featureStack.axis = UILayoutConstraintAxisVertical;
        featureStack.spacing = 24;
        featureStack.translatesAutoresizingMaskIntoConstraints = NO;

        for (NSArray *f in features) {
            UIStackView *row = [[UIStackView alloc] init];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 16;
            row.alignment = UIStackViewAlignmentTop;

            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:f[0]]];
            icon.tintColor = [UIColor whiteColor];
            icon.contentMode = UIViewContentModeScaleAspectFit;
            icon.translatesAutoresizingMaskIntoConstraints = NO;
            [icon.widthAnchor constraintEqualToConstant:32].active = YES;
            [icon.heightAnchor constraintEqualToConstant:32].active = YES;

            UIStackView *textStack = [[UIStackView alloc] init];
            textStack.axis = UILayoutConstraintAxisVertical;
            textStack.spacing = 4;

            UILabel *featureTitle = [[UILabel alloc] init];
            featureTitle.text = f[1];
            featureTitle.font = [UIFont boldSystemFontOfSize:17];
            featureTitle.textColor = [UIColor whiteColor];
            featureTitle.numberOfLines = 0;

            UILabel *featureDesc = [[UILabel alloc] init];
            featureDesc.text = f[2];
            featureDesc.font = [UIFont systemFontOfSize:14];
            featureDesc.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
            featureDesc.numberOfLines = 0;

            [textStack addArrangedSubview:featureTitle];
            [textStack addArrangedSubview:featureDesc];
            [row addArrangedSubview:icon];
            [row addArrangedSubview:textStack];
            [featureStack addArrangedSubview:row];
        }

        UILabel *footer = [[UILabel alloc] init];
        footer.text = @"Mod by Schultzy";
        footer.font = [UIFont systemFontOfSize:14];
        footer.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        footer.textAlignment = NSTextAlignmentCenter;
        footer.translatesAutoresizingMaskIntoConstraints = NO;

        UIButton *continueBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [continueBtn setTitle:LOC(@"Continue") forState:UIControlStateNormal];
        continueBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        continueBtn.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
        continueBtn.tintColor = [UIColor whiteColor];
        continueBtn.layer.cornerRadius = 14;
        continueBtn.translatesAutoresizingMaskIntoConstraints = NO;

        UIViewController *__weak weakWelcome = welcome;
        [continueBtn addAction:[UIAction actionWithTitle:@"" image:nil identifier:nil handler:^(__kindof UIAction *action) {
            ytpSetBool(YES, @"hasSeenWelcome");
            [weakWelcome dismissViewControllerAnimated:YES completion:nil];
        }] forControlEvents:UIControlEventTouchUpInside];

        [welcome.view addSubview:logo];
        [welcome.view addSubview:titleLabel];
        [welcome.view addSubview:featureStack];
        [welcome.view addSubview:footer];
        [welcome.view addSubview:continueBtn];

        UIView *v = welcome.view;
        [NSLayoutConstraint activateConstraints:@[
            [logo.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor constant:40],
            [logo.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
            [logo.widthAnchor constraintEqualToConstant:90],
            [logo.heightAnchor constraintEqualToConstant:90],

            [titleLabel.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:16],
            [titleLabel.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
            [titleLabel.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],

            [featureStack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:32],
            [featureStack.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:28],
            [featureStack.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-28],

            [footer.bottomAnchor constraintEqualToAnchor:continueBtn.topAnchor constant:-16],
            [footer.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
            [footer.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],

            [continueBtn.bottomAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.bottomAnchor constant:-24],
            [continueBtn.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
            [continueBtn.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],
            [continueBtn.heightAnchor constraintEqualToConstant:56],
        ]];

        [self presentViewController:welcome animated:YES completion:nil];
        }); // end dispatch_after
    });
}
%end

%hook YTAppViewController
- (void)showPivotBar {
    if (!ytpBool(@"shortsOnlyMode")) { %orig; isOverlayShown = YES; }
}
%end

%hook YTReelWatchRootViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (ytpBool(@"shortsOnlyMode")) [self.navigationController.parentViewController hidePivotBar];
}
%end

// ─── Copy Video Info Button ───────────────────────────────────────────────────

%hook YTEngagementPanelView
- (void)layoutSubviews {
    %orig;
    if (ytpBool(@"copyVideoInfo") && [self.panelIdentifier.identifierString isEqualToString:@"video-description-ep-identifier"]) {
        if (self.headerView && ![self.headerView viewWithTag:999]) {
            YTQTMButton *btn = [%c(YTQTMButton) iconButton];
            btn.accessibilityLabel = LOC(@"CopyVideoInfo");
            [btn setTag:999];
            [btn enableNewTouchFeedback];
            [btn setImage:YTPImageNamed(@"yt_outline_copy_24pt") forState:UIControlStateNormal];
            [btn setTintColor:[UIColor labelColor]];
            [btn setTranslatesAutoresizingMaskIntoConstraints:NO];
            [btn addTarget:self action:@selector(didTapCopyInfoButton:) forControlEvents:UIControlEventTouchUpInside];
            [self.headerView addSubview:btn];
            [NSLayoutConstraint activateConstraints:@[
                [btn.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-48],
                [btn.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
                [btn.widthAnchor constraintEqualToConstant:40],
                [btn.heightAnchor constraintEqualToConstant:40]
            ]];
        }
    }
}

%new
- (void)didTapCopyInfoButton:(UIButton *)sender {
    YTPlayerViewController *playerVC = self.resizeDelegate.parentViewController.parentViewController.parentViewController.playerViewController;
    NSString *title = playerVC.playerResponse.playerData.videoDetails.title;
    NSString *desc = playerVC.playerResponse.playerData.videoDetails.shortDescription;
    YTDefaultSheetController *sheet = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyTitle") iconImage:YTPImageNamed(@"yt_outline_text_box_24pt") style:0 handler:^{
        [UIPasteboard generalPasteboard].string = title;
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:self.resizeDelegate] send];
    }]];
    [sheet addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyDescription") iconImage:YTPImageNamed(@"yt_outline_message_bubble_right_24pt") style:0 handler:^{
        [UIPasteboard generalPasteboard].string = desc;
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:self.resizeDelegate] send];
    }]];
    [sheet presentFromViewController:self.resizeDelegate animated:YES completion:nil];
}
%end

// ─── Speedmaster (hold-to-speed) ──────────────────────────────────────────────

static CGFloat rateBeforeSpeedmaster = 1.0;

static void manageSpeedmaster(UILongPressGestureRecognizer *gesture, YTMainAppVideoPlayerOverlayViewController *delegate, YTInlinePlayerScrubUserEducationView *edu) {
    NSArray *speeds = @[@0, @2.0, @0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @3.0, @4.0, @5.0];
    YTLabel *label = [edu valueForKey:@"_userEducationLabel"];
    edu.labelType = 1;
    [label setValue:[NSString stringWithFormat:@"%@: %@×", LOC(@"PlaybackSpeed"), speeds[ytpInt(@"speedIndex")]] forKey:@"text"];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        rateBeforeSpeedmaster = delegate.currentPlaybackRate;
        [delegate setPlaybackRate:[speeds[ytpInt(@"speedIndex")] floatValue]];
        [edu setVisible:YES];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        [delegate setPlaybackRate:rateBeforeSpeedmaster];
        [edu setVisible:NO];
    }
}

%hook YTMainAppVideoPlayerOverlayView
- (void)setSeekAnywherePanGestureRecognizer:(id)arg1 {
    if (ytpInt(@"speedIndex") == 0) return %orig;
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(speedmasterYtPlus:)];
    longPress.minimumPressDuration = 0.3;
    [self addGestureRecognizer:longPress];
}

%new
- (void)speedmasterYtPlus:(UILongPressGestureRecognizer *)gesture {
    manageSpeedmaster(gesture, self.delegate, self.scrubUserEducationView);
}
%end

%hook YTSpeedmasterController
- (void)speedmasterDidLongPressWithRecognizer:(UILongPressGestureRecognizer *)gesture {
    if (ytpInt(@"speedIndex") == 0) return;
    if (ytpInt(@"speedIndex") == 1) return %orig;
    YTMainAppVideoPlayerOverlayViewController *delegate = [self valueForKey:@"_delegate"];
    YTInlinePlayerScrubUserEducationView *edu = (YTInlinePlayerScrubUserEducationView *)delegate.videoPlayerOverlayView.scrubUserEducationView;
    manageSpeedmaster(gesture, delegate, edu);
}
%end

// ─── Disable RTL ──────────────────────────────────────────────────────────────

%hook NSParagraphStyle
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(id)lang { return ytpBool(@"disableRTL") ? NSWritingDirectionLeftToRight : %orig; }
+ (NSWritingDirection)_defaultWritingDirection { return ytpBool(@"disableRTL") ? NSWritingDirectionLeftToRight : %orig; }
%end

// ─── Fix Album Covers (Russia/CDN fix) ───────────────────────────────────────

static NSURL *fixedCoverURL(NSURL *originalURL) {
    NSDictionary *hostsToReplace = @{
        @"yt3.ggpht.com": @"yt4.ggpht.com",
        @"yt3.googleusercontent.com": @"yt4.googleusercontent.com"
    };
    NSString *replacement = hostsToReplace[originalURL.host];
    if (ytpBool(@"fixAlbums") && replacement) {
        NSURLComponents *comp = [NSURLComponents componentsWithURL:originalURL resolvingAgainstBaseURL:NO];
        comp.host = replacement;
        return comp.URL;
    }
    return originalURL;
}

%hook YTImageSelectionStrategyImageURLs
- (id)initWithSelectedImageURL:(NSURL *)selected updatedImageURL:(NSURL *)updated {
    return %orig(fixedCoverURL(selected), fixedCoverURL(updated));
}
%end


// ─── Constructor ──────────────────────────────────────────────────────────────

%ctor {
    // Conflict guard: shorts-only mode can't coexist with removing/replacing shorts tab
    if (ytpBool(@"shortsOnlyMode") && (ytpBool(@"removeShorts") || ytpBool(@"reExplore"))) {
        ytpSetBool(NO, @"removeShorts");
        ytpSetBool(NO, @"reExplore");
    }
    // Clear cache on startup if enabled
    if (ytpBool(@"clearCacheOnStartup")) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
            [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
        });
    }
    %init;
}
