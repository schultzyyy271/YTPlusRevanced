#pragma once
#import <UIKit/UIKit.h>
@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)title pickerSectionTitle:(NSString *)sectionTitle rows:(NSArray *)rows selectedItemIndex:(NSUInteger)index parentResponder:(id)responder;
@end