// YouTubeHeaders.h - Forward declarations for YouTube 21.x classes
// These are minimal stubs needed so the compiler is happy; actual classes
// are resolved at runtime via Objective-C message passing.

// ─── Base class stubs ─────────────────────────────────────────────────────────
// Must be declared before YTPlus.h uses them as superclasses or in extensions.

@interface YTCollectionViewCell : UICollectionViewCell
@end

@interface YTSettingsCell : UITableViewCell
@end

@interface YTSettingsSectionItemManager : NSObject
@end

@interface YTLightweightQTMButton : UIButton
@end

@interface YTQTMButton : UIButton
@end

// ─── AsyncDisplayKit / Texture stubs ─────────────────────────────────────────
// Note: ASDisplayNode properties (yogaChildren, layer, closestViewController) are
// declared in YTPlus.h extensions - do NOT redeclare them here to avoid conflicts.

@interface ASDisplayNode : NSObject
@property (nonatomic, copy) NSString *accessibilityIdentifier;
@end

@interface ASCellNode : ASDisplayNode
- (id)controller;
@end

// ASNodeController, ELMNodeController, ELMComponent, ASCollectionElement are
// fully declared in YTPlus.h - omitted here to avoid duplicate interface errors.

@interface ASCollectionView : UICollectionView
@property (nonatomic, copy) NSString *accessibilityIdentifier;
@end

// ─── YTI (Protobuf model) stubs ───────────────────────────────────────────────

@interface YTICompatibilityOptions : NSObject
@property (nonatomic, assign) BOOL hasAdLoggingData;
@end

@interface YTIElementRenderer : NSObject
@property (nonatomic, assign) BOOL hasCompatibilityOptions;
@property (nonatomic, strong) YTICompatibilityOptions *compatibilityOptions;
- (NSString *)description;
@end

@interface YTIIcon : NSObject
@property (nonatomic, assign) NSInteger iconType;
@end

// ─── Classic quality controller stub ─────────────────────────────────────────

@interface YTVideoQualitySwitchOriginalController : NSObject
- (instancetype)initWithParentResponder:(id)responder;
@end

// ─── YouTube data model stubs ─────────────────────────────────────────────────

// YTISectionListRenderer.contentsArray contains YTIItemSectionRenderer objects directly.
// Confirmed from YTLite.dylib type encoding: B32@?0@"YTIItemSectionRenderer"8Q16^B24
// There is no YTISectionListSupportedRenderers wrapper in YouTube 21.16.2.
@interface YTISectionListRenderer : NSObject
@property (nonatomic, strong) NSMutableArray *contentsArray;
@end

@interface YTIItemSectionRenderer : NSObject
@property (nonatomic, strong) NSArray *contentsArray;
@property (nonatomic, assign) BOOL hasPromoType;
@end



@interface YTIPivotBarRenderer : NSObject
- (NSMutableArray *)itemsArray;
+ (id)pivotSupportedRenderersWithBrowseId:(NSString *)browseId title:(NSString *)title iconType:(NSInteger)iconType;
@end

@interface YTIPivotBarSupportedRenderers : NSObject
- (id)pivotBarItemRenderer;
- (id)pivotBarIconOnlyItemRenderer;
@end

@interface YTIPivotBarItemRenderer : NSObject
@property (nonatomic, copy) NSString *pivotIdentifier;
@end

@interface YTIMenuConditionalServiceItemRenderer : NSObject
@property (nonatomic, strong) YTIIcon *icon;
@end

@interface YTIButtonRenderer : NSObject
@property (nonatomic, strong) YTIIcon *icon;
@end

@interface YTPlayerOverlay : NSObject
- (NSString *)overlayIdentifier;
@end

@interface YTPlayerOverlayProvider : NSObject
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier switchOn:(BOOL)on switchBlock:(id)switchBlock settingItemId:(NSInteger)itemId;
+ (instancetype)itemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)identifier detailTextBlock:(id)detailBlock selectBlock:(id)selectBlock;
+ (instancetype)itemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier detailTextBlock:(id)detailBlock selectBlock:(id)selectBlock;
+ (instancetype)checkmarkItemWithTitle:(NSString *)title titleDescription:(NSString *)description selectBlock:(id)selectBlock;
@end

@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)navTitle pickerSectionTitle:(NSString *)sectionTitle rows:(NSArray *)rows selectedItemIndex:(NSUInteger)index parentResponder:(id)responder;
@end

@interface YTSettingsViewController : UIViewController
- (void)pushViewController:(UIViewController *)vc;
- (void)reloadData;
- (void)setSectionItems:(NSArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(UIImage *)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)hidden;
- (void)setSectionItems:(NSArray *)items forCategory:(NSUInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)hidden;
@end

@interface YTAlertView : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
+ (instancetype)confirmationDialogWithAction:(void(^)(void))action actionTitle:(NSString *)actionTitle cancelTitle:(NSString *)cancelTitle;
+ (instancetype)confirmationDialogWithAction:(void(^)(void))action actionTitle:(NSString *)actionTitle cancelAction:(void(^)(void))cancelAction cancelTitle:(NSString *)cancelTitle;
+ (instancetype)infoDialog;
- (void)show;
@end

@interface YTToastResponderEvent : NSObject
+ (instancetype)eventWithMessage:(NSString *)message firstResponder:(id)responder;
- (void)send;
@end

@interface YTUIUtils : NSObject
+ (UIViewController *)topViewControllerForPresenting;
+ (BOOL)openURL:(NSURL *)url;
@end

@interface YTIBrowseRequest : NSObject
+ (NSString *)browseIDForExploreTab;
@end

@interface YTMutableAdCell : UICollectionViewCell
@end

@interface YTGridPromotedVideoCell : UICollectionViewCell
@end

@interface YTInnerTubeCollectionViewController : UIViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer;
- (void)addSectionsFromArray:(NSArray *)array;
@end

