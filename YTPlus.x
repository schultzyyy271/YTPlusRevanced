// YTPlus.x
// Rebuilt from YTLite open-source by the community.
// Updated for YouTube 21.16.2 (iOS 16+).
// Mod by Schultzy — built on YTLite open-source base.
#include <dlfcn.h>
#import <objc/message.h>

#import "YTPlus.h"

// ─── Helpers ──────────────────────────────────────────────────────────────────

static UIImage *YTPImageNamed(NSString *imageName) {
    return [UIImage imageNamed:imageName inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
}

// ─── Shorts to Regular Video Helper ──────────────────────────────────────────
// Uses YouTube's internal protobuf command system (YTICommand + YTCommandResponderEvent)
// instead of URL schemes. This works on sideloaded apps regardless of bundle ID.
// Reverse-engineered from YTLite's YTPPlayerHelper.openVideoWithID implementation.

static void openVideoAsRegular(NSString *videoID, UIView *sourceView, id firstResponder) {
    if (!videoID || videoID.length == 0) return;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    // Get the root view controller's view as source if none provided
    if (!sourceView) {
        sourceView = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    }

    // Method 1: Feed a watch URL directly into YTAppDelegate's URL handler
    // This routes through YouTube's internal navigation, not the OS URL scheme
    id appDelegate = [UIApplication sharedApplication].delegate;
    NSString *watchURLString = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", videoID];
    NSURL *watchURL = [NSURL URLWithString:watchURLString];

    // Try application:openURL:options: (iOS 9+)
    SEL openSel = @selector(application:openURL:options:);
    if ([appDelegate respondsToSelector:openSel]) {
        BOOL result = ((BOOL (*)(id, SEL, id, id, id))objc_msgSend)(
            appDelegate, openSel,
            [UIApplication sharedApplication], watchURL, @{}
        );
        if (result) return;
    }

    // Try application:openURL:sourceApplication:annotation:
    SEL openSel2 = @selector(application:openURL:sourceApplication:annotation:);
    if ([appDelegate respondsToSelector:openSel2]) {
        ((BOOL (*)(id, SEL, id, id, id, id))objc_msgSend)(
            appDelegate, openSel2,
            [UIApplication sharedApplication], watchURL, @"com.apple.mobilesafari", [NSNull null]
        );
        return;
    }

    // Method 2: Use YTICommand protobuf navigation with the source view
    Class YTICommandClass = NSClassFromString(@"YTICommand");
    Class YTCommandResponderEventClass = NSClassFromString(@"YTCommandResponderEvent");

    if (YTICommandClass && YTCommandResponderEventClass) {
        SEL watchSel = @selector(watchNavigationEndpointWithVideoID:);
        if ([YTICommandClass respondsToSelector:watchSel]) {
            id command = [YTICommandClass performSelector:watchSel withObject:videoID];
            if (command) {
                SEL eventSel = @selector(eventWithCommand:fromView:entry:sendClick:firstResponder:);
                if ([YTCommandResponderEventClass respondsToSelector:eventSel]) {
                    NSMethodSignature *sig = [YTCommandResponderEventClass methodSignatureForSelector:eventSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:YTCommandResponderEventClass];
                    [inv setSelector:eventSel];
                    [inv setArgument:&command atIndex:2];
                    [inv setArgument:&sourceView atIndex:3];
                    id nilEntry = nil;
                    [inv setArgument:&nilEntry atIndex:4];
                    BOOL sendClick = YES;
                    [inv setArgument:&sendClick atIndex:5];
                    id nilResponder = nil;
                    [inv setArgument:&nilResponder atIndex:6];
                    [inv invoke];
                    
                    __unsafe_unretained id event = nil;
                    [inv getReturnValue:&event];
                    if (event && [event respondsToSelector:@selector(send)]) {
                        [event performSelector:@selector(send)];
                        return;
                    }
                }
            }
        }
    }

    // Method 3: Last resort — open externally
    [[UIApplication sharedApplication] openURL:watchURL options:@{} completionHandler:nil];
#pragma clang diagnostic pop
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

%hook YTPlayerResponse
%new
- (NSMutableArray *)playerAdsArray { return [NSMutableArray array]; }
%new
- (NSMutableArray *)adSlotsArray { return [NSMutableArray array]; }
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



// ─── Block Shorts / Reel Promoted Ads ────────────────────────────────────────
// YouTube 21.16.2 delivers promoted reels through a dedicated shorts ads system
// that bypasses the regular ad pipeline. These hooks disable it at multiple levels.

// Level 1: Hide the ad overlay
%hook YTReelAdsOverlayView
- (void)setHidden:(BOOL)hidden {
    if (ytpBool(@"noAds")) { %orig(YES); return; }
    %orig;
}
- (void)layoutSubviews {
    if (ytpBool(@"noAds")) { ((UIView *)self).hidden = YES; return; }
    %orig;
}
%end

// Level 2: Block ad model properties — tell YouTube the reel is not an ad
%hook YTReelModel
- (BOOL)isAd {
    if (ytpBool(@"noAds")) return NO;
    return %orig;
}
%end

// Level 3: Block ad showing state on the playback overlay
%hook YTReelWatchPlaybackOverlayView
- (BOOL)isAdShowing {
    if (ytpBool(@"noAds")) return NO;
    return %orig;
}
- (void)setAdShowing:(BOOL)showing {
    if (ytpBool(@"noAds")) { %orig(NO); return; }
    %orig;
}
// ─── Shorts to Regular Video Button ──────────────────────────────────────────
- (void)layoutSubviews {
    %orig;
}

// ─── Hide Shorts Buttons (merged from duplicate hook) ────────────────────────
- (void)setShareButton:(id)arg1 { if (!ytpBool(@"hideShortsShare")) %orig; }
%end

// Level 4: Block the ad fetch pipeline for reels
%hook YTReelAdsAPIImpl
- (void)fetchAdWithURL:(id)url responseBlock:(id)response errorBlock:(id)error {
    if (ytpBool(@"noAds")) return;
    %orig;
}
%end

%hook YTReelAdsAPIV1Impl
- (void)fetchAdWithURL:(id)url responseBlock:(id)response errorBlock:(id)error {
    if (ytpBool(@"noAds")) return;
    %orig;
}
%end

%hook YTReelAdsAPIV2Impl
- (void)fetchAdWithURL:(id)url responseBlock:(id)response errorBlock:(id)error {
    if (ytpBool(@"noAds")) return;
    %orig;
}
%end

// Level 5: Block ad break fetching
%hook YTReelAdsPresenterManager
- (void)fetchAdBreaksWithVideoID:(id)videoID responseBlock:(id)response errorBlock:(id)error {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (void)fetchAdDataWithURL:(id)url responseBlock:(id)response errorBlock:(id)error {
    if (ytpBool(@"noAds")) return;
    %orig;
}
%end

// Level 6: Additional config flags — merged into main YTColdConfig block below

// Level 7: Filter promoted reels from the data source (from YouMod)
// videoType == 3 means the reel is an ad — return nil to skip it entirely
%hook YTReelDataSource
- (id)makeContentModelForEntry:(id)entry {
    id model = %orig;
    if (ytpBool(@"noAds") && [model respondsToSelector:@selector(videoType)] && ((NSInteger)[model performSelector:@selector(videoType)]) == 3)
        return nil;
    return model;
}
- (void)setReels:(NSMutableOrderedSet *)reels {
    if (ytpBool(@"noAds")) {
        [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj respondsToSelector:@selector(videoType)] ? ((NSInteger)[obj performSelector:@selector(videoType)]) == 3 : NO;
        }]];
    }
    %orig;
}
%end

