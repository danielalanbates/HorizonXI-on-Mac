#!/bin/zsh
# addons.sh — change a world's addon list without the launcher window.
#
#   scripts/addons.sh list                      [--world "Local server"]
#   scripts/addons.sh enable  name[,name…]      [--world NAME] [--force]
#   scripts/addons.sh disable name[,name…]      [--world NAME] [--force]
#   scripts/addons.sh narration on|off
#   scripts/addons.sh script                    [--world NAME]      # which file that world runs
#
# A thin wrapper over `FFXI-on-Mac --addons …` (app/Sources/HorizonXILauncher/AddonsCLI.swift),
# run through the installed .app so it reads the launcher's own settings (selected world,
# remembered install, narration). Without --world it acts on the world selected in the launcher.
# It never launches the game and can run while one is playing.
#
# Copyright (c) 2026 Daniel Bates / Bates LLC. All rights reserved.
set -u
APP="${FFXI_ON_MAC_APP:-/Applications/FFXI-on-Mac.app}"
BIN="$APP/Contents/MacOS/FFXI-on-Mac"
[[ -x "$BIN" ]] || { print -u2 -- "no launcher at $APP (set FFXI_ON_MAC_APP)"; exit 2; }
exec "$BIN" --addons "$@"
