#!/bin/zsh
# retail-client.sh <wrapper.app> <installerPrefixName> <world data dir> <world name>
#
# The bring-your-own-retail pathway (Supernova, OmicronXI, and any world whose setup guide says
# "install PlayOnline, then update"). Nothing here redistributes Square Enix data: it fetches
# Square Enix's own free Windows client from Square Enix, runs Square Enix's own installer and
# updater inside the wrapper, and adds the open-source Ashita v4 + xiloader on top. Steps, each
# idempotent (re-run to resume):
#
#   1. FFXIFullSetup_US.part1.exe + part2..5.rar (7.7 GB) from gdl.square-enix.com  -> <data>/retail-downloads
#   2. Unpack the 5-part RAR SFX with 7-Zip if installed (brew install sevenzip), else run
#      part1.exe under wine and let its own extractor unpack (GUI: pick the folder, Install).
#   3. Run the unpacked FFXISetup.exe under wine (Square Enix's InstallShield installer, GUI).
#      Install into C:\Games\<world>\SquareEnix when it asks — that is <data>/SquareEnix.
#   4. Ashita v4 (Ashita-v4beta release zip) + LandSandBoat xiloader.exe   -> <data>/Ashita
#   5. Boot profile <data>/Ashita/config/boot/<world>.ini pointing at bootloader/xiloader.exe.
#   6. PlayOnline update: launch pol.exe under wine; in PlayOnline choose FINAL FANTASY XI ›
#      Check Files, and let it patch (this is the multi-hour part; it resumes if interrupted).
#      A world's FFXI-UpdatePatch.zip (Supernova/Omicron) is applied over FINAL FANTASY XI
#      first when RETAIL_PATCH_URL is set — it seeds an old version table so the updater
#      fetches the whole chain.
#
# The launcher's own layout resolver then finds Ashita-cli.exe and SquareEnix under <data>.
set -euo pipefail
say() { print -r -- "==> $*"; }
die() { print -r -- "!! $*" >&2; exit 1; }

APP="${1:?wrapper.app}"; PFX="${2:?prefixName}"; DATA="${3:?data dir}"; WORLD="${4:?world name}"
SHARED="$APP/Contents/SharedSupport"; WINE="$SHARED/wine/bin/wine"
export WINEPREFIX="$SHARED/$PFX" WINEDEBUG=-all
unset DYLD_FALLBACK_LIBRARY_PATH DYLD_LIBRARY_PATH
[[ -x "$WINE" ]] || die "no wine at $WINE"
mkdir -p "$DATA"
DL="$DATA/retail-downloads"; mkdir -p "$DL"
UA="FFXI-on-Mac launcher"

SE_BASE="${SE_BASE:-https://gdl.square-enix.com/ffxi/download/us}"
PARTS=(FFXIFullSetup_US.part1.exe FFXIFullSetup_US.part2.rar FFXIFullSetup_US.part3.rar FFXIFullSetup_US.part4.rar FFXIFullSetup_US.part5.rar)

winepath() { # unix path -> wine path (C:\ for the prefix's drive_c, Z:\ otherwise)
  local p="$1" c="$WINEPREFIX/drive_c"
  if [[ "$p" == "$c/"* ]]; then print -r -- "C:${${p#$c}//\//\\}"; else print -r -- "Z:${p//\//\\}"; fi
}

# 1. Square Enix's client, five parts, resumable.
say "step 1/6: Square Enix's FFXI client (7.7 GB in five parts) -> $DL"
for f in $PARTS; do
  if [[ -f "$DL/$f.done" ]]; then say "  $f already complete"; continue; fi
  say "  fetching $f"
  curl -fL --retry 8 --retry-delay 5 -C - --progress-bar -A "$UA" -o "$DL/$f" "$SE_BASE/$f" \
    || { rc=$?; [[ $rc == 33 && -s "$DL/$f" ]] || die "download of $f failed (curl $rc)"; }
  touch "$DL/$f.done"
done