// Level 8: Kill the ads playback coordinator entirely
%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return ytpBool(@"noAds") ? nil : %orig; }
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

// ─── Ported from YouMod — additional ad/promo blocking ──────────────────────

%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTIClientMdxGlobalConfig
%new
- (BOOL)enableSkippableAd { return YES; }
%end

%hook MDXFeatureFlags
- (BOOL)areMementoPromotionsEnabled { return NO; }
%end

%hook MDXSession
- (void)adPlaying:(id)ad {}
%end

%hook MDXSessionImpl
- (void)adPlaying:(id)ad {}
%end

%hook YTAppMealbarPromoController
- (id)mealbarPromoController { return nil; }
%end

%hook YTAppMealbarPromoControllerImpl
- (id)mealbarPromoController { return nil; }
%end

%hook YTMealbarPromoController
- (id)promoRenderer { return nil; }
- (void)showMealbarPromoWithEvent:(id)arg {}
%end

%hook YTPromoThrottleControllerImpl
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTPromosheetContainerView
- (BOOL)shouldShowExpandButton { return NO; }
- (void)setPromosheet:(id)arg {}
- (void)setPromosheetDisplayed:(BOOL)arg {}
- (void)setPromosheet:(id)arg1 animated:(BOOL)arg2 completion:(id)arg3 {}
%end

%hook YTPromosheetController
- (BOOL)canPresentPromosheetWithGlobalThrottling:(BOOL)arg1 customizedThrottling:(id)arg2 shouldReplacePromosheet:(BOOL)arg3 { return NO; }
- (void)setCurrentPromosheet:(id)arg {}
%end

%hook YTSPromotionServiceBlockImpl
- (BOOL)createPromotion:(id)arg1 writer:(id)arg2 error:(NSError **)arg3 { return NO; }
%end

