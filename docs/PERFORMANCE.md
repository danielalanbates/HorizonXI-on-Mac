# Where the frame time actually goes

Written 2026-08-11. This document replaces the performance model in `FINDINGS.md` and
`BATCHING.md`. Those two described a renderer-bound game and proposed a draw-call batcher as the
route to 30 fps. **That model was wrong**, and the measurements below say why. Read this before
acting on anything in the older documents.

**2026-09-03 update:** the settled-frame analysis below is still valid, but it did not explain the
multi-minute crawl whenever a scene loaded. That was a separate DXVK 1.10.3 bug on MoltenVK.
FFXI first-touched the initial mapped `DrawPrimitiveUP` arena in 80-byte and 112-byte pieces, one
VM page at a time. `dxvk-1.10.3-up-buffer-prefault.patch` clears the 1 MiB arena up front and keeps
one cleared replacement ready. Stable 50 fps on the same cold rules screen moved from 123.1 to
32.4 seconds, and the only mid-frame rollover allocation disappeared. See the 2026-09-03 section
of `X87-WALL.md` for the controlled runs.

Everything here is measured on an M1 MacBook Pro (8 GB), macOS 26.5.2, at the character-select
scene unless stated otherwise. The instrumentation is in `patches/dxvk-1.10.3-horizonxi.patch`
(and `patches/d3d8to9_probe.hpp` for the layer above); the harness is `scripts/harness/bench.py`.

---

## The short version

| where the time goes | share of the frame |
| --- | --- |
| **FFXI's own code** | **~75%+** |
| DXVK's D3D9 state-setting entry points | ~6% |
| DXVK's draw submission | ~3% |
| `Present` — DXVK, MoltenVK, Metal, the GPU handoff | ~12% |
| d3d8to9 | ~6% (measured separately, on the rules screen) |
| Ashita's D3D8 proxy | not measurable as a cost — removing it makes the game *slower* |

**Skipping every single draw call — rendering literally nothing — moves character select from
12.0 fps to 10.7 fps.** It does not get faster. That one number settles the argument: the
translation stack is not what is costing the frame.

The frame rate is limited by how fast a 2002 32-bit x86 game engine runs under Rosetta, plus the
per-call overhead of the wrapper chain it is calling through. Neither is fixable by optimising
DXVK, MoltenVK, or the batching of draws.

**In the world it is worse, and for a different reason.** Standing still in a Mog House — one of
the lightest scenes in the game, ~850 draws — the client runs at **7.5 fps while using 13% of
one CPU core**, stalling ~120 ms per frame with the renderer idle. That is not slowness, it is
waiting, and it is the single biggest thing left to find. It has its own document:
**`docs/INWORLD-STALL.md`**, written as a bug report with everything already ruled out.

---

## How this was measured

Four probes were added to our DXVK build, each behind an environment variable so they cost
nothing when off:

| variable | what it records |
| --- | --- |
| `DXVK_FPS_LOG` | per second: fps, and per-frame draws / render passes / barriers / submits |
| `DXVK_PRESENT_PROBE` | per second: fps, ms spent **inside** `Present`, ms spent **outside** it |
| `DXVK_DRAW_PROBE` | per second: draw count, ms inside draws, ms inside D3D9 setters, and a histogram of every D3D9 API call by kind |
| `DXVK_SKIP_DRAWS` | isolation switch: accept draws and discard them |

`DXVK_FPS_LOG` matters on its own: it means the frame rate no longer has to be read off an
on-screen overlay, so every configuration is measured with the same instrument, headlessly, from
a script.

## What the probes said

**1. Present is cheap; the game is not.** At the rules-of-conduct screen — a static 2D dialog
with 380 draws — `Present` takes **0.04 ms** and the time between presents is pinned at
**37–40 ms**. At character select `Present` costs ~10 ms and the outside time is ~70 ms.

**2. Draws are cheap.** ~11,000 draws/second cost **19 ms of each second** inside DXVK. That is
**1.9 µs per draw** and under 2% of wall-clock time. DXVK's D3D9 layer is not slow.

