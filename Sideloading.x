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
    NSArray *versions = @[
        @"21.16.2", @"21.15.2", @"21.14.3", @"21.13.3", @"21.12.2",
        @"21.11.3", @"21.10.3", @"21.09.3", @"21.08.3", @"21.07.4",
        @"21.06.2", @"21.05.3", @"21.04.2", @"21.03.2", @"21.02.3",
        @"21.01.3", @"20.50.10"
    ];
    if (!ytpBool(@"versionSpooferEnabled")) return %orig;
    NSInteger idx = ytpInt(@"versionSpooferIndex");
    if (idx < 0 || idx >= (NSInteger)versions.count) return %orig;
    return versions[idx];
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
    if (!isAppStore) %init(gSideloading);
}