%hook YTShareMainView
- (BOOL)shouldShowPromo { return NO; }
- (void)setPromoView:(id)arg {}
%end

%hook YTSurveyPromosheet
- (id)expandablePromosheetDelegate { return nil; }
- (void)setExpandablePromosheetDelegate:(id)arg {}
%end

%hook YTWatchSurveyTriggerController
- (id)initWithParentResponder:(id)arg1 promosheetController:(id)arg2 { return nil; }
%end

%hook YTVideoSubtitleView
- (BOOL)shouldShowAdBadge { return NO; }
%end

%hook YTOfflineButtonPromoController
- (void)showOfflinePromoWithRenderer:(id)arg1 endpoint:(id)arg2 parentResponder:(id)arg3 {}
%end

%hook YTOfflineButtonPromoView
- (id)initWithFrame:(CGRect)arg1 renderer:(id)arg2 attributedView:(id)arg3 formattedStringLabelDelegate:(id)arg4 offlineButtonPromoDelegate:(id)arg5 { return nil; }
%end

%hook YTWatchMiniBarControlsView
- (void)setTitle:(id)arg1 byline:(id)arg2 showingPaidPromotion:(BOOL)arg3 showingPremiumBadge:(BOOL)arg4 {}
%end

%hook ELMPBShowBottomSheetCommand
- (void)showMealbarPromoWithContainerView:(id)arg1 handler:(id)arg2 {}
%end

%hook YTWatchNextResponseViewController
- (void)loadWithModel:(id)model {
    if (ytpBool(@"noAds") && [model respondsToSelector:@selector(onUiReady)]) {
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id onUiReady = [model performSelector:@selector(onUiReady)];
            if (onUiReady && [onUiReady respondsToSelector:NSSelectorFromString(@"yt_commandExecutorCommand")]) {
                id cmdExec = [onUiReady performSelector:NSSelectorFromString(@"yt_commandExecutorCommand")];
                if (cmdExec && [cmdExec respondsToSelector:@selector(commandsArray)]) {
                    NSMutableArray *cmds = [cmdExec performSelector:@selector(commandsArray)];
                    NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
                    [cmds enumerateObjectsUsingBlock:^(id command, NSUInteger idx, BOOL *stop) {
                        if ([command respondsToSelector:NSSelectorFromString(@"yt_showEngagementPanelEndpoint")]) {
                            id ep = [command performSelector:NSSelectorFromString(@"yt_showEngagementPanelEndpoint")];
                            if (ep && [ep respondsToSelector:@selector(identifier)]) {
                                id ident = [ep performSelector:@selector(identifier)];
                                if (ident && [ident respondsToSelector:@selector(tag)]) {
                                    id tag = [ident performSelector:@selector(tag)];
                                    if ([tag isKindOfClass:[NSString class]] && [tag isEqualToString:@"PAproduct_list"])
                                        [toRemove addIndex:idx];
                                }
                            }
                        }
                    }];
                    [cmds removeObjectsAtIndexes:toRemove];
                }
            }
#pragma clang diagnostic pop
        } @catch (NSException *e) {}
    }
    %orig;
}
%end

%hook YCHLiveChatActionPanelView
- (BOOL)shouldShowUpsellButton { return NO; }
%end

%hook YTIPlayerCompanionAdsSupportedRenderers
- (BOOL)hasAppPromoCompanionAdRenderer { return NO; }
%end

%hook YTIRenderer
- (id)appPromoAdCtaRenderer { return nil; }
- (BOOL)hasAppPromoAdCtaRenderer { return NO; }
%end

%hook YTIInStreamPlayerCtaAdsSupportedRenderers
- (BOOL)hasAppPromoAdCtaRenderer { return NO; }
%end

%hook YTInterstitialPromoViewController
- (void)showInterstitialPromo:(id)arg1 enableClientImpressionThrottling:(BOOL)arg2 interstitialParentResponder:(id)arg3 {}
- (void)showInterstitialPromo:(id)arg1 interstitialParentResponder:(id)arg2 {}
%end

%hook YTUserDefaults
- (BOOL)enablePromoDebugToast { return NO; }
- (BOOL)isPromoForced { return NO; }
%end

// Hide AI montage buttons on shorts
%hook YTShortsSharedGalleryPresentationView
- (BOOL)shouldShowAiMontageButton { return NO; }
%end

