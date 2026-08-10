#!/bin/zsh
# Install / remove the D3D8 -> d3d8to9 -> DXVK 1.10.3 -> MoltenVK pathway.
#   dxvk.sh on    | dxvk.sh off
setopt no_err_exit 2>/dev/null || true
W="${HXI_WRAPPER:-/Volumes/x10/Video Games/Mac HorizonXI/siku.app}"
S="$W/Contents/SharedSupport"
export WINEPREFIX="$S/prefix10"
WINE="$S/wine/bin/wine"
G="$WINEPREFIX/drive_c/HorizonXI"
SYSWOW="$WINEPREFIX/drive_c/windows/syswow64"
REPO="${HXI_REPO:-/Users/daniel/Library/Mobile Documents/com~apple~CloudDocs/Code/HorizonXI-on-Mac}"
BK="$WINEPREFIX/drive_c/dll-backup"
LINK="$S/wine/lib/libMoltenVK.dylib"
MVK="$W/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"

DIRS=("$SYSWOW" "$G" "$G/bootloader" "$G/SquareEnix/PlayOnlineViewer" "$G/SquareEnix/FINAL FANTASY XI")

kill_wine() { pkill -9 -f horizon-loader 2>/dev/null; pkill -9 -f Ashita-cli 2>/dev/null; sleep 1; pkill wineserver 2>/dev/null; sleep 3; true }

kill_wine
mkdir -p "$BK"

if [[ "$1" == "on" ]]; then
  for d in d3d8 d3d9; do
    [[ -f "$SYSWOW/$d.dll" && ! -f "$BK/$d.builtin.dll" ]] && cp "$SYSWOW/$d.dll" "$BK/$d.builtin.dll"
  done
  CRT="$S/wine.cx32bak/lib32on64/wine"
  [[ -d "$CRT" ]] && cp "$CRT"/api-ms-win-crt-*.dll "$SYSWOW/" 2>/dev/null || true
  for d in "${DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    cp "$REPO/vendor/d3d8to9.dll" "$d/d3d8.dll"
    cp "$REPO/vendor/dxvk-1.10.3-x32-d3d9.dll" "$d/d3d9.dll"
  done
  "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v '*d3d8' /d native /f >/dev/null 2>&1
  "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /d native /f >/dev/null 2>&1
  [[ -f "$MVK" ]] && { [[ -e "$LINK" && ! -e "$LINK.stock" ]] && mv "$LINK" "$LINK.stock"; ln -sf "$MVK" "$LINK"; }
  echo "dxvk: on"
else
  for d in "${DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    rm -f "$d/d3d8.dll" "$d/d3d9.dll"
  done
  for d in d3d8 d3d9; do
    [[ -f "$BK/$d.builtin.dll" ]] && cp "$BK/$d.builtin.dll" "$SYSWOW/$d.dll"
  done
  "$WINE" reg delete 'HKCU\Software\Wine\DllOverrides' /v '*d3d8' /f >/dev/null 2>&1 || true
  "$WINE" reg delete 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /f >/dev/null 2>&1 || true
  [[ -e "$LINK.stock" ]] && { rm -f "$LINK"; mv "$LINK.stock" "$LINK"; }
  echo "dxvk: off"
fi
kill_wine
