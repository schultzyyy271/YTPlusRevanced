// YTPlus.x
// Rebuilt from YTLite open-source by the community.
// Updated for YouTube 21.16.2 (iOS 16+).
// Mod by Schultzy — built on YTLite open-source base.
#include <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import <stdarg.h>

#import "YTPlus.h"

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Forward declarations for download manager (defined later in file)
static __weak YTPlayerViewController *YTPlusCurrentPlayerVC;
static void YTPlusShowDownloadMgr(YTPlayerViewController *player, UIViewController *presenter, UIView *sender);
void YTPlusConfigureDownloadBtn(_ASDisplayView *view);
static UIViewController *YTPlusPresenter(UIView *sender, YTPlayerViewController *player);
static YTPlayerViewController *YTPlusPlayerFromVC(UIViewController *vc);

// Private API category for view controller lookup
@interface UIView (YTPlusPrivate)
- (UIViewController *)_viewControllerForAncestor;
@end

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
// adSlotsArray removed in 21.16.2
%end

%hook YTPlayerResponse
// playerAdsArray/adSlotsArray removed — use adPlayerResponse instead
- (id)adPlayerResponse { return ytpBool(@"noAds") ? nil : %orig; }
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
- (void)layoutSubviews {
    if (ytpBool(@"noAds")) { ((UIView *)self).hidden = YES; return; }
    %orig;
}
%end

// Level 2: Block ad model properties — tell YouTube the reel is not an ad
%hook YTReelModel
- (BOOL)isAdVideo {
    if (ytpBool(@"noAds")) return NO;
    return %orig;
}
%end

// Level 3: Block ad overlay on Shorts playback overlay
%hook YTReelWatchPlaybackOverlayView
// isAdShowing/setAdShowing removed in 21.16.2 — block ad overlays instead
- (void)layoutAdsPlayerOverlayView {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (void)layoutAdsBottomOverlayViewIfNeeded {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (void)layoutAdsTopOverlayViewIfNeeded {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (void)setAdsPlayerOrganicBottomOverlayView:(id)arg1 {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (void)setAdsPlayerOrganicTopOverlayView:(id)arg1 {
    if (ytpBool(@"noAds")) return;
    %orig;
}
// ─── Shorts Download Button ──────────────────────────────────────────────────
- (void)layoutSubviews {
    %orig;
    if (!ytpBool(@"downloadManager")) return;

    static NSInteger kShortsDownloadTag = 9977;
    UIButton *dlBtn = [self viewWithTag:kShortsDownloadTag];
    if (!dlBtn) {
        dlBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        dlBtn.tag = kShortsDownloadTag;

        UIImage *icon = [UIImage systemImageNamed:@"arrow.down.circle"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular]];
        [dlBtn setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        dlBtn.tintColor = [UIColor whiteColor];
        dlBtn.layer.shadowColor = [UIColor blackColor].CGColor;
        dlBtn.layer.shadowOffset = CGSizeMake(0, 1);
        dlBtn.layer.shadowOpacity = 0.6;
        dlBtn.layer.shadowRadius = 2.0;

        [dlBtn addTarget:self action:@selector(ytpShortsDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:dlBtn];
    }

    // Deep recursive search for the like button in the view hierarchy
    __block UIView *likeBtn = nil;
    __block UIView *dislikeBtn = nil;
    __block void (^deepSearch)(UIView *, int);
    __weak __block void (^weakSearch)(UIView *, int);
    deepSearch = ^(UIView *view, int depth) {
        if (depth > 8 || (likeBtn && dislikeBtn)) return;
        for (UIView *sub in view.subviews) {
            NSString *aid = sub.accessibilityIdentifier;
            if ([aid isEqualToString:@"id.reel_like_button"]) likeBtn = sub;
            else if ([aid isEqualToString:@"id.reel_dislike_button"]) dislikeBtn = sub;
            if (likeBtn && dislikeBtn) return;
            if (weakSearch) weakSearch(sub, depth + 1);
        }
    };
    weakSearch = deepSearch;
    deepSearch(self, 0);

    CGFloat btnSize = 40.0;
    if (likeBtn && dislikeBtn && !CGRectIsEmpty(likeBtn.frame) && !CGRectIsEmpty(dislikeBtn.frame)) {
        CGRect likeFrame = [self convertRect:likeBtn.bounds fromView:likeBtn];
        CGRect dislikeFrame = [self convertRect:dislikeBtn.bounds fromView:dislikeBtn];

        CGFloat likeCenterY = CGRectGetMidY(likeFrame);
        CGFloat dislikeCenterY = CGRectGetMidY(dislikeFrame);
        CGFloat step = dislikeCenterY - likeCenterY;
        CGFloat centerX = CGRectGetMidX(likeFrame);

        // Place one step above like button center, same X
        dlBtn.frame = CGRectMake(centerX - btnSize / 2, likeCenterY - step - btnSize / 2, btnSize, btnSize);
    } else if (likeBtn && !CGRectIsEmpty(likeBtn.frame)) {
        CGRect likeFrame = [self convertRect:likeBtn.bounds fromView:likeBtn];
        CGFloat centerX = CGRectGetMidX(likeFrame);
        dlBtn.frame = CGRectMake(centerX - btnSize / 2, likeFrame.origin.y - btnSize - 4.0, btnSize, btnSize);
    } else {
        // Fallback: use actionBarWidth to position on the right side
        CGFloat abWidth = 0;
        SEL abSel = @selector(actionBarWidth);
        if ([self respondsToSelector:abSel]) {
            abWidth = ((CGFloat (*)(id, SEL))objc_msgSend)((id)self, abSel);
        }
        if (abWidth <= 0) abWidth = 52.0;
        CGFloat centerX = self.bounds.size.width - abWidth / 2.0;
        // Position at roughly 33% from top - just above where the like button typically sits
        CGFloat topY = self.bounds.size.height * 0.33;
        dlBtn.frame = CGRectMake(centerX - btnSize / 2, topY, btnSize, btnSize);
    }
    dlBtn.hidden = NO;
}

%new
- (void)ytpShortsDownloadTapped:(UIButton *)sender {
    UIResponder *r = self;
    YTPlayerViewController *player = nil;
    while (r) {
        if ([r isKindOfClass:%c(YTPlayerViewController)]) { player = (YTPlayerViewController *)r; break; }
        if ([r isKindOfClass:%c(YTShortsPlayerViewController)]) {
            if ([r respondsToSelector:@selector(player)]) player = (YTPlayerViewController *)[(id)r player];
            break;
        }
        if ([r isKindOfClass:%c(YTReelPlayerViewController)]) {
            if ([r respondsToSelector:@selector(player)]) player = (YTPlayerViewController *)[(id)r player];
            break;
        }
        r = r.nextResponder;
    }
    if (!player) player = YTPlusCurrentPlayerVC;

    UIViewController *presenter = [%c(YTUIUtils) topViewControllerForPresenting] ?: (UIViewController *)player;
    YTPlusShowDownloadMgr(player, presenter, sender);
}

%end

// Level 4: Block the ad fetch pipeline for reels
// YTReelAdsAPIImpl removed in 21.16.2 — V1 and V2 use observer pattern now
%hook YTReelAdsAPIV1Impl
- (void)didAddNewReelContentModel:(id)model {
    if (ytpBool(@"noAds")) return;
    %orig;
}
%end

%hook YTReelAdsAPIV2Impl
- (void)didReceiveReelWatchSequenceResponse:(id)response {
    if (ytpBool(@"noAds")) return;
    %orig;
}
- (void)didReceivePlayerResponse:(id)response forItemIdentifier:(id)identifier {
    if (ytpBool(@"noAds")) return;
    %orig;
}
%end

// Level 5: YTReelAdsPresenterManager removed in 21.16.2 — ads blocked at other levels

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

// YTPromoThrottleController removed in 21.16.2 — Impl version below handles it

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

// MDXSession removed in 21.16.2

%hook MDXSessionImpl
- (void)adPlaying:(id)ad {}
%end

// YTAppMealbarPromoController removed in 21.16.2

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

// YTSettings removed in 21.16.2 — noCast handled elsewhere

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
// videoZoomFreeZoomEnabledGlobalConfig — removed in 21.16.2
// enableChipsInTheCommentsHeaderIos — removed in 21.16.2
// shouldUseAppThemeSetting — removed in 21.16.2
// isLandscapeEngagementPanelSwipeRightToDismissEnabled — removed in 21.16.2
- (BOOL)enableHideChipsInTheCommentsHeaderOnScrollIos { return ytpBool(@"stickSortComments") ? NO : %orig; }
- (BOOL)enableSwipeToRemoveInPlaylistWatchEp { return YES; }
- (BOOL)queueClientGlobalConfigEnableFloatingPlaylistMinibar { return ytpBool(@"playlistOldMinibar") ? NO : %orig; }
// Shorts config
- (BOOL)iosEnableVideoPlayerScrubber { return ytpBool(@"shortsProgress") ? YES : %orig; }
// mobileShortsTabInlined — removed in 21.16.2
// iosUseSystemVolumeControlInFullscreen — removed in 21.16.2
// Shorts ad blocking — all removed in 21.16.2, ads blocked at overlay/data level instead
- (BOOL)shortsConsumptionClientGlobalConfigEnableBackgroundRenderingOnShortsAds { return ytpBool(@"noAds") ? NO : %orig; }
%end

%hook YTHotConfig
// enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen — removed in 21.16.2
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

// YTWatchMiniBarVisibilityController removed in 21.16.2

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

// YTVideoQualitySwitchControllerFactory removed in 21.16.2

// ─── Extra Speed Options ──────────────────────────────────────────────────────
// YTVarispeedSwitchController removed in 21.16.2
// Speed control is now handled via YTPlayerViewController setPlaybackRate:

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
- (void)layoutSubviews { %orig; if (ytpBool(@"dontSnapToChapter") && [self respondsToSelector:@selector(setEnableSnapToChapter:)]) self.enableSnapToChapter = NO; }
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

// YTSettings removed in 21.16.2 — hints handled by YTUserDefaults below

%hook YTUserDefaults
- (void)setDisableMDXDeviceDiscovery:(BOOL)arg1 { %orig(ytpBool(@"noCast")); }
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
// YouTube 21.16.2 removed loadWithPlayerTransition:playbackConfig:initialTime:
// and replaced it with loadWithPlayerPlayback:. Also, YTPlayerViewController is
// NOT a UIViewController subclass anymore — no viewDidAppear/viewWillDisappear.
// Use playbackController:didActivateVideo:withPlaybackData: as the "loaded" event
// and playbackControllerDidFinishPlayback: as the "unloaded" event.

- (void)loadWithPlayerPlayback:(id)arg1 {
    %orig;
    if (ytpInt(@"wiFiQualityIndex") != 0 || ytpInt(@"cellQualityIndex") != 0)
        [self performSelector:@selector(autoQuality) withObject:nil afterDelay:1.0];
    if (ytpBool(@"autoFullscreen"))
        [self performSelector:@selector(autoFullscreen) withObject:nil afterDelay:0.75];
    if (ytpInt(@"autoSpeedIndex") != 3)
        [self performSelector:@selector(setAutoSpeed) withObject:nil afterDelay:0.75];
    if (ytpBool(@"disableAutoCaptions"))
        [self performSelector:@selector(turnOffCaptions) withObject:nil afterDelay:1.0];
}

- (void)playbackController:(id)playbackController didActivateVideo:(id)video withPlaybackData:(id)data {
    %orig;
    YTPlusCurrentPlayerVC = self;
}

- (void)playbackControllerDidFinishPlayback:(id)playbackController {
    %orig;
    if (YTPlusCurrentPlayerVC == self)
        YTPlusCurrentPlayerVC = nil;
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
// YTMenuItemVisibilityHandler removed in 21.16.2 — filtering done via YTDefaultSheetController

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
// YTShortsStartupCoordinator removed in 21.16.2

%hook YTReelWatchRootViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (ytpBool(@"shortsOnlyMode")) { UIResponder *r = self; while (r) { if ([r respondsToSelector:@selector(hidePivotBar)]) { [r performSelector:@selector(hidePivotBar)]; break; } r = r.nextResponder; } }
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
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = %orig;
    for (YTQTMButton *button in self.subviews) {
        if ([button respondsToSelector:@selector(buttonRenderer)]) {
            if (ytpBool(@"hideShortsSearch") && button.buttonRenderer.icon.iconType == 1045) button.hidden = YES;
            if (ytpBool(@"hideShortsCamera") && button.buttonRenderer.icon.iconType == 1046) button.hidden = YES;
            if (ytpBool(@"hideShortsMore") && button.buttonRenderer.icon.iconType == 1047) button.hidden = YES;
        }
    }
    return result;
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
// setShortsAdsRenderer: removed in 21.16.2
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

- (void)didMoveToWindow {
    %orig;
    // Configure our download button on the YouTube download button view
    YTPlusConfigureDownloadBtn(self);
    // Keep the button visible — our tap gesture intercepts it for the download manager
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

%new
- (void)YTPlusDownloadButtonTapped:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) return;
    UIViewController *presenter = YTPlusPresenter(self, YTPlusCurrentPlayerVC);
    YTPlayerViewController *player = YTPlusPlayerFromVC(presenter);
    YTPlusShowDownloadMgr(player, presenter, self);
}

%end


// ─── Video Download Manager (adapted from YouMod by @daisuke1227) ─────────
// Full download system: quality picker, audio formats, chunked downloads,
// FFmpegKit merge/convert, captions, thumbnails, share sheet.

// HUGE thanks to @daisuke1227 for implementing all of this

@interface YTDefaultSheetController (YTPlusDownload)
+ (instancetype)sheetControllerWithParentResponder:(id)parentResponder;
- (void)addAction:(YTActionSheetAction *)action;
- (void)presentFromView:(UIView *)view animated:(BOOL)animated completion:(void (^)(void))completion;
- (void)presentFromViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion;
@end

@interface YTPlayerViewController (YTPlusDownload)
- (YTPlayerResponse *)contentPlayerResponse;
@end

@interface YTIPlayerResponse (YTPlusDownload)
- (id)streamingData;
@end

@interface YTIStreamingData : NSObject
- (NSArray *)adaptiveFormatsArray;
@end

@interface YTIFormatStream : NSObject
@end

@interface YTIFormatStream (YTPlusDownload)
- (NSString *)mimeType;
- (BOOL)hasContentLength;
- (unsigned long long)contentLength;
- (unsigned long long)approxDurationMs;
@end

@interface YTIVideoDetails (YTPlusDownload)
- (NSString *)title;
- (NSString *)author;
- (NSString *)shortDescription;
@end

static UIImage *YTPlusIconImage(NSInteger iconType) {
    // Use SF Symbols as fallback since iconImageWithColor: may not exist
    switch (iconType) {
        case 137: return [UIImage systemImageNamed:@"arrow.down.circle"] ?: [UIImage new]; // download
        case 251: return [UIImage systemImageNamed:@"music.note"] ?: [UIImage new]; // audio
        case 371: return [UIImage systemImageNamed:@"captions.bubble"] ?: [UIImage new]; // captions
        case 574: return [UIImage systemImageNamed:@"photo"] ?: [UIImage new]; // thumbnail
        case 610: return [UIImage systemImageNamed:@"square.and.arrow.up"] ?: [UIImage new]; // share
        default: {
            YTIIcon *icon = [%c(YTIIcon) new];
            icon.iconType = iconType;
            SEL colorSel = @selector(iconImageWithColor:);
            if ([icon respondsToSelector:colorSel]) {
                UIImage *image = ((UIImage *(*)(id, SEL, id))objc_msgSend)(icon, colorSel, [UIColor labelColor]);
                return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] ?: [UIImage new];
            }
            SEL plainSel = @selector(iconImage);
            if ([icon respondsToSelector:plainSel]) {
                UIImage *image = ((UIImage *(*)(id, SEL))objc_msgSend)(icon, plainSel);
                return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] ?: [UIImage new];
            }
            return [UIImage systemImageNamed:@"ellipsis.circle"] ?: [UIImage new];
        }
    }
}

@interface YTPlusMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) UIImage *iconImage;
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle handler:(void (^)(void))handler;
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon handler:(void (^)(void))handler;
@end

@implementation YTPlusMenuItem
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle handler:(void (^)(void))handler {
    return [self itemWithTitle:title subtitle:subtitle icon:nil handler:handler];
}
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon handler:(void (^)(void))handler {
    YTPlusMenuItem *item = [YTPlusMenuItem new];
    item.title = title;
    item.subtitle = subtitle;
    item.iconImage = icon;
    item.handler = handler;
    return item;
}
@end

@interface YTPlusMediaFormat : NSObject
@property (nonatomic, strong) id source;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *qualityLabel;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, copy) NSDictionary *httpHeaders;
@property (nonatomic, assign) unsigned long long contentLength;
@property (nonatomic, assign) unsigned long long durationMs;
@property (nonatomic, assign) NSInteger fps;
@property (nonatomic, assign) BOOL video;
@property (nonatomic, copy) NSString *languageCode;
@property (nonatomic, copy) NSString *languageName;
@property (nonatomic, assign) BOOL drcAudio;
@property (nonatomic, assign) BOOL isDefaultAudio;
@end

@implementation YTPlusMediaFormat
@end

@interface YTPlusAudioOutputFormat : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *fileExtension;
@property (nonatomic, copy) NSArray <NSString *> *ffmpegArguments;
@property (nonatomic, assign) BOOL passthroughWhenCompatible;
@property (nonatomic, assign) BOOL supported;
@end

@implementation YTPlusAudioOutputFormat
@end

typedef void (^YTPlusFileDownloadCompletion)(NSURL *fileURL, NSError *error);
typedef void (^YTPlusMergeCompletion)(BOOL success, NSError *error);
typedef void (^YTPlusRangeDownloadProgress)(unsigned long long completedBytes);

@interface YTPlusDownloadChunk : NSObject
@property (nonatomic, assign) unsigned long long offset;
@property (nonatomic, assign) unsigned long long length;
@property (nonatomic, assign) NSUInteger attempts;
@end

@implementation YTPlusDownloadChunk
@end

@interface YTPlusRangeDownloader : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSURL *destinationURL;
@property (nonatomic, copy) NSDictionary *httpHeaders;
@property (nonatomic, assign) unsigned long long expectedBytes;
@property (nonatomic, copy) YTPlusRangeDownloadProgress progress;
@property (nonatomic, copy) YTPlusFileDownloadCompletion completion;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSMutableArray <YTPlusDownloadChunk *> *pendingChunks;
@property (nonatomic, strong) NSMutableSet <NSURLSessionDataTask *> *tasks;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) dispatch_queue_t fileQueue;
@property (nonatomic, assign) NSUInteger activeTaskCount;
@property (nonatomic, assign) NSUInteger totalChunkCount;
@property (nonatomic, assign) unsigned long long completedBytes;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;
- (instancetype)initWithURL:(NSURL *)url destinationURL:(NSURL *)destinationURL expectedBytes:(unsigned long long)expectedBytes headers:(NSDictionary *)headers progress:(YTPlusRangeDownloadProgress)progress completion:(YTPlusFileDownloadCompletion)completion;
- (void)start;
- (void)cancel;
@end

