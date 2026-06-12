// YouPiP_Compat.h — single authoritative stub header for YouPiP + LegacyPiPCompat
// Written in dependency order. No duplicates.
#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVKit/AVKit.h>

// ── 1. ML base player stubs ───────────────────────────────────────────────────
@interface MLAVPlayer : NSObject
@property (nonatomic, assign) float rate;
- (BOOL)externalPlaybackActive;
- (instancetype)initWithVideo:(id)video
                 playerConfig:(id)playerConfig
               stickySettings:(id)stickySettings
       externalPlaybackActive:(BOOL)externalPlayback;
@end

@interface MLDefaultPlayerViewFactory : NSObject
- (id)AVPlayerViewForVideo:(id)video playerConfig:(id)playerConfig;
- (id)hamPlayerViewForVideo:(id)video playerConfig:(id)playerConfig;
- (id)hamPlayerViewForPlayerConfig:(id)playerConfig;
@end


@interface MLPlayerPool : NSObject
@end

@interface MLPlayerPoolImpl : NSObject
@end

@interface MLAVPlayerLayerView : UIView
@end

@interface MLAVPIPPlayerLayerView : UIView
- (AVPlayerLayer *)playerLayer;
@end

@interface MLVideoDecoderFactory : NSObject
@end

@interface MLVideo : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger fps;
@end

// ── 2. MLPIPController — must precede observer category ───────────────────────
#ifndef MLPIPController_DEFINED
#define MLPIPController_DEFINED
@interface MLPIPController : NSObject <AVPictureInPictureControllerDelegate>
+ (instancetype)sharedInstance;
- (BOOL)isPictureInPictureSupported;
- (BOOL)isPictureInPictureActive;
- (void)startPictureInPicture;
- (void)stopPictureInPicture;
- (void)activatePiPController;
- (void)deactivatePiPController;
- (void)addPIPControllerObserver:(id)observer;
@end
#endif


// ── 3. Sticky settings / player config ───────────────────────────────────────
@interface MLPlayerStickySettings : NSObject
@property (nonatomic, assign) float rate;
@end

// ── 4. YTI Hamplayer types ────────────────────────────────────────────────────
@interface YTIHamplayerCodecFilter : NSObject
@property (nonatomic, assign) NSInteger maxArea;
@property (nonatomic, assign) NSInteger maxFps;
@end

@interface YTIHamplayerStreamFilter : NSObject
@property (nonatomic, strong) YTIHamplayerCodecFilter *av1;
@property (nonatomic, strong) YTIHamplayerCodecFilter *vp9;
@property (nonatomic, assign) BOOL enableVideoCodecSplicing;
@end

@interface YTIHamplayerVideoAbrConfig : NSObject
@property (nonatomic, assign) BOOL preferSoftwareHdrOverHardwareSdr;
@end

@interface YTIHamplayerConfig : NSObject
@property (nonatomic, strong) YTIHamplayerStreamFilter *streamFilter;
@property (nonatomic, strong) YTIHamplayerVideoAbrConfig *videoAbrConfig;
@property (nonatomic, assign) NSInteger renderViewType;
@property (nonatomic, assign) BOOL disableResolveOverlappingQualitiesByCodec;
@end

@interface YTIHamplayerHotConfig : NSObject
@property (nonatomic, assign) NSInteger renderViewType;
- (YTIHamplayerConfig *)hamplayerConfig;
@end

// ── 5. MLInnerTubePlayerConfig — returns hamplayerConfig ─────────────────────
@interface MLInnerTubePlayerConfig : NSObject
- (YTIHamplayerConfig *)hamplayerConfig;
@end

// ── 6. YT config objects ──────────────────────────────────────────────────────
@interface YTHotConfig : NSObject
- (YTIHamplayerHotConfig *)hamplayerHotConfig;
@end

// ── 7. YT policy / config objects ────────────────────────────────────────────
@interface YTBackgroundabilityPolicy : NSObject
@property (nonatomic, assign) BOOL playableInPiPByUserSettings;
- (void)addBackgroundabilityPolicyObserver:(id)observer;
@end

#ifndef YTSystemNotifications_DEFINED
#define YTSystemNotifications_DEFINED
@interface YTSystemNotifications : NSObject
+ (void)postNotification:(NSString *)notification;
- (void)addSystemNotificationsObserver:(id)observer;
@end
#endif


@interface YTPlayerViewControllerConfig : NSObject
@end