# 2. Unpack. 7-Zip reads the multi-part RAR SFX directly (no wine, no GUI); without it, the SFX
#    is run under wine and the user clicks Install.
UNPACK="$DL/FFXIFullSetup_US"
if [[ ! -f "$UNPACK/.unpacked" ]]; then
  say "step 2/6: unpacking the installer"
  if command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1; then
    SEVEN=$(command -v 7zz || command -v 7z)
    mkdir -p "$UNPACK"
    "$SEVEN" x -y -o"$UNPACK" "$DL/FFXIFullSetup_US.part1.exe" >/dev/null || die "7-Zip could not unpack the SFX"
  else
    say "  7-Zip not installed (brew install sevenzip) — running Square Enix's self-extractor under wine; choose $UNPACK and press Install"
    mkdir -p "$UNPACK"
    "$WINE" "$(winepath "$DL/FFXIFullSetup_US.part1.exe")" || true
  fi
  # any of the known layouts counts as unpacked
  find "$UNPACK" -iname 'FFXISetup.exe' -o -iname 'setup.exe' | head -1 | grep -q . || die "unpacked folder has no setup executable — re-run to try again"
  touch "$UNPACK/.unpacked"
fi
SETUP=$(find "$UNPACK" -iname 'FFXISetup.exe' | head -1); [[ -n "$SETUP" ]] || SETUP=$(find "$UNPACK" -iname 'setup.exe' | head -1)

# 3. Square Enix's installer, in the wrapper. Their default target is C:\Program Files (x86)\
#    PlayOnline\SquareEnix; C:\Games\<world> is pre-linked to the world's folder, so
#    C:\Games\<world>\SquareEnix keeps every world's client separate.
mkdir -p "$WINEPREFIX/drive_c/Games"
ln -sfn "$DATA" "$WINEPREFIX/drive_c/Games/$WORLD" 2>/dev/null || true
if [[ ! -d "$DATA/SquareEnix/FINAL FANTASY XI" && ! -d "$WINEPREFIX/drive_c/Program Files (x86)/PlayOnline/SquareEnix/FINAL FANTASY XI" ]]; then
  say "step 3/6: Square Enix's installer — install into C:\\Games\\$WORLD\\SquareEnix (that is $DATA/SquareEnix)"
  "$WINE" "$(winepath "$SETUP")" || true
fi
# If it went to the default place anyway, move it under the world's folder.
if [[ ! -d "$DATA/SquareEnix/FINAL FANTASY XI" && -d "$WINEPREFIX/drive_c/Program Files (x86)/PlayOnline/SquareEnix/FINAL FANTASY XI" ]]; then
  say "  moving the client from Program Files into $DATA/SquareEnix"
  mv "$WINEPREFIX/drive_c/Program Files (x86)/PlayOnline/SquareEnix" "$DATA/SquareEnix"
  ln -sfn "$DATA/SquareEnix" "$WINEPREFIX/drive_c/Program Files (x86)/PlayOnline/SquareEnix"
fi
[[ -d "$DATA/SquareEnix/FINAL FANTASY XI" ]] || die "no FINAL FANTASY XI folder yet — the installer did not finish; run Download again to resume from here"

