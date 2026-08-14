# 4K at max settings — where the frames actually are

Written 2026-08-13. Everything here is measured on the **local LandSandBoat server**, in the
same spot, 40-second samples, with x87sidecar attached and `FFXI_FPS_DIVISOR=1`. Profile:
`profiles/lsb-max4k.json`. Reproduce with:

    python3 inworld.py --tag <name> --boot lsb.ini --profile profiles/lsb-max4k.json --sample 40

## The number

| configuration | fps median | draws/frame | render passes/frame |
| --- | --- | --- | --- |
| **4K max, baseline** | **24.88** | 2440 | 259 |
| + `d3d9.presentInterval = 0` (no vsync) | 25.46 | 2406 | 259 |
| + early buffer copies (`DXVK_EARLY_BUFFER_COPY=1`) | **21.84** | 2448 | 263 |

30 fps needs another ~21% over baseline. Nothing tried in this session got it.

## What the render-pass probe says, and why it did not help

`DXVK_PASS_PROBE` attributes every render-pass break. Over one 40 s run in this scene:

    604,924 render-pass spills
    dominated by copyBuffer, then copyBufferToImage

That is more pass breaks per frame than there are draws — roughly 250 breaks against 2440 draws,
each one ending and restarting a Metal render command encoder. It looks exactly like the
explanation for a GPU sitting at ~3 ms of work inside a 40 ms frame.

It is not. DXVK only avoids the spill when a copy replaces a *whole* buffer of at most 256 KB
(`tryInvalidateDeviceLocalBuffer`); FFXI uploads partial dirty ranges of larger buffers, so it
always missed and always spilled. `DXVK_EARLY_BUFFER_COPY=1` (added to
`src/dxvk/dxvk_context.cpp`) moves those copies to the init command buffer whenever the barrier
set shows neither slice has a recorded access, which is safe by the same reasoning the existing
discard path uses — and it made the frame rate **worse**, 24.88 → 21.84.

So the spills are a symptom, not the cost. This is the third time this project has removed
renderer work and found the frame rate unchanged or worse (`DXVK_SKIP_DRAWS=1` was the first,
halving queue submits the second). **The flag is off by default and should stay off.**

## Where the time is

CPU over a 40 s window, from `ps -M` (both time columns summed):

    thread 13   30.1 s      ~75% of a core
    thread 11   23.5 s      ~59% of a core
    thread 2    10.0 s

Two busy threads — the client's frame thread and DXVK's CS thread — neither saturated. That is
not a "one thread is pinned" profile; it is a serialisation profile, where each side waits on the
other. Confirming that is the next measurement, and it needs a lighter instrument than
`DXVK_DRAW_PROBE`, which **crashes the client** at 4K with the sidecar attached (a "Program
Error" window, headers written to the log and nothing else).

## Open leads, in the order worth trying

1. **MoltenVK command-buffer prefill** (`MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1`). Untested:
   the one run attempted came back at 58 fps with 380 draws/frame, which is character select, not
   the world — an invalid comparison, not a result. Rerun and confirm draws ≈ 2400 before
   believing any number from it.
2. **Whether the two busy threads are serialising.** If they are, a deeper CS chunk queue is worth
   more than anything renderer-side.
3. `d3d8to9`, priced at 6% in an earlier session, is still the only layer in the chain that is
   ours and uninstrumented.

## Harness fixes needed to get any of this measured

Two bugs in `bench.py` aborted every 4K run before this session's numbers existed:

- `game_is_frontmost()` asked `NSWorkspace.frontmostApplication()`. In a detached harness process
  that value is whatever was frontmost when the process started — Finder — and it never updates,
  so runs aborted with `frontmost=Finder` while the game demonstrably had focus. It asks System
  Events now.
- `click_to_focus()` clicked the title bar. At 4K the window fills the display and its frame
  starts at `x = -1, y = 30`, which puts that click on the menu bar or the desktop, focusing
  Finder. It falls back to the middle of the window now.

A locked screen (`frontmost=loginwindow`) still stops a run dead, and always will — the harness
must be able to focus the game to drive it.
