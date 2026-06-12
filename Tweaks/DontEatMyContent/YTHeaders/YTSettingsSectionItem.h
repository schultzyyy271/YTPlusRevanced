#pragma once
#import <Foundation/Foundation.h>
@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)aid switchOn:(BOOL)on switchBlock:(BOOL(^)(id cell, BOOL enabled))block settingItemId:(NSInteger)itemId;
+ (instancetype)itemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)aid detailTextBlock:(NSString*(^)(void))detailBlock selectBlock:(BOOL(^)(id cell, NSUInteger idx))selectBlock;
@end