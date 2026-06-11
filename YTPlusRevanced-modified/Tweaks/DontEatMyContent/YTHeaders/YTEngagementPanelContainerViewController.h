#pragma once
#import <UIKit/UIKit.h>
@interface YTEngagementPanelContainerViewController : UIViewController
@property (nonatomic, assign) BOOL watchLandscapeEngagementPanel;
@property (nonatomic, assign) BOOL landscapeEngagementPanel;
- (BOOL)isPeekingSupported;
@end