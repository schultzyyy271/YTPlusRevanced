// Gonerino_Compat.h - stubs for Gonerino headers not in theos
#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// YTAlertView
#ifndef YTAlertView_DEFINED
#define YTAlertView_DEFINED
@interface YTAlertView : UIView
+ (instancetype)confirmationDialogWithAction:(void(^)(void))action actionTitle:(NSString *)title;
- (void)show;
@end
#endif

// YTAppSettingsSectionItemActionController
@interface YTAppSettingsSectionItemActionController : NSObject
@end

// YTSearchableSettingsViewController
@interface YTSearchableSettingsViewController : UIViewController
@end

// YTSettingsGroupData
#ifndef YTSettingsGroupData_DEFINED
#define YTSettingsGroupData_DEFINED
@interface YTSettingsGroupData : NSObject
@property (nonatomic, assign) NSInteger type;
- (NSArray *)orderedCategories;
@end
#endif

// YTSettingsPickerViewController
#ifndef YTSettingsPickerViewController_DEFINED
#define YTSettingsPickerViewController_DEFINED
@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)title pickerSectionTitle:(NSString *)sectionTitle rows:(NSArray *)rows selectedItemIndex:(NSUInteger)index parentResponder:(id)responder;
@end
#endif

// YTSettingsSectionItem
#ifndef YTSettingsSectionItem_DEFINED
#define YTSettingsSectionItem_DEFINED
@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)desc accessibilityIdentifier:(NSString *)aid switchOn:(BOOL)on switchBlock:(BOOL(^)(id cell, BOOL enabled))block settingItemId:(NSInteger)itemId;
+ (instancetype)itemWithTitle:(NSString *)title titleDescription:(NSString *)desc accessibilityIdentifier:(NSString *)aid detailTextBlock:(NSString*(^)(void))detailBlock selectBlock:(BOOL(^)(id cell, NSUInteger idx))selectBlock settingItemId:(NSInteger)itemId;
+ (instancetype)itemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)aid detailTextBlock:(NSString*(^)(void))detailBlock selectBlock:(BOOL(^)(id cell, NSUInteger idx))selectBlock;
@end
#endif

// YTSettingsSectionItemManager
#ifndef YTSettingsSectionItemManager_DEFINED
#define YTSettingsSectionItemManager_DEFINED
@interface YTSettingsSectionItemManager : NSObject
@end
#endif

// YTSettingsViewController
#ifndef YTSettingsViewController_DEFINED
#define YTSettingsViewController_DEFINED
@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)desc headerHidden:(BOOL)hidden;
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)desc headerHidden:(BOOL)hidden;
- (void)pushViewController:(UIViewController *)vc;
- (id)parentResponder;
@end
#endif

// YTSettingsCell
#ifndef YTSettingsCell_DEFINED
#define YTSettingsCell_DEFINED
@interface YTSettingsCell : UITableViewCell
@end
#endif

// YTToastResponderEvent
#ifndef YTToastResponderEvent_DEFINED
#define YTToastResponderEvent_DEFINED
@interface YTToastResponderEvent : NSObject
+ (instancetype)eventWithMessage:(NSString *)message firstResponder:(id)responder;
- (void)send;
@end
#endif

// YTIIcon with iconType
#ifndef YTIIcon_DEFINED
#define YTIIcon_DEFINED
@interface YTIIcon : NSObject
@property (nonatomic, assign) NSInteger iconType;
@end
#endif

#ifndef YT_SETTINGS
#define YT_SETTINGS 352
#endif

// YTHotConfig stubs (Gonerino's Settings.h imports this)
#ifndef YTHotConfig_DEFINED
#define YTHotConfig_DEFINED
@interface YTHotConfig : NSObject
- (BOOL)isPromptForLocalNetworkPermissionsEnabled;
@end
#endif

// GOOHUDManagerInternal
#ifndef GOOHUDManagerInternal_DEFINED
#define GOOHUDManagerInternal_DEFINED
@interface GOOHUDManagerInternal : NSObject
+ (instancetype)sharedInstance;
- (void)showMessageMainQueue:(id)message;
- (void)showMessageMainThread:(id)message;
@end
#endif

// YTCommonUtils
#ifndef YTCommonUtils_DEFINED
#define YTCommonUtils_DEFINED
@interface YTCommonUtils : NSObject
+ (NSString *)yt_appVersion;
@end
#endif

// YTVersionUtils
#ifndef YTVersionUtils_DEFINED
#define YTVersionUtils_DEFINED
@interface YTVersionUtils : NSObject
+ (NSString *)appVersion;
@end
#endif

// SECTION_HEADER macro
#ifndef SECTION_HEADER
#define SECTION_HEADER(title) \
    [sectionItems addObject:[%c(YTSettingsSectionItem) itemWithTitle:(title) \
        accessibilityIdentifier:nil \
        detailTextBlock:nil \
        selectBlock:^BOOL(id c, NSUInteger i) { return NO; }]];
#endif

// YTGlobalConfig
@interface YTGlobalConfig : NSObject
@end

// YTColdConfig
#ifndef YTColdConfig_DEFINED
#define YTColdConfig_DEFINED
@interface YTColdConfig : NSObject
@end
#endif

// YTColdConfig (extended for YTweaks casting hooks)
@interface YTColdConfig (YTweaks)
- (BOOL)cxClientEnableIosLocalNetworkPermissionReliabilityFixes;
- (BOOL)cxClientEnableIosLocalNetworkPermissionUsingSockets;
- (BOOL)cxClientEnableIosLocalNetworkPermissionWifiFixes;
@end

// YTIElementRenderer
@interface YTIElementRenderer : NSObject
- (NSData *)elementData;
@end

