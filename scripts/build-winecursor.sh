#!/bin/zsh
# Build winecursor.dylib (universal: arm64 + x86_64).
#
# x86_64 is the one that matters -- Wine on Apple Silicon runs under Rosetta and that is the
# process whose +[NSCursor hide] we neutralise. arm64 is built too so the swizzle can be tested
# natively (scripts/tests/winecursor-test.m) without Rosetta in the way.
set -euo pipefail
REPO="${0:A:h:h}"
SRC="$REPO/cursor/winecursor.m"
OUT="$REPO/app/Resources/winecursor.dylib"
mkdir -p "$REPO/app/Resources"
CFLAGS=(-O2 -Wall -Wextra -dynamiclib -fobjc-arc -framework AppKit -framework Foundation
        -install_name @rpath/winecursor.dylib)
clang -arch arm64  "${CFLAGS[@]}" -o "$OUT.arm64"  "$SRC"
clang -arch x86_64 "${CFLAGS[@]}" -o "$OUT.x86_64" "$SRC"
lipo -create "$OUT.arm64" "$OUT.x86_64" -output "$OUT"
rm -f "$OUT.arm64" "$OUT.x86_64"
codesign --force --sign - "$OUT"
echo "built $OUT"; lipo -info "$OUT"
