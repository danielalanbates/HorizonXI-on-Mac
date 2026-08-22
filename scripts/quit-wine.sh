#!/bin/zsh
# quit-wine.sh — force-close every Wine window/process from the FFXI wrapper.
# Use whenever a Wine window (crash dialog, hung game) refuses to close.
SHARED="${1:-/Volumes/Games/FFXI/siku.app/Contents/SharedSupport}"
WS="$SHARED/wine/bin/wineserver"
[[ -x "$WS" ]] && WINEPREFIX="$SHARED/prefix10" "$WS" -k -w 2>/dev/null
pkill -9 -f 'winedbg' 2>/dev/null
pkill -9 -f 'horizon-loader.exe|Ashita-cli.exe|xiloader|pol.exe|FFXi.exe' 2>/dev/null
pkill -9 -f "$SHARED/wine" 2>/dev/null
pkill -9 -f 'wineserver|winedevice.exe|services.exe|explorer.exe' 2>/dev/null
sleep 1
left=$(pgrep -fl 'wine|horizon-loader' | grep -v quit-wine | wc -l | tr -d ' ')
echo "wine processes remaining: $left"
