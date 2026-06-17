#!/usr/bin/env bash
set -o pipefail
export THEOS="$HOME/theos"; export PATH="$THEOS/bin:$PATH"; export THEOS_PACKAGE_SCHEME=rootless
SRC="/mnt/c/Users/Corey/Documents/GitHub/YTPlusRevanced"
DST="$HOME/ytbuild-rel/YTPlusRevanced"
OUT="/mnt/c/Users/Corey/Downloads"
echo "=== syncing to ext4 ==="
rm -rf "$HOME/ytbuild-rel"; mkdir -p "$DST"
( cd "$SRC" && tar --exclude=.theos --exclude=packages --exclude=.git -cf - . ) | ( cd "$DST" && tar xf - )
cd "$DST" || { echo "cd failed"; exit 1; }
echo "=== Building RELEASE (DIAG=0) ==="
make clean package DEBUG=0 FINALPACKAGE=1 DIAG=0 YOUTUBE_VERSION=21.24.3 2>&1
rc=$?; echo "=== make exit code: $rc ==="
DEB=$(find packages .theos/debs -name '*.deb' 2>/dev/null | head -1)
if [ -n "$DEB" ]; then cp "$DEB" "$OUT/$(basename "$DEB")"; echo "=== COPIED: $OUT/$(basename "$DEB") ($(du -h "$DEB"|cut -f1)) ==="; else echo "=== NO DEB ==="; fi
exit $rc
