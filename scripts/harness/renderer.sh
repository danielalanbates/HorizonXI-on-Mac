#!/bin/zsh
# Switch the D3D translation stack used by the wrapper's wine.
#
#   ./renderer.sh save                 snapshot the current wine renderer DLLs (once)
#   ./renderer.sh dxmt                 install DXMT   (d3d11/dxgi/winemetal -> Metal, no Vulkan)
#   ./renderer.sh dxvk11               install DXVK's d3d11 (-> Vulkan -> MoltenVK)
#   ./renderer.sh restore              put wine's own builtin DLLs back
#
# DXMT/DXVK-d3d11 only matter in combination with a D3D8->D3D11 wrapper (dgVoodoo2) in the
# game directory; on their own FFXI never calls d3d11.
set -e
W="/Users/daniel/Games/HorizonXI/siku.app"
L="$W/Contents/SharedSupport/wine/lib/wine"
R="$W/Contents/Frameworks/renderer"
BK="/Users/daniel/Games/hxi-workspace/baseline-config/wine-renderer"

PE=(d3d11.dll d3d10core.dll dxgi.dll winemetal.dll)

case "$1" in
save)
  mkdir -p "$BK/i386-windows" "$BK/x86_64-unix"
  for f in $PE; do
    [[ -f "$L/i386-windows/$f" ]] && cp -a "$L/i386-windows/$f" "$BK/i386-windows/$f"
  done
  [[ -f "$L/x86_64-unix/winemetal.so" ]] && cp -a "$L/x86_64-unix/winemetal.so" "$BK/x86_64-unix/"
  echo "saved to $BK"
  ;;
dxmt)
  for f in $PE; do
    [[ -f "$R/dxmt/wine/i386-windows/$f" ]] && cp -f "$R/dxmt/wine/i386-windows/$f" "$L/i386-windows/$f"
  done
  cp -f "$R/dxmt/wine/x86_64-unix/winemetal.so" "$L/x86_64-unix/winemetal.so"
  echo "renderer = dxmt $(cat "$R/dxmt/version")"
  ;;
dxvk11)
  for f in d3d11.dll d3d10core.dll; do
    cp -f "$R/dxvk/wine/i386-windows/$f" "$L/i386-windows/$f"
  done
  # DXVK's package has no dxgi for i386; wine's builtin dxgi drives it.
  [[ -f "$BK/i386-windows/dxgi.dll" ]] && cp -f "$BK/i386-windows/dxgi.dll" "$L/i386-windows/dxgi.dll"
  echo "renderer = dxvk-d3d11 $(cat "$R/dxvk/version")"
  ;;
restore)
  for f in $PE; do
    [[ -f "$BK/i386-windows/$f" ]] && cp -f "$BK/i386-windows/$f" "$L/i386-windows/$f"
  done
  rm -f "$L/x86_64-unix/winemetal.so"
  [[ -f "$BK/x86_64-unix/winemetal.so" ]] && cp -f "$BK/x86_64-unix/winemetal.so" "$L/x86_64-unix/"
  echo "renderer = wine builtin"
  ;;
*)
  echo "usage: renderer.sh (save|dxmt|dxvk11|restore)"; exit 1;;
esac
