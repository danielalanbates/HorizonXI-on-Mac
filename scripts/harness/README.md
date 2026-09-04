# Benchmark harness

The point of this directory is that a frame-rate claim in this project should be reproducible by
running one command, not by squinting at an overlay. Every number in `docs/PERFORMANCE.md` and
`docs/SETTINGS-SWEEP.md` came out of `bench.py`.

These scripts drive Daniel's install directly (paths are hard-coded at the top of `bench.py`);
they are checked in as a record of how the measurements were taken and as a starting point, not
as a general-purpose tool.

## Bounded menu run

`menu-run.py` drives one launch to the top-level menu with the rules-screen Return and nothing
else, so it can run unattended without ever reaching the character list:

```sh
scripts/harness/menu-run.py --x87-profile \
  --profile-analyzer /path/to/x87sidecar/build/bin/profile_analyze
```

It refuses to start while any launcher, Wine, sidecar, or game process is alive, or while launchd
still carries a diagnostic variable from an earlier experiment. It arms `capture-performance.py`,
launches the app exactly as the Play button does, waits for the rules screen by watching the
DXVK frame log, screenshots the game window, sends one Return through the compiled
`game-window` helper, waits for the main menu, screenshots again, holds, and stops. The helper
clicks the title bar and refuses to post the key unless the game is frontmost. A second Return
is a hard error in the driver, not a configuration.

Cleanup is two-phase. The game process this run launched gets `SIGTERM` first and the driver
waits up to eight seconds for its sidecar to see the exit and append the block-profile counter
section. Only then does the broad sweep terminate, kill, and check every related process name.
If a game process the driver did not launch is alive at cleanup time, a person is at the
keyboard and the driver skips cleanup entirely rather than end their session; it once killed a
hand-driven character creation this way. The run ends
with `menu-run.json` in the capture directory: phase times, the game PID, screenshots, every
launchd variable it set and cleared, the leftover process check, and whether the block profile
is complete.

One-launch diagnostic overrides go through `--env NAME=value`, repeatable. Only `X87_`, `DXVK_`,
`D3D9_`, `MVK_`, and `FFXI_ON_MAC_` names are accepted, they are set with `launchctl setenv`
just before the launch, and they are removed on every exit path. `--x87-profile` sets
`X87_PROFILE` to `x87-block-%p.prof` inside the capture directory and, when an analyzer path is
given, writes `x87-block-analysis.txt` from the complete game profile. `--no-return` stops at the
rules screen for a pure boot measurement. Total wall time is bounded by `--limit`, 180 seconds by
default.

## Offline fault benchmark

`fault-bench.py` runs a Windows benchmark under the installed Wine runtime, without the x87
sidecar, and counts its page faults, copy-on-write faults, Mach traps and kernel time per
quarter second. It stops every Wine process afterwards. `scripts/tools/d3d9-scene-bench.c`
reproduces the game's scene-load traffic: thousands of draws per frame under distinct world
transforms, plus a batch of freshly created and initialised index buffers per frame. Its fifth
argument runs steps before the device exists: `load-nonx` loads a DLL built without the
NX-compatible flag, `nx-on` and `nx-on-permanent` set `ProcessExecuteFlags`, `query` prints
them. This is how the loading stall was isolated to Wine's execute-everywhere response:

```sh
i686-w64-mingw32-gcc -O2 -o /tmp/bench/d3d9-scene-bench.exe scripts/tools/d3d9-scene-bench.c -ld3d9 -lgdi32
cp vendor/dxvk-1.10.3-x32-d3d9-horizonxi.dll /tmp/bench/d3d9.dll
scripts/harness/fault-bench.py /tmp/bench d3d9-scene-bench.exe 12 3000 64 65536 load-nonx
scripts/harness/fault-bench.py --env DXVK_ENFORCE_NX=0 /tmp/bench d3d9-scene-bench.exe 12 3000 64 65536 load-nonx
```

## Capture one real launch

`capture-performance.py` records a launch from the installed Mac app without pressing keys or
rebuilding the command that logs into the server:

```sh
scripts/harness/capture-performance.py \
  --game-dir "$HOME/Games/FFXI/HorizonXI"
```

Start the recorder first, press Play normally, then move through the slow screens and into the
problem scene. If the recorder has a terminal, type labels such as `terms`, `character select`,
or `city loaded` and press Return. Labels are timestamped without sending input to the game.
The recorder stops when the game exits, with a 15-minute safety limit. Use `--duration` to change
that limit.

The recorder arms a one-shot request in Application Support. The launcher consumes it on the
next matching launch and gives the DXVK probes unique output paths. Later launches return to
normal automatically. A request expires if Play is not pressed within ten minutes.

The standard capture includes:

- frame rate, draw count, render passes, queue submissions, GPU idle time, GPU sync time,
  asynchronous compiler activity, and live pipeline counts;
- time inside and outside `Present`, DXVK map/CS stalls, Windows wait calls, texture-lock shapes,
  flushes, queue-retirement timing, and once-per-second frame, submit, and in-flight
  `DrawPrimitiveUP` phase watchdogs;
- per-second process CPU, physical footprint, page-ins, instructions, cycles, wakeups, and
  per-process disk bytes from `proc_pid_rusage`, plus page faults, copy-on-write faults, Mach and
  BSD syscall counts, context switches, thread count, and the task user/kernel clock from
  `proc_pidinfo`. `timeline.csv` turns these into per-second rates and a kernel share, and the
  summary contrasts the slow seconds with the recovered seconds so a stall reads as page-fault
  bound, syscall bound, idle, or user-mode work without a second run. Consecutive slow seconds
  are grouped into named low-FPS windows with their fault rate and footprint change;
