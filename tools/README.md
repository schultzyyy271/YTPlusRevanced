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