@interface YTPlusDownloadCoordinator : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSURLSessionDataTask *metadataTask;
@property (nonatomic, strong) YTPlusRangeDownloader *rangeDownloader;
@property (nonatomic, strong) UIAlertController *progressAlert;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, copy) YTPlusFileDownloadCompletion fileCompletion;
@property (nonatomic, strong) NSURL *destinationURL;
@property (nonatomic, strong) NSURL *videoTempURL;
@property (nonatomic, strong) NSURL *audioTempURL;
@property (nonatomic, assign) unsigned long long completedBytes;
@property (nonatomic, assign) unsigned long long totalBytes;
@property (nonatomic, assign) unsigned long long currentBytes;
@property (nonatomic, assign) unsigned long long currentExpectedBytes;
@property (nonatomic, assign) BOOL currentResolvedSizeAddedToTotal;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL finishedCurrentFile;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, copy) NSString *baseProgressTitle;
@property (nonatomic, assign) NSTimeInterval downloadStartTime;
+ (instancetype)sharedCoordinator;
- (void)startVideoDownloadWithVideoFormat:(YTPlusMediaFormat *)videoFormat audioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter;
- (void)startAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter;
- (void)startAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID outputFormat:(YTPlusAudioOutputFormat *)outputFormat presenter:(UIViewController *)presenter;
- (void)startDirectVideoDownloadWithVideoFormat:(YTPlusMediaFormat *)videoFormat audioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter;
- (void)startDirectSingleVideoDownloadWithFormat:(YTPlusMediaFormat *)format fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter;
- (void)startDirectAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter;
- (void)startDirectAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID outputFormat:(YTPlusAudioOutputFormat *)outputFormat presenter:(UIViewController *)presenter;
- (void)mergeVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL fileName:(NSString *)fileName outputExtension:(NSString *)outputExtension durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter;
- (void)mergeVideoWithAVFoundationVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL outputURL:(NSURL *)outputURL durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter fallbackError:(NSError *)fallbackError;
- (void)trimSingleVideoURL:(NSURL *)inputURL outputURL:(NSURL *)outputURL durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter;
- (void)convertAudioURL:(NSURL *)inputURL outputURL:(NSURL *)outputURL outputFormat:(YTPlusAudioOutputFormat *)outputFormat durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter;
@end

static const unsigned long long YTPlusFastDownloadMinimumBytes = 256ULL * 1024ULL;
static const unsigned long long YTPlusFastDownloadChunkBytes = 4ULL * 1024ULL * 1024ULL;
static const NSUInteger YTPlusFastDownloadConcurrency = 8;
static const NSUInteger YTPlusFastDownloadMaxAttempts = 3;

static BOOL YTPlusHTTPHeadersContainField(NSDictionary *headers, NSString *field) {
    for (id key in headers) {
        if ([key isKindOfClass:NSString.class] && [(NSString *)key caseInsensitiveCompare:field] == NSOrderedSame)
            return YES;
    }
    return NO;
}

static NSString *YTPlusYouTubeCookiesString(void) {
    NSMutableArray *cookieStrings = [NSMutableArray array];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([cookie.domain containsString:@"youtube.com"]) {
            [cookieStrings addObject:[NSString stringWithFormat:@"%@=%@", cookie.name, cookie.value]];
        }
    }
    return [cookieStrings componentsJoinedByString:@"; "];
}

static NSString *YTPlusNativeUserAgent(void) {
    NSString *version = @"21.18.4";
    NSString *sysVersion = [[UIDevice currentDevice].systemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"] ?: @"18_7";
    return [NSString stringWithFormat:@"com.google.ios.youtube/%@ (iPhone; CPU iPhone OS %@ like Mac OS X)", version, sysVersion];
}

static void YTPlusApplyDownloadHeaders(NSMutableURLRequest *request, NSDictionary *headers) {
    for (id key in headers) {
        id value = headers[key];
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class])
            [request setValue:value forHTTPHeaderField:key];
    }
    if (!YTPlusHTTPHeadersContainField(headers, @"User-Agent"))
        [request setValue:YTPlusNativeUserAgent() forHTTPHeaderField:@"User-Agent"];
    if (!YTPlusHTTPHeadersContainField(headers, @"Origin"))
        [request setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
    if (!YTPlusHTTPHeadersContainField(headers, @"Referer"))
        [request setValue:@"https://www.youtube.com/" forHTTPHeaderField:@"Referer"];
    if (!YTPlusHTTPHeadersContainField(headers, @"Cookie")) {
        NSString *cookies = YTPlusYouTubeCookiesString();
        if (cookies.length > 0) [request setValue:cookies forHTTPHeaderField:@"Cookie"];
    }
    extern NSString *ytpGlobalAuthHeader;
    if (ytpGlobalAuthHeader && !YTPlusHTTPHeadersContainField(headers, @"Authorization")) {
        [request setValue:ytpGlobalAuthHeader forHTTPHeaderField:@"Authorization"];
    }
    [request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
}

@implementation YTPlusRangeDownloader

- (instancetype)initWithURL:(NSURL *)url destinationURL:(NSURL *)destinationURL expectedBytes:(unsigned long long)expectedBytes headers:(NSDictionary *)headers progress:(YTPlusRangeDownloadProgress)progress completion:(YTPlusFileDownloadCompletion)completion {
    self = [super init];
    if (self) {
        _url = url;
        _destinationURL = destinationURL;
        _httpHeaders = [headers copy];
        _expectedBytes = expectedBytes;
        _progress = [progress copy];
        _completion = [completion copy];
        _pendingChunks = [NSMutableArray array];
        _tasks = [NSMutableSet set];
        _stateQueue = dispatch_queue_create("com.youmod.download.range.state", DISPATCH_QUEUE_SERIAL);
        _fileQueue = dispatch_queue_create("com.youmod.download.range.file", DISPATCH_QUEUE_SERIAL);

        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.HTTPMaximumConnectionsPerHost = YTPlusFastDownloadConcurrency;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.timeoutIntervalForResource = 300;
        NSMutableDictionary *additionalHeaders = [NSMutableDictionary dictionary];
        for (id key in headers) {
            id value = headers[key];
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class])
                additionalHeaders[key] = value;
        }
        if (!YTPlusHTTPHeadersContainField(additionalHeaders, @"User-Agent"))
            additionalHeaders[@"User-Agent"] = YTPlusNativeUserAgent();
        if (!YTPlusHTTPHeadersContainField(additionalHeaders, @"Origin"))
            additionalHeaders[@"Origin"] = @"https://www.youtube.com";
        if (!YTPlusHTTPHeadersContainField(additionalHeaders, @"Referer"))
            additionalHeaders[@"Referer"] = @"https://www.youtube.com/";
        if (!YTPlusHTTPHeadersContainField(additionalHeaders, @"Cookie")) {
            NSString *cookies = YTPlusYouTubeCookiesString();
            if (cookies.length > 0) additionalHeaders[@"Cookie"] = cookies;
        }
        extern NSString *ytpGlobalAuthHeader;
        if (ytpGlobalAuthHeader && !YTPlusHTTPHeadersContainField(additionalHeaders, @"Authorization")) {
            additionalHeaders[@"Authorization"] = ytpGlobalAuthHeader;
        }
        additionalHeaders[@"Accept-Encoding"] = @"identity";
        configuration.HTTPAdditionalHeaders = additionalHeaders;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:@"YTPlus" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Download failed"}];
}

- (BOOL)prepareDestinationWithError:(NSError **)error {
    [NSFileManager.defaultManager removeItemAtURL:self.destinationURL error:nil];
    if (![NSFileManager.defaultManager createFileAtPath:self.destinationURL.path contents:nil attributes:nil]) {
        if (error) *error = [self errorWithCode:20 message:@"Cannot create file"];
        return NO;
    }

    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.destinationURL.path];
    if (!self.fileHandle) {
        if (error) *error = [self errorWithCode:21 message:@"Cannot open file"];
        return NO;
    }

    @try {
        [self.fileHandle truncateFileAtOffset:self.expectedBytes];
    } @catch (NSException *exception) {
        if (error) *error = [self errorWithCode:22 message:exception.reason ?: @"Cannot allocate file"];
        return NO;
    }
    return YES;
}

- (void)start {
    dispatch_async(self.stateQueue, ^{
        if (self.expectedBytes == 0) {
            [self finishWithErrorLocked:[self errorWithCode:23 message:@"Unknown stream size"]];
            return;
        }

        NSError *error = nil;
        if (![self prepareDestinationWithError:&error]) {
            [self finishWithErrorLocked:error];
            return;
        }

        unsigned long long chunkSize = self.expectedBytes / YTPlusFastDownloadConcurrency;
        if (chunkSize < 256ULL * 1024ULL) chunkSize = 256ULL * 1024ULL;
        if (chunkSize > YTPlusFastDownloadChunkBytes) chunkSize = YTPlusFastDownloadChunkBytes;

        for (unsigned long long offset = 0; offset < self.expectedBytes; offset += chunkSize) {
            YTPlusDownloadChunk *chunk = [YTPlusDownloadChunk new];
            chunk.offset = offset;
            unsigned long long remaining = self.expectedBytes - offset;
            chunk.length = remaining < chunkSize ? remaining : chunkSize;
            [self.pendingChunks addObject:chunk];
        }
        self.totalChunkCount = self.pendingChunks.count;
        [self scheduleChunksLocked];
    });
}

- (void)cancel {
    dispatch_async(self.stateQueue, ^{
        if (self.finished) return;
        self.cancelled = YES;
        self.finished = YES;
        for (NSURLSessionDataTask *task in self.tasks) [task cancel];
        [self.tasks removeAllObjects];
        [self.session invalidateAndCancel];
        dispatch_async(self.fileQueue, ^{
            @try {
                [self.fileHandle closeFile];
            } @catch (__unused NSException *exception) {
            }
            [NSFileManager.defaultManager removeItemAtURL:self.destinationURL error:nil];
        });
    });
}

- (void)scheduleChunksLocked {
    if (self.finished || self.cancelled) return;
    while (self.activeTaskCount < YTPlusFastDownloadConcurrency && self.pendingChunks.count > 0) {
        YTPlusDownloadChunk *chunk = self.pendingChunks.firstObject;
        [self.pendingChunks removeObjectAtIndex:0];
        [self startChunkLocked:chunk];
    }

    if (self.activeTaskCount == 0 && self.pendingChunks.count == 0) {
        [self finishSuccessfullyLocked];
    }
}

- (void)startChunkLocked:(YTPlusDownloadChunk *)chunk {
    unsigned long long end = chunk.offset + chunk.length - 1;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    YTPlusApplyDownloadHeaders(request, self.httpHeaders);
    [request setValue:[NSString stringWithFormat:@"bytes=%llu-%llu", chunk.offset, end] forHTTPHeaderField:@"Range"];

    __weak typeof(self) weakSelf = self;
    __block NSURLSessionDataTask *task = nil;
    task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self completeChunk:chunk task:task data:data response:response error:error];
    }];
    [self.tasks addObject:task];
    self.activeTaskCount++;
    [task resume];
}

- (NSError *)validationErrorForChunk:(YTPlusDownloadChunk *)chunk data:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    if (error) return error;

    NSHTTPURLResponse *httpResponse = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    NSInteger statusCode = httpResponse.statusCode;
    BOOL statusOK = statusCode == 206 || (self.totalChunkCount == 1 && statusCode == 200);
    if (httpResponse && !statusOK)
        return [self errorWithCode:24 message:@"Range request rejected by server"];

    if (data.length != chunk.length)
        return [self errorWithCode:25 message:@"Incomplete chunk"];

    return nil;
}

- (void)completeChunk:(YTPlusDownloadChunk *)chunk task:(NSURLSessionDataTask *)task data:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    dispatch_async(self.stateQueue, ^{
        if (self.activeTaskCount > 0) self.activeTaskCount--;
        if (task) [self.tasks removeObject:task];
        if (self.finished || self.cancelled) return;

        NSError *validationError = [self validationErrorForChunk:chunk data:data response:response error:error];
        if (validationError) {
            if (validationError.code == 24) {
                [self finishWithErrorLocked:validationError];
                return;
            }
            if (chunk.attempts + 1 < YTPlusFastDownloadMaxAttempts) {
                chunk.attempts++;
                [self.pendingChunks insertObject:chunk atIndex:0];
                [self scheduleChunksLocked];
            } else {
                [self finishWithErrorLocked:validationError];
            }
            return;
        }

        NSData *chunkData = [data copy];
        dispatch_async(self.fileQueue, ^{
            NSError *writeError = nil;
            @try {
                [self.fileHandle seekToFileOffset:chunk.offset];
                [self.fileHandle writeData:chunkData];
            } @catch (NSException *exception) {
                writeError = [self errorWithCode:26 message:exception.reason ?: @"Write failed"];
            }

            dispatch_async(self.stateQueue, ^{
                if (self.finished || self.cancelled) return;
                if (writeError) {
                    [self finishWithErrorLocked:writeError];
                    return;
                }

                self.completedBytes += chunkData.length;
                if (self.progress) {
                    unsigned long long completed = self.completedBytes;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.progress(completed);
                    });
                }
                [self scheduleChunksLocked];
            });
        });
    });
}

