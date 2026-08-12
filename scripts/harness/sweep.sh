#!/bin/zsh
# Sweep FFXI's own client settings. Measurement showed the renderer is a fifth of the frame at
# most, so the lever that matters is how much work the client itself does. Each variant is one
# ~3 minute run at the character-select scene.
cd /Users/daniel/Games/hxi-workspace
run() { ./bench.py --tag "$1" --profile "profiles/$1.json" --sample 35 2>&1 | tail -1 }

for v in "$@"; do run "$v"; done
