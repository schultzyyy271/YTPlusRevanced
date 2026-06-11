#pragma once
#import <UIKit/UIKit.h>
@class SponsorSegment;
@interface YTPlayerBarSegmentedProgressView : UIView
@property (strong, nonatomic) NSMutableArray *sponsorMarkerViews;
@property (nonatomic, retain) NSMutableArray *skipSegments;
@property (nonatomic, strong) UILabel *durationLabel;
- (void)removeSponsorMarkers;
@end
