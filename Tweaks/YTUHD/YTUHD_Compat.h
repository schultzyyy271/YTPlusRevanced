// YTUHD_Compat.h — complete stubs for all YTUHD types not in theos.
#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>

// ── MLFormat — used for video format filtering ────────────────────────────────
@interface MLMIMEType : NSObject
- (uint32_t)videoCodec;  // returns FourCC e.g. 'vp09' 'av01' 'avc1'
@end

@interface MLFormat : NSObject
- (NSString *)qualityLabel;
- (MLMIMEType *)MIMEType;
- (NSInteger)bitrate;
- (NSInteger)width;
- (NSInteger)height;
- (double)fps;
@end

// ── YTIHamplayer codec filter stubs ──────────────────────────────────────────
@interface YTIHamplayerCodecFilter : NSObject
@property (nonatomic, assign) NSInteger maxArea;
@property (nonatomic, assign) NSInteger maxFps;
@end

@interface YTIHamplayerStreamFilter : NSObject
@property (nonatomic, strong) YTIHamplayerCodecFilter *av1;
@property (nonatomic, strong) YTIHamplayerCodecFilter *vp9;
@property (nonatomic, assign) BOOL enableVideoCodecSplicing;
@property (nonatomic, assign) BOOL hasVideoCodecIdWhitelist;
@property (nonatomic, strong) id videoCodecIdWhitelist;
@property (nonatomic, assign) BOOL hasVideoCodecIdBlacklist;
@property (nonatomic, strong) id videoCodecIdBlacklist;
@end

@interface YTIHamplayerSoftwareStreamFilter : NSObject
@property (nonatomic, assign) BOOL hasVideoCodecIdWhitelist;
@property (nonatomic, strong) id videoCodecIdWhitelist;
@end

// ── YTIHamplayerVideoAbrConfig ────────────────────────────────────────────────
@interface YTIHamplayerVideoAbrConfig : NSObject
@property (nonatomic, assign) BOOL preferSoftwareHdrOverHardwareSdr;
@end

// ── YTIHamplayerConfig ────────────────────────────────────────────────────────
@interface YTIHamplayerConfig : NSObject
@property (nonatomic, strong) YTIHamplayerStreamFilter *streamFilter;
@property (nonatomic, strong) YTIHamplayerSoftwareStreamFilter *softwareStreamFilter;
@property (nonatomic, strong) YTIHamplayerVideoAbrConfig *videoAbrConfig;
@property (nonatomic, assign) BOOL disableResolveOverlappingQualitiesByCodec;
@end

// ── YTIHamplayerHotConfig ─────────────────────────────────────────────────────
@interface YTIHamplayerHotConfig : NSObject
- (YTIHamplayerConfig *)hamplayerConfig;
@end

// ── ABR Policy stubs ──────────────────────────────────────────────────────────
@interface MLABRPolicy : NSObject
- (void)setFormats:(NSArray *)formats;
@end

@interface MLABRPolicyNew : MLABRPolicy
@end

@interface MLABRPolicyOld : MLABRPolicy
@end

@interface HAMDefaultABRPolicy : NSObject
- (id)getSelectableFormatDataAndReturnError:(NSError **)error;
- (void)setFormats:(NSArray *)formats;
@end

// ── HAMDefaultVideoDecoderFactory ─────────────────────────────────────────────
@interface HAMDefaultVideoDecoderFactory : NSObject
@end

// ── ML player stubs ───────────────────────────────────────────────────────────
@interface MLHAMPlayerItem : NSObject
- (void)load;
- (void)loadWithInitialSeekRequired:(BOOL)req initialSeekTime:(double)t;
@end

@interface MLHLSMasterPlaylist : NSObject
- (NSArray *)remotePlaylists;
@end

@interface MLHLSStreamSelector : NSObject
- (id)delegate;
- (void)didLoadHLSMasterPlaylist:(id)arg1;
@end

@interface MLVideo : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger fps;
@end

@interface MLVideoDecoderFactory : NSObject
@end

@interface MLHAMQueuePlayer : NSObject
- (MLHAMPlayerItem *)currentItem;
@end

// ── YT config stubs ───────────────────────────────────────────────────────────
@interface YTColdConfig : NSObject
- (BOOL)iosPlayerClientSharedConfigPopulateSwAv1MediaCapabilities;
- (BOOL)iosPlayerClientSharedConfigDisableLibvpxDecoder;
@end

@interface YTHotConfig : NSObject
- (BOOL)iosPlayerClientSharedConfigDisableServerDrivenAbr;
- (BOOL)iosPlayerClientSharedConfigPostponeCabrPreferredFormatFiltering;
- (BOOL)iosPlayerClientSharedConfigHamplayerPrepareVideoDecoderForAvsbdl;
- (BOOL)iosPlayerClientSharedConfigHamplayerAlwaysEnqueueDecodedSampleBuffersToAvsbdl;
@end

@interface YTIIosOnesieHotConfig : NSObject
@end

// ── YT playback stubs ─────────────────────────────────────────────────────────
@interface YTLocalPlaybackController : NSObject
- (id)currentPlayer;
@end

@interface YTSingleVideoController : NSObject
- (id)playerItem;
@end

@interface YTPlayerTapToRetryResponderEvent : NSObject
@end
