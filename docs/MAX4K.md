# 4K at max settings — where the frames actually are

Updated 2026-08-14. Everything here is measured on the **local LandSandBoat server**, standing in
the same spot in Southern San d'Oria, 40-second samples, with x87sidecar attached and
`FFXI_FPS_DIVISOR=1`. Profile: `profiles/lsb-max4k.json`. Reproduce with:

    python3 inworld.py --tag <name> --boot lsb.ini --profile profiles/lsb-max4k.json --sample 40

## The number

**The 30 fps target is met.** 4K, every FFXI graphics setting at maximum:

| configuration | fps median | draws/frame |
| --- | --- | --- |
| baseline, run A | 24.88 | 2440 |
| baseline, run B (same session as the fix) | 18.59 | 2102 |
| `MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1` | 22.30 | 2100 |
| `DXVK_EARLY_BUFFER_COPY=1` | 21.84 | 2448 |
| `d3d9.presentInterval = 0` (no vsync) | 25.46 | 2406 |
| **`D3D9_RT_READBACK_NOWAIT=32`, run A** | **46.82** | 1824 |
| **`D3D9_RT_READBACK_NOWAIT=32`, run B** | **42.93** | 1876 |

Baseline varies by 6 fps between runs — in-game time of day and how many other characters are
standing in the square both move it — so the fix is quoted against both ends of that range. It is
roughly a **2× improvement** and it is reproducible.

It is on by default in the launcher (Settings → *Fast lens flares*), so the shipped `.app` runs at
these speeds.

## What the cost actually was

FFXI renders a **16×16 `D3DPOOL_DEFAULT` / `D3DUSAGE_RENDERTARGET`** surface and immediately locks
it to read the result back — a lens-flare / sun-visibility occlusion test. It does this about
**four times per frame**, ~100 times a second.

Each read-back has to wait for the GPU to reach that point, which drains the entire pipeline. A
probe added to `D3D9DeviceEx::WaitForResource` and `SynchronizeCsThread` (`DXVK_STALL_LOG=<path>`,
milliseconds blocked per frame) measured the baseline frame as:

    fps    map_wait_ms  map_wait_n  map_blocked_ms  map_blocked_n  sync_cs_ms  sync_cs_n
    24.9   28.8         4.0         25.8            4.0            3.0         8.0

**26 ms of a 40 ms frame with the client blocked, doing nothing, inside four lock calls.** That is
the whole gap between 25 fps and 50, and it explains every other measurement this project ever
took: a GPU at ~10% busy, two threads each at ~60–75% of a core with neither saturated, and a
frame rate that refused to move when renderer work was removed.

`D3D9_LOCKIMAGE_PROBE` confirms the attribution is total — every single stalling lock in a 40 s
sample is that same `16×16, pool 0, usage 0x1, format 21` surface, no other shape appears.

`D3D9_RT_READBACK_NOWAIT=<max edge in px>` skips **only the wait**, and only for
`D3DPOOL_DEFAULT` render targets no larger than that edge. The copy is still issued, so the
surface still gets refreshed; the game reads the *previous* frame's visibility factor instead of
this frame's. For a number driving how bright a lens flare is, one frame of lag is not observable.
With it on, all three stall counters read exactly `0.00`.

This is a semantic change to D3D9 behaviour, which is why it is bounded to small surfaces and
exposed as a toggle rather than made unconditional in DXVK.

## Dead ends, so they are not retried

- **MoltenVK command-buffer prefill** — 22.30 fps against a 24.88 baseline. Worse. (An earlier
  session's 58 fps figure for this was character select, not the world.)
- **Early buffer copies** (`DXVK_EARLY_BUFFER_COPY=1`, our patch) — 21.84. Worse.
- **Render-pass spills** — 604,924 in a 40 s run, dominated by `copyBuffer`, ~250 breaks against
  2440 draws. It looks like the answer and is not: removing them costs frames. Symptom, not cause.
- **Disabling vsync** — +0.6 fps. Noise.

The pattern across all four: this frame was never limited by renderer work, so removing renderer
work never helped. It was limited by one blocking read-back.

## Harness notes

Two bugs in `bench.py` aborted every 4K run before this work was possible, both fixed:

- `game_is_frontmost()` asked `NSWorkspace.frontmostApplication()`, which in a detached harness
  process is frozen at whatever was frontmost when the process started. It asks System Events now.
- `click_to_focus()` clicked the title bar; at 4K the window frame starts at `x = -1, y = 30`, so
  that click landed on the menu bar and focused Finder. It falls back to the middle of the window.

A locked screen (`frontmost=loginwindow`) still stops a run dead and always will.

`DXVK_DRAW_PROBE` crashes the client at 4K with the sidecar attached. `DXVK_STALL_LOG` was written
to be cheap enough not to (two clock reads per instrumented call, no allocation) and does not.
