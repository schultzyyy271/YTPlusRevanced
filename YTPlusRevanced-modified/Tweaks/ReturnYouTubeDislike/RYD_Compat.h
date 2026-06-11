// RYD_Compat.h — complete stub header for Return YouTube Dislikes
// All types declared in dependency order (no forward-only refs for types with properties/methods).
#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ── 1. Enums ──────────────────────────────────────────────────────────────────
typedef NS_ENUM(NSInteger, YTLikeStatus) {
    YTLikeStatusIndifferent = 0,
    YTLikeStatusLike        = 1,
    YTLikeStatusDislike     = 2,
};

// ── 2. RYD helper stubs (declared before any class uses them) ─────────────────

// Reel endpoint chain: model.endpoint.reelWatchEndpoint.videoId
@interface RYDReelWatchEndpoint : NSObject
@property (nonatomic, copy) NSString *videoId;
@end

@interface RYDEndpoint : NSObject
@property (nonatomic, strong) RYDReelWatchEndpoint *reelWatchEndpoint;
@end

// Shorts video chain: currentVideo.singleVideo.videoId
@interface RYDSingleVideo : NSObject
@property (nonatomic, copy) NSString *videoId;
@end

@interface RYDCurrentVideo : NSObject
- (RYDSingleVideo *)singleVideo;
@end

// ── 3. YTQTMButton — needed by YTReelWatchLikesController ────────────────────
@interface YTQTMButton : UIButton
+ (instancetype)iconButton;
- (void)enableNewTouchFeedback;
@end

// ── 4. YTI protobuf types ─────────────────────────────────────────────────────
@interface YTIFormattedString : NSObject
+ (YTIFormattedString *)formattedStringWithString:(NSString *)string;
- (NSString *)stringValue;
- (NSString *)stringWithFormattingRemoved;
@end

@interface YTIToggleButtonRenderer : NSObject
@property (nonatomic, strong) YTIFormattedString *defaultText;
@property (nonatomic, strong) YTIFormattedString *toggledText;
@end

@interface YTIButtonSupportedRenderers : NSObject
@end

@interface YTILikeButtonRendererTarget : NSObject
@property (nonatomic, strong) NSString *videoId;
@end

@interface YTILikeButtonRenderer : NSObject
@property (nonatomic, assign) YTLikeStatus likeStatus;
@property (nonatomic, strong) YTILikeButtonRendererTarget *target;
@property (nonatomic, assign) BOOL hasDislikeCountText;
@property (nonatomic, strong) YTIFormattedString *dislikeCountText;
@property (nonatomic, assign) BOOL hasDislikeCountWithDislikeText;
@property (nonatomic, strong) YTIFormattedString *dislikeCountWithDislikeText;
@property (nonatomic, assign) BOOL hasDislikeCountWithUndislikeText;
@property (nonatomic, strong) YTIFormattedString *dislikeCountWithUndislikeText;
@property (nonatomic, assign) BOOL hasLikeCountText;
@property (nonatomic, strong) YTIFormattedString *likeCountText;
@property (nonatomic, assign) BOOL hasLikeCountWithLikeText;
@property (nonatomic, strong) YTIFormattedString *likeCountWithLikeText;
@property (nonatomic, assign) BOOL hasLikeCountWithUnlikeText;
@property (nonatomic, strong) YTIFormattedString *likeCountWithUnlikeText;
@property (nonatomic, strong) id likedText;
@property (nonatomic, strong) id dislikedText;
@property (nonatomic, strong) id defaultText;
@property (nonatomic, strong) id toggledText;
@end

// ── 5. Color palette — needed by currentColorPalette() ───────────────────────
@interface YTCommonColorPalette : NSObject
+ (instancetype)darkPalette;
+ (instancetype)lightPalette;
- (UIColor *)textPrimary;
@end

@interface YTColorPalette : NSObject
+ (instancetype)colorPaletteForPageStyle:(NSInteger)pageStyle;
- (UIColor *)textPrimary;
@end

// YTPageStyleController — currentColorPalette class method
@interface YTPageStyleController : NSObject
+ (YTCommonColorPalette *)currentColorPalette;
@end

// ── 6. YTAppDelegate / YTAppViewController ────────────────────────────────────
@interface YTAppViewController : UIViewController
- (NSInteger)pageStyle;
@end

@interface YTAppDelegate : NSObject <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

// ── 7. YTPlayerViewController — contentVideoID ───────────────────────────────
@interface YTPlayerViewController : UIViewController
- (NSString *)contentVideoID;
@end

// ── 8. Watch controller chain ─────────────────────────────────────────────────
@interface YTWatchPlaybackController : NSObject
@end

@interface YTWatchController : NSObject
@property (nonatomic, strong) id watchPlaybackController;
@end

