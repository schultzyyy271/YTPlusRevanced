/* YouTube Native Share — adapted for YTPlus rebuild.
 * Original: https://github.com/jkhsjdhjs/youtube-native-share (GPL-3.0-or-later)
 * Thanks to @jkhsjdhjs for the original implementation.
 */

#include <UIKit/UIActivityViewController.h>
#import "YTPlus.h"

// ─── GoogleProtocolBuffers base class stubs ───────────────────────────────────
// GPB classes are loaded at runtime from YouTube's binary; we only need
// minimal declarations so the compiler accepts the category extensions below.

@interface GPBMessage : NSObject
@end

@interface GPBUnknownFieldSet : NSObject
@end

@interface GPBUnknownField : NSObject
@end

@interface GPBMessage (YTPlus)
+ (instancetype)deserializeFromString:(NSString *)string;
+ (instancetype)parseFromData:(NSData *)data error:(NSError **)error;
@property (nonatomic, strong, readonly) GPBUnknownFieldSet *unknownFields;
- (BOOL)hasExtension:(id)extension;
- (id)getExtension:(id)extension;
@end

@interface GPBUnknownFieldSet (YTPlus)
- (BOOL)hasField:(NSInteger)fieldNumber;
- (id)getField:(NSInteger)fieldNumber;
@end

@interface GPBUnknownField (YTPlus)
@property (nonatomic, readonly) NSArray *lengthDelimitedList;
@end

@interface YTICommand : GPBMessage
@end

@interface ELMPBCommand : GPBMessage
@end

@interface ELMPBShowActionSheetCommand : GPBMessage
@property (nonatomic, strong, readwrite) ELMPBCommand *onAppear;
@property (nonatomic, assign, readwrite) BOOL hasOnAppear;
@end

@interface YTIUpdateShareSheetCommand : GPBMessage
@property (nonatomic, assign, readwrite) BOOL hasSerializedShareEntity;
@property (nonatomic, copy, readwrite) NSString *serializedShareEntity;
+ (id)updateShareSheetCommand;
@end

@interface YTIInnertubeCommandExtensionRoot : NSObject
+ (id)innertubeCommand;
@end

typedef NS_ENUM(NSInteger, ShareEntityType) {
    ShareEntityFieldVideo    = 1,
    ShareEntityFieldPlaylist = 2,
    ShareEntityFieldChannel  = 3,
    ShareEntityFieldClip     = 8
};

static inline NSString *extractIdWithFormat(GPBUnknownFieldSet *fields, NSInteger fieldNumber, NSString *format) {
    if (![fields hasField:fieldNumber]) return nil;
    GPBUnknownField *idField = [fields getField:fieldNumber];
    if ([idField.lengthDelimitedList count] != 1) return nil;
    NSString *entityId = [[NSString alloc] initWithData:[idField.lengthDelimitedList firstObject] encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:format, entityId];
}

%hook ELMPBShowActionSheetCommand
- (void)executeWithCommandContext:(id)context handler:(id)handler {
    if (!ytpBool(@"nativeShare")) return %orig;
    if (!self.hasOnAppear)       return %orig;

    id innertubeDescriptor = [%c(YTIInnertubeCommandExtensionRoot) innertubeCommand];
    if (![self.onAppear hasExtension:innertubeDescriptor]) return %orig;

    YTICommand *innertubeCommand = [self.onAppear getExtension:innertubeDescriptor];
    id shareSheetDescriptor = [%c(YTIUpdateShareSheetCommand) updateShareSheetCommand];
    if (![innertubeCommand hasExtension:shareSheetDescriptor]) return %orig;

    YTIUpdateShareSheetCommand *updateShareSheetCommand = [innertubeCommand getExtension:shareSheetDescriptor];
    if (!updateShareSheetCommand.hasSerializedShareEntity) return %orig;

    GPBMessage *shareEntity = [%c(GPBMessage) deserializeFromString:updateShareSheetCommand.serializedShareEntity];
    GPBUnknownFieldSet *fields = shareEntity.unknownFields;
    NSString *shareUrl = nil;

    // Clip
    if ([fields hasField:ShareEntityFieldClip]) {
        GPBUnknownField *clipField = [fields getField:ShareEntityFieldClip];
        if ([clipField.lengthDelimitedList count] == 1) {
            GPBMessage *clipMsg = [%c(GPBMessage) parseFromData:[clipField.lengthDelimitedList firstObject] error:nil];
            shareUrl = extractIdWithFormat(clipMsg.unknownFields, 1, @"https://youtube.com/clip/%@");
        }
    }

    // Channel
    if (!shareUrl) shareUrl = extractIdWithFormat(fields, ShareEntityFieldChannel, @"https://youtube.com/channel/%@");

    // Playlist
    if (!shareUrl) {
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPlaylist, @"%@");
        if (shareUrl) {
            if (![shareUrl hasPrefix:@"PL"] && ![shareUrl hasPrefix:@"FL"])
                shareUrl = [shareUrl stringByAppendingString:@"&playnext=1"];
            shareUrl = [@"https://youtube.com/playlist?list=" stringByAppendingString:shareUrl];
        }
    }

    // Video
    if (!shareUrl) shareUrl = extractIdWithFormat(fields, ShareEntityFieldVideo, @"https://youtube.com/watch?v=%@");

    if (!shareUrl) return %orig;

    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[shareUrl] applicationActivities:nil];
    [[%c(YTUIUtils) topViewControllerForPresenting] presentViewController:avc animated:YES completion:nil];
}
%end