// ── 8. YT player controllers ──────────────────────────────────────────────────
@interface YTPlayerPIPController : NSObject
@property (nonatomic, strong) id backgroundabilityPolicy;
- (BOOL)canEnablePictureInPicture;
- (BOOL)canInvokePictureInPicture;
- (void)maybeEnablePictureInPicture;
- (void)maybeInvokePictureInPicture;
- (void)didStopPictureInPicture;
- (void)appWillResignActive:(id)arg1;
@end

@interface YTPlayerStatus : NSObject
@property (nonatomic, assign) NSInteger visibility;
@end

// ── 9. YT UI stubs ───────────────────────────────────────────────────────────
#ifndef YTColor_DEFINED
#define YTColor_DEFINED
@interface YTColor : NSObject
+ (UIColor *)white1;
@end
#endif

@interface YTColorPalette : NSObject
+ (instancetype)colorPaletteForPageStyle:(NSInteger)pageStyle;
- (UIColor *)textPrimary;
@end

@interface YTCommonColorPalette : NSObject
+ (instancetype)darkPalette;
+ (instancetype)lightPalette;
- (UIColor *)textPrimary;
@end

@interface YTPlaybackStrippedWatchController : NSObject
@end

#ifndef YTTouchFeedbackController_DEFINED
#define YTTouchFeedbackController_DEFINED
@interface YTTouchFeedbackController : NSObject
- (instancetype)initWithView:(UIView *)view;
@end
#endif


@interface YTUIResources : NSObject
+ (BOOL)delhiIconsEnabled;
@end

@interface YTWatchViewController : UIViewController
@end

// ── 10. QTMIcon / YTIIcon ────────────────────────────────────────────────────
@interface QTMIcon : NSObject
+ (UIImage *)tintImage:(UIImage *)image color:(UIColor *)color;
@end


// ── 11. YTAppDelegate / YTAppViewControllerImpl ───────────────────────────────
@interface YTAppViewControllerImpl : UIViewController
- (NSInteger)pageStyle;
@end

@interface YTAppDelegate : NSObject <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

// ── 12. YT overlay view controllers ──────────────────────────────────────────
#ifndef YTMainAppControlsOverlayView_DEFINED
#define YTMainAppControlsOverlayView_DEFINED
@interface YTMainAppControlsOverlayView : UIView
@end
#endif

#ifndef YTMainAppVideoPlayerOverlayViewController_DEFINED
#define YTMainAppVideoPlayerOverlayViewController_DEFINED
@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
- (BOOL)isFullscreen;
- (void)didPressVideoQuality:(id)arg;
@end
#endif

// ── 13. YTPageStyleController ─────────────────────────────────────────────────
@interface YTPageStyleController : NSObject
+ (NSInteger)pageStyle;
+ (YTCommonColorPalette *)currentColorPalette;
@end

// ── 14. YTSettingsSectionItemManager (minimal forward stub) ──────────────────
#ifndef YTSettingsSectionItemManager_STUB
#define YTSettingsSectionItemManager_STUB
#ifndef YTSettingsSectionItemManager_DEFINED
#define YTSettingsSectionItemManager_DEFINED
@interface YTSettingsSectionItemManager : NSObject
@end
#endif
#endif

// ── 15. YTLocalPlaybackController ────────────────────────────────────────────
@interface YTLocalPlaybackController : NSObject
- (id)currentPlayer;
- (BOOL)backgroundable;
@end

// ── 16. ML pool stubs (LegacyPiPCompat.x needs AVPlayerViewForVideo:) ────────
// Already declared above — MLDefaultPlayerViewFactory has AVPlayerViewForVideo:

// ── 17. YT controller stubs needed by LegacyPiPCompat.x ─────────────────────
@interface YTAutonavEndscreenController : NSObject
@end

@interface YTResumeToHomeController : NSObject
@end

@interface YTLiveWatchPlaybackOverlayView : UIView
@end

@interface YTAutonavEndscreenControllerConfig : NSObject
@end


// ── 19. MLHAMQueuePlayer extended for LegacyPiPCompat ────────────────────────
#ifndef MLHAMQueuePlayer_DEFINED
#define MLHAMQueuePlayer_DEFINED
@interface MLHAMQueuePlayer : NSObject
- (id)currentItem;
@end
#endif


@interface MLHAMQueuePlayer (LegacyPiP)
- (instancetype)initWithStickySettings:(MLPlayerStickySettings *)stickySettings
                    playerViewProvider:(MLPlayerPoolImpl *)playerViewProvider
                   playerConfiguration:(void *)playerConfiguration;