# 4. Ashita v4 + xiloader.
ASHITA="$DATA/Ashita"
if [[ ! -f "$ASHITA/Ashita-cli.exe" ]]; then
  say "step 4/6: Ashita v4"
  mkdir -p "$ASHITA"
  # Ashita v4 is published as a zip on its GitHub releases page.
  url=$(curl -fsSL -A "$UA" https://api.github.com/repos/AshitaXI/Ashita-v4beta/releases/latest 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((a["browser_download_url"] for a in d.get("assets",[]) if a["name"].lower().endswith(".zip")),""))' 2>/dev/null || true)
  if [[ -z "$url" ]]; then
    url="https://github.com/AshitaXI/Ashita-v4beta/archive/refs/heads/main.zip"
    say "  no release asset listed — using the repository snapshot"
  fi
  curl -fL --retry 5 -A "$UA" -o "$DL/ashita.zip" "$url" || die "could not fetch Ashita v4"
  ditto -x -k "$DL/ashita.zip" "$DL/ashita-unpacked" || die "Ashita zip did not unpack"
  cli=$(find "$DL/ashita-unpacked" -name 'Ashita-cli.exe' | head -1); [[ -n "$cli" ]] || die "Ashita zip has no Ashita-cli.exe"
  ditto "${cli:h}" "$ASHITA"
fi
if [[ ! -f "$ASHITA/bootloader/xiloader.exe" ]]; then
  say "  xiloader (LandSandBoat)"
  mkdir -p "$ASHITA/bootloader"
  url=$(curl -fsSL -A "$UA" https://api.github.com/repos/LandSandBoat/xiloader/releases/latest 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((a["browser_download_url"] for a in d.get("assets",[]) if a["name"].lower()=="xiloader.exe"),""))' 2>/dev/null || true)
  [[ -n "$url" ]] || die "could not find xiloader.exe on LandSandBoat's releases"
  curl -fL --retry 5 -A "$UA" -o "$ASHITA/bootloader/xiloader.exe" "$url" || die "could not fetch xiloader.exe"
fi

# 5. Boot profile: the launcher rewrites `command =` with host + credentials at Play; this only
#    has to exist and name the right loader.
PROFILE="$ASHITA/config/boot/${${WORLD:l}// /}.ini"
if [[ ! -f "$PROFILE" ]]; then
  say "step 5/6: boot profile ${PROFILE:t}"
  mkdir -p "${PROFILE:h}"
  seed=$(ls "$ASHITA"/config/boot/example-privateserver.ini "$ASHITA"/config/boot/example.ini 2>/dev/null | head -1)
  if [[ -n "$seed" ]]; then
    sed -e 's#^file *=.*#file        = .\\\\bootloader\\\\xiloader.exe#' -e 's#^command *=.*#command     = --server localhost#' "$seed" > "$PROFILE"
  else
    cat > "$PROFILE" <<EOF
[ashita.launcher]
autoclose   = 1
name        = $WORLD
[ashita.boot]
file        = .\\\\bootloader\\\\xiloader.exe
command     = --server localhost
gamemodule  = ffximain.dll
script      = default.txt
[ashita.language]
playonline  = 2
ashita      = 2
[ffxi.registry]
0000        = 6
EOF
  fi
  chmod 600 "$PROFILE"
fi

# 6. World patch (optional) + PlayOnline update.
FFXI="$DATA/SquareEnix/FINAL FANTASY XI"
if [[ -n "${RETAIL_PATCH_URL:-}" && ! -f "$FFXI/.world-patch-applied" ]]; then
  say "step 6a: world patch $RETAIL_PATCH_URL over FINAL FANTASY XI"
  curl -fL --retry 5 -A "$UA" -o "$DL/world-patch.zip" "$RETAIL_PATCH_URL" || die "could not fetch the world patch"
  ditto -x -k "$DL/world-patch.zip" "$FFXI" || die "world patch did not unpack"
  touch "$FFXI/.world-patch-applied"
fi
POL="$DATA/SquareEnix/PlayOnlineViewer/pol.exe"
if [[ -f "$POL" ]]; then
  say "step 6/6: PlayOnline update — in the PlayOnline window choose FINAL FANTASY XI › Check Files and let it patch. Hours. Close PlayOnline when it says the files are up to date."
  # POL needs its registry entries in this prefix to start at all.
  for REG in 'C:\windows\syswow64\reg.exe' reg; do
    "$WINE" $REG add "HKLM\\SOFTWARE\\PlayOnlineUS\\InstallFolder" /v 0001 /d "$(winepath "$FFXI")" /f >/dev/null 2>&1 || true
    "$WINE" $REG add "HKLM\\SOFTWARE\\PlayOnlineUS\\InstallFolder" /v 1000 /d "$(winepath "$DATA/SquareEnix/PlayOnlineViewer")" /f >/dev/null 2>&1 || true
    "$WINE" $REG add "HKLM\\SOFTWARE\\PlayOnlineUS\\Interface" /v 0001 /d "0" /f >/dev/null 2>&1 || true
  done
  "$WINE" "$(winepath "$POL")" || true
fi
say "retail client steps done for $WORLD — press ↻ in the launcher; Play uses $ASHITA + $DATA/SquareEnix"