- (void)finishSuccessfullyLocked {
    if (self.finished) return;
    self.finished = YES;
    [self.session finishTasksAndInvalidate];
    dispatch_async(self.fileQueue, ^{
        @try {
            [self.fileHandle closeFile];
        } @catch (__unused NSException *exception) {
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completion) self.completion(self.destinationURL, nil);
        });
    });
}

- (void)finishWithErrorLocked:(NSError *)error {
    if (self.finished) return;
    self.finished = YES;
    for (NSURLSessionDataTask *task in self.tasks) [task cancel];
    [self.tasks removeAllObjects];
    [self.session invalidateAndCancel];
    dispatch_async(self.fileQueue, ^{
        @try {
            [self.fileHandle closeFile];
        } @catch (__unused NSException *exception) {
        }
        [NSFileManager.defaultManager removeItemAtURL:self.destinationURL error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completion) self.completion(nil, error ?: [self errorWithCode:27 message:@"Download failed"]);
        });
    });
}

@end

// YTPlusCurrentPlayerVC declared at top of file (forward declaration)

void YTPlusDownloadSetCurrentPlayer(YTPlayerViewController *player) {
    YTPlusCurrentPlayerVC = player;
}

static NSString *YTPlusStringFromSel(id object, SEL selector) {
    if (!object) return nil;
    id value = nil;
    if ([object respondsToSelector:selector]) {
        value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } else {
        @try {
            value = [object valueForKey:NSStringFromSelector(selector)];
        } @catch (__unused NSException *exception) {
            value = nil;
        }
    }
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return [(NSURL *)value absoluteString];
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return [value respondsToSelector:@selector(description)] ? [value description] : nil;
}

static id YTPlusObjectFromSel(id object, SEL selector) {
    if (!object) return nil;
    if ([object respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    }
    @try {
        return [object valueForKey:NSStringFromSelector(selector)];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static unsigned long long YTPlusULLFromSel(id object, SEL selector) {
    if (!object) return 0;
    if ([object respondsToSelector:selector]) {
        return ((unsigned long long (*)(id, SEL))objc_msgSend)(object, selector);
    }
    @try {
        id value = [object valueForKey:NSStringFromSelector(selector)];
        if ([value respondsToSelector:@selector(unsignedLongLongValue)])
            return [value unsignedLongLongValue];
    } @catch (__unused NSException *exception) {
    }
    return 0;
}

static BOOL YTPlusBoolFromSel(id object, SEL selector) {
    if (!object) return NO;
    if ([object respondsToSelector:selector]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    }
    @try {
        id value = [object valueForKey:NSStringFromSelector(selector)];
        if ([value respondsToSelector:@selector(boolValue)])
            return [value boolValue];
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static NSInteger YTPlusIntFromSel(id object, SEL selector) {
    if (!object) return 0;
    if ([object respondsToSelector:selector]) {
        return ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
    }
    @try {
        id value = [object valueForKey:NSStringFromSelector(selector)];
        if ([value respondsToSelector:@selector(integerValue)])
            return [value integerValue];
    } @catch (__unused NSException *exception) {
    }
    return 0;
}

static UIViewController *YTPlusTopVC(UIViewController *root) {
    if (!root) {
        UIWindow *keyWindow = nil;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        root = keyWindow.rootViewController;
    }
    while (root.presentedViewController) root = root.presentedViewController;
    if ([root isKindOfClass:UINavigationController.class])
        return YTPlusTopVC(((UINavigationController *)root).topViewController);
    if ([root isKindOfClass:UITabBarController.class])
        return YTPlusTopVC(((UITabBarController *)root).selectedViewController);
    return root;
}

static void YTPlusSendToast(NSString *message, id responder) {
    Class toastClass = NSClassFromString(@"YTToastResponderEvent");
    id event = [toastClass eventWithMessage:message firstResponder:responder ?: YTPlusTopVC(nil)];
    if ([event respondsToSelector:@selector(send)]) {
        [event send];
        return;
    }

    UIViewController *presenter = YTPlusTopVC([responder isKindOfClass:UIViewController.class] ? responder : nil);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [presenter presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

static NSString *YTPlusByteCount(unsigned long long bytes) {
    if (bytes == 0) return nil;
    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:(long long)bytes];
}

static NSString *YTPlusGenerateCPN(void) {
    static NSString *const alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    NSMutableString *nonce = [NSMutableString stringWithCapacity:16];
    for (NSUInteger i = 0; i < 16; i++)
        [nonce appendFormat:@"%C", [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
    return nonce;
}

static NSString *YTPlusURLBypassThrottle(NSString *urlString) {
    if (urlString.length == 0) return urlString;
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    if (components) {
        NSMutableArray *queryItems = [components.queryItems mutableCopy] ?: [NSMutableArray array];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSURLQueryItem *item in queryItems) {
            if (![item.name isEqualToString:@"n"])
                [filtered addObject:item];
        }
        BOOL hasRateBypass = NO;
        for (NSURLQueryItem *item in filtered) {
            if ([item.name isEqualToString:@"ratebypass"]) { hasRateBypass = YES; break; }
        }
        if (!hasRateBypass)
            [filtered addObject:[NSURLQueryItem queryItemWithName:@"ratebypass" value:@"yes"]];
        components.queryItems = filtered;
        NSString *result = components.string;
        if (result.length > 0) return result;
    }
    return urlString;
}

static NSString *YTPlusURLWithCPN(NSString *urlString) {
    if (urlString.length == 0) return urlString;
    urlString = YTPlusURLBypassThrottle(urlString);
    if ([urlString containsString:@"cpn="]) return urlString;
    Class ytDataUtils = NSClassFromString(@"YTDataUtils");
    NSString *cpn = ((id (*)(Class, SEL))objc_msgSend)(ytDataUtils, @selector(generateClientSideNonce));
    if (![cpn isKindOfClass:NSString.class] || cpn.length == 0)
        cpn = YTPlusGenerateCPN();
    NSString *separator = [urlString containsString:@"?"] ? @"&" : @"?";
    return [NSString stringWithFormat:@"%@%@cpn=%@", urlString, separator, cpn];
}

static NSString *YTPlusSanitizedFileName(NSString *name) {
    if (name.length == 0) return @"YouTube Video";
    NSMutableCharacterSet *invalid = [NSMutableCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
    [invalid formUnionWithCharacterSet:NSCharacterSet.newlineCharacterSet];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:invalid];
    NSString *clean = [[parts componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([clean containsString:@"  "]) clean = [clean stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    if (clean.length > 120) clean = [clean substringToIndex:120];
    return clean.length ? clean : @"YouTube Video";
}

static NSURL *YTPlusDownloadsDir(void) {
    NSURL *documentsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *downloadsURL = [documentsURL URLByAppendingPathComponent:@"YTPlus Downloads" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:downloadsURL withIntermediateDirectories:YES attributes:nil error:nil];
    return downloadsURL;
}

static NSString *YTPlusLastDiagnostic;

static NSURL *YTPlusDiagLogURL(void) {
    return [YTPlusDownloadsDir() URLByAppendingPathComponent:@"ytplus-download-diagnostics.txt"];
}

static void YTPlusRecordDiag(NSString *context, NSString *details) {
    if (context.length == 0 && details.length == 0) return;

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss ZZZZZ";
    NSString *timestamp = [formatter stringFromDate:NSDate.date];
    NSString *entry = [NSString stringWithFormat:@"[%@]\n%@\n%@\n\n", timestamp ?: @"", context ?: @"", details ?: @""];
    YTPlusLastDiagnostic = entry;

    NSURL *logURL = YTPlusDiagLogURL();
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    if (![NSFileManager.defaultManager fileExistsAtPath:logURL.path])
        [NSFileManager.defaultManager createFileAtPath:logURL.path contents:nil attributes:nil];

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    } @catch (__unused NSException *exception) {
    }
}

static NSString *YTPlusDiagText(void) {
    if (YTPlusLastDiagnostic.length) return YTPlusLastDiagnostic;
    NSString *log = [NSString stringWithContentsOfURL:YTPlusDiagLogURL() encoding:NSUTF8StringEncoding error:nil];
    if (log.length == 0) return nil;
    NSUInteger maxLength = 12000;
    return log.length > maxLength ? [log substringFromIndex:log.length - maxLength] : log;
}

static void YTPlusCopyDiag(UIViewController *presenter) {
    NSString *diagnostic = YTPlusDiagText();
    if (diagnostic.length == 0) {
        YTPlusSendToast(@"No download diagnostics yet.", presenter);
        return;
    }
    UIPasteboard.generalPasteboard.string = diagnostic;
    YTPlusSendToast(@"Copied download diagnostics", presenter);
}

static NSURL *YTPlusUniqueFileURL(NSString *fileName, NSString *extension) {
    NSString *safeName = YTPlusSanitizedFileName(fileName);
    NSURL *directoryURL = YTPlusDownloadsDir();
    NSURL *candidate = [directoryURL URLByAppendingPathComponent:[safeName stringByAppendingPathExtension:extension]];
    NSUInteger index = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
        NSString *indexed = [NSString stringWithFormat:@"%@ %lu", safeName, (unsigned long)index++];
        candidate = [directoryURL URLByAppendingPathComponent:[indexed stringByAppendingPathExtension:extension]];
    }
    return candidate;
}

static NSURL *YTPlusTempFileURL(NSString *extension) {
    NSString *name = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:extension];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

static NSInteger YTPlusResFromQuality(NSString *quality);
static NSInteger YTPlusFPSFromQuality(NSString *quality);
static NSInteger YTPlusNormalizedFPS(NSInteger fps);
static NSInteger YTPlusDisplayHeight(NSInteger height);
static NSString *YTPlusQualityLabel(NSInteger height, NSInteger fps, NSString *fallback);
static BOOL YTPlusFFmpegKitAvailable(void);

static unsigned long long YTPlusDurationMs(NSURL *url) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    if (!CMTIME_IS_NUMERIC(asset.duration) || !CMTIME_IS_VALID(asset.duration)) return 0;
    Float64 seconds = CMTimeGetSeconds(asset.duration);
    if (!isfinite(seconds) || seconds <= 0.0) return 0;
    return (unsigned long long)llround(seconds * 1000.0);
}

static NSString *YTPlusDurationSecs(unsigned long long durationMs) {
    return [NSString stringWithFormat:@"%.3f", (double)durationMs / 1000.0];
}

static BOOL YTPlusCMTimeUsable(CMTime time) {
    if (!CMTIME_IS_VALID(time) || !CMTIME_IS_NUMERIC(time) || CMTIME_IS_INDEFINITE(time)) return NO;
    Float64 seconds = CMTimeGetSeconds(time);
    return isfinite(seconds) && seconds > 0.0;
}

static CMTime YTPlusMinDuration(CMTime first, CMTime second) {
    BOOL firstOK = YTPlusCMTimeUsable(first);
    BOOL secondOK = YTPlusCMTimeUsable(second);
    if (firstOK && secondOK) return CMTIME_COMPARE_INLINE(first, <, second) ? first : second;
    if (firstOK) return first;
    if (secondOK) return second;
    return kCMTimeInvalid;
}

static CMTime YTPlusExportDuration(AVAsset *videoAsset, AVAsset *audioAsset, unsigned long long expectedDurationMs) {
    CMTime duration = kCMTimeInvalid;
    if (expectedDurationMs > 0)
        duration = CMTimeMakeWithSeconds((double)expectedDurationMs / 1000.0, 600);

    CMTime videoDuration = YTPlusMinDuration(videoAsset.duration, [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject].timeRange.duration);
    CMTime audioDuration = audioAsset ? YTPlusMinDuration(audioAsset.duration, [[audioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject].timeRange.duration) : kCMTimeInvalid;
    CMTime mediaDuration = audioAsset ? YTPlusMinDuration(videoDuration, audioDuration) : videoDuration;

    if (!YTPlusCMTimeUsable(duration)) return mediaDuration;
    if (YTPlusCMTimeUsable(mediaDuration) && CMTIME_COMPARE_INLINE(duration, >, mediaDuration))
        return mediaDuration;
    return duration;
}

static NSMutableArray <NSString *> *YTPlusFFmpegKitLoadEntries(void) {
    static NSMutableArray <NSString *> *entries = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        entries = [NSMutableArray array];
    });
    return entries;
}

static void YTPlusAppendFFmpegEntry(NSString *format, ...) {
    if (format.length == 0) return;

    va_list arguments;
    va_start(arguments, format);
    NSString *entry = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    if (entry.length == 0) return;

    NSMutableArray <NSString *> *entries = YTPlusFFmpegKitLoadEntries();
    @synchronized(entries) {
        [entries addObject:entry];
        if (entries.count > 220)
            [entries removeObjectsInRange:NSMakeRange(0, entries.count - 220)];
    }
}

static NSArray <NSString *> *YTPlusFFmpegKitSearchDirectories(void) {
    NSMutableOrderedSet <NSString *> *directories = [NSMutableOrderedSet orderedSet];
    
    // Path to YouTubePlusRevanced.bundle/Frameworks inside the main app bundle
    NSString *bundlePath = [[NSBundle.mainBundle resourcePath] stringByAppendingPathComponent:@"YouTubePlusRevanced.bundle"];
    NSString *frameworksInsideBundle = [bundlePath stringByAppendingPathComponent:@"Frameworks"];
    
    // Safety check: only add if the directory actually exists
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksInsideBundle isDirectory:&isDir] && isDir) {
        [directories addObject:frameworksInsideBundle];
    }

    return directories.array;
}

static void YTPlusDlopenPath(NSString *path, BOOL requireExistingFile) {
    if (path.length == 0) return;
    if (requireExistingFile && ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        YTPlusAppendFFmpegEntry(@"missing %@", path);
        return;
    }

    dlerror();
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    const char *error = dlerror();
    if (handle) {
        YTPlusAppendFFmpegEntry(@"loaded %@", path);
    } else {
        YTPlusAppendFFmpegEntry(@"failed %@\n  dlerror=%@", path, error ? [NSString stringWithUTF8String:error] : @"unknown");
    }
}

static void YTPlusDlopenPathIfPresent(NSString *path) {
    YTPlusDlopenPath(path, YES);
}

static void YTPlusLoadFrameworkBin(NSString *directory, NSString *frameworkName, NSString *binaryName) {
    if (directory.length == 0 || frameworkName.length == 0 || binaryName.length == 0) return;
    YTPlusDlopenPathIfPresent([[directory stringByAppendingPathComponent:[frameworkName stringByAppendingString:@".framework"]] stringByAppendingPathComponent:binaryName]);
    YTPlusDlopenPathIfPresent([[directory stringByAppendingPathComponent:[frameworkName stringByAppendingString:@".framework"]] stringByAppendingPathComponent:frameworkName]);
}

static void YTPlusLoadFFmpegIfNeeded(void) {
    static BOOL attempted = NO;
    if (NSClassFromString(@"FFmpegKit")) return;
    if (attempted) return;
    attempted = YES;

    YTPlusAppendFFmpegEntry(@"[YTPlus] Starting bundled FFmpegKit load...");

    // Order is important: load dependencies (avutil, etc.) before the main toolkit
    NSArray <NSArray <NSString *> *> *frameworks = @[
        @[@"libavutil", @"libavutil"],
        @[@"libswresample", @"libswresample"],
        @[@"libswscale", @"libswscale"],
        @[@"libavcodec", @"libavcodec"],
        @[@"libavformat", @"libavformat"],
        @[@"libavfilter", @"libavfilter"],
        @[@"libavdevice", @"libavdevice"],
        @[@"ffmpegkit", @"ffmpegkit"],
        @[@"FFmpegKit", @"FFmpegKit"],
    ];

    NSArray *searchDirs = YTPlusFFmpegKitSearchDirectories();
    if (searchDirs.count == 0) {
        YTPlusAppendFFmpegEntry(@"[YTPlus] Error: Bundled Frameworks directory not found.");
        return;
    }

    // Only iterate through our controlled bundle directory
    for (NSString *directory in searchDirs) {
        for (NSArray <NSString *> *framework in frameworks) {
            // This helper uses dlopen on the direct path within our bundle
            YTPlusLoadFrameworkBin(directory, framework.firstObject, framework.lastObject);
        }
        
        if (NSClassFromString(@"FFmpegKit")) {
            YTPlusAppendFFmpegEntry(@"[YTPlus] Success: FFmpegKit loaded from bundle.");
            return;
        }
    }

    YTPlusAppendFFmpegEntry(@"[YTPlus] Critical: FFmpegKit could not be found in YouTubePlusRevanced.bundle.");
}

static Class YTPlusFFmpegKitClass(void) {
    Class ffmpegKitClass = NSClassFromString(@"FFmpegKit");
    if (!ffmpegKitClass) {
        YTPlusLoadFFmpegIfNeeded();
        ffmpegKitClass = NSClassFromString(@"FFmpegKit");
    }
    return ffmpegKitClass;
}

static BOOL YTPlusFFmpegKitAvailable(void) {
    Class ffmpegKitClass = YTPlusFFmpegKitClass();
    return ffmpegKitClass && [ffmpegKitClass respondsToSelector:@selector(executeWithArgumentsAsync:withCompleteCallback:withLogCallback:withStatisticsCallback:)];
}

static NSString *YTPlusFFmpegKitDiagnosticText(YTPlusAudioOutputFormat *outputFormat, YTPlusMediaFormat *sourceFormat, NSString *videoID) {
    YTPlusLoadFFmpegIfNeeded();

    Class ffmpegKitClass = NSClassFromString(@"FFmpegKit");
    SEL executeSelector = @selector(executeWithArgumentsAsync:withCompleteCallback:withLogCallback:withStatisticsCallback:);
    NSMutableArray <NSString *> *lines = [NSMutableArray array];
    NSBundle *mainBundle = NSBundle.mainBundle;
    NSString *resourcePath = mainBundle.resourcePath ?: @"";
    NSString *privateFrameworksPath = mainBundle.privateFrameworksPath ?: @"";
    NSString *executablePath = mainBundle.executablePath ?: @"";
    NSString *bundlePath = [resourcePath stringByAppendingPathComponent:@"YouTubePlusRevanced.bundle"];
    NSString *packageFrameworkPath = [resourcePath stringByAppendingPathComponent:@"YouTubePlusRevanced.bundle/Frameworks"];

    [lines addObject:@"FFmpegKit lookup"];
    [lines addObject:[NSString stringWithFormat:@"videoID=%@", videoID ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"requestedFormat=%@ (%@)", outputFormat.title ?: @"", outputFormat.identifier ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"sourceMime=%@", sourceFormat.mimeType ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"sourceQuality=%@", sourceFormat.qualityLabel ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"sourceBytes=%llu", sourceFormat.contentLength]];
    [lines addObject:[NSString stringWithFormat:@"mainBundle=%@", mainBundle.bundlePath ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"resourcePath=%@", resourcePath]];
    [lines addObject:[NSString stringWithFormat:@"privateFrameworksPath=%@", privateFrameworksPath]];
    [lines addObject:[NSString stringWithFormat:@"executablePath=%@", executablePath]];
    [lines addObject:[NSString stringWithFormat:@"YouTubePlusRevanced.bundle exists=%@", [NSFileManager.defaultManager fileExistsAtPath:bundlePath] ? @"YES" : @"NO"]];
    [lines addObject:[NSString stringWithFormat:@"YouTubePlusRevanced.bundle/Frameworks exists=%@", [NSFileManager.defaultManager fileExistsAtPath:packageFrameworkPath] ? @"YES" : @"NO"]];
    [lines addObject:[NSString stringWithFormat:@"FFmpegKit class=%@", ffmpegKitClass ? @"YES" : @"NO"]];
    [lines addObject:[NSString stringWithFormat:@"FFmpegKit execute selector=%@", [ffmpegKitClass respondsToSelector:executeSelector] ? @"YES" : @"NO"]];
    [lines addObject:[NSString stringWithFormat:@"ReturnCode class=%@", NSClassFromString(@"ReturnCode") ? @"YES" : @"NO"]];
    [lines addObject:@"searchDirectories:"];
    for (NSString *directory in YTPlusFFmpegKitSearchDirectories()) {
        BOOL isDirectory = NO;
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory];
        [lines addObject:[NSString stringWithFormat:@"  %@ exists=%@ directory=%@", directory, exists ? @"YES" : @"NO", isDirectory ? @"YES" : @"NO"]];
    }

    NSMutableArray <NSString *> *entries = YTPlusFFmpegKitLoadEntries();
    [lines addObject:@"dlopenAttempts:"];
    @synchronized(entries) {
        [lines addObjectsFromArray:entries];
    }
    return [lines componentsJoinedByString:@"\n"];
}

static void YTPlusCancelFFmpeg(void) {
    Class ffmpegKitClass = YTPlusFFmpegKitClass();
    if ([ffmpegKitClass respondsToSelector:@selector(cancel)])
        ((void (*)(Class, SEL))objc_msgSend)(ffmpegKitClass, @selector(cancel));
}

static NSError *YTPlusFFmpegError(id session) {
    NSString *failure = YTPlusStringFromSel(session, @selector(getFailStackTrace));
    NSString *message = failure.length ? failure : @"FFmpeg failed";
    return [NSError errorWithDomain:@"YTPlus" code:7 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL YTPlusIsPhotosVideo(NSString *extension) {
    NSString *lower = extension.lowercaseString ?: @"";
    return [@[@"mp4", @"m4v", @"mov"] containsObject:lower];
}

static BOOL YTPlusStartFFmpegMerge(NSURL *videoURL, NSURL *audioURL, NSURL *outputURL, unsigned long long durationMs, void (^progress)(float progress), YTPlusMergeCompletion completion) {
    Class ffmpegKitClass = YTPlusFFmpegKitClass();
    SEL executeSelector = @selector(executeWithArgumentsAsync:withCompleteCallback:withLogCallback:withStatisticsCallback:);
    if (![ffmpegKitClass respondsToSelector:executeSelector]) return NO;

    NSMutableArray *arguments = [@[
        @"-y",
        @"-i", videoURL.path,
        @"-i", audioURL.path,
        @"-map", @"0:v:0",
        @"-map", @"1:a:0",
    ] mutableCopy];
    if (durationMs > 0)
        [arguments addObjectsFromArray:@[@"-t", YTPlusDurationSecs(durationMs)]];
    [arguments addObjectsFromArray:@[
        @"-c", @"copy",
        @"-shortest",
        @"-avoid_negative_ts", @"make_zero",
    ]];
    if (YTPlusIsPhotosVideo(outputURL.pathExtension))
        [arguments addObjectsFromArray:@[@"-movflags", @"+faststart"]];
    [arguments addObject:outputURL.path];

    id completeBlock = [^(id session) {
        Class returnCodeClass = NSClassFromString(@"ReturnCode");
        id returnCode = YTPlusObjectFromSel(session, @selector(getReturnCode));
        BOOL success = NO;
        if ([returnCodeClass respondsToSelector:@selector(isSuccess:)])
            success = ((BOOL (*)(Class, SEL, id))objc_msgSend)(returnCodeClass, @selector(isSuccess:), returnCode);

        NSError *error = success ? nil : YTPlusFFmpegError(session);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && [NSFileManager.defaultManager fileExistsAtPath:outputURL.path]) {
                completion(YES, nil);
            } else {
                completion(NO, error ?: [NSError errorWithDomain:@"YTPlus" code:7 userInfo:@{NSLocalizedDescriptionKey: @"Merge failed"}]);
            }
        });
    } copy];

    id statisticsBlock = durationMs ? [^(id statistics) {
        if (!progress || ![statistics respondsToSelector:@selector(getTime)]) return;
        double timeMs = ((double (*)(id, SEL))objc_msgSend)(statistics, @selector(getTime));
        if (!isfinite(timeMs) || timeMs <= 0.0) return;
        float mergeProgress = 0.985f + (0.01f * fminf((float)(timeMs / (double)durationMs), 1.0f));
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(mergeProgress);
        });
    } copy] : nil;

    ((id (*)(Class, SEL, NSArray *, id, id, id))objc_msgSend)(ffmpegKitClass, executeSelector, arguments, completeBlock, nil, statisticsBlock);
    return YES;
}