%hook YTShortsSharedGalleryPresentationViewController
- (BOOL)shouldShowAiMontageButton { return NO; }
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
- (BOOL)videoZoomFreeZoomEnabledGlobalConfig { return ytpBool(@"noFreeZoom") ? NO : %orig; } // ❌ BROKEN: method removed in YT 21.16.2 — noFreeZoom toggle non-functional
- (BOOL)enableHideChipsInTheCommentsHeaderOnScrollIos { return ytpBool(@"stickSortComments") ? NO : %orig; }
- (BOOL)enableChipsInTheCommentsHeaderIos { return ytpBool(@"hideSortComments") ? NO : %orig; } // ❌ BROKEN: method removed in YT 21.16.2 — hideSortComments toggle non-functional
- (BOOL)shouldUseAppThemeSetting { return YES; } // ❌ BROKEN: method removed in YT 21.16.2
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; } // ❌ BROKEN: method removed in YT 21.16.2
- (BOOL)enableSwipeToRemoveInPlaylistWatchEp { return YES; }
- (BOOL)queueClientGlobalConfigEnableFloatingPlaylistMinibar { return ytpBool(@"playlistOldMinibar") ? NO : %orig; }
// Shorts config
- (BOOL)iosEnableVideoPlayerScrubber { return ytpBool(@"shortsProgress") ? YES : %orig; }
- (BOOL)mobileShortsTabInlined { return ytpBool(@"shortsProgress") ? YES : NO; } // ❌ BROKEN: method removed in YT 21.16.2 — shortsProgress partially non-functional
- (BOOL)iosUseSystemVolumeControlInFullscreen { return ytpBool(@"stockVolumeHUD") ? YES : NO; } // ❌ BROKEN: method removed in YT 21.16.2 — stockVolumeHUD toggle non-functional
// Shorts ad blocking
- (BOOL)enableShortsAdsEndcap { return ytpBool(@"noAds") ? NO : %orig; }
- (BOOL)enableShortsAdsPlayerSide { return ytpBool(@"noAds") ? NO : %orig; }
- (BOOL)enableShortsAdsUnderlay { return ytpBool(@"noAds") ? NO : %orig; }
- (BOOL)enableShortsAdLeaveBehindClient { return ytpBool(@"noAds") ? NO : %orig; }
- (BOOL)iosEnableShortsAdsRenderingFlowRefactoring { return ytpBool(@"noAds") ? NO : %orig; }
- (BOOL)enableReelAdsScrollBlockFix { return ytpBool(@"noAds") ? NO : %orig; }
- (BOOL)shortsConsumptionClientGlobalConfigEnableBackgroundRenderingOnShortsAds { return ytpBool(@"noAds") ? NO : %orig; }
%end

%hook YTHotConfig
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return ytpBool(@"shortsProgress") ? YES : %orig; } // ❌ BROKEN: method removed in YT 21.16.2
// Shorts quality picker (from YouMod)
- (BOOL)enableOmitAdvancedMenuInShortsVideoQualityPicker { return YES; }
- (BOOL)enableShortsVideoQualityPicker { return YES; }
- (BOOL)iosEnableImmersiveLivePlayerVideoQuality { return YES; }
- (BOOL)iosEnableShortsPlayerVideoQuality { return YES; }
- (BOOL)iosEnableShortsPlayerVideoQualityRestartVideo { return YES; }
- (BOOL)iosEnableSimplerTitleInShortsVideoQualityPicker { return YES; }
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

%hook YTWatchMiniBarVisibilityController
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

%hook YTPlayabilityResolutionUserActionUIControllerImpl
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

%hook YTInlinePlayerBarView
- (void)didMoveToWindow { %orig; if (ytpBool(@"dontSnapToChapter")) self.enableSnapToChapter = NO; }
%end

// ─── Red Progress Bar ─────────────────────────────────────────────────────────

%hook YTInlinePlayerBarContainerView
- (id)quietProgressBarColor { return ytpBool(@"redProgressBar") ? [UIColor redColor] : %orig; }
%end

%hook YTInlinePlayerBarView
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
// YouTube 21.x removed the 2-arg loadWithPlayerTransition:playbackConfig: and replaced it
// with a 3-arg variant that includes initialTime. Hooking the wrong signature means Logos
// silently skips the hook and none of the deferred selectors ever fire (shortsToRegular,
// autoFullscreen, autoSpeed, autoQuality, disableAutoCaptions).
- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 initialTime:(double)initialTime {
    %orig;
    if (ytpInt(@"wiFiQualityIndex") != 0 || ytpInt(@"cellQualityIndex") != 0)
        [self performSelector:@selector(autoQuality) withObject:nil afterDelay:1.0];
    if (ytpBool(@"autoFullscreen"))
        [self performSelector:@selector(autoFullscreen) withObject:nil afterDelay:0.75];
    if (ytpInt(@"autoSpeedIndex") != 3)
        [self performSelector:@selector(setAutoSpeed) withObject:nil afterDelay:0.75];
    if (ytpBool(@"disableAutoCaptions"))
        [self performSelector:@selector(turnOffCaptions) withObject:nil afterDelay:1.0];
    // shortsToRegular is now handled via YTReelWatchPlaybackOverlayView button, not here
}

