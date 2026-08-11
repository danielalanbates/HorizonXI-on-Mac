#!/bin/zsh
# Clean-room launch: upstream WineHQ wine (LGPL 2.1) instead of the CrossOver-derived wrapper.
W="/Users/daniel/Games/WineHQ/Wine Stable.app/Contents/Resources/wine"
export WINEPREFIX="/Users/daniel/Games/HorizonXI/prefix-winehq"
export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1
export WINEMSYNC=1
export MVK_CONFIG_FAST_MATH_ENABLED=1
export MVK_CONFIG_USE_COMMAND_POOLING=1
export MVK_CONFIG_PREALLOCATE_DESCRIPTORS=1
export MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1
export DXVK_CONFIG_FILE='C:\HorizonXI\dxvk.conf'
export DXVK_HUD=fps,drawcalls,version
export WINEDEBUG=-all
cd "$WINEPREFIX/drive_c/HorizonXI" || exit 1
exec "$W/bin/wine" "C:\\HorizonXI\\Ashita-cli.exe" horizonxi.ini