// YTMainAppVideoPlayerOverlayView (YTweaks virtual bezel)
@interface YTMainAppVideoPlayerOverlayView : UIView
@end

// YTWatchViewController (YTweaks fullscreen)
@interface YTWatchViewController : UIViewController
- (UIInterfaceOrientationMask)allowedFullScreenOrientations;
@end

// YTAppSettingsGroupPresentationData (YouGroupSettings)
@interface YTAppSettingsGroupPresentationData : NSObject
+ (NSArray *)orderedGroups;
@end

// UIDevice+YouTube
@interface UIDevice (YouTube)
- (BOOL)yt_isPortrait;
@end


// YTQTMButton - full stub with iconButton and enableNewTouchFeedback
#ifndef YTQTMButton_DEFINED
#define YTQTMButton_DEFINED
@interface YTQTMButton : UIButton
+ (nonnull instancetype)iconButton;
- (void)enableNewTouchFeedback;
@end
#endif

// ── Full interface stubs for Gonerino hooked classes ──────────────────────────
// Declared here (before Tweak.h) so they are visible before Logos generates @class forward decls.

#ifndef YTAsyncCollectionView_DEFINED
#define YTAsyncCollectionView_DEFINED
@interface YTAsyncCollectionView : UICollectionView
- (void)layoutSubviews;
- (void)performBatchUpdates:(void (NS_NOESCAPE ^ _Nullable)(void))updates completion:(void (^ _Nullable)(BOOL))completion;
- (NSArray<UICollectionViewCell *> *)visibleCells;
- (nullable NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell;
- (void)removeOffendingCells;
@property (nonatomic, weak, nullable) id pageStylingDelegate;
@end
#endif

#ifndef _ASCollectionViewCell_DEFINED
#define _ASCollectionViewCell_DEFINED
@interface _ASCollectionViewCell : UICollectionViewCell
- (nullable id)node;
@end
#endif

#ifndef YTDefaultSheetController_DEFINED
#define YTDefaultSheetController_DEFINED
@interface YTDefaultSheetController : NSObject
- (void)addAction:(nonnull id)action;
- (void)dismiss;
- (nullable id)valueForKey:(nonnull NSString *)key;
- (nonnull NSArray *)actions;
@end
#endif

#ifndef YTActionSheetAction_DEFINED
#define YTActionSheetAction_DEFINED
@interface YTActionSheetAction : NSObject
@property (nonatomic, copy, nonnull) NSString *title;
@property (nonatomic, strong, nullable) UIImage *iconImage;
+ (nonnull instancetype)actionWithTitle:(nonnull NSString *)title iconImage:(nullable UIImage *)image style:(NSInteger)style handler:(nullable void (^)(id))handler;
@end
#endif

#ifndef YTRightNavigationButtons_DEFINED
#define YTRightNavigationButtons_DEFINED
@interface YTRightNavigationButtons : UIView
@property (retain, nonatomic, nullable) YTQTMButton *gonerinoButton;
- (nonnull NSMutableArray *)buttons;
- (nonnull NSMutableArray *)visibleButtons;
@end
#endif
// ── Stubs needed before Logos @class forward declarations ────────────────────
// Logos generates @class for all hooked classes, shadowing full @interface.
// These must be declared here (imported before Tweak.h) to survive that.

#ifndef Util_DEFINED
#define Util_DEFINED
@interface Util : NSObject
+ (BOOL)nodeContainsBlockedVideo:(nonnull id)node;
+ (nonnull UIImage *)createBlockChannelIconWithSize:(CGSize)size;
+ (nonnull UIImage *)createBlockVideoIconWithSize:(CGSize)size;
+ (void)extractVideoInfoFromNode:(nonnull id)node completion:(void (^ _Nonnull)(NSString * _Nullable, NSString * _Nullable, NSString * _Nullable))completion;
@end
#endif

#ifndef YTPageStyleController_DEFINED
#define YTPageStyleController_DEFINED
@interface YTPageStyleController : NSObject
+ (NSInteger)pageStyle;
@end
#endif

#ifndef YTAppDelegate_DEFINED
#define YTAppDelegate_DEFINED
@interface YTAppDelegate : NSObject <UIApplicationDelegate>
@end
#endif

#ifndef YTAppViewControllerImpl_DEFINED
#define YTAppViewControllerImpl_DEFINED
@interface YTAppViewControllerImpl : NSObject
- (NSInteger)pageStyle;
@end
#endif


// ── Additional stubs needed by Gonerino/sources/Tweak.x ─────────────────────

// NSObject subnodes category (node is typed `id`, needs subnodes method)
@interface NSObject (GonerinoNode)
- (nullable NSArray *)subnodes;
@end

// ChannelManager
#ifndef ChannelManager_DEFINED
#define ChannelManager_DEFINED
@interface ChannelManager : NSObject
+ (nonnull instancetype)sharedInstance;
- (void)addBlockedChannel:(nonnull NSString *)channel;
@end
#endif

// VideoManager
#ifndef VideoManager_DEFINED
#define VideoManager_DEFINED
@interface VideoManager : NSObject
+ (nonnull instancetype)sharedInstance;
- (void)addBlockedVideo:(nonnull NSString *)videoId title:(nullable NSString *)title channel:(nullable NSString *)channel;
@end
#endif


// QTMIcon
#ifndef QTMIcon_DEFINED
#define QTMIcon_DEFINED
@interface QTMIcon : NSObject
+ (nullable UIImage *)tintImage:(nullable UIImage *)image color:(nullable UIColor *)color;
@end
#endif


NS_ASSUME_NONNULL_END
