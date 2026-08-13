# The x87 wall — found, and broken

Written 2026-08-12. This supersedes `docs/INWORLD-STALL.md`.

**FFXI's floating-point math ran ~100x slower than native on this machine. That was the whole
problem, and accelerating x87 fixes it: in-world, at maximum settings, 11.3 fps became 28.5.**

| in-world, max settings, ~2090 draws | fps | frame-thread CPU over 45 s |
| --- | --- | --- |
| baseline | 11.26 | 33.0 s |
| **+ [x87sidecar](https://github.com/athei/x87sidecar)** | **28.54** | **12.95 s** |

Nothing else in this repository moved the number by more than noise. The renderer was never the
constraint; the client's own arithmetic was, and it was running at roughly 1% of the machine's
floating-point speed.

## The measurement

Same source, same optimisation level, three targets. The workload is 20 million 4×4
matrix-by-vector transforms with a normalise — what character animation and geometry actually
cost. Source: `scripts/tools/x87real.c`.

| target | time | throughput |
| --- | --- | --- |
| native arm64 | 0.294 s | 68 Mverts/s |
| x86_64 under Rosetta (SSE) | 0.291 s | 69 Mverts/s |
| **x86-32 under this wine (x87)** | **34.084 s** | **1 Mverts/s** |

Rosetta running 64-bit SSE code is **not slow at all** — it matches native. The penalty is
specific to **x87**, the 1997-era floating-point stack that a 32-bit 2002 game uses for
everything.

A second benchmark isolates the two layers responsible (`scripts/tools/cpubench.c`):

| workload | native | x86_64/Rosetta | x86-32/wine |
| --- | --- | --- | --- |
| integer | 0.074 s | 0.013 s | 0.225 s |
| x87 long double | 0.126 s | 4.484 s | 3.969 s |
| SSE2 double | 0.125 s | 0.113 s | 5.174 s |

Reading it:

- **Rosetta's x87 emulation is ~36× slower than native** (0.126 → 4.484), and that is true even
  in a 64-bit process with no wine involved at all. This is Apple's translator, not wine.
- **wine's 32-bit layer multiplies it again**, to ~116× on the realistic benchmark.
- Integer code is only ~3× slower. It is *only* floating point.
- On 32-bit x86 the compiler emits x87 for plain `double` too, which is why the SSE2 row is slow
  in the wine column but fast under Rosetta.

The x87 precision-control word makes no difference — 24-bit, 53-bit and 64-bit precision all
measure 4.5 s (`scripts/tools/x87test.c`). That knob is closed; d3d9's documented
`SetupFPU` behaviour buys nothing here.

## Why this explains everything else

The client was measured burning a full CPU core on one thread in a city, at ~80 ms per frame,
with the renderer accounting for a small fraction of it. Every attempt to reduce renderer cost
landed within noise:

| change | result |
| --- | --- |
| skip every draw call (`DXVK_SKIP_DRAWS=1`) | slower, not faster |
| clamp short sleeps to a yield | no change (12.4 → 11.7) |
| halve queue submits (28.7 → 16.8 per frame) | no change |
| drop d3d8to9's blanket `D3DUSAGE_RENDERTARGET` | no change |
| redundant render-state filter in d3d8to9 | no change |
| window at 960 px wide instead of full size | no change (11.87 vs 11.9) |
| every graphics quality setting | no change; several hurt |

Resolution changing nothing rules out the GPU and fill rate. A renderer that can be removed
entirely without the frame rate improving is not the constraint. The constraint is the game's
own arithmetic, and it is running at roughly 1% of the machine's floating-point speed.

## What was ruled out along the way, corrected

Two earlier conclusions in this repository were wrong and are corrected here.

- **"The client is idle — 13% of one core."** That reading came from `ps -M`, whose first
  time-shaped column is *system* time, not user time. Summing both columns shows one thread at
  81–100% of a core. `GetThreadTimes` on the frame thread agrees: 1040 ms of user CPU per
  1058 ms of wall clock. The client is compute-bound, not waiting.
- **"~90% of the frame thread is in `NtDelayExecution`."** Produced by an in-process sampling
  profiler that suspends the frame thread to read its instruction pointer. Every DXVK-side
  measurement of the same thread — time in Present, in draws, in state setters, in
  `SyncFrameLatency`, in every hooked blocking API — says it does not wait. The suspend itself
  perturbs the thread. Do not trust that profile.

Sleep granularity is also fine (`Sleep(1)` = 1.26 ms) and the clocks are consistent
(QPC, `timeGetTime` and `GetTickCount` agree to 0.3% with 1 ms resolution), so the client's own
pacing is not misfiring.

## The engine hunt, settled

The obvious hope is that a different wine engine executes 32-bit code better. Both engines
present in the wrapper were measured on the identical benchmark:

| engine | 32-bit model | 20M transforms |
| --- | --- | --- |
| Sikarugir wine 10.0 (in use) | upstream new-wow64 | **34.08 s** |
| CrossOver-derived `wine32on64` (`wine.cx32bak`) | wine32on64 | **77.30 s** |
| native arm64, for scale | — | 0.29 s |

The engine already in use is the better of the two by 2.3×, so the older engine is not a
route forward. WineHQ 11.0 was measured in an earlier session at 4.7 fps against 25 on the same
scene, which is the same story again.

More importantly, the floor is not set by wine. The same transform in `long double`, compiled
for **x86_64 and run under Rosetta with no wine involved at all**, takes **71.08 s** against
0.52 s native. Apple's translator is itself two orders of magnitude slow on x87. Whatever engine
runs the game, it runs x86 through Rosetta, so it inherits that. There is no headroom for a
better engine to recover — the ceiling belongs to Rosetta, not to wine.

## x87sidecar, and the bug that hid the win for hours

[x87sidecar](https://github.com/athei/x87sidecar) (MIT) patches Rosetta's `translate_insn` so x87
opcodes are translated by a native ARM64 JIT in a separate process. On the benchmarks:

| benchmark | stock Rosetta | with x87sidecar |
| --- | --- | --- |
| x86_64 x87, no wine | 41.56 s | **0.371 s** |
| 32-bit Windows x87 through our wine | 34.08 s | **0.399 s (~85x)** |

It beats native arm64 (0.52 s), because the JIT works in double precision instead of emulating
80-bit. The float result is identical to the baseline.

**In the game it is worth 2.5x** — 11.26 to 28.54 fps in-world at max settings, with frame-thread
CPU falling from 33.0 s to 12.95 s over the same window.

That result took hours longer than it should have, because of one bug worth stating plainly:

- The sidecar patches **the process it is attached to**. Under Ashita the client runs in
  `horizon-loader.exe`, while `Ashita-cli.exe` is only the injector — and Ashita has the lower
  pid. Selecting "the first client pid" attaches to the injector, which does no rendering, and
  the result is a *silent* no-op: the hook installs successfully, logs success, and changes
  nothing. This produced a confident, fully-measured "x87 acceleration does not help FFXI"
  conclusion that was entirely wrong. Always confirm the attached pid is the one burning CPU.
- Wrapping the launcher (`x87sidecar wine Ashita-cli.exe`) fails the same way, for the same
  reason. Cooperative mode does not fix it either: the handshake covers only the process that
  performs it, so athei's prebuilt CrossOver-based wine also leaves children unhooked.
- Attaching to a running client needs an `--attach <pid>` mode, added in
  `patches/x87sidecar-attach-pid.patch`.

Two operational requirements. The target must be started with `ROSETTA_DISABLE_AOT=1` or Rosetta
never calls `translate_insn` and there is nothing to hook. And that makes start-up much slower —
every block JITs cold — so a harness that sleeps a fixed interval before driving the UI will find
a black screen. `scripts/inworld.py` now waits for the first rendered frame instead.

## What in-world still costs (open)

Before the x87 fix, in-world sat at 10-12 fps across ~60 runs of every configuration tried,
while character select ran 28-29 fps at a comparable draw count. The x87 fix closed that gap.
What remains is the submit count, which is still four times higher in-world:

```
character select   1841 draws   28.3 fps    59 passes    6.5 submits/frame
in-world, city     2200 draws   11.9 fps    51-79 passes  27.8 submits/frame
```

The distinguishing feature is not draw count -- it is that in-world issues **four times the queue
submits**. Every lever aimed at the client's own CPU (x87, sleeps, quality settings, resolution)
has now been measured, and none of them move in-world at all. That points away from the client's
arithmetic and towards the per-submit cost of the Metal path in the in-world scene specifically.
Halving submits (28.7 to 16.8) did not help *while x87 was still assumed to be the wall*; that
experiment is worth rerunning now, together with finding what forces ~28 submits per frame
in-world and only ~6 at character select.

## What reaching 30 fps would actually require

Nothing in DXVK, MoltenVK, d3d8to9 or the client's settings can move a 100× arithmetic penalty.
The only levers that touch it:

1. **A translator with fast x87.** This is the whole problem in one sentence: Apple's Rosetta
   emulates x87 slowly and offers no switch. box64/FEX-style translators have specific x87 fast
   paths (e.g. skipping 80-bit intermediate precision), but they translate Linux binaries and
   there is no working path for Windows-on-macOS through them today. Worth re-checking as
   Sikarugir/CrossOver/GPTk engines are updated — the benchmark here is three files and
   re-running it against a new engine takes a minute.
2. **Less floating-point work per frame.** Not available without patching the game's own code.
3. **Accepting the ceiling.** Scenes light on geometry already run better; the crowded city
   measured here is close to the worst case the game has.

Before trying anything else on this project, run `scripts/tools/x87real.c` against the engine in
question. If it does not beat 1 Mverts/s, the frame rate will not change, whatever else is done.
