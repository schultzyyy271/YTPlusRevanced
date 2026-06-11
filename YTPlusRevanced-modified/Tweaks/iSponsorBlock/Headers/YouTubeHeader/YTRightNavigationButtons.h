#pragma once
#import <UIKit/UIKit.h>
#import "QTMIcon.h"
@interface YTRightNavigationButtons : UIView
@property (strong, nonatomic) YTQTMButton *sponsorBlockButton;
- (void)setLeadingPadding:(CGFloat)padding;
@end
