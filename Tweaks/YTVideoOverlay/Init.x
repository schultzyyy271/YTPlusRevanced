#import <dlfcn.h>
#import "Init.h"

static void initYTVideoOverlay(NSString *tweakKey, NSDictionary *metadata) {
    // YTVideoOverlay compiled inline - no dlopen needed
    // YTVideoOverlay is compiled inline - no dlopen needed
    [NSClassFromString(@"YTSettingsSectionItemManager") registerTweak:tweakKey metadata:metadata];
}
