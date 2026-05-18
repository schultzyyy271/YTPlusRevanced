#pragma once
#import <UIKit/UIKit.h>
@interface QTMIcon : NSObject
+ (UIImage *)tintImage:(UIImage *)image color:(UIColor *)color;
@end
@interface YTQTMButton : UIButton
+ (instancetype)iconButton;
- (void)enableNewTouchFeedback;
@end
