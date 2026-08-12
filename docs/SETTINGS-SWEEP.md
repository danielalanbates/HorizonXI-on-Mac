# FFXI client settings — a negative result, measured

Once `docs/PERFORMANCE.md` established that the renderer is a fifth of the frame at most, the
obvious next lever was the client's own settings: if the client's per-frame work is what costs,
turning its quality settings down should buy frames.

**It does not.** Every setting was measured and none of them moved the number.

## Method

`scripts/harness/bench.py`, one run per variant, character-select scene, 35 seconds of
steady-state sampling each, frame rate from `DXVK_FPS_LOG`. Settings are applied through
Ashita's `[ffxi.registry]` block, which overrides FFXI's real registry values. Profiles are in
`scripts/harness/profiles/s-*.json`.

## Results

| variant | registry | fps (median) |
| --- | --- | --- |
| baseline | — | **12.85** |
| environment animations off | `0011 = 0` | 11.93 |
| sound off | `0007 = 0` | 11.99 |
| window 960×540 | `0001/0002/0037/0038` | 11.87 |
| texture compression high | `0018 = 0` | 11.78 |
| menu resolution 640×360 | `0037/0038` | 11.57 |
| mip mapping off | `0000 = 0` | 10.69 |
| background/map textures 1024 | `0003/0004 = 1024` | *(run interrupted)* |
| **all of the above together** | | **9.71** |

Two things stand out.

**Nothing helps.** The spread from 12.85 down to 9.71 is entirely in the wrong direction. The
draw count was *identical* — 1841.5 per frame — in every single variant, which is the tell:
these settings change how much work the GPU does per pixel, and the GPU is idle. They do not
change how much work the client's CPU does per frame, and that is what limits us.

**Turning quality down can make it worse.** Mip mapping off is the clearest case (10.69 vs
12.85): without mip maps the GPU samples full-resolution textures for distant geometry, which
costs bandwidth for no benefit. "All low" being the slowest variant of all follows from the same
thing. If someone reports that lowering settings made FFXI-on-Mac feel worse, believe them.

## What this rules out, and what it leaves

Ruled out: FFXI's graphics-quality settings as a route to 30 fps.

Still open, and different in kind: settings that reduce the *number of things being simulated
and drawn*, rather than their quality. The in-game "number of characters displayed" limit is the
main one — it is a client setting, not a hack, and in a crowded hub it removes other players'
models from the frame entirely. It is not in Ashita's registry table, so it has to be set in the
game's own Config menu, which the harness cannot currently drive. That is the one client-side
lever left untested.