**3. The API call volume is enormous.** Per second, at ~12 fps:

```
SetRenderState          140,000      SetStreamSource      12,574
SetVertexDeclaration     19,314      draws                12,250
SetTransform             16,876      SetFVF                9,639
SetSamplerState          15,886      SetVertexShader       9,675
SetTexture               15,850      SetTextureStageState 10,255
```

**~265,000 D3D9 calls per second — about 12,000 per frame, of which only ~560 are draws.**
FFXI issues roughly eleven `SetRenderState` calls per draw. Every one crosses FFXI → Ashita's
D3D8 proxy → d3d8to9 → DXVK. Only ~0.22 µs of the per-call cost is inside DXVK — but the two
layers above it were subsequently measured too, and they are not the answer either: d3d8to9 is
6% of the frame, and removing Ashita entirely makes the game *slower*. The volume is real; the
cost of carrying it is in the client.

**4. Removing the renderer changes nothing.** `DXVK_SKIP_DRAWS=1` at character select:
**10.7 fps**, versus 12.0 fps with the renderer doing its full job.

**5. Nothing ever exceeded 30 fps** — until the frame divisor was patched (below). Every
measurement in this project's history sits under 30. That is the client's own limiter.

---

## The frame limiter, and the one real win

FFXI limits itself to 60/n frames per second, where n is a divisor the client keeps in memory —
n = 2 (30 fps) by default. Under wine the limiter overshoots: at the static rules screen the
client is only **52% busy** yet still spends 38 ms per frame, well past the 33.3 ms the 30 fps
cap asks for.

Our `d3d9.dll` can now patch that divisor at start-up with `FFXI_FPS_DIVISOR=<n>`, using the same
signature scan and pointer walk as Ashita's own `fps` addon (done in the DLL because Ashita's
plugin host does not load in this install — see below). With `FFXI_FPS_DIVISOR=1` the client
was measured at **33.6 fps**, the first time this project has ever seen a frame above 30.

This does not help heavy scenes, which are nowhere near the cap. It helps exactly where the
client was holding itself back, which is normal play in ordinary zones.

60 fps mode is a setting the retail client supports; this is not a modification to game logic.

---

## Corrections to earlier conclusions

**Draw-call batching will not deliver 30 fps.** `BATCHING.md` measured a 9.9× instancing ratio
and concluded that collapsing 1,891 draws into ~191 would clear the bar. The premise was that
draw submission is what costs the frame. It is 3%. Even a perfect batcher that removed every
draw call would gain about what `DXVK_SKIP_DRAWS` gains, which is nothing. The
`DXVK_FF_INSTANCING` groundwork is left in place and left off; it is not the route.

**Render-pass churn is not the problem either.** FFXI spills DXVK's render pass ~59 times per
frame, 88% of those from `updateFramebuffer`, and the cause is real: the game detaches and
reattaches the depth-stencil ~24,000 times per run as it toggles `ZENABLE`/`ZWRITEENABLE`
between world geometry and UI. Keeping the depth attachment bound (`DXVK_KEEP_DEPTH=1`) is the
correct fix and it does remove those framebuffer changes — but at ~700 render passes per second
the whole phenomenon is worth under 2% of a frame, and keeping the attachment bound adds depth
load/store work that made the measured frame rate slightly *worse* (11.6 vs 12.9 fps). It is off
by default. A red herring, found and priced out.

**The Ashita overlay addons were never running.** `HANDOFF.md` §4 called disabling them "the
most promising thing left". They cannot be disabled because they never load: Ashita.dll in this
install reports interface version **4.16** while every bundled plugin — `Addons`, `Nameplate`,
`PacketFlow`, `Screenshot`, `Sequencer`, `Thirdparty` — is built against **4.15**, so
`PluginManager::Load` rejects all of them, and with the `Addons` host rejected no Lua addon
loads either. Every performance number this project has ever taken was already addon-free.
(This is also a real bug in Daniel's install worth fixing for gameplay reasons: none of his 22
addons work.)

