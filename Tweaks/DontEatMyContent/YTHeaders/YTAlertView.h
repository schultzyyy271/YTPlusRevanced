#ifndef YTAlertView_DEFINED
#define YTAlertView_DEFINED
#pragma once
#import <UIKit/UIKit.h>
@interface YTAlertView : UIView
+ (instancetype)confirmationDialogWithAction:(void(^)(void))action actionTitle:(NSString *)title;
- (void)show;
@end
#endif
