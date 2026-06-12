#pragma once
#import <UIKit/UIKit.h>
@interface YTPlayerView : UIView
@property (nonatomic, strong) UIView *renderingView;
- (UIView *)renderingView;
@end