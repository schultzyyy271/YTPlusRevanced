#!/usr/bin/env python3
"""
Verify the rebuilt YouTubePlusRevanced.dylib has the YTVideoOverlay registry compiled in.

Two critical selectors must be added via class_addMethod:
  +registerTweak:metadata:   -- the tweak metadata registry
  -buttonImage:              -- player overlay button image

If these are missing, YouPiP/YouQuality button rendering won't work even when
the app launches without crashing.

Usage (after `THEOS_PACKAGE_SCHEME=rootless make clean package DEBUG=0 FINALPACKAGE=1`):
    python3 VERIFY_FIX.py path/to/YouTubePlusRevanced.dylib

Tries `lief` (pip) first; falls back to `otool -Iv` if available.
"""
import sys, struct, re, subprocess, shutil

def fail(msg): print("FAIL:", msg); sys.exit(1)
def ok(msg): print("PASS:", msg)

if len(sys.argv) != 2: fail("usage: VERIFY_FIX.py <YouTubePlusRevanced.dylib>")
path = sys.argv[1]
with open(path, "rb") as f: data = f.read()

# ---- parse Mach-O sections ----
def parse_sections(data):
    magic, *_, ncmds, _, _, _ = struct.unpack_from("<IIIIIIII", data, 0)
    if magic != 0xFEEDFACF: fail("not a 64-bit Mach-O")
    off = 32
    sections = {}
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:
            nsects = struct.unpack_from("<I", data, off+64)[0]
            so = off + 72
            for _i in range(nsects):
                sn = data[so:so+16].rstrip(b"\x00").decode()
                seg = data[so+16:so+32].rstrip(b"\x00").decode()
                addr, size, fileoff = struct.unpack_from("<QQI", data, so+32)
                sections[(seg, sn)] = (addr, size, fileoff)
                so += 80
        off += cmdsize
    return sections

S = parse_sections(data)
def need(seg, sn):
    if (seg, sn) not in S: fail(f"missing section {seg},{sn}")
    return S[(seg, sn)]

ts_va, ts_sz, ts_off = need("__TEXT", "__text")
st_va, st_sz, st_off = need("__TEXT", "__stubs")
sr_va, sr_sz, sr_off = need("__DATA", "__objc_selrefs")
mn_va, mn_sz, mn_off = need("__TEXT", "__objc_methname")

# ---- locate _class_addMethod's __la_symbol_ptr address ----
def import_addr_via_lief():
    try:
        import lief
    except ImportError:
        return None
    b = lief.parse(path)
    if b is None: return None
    for binding in b.bindings:
        if binding.symbol and binding.symbol.name == "_class_addMethod":
            return binding.address
    return None

def import_addr_via_otool():
    if not (shutil.which("otool") or shutil.which("llvm-otool")):
        return None
    tool = "llvm-otool" if shutil.which("llvm-otool") else "otool"
    r = subprocess.run([tool, "-Iv", path], capture_output=True, text=True)
    if r.returncode != 0: return None
    cur = None
    for line in r.stdout.splitlines():
        if "Section" in line: cur = None
        if "section (__DATA,__la_symbol_ptr)" in line:
            cur = "la"; continue
        if cur == "la":
            m = re.match(r'^\s*0x([0-9a-fA-F]+)\s+\d+\s+(\S+)', line)
            if m and m.group(2) == "_class_addMethod":
                return int(m.group(1), 16) & 0xFFFFFFFF
    return None

cam = import_addr_via_lief() or import_addr_via_otool()
if cam is None:
    fail("cannot resolve _class_addMethod address. Install `lief` (pip install lief) "
         "or run on a host with otool.")
cam &= 0xFFFFFFFF

