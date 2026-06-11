#pragma once
#import <UIKit/UIKit.h>
#import "YTPlayerBarProtocol.h"
@class YTMainAppControlsOverlayView;
@interface YTMainAppVideoPlayerOverlayView : UIView
@property (nonatomic, strong) id<YTPlayerBarProtocol> playerBar;
@property (nonatomic, strong) YTMainAppControlsOverlayView *controlsOverlayView;
@end
