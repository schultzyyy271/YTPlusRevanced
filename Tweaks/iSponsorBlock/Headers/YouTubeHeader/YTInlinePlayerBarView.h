#pragma once
#import <UIKit/UIKit.h>
@class SponsorSegment;
@class YTPlayerViewController;
@interface YTInlinePlayerBarView : UIView
@property (nonatomic, strong) NSMutableArray *sponsorMarkerViews;
@property (nonatomic, strong) NSMutableArray *skipSegments;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, assign) CGFloat totalTime;
@property (nonatomic, weak) YTPlayerViewController *playerViewController;
- (void)removeSponsorMarkers;
- (void)maybeCreateMarkerViewsISB;
@end
