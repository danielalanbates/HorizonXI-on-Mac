#!/bin/zsh
# install.sh — configure a Wine prefix so HorizonXI (Final Fantasy XI) actually launches on macOS.
#
# Assumes: a Sikarugir/Kegworks-style wrapper .app containing a wine build, and the HorizonXI
# client already extracted to <prefix>/drive_c/HorizonXI (~27GB).
#
# This encodes the configuration that was proven to work on an M1 MacBook Pro, macOS 26.5,
# Wine 10.0 (Sikarugir), HorizonXI client 1.9.0, Ashita 4.3.1.2 — the first time FFXI has
# rendered natively on macOS. Every step here is load-bearing; see docs/FINDINGS.md for the
# instrumented evidence behind each one.
#
#   ./install.sh /path/to/wrapper.app [prefix-name]

set -euo pipefail

APP="${1:?usage: install.sh /path/to/wrapper.app [prefix-name]}"
PREFIX_NAME="${2:-prefix10}"
SHARED="$APP/Contents/SharedSupport"
export WINEPREFIX="$SHARED/$PREFIX_NAME"
WINE="$SHARED/wine/bin/wine"
GAME_C='C:\HorizonXI'
SE_C="$GAME_C\\SquareEnix"
REG32='C:\windows\syswow64\reg.exe'

[[ -x "$WINE" ]] || { echo "no wine at $WINE" >&2; exit 1; }
[[ -d "$WINEPREFIX/drive_c/HorizonXI" ]] || { echo "no client at $WINEPREFIX/drive_c/HorizonXI" >&2; exit 1; }

info() { print -P "%F{cyan}==>%f $*"; }

# ---------------------------------------------------------------------------
# 1. dylib rpath.
#
# The wrapper's wine/wineserver are linked with rpath @loader_path/../../, which resolves to
# SharedSupport/, but the dylibs ship in Contents/Frameworks/. Everyone works around this by
# exporting DYLD_FALLBACK_LIBRARY_PATH — do not. SIP strips DYLD_* when exec'ing a protected
# binary, which includes nohup and /bin/sh, so anything scripted or backgrounded breaks with an
# unexplained "dyld: Library not loaded". Symlinking removes the env dependency entirely.
# ---------------------------------------------------------------------------
info "fixing dylib rpath"
"${0:h}/fix-wine-rpath.sh" "$APP" >/dev/null

# ---------------------------------------------------------------------------
# 2. PlayOnline registry.
#
# Taken verbatim from HorizonXI's own Switch_Horizon.bat, which ships in SquareEnix/. The layout
# is not what it looks like:
#   InstallFolder\0001 = the FINAL FANTASY XI directory   (NOT PlayOnlineViewer)
#   InstallFolder\1000 = the PlayOnlineViewer directory
#   Interface\0001     = the string "0"
# Putting PlayOnlineViewer in 0001 — the intuitive reading — stops FFXiMain.dll loading at all.
#
# Write BOTH registry views. The 32-bit game reads HKLM\SOFTWARE\Wow6432Node\..., and the 64-bit
# reg.exe writes only the 64-bit view, so a prefix configured with plain `wine reg add` leaves the
# game seeing nothing.
# ---------------------------------------------------------------------------
info "writing PlayOnline registry (both views)"
for REG in "$REG32" reg; do
  "$WINE" $REG add "HKLM\\SOFTWARE\\PlayOnlineUS\\InstallFolder" /v 0001 /d "$SE_C\\FINAL FANTASY XI" /f >/dev/null 2>&1
  "$WINE" $REG add "HKLM\\SOFTWARE\\PlayOnlineUS\\InstallFolder" /v 1000 /d "$SE_C\\PlayOnlineViewer" /f >/dev/null 2>&1
  "$WINE" $REG add "HKLM\\SOFTWARE\\PlayOnlineUS\\Interface"     /v 0001 /d "0" /f >/dev/null 2>&1
done

# The client ships pol.reg / polu.reg; polu.reg holds HKCU video settings the game needs present.
for r in pol polu; do
  [[ -f "$WINEPREFIX/drive_c/$r.reg" ]] && "$WINE" regedit /S "C:\\$r.reg" >/dev/null 2>&1 || true
done

# ---------------------------------------------------------------------------
# 3. COM registration.
#
# FFXI is three in-proc COM servers, not one: FFXi.FFXiEntry (FFXi.dll),
# FFXiMain.GameMain (FFXiMain.dll) and POLCore.POLCoreCom (polcore.dll). Missing any of them
# gives "Failed to initialize instance of FFxi!" or a bare err:ole:com_get_class_object.
#
# The /s flag is mandatory: without it FFXi.dll's DllRegisterServer opens a GUI dialog, and
# synthetic input (CGEvent) does not reach wine-hosted windows on macOS, so it hangs forever
# with nothing to click.
# ---------------------------------------------------------------------------
info "registering FFXI COM servers"
for d in FFXi.dll FFXiMain.dll FFXiVersions.dll; do
  "$WINE" regsvr32 /s "$SE_C\\FINAL FANTASY XI\\$d" >/dev/null 2>&1
done
"$WINE" regsvr32 /s "$SE_C\\PlayOnlineViewer\\viewer\\com\\polcore.dll" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 4. Launcher.
#
# Launch through Ashita-cli, not xiloader directly. With the registry above but launched
# xiloader-direct, the game still exits silently before creating its window; through Ashita it
# runs. Always pass the absolute C:\ path — wine resolves a bare exe name against
# C:\windows\system32, not the cwd.
# ---------------------------------------------------------------------------
info "writing launcher"
LAUNCHER="${APP:h}/Play HorizonXI.command"
cat > "$LAUNCHER" <<EOF
#!/bin/zsh
W="$APP"
export WINEPREFIX="\$W/Contents/SharedSupport/$PREFIX_NAME"
export D3DMETAL_FRAMEWORK_PATH="\$W/Contents/Frameworks/renderer/d3dmetal/external"
export WINEDEBUG=-all
cd "\$WINEPREFIX/drive_c/HorizonXI" || { echo "game dir missing"; exit 1; }
exec "\$W/Contents/SharedSupport/wine/bin/wine" "C:\\\\HorizonXI\\\\Ashita-cli.exe" horizonxi.ini
EOF
chmod +x "$LAUNCHER"

info "done — launch with: $LAUNCHER"
echo
echo "Note: the character-select screen needs a real keypress. Synthetic input does not reach"
echo "wine windows on macOS, so that step cannot be scripted; click the window and press Enter."
