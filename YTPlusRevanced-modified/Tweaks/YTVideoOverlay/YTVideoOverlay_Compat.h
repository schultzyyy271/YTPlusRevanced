// YTVideoOverlay_Compat.h
// Forward declarations for all YT classes used by YTVideoOverlay/Tweak.x
// so it compiles inline without the YouTubeHeader package.
#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// rootless.h may not provide PS_ROOT_PATH_NS on all Theos installs.
#if __has_include(<rootless.h>)
#import <rootless.h>
#endif
#ifndef PS_ROOT_PATH_NS
#define PS_ROOT_PATH_NS(x) (x)
#endif

// ── UIView+YouTube category ──────────────────────────────────────────────────
@interface UIView (YouTube)
- (UIViewController *)_viewControllerForAncestor;
- (id)_findFirstResponder;
- (void)yt_setWidth:(CGFloat)width;
- (BOOL)yt_isVisible;
@end

// ── YTFrostedGlassView ──────────────────────────────────────────────────────
@interface YTFrostedGlassView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
+ (NSInteger)frostedGlassBlurEffectStyle;
- (instancetype)initWithBlurEffectStyle:(NSInteger)style alpha:(CGFloat)alpha;
- (instancetype)initWithBlurEffectStyle:(NSInteger)style;
- (void)maybeApplyToView:(UIView *)view;
@end

// ── YTQTMButton ─────────────────────────────────────────────────────────────
#ifndef YTQTMButton_DEFINED
#define YTQTMButton_DEFINED
@interface YTQTMButton : UIButton
@property (nonatomic, strong) UIColor *customTitleColor;
@property (nonatomic, assign) CGFloat verticalContentPadding;
@property (nonatomic, assign) CGFloat minHitTargetSize;
+ (instancetype)iconButton;
+ (instancetype)textButton;
+ (instancetype)buttonWithImage:(UIImage *)image accessibilityLabel:(NSString *)label verticalContentPadding:(CGFloat)padding;
- (void)enableNewTouchFeedback;
+ (CGFloat)topButtonAdditionalPadding;
@end
#endif

// ── YTMainAppVideoPlayerOverlayViewController ───────────────────────────────
#ifndef YTMainAppVideoPlayerOverlayViewController_DEFINED
#define YTMainAppVideoPlayerOverlayViewController_DEFINED
@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@end
#endif

// ── YTInlinePlayerBarContainerView ──────────────────────────────────────────
#ifndef YTInlinePlayerBarContainerView_DEFINED
#define YTInlinePlayerBarContainerView_DEFINED
@interface YTInlinePlayerBarContainerView : UIView
@property (nonatomic, weak) id delegate;
@property (nonatomic, assign) NSInteger layout;
- (UIView *)multiFeedElementView;
- (YTQTMButton *)enterFullscreenButton;
- (YTQTMButton *)exitFullscreenButton;
- (UIView *)peekableView;
@end
#endif

// ── YTMainAppControlsOverlayView ────────────────────────────────────────────
#ifndef YTMainAppControlsOverlayView_DEFINED
#define YTMainAppControlsOverlayView_DEFINED
@interface YTMainAppControlsOverlayView : UIView
+ (CGFloat)topButtonAdditionalPadding;
- (YTQTMButton *)buttonWithImage:(UIImage *)image accessibilityLabel:(NSString *)label verticalContentPadding:(CGFloat)padding;
@end
#endif

// ── YTSettingsSectionItemManager ────────────────────────────────────────────
#ifndef YTSettingsSectionItemManager_DEFINED
#define YTSettingsSectionItemManager_DEFINED
@interface YTSettingsSectionItemManager : NSObject
- (id)parentResponder;
@end
#endif

// ── Settings classes ────────────────────────────────────────────────────────

#ifndef YTSettingsGroupData_DEFINED
#define YTSettingsGroupData_DEFINED
@interface YTSettingsGroupData : NSObject
@property (nonatomic, assign) NSInteger type;
- (NSArray <NSNumber *> *)orderedCategories;
@end
#endif

