#pragma once
#import <Foundation/Foundation.h>
@interface YTVideoDetails : NSObject
@property (nonatomic, copy) NSString *channelId;
@end
@interface YTVideoInfo : NSObject
@property (nonatomic, strong) YTVideoDetails *videoDetails;
@end
@interface YTPlaybackData : NSObject
@property (nonatomic, strong) YTVideoInfo *video;
@end
@interface YTSingleVideo : NSObject
@property (nonatomic, strong) YTVideoInfo *video;
@property (nonatomic, strong) YTPlaybackData *playbackData;
@end
@interface YTSingleVideoController : NSObject
@property (nonatomic, strong) YTSingleVideo *singleVideo;
@end
