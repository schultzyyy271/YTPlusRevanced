# YTPlusRevanced — YouTube Update Playbook

Step-by-step to port the tweak to a new YouTube version, reproducing the 21.16.2 → 21.24.3 port.
Tools live in `tools/`. The core idea: **the binary is the source of truth** — every hook is a
`(class, selector)` pair that either still binds to a real method or doesn't.

---

## ⭐ NO-MCP / free-plan (Sonnet) mode — READ THIS FIRST

If the AI session has **no IDA MCP** (can't drive IDA itself), the workflow still works — **YOU run
`dump_objc.py` inside IDA Pro** (File ▸ Script file…) and paste outputs back. The AI then works from
plain files with `grep`/`read`. Nothing here needs the MCP; the MCP was only how a Pro session drove IDA.

What the AI will ask you to run in IDA's Output window, and you paste back:
```python
# (script auto-builds T on load)
T.exists("someSelector:")                       # is this method still in the binary?
T.whichclass("someSelector:")                   # which class(es) implement it
T.methods("SomeClass")                           # a class's methods   (add True for inherited)
T.ivars("SomeClass")                             # ivars / properties
print(T.decompile("SomeClass","someSel:"))       # << pseudocode — this is the key one for tracing flow
print(T.disasm("SomeClass","someSel:"))          # asm fallback if Hex-Rays missing
```
And generate the offline reference files once per version, then hand the FILES to the AI:
```python
T.dump_all(r"C:\out\objc_<ver>")                 # objc_dump.json (class->super/methods/ivars) + selectors.txt
T.audit(r"C:\path\hooks.tsv", r"C:\out\audit.txt")   # which of our hooks are dead
T.dump_methods([("YTGetDownloadActionCommandHandler","executeWithCommand:entry:fromView:sender:")],
               r"C:\out\decomp.txt")             # batch pseudocode dump for the methods in question
```
With `objc_dump.json` + `selectors.txt` + targeted `T.decompile()` pastes, Sonnet has everything a Pro
session had — `grep selectors.txt` replaces `T.exists`, the JSON replaces `T.methods/whichclass/ivars`,
and your pasted pseudocode replaces live `decompile`. The steps below are the same either way.

---

## 0. Inputs
- The **decrypted YouTube IPA/binary** for the new version, loaded in **IDA Pro** (with the IDA MCP
  server running so Claude can drive it via `py_eval` / `decompile`).
- This project checked out locally.

## 1. Build the ObjC index (in IDA)
Paste `tools/dump_objc.py` into the IDA MCP `py_eval` (or File > Script file in IDA Pro).
It self-builds into a global `T`. Sanity-check:
```python
T.exists("videoZoomFreeZoomEnabled")     # True/False — the "is this method still here?" oracle
T.whichclass("setSkipSegments:")         # which class(es) implement a selector
```
Optionally snapshot for offline diffing between versions:
```python
T.dump_all(r"C:\Users\Corey\Downloads\objc_<version>")   # writes objc_dump.json + selectors.txt
```

## 2. Extract every hook from the source
```bash
bash tools/extract_hooks.sh > hooks.tsv      # (file, class, selector) per line; skips %new/%property
```

## 3. Audit hooks against the new binary (in IDA)
```python
T.audit(r"C:\Users\Corey\Downloads\YTPlusRevanced-main\hooks.tsv")
```
Output buckets:
- **BINDS** — hook resolves to a real method (own or inherited). Fine.
- **inherited/elsewhere** — selector exists somewhere / is a UIKit override. Almost always fine.
- **system** — NS*/UI*/AV*/… framework classes (not in the app binary). Assumed stable.
- **DEAD** — selector name absent from the entire binary ⇒ **removed/renamed** (or a tweak-added
  `%new`/`%property` the extractor didn't skip). These are the ones to investigate.
- **MISSING_CLASS** — class gone (or a tweak-defined subclass like `…Sub`).

> Important nuance learned the hard way: a DEAD entry is often a **deliberate dead version-fallback**
> hook whose current-signature sibling is also hooked (e.g. old `MLPlayerPoolImpl` signatures,
> `initWithDelegate:autoplaySwitchEnabled:`, `YTLikeService`). Before "fixing", check whether the
> tweak ALSO hooks the replacement. Only act if NO current-signature variant is hooked.

## 4. Find the replacement for each genuine break (in IDA)
For a DEAD selector, find what replaced it:
```python
T.find("ReelActionBar")                       # classes by name substring
T.methods("YTReelBottomActionBarView")        # a class's own methods
T.methods("YTPlayerViewController", True)      # include inherited
T.ivars("YTReelWatchLikesController")          # ivars (e.g. did dislikeButton disappear?)
addr = T.imp("MLPlayerPoolImpl", "canQueuePlayerPlayVideo:playerConfig:reloadContext:error:")
# then decompile(addr) via the MCP to confirm argument types / behaviour
```
Typical breakage patterns:
- **Config getter renamed** (e.g. `…GlobalConfig` suffix dropped) → re-point the hook.
- **Method gained/lost a trailing parameter** → add the new-signature variant alongside the old.
- **Whole subsystem went Swift** (e.g. Shorts action bar) → no per-button ObjC selectors; hook the
  ObjC surface (`layoutSubviews`) and match subviews by `accessibilityLabel` (needs the diagnostic
  build, below, to capture real labels).

## 5. Apply fixes
Keep the old-signature hooks too (back-compat with older YouTube). Just ADD the new ones.
Conditional/diagnostic hooks must be in a Logos **`%group`** registered via `%init(Group)` inside
`#if` — an ungrouped `#if`'d `%hook` breaks the non-diagnostic build (Logos auto-registers it in the
main `%init`, leaving a dangling ref when the `#if` strips the body). Also a `#if`'d block must never
be the FIRST `%hook` in a file (Logos emits its preamble there).

## 6. Bump version metadata
`Makefile` (`YOUTUBE_VERSION`), `control` (`Version:`), `README.md`, `.github/workflows/build.yml`.

## 7. Build
**Cloud (no local setup):** push to GitHub → Actions builds both release + DIAG `.deb`s (matrix).
**Local (WSL):** see `ytplus-wsl-build` memory. Key gotchas:
- WSL2 needs virtualization (Virtual Machine Platform feature + reboot).
- **Build on native ext4, NOT `/mnt/c`** (drvfs 777 perms make `dpkg-deb` reject the control dir).
- `ldid` must be on `$THEOS/bin` (download from ProcursusTeam/ldid).
```bash
# from a copy on ext4:
export THEOS=~/theos PATH=$THEOS/bin:$PATH THEOS_PACKAGE_SCHEME=rootless
make clean package DEBUG=0 FINALPACKAGE=1 DIAG=0 YOUTUBE_VERSION=<ver>   # DIAG=1 for diagnostic
```

## 8. Verify runtime behaviour (the part the binary can't tell you)
Build with `DIAG=1`, sideload, then in one session: open a video → comments → a Short → Settings,
and **shake the device** — all diagnostics copy to the clipboard. It reports which hooks fired, the
binding self-check for every hook, and dumps the Shorts action-bar button labels (so locale-correct
`accessibilityLabel` matches can be set). See `YTPDiag.h`.

---

### Quick reference — what each tool answers
| Question | Tool |
|---|---|
| Is this method still in the app? | `T.exists("sel")` |
| Which class has it? | `T.whichclass("sel")` |
| What does this class expose now? | `T.methods("Class"[, inherited=True])` |
| Did an ivar/property disappear? | `T.ivars("Class")` |
| Address to decompile a method | `T.imp("Class","sel")` → `decompile(addr)` |
| Which of OUR hooks are dead? | `bash tools/extract_hooks.sh > hooks.tsv` → `T.audit("hooks.tsv")` |
| Snapshot for version diffing | `T.dump_all("out_dir")` |
