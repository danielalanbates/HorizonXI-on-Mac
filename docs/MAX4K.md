# 4K at max settings — where the frames actually are

Updated 2026-08-14. Everything here is measured on the **local LandSandBoat server**, standing in
the same spot in Southern San d'Oria, 40-second samples, with x87sidecar attached and
`FFXI_FPS_DIVISOR=1`. Profile: `profiles/lsb-max4k.json`. Reproduce with:

    python3 inworld.py --tag <name> --boot lsb.ini --profile profiles/lsb-max4k.json --sample 40

## The number

**The 30 fps target is NOT met, and the entry below claiming it was is retracted.** The 46.8 fps
figure came from a change that breaks the game: see "Why the fast number is not real". The honest
number at 4K max is **~24 fps**.

4K, every FFXI graphics setting at maximum:

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
standing in the square both move it.

**The flag is off by default.** It doubles the frame rate and breaks the game.

## Why the fast number is not real

Daniel found it in about a minute of play: NPCs blink in and out of existence roughly once a
second. `blinkprobe.py` takes a burst of frames 0.25 s apart in a static scene and diffs
consecutive ones:

| build | median | p90 | max | spikes (>3× median) |
| --- | --- | --- | --- | --- |
| `D3D9_RT_READBACK_NOWAIT=32` | 0.023 | 0.493 | 0.512 | **17 of 39** |
| unmodified | 0.021 | 0.023 | 0.026 | 0 of 39 |

The cause is exactly what "skip the wait" means: the GPU is still writing the buffer the game
then reads, so the visibility test gets a half-written answer and the thing it controls is culled
at random.

**The read-back is not a lens flare.** It decides whether *entities render at all*. A second
attempt (`ReadbackShadow` in `d3d9_device.cpp`) kept a CPU copy of the last completed read-back
and served that instead of the in-flight buffer, which does remove the flicker — by removing the
NPCs. Standing in the same spot in Southern San d'Oria:

- unmodified, 24.4 fps: Shard of Sunlight, Varchet and ellouine all present and stable
- shadow read-back, 53.8 fps: **the plaza is empty**, no flicker because nothing is drawn

A stale or zeroed visibility result reads as "not visible", so every entity it governs
disappears. Feeding the game anything other than the true, completed read-back breaks it. The
shadow code is left in place behind the same off-by-default flag, because the measurement is
worth keeping, but it is not a fix and must not be shipped on.

**What would actually work** is making the wait cheap rather than skipping it: the 26 ms is spent
waiting for a whole frame of queued GPU work to drain before the copy lands. Issuing the
read-back copy at the top of the frame, or on its own queue, would let it complete before the
game asks — exact, not approximate. That is the next thing to try.

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
surface still gets refreshed. With it on, all three stall counters read exactly `0.00` — and the
game breaks, for the reasons above. It stays as a measurement tool, not a setting to turn on.

## Scheduling the read-back earlier: no demonstrated gain

Tried 2026-08-14, because the previous entry named it as the thing that would work. It does not,
or at least it cannot be shown to on this machine.

`D3D9_RT_READBACK_EARLY=<max edge in px>` records the image->buffer copy in `SetRenderTarget`,
when the game stops drawing to the small surface, instead of at `Lock`. `Flush()` follows it
(`D3D9_RT_READBACK_EARLY_FLUSH=0` separates the two effects), so the copy is submitted with a
whole frame left to complete rather than sitting in the batch that Present flushes. Nothing about
what the game reads changes: the wait still happens and the data is still this frame's, complete.

**Three runs each, same build, flag off vs on:**

| | runs (fps median, 40 s in-world) | median |
| --- | --- | --- |
| flag off | 20.52, 27.30, 23.15 | 23.15 |
| flag on | 25.38, 26.63, 27.26 | 26.63 |

The medians differ by 3.5 fps and **the ranges overlap almost completely** -- the best baseline run
beats every flagged run. n=3, and the baseline spread alone is 6.8 fps. There is no effect here
worth claiming. The flag stays off by default and stays in the tree as a measurement, not a fix.
A first pair of runs looked like +2 fps; that was one run each, and it did not survive repeats.

**The first two attempts at this measured nothing at all,** which is the part worth remembering.
The early path was gated on "the game has locked this subresource before", which never becomes
true: instrumentation (`Logger::err` counters on both the lock and the unbind) showed
`candidate=0` after 6,500 locks of a 16x16 render target. FFXI creates a **fresh** render target
for each visibility test, so a per-object flag can never be set in time. Gating on the shape
alone -- `D3DPOOL_DEFAULT`, `D3DUSAGE_RENDERTARGET`, at most 32 px a side -- makes it fire ~8,000
times a run. Two builds were benchmarked and written up before that was checked. **A frame rate
that did not move and an optimisation that never ran are indistinguishable from the outside; add
the counter first.**

With it firing, the block inside `Map` falls from 28.6 ms to 26.7 ms. That is the real result: the
client is not waiting for the 1 KiB copy, it is waiting for the GPU to finish the draws that
produce the surface, and no amount of scheduling moves that. Reaching 30 fps needs the visibility
test to stop serialising the frame, not to be scheduled better.

## Dead ends, so they are not retried

- **MoltenVK command-buffer prefill** — 22.30 fps against a 24.88 baseline. Worse. (An earlier
  session's 58 fps figure for this was character select, not the world.)
- **Early buffer copies** (`DXVK_EARLY_BUFFER_COPY=1`, our patch) — 21.84. Worse.
- **Render-pass spills** — 604,924 in a 40 s run, dominated by `copyBuffer`, ~250 breaks against
  2440 draws. It looks like the answer and is not: removing them costs frames. Symptom, not cause.
- **Disabling vsync** — +0.6 fps. Noise.

The pattern across all four: this frame was never limited by renderer work, so removing renderer
work never helped. It is limited by one blocking read-back — which is real, and load-bearing, and
cannot simply be skipped.

## Harness notes

Two bugs in `bench.py` aborted every 4K run before this work was possible, both fixed:

- `game_is_frontmost()` asked `NSWorkspace.frontmostApplication()`, which in a detached harness
  process is frozen at whatever was frontmost when the process started. It asks System Events now.
- `click_to_focus()` clicked the title bar; at 4K the window frame starts at `x = -1, y = 30`, so
  that click landed on the menu bar and focused Finder. It falls back to the middle of the window.

A locked screen (`frontmost=loginwindow`) still stops a run dead and always will.

`DXVK_DRAW_PROBE` crashes the client at 4K with the sidecar attached. `DXVK_STALL_LOG` was written
to be cheap enough not to (two clock reads per instrumented call, no allocation) and does not.