%new
- (void)autoFullscreen {
    id watchController = [self valueForKey:@"_UIDelegate"];
    if ([watchController respondsToSelector:@selector(showFullScreen)])
        [watchController performSelector:@selector(showFullScreen)];
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


// ─── Shorts Progress Bar + Doom Scrolling + Advance Blocking ─────────────────
// All confirmed via IDA Pro decompilation of YouTube 21.16.2 binary.
// reelContentViewRequestsAdvanceToNextVideo: is the KEY delegate method
// that triggers video advance — blocking it prevents scrolling to next short.

%hook YTReelPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytpBool(@"shortsProgress") ? NO : %orig; }
%end

%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return ytpBool(@"shortsProgress") ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytpBool(@"shortsProgress") ? NO : %orig; }

// Auto-open shorts as regular video (once per video ID)
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (ytpBool(@"shortsToRegular")) {
        static NSMutableSet *redirectedVideoIDs = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            redirectedVideoIDs = [NSMutableSet new];
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *videoID = nil;
            if ([self respondsToSelector:@selector(contentVideoID)])
                videoID = [(id)self performSelector:@selector(contentVideoID)];
            if (!videoID && [self respondsToSelector:@selector(currentVideoID)])
                videoID = [(id)self performSelector:@selector(currentVideoID)];
            if (!videoID && [self respondsToSelector:@selector(videoID)])
                videoID = [(id)self performSelector:@selector(videoID)];
            if (!videoID && [self respondsToSelector:@selector(videoId)])
                videoID = [(id)self performSelector:@selector(videoId)];

            if (videoID && ![redirectedVideoIDs containsObject:videoID]) {
                [redirectedVideoIDs addObject:videoID];
                openVideoAsRegular(videoID, ((UIViewController *)self).view, nil);
            }
        });
    }
}
%end

// ─── Shorts Startup ───────────────────────────────────────────────────────────

%hook YTShortsStartupCoordinator
- (id)evaluateResumeToShorts { return ytpBool(@"resumeShorts") ? nil : %orig; }
%end

%hook YTReelWatchRootViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (ytpBool(@"shortsOnlyMode")) [self.navigationController.parentViewController hidePivotBar];
}
%end

// ─── Hide Shorts Elements ─────────────────────────────────────────────────────

%hook YTReelPausedStateCarouselView
- (void)setPausedStateCarouselVisible:(BOOL)arg1 animated:(BOOL)arg2 { ytpBool(@"hideShortsSubscriptions") ? %orig(NO, arg2) : %orig; }
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
// Block promoted reel ads
- (void)setShortsAdsRenderer:(id)renderer {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (BOOL)hasShortsAdsRenderer {
    if (ytpBool(@"noAds")) return NO;
    return %orig;
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

// ─── Video Download Manager ───────────────────────────────────────────────────
// Full implementation with n-parameter cipher decryption via JavaScriptCore.
//
// YouTube adaptive streams (720p+, all audio tracks) include an &n= parameter
// that throttles downloads to ~50KB/s unless transformed by a JS function
// embedded in YouTube's player JS. This code:
//   1. Sniffs the player JS URL from network responses (one-time, cached)
//   2. Fetches the JS, extracts the n-transform function
//   3. Runs it on-device via JSCore (zero external dependencies)
//   4. Patches all stream URLs before downloading
//
// Muxed streams (≤360p) have plain URLs and work without deciphering.

// JavaScriptCore loaded at runtime via dlopen to avoid sideloaded app crash on iOS 26.
// Forward-declare only what we use so the compiler is happy without the framework linked.
@interface JSContext : NSObject
+ (instancetype)new;
@property (copy) void (^exceptionHandler)(JSContext *context, id exception);
- (id)evaluateScript:(NSString *)script;
@end
@interface JSValue : NSObject
- (id)callWithArguments:(NSArray *)arguments;
- (NSString *)toString;
@property (readonly) BOOL isUndefined;
@property (readonly) BOOL isNull;
@end
static void ytpLoadJSCoreIfNeeded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore", RTLD_LAZY | RTLD_GLOBAL);
    });
}

static NSString *ytpCachedPlayerJSURL = nil;  // e.g. /s/player/abc123/player_ias.vflset/en_US/base.js
static NSString *ytpCachedNFuncJS     = nil;  // The extracted JS: "var f=function(a){...}; f"
static dispatch_queue_t ytpCipherQueue;

static void ytpEnsureCipherQueue() {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ ytpCipherQueue = dispatch_queue_create("com.ytplus.cipher", DISPATCH_QUEUE_SERIAL); });
}

