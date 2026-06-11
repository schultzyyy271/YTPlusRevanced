#pragma once
#import <UIKit/UIKit.h>
@protocol YTPlayerBarProtocol <NSObject>
@optional
@property (nonatomic, strong) id playerBar;
@property (nonatomic, strong) id modularPlayerBar;
@property (nonatomic, strong) id segmentablePlayerBar;
@property (nonatomic, strong) UILabel *durationLabel;
@end
