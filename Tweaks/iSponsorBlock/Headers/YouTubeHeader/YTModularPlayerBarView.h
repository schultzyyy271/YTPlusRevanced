#pragma once
#import <UIKit/UIKit.h>
@class SponsorSegment;
@interface YTModularPlayerBarView : UIView
@property (nonatomic, strong) NSMutableArray *sponsorMarkerViews;
@property (nonatomic, strong) NSMutableArray *skipSegments;
@property (nonatomic, assign) CGFloat totalTime;
- (void)removeSponsorMarkers;
- (void)maybeCreateMarkerViewsISB;
@end
