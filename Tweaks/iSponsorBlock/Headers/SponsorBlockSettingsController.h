#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <rootless.h>
#import "ColorFunctions.h"

@interface UIView ()
- (UIViewController *)_viewControllerForAncestor;
@end

@interface UITableViewCell ()
- (UITextField *)editableTextField;
- (id)_indexPath;
@end

@interface UISegment : UIView
@end

// Native color swatch button — replaces HBColorWell (no libcolorpicker needed)
@interface YTPColorSwatch : UIButton
@property (nonatomic, strong) UIColor *color;
@end

@interface SponsorBlockTableCell : UITableViewCell <UIColorPickerViewControllerDelegate>
@property (strong, nonatomic) NSString *category;
@property (strong, nonatomic) UIColor *color;
@property (strong, nonatomic) YTPColorSwatch *colorWell;
@end

@interface SponsorBlockSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) NSString *tweakTitle;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray *sectionTitles;
@property (strong, nonatomic) NSMutableDictionary *settings;
@property (strong, nonatomic) NSString *settingsPath;
- (void)enabledSwitchToggled:(UISwitch *)sender;
- (void)switchToggled:(UISwitch *)sender;
- (void)categorySegmentSelected:(UISegmentedControl *)segmentedControl;
@end
