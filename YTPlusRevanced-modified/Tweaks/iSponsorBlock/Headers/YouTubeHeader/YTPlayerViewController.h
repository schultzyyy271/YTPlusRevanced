#pragma once
#import <UIKit/UIKit.h>
@class YTSingleVideoController;
@class MBProgressHUD;
@class SponsorSegment;
@class YTPlayerOverlayManager;

@interface YTPlayerViewController : UIViewController
@property (nonatomic, assign) NSInteger currentSponsorSegment;
@property (nonatomic, strong) MBProgressHUD *hud;
@property (nonatomic, assign) NSInteger unskippedSegment;
@property (nonatomic, assign) BOOL hudDisplayed;
@property (nonatomic, copy) NSString *channelID;
@property (nonatomic, strong) YTSingleVideoController *activeVideo;
@property (nonatomic, assign) BOOL isPlayingAd;
@property (nonatomic, assign) CGFloat currentVideoTotalMediaTime;
@property (nonatomic, assign) CGFloat currentVideoMediaTime;
@property (nonatomic, copy) NSString *currentVideoID;
@property (nonatomic, strong) YTPlayerOverlayManager *overlayManager;
- (BOOL)isMDXActive;
- (NSInteger)playerViewLayout;
- (void)didPressToggleFullscreen;
- (void)scrubToTime:(CGFloat)time;
- (void)seekToTime:(CGFloat)time;
- (void)isb_scrubToTime:(CGFloat)time;
- (void)isb_fixVisualGlitch;
@end
