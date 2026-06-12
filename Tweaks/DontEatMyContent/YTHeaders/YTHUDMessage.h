#pragma once
#import <Foundation/Foundation.h>
@interface YTHUDMessage : NSObject
+ (instancetype)messageWithText:(NSString *)text;
- (void)showProgressHUDInView:(UIView *)view;
@end