# dump_objc.py — Objective-C metadata toolkit for auditing the YouTube binary across updates.
# Built to reproduce the exact workflow used to port YTPlusRevanced 21.16.2 -> 21.24.3.
#
# WHAT IT DOES
#   Parses the loaded Mach-O's ObjC metadata (classes, categories, selectors, ivars) WITHOUT
#   relying on symbols (the YouTube binary is stripped to sub_*). Gives you:
#     - exists(sel)            : is this selector name anywhere in the binary?  (the "is it removed?" oracle)
#     - whichclass(sel)        : which class(es) implement this selector
#     - methods(cls)           : a class's own (or inherited) methods
#     - imp(cls, sel)          : the IMP address of a method, so you can decompile() it
#     - ivars(cls)             : a class's instance variables
#     - audit(hooks_tsv)       : classify a list of (file, class, selector) hooks -> BINDS / DEAD / SYSTEM / MISSING_CLASS
#     - dump_all(outdir)       : write objc_dump.json + selectors.txt for offline diffing across versions
#
# HOW TO RUN
#   In IDA Pro:   File > Script file... > dump_objc.py    then call the functions in the console, e.g.
#                   T.build(); T.whichclass("videoZoomFreeZoomEnabled"); T.audit(r"C:\path\hooks.tsv")
#   Via IDA MCP:  paste this whole file into py_eval (it self-builds into the global `T`), then call T.*
#                 (the closure design below avoids the py_eval scoping quirk where top-level
#                  helpers can't see each other).
#
# CROSS-UPDATE WORKFLOW: see tools/UPDATE_PLAYBOOK.md