// Regex helpers ----------------------------------------------------------------

// Extract the n-function name from player JS.
// Pattern: the n-param is processed by a function whose name is found via:
//   ||a.length||b[c("n")]  (classic)  or  .get("n")&&  (newer builds)
// We look for the assignment: var NNN=function(a){ ... return a.join("") }
// then return "var ytpNFunc=NNN; ytpNFunc"  so JSCore can call it.
static NSString *ytpExtractNFunction(NSString *js) {
    if (!js.length) return nil;

    // Step 1: find the n-function name via the known call-site pattern
    // YouTube 21.x pattern: b[c("n")]&&(b[c("n")]=NNN(b[c("n")])
    NSError *err = nil;
    NSRegularExpression *nameRe = [NSRegularExpression
        regularExpressionWithPattern:@"\\bc\\(\"n\"\\)\\]&&\\(b\\[c\\(\"n\"\\)\\]=([a-zA-Z0-9$]{2,5})\\(b"
        options:0 error:&err];
    NSTextCheckingResult *m = [nameRe firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];

    if (!m) {
        // Alternative pattern: .get("n")&&(b=NNN(b)
        nameRe = [NSRegularExpression
            regularExpressionWithPattern:@"\\.get\\(\"n\"\\)&&\\(b=([a-zA-Z0-9$]{2,5})\\(b\\)"
            options:0 error:&err];
        m = [nameRe firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];
    }

    if (!m || m.numberOfRanges < 2) return nil;
    NSString *funcName = [js substringWithRange:[m rangeAtIndex:1]];

    // Step 2: extract the full function body
    // Search for: var FUNCNAME=function(a){...}  or  FUNCNAME=function(a){...}
    NSString *bodyPattern = [NSString stringWithFormat:
        @"(?:var\\s+)?%@=function\\(([a-zA-Z0-9,\\s]*)\\)\\{([^}]+(?:\\{[^}]*\\}[^}]*)*)\\}",
        [NSRegularExpression escapedPatternForString:funcName]];
    NSRegularExpression *bodyRe = [NSRegularExpression
        regularExpressionWithPattern:bodyPattern
        options:NSRegularExpressionDotMatchesLineSeparators error:&err];
    NSTextCheckingResult *bm = [bodyRe firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];
    if (!bm) return nil;

    NSString *fullFunc = [js substringWithRange:bm.range];

    // Step 3: the n-function often calls helper objects (split/reverse/splice arrays).
    // We need to include those helper definitions too.
    // Find all identifiers used inside the function that look like object references.
    NSMutableSet *helpers = [NSMutableSet set];
    NSRegularExpression *refRe = [NSRegularExpression
        regularExpressionWithPattern:@"([a-zA-Z0-9$]{2,5})\\.[a-zA-Z0-9$]+"
        options:0 error:nil];
    NSArray *refs = [refRe matchesInString:fullFunc options:0 range:NSMakeRange(0, fullFunc.length)];
    for (NSTextCheckingResult *r in refs) {
        NSString *objName = [fullFunc substringWithRange:[r rangeAtIndex:1]];
        if (![objName isEqualToString:funcName]) [helpers addObject:objName];
    }

    // Find and prepend helper var definitions from player JS
    NSMutableString *helperJS = [NSMutableString string];
    for (NSString *h in helpers) {
        NSString *hp = [NSString stringWithFormat:@"var\\s+%@=\\{[^;]+\\};",
            [NSRegularExpression escapedPatternForString:h]];
        NSRegularExpression *hRe = [NSRegularExpression regularExpressionWithPattern:hp
            options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *hm = [hRe firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];
        if (hm) [helperJS appendFormat:@"%@\n", [js substringWithRange:hm.range]];
    }

    // Build final callable JS: helpers + func definition + "funcName"  (JSCore evaluates to the func)
    return [NSString stringWithFormat:@"%@\n%@\n%@", helperJS, fullFunc, funcName];
}

// Apply n-cipher to a URL string, returns patched URL or original if n absent/error
static NSString *ytpApplyNCipher(NSString *urlString, NSString *nFuncJS) {
    if (!nFuncJS || !urlString.length) return urlString;

    // Extract the n value
    NSRegularExpression *nRe = [NSRegularExpression
        regularExpressionWithPattern:@"[&?]n=([a-zA-Z0-9_-]+)"
        options:0 error:nil];
    NSTextCheckingResult *nm = [nRe firstMatchInString:urlString options:0
        range:NSMakeRange(0, urlString.length)];
    if (!nm || nm.numberOfRanges < 2) return urlString; // No n-param, URL is fine as-is

    NSRange nValRange = [nm rangeAtIndex:1];
    NSString *nVal = [urlString substringWithRange:nValRange];

    // Load JavaScriptCore at runtime (not linked at build time to avoid iOS 26 sideload crash)
    ytpLoadJSCoreIfNeeded();

    // Run through JSCore
    JSContext *ctx = [[JSContext alloc] init];
    ctx.exceptionHandler = ^(JSContext *c, JSValue *ex) { /* swallow */ };
    JSValue *func = [ctx evaluateScript:nFuncJS];
    if (!func || func.isUndefined || func.isNull) return urlString;

    JSValue *result = [func callWithArguments:@[nVal]];
    if (!result || result.isUndefined || result.isNull) return urlString;

    NSString *newN = result.toString;
    if (!newN.length) return urlString;

    // Replace the n value in the URL
    NSMutableString *patched = [urlString mutableCopy];
    [patched replaceCharactersInRange:nValRange withString:newN];
    return [patched copy];
}

// Fetch player JS and extract n-function, then call completion on main queue
static void ytpFetchNCipher(NSString *playerJSPath, void(^completion)(NSString *nFuncJS)) {
    ytpEnsureCipherQueue();
    dispatch_async(ytpCipherQueue, ^{
        // Return cached version if JS URL hasn't changed
        if ([playerJSPath isEqualToString:ytpCachedPlayerJSURL] && ytpCachedNFuncJS) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(ytpCachedNFuncJS); });
            return;
        }

        NSString *fullURL = [NSString stringWithFormat:@"https://www.youtube.com%@", playerJSPath];
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:fullURL]
            cachePolicy:NSURLRequestReturnCacheDataElseLoad
            timeoutInterval:15];

        // Inline semaphore-based synchronous fetch (we're already off main thread on our serial queue)
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSData *fetchedData = nil;
        __block NSError *fetchErr = nil;
        [[NSURLSession.sharedSession dataTaskWithRequest:req
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                fetchedData = d; fetchErr = e;
                dispatch_semaphore_signal(sem);
            }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));

        if (!fetchedData || fetchErr) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
            return;
        }

        NSString *js = [[NSString alloc] initWithData:fetchedData encoding:NSUTF8StringEncoding];
        NSString *nFunc = ytpExtractNFunction(js);

        if (nFunc) {
            ytpCachedPlayerJSURL = playerJSPath;
            ytpCachedNFuncJS     = nFunc;
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion(nFunc); });
    });
}


