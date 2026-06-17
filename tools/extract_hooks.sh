#!/usr/bin/env bash
# extract_hooks.sh — list every (file, class, selector) the tweak %hook's.
# Skips %new/%property (tweak-added, not real YT methods). Output is TSV for tools/dump_objc.py audit().
#
# Usage (from the project root):
#   bash tools/extract_hooks.sh > hooks.tsv
#   # then in IDA (with the new YouTube binary loaded):  T.audit(r"C:\...\hooks.tsv")
#
# Selector reconstruction: joins keyword:parts: of each method signature; bare methods keep their name.

set -euo pipefail
ROOT="${1:-.}"
cd "$ROOT"

find . -name '*.x' -o -name '*.xm' -o -name '*.mm' | while read -r f; do
  awk '
    /%new/ { skip=1 }
    /%hook[ \t]/ { l=$0; sub(/.*%hook[ \t]+/,"",l); sub(/[ \t<({].*/,"",l); cls=l; inhook=1; next }
    /%end/ { inhook=0; cls=""; next }
    inhook && /^[ \t]*[-+][ \t]*\(/ {
      if(skip){skip=0; next}
      sig=$0; sub(/^[ \t]*[-+][ \t]*/,"",sig); sub(/^\([^)]*\)[ \t]*/,"",sig); sub(/\{.*/,"",sig);
      sel=""; rest=sig;
      if(index(rest,":")>0){
        while(match(rest,/[A-Za-z_][A-Za-z0-9_]*[ \t]*:/)){
          kw=substr(rest,RSTART,RLENGTH); gsub(/[ \t:]/,"",kw); sel=sel kw ":";
          rest=substr(rest,RSTART+RLENGTH)
        }
      } else {
        if(match(rest,/[A-Za-z_][A-Za-z0-9_]*/)) sel=substr(rest,RSTART,RLENGTH)
      }
      if(sel!="") print FILENAME"\t"cls"\t"sel
    }
  ' "$f"
done | sort -u