**Rosetta really is structural, and nothing in the wrapper escapes it.** `libd3dshared.dylib`,
`D3DMetal.framework`, `winemetal.so`, `libMoltenVK.dylib` and `wine` itself are all x86_64-only
in this wrapper — checked with `lipo -archs`. There is no native arm64 component anywhere in the
graphics path, so no part of the translation runs outside Rosetta.

---

## The loading stall, 2026-09-03

Everything above is about the settled frame. The remaining complaint is different: whenever a
scene or its models load, the client sits at well under 1 FPS for ten to sixteen seconds and
then recovers to the mid-fifties. Measured on the bounded menu run (`scripts/harness/menu-run.py`)
with production DXVK and x87sidecar `4e9c738`:

| window | seconds | min FPS | faults/s | kernel share | footprint |
|---|---|---|---|---|---|
| boot to rules screen | 10 | 0.04 | 33,700 | 0.88 | +39 MB |
| rules to main menu | 16 | 0.21 | 30,000 | 0.87 | +15 MB |
| recovered baseline | | 55 | 3,900 | 0.15 | flat |

What the stall is not, each ruled out with a measurement rather than an argument:

* **Not x87.** The complete block-execution profile of the game process shows 3.45 billion ARM
  instructions of translated x87 work across the whole 130-second run, against 4 to 5 billion
  instructions per second during the stall. The hottest block is 4.6% of x87 emit, the IR path
  handles 84% of ops, gate refusals are 0.01 to 0.03 per thousand ops, and only `f2xm1` is
  ever forwarded to stock Rosetta. FMA contraction changed nothing and is unsafe anyway.
* **Not disk.** Reads and page-ins are near zero inside the stall windows.
* **Not the GPU.** System GPU utilization stays under 20%.
* **Not DXVK pipeline compilation.** Three of nine slow samples overlap compiler activity.

What it is: the process spends about 88% of its CPU in the kernel, taking roughly 33,000 page
faults and 170,000 Mach traps per second, with 70,000 context switches per second, while user
instructions per second fall. Copy-on-write faults are zero, so these are first-touch faults on
fresh anonymous memory. The guest-PC sampler's stacks put the leaf in `ucrtbase.dll!memset`
under `Ashita.dll+0x1402a7` (24% of slow samples), `FFXiMain.dll+0x43f7f` (16%), and
`d3dx9_43.dll!D3DXCreateSprite` (8%), with `FFXiMain.dll` on 79% of slow stacks and
`d3d9.dll` on 72%. The Wine side of every fault is a Mach trap and a wakeup, which is where the
switch and trap counts come from.

So the stall was memory commit, but not because of how much was committed. The first
experiment, keeping DXVK's emptied memory chunks mapped across the transition, changed nothing.
The offline reproducer (`scripts/tools/d3d9-scene-bench.c`, driven by
`scripts/harness/fault-bench.py`) then showed the actual variable: the same allocation storm
costs 12 ms per frame in a process with DEP on and 2,260 ms per frame once a single module built
without `IMAGE_DLLCHARACTERISTICS_NX_COMPAT` has been loaded. FFXiMain.dll, FFXi.dll and
pol.exe are all such modules. Wine reacts to them by enabling execute on every page in the
process, Windows does not, and under Rosetta each first touch of a writable-and-executable page
adds a Mach round trip through the exception server to the ordinary page fault. That is the
5 Mach messages per fault and the 88% kernel share.

`patches/dxvk-1.10.3-enforce-nx.patch` sets `ProcessExecuteFlags` back to disable-permanent in
`Direct3DCreate9`, before any buffer exists. Two consecutive character-list runs on 2026-09-03:

