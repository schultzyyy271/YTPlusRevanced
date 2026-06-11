#pragma once
#import <Foundation/Foundation.h>
@interface YTIModularPlayerBarPlayingState : NSObject
@property (nonatomic, assign) CGFloat totalTimeSec;
@end
@interface YTIModularPlayerBarModel : NSObject
@property (nonatomic, strong) YTIModularPlayerBarPlayingState *playingState;
@end
