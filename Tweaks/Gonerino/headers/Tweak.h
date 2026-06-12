#pragma once
#import "Util.h"

#import "ChannelManager.h"
#import "VideoManager.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>


NS_ASSUME_NONNULL_BEGIN

#ifndef YTAsyncCollectionView_DEFINED
#define YTAsyncCollectionView_DEFINED
@interface YTAsyncCollectionView : UICollectionView

- (void)layoutSubviews;

- (void)performBatchUpdates:(void(NS_NOESCAPE ^ _Nullable)(void))updates
                 completion:(void (^_Nullable)(BOOL finished))completion;

- (NSArray<UICollectionViewCell *> *)visibleCells;

- (nullable NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell;

- (void)removeOffendingCells;

@end
#endif


#ifndef _ASCollectionViewCell_DEFINED
#define _ASCollectionViewCell_DEFINED
@interface _ASCollectionViewCell : UICollectionViewCell

- (nullable ASDisplayNode *)node;

@end
#endif


@interface ASDisplayNode : NSObject

@property(nonatomic, copy, nullable) NSString *accessibilityLabel;
@property(nonatomic, copy, nullable) NSString *accessibilityIdentifier;

- (nullable NSArray<ASDisplayNode *> *)subnodes;

@end

@interface ASTextNode : ASDisplayNode

@property(nonatomic, copy, nullable) NSAttributedString *attributedText;

@end

@interface NSObject (ChannelName)

- (nullable NSString *)channelName;
- (nullable NSString *)ownerName;

@end

@interface YTWatchController : NSObject
@property(nonatomic, strong, readonly) YTSingleVideoController *singleVideoController;
- (YTSingleVideoController *)valueForKey:(NSString *)key;
@end

@interface YTSingleVideoController : NSObject
@property(nonatomic, copy, readonly) NSString *channelName;
- (NSString *)valueForKey:(NSString *)key;
@end

#ifndef YTDefaultSheetController_DEFINED
#define YTDefaultSheetController_DEFINED
@interface YTDefaultSheetController : NSObject
- (void)addAction:(YTActionSheetAction *)action;
- (void)dismiss;
- (id)valueForKey:(NSString *)key;
- (UIImage *)createBlockIconWithOriginalAction:(nullable YTActionSheetAction *)originalAction;
- (UIViewController *)findViewControllerForView:(UIView *)view;
- (void)extractChannelNameFromNode:(id)node completion:(void (^)(NSString *channelName))completion;
- (nullable NSString *)extractVideoTitleFromNode:(id)node;
- (NSArray<YTActionSheetAction *> *)actions;  // Added this line
@end
#endif


#ifndef YTActionSheetAction_DEFINED
#define YTActionSheetAction_DEFINED
@interface YTActionSheetAction : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) void (^handler)(id);
@property(nonatomic, strong) UIImage *iconImage;
@property(nonatomic) BOOL shouldDismissOnAction;

+ (instancetype)actionWithTitle:(NSString *)title
                      iconImage:(UIImage *)iconImage
                          style:(NSInteger)style
                        handler:(void (^)(id))handler;

+ (instancetype)actionWithTitle:(NSString *)title iconImage:(UIImage *)iconImage handler:(void (^)(id))handler;
@end
#endif


@interface YTActionSheetController : UIViewController
- (void)presentFromView:(UIView *)view;
- (NSArray<YTActionSheetAction *> *)actions;
- (void)addAction:(YTActionSheetAction *)action;
- (void)dismiss;
- (UIViewController *)findViewControllerForView:(UIView *)view;
@end
#ifndef YTToastResponderEvent_DEFINED
#define YTToastResponderEvent_DEFINED
@interface YTToastResponderEvent : NSObject
+ (instancetype)eventWithMessage:(NSString *)message firstResponder:(UIViewController *)responder;
- (void)send;
@end
#endif


#ifndef YTSettingsSectionItem_DEFINED
#define YTSettingsSectionItem_DEFINED
@interface YTSettingsSectionItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title
             titleDescription:(nullable NSString *)titleDescription
      accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
              detailTextBlock:(nullable NSString * (^)(void))detailTextBlock
                  selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))selectBlock
                settingItemId:(NSUInteger)settingItemId;
@end
#endif


@interface YTICommand : NSObject
@property(copy, nonatomic) NSString *description;
@end

@interface YTInlinePlaybackPlayerDescriptor : NSObject
@property(retain, nonatomic) id navigationEndpoint;
@end

@interface YTASDPlayableEntry : NSObject
@property(retain, nonatomic) YTICommand *navigationEndpoint;
@property(nonatomic) BOOL hasNavigationEndpoint;
@property(copy, nonatomic) NSString *description;
@end

@interface YTElementsInlineMutedPlaybackView : NSObject
@property(retain, nonatomic) YTASDPlayableEntry *asdPlayableEntry;
@end

@interface ELMContext : NSObject
- (id)elementForKey:(NSString *)key;
@end

@interface ELMElement : NSObject
@property(retain, nonatomic) id properties;
@property(retain, nonatomic) ELMContext *context;
- (id)propertyForKey:(NSString *)key;
- (NSDictionary *)allProperties;
- (id)valueForKey:(NSString *)key;
@end

@interface YTInlinePlaybackPlayerNode : ASDisplayNode
@property(nonatomic, readonly) id playbackView;
@property(nonatomic, readonly) ELMElement *element;
@property(nonatomic, readonly) ELMContext *context;
- (id)playbackView;
@end

#ifndef YTRightNavigationButtons_DEFINED
#define YTRightNavigationButtons_DEFINED
@interface YTRightNavigationButtons : UIView
@property (retain, nonatomic, nullable) YTQTMButton *gonerinoButton;
- (NSMutableArray *)buttons;
- (NSMutableArray *)visibleButtons;
- (void)gonerinoButtonPressed:(UIButton *)sender;
@end
#endif


#ifndef YTQTMButton_DEFINED
#define YTQTMButton_DEFINED
@interface YTQTMButton : UIButton
+ (instancetype)iconButton;
- (void)enableNewTouchFeedback;
@end
#endif


@interface QTMIcon : NSObject
+ (UIImage *)tintImage:(UIImage *)image color:(UIColor *)color;
@end

#ifndef YTPageStyleController_DEFINED
#define YTPageStyleController_DEFINED
@interface YTPageStyleController : NSObject
+ (NSInteger)pageStyle;
@end
#endif


#ifndef YTAppDelegate_DEFINED
#define YTAppDelegate_DEFINED
@interface YTAppDelegate : NSObject
@end
#endif


#ifndef YTAppViewControllerImpl_DEFINED
#define YTAppViewControllerImpl_DEFINED
@interface YTAppViewControllerImpl : NSObject
- (NSInteger)pageStyle;
@end
#endif


NS_ASSUME_NONNULL_END
