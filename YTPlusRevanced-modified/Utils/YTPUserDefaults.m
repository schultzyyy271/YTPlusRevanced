#import "YTPUserDefaults.h"

@implementation YTPUserDefaults

static NSString *const kDefaultsSuiteName = @"com.community.youtubeplusrevanced";

+ (YTPUserDefaults *)standardUserDefaults {
    static dispatch_once_t onceToken;
    static YTPUserDefaults *defaults = nil;

    dispatch_once(&onceToken, ^{
        defaults = [[self alloc] initWithSuiteName:kDefaultsSuiteName];
        [defaults registerYTPDefaults];
    });

    return defaults;
}

- (void)reset {
    [self removePersistentDomainForName:kDefaultsSuiteName];
}

+ (void)resetUserDefaults {
    [[self standardUserDefaults] reset];
}

- (void)registerYTPDefaults {
    [self registerDefaults:@{
        // Version spoofer
        @"versionSpooferEnabled": @NO,
        @"versionSpooferIndex":   @0,
        @"hideMerchShelf":        @YES,

        // Core — on by default
        @"noAds":              @YES,
        @"backgroundPlayback": @YES,

        // Playback defaults
        @"speedIndex":         @1,   // index 1 = 2.0x hold speed
        @"autoSpeedIndex":     @3,   // index 3 = 1.0x (no auto-speed)
        @"wiFiQualityIndex":   @0,   // 0 = auto
        @"cellQualityIndex":   @0,

        // Tab bar defaults
        @"pivotIndex":         @0,   // 0 = Home

        // Features off by default (user enables what they want)
        @"removeUploads":      @NO,
        @"removeLibrary":      @NO,
        @"removeSubscriptions":@NO,
        @"removeExplore":      @NO,
        @"addExplore":         @NO,
        @"reExplore":          @NO,
        @"hideShorts":         @NO,
        @"autoSkipShorts":     @NO,
        @"shortsOnlyMode":     @NO,
        @"noHUDMsgs":          @NO,
        @"noContinueWatching": @NO,
        @"redProgressBar":     @NO,
        @"disableRTL":         @NO,
        @"fixAlbums":          @NO,
        @"advancedMode":       @NO,
        @"advancedModeReminder": @NO,

        // Player button hiding
        @"noPlayerClipButton":     @NO,
        @"noPlayerDownloadButton": @NO,
        @"noPlayerRemixButton":    @NO,

        // Shorts UI
        @"hideShortsAvatars":       @NO,
        @"hideShortsComments":      @NO,
        @"hideShortsDislike":       @NO,
        @"hideShortsLike":          @NO,
        @"hideShortsRemix":         @NO,
        @"hideShortsShare":         @NO,
        @"hideShortsSubscriptions": @NO,
        @"resumeShorts":            @NO,

        // Shorts features
        @"stopDoomScrolling":       @NO,
        @"shortsToRegular":         @NO,
        @"shortsProgress":          @NO,
        @"pinchToFullscreenShorts": @NO,
        @"hideShortsAudioTrack":    @NO,
        @"hideShortsCamera":        @NO,
        @"hideShortsChannelName":   @NO,
        @"hideShortsDescription":   @NO,
        @"hideShortsLogo":          @NO,
        @"hideShortsMore":          @NO,
        @"hideShortsPromoCards":    @NO,
        @"hideShortsSearch":        @NO,
        @"hideShortsSource":        @NO,
        @"hideShortsThanks":        @NO,

        // Download/share
        @"removeDownloadMenu":  @NO,
        @"nativeShare":         @NO,
        @"copyVideoInfo":       @NO,

        // Player features
        @"autoFullscreen":          @NO,
        @"classicQuality":          @NO,
        @"disableAutoCaptions":     @NO,
        @"disableAutoplay":         @NO,
        @"dontSnapToChapter":       @NO,
        @"endScreenCards":          @NO,
        @"exitFullscreen":          @NO,
        @"extraSpeedOptions":       @NO,
        @"hideAutoplay":            @NO,
        @"hidePrevNext":            @NO,
        @"miniplayer":              @NO,
        @"noCast":                  @NO,
        @"noContentWarning":        @NO,
        @"noDarkBg":                @NO,
        @"noDoubleTapToSeek":       @NO,
        @"noFreeZoom":              @NO,
        @"noFullscreenActions":     @NO,
        @"noHints":                 @NO,
        @"noNotifsButton":          @NO,
        @"noPromotionCards":        @NO,
        @"noRelatedVids":           @NO,
        @"noRelatedWatchNexts":     @NO,
        @"noSearchButton":          @NO,
        @"noSearchHistory":         @NO,
        @"noSubbar":                @NO,
        @"noTwoFingerSnapToChapter":@NO,
        @"noVoiceSearchButton":     @NO,
        @"noWatermarks":            @NO,
        @"noYTLogo":                @NO,
        @"pauseOnOverlay":          @NO,
        @"persistentProgressBar":   @NO,
        @"playlistOldMinibar":      @NO,
        @"portraitFullscreen":       @NO,
        @"premiumYTLogo":           @NO,
        @"replacePrevNext":         @NO,
        @"stickyNavbar":            @NO,
        @"stockVolumeHUD":          @NO,
        @"videoEndTime":            @NO,
        @"24hrFormat":              @NO,
        @"copyWithTimestamp":        @NO,
        @"stickSortComments":       @NO,
        @"hideSortComments":        @NO,
        @"hideSubs":                @NO,
        @"clearCacheOnStartup":     @NO,
        @"removeShorts":            @NO,
        @"removeIndicators":        @NO,
        @"removeLabels":            @NO,
        @"removePlayNext":          @NO,
        @"removeDontRecommendMenu": @NO,
        @"removeNotInterestedMenu": @NO,
        @"removeReportMenu":        @NO,
        @"removeSaveToPlaylistMenu":@NO,
        @"removeShareMenu":         @NO,
        @"removeWatchLaterMenu":    @NO,
        @"downloadManager":         @YES,
        @"downloadSaveToPhotos":    @NO,
        @"postManager":             @NO,
        @"commentManager":          @NO,
        @"saveProfilePhoto":        @NO,
    }];
}

@end
