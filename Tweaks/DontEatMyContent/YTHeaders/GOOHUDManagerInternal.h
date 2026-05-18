#ifndef GOOHUDManagerInternal_DEFINED
#define GOOHUDManagerInternal_DEFINED
#pragma once
#import <Foundation/Foundation.h>
@interface GOOHUDManagerInternal : NSObject
+ (instancetype)sharedInstance;
- (void)showMessageMainQueue:(id)message;
- (void)showMessageMainThread:(id)message;
@end
#endif
