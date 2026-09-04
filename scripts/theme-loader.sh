#!/bin/zsh
# theme-loader.sh — give a world's boot loader an icon, so its Dock tile is not wine's generic one.
#
# wine's macOS driver takes the Dock tile from the first RT_GROUP_ICON of the running .exe, once,
# at first window creation (see docs/DOCK-ICON.md). HorizonXI's horizon-loader.exe has no icon
# resource at all, so wine falls back to its own. This adds one — to a COPY, never in place.
#
#   ./scripts/theme-loader.sh <prefix drive_c path> <world dir> <loader name>
#
# Needs i686-w64-mingw32-gcc (brew install mingw-w64) and the wine at WINE, and leaves
# <world>/bootloader-ffxi/<loader name> next to the original.
#
# STATUS 2026-08-21: the patched copy is a valid executable and runs standalone, but Ashita will
# not boot it — banner, then silence. Do not point a boot profile at the result until that is
# understood. Kept because the icon injection itself is correct and re-runnable.
set -euo pipefail
HERE="${0:A:h}"; REPO="${HERE:h}"
DRIVE_C="${1:?drive_c path}"; WORLD="${2:?world dir, e.g. HorizonXI}"; LOADER="${3:-horizon-loader.exe}"
WINE="${WINE:-$HOME/Library/Application Support/HorizonXI-on-Mac/runtimes/wine-cx-26.3.0-1/wine/bin/wine}"

BOOT="$DRIVE_C/$WORLD/bootloader"
OUT="$DRIVE_C/$WORLD/bootloader-ffxi"
[[ -f "$BOOT/$LOADER" ]] || { print -u2 "no $LOADER in $BOOT"; exit 1 }

i686-w64-mingw32-gcc -O2 -o "$REPO/tools/icon-into-exe.exe" "$REPO/tools/icon-into-exe.c"

mkdir -p "$OUT"
cp "$BOOT/$LOADER" "$OUT/$LOADER"
cp "$BOOT"/d3d8.dll "$BOOT"/d3d9.dll "$OUT/" 2>/dev/null || true
cp "$REPO/tools/icon-into-exe.exe" "$OUT/icon-into-exe.exe"
cp "$REPO/addons/mousediag/ffxi-dock.ico" "$OUT/ffxi-dock.ico"

cd "$OUT"
"$WINE" icon-into-exe.exe "$LOADER" ffxi-dock.ico
rm -f "$OUT/icon-into-exe.exe" "$OUT/ffxi-dock.ico"

print "themed loader: $OUT/$LOADER"
command -v wrestool >/dev/null && wrestool -l "$OUT/$LOADER" | grep -i group_icon || true