static BOOL YTPlusStartFFmpegConvert(NSURL *inputURL, NSURL *outputURL, YTPlusAudioOutputFormat *outputFormat, unsigned long long durationMs, void (^progress)(float progress), YTPlusMergeCompletion completion) {
    Class ffmpegKitClass = YTPlusFFmpegKitClass();
    SEL executeSelector = @selector(executeWithArgumentsAsync:withCompleteCallback:withLogCallback:withStatisticsCallback:);
    if (![ffmpegKitClass respondsToSelector:executeSelector] || outputFormat.ffmpegArguments.count == 0) return NO;

    NSMutableArray *arguments = [@[@"-y", @"-i", inputURL.path] mutableCopy];
    [arguments addObjectsFromArray:outputFormat.ffmpegArguments];
    [arguments addObject:outputURL.path];

    id completeBlock = [^(id session) {
        Class returnCodeClass = NSClassFromString(@"ReturnCode");
        id returnCode = YTPlusObjectFromSel(session, @selector(getReturnCode));
        BOOL success = NO;
        if ([returnCodeClass respondsToSelector:@selector(isSuccess:)])
            success = ((BOOL (*)(Class, SEL, id))objc_msgSend)(returnCodeClass, @selector(isSuccess:), returnCode);

        NSError *error = success ? nil : YTPlusFFmpegError(session);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && [NSFileManager.defaultManager fileExistsAtPath:outputURL.path]) {
                completion(YES, nil);
            } else {
                completion(NO, error ?: [NSError errorWithDomain:@"YTPlus" code:13 userInfo:@{NSLocalizedDescriptionKey: @"Conversion failed"}]);
            }
        });
    } copy];

    id statisticsBlock = durationMs ? [^(id statistics) {
        if (!progress || ![statistics respondsToSelector:@selector(getTime)]) return;
        double timeMs = ((double (*)(id, SEL))objc_msgSend)(statistics, @selector(getTime));
        if (!isfinite(timeMs) || timeMs <= 0.0) return;
        float convertProgress = 0.985f + (0.01f * fminf((float)(timeMs / (double)durationMs), 1.0f));
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(convertProgress);
        });
    } copy] : nil;

    ((id (*)(Class, SEL, NSArray *, id, id, id))objc_msgSend)(ffmpegKitClass, executeSelector, arguments, completeBlock, nil, statisticsBlock);
    return YES;
}

static NSString *YTPlusMimeDetail(NSString *mimeType) {
    NSString *lower = mimeType.lowercaseString ?: @"";
    if ([lower containsString:@"mp4"]) return @"MP4";
    if ([lower containsString:@"webm"]) return @"WebM";
    if ([lower containsString:@"mp3"]) return @"MP3";
    if ([lower containsString:@"aac"]) return @"AAC";
    return mimeType.length ? mimeType : @"Stream";
}

static NSString *YTPlusExtForFormat(YTPlusMediaFormat *format, NSString *fallbackExtension) {
    NSString *lower = format.mimeType.lowercaseString ?: @"";
    if ([lower containsString:@"webm"]) return @"webm";
    if ([lower containsString:@"matroska"]) return @"mkv";
    if ([lower containsString:@"quicktime"]) return @"mov";
    if ([lower containsString:@"m4a"]) return @"m4a";
    if ([lower containsString:@"mp4"]) return @"mp4";
    return fallbackExtension ?: @"mp4";
}

static BOOL YTPlusIsMP4Family(YTPlusMediaFormat *format) {
    NSString *mime = format.mimeType.lowercaseString ?: @"";
    NSString *extension = YTPlusExtForFormat(format, @"").lowercaseString ?: @"";
    return [mime containsString:@"mp4"] || [mime containsString:@"m4a"] || [mime containsString:@"quicktime"] || [@[@"mp4", @"m4a", @"m4v", @"mov"] containsObject:extension];
}

static BOOL YTPlusIsWebM(YTPlusMediaFormat *format) {
    NSString *mime = format.mimeType.lowercaseString ?: @"";
    NSString *extension = YTPlusExtForFormat(format, @"").lowercaseString ?: @"";
    return [mime containsString:@"webm"] || [extension isEqualToString:@"webm"];
}

static NSString *YTPlusMergedExt(YTPlusMediaFormat *videoFormat, YTPlusMediaFormat *audioFormat) {
    if (YTPlusIsMP4Family(videoFormat) && YTPlusIsMP4Family(audioFormat)) return @"mp4";
    if (YTPlusIsWebM(videoFormat) && YTPlusIsWebM(audioFormat)) return @"webm";
    return @"mkv";
}

static BOOL YTPlusCanUseAVF(NSURL *fileURL) {
    return YTPlusIsPhotosVideo(fileURL.pathExtension);
}

static BOOL YTPlusCanSavePhotos(NSURL *fileURL) {
    return YTPlusIsPhotosVideo(fileURL.pathExtension);
}

static YTPlusAudioOutputFormat *YTPlusAudioOutputFormatMake(NSString *identifier, NSString *title, NSString *subtitle, NSString *fileExtension, NSArray <NSString *> *ffmpegArguments, BOOL passthroughWhenCompatible, BOOL supported) {
    YTPlusAudioOutputFormat *format = [YTPlusAudioOutputFormat new];
    format.identifier = identifier;
    format.title = title;
    format.subtitle = subtitle;
    format.fileExtension = fileExtension;
    format.ffmpegArguments = ffmpegArguments;
    format.passthroughWhenCompatible = passthroughWhenCompatible;
    format.supported = supported;
    return format;
}

static NSArray <YTPlusAudioOutputFormat *> *YTPlusAudioOutputFormats(void) {
    static NSArray <YTPlusAudioOutputFormat *> *formats = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formats = @[
            YTPlusAudioOutputFormatMake(@"m4a", @"M4A", @"AAC container, passthrough when possible", @"m4a", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"aac", @"-b:a", @"192k", @"-movflags", @"+faststart"], YES, YES),
            YTPlusAudioOutputFormatMake(@"aac", @"AAC", @"Lossy (192k)", @"aac", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"aac", @"-b:a", @"192k", @"-f", @"adts"], YES, YES),
            YTPlusAudioOutputFormatMake(@"mp3", @"MP3", @"Lossy, widely compatible", @"mp3", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"libmp3lame", @"-q:a", @"2"], NO, YES),
            YTPlusAudioOutputFormatMake(@"opus", @"Opus", @"Lossy, small file size", @"opus", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"libopus", @"-b:a", @"160k", @"-vbr", @"on"], NO, YES),
            YTPlusAudioOutputFormatMake(@"ogg", @"OGG", @"Vorbis lossy", @"ogg", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"libvorbis", @"-q:a", @"6"], NO, YES),
            YTPlusAudioOutputFormatMake(@"flac", @"FLAC", @"Lossless compressed", @"flac", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"flac", @"-compression_level", @"8"], NO, YES),
            YTPlusAudioOutputFormatMake(@"alac", @"ALAC", @"Apple lossless (M4A)", @"m4a", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"alac", @"-movflags", @"+faststart"], NO, YES),
            YTPlusAudioOutputFormatMake(@"wav", @"WAV", @"Uncompressed PCM", @"wav", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"pcm_s24le"], NO, YES),
            YTPlusAudioOutputFormatMake(@"aiff", @"AIFF", @"Apple PCM", @"aiff", @[@"-map", @"0:a:0", @"-vn", @"-c:a", @"pcm_s24be"], NO, YES),
        ];
    });
    return formats;
}

static YTPlusAudioOutputFormat *YTPlusDefaultAudioFmt(void) {
    return [YTPlusAudioOutputFormats() firstObject];
}