// ── Network response sniffer — extracts player JS URL from InnerTube responses ─

// ── Player JS URL sniffer — iterative JSON walk, no recursive blocks ─────────
// Logos preprocessor doesn't support recursive ^__block inside %hook, so we use
// a plain C function with an NSMutableArray stack instead.

static NSString *ytpFindJsUrlInJSON(id root) {
    if (!root) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        id node = stack.lastObject;
        [stack removeLastObject];
        if ([node isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)node;
            if (d[@"jsUrl"] && [d[@"jsUrl"] isKindOfClass:[NSString class]]) return d[@"jsUrl"];
            [stack addObjectsFromArray:d.allValues];
        } else if ([node isKindOfClass:[NSArray class]]) {
            [stack addObjectsFromArray:(NSArray *)node];
        }
    }
    return nil;
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (![request.URL.path containsString:@"/youtubei/v1/player"]) {
        return %orig;
    }

    // Logos preprocessor cannot handle block literals as %orig arguments.
    // Capture the original completion handler and request, then call %orig
    // with the original arguments, intercepting via our own wrapper task.
    void (^wrapper)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && !error && !ytpCachedPlayerJSURL) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    NSString *jsUrl = ytpFindJsUrlInJSON(json);
                    if (jsUrl && ![jsUrl isEqualToString:ytpCachedPlayerJSURL]) {
                        ytpFetchNCipher(jsUrl, ^(NSString *f) { /* prefetch complete */ });
                    }
                });
            }
            if (completionHandler) completionHandler(data, response, error);
        };
    return %orig(request, wrapper);
}

%end

// ── Download helper — applies n-cipher then downloads ─────────────────────────

