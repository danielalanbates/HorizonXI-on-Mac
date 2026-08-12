# The in-world stall — the open problem

This is the biggest unsolved thing in the project and the one worth picking up first. It is
written as a bug report rather than a narrative, so the next person can test a hypothesis
against the evidence instead of spending an hour rediscovering it.

## Symptom

In the world — standing still in a Mog House in Southern San d'Oria, about the lightest scene
the game has — the client runs at **7.5 fps**.

```
in-world, Mog House          7.5 fps    ~850 draws/frame
character select            12.9 fps   ~1841 draws/frame
rules-of-conduct screen     23.8 fps    ~380 draws/frame
```

Fewer draws, worse frame rate. Draw count is not what is driving this.

## What the probes say

From `DXVK_PRESENT_PROBE` and `DXVK_DRAW_PROBE` (see `docs/PERFORMANCE.md`), in-world, per
second of wall clock:

```
time inside Present()                    0.05 ms per frame  (nothing)
time inside all D3D9 draw calls          2 ms/s             (nothing)
time inside all D3D9 state setters      38 ms/s             (nothing)
pauses > 100 us, before SetTexture     843 ms/s over 7 pauses  <-- 84% of wall clock
```

**Seven pauses per second, ~120 ms each — one per frame.** They sit between the last D3D9 call
of one frame and the first of the next, the interval that contains `Present` and everything the
client does between frames. `Present` itself is 0.05 ms of it.

The same shape exists in the menus, smaller: the rules screen — a static 2D dialog — spends a
rock-steady 37–40 ms per frame outside our entry points.

## Which layer it is: measured, not guessed

Every layer in the chain has now been instrumented and priced. On the rules screen at 27.5 fps:

| layer | cost |
| --- | --- |
| DXVK (draws + state setters + Present) | ~20% of a frame in menus, ~5% in-world |
| **d3d8to9** | **61 ms/s — 6%** |
| **FFXI itself, plus Ashita's proxy** | **938 ms/s — 94%** |

d3d8to9 was built from source (crosire/d3d8to9, BSD 3-Clause) as a 32-bit mingw cross-build and
instrumented exactly like DXVK — time inside every entry point, a histogram of the gaps between
them, and long pauses attributed to the call that follows. Recipe and probe source:
`docs/D3D8TO9-BUILD.md`. Its verdict:

```
inside d3d8to9 entry points                        61 ms/s
above d3d8to9 (FFXI + Ashita)                     938 ms/s
   of which, 81 pauses/second longer than 1 ms    852 ms/s
      84 pauses/s of ~6.6 ms  -> before SetRenderState   (~3 per frame, mid-frame)
      27 pauses/s of ~11.3 ms -> before SetTransform     (one per frame, right after Present)
```

And Ashita is not it either. A no-Ashita run finally works (see below) and is **slower**:
**23.45 fps without Ashita against 27.48 fps with it**, same scene. Removing the proxy did not
help. *Caveat:* without Ashita the `[ffxi.registry]` overrides do not apply, so the client runs
on its own registry settings — not a perfectly controlled comparison. But nothing here is 2–4×
faster, and 2–4× is what is needed.

**Conclusion: the time is inside FFXI's own code**, in roughly four multi-millisecond chunks per
frame, one of them immediately after `Present` — on a static dialog box.

## The contradiction to resolve first

Two observations do not fit together:

- the pauses look like **chunks of computation** (4 per frame, milliseconds each), and
- in-world the process sits at **13% of one CPU core** (`top -pid`), which says it is idle.

One of those is being misread. `sample` on the game thread showed most of its samples at two
adjacent addresses inside FFXiMain.dll's 32-bit range, which reads like a tight loop — but
`sample`'s stack unwinding is broken through Rosetta and its per-thread counts could not be
trusted either.

**Settle it with per-thread CPU time, not percentages:** in-world, take `ps -M <pid>` twice
twenty seconds apart and diff the TIME column. If the game thread burned ~13 s of CPU in those
20 s it is computing and Rosetta is the wall; if it burned ~2 s it is waiting and there is a
wait to find. Everything else depends on that answer, and it costs one login.

## Ruled out, with evidence

Do not re-test these.

| hypothesis | test | result |
| --- | --- | --- |
| the renderer | `DXVK_SKIP_DRAWS=1` — discard every draw | *slower*, not faster |
| d3d8to9 | built from source and instrumented | 6% of the frame |
| Ashita's D3D8 proxy | no-Ashita run, same scene | slower without it (23.45 vs 27.48) |
| Ashita's overlay addons | they never load (interface 4.16 vs 4.15) | not running to begin with |
| vsync | `d3d9.presentInterval = 0`; DXVK already picks `VK_PRESENT_MODE_IMMEDIATE_KHR` | no change |
| swapchain drawable starvation | `d3d9.numBackBuffers = 3`, log confirms "Image count: 3" | no change (7.44) |
| FFXI's frame-rate cap | `FFXI_FPS_DIVISOR=1` (60 fps target) vs 2 | no change in-world (7.09 vs 7.48) |
| coarse Windows timer | `DXVK_TIMER_RESOLUTION=1`, log confirms it applied | no change (7.50) |
| audio | sound off, `0007 = 0` and `0035 = 0` | no change (7.03) |
| window focus / background throttle | focused, unfocused, refocused | no change (7.49 / 7.43 / 7.28) |
| memory pressure, swapping | `vm_stat` in play: 1330 pageins/s, only **3.2 swapins/s** | not swapping |
| the client polling for vblank | instrumented `GetRasterStatus` | **never called once** |
| wine's msync | `WINEMSYNC=0` in-world | slightly *worse* (6.83 vs 7.48) |
| graphics quality settings | full sweep, `docs/SETTINGS-SWEEP.md` | none help; several hurt |
| dgVoodoo2 instead of d3d8to9 | 2.87.3 `MS/x86/D3D8.dll`, on wine-d3d11 and DXVK-d3d11 | crashes instantly: `page fault on read access to 0x00000000 in wow64 32-bit code` |

## Still untested

1. **Network.** In-world is the only state with a live map-server connection, and the stall is
   in-world-sized only in-world. If the client's frame loop waits on a socket with a timeout and
   wine's socket wait is coarse, that is a per-frame stall that exists nowhere else.
   `WINEDEBUG=+winsock` for a few seconds would show it.
2. **`NtDelayExecution` granularity under this wine.** `timeBeginPeriod(1)` changes only the
   multimedia timer. A five-line Windows test program — sleep 1 ms in a loop, report real
   elapsed time — settles it in one run and needs no game at all.

## How to run the no-Ashita control

It works now, and it is the cleanest lever available:

```sh
# the client reads its own registry, not Ashita's [ffxi.registry] overrides, so it must be
# windowed or DXVK's fullscreen mode change fails and takes the client with it
#   HKCU\Software\PlayOnlineUS\SquareEnix\FinalFantasyXI  (and the Wow6432Node twin, in system.reg)
#   0001 = 1280   0002 = 720   0034 = 1 (windowed)   0037/0038 = 1280/720
wine 'C:\HorizonXI\bootloader\horizon-loader.exe' --server play.horizonxi.com --user … --pass …
```

Edit `user.reg`/`system.reg` directly with the client stopped rather than looping `wine reg add`
— each invocation spawns a wineserver and fourteen of them take five minutes.

## Why this matters more than anything else here

If the stall is removed, the client's real work in that Mog House is about 13 ms per frame —
**75 fps**. Every other optimisation in this repository is competing over the ~20% of a frame
the renderer occupies. This one is worth more than all of them together.
