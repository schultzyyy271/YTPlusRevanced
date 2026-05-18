#pragma once
#import <UIKit/UIKit.h>
#import "YTPlayerBarProtocol.h"
@interface YTInlinePlayerBarContainerView : UIView
@property (nonatomic, strong, readwrite) id modularPlayerBar;
@property (nonatomic, strong) UILabel *durationLabel;
- (id)playerBar;
- (id)segmentablePlayerBar;
@end