// ── 9. ASDisplayNode — base for all ELM nodes ────────────────────────────────
@interface ASDisplayNode : NSObject
@property (nonatomic, strong) NSArray *yogaChildren;
@property (nonatomic, assign) CGSize calculatedSize;
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic, strong) id layoutAttributes;
@property (nonatomic, copy) NSString *accessibilityIdentifier;
@property (nonatomic, strong) UIView *view;
- (UIViewController *)closestViewController;
- (void)addYogaChild:(id)child;
- (void)relayoutNode;
@end

// ── 10. ELM nodes (inherit ASDisplayNode) ─────────────────────────────────────
@interface ELMCellNode : ASDisplayNode
@end

@interface ELMContainerNode : ASDisplayNode
- (id)controller;
@end

@interface ELMTextNode : ASDisplayNode
@property (nonatomic, strong) id element;
@property (nonatomic, copy) NSAttributedString *attributedText;
@property (nonatomic, copy) NSAttributedString *attributedString;
@property (nonatomic, copy) NSString *accessibilityLabel;
@end

@interface ELMNodeController : NSObject
- (id)owningComponent;
@end

@interface ELMComponent : NSObject
- (id)owningComponent;
- (NSString *)templateURI;
@end

@interface ELMNodeFactory : NSObject
+ (instancetype)sharedInstance;
- (id)nodeWithElement:(id)element materializationContext:(id *)context;
@end

// ── 11. YTRollingNumber ───────────────────────────────────────────────────────
@interface YTRollingNumberView : UIView
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) id fontAttributes;
- (void)setNumber:(NSString *)number animated:(BOOL)animated;
- (void)setUpdatedCount:(NSString *)count updatedCountNumber:(NSNumber *)number font:(UIFont *)font fontAttributes:(id)attrs color:(UIColor *)color skipAnimation:(BOOL)skip;
- (void)setUpdatedCount:(NSString *)count updatedCountNumber:(NSNumber *)number font:(UIFont *)font color:(UIColor *)color skipAnimation:(BOOL)skip;
@end

@interface YTRollingNumberNode : NSObject
@property (nonatomic, strong) id element;
@property (nonatomic, strong) YTRollingNumberView *rollingNumberView;
@property (nonatomic, strong) UIView *view;
- (void)setString:(NSString *)string;
- (void)updateRollingNumberView;
- (void)relayoutNode;
@end

// ── 12. ASCollectionView ──────────────────────────────────────────────────────
@interface _ASDisplayView : UIView
@end

@interface _ASCollectionViewCell : UICollectionViewCell
@end

@interface ASCollectionView : UICollectionView
@end

@interface YTAsyncCollectionView : UICollectionView
@property (nonatomic, weak) id pageStylingDelegate;
@end

// ── 13. YouTube Reel/Shorts stubs ─────────────────────────────────────────────
@interface YTELMView : UIView
@end

@interface YTReelModel : NSObject
- (RYDEndpoint *)endpoint;
- (RYDEndpoint *)command;
@end


// YTReelWatchPlaybackOverlayView — base BEFORE the (RYD) category below
@interface YTReelWatchPlaybackOverlayView : UIView
- (id)parentResponder;
@end

// YTReelWatchPlaybackOverlayViewSub is a subclass used in newer YT versions
@interface YTReelWatchPlaybackOverlayViewSub : YTReelWatchPlaybackOverlayView
@end

@interface YTReelWatchActionBarView : UIView
@end

@interface YTReelElementAsyncComponentView : UIView
@end

@interface YTReelWatchLikesController : NSObject
@property (nonatomic, strong) YTQTMButton *likeButton;
@property (nonatomic, strong) YTQTMButton *dislikeButton;
- (void)updateLikeButtonWithRenderer:(id)renderer;
@end


@interface YTShortsPlayerViewController : UIViewController
- (RYDCurrentVideo *)currentVideo;
@end

@interface YTWatchNextResultsViewController : UIViewController
@end

@interface YTAppViewController2 : UIViewController
- (NSInteger)pageStyle;
@end

// Engagement stubs
@interface YTFullscreenEngagementActionBarButtonRenderer : NSObject
@end
@interface YTFullscreenEngagementActionBarButtonView : UIView
@end

// ── 14. RYD category extensions (base classes declared above) ─────────────────
@interface YTRollingNumberNode (RYD)
@property (strong, nonatomic) NSString *updatedCount;
@property (strong, nonatomic) NSNumber *updatedCountNumber;
- (void)updateCount:(NSString *)updateCount color:(UIColor *)color;
@end

@interface YTReelWatchPlaybackOverlayView (RYD)
@property (assign, nonatomic) BOOL didGetVote;
@end

// ── 15. NSObject/NSArray/UIView categories ────────────────────────────────────
@interface NSObject (RYDTextFormatting)
- (NSString *)stringWithFormattingRemoved;
@end

@interface NSArray (RYDArray)
- (id)yt_objectAtIndex:(NSUInteger)index;
- (id)yt_objectAtIndexOrNil:(NSUInteger)index;
@end

@interface UIView (AsyncDisplayKit)
- (id)closestViewController;
@end
