#!/bin/zsh
# Build audiofollow.dylib (universal: arm64 + x86_64).
#
# x86_64 is the one that matters — wine on Apple Silicon runs under Rosetta and that is the
# process whose CoreAudio calls we interpose. arm64 is built too so the same file can be tested
# natively on the Mac (scripts/tests/audiofollow-test.c) without Rosetta in the way.
set -euo pipefail
REPO="${0:A:h:h}"
SRC="$REPO/audio/audiofollow.c"
OUT="$REPO/app/Resources/audiofollow.dylib"
mkdir -p "$REPO/app/Resources"
CFLAGS=(-O2 -Wall -Wextra -dynamiclib -framework AudioToolbox -framework CoreAudio
        -install_name @rpath/audiofollow.dylib)
clang -arch arm64   "${CFLAGS[@]}" -o "$OUT.arm64"  "$SRC"
clang -arch x86_64  "${CFLAGS[@]}" -o "$OUT.x86_64" "$SRC"
lipo -create "$OUT.arm64" "$OUT.x86_64" -output "$OUT"
rm -f "$OUT.arm64" "$OUT.x86_64"
codesign --force --sign - "$OUT"
echo "built $OUT"
lipo -info "$OUT"
