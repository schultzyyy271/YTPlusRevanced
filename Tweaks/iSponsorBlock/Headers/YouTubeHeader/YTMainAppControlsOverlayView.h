#pragma once
#import <UIKit/UIKit.h>
#import "QTMIcon.h"
@class YTPlayerViewController;
@interface YTMainAppControlsOverlayView : UIView
+ (CGFloat)topButtonAdditionalPadding;
- (YTQTMButton *)buttonWithImage:(UIImage *)image accessibilityLabel:(NSString *)label verticalContentPadding:(CGFloat)padding;
- (void)setOverlayVisible:(BOOL)visible;
- (void)sponsorBlockButtonPressed:(YTQTMButton *)sender;
- (void)sponsorStartedButtonPressed:(YTQTMButton *)sender;
- (void)sponsorEndedButtonPressed:(YTQTMButton *)sender;
- (void)presentSponsorBlockViewController;
@property (retain, nonatomic) YTQTMButton *sponsorBlockButton;
@property (retain, nonatomic) YTQTMButton *sponsorStartedEndedButton;
@property (nonatomic, assign) BOOL isDisplayingSponsorBlockViewController;
@property (nonatomic, weak) YTPlayerViewController *playerViewController;
@end