static BOOL YTPlusAudioOutputFormatCanPassthrough(YTPlusAudioOutputFormat *outputFormat, YTPlusMediaFormat *sourceFormat) {
    if (!outputFormat.passthroughWhenCompatible) return NO;
    NSString *identifier = outputFormat.identifier.lowercaseString ?: @"";
    NSString *mime = sourceFormat.mimeType.lowercaseString ?: @"";
    NSString *extension = YTPlusExtForFormat(sourceFormat, @"").lowercaseString ?: @"";
    if ([identifier isEqualToString:@"m4a"] || [identifier isEqualToString:@"aac"])
        return [extension isEqualToString:@"m4a"] || [mime containsString:@"mp4"] || [mime containsString:@"m4a"];
    return NO;
}

static NSString *YTPlusAudioOutExt(YTPlusAudioOutputFormat *outputFormat, YTPlusMediaFormat *sourceFormat, BOOL passthrough) {
    NSString *identifier = outputFormat.identifier.lowercaseString ?: @"";
    NSString *mime = sourceFormat.mimeType.lowercaseString ?: @"";
    if (passthrough && ([identifier isEqualToString:@"m4a"] || [identifier isEqualToString:@"aac"]) && ([mime containsString:@"mp4"] || [mime containsString:@"m4a"]))
        return @"m4a";
    return outputFormat.fileExtension ?: YTPlusExtForFormat(sourceFormat, @"m4a");
}

static NSString *YTPlusAudioSubtitle(YTPlusAudioOutputFormat *outputFormat) {
    return [NSString stringWithFormat:@"%@", outputFormat.subtitle];
}

static NSString *YTPlusFormatSubtitle(YTPlusMediaFormat *format) {
    NSMutableArray *parts = [NSMutableArray array];
    NSString *language = format.languageName.length ? format.languageName : format.languageCode;
    if (language.length) [parts addObject:language];
    if (format.drcAudio) [parts addObject:@"DRC"];
    NSString *detail = YTPlusMimeDetail(format.mimeType);
    if (detail.length) [parts addObject:detail];
    NSString *size = YTPlusByteCount(format.contentLength);
    if (size.length) [parts addObject:size];
    return [parts componentsJoinedByString:@" - "];
}

static NSString *YTPlusVideoID(YTPlayerViewController *player) {
    NSString *videoID = [player contentVideoID];
    if (videoID.length == 0)
        videoID = [player currentVideoID];
    return videoID;
}

static NSArray *YTPlusPlayerResponses(YTPlayerViewController *player) {
    NSMutableArray *responses = [NSMutableArray array];
    id response = YTPlusObjectFromSel(player, @selector(contentPlayerResponse));
    if (response) [responses addObject:response];

    id activeVideo = YTPlusObjectFromSel(player, @selector(activeVideo));
    response = YTPlusObjectFromSel(activeVideo, @selector(contentPlayerResponse));
    if (response && ![responses containsObject:response]) [responses addObject:response];
    return responses.copy;
}

// Where is this going to?
static NSArray *YTPlusCaptionTracks(YTPlayerViewController *player) {
    for (id response in YTPlusPlayerResponses(player)) {
        id playerData = YTPlusObjectFromSel(response, @selector(playerData)) ?: response;
        id captions = YTPlusObjectFromSel(playerData, @selector(captions));
        id tracklistRenderer = YTPlusObjectFromSel(captions, @selector(playerCaptionsTracklistRenderer));
        NSArray *tracks = YTPlusObjectFromSel(tracklistRenderer, @selector(captionTracksArray));
        if (tracks.count > 0) return tracks;
    }
    return nil;
}

static id YTPlusPlayerData(YTPlayerViewController *player) {
    id response = YTPlusPlayerResponses(player).firstObject;
    id playerData = YTPlusObjectFromSel(response, @selector(playerData));
    return playerData ?: response;
}

static NSString *YTPlusVideoTitle(YTPlayerViewController *player) {
    id playerData = YTPlusPlayerData(player);
    id details = YTPlusObjectFromSel(playerData, @selector(videoDetails));
    NSString *title = YTPlusStringFromSel(details, @selector(title));
    NSString *author = YTPlusStringFromSel(details, @selector(author));
    if (author.length && title.length) {
        return [NSString stringWithFormat:@"%@ - %@", author, title];
    } else if (title.length) {
        return title;
    }
    NSString *videoID = YTPlusVideoID(player);
    return videoID.length ? [NSString stringWithFormat:@"YouTube %@", videoID] : @"YouTube Video";
}

static NSArray *YTPlusAdaptiveFormats(YTPlayerViewController *player) {
    NSMutableArray *formats = [NSMutableArray array];
    NSMutableSet *seenPointers = [NSMutableSet set];

    void (^appendFormats)(NSArray *) = ^(NSArray *candidateFormats) {
        if (![candidateFormats isKindOfClass:NSArray.class]) return;
        for (id format in candidateFormats) {
            NSString *key = [NSString stringWithFormat:@"%p", format];
            if ([seenPointers containsObject:key]) continue;
            [seenPointers addObject:key];
            [formats addObject:format];
        }
    };

    id activeVideo = YTPlusObjectFromSel(player, @selector(activeVideo));
    id streamingData = YTPlusObjectFromSel(activeVideo, @selector(streamingData));
    appendFormats(YTPlusObjectFromSel(streamingData, @selector(adaptiveStreams)));
    appendFormats(YTPlusObjectFromSel(activeVideo, @selector(selectableVideoFormats)));

    for (id response in YTPlusPlayerResponses(player)) {
        id playerData = YTPlusObjectFromSel(response, @selector(playerData)) ?: response;
        id responseStreamingData = YTPlusObjectFromSel(playerData, @selector(streamingData));
        appendFormats(YTPlusObjectFromSel(responseStreamingData, @selector(adaptiveFormatsArray)));
    }

    return formats.copy;
}

static YTPlusMediaFormat *YTPlusMediaFormatFromStream(id stream, BOOL video) {
    id formatStream = YTPlusObjectFromSel(stream, @selector(formatStream));
    NSString *url = YTPlusStringFromSel(stream, @selector(URL));
    if (url.length == 0) url = YTPlusStringFromSel(formatStream, @selector(URL));
    if (url.length == 0) url = YTPlusStringFromSel(stream, @selector(url));
    if (url.length == 0) url = YTPlusStringFromSel(formatStream, @selector(url));
    if (url.length == 0) return nil;

    NSString *mimeType = YTPlusStringFromSel(stream, @selector(mimeType));
    if (mimeType.length == 0) mimeType = YTPlusStringFromSel(formatStream, @selector(mimeType));
    NSString *lowerMime = mimeType.lowercaseString ?: @"";
    BOOL streamSaysVideo = YTPlusBoolFromSel(stream, @selector(isVideo)) || YTPlusBoolFromSel(formatStream, @selector(isVideo));
    BOOL streamSaysAudio = YTPlusBoolFromSel(stream, @selector(isAudio)) || YTPlusBoolFromSel(formatStream, @selector(isAudio));
    NSInteger itag = YTPlusIntFromSel(stream, @selector(itag));
    if (itag == 0) itag = YTPlusIntFromSel(formatStream, @selector(itag));

    NSSet *mp4VideoItags = [NSSet setWithObjects:@18, @22, @37, @38, @59, @78, @133, @134, @135, @136, @137, @160, @212, @264, @266, @298, @299, nil];
    NSSet *m4aAudioItags = [NSSet setWithObjects:@139, @140, @141, @256, @258, @325, @328, nil];
    BOOL itagMatches = video ? [mp4VideoItags containsObject:@(itag)] : [m4aAudioItags containsObject:@(itag)];
    BOOL typeMatches = video ? ([lowerMime containsString:@"video/"] || streamSaysVideo || itagMatches) : ([lowerMime containsString:@"audio/"] || streamSaysAudio || itagMatches);
    if (!typeMatches) return nil;

    BOOL mimeLooksMP4 = [lowerMime containsString:@"mp4"] || [lowerMime containsString:@"m4a"];
    BOOL canRemuxWithFFmpeg = YTPlusFFmpegKitAvailable();
    if (mimeType.length && !mimeLooksMP4 && !itagMatches && !canRemuxWithFFmpeg) return nil;

    YTPlusMediaFormat *format = [YTPlusMediaFormat new];
    format.source = stream;
    format.video = video;
    format.urlString = YTPlusURLWithCPN(url);
    format.mimeType = mimeType.length ? mimeType : (video ? @"video/mp4" : @"audio/mp4");
    NSInteger height = YTPlusIntFromSel(stream, @selector(height));
    if (height == 0) height = YTPlusIntFromSel(formatStream, @selector(height));
    NSInteger fps = YTPlusIntFromSel(stream, @selector(fps));
    if (fps == 0) fps = YTPlusIntFromSel(formatStream, @selector(fps));
    if (fps == 0) fps = YTPlusIntFromSel(stream, @selector(framesPerSecond));
    if (fps == 0) fps = YTPlusIntFromSel(formatStream, @selector(framesPerSecond));
    if (fps == 0) fps = YTPlusIntFromSel(stream, @selector(frameRate));
    if (fps == 0) fps = YTPlusIntFromSel(formatStream, @selector(frameRate));
    fps = YTPlusNormalizedFPS(fps);
    format.fps = fps;
    format.qualityLabel = YTPlusStringFromSel(stream, @selector(qualityLabel));
    if (format.qualityLabel.length == 0) format.qualityLabel = YTPlusStringFromSel(formatStream, @selector(qualityLabel));
    if (video) {
        NSInteger labelHeight = YTPlusResFromQuality(format.qualityLabel);
        NSInteger labelFPS = YTPlusFPSFromQuality(format.qualityLabel);
        if (labelHeight == 960) format.qualityLabel = YTPlusQualityLabel(labelHeight, fps ?: labelFPS, nil);
        else if (labelFPS == 0 && fps > 0) format.qualityLabel = YTPlusQualityLabel(height, fps, format.qualityLabel);
        if (format.qualityLabel.length == 0) format.qualityLabel = YTPlusQualityLabel(height, fps, nil);
    }
    if (format.qualityLabel.length == 0 && !video) format.qualityLabel = @"Audio";
    if (!video) {
        // Get the audioTrack sub-object first — it contains language and default info
        id audioTrackObj = YTPlusObjectFromSel(stream, @selector(audioTrack));
        if (!audioTrackObj) audioTrackObj = YTPlusObjectFromSel(formatStream, @selector(audioTrack));

        // Extract language code from multiple sources
        NSString *languageCode = YTPlusStringFromSel(stream, @selector(languageCode));
        if (languageCode.length == 0) languageCode = YTPlusStringFromSel(formatStream, @selector(languageCode));
        if (languageCode.length == 0) languageCode = YTPlusStringFromSel(stream, @selector(language));
        if (languageCode.length == 0) languageCode = YTPlusStringFromSel(formatStream, @selector(language));
        // Try audioTrack object's ID — YouTube uses format "en.1", "ja.1", "en.drc.1"
        if (languageCode.length == 0 && audioTrackObj) {
            NSString *trackID = YTPlusStringFromSel(audioTrackObj, @selector(id_p));
            if (!trackID.length) trackID = YTPlusStringFromSel(audioTrackObj, @selector(id));
            if (trackID.length == 0) trackID = YTPlusStringFromSel(audioTrackObj, @selector(identifier));
            if (trackID.length == 0) trackID = YTPlusStringFromSel(audioTrackObj, @selector(audioTrackId));
            if (trackID.length >= 2) {
                // Extract language prefix from track ID like "en.1" -> "en"
                NSString *prefix = [[trackID componentsSeparatedByString:@"."] firstObject];
                if (prefix.length >= 2 && prefix.length <= 5) languageCode = prefix;
            }
        }
        format.languageCode = languageCode;

        NSString *languageName = YTPlusStringFromSel(stream, @selector(languageName));
        if (languageName.length == 0) languageName = YTPlusStringFromSel(formatStream, @selector(languageName));
        if (languageName.length == 0) languageName = YTPlusStringFromSel(stream, @selector(displayName));
        if (languageName.length == 0) languageName = YTPlusStringFromSel(formatStream, @selector(displayName));
        // Try audioTrack object's displayName (e.g. "English", "Japanese")
        if (languageName.length == 0 && audioTrackObj) {
            languageName = YTPlusStringFromSel(audioTrackObj, @selector(displayName));
        }
        format.languageName = languageName.length ? languageName : languageCode;

        NSMutableArray *audioTraits = [NSMutableArray array];
        for (NSString *value in @[
            mimeType ?: @"",
            format.qualityLabel ?: @"",
            YTPlusStringFromSel(stream, @selector(audioTrack)) ?: @"",
            YTPlusStringFromSel(formatStream, @selector(audioTrack)) ?: @"",
            YTPlusStringFromSel(stream, @selector(audioTrackType)) ?: @"",
            YTPlusStringFromSel(formatStream, @selector(audioTrackType)) ?: @"",
            YTPlusStringFromSel(stream, @selector(audioTrackDisplayName)) ?: @"",
            YTPlusStringFromSel(formatStream, @selector(audioTrackDisplayName)) ?: @"",
        ]) {
            if (value.length) [audioTraits addObject:value];
        }
        format.drcAudio = [[audioTraits componentsJoinedByString:@" "] localizedCaseInsensitiveContainsString:@"drc"];

        // Detect default/original audio track
        NSString *traitsJoined = [audioTraits componentsJoinedByString:@" "];
        BOOL isOriginal = [traitsJoined localizedCaseInsensitiveContainsString:@"original"];
        BOOL isDefault = YTPlusBoolFromSel(stream, @selector(audioIsDefault)) || YTPlusBoolFromSel(formatStream, @selector(audioIsDefault));
        if (audioTrackObj && [audioTrackObj respondsToSelector:@selector(audioIsDefault)]) {
            isDefault = isDefault || YTPlusBoolFromSel(audioTrackObj, @selector(audioIsDefault));
        }
        // No explicit language and no track type = single-language video, treat as default
        if (!isDefault && !isOriginal && format.languageCode.length == 0) isDefault = YES;
        format.isDefaultAudio = isDefault || isOriginal;
    }
    if (YTPlusBoolFromSel(stream, @selector(hasContentLength)) || [stream respondsToSelector:@selector(contentLength)])
        format.contentLength = YTPlusULLFromSel(stream, @selector(contentLength));
    if (format.contentLength == 0 && (YTPlusBoolFromSel(formatStream, @selector(hasContentLength)) || [formatStream respondsToSelector:@selector(contentLength)]))
        format.contentLength = YTPlusULLFromSel(formatStream, @selector(contentLength));
    format.durationMs = YTPlusULLFromSel(stream, @selector(approxDurationMs));
    if (format.durationMs == 0) format.durationMs = YTPlusULLFromSel(formatStream, @selector(approxDurationMs));

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSDictionary *streamHeaders = YTPlusObjectFromSel(stream, @selector(httpHeaders));
    if (![streamHeaders isKindOfClass:NSDictionary.class]) streamHeaders = YTPlusObjectFromSel(formatStream, @selector(httpHeaders));
    if (![streamHeaders isKindOfClass:NSDictionary.class]) streamHeaders = YTPlusObjectFromSel(stream, @selector(headers));
    if (![streamHeaders isKindOfClass:NSDictionary.class]) streamHeaders = YTPlusObjectFromSel(formatStream, @selector(headers));
    if ([streamHeaders isKindOfClass:NSDictionary.class]) {
        for (id key in streamHeaders) {
            id value = streamHeaders[key];
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class])
                headers[key] = value;
        }
    }
    if (!YTPlusHTTPHeadersContainField(headers, @"Origin"))
        headers[@"Origin"] = @"https://www.youtube.com";
    if (!YTPlusHTTPHeadersContainField(headers, @"Referer"))
        headers[@"Referer"] = @"https://www.youtube.com/";
    format.httpHeaders = headers;
    return format;
}

static NSInteger YTPlusResFromQuality(NSString *quality) {
    NSScanner *scanner = [NSScanner scannerWithString:quality ?: @""];
    NSInteger value = 0;
    [scanner scanInteger:&value];
    return value;
}

