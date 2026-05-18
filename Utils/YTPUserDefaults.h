#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTPUserDefaults : NSUserDefaults

@property (class, readonly, strong) YTPUserDefaults *standardUserDefaults;

- (void)reset;
+ (void)resetUserDefaults;

@end

NS_ASSUME_NONNULL_END
