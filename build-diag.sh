#!/usr/bin/env bash
set -o pipefail
export THEOS="$HOME/theos"
export PATH="$THEOS/bin:$PATH"
export THEOS_PACKAGE_SCHEME=rootless

SRC="/mnt/c/Users/Corey/Downloads/YTPlusRevanced-main"
DST="$HOME/ytbuild-diag/YTPlusRevanced-main"
OUT="/mnt/c/Users/Corey/Downloads"

echo "=== syncing source to native ext4 ($DST) ==="
rm -rf "$HOME/ytbuild-diag"
mkdir -p "$DST"
( cd "$SRC" && tar --exclude=.theos --exclude=packages -cf - . ) | ( cd "$DST" && tar xf - )

cd "$DST" || { echo "cd failed"; exit 1; }
echo "=== Building DIAG=1 deb (rootless, 21.24.3) ==="
make clean package DEBUG=0 FINALPACKAGE=1 DIAG=1 YOUTUBE_VERSION=21.24.3 2>&1
rc=$?
echo "=== make exit code: $rc ==="

DEB=$(find packages .theos/debs -name '*.deb' 2>/dev/null | head -1)
if [ -n "$DEB" ]; then
  base=$(basename "$DEB" .deb)
  cp "$DEB" "$OUT/${base}-DIAG.deb"
  echo "=== COPIED TO WINDOWS: $OUT/${base}-DIAG.deb ($(du -h "$DEB" | cut -f1)) ==="
else
  echo "=== NO DEB PRODUCED ==="
fi
exit $rc