static NSInteger YTPlusFPSFromQuality(NSString *quality) {
    NSString *lower = quality.lowercaseString ?: @"";
    NSRange pRange = [lower rangeOfString:@"p"];
    if (pRange.location != NSNotFound && pRange.location + 1 < lower.length) {
        NSString *afterP = [lower substringFromIndex:pRange.location + 1];
        NSScanner *scanner = [NSScanner scannerWithString:afterP];
        NSInteger fps = 0;
        if ([scanner scanInteger:&fps] && fps > 0) return fps;
    }
    if ([lower containsString:@"60fps"] || [lower containsString:@"60 fps"]) return 60;
    if ([lower containsString:@"30fps"] || [lower containsString:@"30 fps"]) return 30;
    return 0;
}

static NSInteger YTPlusNormalizedFPS(NSInteger fps) {
    if (fps >= 50 && fps <= 61) return 60;
    if (fps >= 24 && fps <= 31) return 30;
    return fps;
}

static NSInteger YTPlusDisplayHeight(NSInteger height) {
    if (height >= 900 && height < 1080) return 1080;
    return height;
}

static NSString *YTPlusQualityLabel(NSInteger height, NSInteger fps, NSString *fallback) {
    height = YTPlusDisplayHeight(height);
    fps = YTPlusNormalizedFPS(fps);
    if (height > 0 && fps > 0) return [NSString stringWithFormat:@"%ldp%ld", (long)height, (long)fps];
    if (height > 0) return [NSString stringWithFormat:@"%ldp", (long)height];
    if (fallback.length && fps > 0 && ![fallback.lowercaseString containsString:@"fps"])
        return [NSString stringWithFormat:@"%@ %ldfps", fallback, (long)fps];
    return fallback;
}

static NSArray <YTPlusMediaFormat *> *YTPlusFormatsForPlayer(YTPlayerViewController *player, BOOL video) {
    NSMutableArray *formats = [NSMutableArray array];
    for (id stream in YTPlusAdaptiveFormats(player)) {
        YTPlusMediaFormat *format = YTPlusMediaFormatFromStream(stream, video);
        if (format) [formats addObject:format];
    }

    [formats sortUsingComparator:^NSComparisonResult(YTPlusMediaFormat *left, YTPlusMediaFormat *right) {
        if (video) {
            NSInteger leftRes = YTPlusResFromQuality(left.qualityLabel);
            NSInteger rightRes = YTPlusResFromQuality(right.qualityLabel);
            if (leftRes != rightRes) return leftRes > rightRes ? NSOrderedAscending : NSOrderedDescending;
            NSInteger leftFPS = left.fps ?: YTPlusFPSFromQuality(left.qualityLabel);
            NSInteger rightFPS = right.fps ?: YTPlusFPSFromQuality(right.qualityLabel);
            if (leftFPS != rightFPS) return leftFPS > rightFPS ? NSOrderedAscending : NSOrderedDescending;
        }
        
        BOOL leftMP4 = YTPlusIsMP4Family(left);
        BOOL rightMP4 = YTPlusIsMP4Family(right);
        if (leftMP4 != rightMP4) return leftMP4 ? NSOrderedAscending : NSOrderedDescending;
        
        // For audio: prefer the default/original language track
        if (!video && left.isDefaultAudio != right.isDefaultAudio)
            return left.isDefaultAudio ? NSOrderedAscending : NSOrderedDescending;

        if (!video && ytpBool(@"downloadPreferDRC") && left.drcAudio != right.drcAudio)
            return left.drcAudio ? NSOrderedAscending : NSOrderedDescending;
        if (left.contentLength != right.contentLength)
            return left.contentLength > right.contentLength ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableArray *unique = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (YTPlusMediaFormat *format in formats) {
        NSInteger fps = format.fps ?: YTPlusFPSFromQuality(format.qualityLabel);
        NSString *key = video
            ? [NSString stringWithFormat:@"%@-%ld-%@", format.qualityLabel ?: @"", (long)fps, YTPlusMimeDetail(format.mimeType)]
            : [NSString stringWithFormat:@"%@-%@-%@-%@", format.qualityLabel ?: @"", format.languageCode ?: @"", format.drcAudio ? @"drc" : @"std", YTPlusMimeDetail(format.mimeType)];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [unique addObject:format];
    }
    return unique.copy;
}

static YTPlusMediaFormat *YTPlusBestAudio(YTPlayerViewController *player) {
    NSArray <YTPlusMediaFormat *> *audioFormats = YTPlusFormatsForPlayer(player, NO);
    if (audioFormats.count <= 1) return audioFormats.firstObject;

    // Strategy 1: Get the audio track the player is currently using
    // This is the most reliable way — download what the user is hearing
    @try {
        id selectedTrack = nil;

        // For regular videos: contentVideoPlayerOverlay.selectedAudioTrack
        id overlay = YTPlusObjectFromSel(player, @selector(contentVideoPlayerOverlay));
        if (!overlay) overlay = YTPlusObjectFromSel(player, @selector(activeVideoPlayerOverlay));
        if (overlay) selectedTrack = YTPlusObjectFromSel(overlay, @selector(selectedAudioTrack));

        // For Shorts: walk the responder chain to find YTReelPlayerViewController
        // which has selectedAudioTrack directly
        if (!selectedTrack) {
            UIResponder *r = (UIResponder *)player;
            for (int i = 0; i < 15 && r; i++) {
                if ([r isKindOfClass:%c(YTReelPlayerViewController)] ||
                    [r isKindOfClass:%c(YTReelContainerViewController)]) {
                    selectedTrack = YTPlusObjectFromSel(r, @selector(selectedAudioTrack));
                    break;
                }
                r = r.nextResponder;
            }
        }

        // Also try player.parentViewController chain
        if (!selectedTrack) {
            UIViewController *vc = [player isKindOfClass:[UIViewController class]] ? (UIViewController *)player : nil;
            for (int i = 0; i < 10 && vc; i++) {
                if ([vc isKindOfClass:%c(YTReelPlayerViewController)] ||
                    [vc isKindOfClass:%c(YTReelContainerViewController)]) {
                    selectedTrack = YTPlusObjectFromSel(vc, @selector(selectedAudioTrack));
                    break;
                }
                vc = vc.parentViewController;
            }
        }

        if (selectedTrack) {
            // Get the track ID (e.g. "en.1", "ja.1") and displayName (e.g. "English")
            NSString *trackID = YTPlusStringFromSel(selectedTrack, @selector(id_p));
            if (!trackID.length) trackID = YTPlusStringFromSel(selectedTrack, @selector(id));
            NSString *trackName = YTPlusStringFromSel(selectedTrack, @selector(displayName));

            // Match by track ID prefix (language code)
            if (trackID.length >= 2) {
                NSString *trackLang = [[trackID componentsSeparatedByString:@"."] firstObject].lowercaseString;
                for (YTPlusMediaFormat *format in audioFormats) {
                    NSString *fmtLang = format.languageCode.lowercaseString;
                    if (fmtLang.length && [fmtLang hasPrefix:trackLang]) return format;
                    if (format.languageName.length && trackName.length && [format.languageName localizedCaseInsensitiveContainsString:trackName]) return format;
                }
            }
            // Match by display name if track ID didn't work
            if (trackName.length) {
                for (YTPlusMediaFormat *format in audioFormats) {
                    if (format.languageName.length && [format.languageName localizedCaseInsensitiveContainsString:trackName]) return format;
                }
            }
            // If selected track has audioIsDefault, find the default format
            if (YTPlusBoolFromSel(selectedTrack, @selector(audioIsDefault))) {
                for (YTPlusMediaFormat *format in audioFormats) {
                    if (format.isDefaultAudio) return format;
                }
            }
        }
    } @catch (__unused NSException *e) {}

    // Strategy 2: Match the user's device language
    NSArray *preferredLanguages = [NSLocale preferredLanguages];
    for (NSString *preferred in preferredLanguages) {
        NSString *langPrefix = [[preferred componentsSeparatedByString:@"-"] firstObject].lowercaseString;
        for (YTPlusMediaFormat *format in audioFormats) {
            NSString *fmtLang = format.languageCode.lowercaseString;
            if (fmtLang.length && [fmtLang hasPrefix:langPrefix]) return format;
        }
    }

    // Strategy 3: Prefer default/original track
    for (YTPlusMediaFormat *format in audioFormats) {
        if (format.isDefaultAudio) return format;
    }

    return audioFormats.firstObject;
}

static UIViewController *YTPlusPresenter(UIView *sender, YTPlayerViewController *player) {
    UIViewController *presenter = nil;
    if ([sender respondsToSelector:@selector(_viewControllerForAncestor)])
        presenter = [sender _viewControllerForAncestor];
    if (!presenter) presenter = player;
    return YTPlusTopVC(presenter);
}

static YTPlayerViewController *YTPlusPlayerFromVC(UIViewController *vc) {
    Class playerClass = NSClassFromString(@"YTPlayerViewController");
    UIViewController *cursor = vc;
    while (cursor) {
        if (playerClass && [cursor isKindOfClass:playerClass]) return (YTPlayerViewController *)cursor;
        id player = YTPlusObjectFromSel(cursor, @selector(playerViewController));
        if (playerClass && [player isKindOfClass:playerClass]) return (YTPlayerViewController *)player;
        cursor = cursor.parentViewController;
    }
    return YTPlusCurrentPlayerVC;
}

static NSURL *YTPlusThumbnailURL(NSString *videoID) {
    if (videoID.length == 0) return nil;
    NSString *urlString = [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/maxresdefault.jpg", videoID];
    return [NSURL URLWithString:urlString];
}

static void YTPlusRequestPhotos(void (^completion)(BOOL granted)) {
    if (@available(iOS 14.0, *)) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
            completion(status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);
        }];
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            completion(status == PHAuthorizationStatusAuthorized);
        }];
    }
}

static void YTPlusSaveToPhotos(NSURL *fileURL, UIViewController *presenter, void (^completion)(BOOL success, NSError *error)) {
    YTPlusRequestPhotos(^(BOOL granted) {
        if (!granted) {
            NSError *error = [NSError errorWithDomain:@"YTPlus" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Photos access denied"}];
            completion(NO, error);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }];
    });
}

static void YTPlusShareFile(NSURL *fileURL, UIViewController *presenter) {
    if (!fileURL || !presenter) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    // Fix for iPad and specific presentation alignment
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activity.popoverPresentationController.sourceView = presenter.view;
        // Position at the bottom center of the screen
        activity.popoverPresentationController.sourceRect = CGRectMake(presenter.view.bounds.size.width / 2, presenter.view.bounds.size.height, 0, 0);
        activity.popoverPresentationController.permittedArrowDirections = 0; // No arrow pointing to a button
    } else {
        // On iPhone, UIActivityViewController naturally comes from the bottom center
        activity.popoverPresentationController.sourceView = presenter.view;
    }
    [presenter presentViewController:activity animated:YES completion:nil];
}

static void YTPlusPresentMenu(NSString *title, NSArray <YTPlusMenuItem *> *items, UIViewController *presenter, UIView *sender) {
    presenter = YTPlusTopVC(presenter);
    Class sheetClass = NSClassFromString(@"YTDefaultSheetController");
    if (sheetClass && [sheetClass respondsToSelector:@selector(sheetControllerWithParentResponder:)]) {
        YTDefaultSheetController *sheet = [sheetClass sheetControllerWithParentResponder:presenter];
        Class actionClass = NSClassFromString(@"YTActionSheetAction");
        for (YTPlusMenuItem *item in items) {
            id action = nil;
            if ([actionClass respondsToSelector:@selector(actionWithTitle:subtitle:iconImage:handler:)]) {
                action = ((id (*)(Class, SEL, NSString *, NSString *, UIImage *, id))objc_msgSend)(actionClass, @selector(actionWithTitle:subtitle:iconImage:handler:), item.title, item.subtitle, item.iconImage, ^(__unused id action) {
                    if (item.handler) item.handler();
                });
            } else {
                action = ((id (*)(Class, SEL, NSString *, NSInteger, id))objc_msgSend)(actionClass, @selector(actionWithTitle:style:handler:), item.title, 0, ^(__unused id action) {
                    if (item.handler) item.handler();
                });
            }
            if (action) [sheet addAction:action];
        }
        if (sender && [sheet respondsToSelector:@selector(presentFromView:animated:completion:)])
            [sheet presentFromView:sender animated:YES completion:nil];
        else
            [sheet presentFromViewController:presenter animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (YTPlusMenuItem *item in items) {
        NSString *rowTitle = item.subtitle.length ? [NSString stringWithFormat:@"%@\n%@", item.title, item.subtitle] : item.title;
        [alert addAction:[UIAlertAction actionWithTitle:rowTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (item.handler) item.handler();
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = sender ?: presenter.view;
    [presenter presentViewController:alert animated:YES completion:nil];
}

@implementation YTPlusDownloadCoordinator

+ (instancetype)sharedCoordinator {
    static YTPlusDownloadCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTPlusDownloadCoordinator new];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Mozilla/5.0",
            @"Origin": @"https://www.youtube.com",
            @"Referer": @"https://www.youtube.com/",
        };
        configuration.HTTPMaximumConnectionsPerHost = YTPlusFastDownloadConcurrency;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.timeoutIntervalForResource = 300;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)showProgressWithTitle:(NSString *)title presenter:(UIViewController *)presenter {
    self.presenter = presenter;
    self.baseProgressTitle = title;
    self.downloadStartTime = [NSDate timeIntervalSinceReferenceDate];
    self.progressAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ - 0%%", title] message:@"\n" preferredStyle:UIAlertControllerStyleAlert];
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0.0;
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressAlert.view addSubview:self.progressView];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.progressAlert.view.leadingAnchor constant:24.0],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.progressAlert.view.trailingAnchor constant:-24.0],
        [self.progressView.bottomAnchor constraintEqualToAnchor:self.progressAlert.view.bottomAnchor constant:-56.0],
    ]];
    __weak typeof(self) weakSelf = self;
    [self.progressAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        [weakSelf cancelWithMessage:@"Download cancelled"];
    }]];
    [presenter presentViewController:self.progressAlert animated:YES completion:nil];
}

- (void)updateProgressTitle:(NSString *)title progress:(float)progress {
    self.progressAlert.title = [NSString stringWithFormat:@"%@ - %ld%%", title, (long)lrintf(progress * 100.0f)];
    self.progressAlert.message = @"\n";
    [self.progressView setProgress:progress animated:YES];
}

- (void)cancelWithMessage:(NSString *)message {
    [self.task cancel];
    [self.metadataTask cancel];
    [self.rangeDownloader cancel];
    YTPlusCancelFFmpeg();
    self.task = nil;
    self.metadataTask = nil;
    self.rangeDownloader = nil;
    self.fileCompletion = nil;
    self.active = NO;
    self.cancelled = YES;
    [self cleanupTemporaryFiles];
    if (message.length) YTPlusSendToast(message, self.presenter);
}

- (void)cleanupTemporaryFiles {
    if (self.videoTempURL) [NSFileManager.defaultManager removeItemAtURL:self.videoTempURL error:nil];
    if (self.audioTempURL) [NSFileManager.defaultManager removeItemAtURL:self.audioTempURL error:nil];
    self.videoTempURL = nil;
    self.audioTempURL = nil;
}

- (void)downloadURL:(NSURL *)url toURL:(NSURL *)destinationURL expectedBytes:(unsigned long long)expectedBytes headers:(NSDictionary *)headers completion:(YTPlusFileDownloadCompletion)completion {
    self.currentResolvedSizeAddedToTotal = NO;
    self.currentExpectedBytes = expectedBytes;
    self.currentBytes = 0;
    if (expectedBytes == 0) {
        __weak typeof(self) weakSelf = self;
        [self resolveExpectedBytesForURL:url headers:headers completion:^(unsigned long long bytes) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.cancelled) return;
            if (bytes > 0) [self adjustCurrentExpectedBytesIfNeeded:bytes];
            [self beginDownloadURL:url toURL:destinationURL expectedBytes:bytes headers:headers allowFast:YES completion:completion];
        }];
        return;
    }
    [self beginDownloadURL:url toURL:destinationURL expectedBytes:expectedBytes headers:headers allowFast:YES completion:completion];
}

