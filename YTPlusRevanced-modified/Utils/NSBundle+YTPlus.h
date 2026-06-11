#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBundle (YTPlus)

// Returns YTPlus default bundle (supports rootless/roothide)
@property (class, nonatomic, readonly) NSBundle *ytp_defaultBundle;

@end

NS_ASSUME_NONNULL_END