# ---- find the __stubs entry that loads from cam ----
def insn(off): return struct.unpack_from("<I", data, off)[0]
def decode_adrp(i, pc):
    immlo = (i >> 29) & 0x3
    immhi = (i >> 5) & 0x7FFFF
    imm = (immhi << 2) | immlo
    if imm & (1<<20): imm -= (1<<21)
    return i & 0x1F, (pc & ~0xFFF) + (imm << 12)

cam_stub = None
for stub_va in range(st_va, st_va + st_sz, 12):
    foff = st_off + (stub_va - st_va)
    i1 = insn(foff); i2 = insn(foff+4)
    _, page = decode_adrp(i1, stub_va)
    imm = ((i2 >> 10) & 0xFFF) << 3
    if page + imm == cam:
        cam_stub = stub_va; break
if cam_stub is None: fail("no __stubs entry resolves to _class_addMethod")

# ---- walk __text, log every selector loaded into x1 before bl cam_stub ----
def is_adrp(i): return ((i >> 31) & 1) == 1 and ((i >> 24) & 0x9f) == 0x90
def is_ldr_imm64_uns(i): return ((i >> 22) & 0x3FF) == 0b1111100101
def decode_bl(i, pc):
    if (i >> 26) != 0b100101: return None
    imm26 = i & 0x3FFFFFF
    if imm26 & (1<<25): imm26 -= (1<<26)
    return pc + (imm26 << 2)

def cstr_at(va):
    if not (mn_va <= va < mn_va + mn_sz): return None
    foff = mn_off + (va - mn_va)
    end = data.index(b"\x00", foff)
    return data[foff:end].decode("utf-8", errors="replace")

def selref_to_sel(va):
    if not (sr_va <= va < sr_va + sr_sz): return None
    foff = sr_off + (va - sr_va)
    p = struct.unpack_from("<Q", data, foff)[0] & 0xFFFFFFFF
    return cstr_at(p)

added = set()
for pc in range(ts_va, ts_va + ts_sz, 4):
    foff = ts_off + (pc - ts_va)
    i = insn(foff)
    if decode_bl(i, pc) != cam_stub: continue
    adrp_state = {}
    last_sel = None
    for back_pc in range(max(ts_va, pc - 32*4), pc, 4):
        bi = insn(ts_off + (back_pc - ts_va))
        # Stop tracking through any branch -- it clobbers the register state.
        # bl/b/blr/br/ret all break our linear-flow assumption.
        op = bi >> 26
        if op == 0b000101 or op == 0b100101:  # b / bl
            adrp_state.clear()
            last_sel = None
            continue
        if (bi & 0xFFFFFC1F) == 0xD61F0000 or (bi & 0xFFFFFC1F) == 0xD63F0000:  # br/blr
            adrp_state.clear()
            last_sel = None
            continue
        if is_adrp(bi):
            rd, page = decode_adrp(bi, back_pc)
            adrp_state[rd] = page
        if is_ldr_imm64_uns(bi):
            rt = bi & 0x1F; rn = (bi >> 5) & 0x1F
            imm = ((bi >> 10) & 0xFFF) << 3
            if rt == 1 and rn in adrp_state:
                s = selref_to_sel(adrp_state[rn] + imm)
                if s: last_sel = s   # overwrite: keep the most recent
    if last_sel is not None:
        added.add(last_sel)

print(f"Found {len(added)} unique selectors added via class_addMethod.\n")
required = ["registerTweak:metadata:", "buttonImage:"]
sanity   = ["switchWithTitle:key:", "didPressPiP:event:", "updateYTPlusTweaksSectionWithSettingsVC:"]

all_good = True
for sel in required:
    if sel in added: ok(f"'{sel}' is added via class_addMethod")
    else:
        print(f"FAIL: '{sel}' is NOT added via class_addMethod -- YTVideoOverlay registry not compiled in.")
        all_good = False

for sel in sanity:
    if sel in added: ok(f"'{sel}' present (sanity)")
    else: print(f"WARN: expected selector '{sel}' missing")

sys.exit(0 if all_good else 1)