def _make_tools():
    import ida_bytes, ida_segment, idc, json, os
    GQ = ida_bytes.get_qword
    GD = ida_bytes.get_dword

    # System framework class prefixes — present in other dylibs, not the app binary; assumed stable.
    SYS = ("NS", "UI", "AV", "CA", "CG", "MP", "WK", "SF", "SK", "MK", "CL", "PH",
           "GLK", "SCN", "CN", "EK", "CB", "QL", "LA", "PK", "GCK", "CM", "VT", "OS")
    # Common UIKit overrides — a hook on these binds via inheritance even if not in the class's own list.
    UIKIT = {"layoutSubviews", "drawRect:", "init", "initWithFrame:", "initWithCoder:", "dealloc",
             "setHidden:", "setFrame:", "setBounds:", "setBackgroundColor:", "viewDidLoad",
             "viewWillAppear:", "viewDidAppear:", "didMoveToWindow", "willMoveToSuperview:",
             "sizeThatFits:", "intrinsicContentSize", "traitCollectionDidChange:", "setAlpha:",
             "hitTest:withEvent:", "pointInside:withEvent:", "prepareForReuse", "setSelected:",
             "setEnabled:", "setNeedsLayout", "updateConstraints", "motionEnded:withEvent:"}

    state = {"classes": {}, "ea2name": {}, "methnames": set(), "built": False}

    def _seg(name):
        s = ida_segment.get_first_seg()
        while s:
            if idc.get_segm_name(s.start_ea) == name:
                return s.start_ea, s.end_ea
            s = ida_segment.get_next_seg(s.start_ea)
        return None

    def _str(ea):
        return (ida_bytes.get_strlit_contents(ea, -1, 0) or b"").decode("utf-8", "replace")

    def _methlist(ml):
        # returns list of (sel, imp). Handles relative (iOS15+) and absolute method lists.
        if not ml:
            return []
        es = GD(ml); cnt = GD(ml + 4)
        rel = (es & 0x80000000) != 0
        w = es & 0xffff
        out = []; p = ml + 8
        for _ in range(cnt):
            if rel:
                no = GD(p); no -= 0x100000000 if no & 0x80000000 else 0
                sel = _str(GQ(p + no))
                io = GD(p + 8); io -= 0x100000000 if io & 0x80000000 else 0
                imp = p + 8 + io
            else:
                sel = _str(GQ(p)); imp = GQ(p + 16)
            out.append((sel, imp))
            p += w if w else (12 if rel else 24)
        return out

    def _ivars(il):
        if not il:
            return []
        cnt = GD(il + 4); p = il + 8; out = []
        for _ in range(cnt):
            out.append((_str(GQ(p + 8)), _str(GQ(p + 16))))
            p += 32
        return out

    def build():
        classes, ea2name = {}, {}
        cl = _seg("__objc_classlist")
        if not cl:
            print("[dump_objc] ERROR: no __objc_classlist — is an ObjC Mach-O loaded?")
            return (0, 0)
        ea = cl[0]
        while ea < cl[1]:
            c = GQ(ea); ea += 8
            if not c:
                continue
            ro = GQ(c + 0x20) & ~7
            nm = _str(GQ(ro + 0x18))
            if not nm:
                continue
            classes[nm] = {
                "super_ea": GQ(c + 8),
                "sels": {s: i for (s, i) in _methlist(GQ(ro + 0x20))},
                "ivars": _ivars(GQ(ro + 0x30)),
                "ea": c,
            }
            ea2name[c] = nm
        # superclass names
        for d in classes.values():
            d["supername"] = ea2name.get(d["super_ea"])
        # fold in categories (they add methods to existing classes)
        for segname in ("__objc_catlist", "__objc_catlist2"):
            seg = _seg(segname)
            if not seg:
                continue
            ea = seg[0]
            while ea < seg[1]:
                cat = GQ(ea); ea += 8
                if not cat:
                    continue
                nm = ea2name.get(GQ(cat + 8))
                if nm and nm in classes:
                    for (s, i) in _methlist(GQ(cat + 0x10)):
                        classes[nm]["sels"].setdefault(s, i)
        # methname oracle (every selector string the binary knows)
        names = set()
        mn = _seg("__objc_methname")
        if mn:
            data = ida_bytes.get_bytes(mn[0], mn[1] - mn[0])
            names = set(x.decode("utf-8", "replace") for x in data.split(b"\x00") if x)
        state.update(classes=classes, ea2name=ea2name, methnames=names, built=True)
        print("[dump_objc] built: %d classes, %d selector names" % (len(classes), len(names)))
        return (len(classes), len(names))

    def _need():
        if not state["built"]:
            build()

    def exists(sel):
        _need()
        return sel in state["methnames"]

    def whichclass(sel):
        _need()
        return sorted(n for n, d in state["classes"].items() if sel in d["sels"])

    def _resolve(cls, sel):
        c = cls; seen = 0
        while c in state["classes"] and seen < 40:
            if sel in state["classes"][c]["sels"]:
                return True
            c = state["classes"][c].get("supername"); seen += 1
        return False

    def methods(cls, inherited=False):
        _need()
        if cls not in state["classes"]:
            return None
        if not inherited:
            return sorted(state["classes"][cls]["sels"])
        out, c, seen = set(), cls, 0
        while c in state["classes"] and seen < 40:
            out |= set(state["classes"][c]["sels"])
            c = state["classes"][c].get("supername"); seen += 1
        return sorted(out)

    def imp(cls, sel):
        _need()
        d = state["classes"].get(cls)
        if not d or sel not in d["sels"]:
            return None
        return hex(d["sels"][sel])

    def ivars(cls):
        _need()
        d = state["classes"].get(cls)
        return d["ivars"] if d else None

    def find(substr):
        # fuzzy: class names containing substr
        _need()
        return sorted(n for n in state["classes"] if substr.lower() in n.lower())

    def audit(hooks_tsv, out_path=None):
        # hooks_tsv: lines of "file<TAB>Class<TAB>selector" (see tools/extract_hooks.sh)
        _need()
        import io
        rows = [r for r in open(hooks_tsv, encoding="utf-8").read().splitlines() if r.strip()]
        dead, missing, binds, system, inh = [], [], 0, 0, 0
        for line in rows:
            parts = line.split("\t")
            if len(parts) == 3:
                f, cls, sel = parts
            elif len(parts) == 2:
                f, (cls, sel) = "?", parts
            else:
                continue
            if cls not in state["classes"]:
                if cls.startswith(SYS):
                    system += 1
                else:
                    missing.append((f, cls, sel))
            elif _resolve(cls, sel):
                binds += 1
            elif sel in UIKIT:
                inh += 1
            elif sel in state["methnames"]:
                inh += 1   # exists elsewhere / inherited — almost always fine
            else:
                dead.append((f, cls, sel))   # selector name absent from binary => removed/renamed
        lines = []
        lines.append("=== HOOK AUDIT: %d pairs ===" % len(rows))
        lines.append("BINDS=%d  inherited/elsewhere=%d  system=%d  DEAD=%d  MISSING_CLASS=%d"
                     % (binds, inh, system, len(dead), len(missing)))
        lines.append("\n--- DEAD SELECTORS (name absent from binary -> removed/renamed, or tweak-added %new) ---")
        for f, cls, sel in sorted(dead):
            lines.append("  -[%s %s]   (%s)" % (cls, sel, f))
        lines.append("\n--- MISSING APP CLASSES ---")
        for f, cls, sel in sorted(set(missing)):
            lines.append("  %s   (%s)" % (cls, f))
        report = "\n".join(lines)
        print(report)
        if out_path:
            open(out_path, "w", encoding="utf-8").write(report)
            print("[dump_objc] wrote %s" % out_path)
        return {"binds": binds, "dead": dead, "missing": missing}

    def dump_all(outdir):
        _need()
        os.makedirs(outdir, exist_ok=True)
        # selectors.txt
        with open(os.path.join(outdir, "selectors.txt"), "w", encoding="utf-8") as fh:
            for s in sorted(state["methnames"]):
                fh.write(s + "\n")
        # objc_dump.json: class -> {super, methods, ivars}
        obj = {}
        for n, d in state["classes"].items():
            obj[n] = {"super": d.get("supername"),
                      "methods": sorted(d["sels"].keys()),
                      "ivars": [{"name": iv[0], "type": iv[1]} for iv in d["ivars"]]}
        with open(os.path.join(outdir, "objc_dump.json"), "w", encoding="utf-8") as fh:
            json.dump(obj, fh, indent=1, sort_keys=True)
        print("[dump_objc] wrote %s/{selectors.txt, objc_dump.json}  (%d classes)" % (outdir, len(obj)))

    class _T:
        pass
    t = _T()
    for fn in (build, exists, whichclass, methods, imp, ivars, find, audit, dump_all):
        setattr(t, fn.__name__, fn)
    t.state = state
    return t


T = _make_tools()
T.build()
print("Ready. Try: T.whichclass('videoZoomFreeZoomEnabled'), T.exists('scrubToTime:'), "
      "T.methods('YTReelBottomActionBarView'), T.imp('YTColdConfig','videoZoomFreeZoomEnabled'), "
      "T.audit(r'C:\\path\\hooks.tsv'), T.dump_all(r'C:\\path\\out')")
