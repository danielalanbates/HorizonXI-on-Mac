# The in-world stall — the open problem

This is the biggest unsolved thing in the project and the one worth picking up first. It is
written as a bug report rather than a narrative, because the next person should be able to test
a hypothesis against the evidence before spending an hour on it.

## Symptom

In the world — measured standing still in a Mog House in Southern San d'Oria, about the lightest
scene the game has — the client runs at **7.5 fps**, and it does so while using about
**13% of one CPU core**. It is not computing. It is waiting.

```
in-world, Mog House          7.5 fps   ~850 draws/frame
character select            12.9 fps   ~1841 draws/frame
rules-of-conduct screen     23.8 fps    ~380 draws/frame
```

Fewer draws, worse frame rate. Draw count is not what is driving this.

## What the probes say

From `DXVK_PRESENT_PROBE` and `DXVK_DRAW_PROBE` (see `docs/PERFORMANCE.md` for what they are),
in-world, per second of wall clock:

```
time inside Present()                    0.05 ms per frame  (nothing)
time inside all D3D9 draw calls          2 ms/s             (nothing)
time inside all D3D9 state setters      38 ms/s             (nothing)
pauses > 100 us, before SetTexture     843 ms/s over 7 pauses  <-- 84% of wall clock
```

**Seven pauses per second, ~120 ms each, one per frame.** They sit between the last D3D9 call of
one frame and the first D3D9 call of the next, which is the interval that contains `Present` and
everything the client does between frames. `Present` itself accounts for 0.05 ms of it.

The same phenomenon exists in the menus, smaller: the rules-of-conduct screen — a static 2D
dialog — spends a rock-steady 37–40 ms per frame outside our entry points, at 52% CPU.

## Ruled out, with evidence

Do not spend time re-testing these.

| hypothesis | test | result |
| --- | --- | --- |
| vsync | `d3d9.presentInterval = 0`; DXVK already picks `VK_PRESENT_MODE_IMMEDIATE_KHR` | no change |
| swapchain drawable starvation | `d3d9.numBackBuffers = 3`, confirmed "Image count: 3" in the log | no change (7.44) |
| the renderer | `DXVK_SKIP_DRAWS=1` — discard every draw | *slower*, not faster |
| FFXI's frame-rate cap | `FFXI_FPS_DIVISOR=1` (60 fps target) vs 2 | no change in-world (7.09 vs 7.48) |
| coarse Windows timer | `DXVK_TIMER_RESOLUTION=1` via `timeBeginPeriod`, confirmed applied in the log | no change (7.50) |
| audio | sound off, `0007 = 0` and `0035 = 0` | no change (7.03) |
| window focus / background throttle | measured focused, unfocused, refocused | no change (7.49 / 7.43 / 7.28) |
| memory pressure, swapping | `vm_stat` during play: 1330 pageins/s but only **3.2 swapins/s** | not swapping |
| the client polling for vblank | instrumented `GetRasterStatus` — logs every 5000 calls | **never called once** |
| wine's msync | `WINEMSYNC=0` in-world | slightly *worse* (6.83 vs 7.48) |
| Ashita's overlay addons | they do not load at all (interface 4.16 vs 4.15) | not running to begin with |
| graphics quality settings | full sweep, `docs/SETTINGS-SWEEP.md` | no setting helps; some hurt |

## The strongest lead: it is the texture path, and probably d3d8to9

Two facts point the same way, and they were not put together until the end of the session.

**One.** The stall is attributed to the call that follows it, and that call is almost always
`SetTexture` — 843 of the 915 ms/s of pause time.

**Two.** An earlier session measured all three renderer pathways in-zone and wrote the numbers
into this repo's README:

```
OpenGL (wined3d)          3.2 fps in-zone
wined3d Vulkan           20.6 fps in-zone   -- models and terrain came out UNTEXTURED
d3d8to9 + DXVK           29.1 fps           -- menus only; the world was black at the time
```

**wined3d-Vulkan reached 20.6 fps in-zone — with Ashita loaded, exactly as now.** That kills the
"Ashita's proxy is the cost" theory outright: Ashita was in the chain for that run too. And the
pathway that was fast is precisely the one that *was not uploading textures properly*.

So the suspect is FFXI's texture handling as it passes through **d3d8to9**, the one layer in the
chain that is ours and is not instrumented. A gap measured at DXVK's boundary "before
SetTexture" contains all of d3d8to9's work, so a slow texture path there is invisible to every
probe built this session and would look exactly like what we see.

**Next step:** build `d3d8to9` from source (crosire/d3d8to9, BSD 3-Clause) with the same timing
instrumentation used on DXVK — time inside each entry point, gap histogram between them. That
splits the 120 ms into "d3d8to9" and "FFXI itself" in one run and ends the guessing.

Replacing d3d8to9 with dgVoodoo2 was tried as a shortcut and **does not work**: dgVoodoo2 2.87.3
(`MS/x86/D3D8.dll`) crashes immediately under this wine, on both wine's builtin d3d11 and DXVK's
d3d11 — `page fault on read access to 0x00000000 in wow64 32-bit code`. Profiles kept at
`scripts/harness/profiles/dgvoodoo*.json` in case a later dgVoodoo build behaves.

## Also untested

1. **Network.** In-world is the only state with a live map-server connection. If the client's
   frame loop waits on a socket with a timeout, and wine's socket wait has coarse granularity,
   that is a per-frame stall that exists in the world and nowhere else. `WINEDEBUG=+winsock`
   for a few seconds would show it.

2. **A no-Ashita run**, now demoted by the wined3d evidence above but still a clean control. It
   is nearly working: launching `bootloader/horizon-loader.exe` directly logs in fine and
   creates a D3D device, but the client needs Ashita's `sandbox` POL plugin for path
   redirection (`[sandbox.paths]` in the boot ini). Setting
   `HKCU\Software\PlayOnlineUS\SquareEnix\FinalFantasyXI` to windowed 1280×720 (`0034 = 1`) got
   past the "Failed to change display mode" error and produced a window, but the client exited
   shortly after.

3. **A wine `Sleep`/timer path.** `timeBeginPeriod(1)` did not help, but that only changes the
   multimedia timer. `NtDelayExecution` granularity under this wine on macOS has not been
   measured directly. A five-line Windows test program run under the same wine — sleep 1 ms in a
   loop, report the real elapsed time — would settle it in one run and needs no game at all.

## Why this matters more than anything else in the project

If the stall is removed, the client's actual work in that Mog House is about 13 ms per frame.
That is **75 fps**. Every other optimisation in this repository is competing for the remaining
~20% of a frame that the renderer occupies. This one is worth 10× more than all of them
together, and unlike Rosetta it is not obviously structural.