static void ytpDownloadFromURL(NSURL *url, BOOL isAudio, UIViewController *presenter) {
    if (!url) {
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Error.NoStreamURL") firstResponder:presenter] send];
        return;
    }

    [[%c(YTToastResponderEvent) eventWithMessage:(isAudio ? LOC(@"DownloadingAudio") : LOC(@"DownloadingVideo")) firstResponder:presenter] send];

    void (^startDownload)(NSURL *) = ^(NSURL *finalURL) {
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
            downloadTaskWithURL:finalURL
            completionHandler:^(NSURL *tmpLocation, NSURLResponse *response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error || !tmpLocation) {
                        NSString *msg = [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), error.localizedDescription ?: @"Unknown"];
                        [[%c(YTToastResponderEvent) eventWithMessage:msg firstResponder:presenter] send];
                        return;
                    }
                    NSString *ext = isAudio ? @"m4a" : @"mp4";
                    NSURL *destURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                        URLByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:ext]];
                    [[NSFileManager defaultManager] moveItemAtURL:tmpLocation toURL:destURL error:nil];
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:destURL];
                    } completionHandler:^(BOOL success, NSError *err) {
                        [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSString *result = success
                                ? LOC(@"DownloadCompleted")
                                : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), err.localizedDescription];
                            [[%c(YTToastResponderEvent) eventWithMessage:result firstResponder:presenter] send];
                        });
                    }];
                });
            }];
        [task resume];
    };

    // If we have a cached n-cipher, apply it synchronously on main thread (JSCore is fast)
    if (ytpCachedNFuncJS) {
        NSString *patched = ytpApplyNCipher(url.absoluteString, ytpCachedNFuncJS);
        startDownload([NSURL URLWithString:patched] ?: url);
        return;
    }

    // No cipher cached yet — try to fetch it first, then download
    if (ytpCachedPlayerJSURL) {
        ytpFetchNCipher(ytpCachedPlayerJSURL, ^(NSString *nFuncJS) {
            NSString *patched = ytpApplyNCipher(url.absoluteString, nFuncJS);
            startDownload([NSURL URLWithString:patched] ?: url);
        });
    } else {
        // No player JS URL sniffed yet — download without cipher (works for muxed/360p streams)
        startDownload(url);
    }
}

// ── Download button hook ───────────────────────────────────────────────────────

%hook YTPlayabilityResolutionUserActionUIControllerImpl
- (void)confirmAlertDidPressConfirm {
    if (!ytpBool(@"downloadManager")) { %orig; return; }

    UIViewController *topVC = [%c(YTUIUtils) topViewControllerForPresenting];

    // Walk responder chain to find YTPlayerViewController
    YTPlayerViewController *playerVC = nil;
    UIResponder *r = topVC;
    while (r) {
        if ([r isKindOfClass:%c(YTPlayerViewController)]) { playerVC = (YTPlayerViewController *)r; break; }
        if ([r isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)r;
            if ([vc.parentViewController isKindOfClass:%c(YTPlayerViewController)]) {
                playerVC = (YTPlayerViewController *)vc.parentViewController; break;
            }
        }
        r = r.nextResponder;
    }

    NSArray *formats = playerVC.activeVideo.selectableVideoFormats;
    NSURL *audioURL  = playerVC.activeVideo.streamingData.selectedAudioFormat.streamURL;

    if (!formats.count && !audioURL) { %orig; return; }

    YTDefaultSheetController *sheet = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];

    // Sort by resolution descending
    NSArray *sorted = [formats sortedArrayUsingComparator:^NSComparisonResult(MLFormat *a, MLFormat *b) {
        if (b.singleDimensionResolution > a.singleDimensionResolution) return NSOrderedDescending;
        if (b.singleDimensionResolution < a.singleDimensionResolution) return NSOrderedAscending;
        return NSOrderedSame;
    }];

    for (MLFormat *fmt in sorted) {
        if (!fmt.streamURL) continue;
        NSString *label = [NSString stringWithFormat:@"%@ — %@", LOC(@"DownloadVideo"), fmt.qualityLabel];
        NSURL *url = fmt.streamURL;
        [sheet addAction:[%c(YTActionSheetAction)
            actionWithTitle:label
            iconImage:YTPImageNamed(@"yt_outline_arrow_down_alt_24pt")
            style:0
            handler:^{ ytpDownloadFromURL(url, NO, topVC); }]];
    }

    if (audioURL) {
        [sheet addAction:[%c(YTActionSheetAction)
            actionWithTitle:LOC(@"DownloadAudio")
            iconImage:YTPImageNamed(@"yt_outline_youtube_music_24pt")
            style:0
            handler:^{ ytpDownloadFromURL(audioURL, YES, topVC); }]];
    }

    [sheet presentFromViewController:topVC animated:YES completion:nil];
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

%hook YTPivotBarViewController
- (void)showPivotBar {
    if (!ytpBool(@"shortsOnlyMode")) { %orig; isOverlayShown = YES; }
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
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(id)lang { return ytpBool(@"disableRTL") ? NSWritingDirectionLeftToRight : %orig; } // ❌ BROKEN: method removed — disableRTL toggle non-functional
+ (NSWritingDirection)_defaultWritingDirection { return ytpBool(@"disableRTL") ? NSWritingDirectionLeftToRight : %orig; } // ❌ BROKEN: method removed
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
