#!/bin/zsh
# catseye-launcher.sh <wrapper.app> <prefixName>
# Runs CatsEyeXI's own launcher inside the wine prefix. Their client is only obtainable through
# that launcher (private Cloudflare R2 storage), so instead of re-implementing it this wraps it:
# fetch the current build from catseyexi.com/launcher_version.txt, make WPF render in software
# (hardware WPF under wine draws a blank white window — verified 2026-08-15), and start it.
# The user then does the install/update in CatsEye's UI; it defaults to C:\Games\CatsEyeXI.
set -euo pipefail
APP="${1:?wrapper.app}"; PFX="${2:?prefixName}"
SHARED="$APP/Contents/SharedSupport"; WINE="$SHARED/wine/bin/wine"
export WINEPREFIX="$SHARED/$PFX" WINEDEBUG=-all
unset DYLD_FALLBACK_LIBRARY_PATH DYLD_LIBRARY_PATH
dir="$WINEPREFIX/drive_c/CatsEyeXI-Launcher"; mkdir -p "$dir"
line=$(curl -fsSL --max-time 20 https://www.catseyexi.com/launcher_version.txt | head -1 || true)
url="${line%%,*}"; ver="${line##*, }"
if [[ -n "$url" && ( ! -f "$dir/CatsEyeXI-Launcher.exe" || "$(cat "$dir/.version" 2>/dev/null)" != "$ver" ) ]]; then
  echo "==> fetching CatsEyeXI launcher $ver"
  curl -fL --progress-bar "$url" -o "$dir/launcher.zip"
  ditto -x -k "$dir/launcher.zip" "$dir" && rm -f "$dir/launcher.zip"
  print -r -- "$ver" > "$dir/.version"
fi
[[ -f "$dir/CatsEyeXI-Launcher.exe" ]] || { echo "!! CatsEyeXI-Launcher.exe missing and could not be fetched"; exit 1; }
"$WINE" reg add 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
echo "==> starting CatsEyeXI's launcher (install to C:\\Games\\CatsEyeXI when it asks)"
exec "$WINE" 'C:\CatsEyeXI-Launcher\CatsEyeXI-Launcher.exe'
