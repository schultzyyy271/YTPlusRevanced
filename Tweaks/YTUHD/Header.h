#ifndef YTUHD_H_
#define YTUHD_H_

// All YTUHD-specific headers are not available in the theos YouTubeHeader package.
// Everything is stubbed in YTUHD_Compat.h — resolved at runtime via ObjC messaging.
#import "YTUHD_Compat.h"

#define IOS_BUILD "19H402"
#define MAX_FPS 60
#define MAX_HEIGHT 2160 // 4k
#define MAX_PIXELS 8294400 // 3840 x 2160 (4k)

#define UseVP9Key @"EnableVP9"
#define AllVP9Key @"AllVP9"
#define DisableServerABRKey @"DisableServerABR"
#define DecodeThreadsKey @"VP9DecodeThreads"
#define SkipLoopFilterKey @"VP9SkipLoopFilter"
#define LoopFilterOptimizationKey @"VP9LoopFilterOptimization"
#define RowThreadingKey @"VP9RowThreading"

#endif