- (void)beginDownloadURL:(NSURL *)url toURL:(NSURL *)destinationURL expectedBytes:(unsigned long long)expectedBytes headers:(NSDictionary *)headers allowFast:(BOOL)allowFast completion:(YTPlusFileDownloadCompletion)completion {
    self.destinationURL = destinationURL;
    self.currentExpectedBytes = expectedBytes;
    self.currentBytes = 0;
    self.finishedCurrentFile = NO;
    self.fileCompletion = completion;
    [NSFileManager.defaultManager removeItemAtURL:destinationURL error:nil];

    if (allowFast && expectedBytes == 0) allowFast = NO;

    if (allowFast && expectedBytes >= YTPlusFastDownloadMinimumBytes) {
        __weak typeof(self) weakSelf = self;
        self.rangeDownloader = [[YTPlusRangeDownloader alloc] initWithURL:url destinationURL:destinationURL expectedBytes:expectedBytes headers:headers progress:^(unsigned long long completedBytes) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.cancelled) return;
            self.currentBytes = completedBytes;
            [self updateDownloadProgressWithCurrentBytes:completedBytes expectedBytes:expectedBytes];
        } completion:^(NSURL *fileURL, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.cancelled) return;
            self.rangeDownloader = nil;
            if (error) {
                [self beginDownloadURL:url toURL:destinationURL expectedBytes:expectedBytes headers:headers allowFast:NO completion:completion];
                return;
            }
            if (completion) completion(fileURL, nil);
        }];
        [self.rangeDownloader start];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    YTPlusApplyDownloadHeaders(request, headers);
    self.task = [self.session downloadTaskWithRequest:request];
    [self.task resume];
}

- (void)resolveExpectedBytesForURL:(NSURL *)url headers:(NSDictionary *)headers completion:(void (^)(unsigned long long bytes))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    request.HTTPMethod = @"HEAD";
    YTPlusApplyDownloadHeaders(request, headers);

    __weak typeof(self) weakSelf = self;
    self.metadataTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(__unused NSData *data, NSURLResponse *response, __unused NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        unsigned long long bytes = 0;
        if (response.expectedContentLength > 0) {
            bytes = (unsigned long long)response.expectedContentLength;
        } else if ([response isKindOfClass:NSHTTPURLResponse.class]) {
            id header = ((NSHTTPURLResponse *)response).allHeaderFields[@"Content-Length"];
            if ([header respondsToSelector:@selector(unsignedLongLongValue)])
                bytes = [header unsignedLongLongValue];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.metadataTask = nil;
            completion(bytes);
        });
    }];
    [self.metadataTask resume];
}

- (void)updateDownloadProgressWithCurrentBytes:(unsigned long long)currentBytes expectedBytes:(unsigned long long)expectedBytes {
    unsigned long long total = self.totalBytes ?: expectedBytes;
    float progress = total ? (float)(self.completedBytes + currentBytes) / (float)total : 0.0f;
    progress = fminf(fmaxf(progress, 0.0f), 0.985f);
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = now - self.downloadStartTime;
    double speedMBps = 0;
    if (elapsed > 0) {
        speedMBps = ((double)(self.completedBytes + currentBytes) / 1048576.0) / elapsed;
    }
    double totalMB = (double)total / 1048576.0;
    
    self.progressAlert.title = [NSString stringWithFormat:@"%@ - %ld%%", self.baseProgressTitle ?: @"Downloading", (long)lrintf(progress * 100.0f)];
    if (total > 0) {
        self.progressAlert.message = [NSString stringWithFormat:@"%.1f MB/s - %.1f MB\n", speedMBps, totalMB];
    } else {
        self.progressAlert.message = [NSString stringWithFormat:@"%.1f MB/s\n", speedMBps];
    }
    [self.progressView setProgress:progress animated:YES];
}

- (void)adjustCurrentExpectedBytesIfNeeded:(unsigned long long)newExpectedBytes {
    unsigned long long oldExpectedBytes = self.currentExpectedBytes;
    if (newExpectedBytes <= oldExpectedBytes) return;

    self.currentExpectedBytes = newExpectedBytes;
    if (oldExpectedBytes > 0) {
        self.totalBytes += newExpectedBytes - oldExpectedBytes;
    } else if (!self.currentResolvedSizeAddedToTotal) {
        self.totalBytes += newExpectedBytes;
        self.currentResolvedSizeAddedToTotal = YES;
    }
}

- (void)startVideoDownloadWithVideoFormat:(YTPlusMediaFormat *)videoFormat audioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter {
    if (self.active) {
        YTPlusSendToast(@"Already downloading", presenter);
        return;
    }
    [self startDirectVideoDownloadWithVideoFormat:videoFormat audioFormat:audioFormat fileName:fileName videoID:videoID presenter:presenter];
}

- (void)startDirectVideoDownloadWithVideoFormat:(YTPlusMediaFormat *)videoFormat audioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter {
    NSURL *videoURL = [NSURL URLWithString:videoFormat.urlString];
    NSURL *audioURL = [NSURL URLWithString:audioFormat.urlString];
    if (!videoURL || !audioURL) {
        YTPlusSendToast(@"No stream URL found", presenter);
        return;
    }

    self.active = YES;
    self.cancelled = NO;
    self.completedBytes = 0;
    self.totalBytes = videoFormat.contentLength + audioFormat.contentLength;
    self.videoTempURL = YTPlusTempFileURL(YTPlusExtForFormat(videoFormat, @"mp4"));
    self.audioTempURL = YTPlusTempFileURL(YTPlusExtForFormat(audioFormat, @"m4a"));
    NSString *outputExtension = YTPlusMergedExt(videoFormat, audioFormat);
    [self showProgressWithTitle:@"Downloading video" presenter:presenter];

    __weak typeof(self) weakSelf = self;
    [self downloadURL:videoURL toURL:self.videoTempURL expectedBytes:videoFormat.contentLength headers:videoFormat.httpHeaders completion:^(NSURL *videoFileURL, NSError *videoError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || videoError) {
            [self failWithError:videoError ?: [NSError errorWithDomain:@"YTPlus" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Video download failed"}]];
            return;
        }

        self.completedBytes += MAX(videoFormat.contentLength, self.currentBytes);
        [self updateProgressTitle:@"Downloading audio" progress:(self.totalBytes ? (float)self.completedBytes / (float)self.totalBytes : 0.5f)];
        [self downloadURL:audioURL toURL:self.audioTempURL expectedBytes:audioFormat.contentLength headers:audioFormat.httpHeaders completion:^(NSURL *audioFileURL, NSError *audioError) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || audioError) {
                [self failWithError:audioError ?: [NSError errorWithDomain:@"YTPlus" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Audio download failed"}]];
                return;
            }
            unsigned long long durationMs = videoFormat.durationMs ?: audioFormat.durationMs;
            [self mergeVideoURL:videoFileURL audioURL:audioFileURL fileName:fileName outputExtension:outputExtension durationMs:durationMs presenter:presenter];
        }];
    }];
}

- (void)startDirectSingleVideoDownloadWithFormat:(YTPlusMediaFormat *)format fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter {
    NSURL *videoURL = [NSURL URLWithString:format.urlString];
    if (!videoURL) {
        YTPlusSendToast(@"No stream URL found", presenter);
        return;
    }

    self.active = YES;
    self.cancelled = NO;
    self.completedBytes = 0;
    self.totalBytes = format.contentLength;
    NSString *extension = YTPlusExtForFormat(format, @"mp4");
    BOOL canFinalizeWithAVFoundation = format.durationMs > 0 && YTPlusIsPhotosVideo(extension);
    NSURL *finalURL = YTPlusUniqueFileURL(fileName, extension);
    NSURL *downloadURL = canFinalizeWithAVFoundation ? YTPlusTempFileURL(extension) : finalURL;
    self.videoTempURL = canFinalizeWithAVFoundation ? downloadURL : nil;
    [self showProgressWithTitle:@"Downloading video" presenter:presenter];

    __weak typeof(self) weakSelf = self;
    [self downloadURL:videoURL toURL:downloadURL expectedBytes:format.contentLength headers:format.httpHeaders completion:^(NSURL *fileURL, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error) {
            [self failWithError:error ?: [NSError errorWithDomain:@"YTPlus" code:8 userInfo:@{NSLocalizedDescriptionKey: @"Video download failed"}]];
            return;
        }
        if (canFinalizeWithAVFoundation) {
            [self trimSingleVideoURL:fileURL outputURL:finalURL durationMs:format.durationMs presenter:presenter];
            return;
        }
        [self completeWithFileURL:fileURL isVideo:YES presenter:presenter];
    }];
}

- (void)startAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter {
    [self startAudioDownloadWithAudioFormat:audioFormat fileName:fileName videoID:videoID outputFormat:nil presenter:presenter];
}

- (void)startAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID outputFormat:(YTPlusAudioOutputFormat *)outputFormat presenter:(UIViewController *)presenter {
    if (self.active) {
        YTPlusSendToast(@"Already downloading", presenter);
        return;
    }
    [self startDirectAudioDownloadWithAudioFormat:audioFormat fileName:fileName videoID:videoID outputFormat:outputFormat presenter:presenter];
}

- (void)startDirectAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID presenter:(UIViewController *)presenter {
    [self startDirectAudioDownloadWithAudioFormat:audioFormat fileName:fileName videoID:videoID outputFormat:nil presenter:presenter];
}

- (void)startDirectAudioDownloadWithAudioFormat:(YTPlusMediaFormat *)audioFormat fileName:(NSString *)fileName videoID:(NSString *)videoID outputFormat:(YTPlusAudioOutputFormat *)outputFormat presenter:(UIViewController *)presenter {
    NSURL *audioURL = [NSURL URLWithString:audioFormat.urlString];
    if (!audioURL) {
        YTPlusSendToast(@"No audio URL found", presenter);
        return;
    }
    outputFormat = outputFormat ?: YTPlusDefaultAudioFmt();
    if (!outputFormat.supported) {
        YTPlusSendToast([NSString stringWithFormat:@"%@ not supported", outputFormat.title ?: @"Format"], presenter);
        return;
    }

    self.active = YES;
    self.cancelled = NO;
    self.completedBytes = 0;
    self.totalBytes = audioFormat.contentLength;
    BOOL passthrough = YTPlusAudioOutputFormatCanPassthrough(outputFormat, audioFormat);
    if (!passthrough && !YTPlusFFmpegKitAvailable()) {
        self.active = NO;
        NSString *details = YTPlusFFmpegKitDiagnosticText(outputFormat, audioFormat, videoID);
        YTPlusRecordDiag(@"FFmpegKit unavailable for audio conversion", details);
        NSString *diagnostic = YTPlusDiagText();
        if (diagnostic.length) {
            UIPasteboard.generalPasteboard.string = diagnostic;
            YTPlusSendToast(@"FFmpegKit not loaded, diagnostics copied", presenter);
        } else {
            YTPlusSendToast([NSString stringWithFormat:@"FFmpegKit required for %@", outputFormat.title ?: @"this format"], presenter);
        }
        return;
    }

    NSURL *finalURL = YTPlusUniqueFileURL(fileName, YTPlusAudioOutExt(outputFormat, audioFormat, passthrough));
    NSURL *downloadURL = passthrough ? finalURL : YTPlusTempFileURL(YTPlusExtForFormat(audioFormat, @"m4a"));
    self.audioTempURL = passthrough ? nil : downloadURL;
    [self showProgressWithTitle:@"Downloading audio" presenter:presenter];

    __weak typeof(self) weakSelf = self;
    [self downloadURL:audioURL toURL:downloadURL expectedBytes:audioFormat.contentLength headers:audioFormat.httpHeaders completion:^(NSURL *fileURL, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error) {
            [self failWithError:error ?: [NSError errorWithDomain:@"YTPlus" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Audio download failed"}]];
            return;
        }
        if (!passthrough) {
            unsigned long long durationMs = audioFormat.durationMs ?: YTPlusDurationMs(fileURL);
            [self convertAudioURL:fileURL outputURL:finalURL outputFormat:outputFormat durationMs:durationMs presenter:presenter];
            return;
        }
        [self completeWithFileURL:fileURL isVideo:NO presenter:presenter];
    }];
}

- (void)convertAudioURL:(NSURL *)inputURL outputURL:(NSURL *)outputURL outputFormat:(YTPlusAudioOutputFormat *)outputFormat durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter {
    [self updateProgressTitle:[NSString stringWithFormat:@"Converting to %@", outputFormat.title ?: @"audio"] progress:0.985f];
    [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];

    __weak typeof(self) weakSelf = self;
    BOOL started = YTPlusStartFFmpegConvert(inputURL, outputURL, outputFormat, durationMs, ^(float progress) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.cancelled) return;
        [self updateProgressTitle:[NSString stringWithFormat:@"Converting to %@", outputFormat.title ?: @"audio"] progress:progress];
    }, ^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.cancelled) return;
        if (success) {
            [self completeWithFileURL:outputURL isVideo:NO presenter:presenter];
            return;
        }
        [self failWithError:error ?: [NSError errorWithDomain:@"YTPlus" code:14 userInfo:@{NSLocalizedDescriptionKey: @"Conversion failed"}]];
    });

    if (!started) {
        [self failWithError:[NSError errorWithDomain:@"YTPlus" code:15 userInfo:@{NSLocalizedDescriptionKey: @"Format unavailable"}]];
    }
}

- (void)mergeVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL fileName:(NSString *)fileName outputExtension:(NSString *)outputExtension durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter {
    [self updateProgressTitle:@"Merging video" progress:0.985f];
    NSURL *outputURL = YTPlusUniqueFileURL(fileName, outputExtension.length ? outputExtension : @"mp4");
    if (durationMs == 0) durationMs = YTPlusDurationMs(videoURL);

    if (YTPlusFFmpegKitAvailable()) {
        __weak typeof(self) weakSelf = self;
        BOOL started = YTPlusStartFFmpegMerge(videoURL, audioURL, outputURL, durationMs, ^(float progress) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.cancelled) return;
            [self updateProgressTitle:@"Merging video" progress:progress];
        }, ^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.cancelled) return;
            if (success) {
                [self completeWithFileURL:outputURL isVideo:YES presenter:presenter];
                return;
            }

            [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];
            if (YTPlusCanUseAVF(outputURL)) {
                [self mergeVideoWithAVFoundationVideoURL:videoURL audioURL:audioURL outputURL:outputURL durationMs:durationMs presenter:presenter fallbackError:error];
            } else {
                [self failWithError:error ?: [NSError errorWithDomain:@"YTPlus" code:16 userInfo:@{NSLocalizedDescriptionKey: @"FFmpegKit required for this stream"}]];
            }
        });
        if (started) return;
    }

    if (YTPlusCanUseAVF(outputURL)) {
        [self mergeVideoWithAVFoundationVideoURL:videoURL audioURL:audioURL outputURL:outputURL durationMs:durationMs presenter:presenter fallbackError:nil];
    } else {
        [self failWithError:[NSError errorWithDomain:@"YTPlus" code:16 userInfo:@{NSLocalizedDescriptionKey: @"FFmpegKit required for this stream"}]];
    }
}

- (void)mergeVideoWithAVFoundationVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL outputURL:(NSURL *)outputURL durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter fallbackError:(NSError *)fallbackError {
    [self updateProgressTitle:fallbackError ? @"Merging video with fallback" : @"Merging video" progress:0.985f];
    AVURLAsset *videoAsset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
    AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:audioURL options:nil];
    AVMutableComposition *composition = [AVMutableComposition composition];

    AVAssetTrack *videoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    AVAssetTrack *audioTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (!videoTrack || !audioTrack) {
        [self failWithError:fallbackError ?: [NSError errorWithDomain:@"YTPlus" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Merge failed"}]];
        return;
    }

    CMTime duration = YTPlusExportDuration(videoAsset, audioAsset, durationMs);
    if (!YTPlusCMTimeUsable(duration)) {
        [self failWithError:fallbackError ?: [NSError errorWithDomain:@"YTPlus" code:9 userInfo:@{NSLocalizedDescriptionKey: @"Cannot determine duration"}]];
        return;
    }
    NSError *insertError = nil;
    AVMutableCompositionTrack *compositionVideo = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [compositionVideo insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:videoTrack atTime:kCMTimeZero error:&insertError];
    compositionVideo.preferredTransform = videoTrack.preferredTransform;
    if (insertError) {
        [self failWithError:insertError];
        return;
    }

    AVMutableCompositionTrack *compositionAudio = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    [compositionAudio insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:audioTrack atTime:kCMTimeZero error:&insertError];
    if (insertError) {
        [self failWithError:insertError];
        return;
    }

    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    exporter.outputURL = outputURL;
    exporter.outputFileType = AVFileTypeMPEG4;
    exporter.shouldOptimizeForNetworkUse = YES;

    __weak typeof(self) weakSelf = self;
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (exporter.status == AVAssetExportSessionStatusCompleted) {
                [self completeWithFileURL:outputURL isVideo:YES presenter:presenter];
            } else {
                [self failWithError:exporter.error ?: [NSError errorWithDomain:@"YTPlus" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Merge failed"}]];
            }
        });
    }];
}

- (void)trimSingleVideoURL:(NSURL *)inputURL outputURL:(NSURL *)outputURL durationMs:(unsigned long long)durationMs presenter:(UIViewController *)presenter {
    [self updateProgressTitle:@"Finalizing video" progress:0.99f];
    [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) {
        [self failWithError:[NSError errorWithDomain:@"YTPlus" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Cannot finalize video"}]];
        return;
    }

    CMTime duration = YTPlusExportDuration(asset, nil, durationMs);
    if (!YTPlusCMTimeUsable(duration)) {
        [self failWithError:[NSError errorWithDomain:@"YTPlus" code:11 userInfo:@{NSLocalizedDescriptionKey: @"Cannot determine duration"}]];
        return;
    }

    AVMutableComposition *composition = [AVMutableComposition composition];
    NSError *insertError = nil;
    AVMutableCompositionTrack *compositionVideo = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [compositionVideo insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:videoTrack atTime:kCMTimeZero error:&insertError];
    compositionVideo.preferredTransform = videoTrack.preferredTransform;
    if (insertError) {
        [self failWithError:insertError];
        return;
    }

    AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (audioTrack) {
        CMTime audioDuration = YTPlusMinDuration(duration, audioTrack.timeRange.duration);
        AVMutableCompositionTrack *compositionAudio = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        [compositionAudio insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioDuration) ofTrack:audioTrack atTime:kCMTimeZero error:&insertError];
        if (insertError) {
            [self failWithError:insertError];
            return;
        }
    }

    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    exporter.outputURL = outputURL;
    exporter.outputFileType = AVFileTypeMPEG4;
    exporter.shouldOptimizeForNetworkUse = YES;

    __weak typeof(self) weakSelf = self;
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (exporter.status == AVAssetExportSessionStatusCompleted) {
                [self completeWithFileURL:outputURL isVideo:YES presenter:presenter];
            } else {
                [self failWithError:exporter.error ?: [NSError errorWithDomain:@"YTPlus" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Finalize failed"}]];
            }
        });
    }];
}

- (void)completeWithFileURL:(NSURL *)fileURL isVideo:(BOOL)isVideo presenter:(UIViewController *)presenter {
    self.active = NO;
    [self updateProgressTitle:@"Download completed" progress:1.0f];
    [self.progressAlert dismissViewControllerAnimated:YES completion:nil];
    self.progressAlert = nil;
    self.progressView = nil;

    BOOL canSaveToPhotos = isVideo && YTPlusCanSavePhotos(fileURL);
    if (isVideo && ytpBool(@"downloadSaveToPhotos") && canSaveToPhotos) {
        [self cleanupTemporaryFiles];
        YTPlusSaveToPhotos(fileURL, presenter, ^(BOOL success, NSError *error) {
            if (success) {
                YTPlusSendToast(@"Saved to Photos", presenter);
            } else {
                YTPlusSendToast(error.localizedDescription ?: @"Cannot save to Photos", presenter);
                YTPlusShareFile(fileURL, presenter);
            }
        });
    } else {
        [self cleanupTemporaryFiles];
        // Always present the share sheet so users can choose where to save
        YTPlusShareFile(fileURL, presenter);
    }
}

- (void)failWithError:(NSError *)error {
    self.active = NO;
    [self.progressAlert dismissViewControllerAnimated:YES completion:nil];
    self.progressAlert = nil;
    self.progressView = nil;
    [self cleanupTemporaryFiles];
    YTPlusSendToast(error.localizedDescription ?: @"Download failed", self.presenter);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    self.currentBytes = (unsigned long long)MAX(totalBytesWritten, 0);
    if (totalBytesExpectedToWrite > 0)
        [self adjustCurrentExpectedBytesIfNeeded:(unsigned long long)totalBytesExpectedToWrite];
    if (self.currentBytes > self.currentExpectedBytes)
        [self adjustCurrentExpectedBytesIfNeeded:self.currentBytes];
    [self updateDownloadProgressWithCurrentBytes:self.currentBytes expectedBytes:self.currentExpectedBytes];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    self.finishedCurrentFile = YES;
    NSError *error = nil;
    [NSFileManager.defaultManager removeItemAtURL:self.destinationURL error:nil];
    [NSFileManager.defaultManager moveItemAtURL:location toURL:self.destinationURL error:&error];
    if (self.fileCompletion) self.fileCompletion(error ? nil : self.destinationURL, error);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && !self.finishedCurrentFile && self.fileCompletion) {
        self.fileCompletion(nil, error);
    }
}

@end

static void YTPlusDownloadThumb(NSString *videoID, UIViewController *presenter) {
    NSURL *thumbnailURL = YTPlusThumbnailURL(videoID);
    if (!thumbnailURL) {
        YTPlusSendToast(@"No thumbnail found", presenter);
        return;
    }

    YTPlusSendToast(@"Downloading thumbnail", presenter);
    [[NSURLSession.sharedSession dataTaskWithURL:thumbnailURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!image || error) {
                YTPlusSendToast(error.localizedDescription ?: @"Thumbnail failed", presenter);
                return;
            }
            YTPlusRequestPhotos(^(BOOL granted) {
                if (!granted) {
                    YTPlusSendToast(@"Photos access denied", presenter);
                    return;
                }
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                } completionHandler:^(BOOL success, NSError *saveError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        YTPlusSendToast(success ? @"Saved to Photos" : (saveError.localizedDescription ?: @"Save failed"), presenter);
                    });
                }];
            });
        });
    }] resume];
}

static void YTPlusCopyVideoInfo(YTPlayerViewController *player, UIViewController *presenter) {
    NSString *videoID = YTPlusVideoID(player);
    NSString *title = YTPlusVideoTitle(player);
    NSString *url = videoID.length ? [NSString stringWithFormat:@"https://youtu.be/%@", videoID] : @"";
    UIPasteboard.generalPasteboard.string = url.length ? [NSString stringWithFormat:@"%@\n%@", title, url] : title;
    YTPlusSendToast(@"Copied video information", presenter);
}

static void YTPlusShowVideoSheet(YTPlayerViewController *player, UIViewController *presenter, UIView *sender) {
    NSArray <YTPlusMediaFormat *> *videoFormats = YTPlusFormatsForPlayer(player, YES);
    YTPlusMediaFormat *audioFormat = YTPlusBestAudio(player);
    NSString *title = YTPlusVideoTitle(player);
    NSString *videoID = YTPlusVideoID(player);

    if (videoFormats.count == 0 || !audioFormat) {
        YTPlusSendToast(@"No video/audio streams found", presenter);
        return;
    }

    NSMutableArray *items = [NSMutableArray array];
    for (YTPlusMediaFormat *format in videoFormats) {
        NSString *rowTitle = format.qualityLabel.length ? format.qualityLabel : @"Video";
        NSString *subtitle = YTPlusFormatSubtitle(format);
        [items addObject:[YTPlusMenuItem itemWithTitle:rowTitle subtitle:subtitle icon:YTPlusIconImage(658) handler:^{
            [[YTPlusDownloadCoordinator sharedCoordinator] startVideoDownloadWithVideoFormat:format audioFormat:audioFormat fileName:title videoID:videoID presenter:presenter];
        }]];
    }
    YTPlusPresentMenu(@"Download video", items, presenter, sender);
}

static void YTPlusShowAudioSrcSheet(YTPlayerViewController *player, YTPlusAudioOutputFormat *outputFormat, UIViewController *presenter, UIView *sender) {
    NSArray <YTPlusMediaFormat *> *audioFormats = YTPlusFormatsForPlayer(player, NO);
    NSString *title = YTPlusVideoTitle(player);
    NSString *videoID = YTPlusVideoID(player);
    NSMutableArray *items = [NSMutableArray array];

    if (audioFormats.count == 0) {
        if (items.count) {
            YTPlusPresentMenu(@"Download audio", items, presenter, sender);
            return;
        }
        YTPlusSendToast(@"No audio streams found", presenter);
        return;
    }

    NSUInteger index = 1;
    for (YTPlusMediaFormat *format in audioFormats) {
        NSString *rowTitle = audioFormats.count == 1 ? @"Audio" : [NSString stringWithFormat:@"Audio %lu", (unsigned long)index++];
        NSString *subtitle = YTPlusFormatSubtitle(format);
        [items addObject:[YTPlusMenuItem itemWithTitle:rowTitle subtitle:subtitle icon:YTPlusIconImage(21) handler:^{
            [[YTPlusDownloadCoordinator sharedCoordinator] startAudioDownloadWithAudioFormat:format fileName:title videoID:videoID outputFormat:outputFormat presenter:presenter];
        }]];
    }
    NSString *menuTitle = outputFormat.title.length ? [NSString stringWithFormat:@"Download %@", outputFormat.title] : @"Download audio";
    YTPlusPresentMenu(menuTitle, items, presenter, sender);
}

static void YTPlusShowAudioSheet(YTPlayerViewController *player, UIViewController *presenter, UIView *sender) {
    NSMutableArray *items = [NSMutableArray array];
    for (YTPlusAudioOutputFormat *format in YTPlusAudioOutputFormats()) {
        [items addObject:[YTPlusMenuItem itemWithTitle:format.title subtitle:YTPlusAudioSubtitle(format) icon:YTPlusIconImage(21) handler:^{
            if (!format.supported) {
                YTPlusSendToast(@"DSD export is not supported by bundled FFmpeg.", presenter);
                return;
            }
            YTPlusShowAudioSrcSheet(player, format, presenter, sender);
        }]];
    }
    YTPlusPresentMenu(@"Audio format", items, presenter, sender);
}

static void YTPlusShowCaptionsSheet(YTPlayerViewController *player, UIViewController *presenter, UIView *sender) {
    NSArray *tracks = YTPlusCaptionTracks(player);
    if (tracks.count == 0) {
        YTPlusSendToast(@"No captions available for this video.", presenter);
        return;
    }
    
    NSMutableArray *items = [NSMutableArray array];
    for (id track in tracks) {
        NSString *baseURL = YTPlusStringFromSel(track, @selector(baseURL));
        if (baseURL.length == 0) continue;
        
        NSString *languageCode = YTPlusStringFromSel(track, @selector(languageCode));
        NSString *vssId = YTPlusStringFromSel(track, @selector(vssId));
        NSString *nameStr = nil;
        id nameObj = YTPlusObjectFromSel(track, @selector(name));
        nameStr = YTPlusStringFromSel(nameObj, @selector(simpleText));
        if (!nameStr.length) {
            NSArray *runs = YTPlusObjectFromSel(nameObj, @selector(runsArray));
            if (runs.count > 0) nameStr = YTPlusStringFromSel(runs.firstObject, @selector(text));
        }
        if (!nameStr.length) nameStr = languageCode;
        if (!nameStr.length) nameStr = vssId;
        
        [items addObject:[YTPlusMenuItem itemWithTitle:nameStr subtitle:languageCode icon:YTPlusIconImage(637) handler:^{
            NSString *vttURL = [baseURL stringByAppendingString:@"&fmt=vtt"];
            NSURL *url = [NSURL URLWithString:vttURL];
            if (!url) {
                YTPlusSendToast(@"Invalid caption URL.", presenter);
                return;
            }
            YTPlusSendToast(@"Downloading captions...", presenter);
            [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error || data.length == 0) {
                        YTPlusSendToast(@"Failed to download captions.", presenter);
                        return;
                    }
                    NSString *videoID = YTPlusVideoID(player) ?: @"video";
                    NSString *filename = [NSString stringWithFormat:@"%@_%@.vtt", videoID, languageCode ?: @"captions"];
                    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
                    [data writeToURL:tempURL atomically:YES];
                    YTPlusShareFile(tempURL, presenter);
                });
            }] resume];
        }]];
    }
    
    if (items.count == 0) {
        YTPlusSendToast(@"No valid caption URLs found.", presenter);
        return;
    }
    
    YTPlusPresentMenu(@"Download captions", items, presenter, sender);
}

static void YTPlusShowDownloadMgr(YTPlayerViewController *player, UIViewController *presenter, UIView *sender) {
    if (!player) {
        YTPlusSendToast(@"Open a video before using the download manager.", presenter);
        return;
    }

    NSString *videoID = YTPlusVideoID(player);
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[YTPlusMenuItem itemWithTitle:@"Download video" subtitle:@"Choose quality" icon:YTPlusIconImage(658) handler:^{
        YTPlusShowVideoSheet(player, presenter, sender);
    }]];
    [items addObject:[YTPlusMenuItem itemWithTitle:@"Download audio" subtitle:@"Choose format" icon:YTPlusIconImage(21) handler:^{
        YTPlusShowAudioSheet(player, presenter, sender);
    }]];
    [items addObject:[YTPlusMenuItem itemWithTitle:@"Download captions" subtitle:@"Save subtitles as VTT" icon:YTPlusIconImage(637) handler:^{
        YTPlusShowCaptionsSheet(player, presenter, sender);
    }]];
    [items addObject:[YTPlusMenuItem itemWithTitle:@"Copy diagnostics" subtitle:@"Copy last error log" icon:YTPlusIconImage(870) handler:^{
        YTPlusCopyDiag(presenter);
    }]];
    [items addObject:[YTPlusMenuItem itemWithTitle:@"Save thumbnail" subtitle:@"Save to Photos" icon:YTPlusIconImage(367) handler:^{
        YTPlusDownloadThumb(videoID, presenter);
    }]];
    [items addObject:[YTPlusMenuItem itemWithTitle:@"Copy video information" subtitle:@"Copy title and URL" icon:YTPlusIconImage(250) handler:^{
        YTPlusCopyVideoInfo(player, presenter);
    }]];
    YTPlusPresentMenu(@"Download manager", items, presenter, sender);
}

void YTPlusConfigureDownloadBtn(_ASDisplayView *view) {
    if (![view.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) return;
    if (!ytpBool(@"downloadManager") || ytpBool(@"noPlayerDownloadButton")) return;
    if (objc_getAssociatedObject(view, @selector(YTPlusDownloadButtonTapped:))) return;

    view.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:view action:@selector(YTPlusDownloadButtonTapped:)];
    tap.cancelsTouchesInView = YES;
    tap.delaysTouchesBegan = YES;
    tap.delaysTouchesEnded = YES;
    [view addGestureRecognizer:tap];
    objc_setAssociatedObject(view, @selector(YTPlusDownloadButtonTapped:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSString *ytpGlobalAuthHeader = nil;

// SSOAuthorization removed in 21.16.2

%hook SSOAuthorizationImpl
- (id)accessToken {
    id token = %orig;
    if ([token isKindOfClass:[NSString class]] && [(NSString *)token length] > 0) {
        ytpGlobalAuthHeader = [NSString stringWithFormat:@"Bearer %@", token];
    }
    return token;
}
%end

%hook GNPSSOAuthorizationService
- (id)authToken {
    id token = %orig;
    if ([token isKindOfClass:[NSString class]] && [(NSString *)token length] > 0) {
        ytpGlobalAuthHeader = [NSString stringWithFormat:@"Bearer %@", token];
    }
    return token;
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
