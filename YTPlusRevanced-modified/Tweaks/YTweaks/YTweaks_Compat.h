// YTweaks_Compat.h - stubs needed before Logos generates @class forward declarations
#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// YTGlobalConfig
#ifndef YTGlobalConfig_DEFINED
#define YTGlobalConfig_DEFINED
@interface YTGlobalConfig : NSObject
@end
#endif

// YTColdConfig
#ifndef YTColdConfig_DEFINED
#define YTColdConfig_DEFINED
@interface YTColdConfig : NSObject
@end
#endif

// YTHotConfig
#ifndef YTHotConfig_DEFINED
#define YTHotConfig_DEFINED
@interface YTHotConfig : NSObject
@end
#endif

// YTAppDelegate - full interface so valueForKey calls compile
#ifndef YTAppDelegate_DEFINED
#define YTAppDelegate_DEFINED
@interface YTAppDelegate : NSObject <UIApplicationDelegate>
- (nullable id)valueForKey:(nonnull NSString *)key;
@end
#endif

// YTIElementRenderer
#ifndef YTIElementRenderer_DEFINED
#define YTIElementRenderer_DEFINED
@interface YTIElementRenderer : NSObject
- (nullable NSData *)elementData;
- (nonnull NSString *)description;
@end
#endif

// YTWatchViewController
#ifndef YTWatchViewController_DEFINED
#define YTWatchViewController_DEFINED
@interface YTWatchViewController : UIViewController
- (UIInterfaceOrientationMask)allowedFullScreenOrientations;
@end
#endif

// YTMainAppVideoPlayerOverlayView
#ifndef YTMainAppVideoPlayerOverlayView_DEFINED
#define YTMainAppVideoPlayerOverlayView_DEFINED
@interface YTMainAppVideoPlayerOverlayView : UIView
@end
#endif

// ASCollectionView
#ifndef ASCollectionView_DEFINED
#define ASCollectionView_DEFINED
@interface ASCollectionView : UICollectionView
@end
#endif

// YTAsyncCollectionView (used in Gonerino but may appear here too)
#ifndef YTAsyncCollectionView_DEFINED
#define YTAsyncCollectionView_DEFINED
@interface YTAsyncCollectionView : UICollectionView
@property (nonatomic, weak, nullable) id pageStylingDelegate;
@end
#endif

NS_ASSUME_NONNULL_END
