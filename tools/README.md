# tools/ — YouTube update toolkit

Everything needed to port YTPlusRevanced to a new YouTube version **without an AI that can drive IDA**.
The binary is the source of truth; these tools turn it into files an AI can read with `grep`/`read`.

| File | What it is |
|---|---|
| `dump_objc.py` | IDAPython toolkit — parses the (stripped) YouTube binary's ObjC metadata and can decompile methods. **Run it inside IDA Pro.** |
| `extract_hooks.sh` | Lists every `(file, class, selector)` the tweak `%hook`s. Run on the project sources. |
| `UPDATE_PLAYBOOK.md` | The full step-by-step porting workflow. Read it after this. |

---

## ⭐ Read this if the AI has NO IDA access (free / Sonnet plan)

The AI cannot open IDA. **You** run `dump_objc.py` in IDA Pro and hand the AI the output files +
pasted pseudocode. The AI works from those. That's the whole trick — nothing here needs a special plan.

### 1. Load the toolkit in IDA Pro
Open the decrypted YouTube binary in IDA, wait for analysis, then **File ▸ Script file… ▸ `dump_objc.py`**.
It prints `built: N classes, M selector names` and creates a global `T`. Use IDA's Output window console.

### 2. Generate the offline reference files (once per YouTube version)
```python
T.dump_all(r"C:\Users\Corey\Downloads\objc_21.xx")     # -> objc_dump.json + selectors.txt
```
- `selectors.txt` — every method name in the binary. `grep` it: present = method exists, absent = removed.
- `objc_dump.json` — `{ "ClassName": { "super": ..., "methods": [...], "ivars": [...] } }`.

Hand those two files to the AI. They replace the live queries:
| Live query | Offline equivalent |
|---|---|
| `T.exists("foo:")` | `grep -x "foo:" selectors.txt` |
| `T.whichclass("foo:")` | search `objc_dump.json` for classes whose `methods` contain `foo:` |
| `T.methods("Class")` / `T.ivars("Class")` | read that class's entry in `objc_dump.json` |

### 3. Audit which of our hooks are dead on the new version
```python
# first, in a shell at the project root:  bash tools/extract_hooks.sh > hooks.tsv
T.audit(r"C:\...\hooks.tsv", r"C:\...\audit.txt")
```
`audit.txt` lists `DEAD SELECTORS` (removed/renamed → need fixing) and `MISSING APP CLASSES`.
⚠️ A DEAD entry is often a deliberate version-fallback hook whose current-signature sibling is also
hooked — only act if NO current variant binds. (See the playbook.)

### 4. Trace a method's logic (the part that needs the decompiler)
When the AI needs to understand *what a method does* (e.g. to find where a Download tap leads), it will
ask you to run one of these and paste the result:
```python
print(T.decompile("YTGetDownloadActionCommandHandler", "executeWithCommand:entry:fromView:sender:"))
print(T.disasm("SomeClass", "someSel:"))               # asm fallback if Hex-Rays unavailable
T.dump_methods([("ClassA","sel:"), ("ClassB","sel:")], r"C:\...\decomp.txt")   # batch -> file
```
`decompile` is how the 21.24.3 video-download fix was found: it revealed that tapping Download runs
`YTGetDownloadActionCommandHandler executeWithCommand:` (spinner → request → Premium upsell), so that
method was the correct hook target.

---

## Full function reference (`T.` …)
| Call | Returns |
|---|---|
| `T.exists("sel:")` | bool — is this selector anywhere in the binary |
| `T.whichclass("sel:")` | list of classes implementing the selector |
| `T.methods("Class"[, True])` | a class's own (or inherited) selectors |
| `T.ivars("Class")` | `[(name, typeEncoding), …]` |
| `T.imp("Class","sel:")` | method address (hex) for decompile/disasm |
| `T.find("substr")` | class names containing substr |
| `T.decompile("Class","sel:")` / `T.decompile(0xADDR)` | Hex-Rays pseudocode (string) |
| `T.disasm("Class","sel:"[, n])` | disassembly (string) |
| `T.audit("hooks.tsv"[, out])` | classify all hooks: BINDS / DEAD / MISSING_CLASS |
| `T.dump_all("dir")` | write `objc_dump.json` + `selectors.txt` |
| `T.dump_methods([(cls,sel),…], "out")` | write pseudocode of those methods to a file |

## Notes
- Stripped binary (funcs are `sub_*`) but ObjC metadata is intact — that's what this parses.
- Class methods (`+`) aren't in the index (only instance methods + categories); a `+constructor`
  showing as "not found" may still exist.
- Re-generate `objc_dump.json`/`selectors.txt` for **each** YouTube version; diff them to see what changed.

---

## Architecture: one dylib, and why splitting won't fix conflicts

