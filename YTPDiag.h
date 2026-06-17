// YTPDiag.h — one-shot diagnostic logging for YTPlusRevanced.
//
// Flip YTP_DIAG to 1 to build a diagnostic build, install once, then:
//   1. Open a normal video, open the comments, open a Short, open YT Settings.
//   2. SHAKE the device — all collected diagnostics are copied to the clipboard
//      (an alert confirms the line count). Paste that to the dev.
// The same text is also NSLog'd with the [YTPDIAG] tag and written to
//   <app>/Documents/YTPlusDiag.log  (retrievable via iMazing/3uTools/Finder).
//
// Default 0 = the macro compiles to nothing, so release builds have ZERO overhead.

#import <Foundation/Foundation.h>

#ifndef YTP_DIAG
#define YTP_DIAG 0
#endif

#if YTP_DIAG
#ifdef __cplusplus
extern "C" {
#endif
void YTPDiagLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *YTPDiagText(void);
// Dump a view subtree (class / accessibilityLabel / accessibilityIdentifier / hidden),
// each unique tuple logged once per session. Used to discover Shorts button labels.
void YTPDiagDumpTree(id /* UIView * */ root, NSString *tag);
// Dump an ASDisplayNode/ELM yoga-node subtree (class / accessibilityIdentifier).
// Used to discover the new segmented like/dislike button node structure for RYD.
void YTPDiagDumpNodes(id /* ASDisplayNode * */ node, NSString *tag, int depth);
#ifdef __cplusplus
}
#endif
#define YTPDIAG(...)             YTPDiagLog(__VA_ARGS__)
#define YTPDIAG_TREE(root, tag)  YTPDiagDumpTree((root), (tag))
#define YTPDIAG_NODES(node, tag) YTPDiagDumpNodes((node), (tag), 0)
#else
#define YTPDIAG(...)             do {} while (0)
#define YTPDIAG_TREE(root, tag)  do {} while (0)
#define YTPDIAG_NODES(node, tag) do {} while (0)
#endif
