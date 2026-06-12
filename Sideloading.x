// Sideloading.x — YTPlus
// Keychain / bundle-ID patches so sideloaded IPA can log in.
// Based on IAmYouTube by PoomSmart and YTLite sideloading fixes.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "YTPlus.h"

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME      @"YouTube"

@interface SSOConfiguration : NSObject
@end

// Launch gate: never spoof the version during app startup. YouTube's own
// 21.x code reads +[YTVersionUtils appVersion] while launching and will crash
// if it sees an older version than the actual binary. We only begin reporting
// the spoofed version once the app has finished launching, so startup always
// sees the real version. Network/API requests happen after launch and still
// get the spoofed value.
static BOOL ytpLaunchComplete = NO;

%group gSideloading

// ── Keychain access group helper ──────────────────────────────────────────────
static NSString *accessGroupID() {
    NSDictionary *query = @{
        (__bridge NSString *)kSecClass:           (__bridge NSString *)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrAccount:     @"bundleSeedID",
        (__bridge NSString *)kSecAttrService:     @"",
        (__bridge NSString *)kSecReturnAttributes: @YES
    };
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound)
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status != errSecSuccess) return nil;
    return [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
}

// ── IAmYouTube hooks ──────────────────────────────────────────────────────────
%hook YTVersionUtils
+ (NSString *)appName { return YT_NAME; }
+ (NSString *)appID   { return YT_BUNDLE_ID; }
+ (NSString *)appVersion {
    if (!ytpLaunchComplete) return %orig;              // never spoof during launch
    if (!ytpBool(@"versionSpooferEnabled")) return %orig;
    NSString *spoofed = ytpString(@"versionSpooferValue");
    // Only spoof to a version we actually know about; otherwise report real.
    if (spoofed.length && [ytpSpoofVersionList() containsObject:spoofed]) return spoofed;
    return %orig;
}
%end

%hook GCKBUtils
+ (NSString *)appIdentifier { return YT_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
+ (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook OGLBundle
+ (NSString *)shortAppName { return YT_NAME; }
%end

%hook GVROverlayView
+ (NSString *)appName { return YT_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)services {
    self = %orig;
    [self setValue:YT_NAME forKey:@"_shortAppName"];
    [self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
    return self;
}
%end

// ── Bundle ID spoofing ────────────────────────────────────────────────────────
static BOOL isSelf() {
    NSArray *addresses = [NSThread callStackReturnAddresses];
    Dl_info info = {0};
    if (dladdr((void *)[addresses[2] longLongValue], &info) == 0) return NO;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    return [path hasPrefix:NSBundle.mainBundle.bundlePath];
}

%hook NSBundle
- (NSString *)bundleIdentifier {
    return isSelf() ? YT_BUNDLE_ID : %orig;
}
- (NSDictionary *)infoDictionary {
    if (!isSelf()) return %orig;
    NSMutableDictionary *info = [%orig mutableCopy];
    if (info[@"CFBundleIdentifier"])  info[@"CFBundleIdentifier"]  = YT_BUNDLE_ID;
    if (info[@"CFBundleDisplayName"]) info[@"CFBundleDisplayName"] = YT_NAME;
    if (info[@"CFBundleName"])        info[@"CFBundleName"]        = YT_NAME;
    return info;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (!isSelf()) return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])                           return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"]) return YT_NAME;
    return %orig;
}
%end

// ── Keychain group fixes (login on YouTube 17.33+) ────────────────────────────
%hook SSOKeychainHelper
+ (NSString *)accessGroup       { return accessGroupID(); }
+ (NSString *)sharedAccessGroup { return accessGroupID(); }
%end

%hook SSOKeychainCore
+ (NSString *)accessGroup       { return accessGroupID(); }
+ (NSString *)sharedAccessGroup { return accessGroupID(); }
%end

// ── App Group directory redirect ───────────────────────────────────────────────
%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (!groupIdentifier) return %orig(groupIdentifier);
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [docs URLByAppendingPathComponent:@"AppGroup"];
}
%end

%end // gSideloading

%ctor {
    BOOL isAppStore = [[NSFileManager defaultManager] fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
    if (!isAppStore) {
        %init(gSideloading);
        // Flip the spoofer on only once startup is finished (see note above).
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            // Small settle delay so the first post-launch feed build also sees
            // the real version; spoof takes effect for subsequent requests.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ytpLaunchComplete = YES;
            });
        }];
    }
}