All sub-tweaks compile **inline into one dylib** (`YouTubePlusRevanced.dylib`). This is deliberate and
correct — uYouEnhanced (the largest YouTube tweak) does the same. Don't split it expecting fixes.

**Why features break ≠ the dylib.** Every broken feature traces to a YouTube **version change**
(a hooked class/method was renamed/removed/moved) or a **server-side change** (e.g. dislike counts,
delivered by the InnerTube response, not the app). The fix is always: find what YouTube changed and
re-point the hook (see UPDATE_PLAYBOOK.md). Packaging is never the cause — the hook audit shows the
vast majority of hooks bind fine.

**Why splitting into separate dylibs does NOT help — important:**
- Method hooking composes at the **runtime IMP-swizzle level, not the dylib level.** When N hooks
  target one method — whether in one dylib or ten — MobileSubstrate stacks them in load order, each
  chaining to the previous via `%orig`. **The dylib boundary is invisible to hook composition.**
- So a hook **conflict** (two hooks fighting over a method) happens *identically* in 1 dylib or N
  dylibs. Splitting cannot fix or prevent it.
- Splitting actually makes things **worse**: you lose the Makefile's deterministic link order. The
  single dylib's link order *guarantees* dependencies like "YTVideoOverlay registers its button API
  (`+registerTweak:`/`buttonImage:`) before YouPiP/YouQuality use it." Separate dylibs load in
  OS-decided order → that dependency becomes fragile (overlay buttons may not appear).

**What a real conflict looks like, and how to actually fix it:** two tweaks hook the same method and
one `return`s without calling `%orig` (short-circuiting the other), or both fight over the return
value. The fix is **code coordination** — make both call `%orig`, order them deliberately, or merge
the logic. This is the same fix in one or many dylibs, and is *easier* in one dylib (all hooks in one
place, order controllable). Find overlapping hooks with:
```bash
bash tools/extract_hooks.sh | awk -F'\t' '{k=$2"\t"$3} !s[k,$1]++{c[k]++; f[k]=f[k]" "$1} END{for(x in c) if(c[x]>1) print c[x]" files: -["x"]"f[x]}'
```
Most overlaps are **intentional chaining** (every tweak adding its own settings section, or overlay
buttons stacking) — that's by design and works. Only investigate ones where two tweaks would *fight*
over the same return value.

### Verified-clean status (21.24.3)
Audited all 23 cross-file overlapping `(class, method)` hooks: **every cross-tweak overlap calls
`%orig` and passes through in its default path → they chain cleanly.** The only hook that never calls
`%orig` is YouPiP's own `-[MLPIPController activatePiPController]`, hooked in two **mutually-exclusive
`%group`s** (Legacy vs Modern, only one `%init`'d at runtime) — intentional, not a conflict. Chain
order is deterministic via the `_FILES` order in the Makefile (YTVideoOverlay is listed before
YouPiP/YouQuality on purpose). **No fixes were needed.**

Re-run after adding/changing hooks — flags any overlapping hook that *never* calls `%orig` (the real
short-circuit risk):
```bash
# build overlap list
bash tools/extract_hooks.sh | awk -F'\t' '{k=$2"|"$3} !s[k,$1]++{c[k]++} END{for(x in c) if(c[x]>1)print x}' > /tmp/ov.txt
# per-method %orig presence, then flag NOORIG overlaps
find . -name '*.x' -o -name '*.xm' | while read f; do awk '
function fl(){if(sl!="")printf "%s\t%s|%s\t%s\n",FILENAME,cls,sl,(o?"ORIG":"NOORIG");sl=""}
/%new/{sk=1}/%hook[ \t]/{fl();l=$0;sub(/.*%hook[ \t]+/,"",l);sub(/[ \t<({].*/,"",l);cls=l;ih=1;next}
/%end/{fl();ih=0;next} ih&&/^[ \t]*[-+][ \t]*\(/{fl();if(sk){sk=0;next}
 s=$0;sub(/^[ \t]*[-+][ \t]*/,"",s);sub(/^\([^)]*\)[ \t]*/,"",s);sub(/\{.*/,"",s);sel="";r=s;
 if(index(r,":")){while(match(r,/[A-Za-z_][A-Za-z0-9_]*[ \t]*:/)){k=substr(r,RSTART,RLENGTH);gsub(/[ \t:]/,"",k);sel=sel k ":";r=substr(r,RSTART+RLENGTH)}}else{if(match(r,/[A-Za-z_][A-Za-z0-9_]*/))sel=substr(r,RSTART,RLENGTH)}
 sl=sel;o=($0~/%orig/);next} ih&&sl!=""&&/%orig/{o=1} END{fl()}' "$f"; done \
 | awk -F'\t' 'NR==FNR{ov[$1]=1;next} $3=="NOORIG"&&($2 in ov){print $1"  "$2}' /tmp/ov.txt -
# (empty output = all overlaps chain cleanly)
```
