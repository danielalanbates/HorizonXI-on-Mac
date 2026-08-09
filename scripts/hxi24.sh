#!/bin/zsh
S="/Volumes/x10/Video Games/Mac HorizonXI/siku.app/Contents/SharedSupport"
export WINEPREFIX="$S/prefixcx24n"
cd "$WINEPREFIX/drive_c/HorizonXI" 2>/dev/null || cd /tmp
exec "$S/wine.cx24bak/bin/wine" "$@"