- five-second thread CPU, system memory, and system-wide GPU utilization snapshots; network byte
  totals, loaded-file snapshots, and binary hashes;
- a 1 kHz x87sidecar guest-PC profile of the real game thread, split into ten-second windows and
  correlated with the DXVK frame-rate log. Broad discovery finds the busiest guest-running thread,
  and sticky sampling keeps following it through DLLs, Rosetta code, syscalls, and long stalls. The
  summary reports coverage and separate hotspots for slow and recovered windows;
- the launcher logs with common username, password, token, and secret forms redacted;
- when `X87_PROFILE` is set for the launch, the x87sidecar block-execution profile of the game
  process. The summary reports whether the counter section is present; it is written only after
  the game exits, which is why `menu-run.py` stops the game before the sidecars.

For a short run at 1080p, `--level deep` also enables the D3D9 call histogram, long-gap
attribution, framebuffer and render-pass probes. Those per-call probes change timing more than
the standard set. The draw probe is known to be unstable with the x87 sidecar at 4K, so do not
use deep mode there. The retired DXVK instruction sampler is intentionally excluded because it
suspended the frame thread and could turn a slow launch into a black-screen run. The guest-PC
sampler used now runs in x87sidecar and never suspends the target.

The diagnostic DLL also exposes `DXVK_UP_STAGE_LOG` in standard captures. It records any
`DrawPrimitiveUP` call that stays in one phase for a second, including primitive count, generated
vertex count, stride, data size, and allocation size. The deep-only `DXVK_UP_PROBE` splits
completed calls into device lock, draw preparation, temporary-buffer allocation, user-data copy,
and command-enqueue time, with call rates and upload-size buckets. Apply
`patches/dxvk-1.10.3-drawprimitiveup-probe.patch` after the cumulative fence-wait patch when
building that DLL. Older DLLs ignore the variable, and the manifest records which probe names
each installed DLL actually contains.

With `patches/dxvk-1.10.3-pipeline-compiler-probe.patch` applied, `DXVK_FPS_LOG` also records
`compiler_busy`, `graphics_pipelines`, and `compute_pipelines`. Those columns show whether the
low-FPS window overlaps asynchronous state-cache compilation.

`scripts/tools/d3d9-up-bench.c` reproduces FFXI's 112-byte `DrawPrimitiveUP` traffic without an
account or server connection. It crosses the 1 MiB arena boundary many times and reports calls per
second. Use `DXVK_UP_PROBE` and `DXVK_UP_STAGE_LOG` with it to verify that an upload-buffer change
does not introduce a rollover stall.

Native `/usr/bin/sample` snapshots are off by default. Rosetta can produce recursive or otherwise
invalid native unwinds that look like Wine syscall loops. They remain available for a specific
host-side question with `--sample-at 30,90 --sample-seconds 5`.

Results go under `GAME/logs/performance-captures/<session>/`. The recorder writes both a compact
`summary.txt` and the raw files, then makes a `.tar.gz` beside the directory. It deliberately
never reads or stores a process argument list or Ashita boot profile because both may contain
account credentials.

To add host-side data to a game that is already running:

```sh
scripts/harness/capture-performance.py --pid <game-pid> --duration 60
```

An attached capture cannot turn on DXVK probes after process start, so use an armed launch when
the renderer data matters.

## bench.py

```sh
./bench.py --tag baseline                       # character select, default settings
./bench.py --tag div1 --env FFXI_FPS_DIVISOR=1  # one environment override
./bench.py --tag low --profile profiles/s-all-low.json
./bench.py --tag light --enters 0               # stop at the rules screen instead
```

It kills stale clients, applies the variant, launches the game, presses Return until the draw
count says the heavy scene has been reached, samples for `--sample` seconds, screenshots the game
window in the background (`screencapture -l <window>`, which works even when the window is
occluded), kills the client and writes `results/<tag>.json`.

A variant is a JSON profile with any of: `env`, `registry` (FFXI's own settings, applied through
Ashita's `[ffxi.registry]` block), `dxvk_conf`, `dlls`, `renderer`, `addons`.

Frame rate comes from `DXVK_FPS_LOG`, which our `d3d9.dll` writes. It also reports per-frame
draws, render passes, barriers and queue submits, so a change that helps the frame rate can be
told apart from one that just changes the scene.

**Scene choice.** Character select: ~1841 draws, deterministic, reachable with two keypresses,
and no character is in the world, so killing the client afterwards is safe. The rules-of-conduct
screen (`--enters 0`) is the light-scene equivalent at ~380 draws.

## fpsvideo.py

Frame rate for pathways that do not use our DXVK — counts visually distinct frames in a screen
recording with ffmpeg's `mpdecimate`. Cross-check it against `DXVK_FPS_LOG` on a DXVK run before
trusting it: it under-reports on a scene that is genuinely static.

## renderer.sh

Swaps the wrapper's wine D3D translation DLLs between wine's own builtins, DXMT (native Metal)
and DXVK's d3d11. Run `./renderer.sh save` once before the first switch and `restore` after.

## install-d3d9.sh

Copies a built `d3d9.dll` to all five paths the game can load it from. Missing one silently
tests the old build.

## addons/fpslog

An Ashita Lua addon that logs frame rate, zone and rendered-entity count to CSV — renderer
agnostic, so it measures pathways that have no DXVK in them. **It does not currently load**:
Ashita.dll in this install is interface 4.16 and every bundled plugin, including the `Addons`
Lua host, is 4.15, so the plugin manager rejects them all. Kept for when that is fixed.
