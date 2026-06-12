#import "NSBundle+YTPlus.h"

@implementation NSBundle (YTPlus)

+ (NSBundle *)ytp_defaultBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        // Try embedded bundle first (sideloaded IPA), then jailbreak path
        NSString *embeddedPath = [[NSBundle mainBundle] pathForResource:@"YouTubePlusRevanced" ofType:@"bundle"];
        NSString *jbPath = @"/var/jb/Library/Application Support/YouTubePlusRevanced.bundle"; // rootless
        NSString *rootPath = @"/Library/Application Support/YouTubePlusRevanced.bundle";       // rootful

        if (embeddedPath) {
            bundle = [NSBundle bundleWithPath:embeddedPath];
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:jbPath]) {
            bundle = [NSBundle bundleWithPath:jbPath];
        } else {
            bundle = [NSBundle bundleWithPath:rootPath];
        }
    });

    return bundle;
}

@end