| | before | after |
|---|---|---|
| seconds below 10 FPS | 24 | 1 |
| boot to rules screen | 41.7 s | 17.1 s |
| rules to main menu | 28 s | 10 s |
| main menu to character list | not reached in 36 s | 10 s |
| kernel share of CPU in the slow seconds | 0.88 | 0.19 |
| character-list settled FPS | n/a | 44 to 47 |

The one remaining slow second is window creation. Rendering is unchanged, and x87 acceleration
stays active with both cooperative handshakes. The proper home for this fix is Wine, keyed on
running under Rosetta, and it should be raised there.

## What is left that can move the number

Ranked by measured or expected value:

1. **`FFXI_FPS_DIVISOR=1`** — proven to allow >30 fps. Free.
2. **The client's own settings** — the dominant cost is the client's per-frame work, so the
   settings that reduce that work are the lever. Swept in `docs/SETTINGS-SWEEP.md`.
3. **Removing a wrapper hop.** 265,000 calls a second cross three proxies. dgVoodoo2 implements
   D3D8 directly on D3D11, which removes d3d8to9 entirely and lets DXMT (native Metal, no Vulkan
   and no MoltenVK) replace two more layers. Measured in `docs/PATHWAYS.md`.
4. ~~**Filtering redundant state in d3d8to9**~~ — d3d8to9 was subsequently built from source and
   instrumented: it is **6% of the frame**, so filtering inside it cannot pay. Recipe in
   `docs/D3D8TO9-BUILD.md`; one unverified observation there is that the mingw build measured
   ~15% faster than the shipped MSVC one, which is worth a proper A/B.

What will *not* move it: batching draws, instancing, MoltenVK tuning, render-pass merging,
different Vulkan settings. Those were the previous plan and they are all inside the 20%.

## In-world, 2026-09-03: where the settled frame goes

Measured on the local test server (`docs/LOCAL-TEST-SERVER.md`) with the `city` scenario in
`scripts/harness/addons/perfscene`: godmode, `/fps 0`, draw distance maxed, then Bastok
Markets and Bastok Mines, each held twenty seconds. Three runs, all unattended.

| scene | FPS | draws / frame | passes / frame | GPU idle / frame |
|---|---|---|---|---|
| Bastok Markets | 30 to 33 | 1,800 to 2,500 | 50 | most of it |
| Bastok Mines | 51 to 64 | 2,300 to 3,000 | 4 | 12.8 of 15.7 ms |

The GPU is waiting on the CPU, and two threads are co-limiting: the game thread (draw
submission through Ashita, d3d8to9 and DXVK's D3D9 front end) and DXVK's command-stream thread
(Vulkan encode through MoltenVK to Metal). Each runs at 0.7 to 0.8 of a core in the Mines.
End-to-end cost is about 6.7 µs per draw; Markets is slower because it renders 50 passes per
frame against 4, and per-pass cost dominates.

Two experiments, neither a win:

- **Removing HorizonXI's addon set** (only `fps`, `drawdistance`, `perfscene`) took the Mines
  from 51 to 64 FPS, but the draw count also dropped by a fifth, so the per-draw cost was
  unchanged. `Addons.dll` is 22% of the game thread's guest samples in the full configuration;
  which addon is hot is answerable from those offsets and worth a separate pass.
- **DXVK built with llvm-mingw Clang 23** instead of Homebrew's i686 gcc. The gcc build uses
  SjLj exceptions and winpthreads TLS, which put `_Unwind_SjLj_Register`, `pthread_setspecific`
  and spinlocks at half of DXVK's guest samples. Clang's DWARF build removes them (the cross
  file is `scripts/harness/dxvk-cross-llvm-mingw.txt`, one include fix in
  `patches/dxvk-1.10.3-clang-include.patch`), but draws per second were identical in the game.
  That overhead was visible in samples on a thread that was not the limiting one. The gcc build
  stays vendored.

Next levers, in order: pin the scenario camera so draw counts stop varying between runs; the
MoltenVK encode side (`MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS` is set on the Vulkan pathway
but not on Metal); and the `field` scenario with spawned mobs and weather for a heavier,
reproducible load.
