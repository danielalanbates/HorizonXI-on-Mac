#!/bin/zsh
# Play HorizonXI — runs entirely from the internal SSD (no external drive needed).
# Renderer: Metal / DXVK 1.10.3 (patched: Metal feature relaxations + the fixed-function
# push-constant fix that restored fog).
B="/Users/daniel/Games/HorizonXI"
W="$B/siku.app"
export WINEPREFIX="$W/Contents/SharedSupport/prefix10"
export DYLD_FALLBACK_LIBRARY_PATH="$W/Contents/Frameworks:/usr/lib"
export D3DMETAL_FRAMEWORK_PATH="$W/Contents/Frameworks/renderer/d3dmetal/external"
export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1

# Measured 2026-08-11: these three together took the same scene from 17.6 fps to 22.8 fps
# (~30%). None of them touch rendering logic, so none can cause visual glitches:
#   WINEMSYNC                  wine's fast thread synchronisation (was never being set here)
#   MVK_CONFIG_FAST_MATH       relaxed float maths in generated Metal shaders
#   MVK_CONFIG_USE_COMMAND_POOLING  reuses Metal command buffer objects instead of reallocating
export WINEMSYNC=1
export MVK_CONFIG_FAST_MATH_ENABLED=1
export MVK_CONFIG_USE_COMMAND_POOLING=1

export MVK_CONFIG_PREALLOCATE_DESCRIPTORS=1
export MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1
export DXVK_CONFIG_FILE='C:\HorizonXI\dxvk.conf'

export WINEDEBUG=-all
cd "$WINEPREFIX/drive_c/HorizonXI" || { echo "game dir missing"; exit 1; }
exec "$W/Contents/SharedSupport/wine/bin/wine" "C:\\HorizonXI\\Ashita-cli.exe" horizonxi.ini