- (instancetype)initWithStickySettings:(MLPlayerStickySettings *)stickySettings
                    playerViewProvider:(MLPlayerPoolImpl *)playerViewProvider
                   playerConfiguration:(void *)playerConfiguration
                   mediaPlayerResources:(id)mediaPlayerResources;
@end

// ── YouPiP/Tweak.x additional stubs ─────────────────────────────────────────

// ASCollectionView — base for (YP) category in Tweak.x
#ifndef ASCollectionView_DEFINED
#define ASCollectionView_DEFINED
@interface ASCollectionView : UICollectionView
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section;
@end
#endif

// ELMCellNode / ELMContainerNode
#ifndef ELMCellNode_DEFINED
#define ELMCellNode_DEFINED
@interface ASDisplayNode : NSObject
@property (nonatomic, strong) NSArray *yogaChildren;
@property (nonatomic, assign) CGSize calculatedSize;
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic, strong) id layoutAttributes;
@property (nonatomic, strong) UIView *view;
- (void)addYogaChild:(id)child;
- (void)relayoutNode;
@end
@interface ELMCellNode : ASDisplayNode
@end
@interface ELMContainerNode : ASDisplayNode
@end
#endif

// YTPlayerViewController
#ifndef YTPlayerViewController_DEFINED
#define YTPlayerViewController_DEFINED
@interface YTPlayerViewController : UIViewController
- (NSString *)contentVideoID;
@end
#endif


// YTIIcon with iconType property and PiP constant
#ifndef YT_PICTURE_IN_PICTURE
#define YT_PICTURE_IN_PICTURE 454
#endif
#ifndef YTIIcon_DEFINED
#define YTIIcon_DEFINED
@interface YTIIcon : NSObject
@property (nonatomic, assign) NSInteger iconType;
@end
#endif


#ifndef YT_PICTURE_IN_PICTURE
#define YT_PICTURE_IN_PICTURE 454
#endif

@interface YTIIcon (YouPiP)
@property (nonatomic, assign) NSInteger iconType;
@end

// YTTouchFeedbackView — has customCornerRadius
@interface YTTouchFeedbackView : UIView
@property (nonatomic, assign) CGFloat customCornerRadius;
@end

// ── Complete YouPiP additions ─────────────────────────────────────────────────

// MLHAMSBDLSampleBufferRenderingView
@interface MLHAMSBDLSampleBufferRenderingView : UIView
@end

// MLPIPController extra methods
@interface MLPIPController (YouPiPMethods)
- (BOOL)pictureInPictureActive;
- (CGSize)renderSizeForView:(id)view;
- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)pip;
- (void)pictureInPictureControllerStartPlayback;
- (void)pictureInPictureControllerStopPlayback;
@end

// ASCollectionNode — what collectionNode returns
@interface ASCollectionNode : NSObject
- (UIViewController *)closestViewController;
@end

// ASCollectionView collectionNode property
@interface ASCollectionView (YouPiPNode)
@property (nonatomic, strong) ASCollectionNode *collectionNode;
@end

// YTTouchFeedbackController touchFeedbackView
@interface YTTouchFeedbackController (YouPiP)
@property (nonatomic, strong) YTTouchFeedbackView *touchFeedbackView;
@end


// YTSystemNotificationsObserver protocol
@protocol YTSystemNotificationsObserver <NSObject>
@optional
- (void)appWillResignActive:(UIApplication *)application;
- (void)appWillEnterForeground:(UIApplication *)application;
@end

// YTSystemNotifications callBlockForEveryObserver:
@interface YTSystemNotifications (YouPiP)
- (void)callBlockForEveryObserver:(void(^)(id<YTSystemNotificationsObserver> observer))block;
@end

// YTIIosMediaHotConfig
@interface YTIIosMediaHotConfig : NSObject
- (BOOL)enablePictureInPicture;
- (BOOL)enablePipForNonBackgroundableContent;
- (BOOL)enablePipForNonPremiumUsers;
@end

// YTSingleVideo
@interface YTSingleVideo : NSObject
- (BOOL)isLivePlayback;
@end

// YTIPlayabilityStatus
@interface YTIPlayabilityStatus : NSObject
- (BOOL)isPlayableInPictureInPicture;
- (BOOL)hasPictureInPicture;
@end

// AVPictureInPicturePlatformAdapter
@interface AVPictureInPicturePlatformAdapter : NSObject
- (BOOL)isSystemPictureInPicturePossible;
@end
