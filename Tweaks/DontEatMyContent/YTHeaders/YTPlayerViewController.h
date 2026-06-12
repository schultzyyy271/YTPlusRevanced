#pragma once
#import <UIKit/UIKit.h>
@interface YTPlayerViewController : UIViewController
- (NSString *)contentVideoID;
- (id)playerView;
- (id)activeVideoPlayerOverlay;
- (BOOL)isCurrentVideoVertical;
@end