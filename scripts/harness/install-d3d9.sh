#!/bin/zsh
# Install a d3d9.dll into every path the game can load it from. Missing one silently tests the
# old build -- this cost a lot of time in an earlier session, so it is scripted now.
set -e
SRC="${1:?usage: install-d3d9.sh <d3d9.dll>}"
P="/Users/daniel/Games/HorizonXI/siku.app/Contents/SharedSupport/prefix10"
for d in \
  "$P/drive_c/HorizonXI" \
  "$P/drive_c/HorizonXI/bootloader" \
  "/Users/daniel/Games/HorizonXI/SquareEnix/FINAL FANTASY XI" \
  "/Users/daniel/Games/HorizonXI/SquareEnix/PlayOnlineViewer" \
  "$P/drive_c/windows/syswow64"
do
  [[ -d "$d" ]] && cp -f "$SRC" "$d/d3d9.dll" && echo "  -> $d"
done
md5 -q "$SRC"