#ifndef YTAppSettingsPresentationData_DEFINED
#define YTAppSettingsPresentationData_DEFINED
@interface YTAppSettingsPresentationData : NSObject
+ (NSArray <NSNumber *> *)settingsCategoryOrder;
@end
#endif

#ifndef YTSettingsSectionItem_DEFINED
#define YTSettingsSectionItem_DEFINED
@interface YTSettingsSectionItem : NSObject
@property (nonatomic, assign) BOOL enabled;
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier switchOn:(BOOL)on switchBlock:(id)switchBlock settingItemId:(NSInteger)itemId;
+ (instancetype)itemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)identifier detailTextBlock:(id)detailBlock selectBlock:(id)selectBlock;
+ (instancetype)itemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier detailTextBlock:(id)detailBlock selectBlock:(id)selectBlock;
+ (instancetype)checkmarkItemWithTitle:(NSString *)title titleDescription:(NSString *)description selectBlock:(id)selectBlock;
@end
#endif

#ifndef YTSettingsPickerViewController_DEFINED
#define YTSettingsPickerViewController_DEFINED
@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)navTitle pickerSectionTitle:(NSString *)sectionTitle rows:(NSArray *)rows selectedItemIndex:(NSUInteger)index parentResponder:(id)responder;
@end
#endif

// icon: parameter typed as id — accepts both UIImage and YTIIcon at runtime
#ifndef YTSettingsViewController_DEFINED
#define YTSettingsViewController_DEFINED
@interface YTSettingsViewController : UIViewController
- (void)pushViewController:(UIViewController *)vc;
- (void)reloadData;
- (void)setSectionItems:(NSArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)hidden;
- (void)setSectionItems:(NSArray *)items forCategory:(NSUInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)hidden;
@end
#endif

// ── Type style helpers ──────────────────────────────────────────────────────

#ifndef YTColor_DEFINED
#define YTColor_DEFINED
@interface YTColor : NSObject
+ (UIColor *)blackPureAlpha0;
+ (UIColor *)white1;
@end
#endif

@interface YTDefaultTypeStyle : NSObject
- (UIFont *)ytSansFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
- (UIFont *)fontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
@end

@interface YTTypeStyle : NSObject
+ (YTDefaultTypeStyle *)defaultTypeStyle;
@end

// ── YTSettingsCell ──────────────────────────────────────────────────────────
#ifndef YTSettingsCell_DEFINED
#define YTSettingsCell_DEFINED
@interface YTSettingsCell : UITableViewCell
@end
#endif

// ── YTMainAppVideoPlayerOverlayView (NOT the *Controller) ───────────────────
#ifndef YTMainAppVideoPlayerOverlayView_DEFINED
#define YTMainAppVideoPlayerOverlayView_DEFINED
@interface YTMainAppVideoPlayerOverlayView : UIView
@end
#endif

@interface YTMainAppVideoPlayerOverlayViewController (Overlay)
- (YTMainAppVideoPlayerOverlayView *)videoPlayerOverlayView;
- (void)updateTopRightButtonAvailability;
@end

// ── YTIIcon + YT_TV ─────────────────────────────────────────────────────────
#ifndef YT_TV
#define YT_TV 267
#endif
#ifndef YTIIcon_DEFINED
#define YTIIcon_DEFINED
@interface YTIIcon : NSObject
@property (nonatomic, assign) NSInteger iconType;
@end
#endif

// ── YouQuality stubs ────────────────────────────────────────────────────────

@interface MLMIMEType : NSObject
- (uint32_t)videoCodec;
@end

@interface MLFormat : NSObject
- (NSString *)qualityLabel;
- (double)FPS;
- (MLMIMEType *)MIMEType;
- (NSInteger)bitrate;
- (NSInteger)width;
- (NSInteger)height;
@end

@interface YTVideoQualitySwitchOriginalController : NSObject
@end
@interface YTVideoQualitySwitchRedesignedController : NSObject
@end

@interface YTMainAppVideoPlayerOverlayViewController (YouQuality)
- (void)didPressVideoQuality:(id)arg;
@end
