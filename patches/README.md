# DXVK patch

`dxvk-1.10.3-horizonxi.patch` is the whole of this project's DXVK work as one patch against a
clean `v1.10.3` checkout. Apply it alone; the three earlier patches it replaces are in
`archive/2026-08-11/patches/` and applying any of them first will conflict.

```sh
git clone --depth 1 --branch v1.10.3 --recurse-submodules https://github.com/doitsujin/dxvk.git
cd dxvk
git apply /path/to/dxvk-1.10.3-horizonxi.patch
meson setup --cross-file build-win32.txt --buildtype release build32
ninja -C build32
i686-w64-mingw32-strip -o d3d9.dll build32/src/d3d9/d3d9.dll
```

Then install it with `scripts/install-d3d9.sh`, which copies it to all five paths the game can
load it from. Missing one silently tests the previous build.

The current vendored DLL starts with the later exact fence-wait work recorded in the cumulative
`dxvk-1.10.3-horizonxi-fencewait.patch`, then applies the upload-buffer prefault below. Apply
those patches to a clean `v1.10.3` checkout instead of applying the older cumulative patch.

For a diagnostic build that times each stage of `DrawPrimitiveUP`, apply the small probe patch
and the non-invasive presentation watchdog after it:

```sh
git apply /path/to/dxvk-1.10.3-horizonxi-fencewait.patch
git apply /path/to/dxvk-1.10.3-up-buffer-prefault.patch
git apply /path/to/dxvk-1.10.3-drawprimitiveup-probe.patch
git apply /path/to/dxvk-1.10.3-present-stage-probe.patch
git apply /path/to/dxvk-1.10.3-pipeline-compiler-probe.patch
git apply /path/to/dxvk-1.10.3-enforce-nx.patch
```

Set `DXVK_UP_PROBE=<path>` at launch for completed-call aggregates. Set
`DXVK_UP_STAGE_LOG=<path>` for an in-flight watchdog that reports the current phase and upload
sizes when a `DrawPrimitiveUP` call lasts at least one second. These probes do not alter the
normal build unless their environment variables are present. `DXVK_PRESENT_STAGE_LOG` and
`DXVK_SUBMIT_STAGE_LOG` record the current frame and submission phases once per second. Unlike
the older instruction sampler, none of the watchdogs suspend a Wine thread, and they still
identify a call that never returns. The pipeline compiler probe adds compiler activity and
graphics/compute pipeline totals to `DXVK_FPS_LOG`, which distinguishes scene-load compilation
from game-thread or renderer stalls.

## What is in it

**The loading-stall fix:** `dxvk-1.10.3-enforce-nx.patch`. FFXiMain.dll, FFXi.dll and pol.exe
are built without `IMAGE_DLLCHARACTERISTICS_NX_COMPAT`. Wine answers the first such module by
switching the whole process to execute-everywhere, something Windows never does for a DLL. Under
Rosetta, writable-and-executable pages are tracked by the exception server, and the first touch
of every fresh page then costs a Mach round trip on top of the fault. DXVK clears every new
host-visible buffer, so a scene load became a fault storm at 88% kernel time and under 1 FPS for
ten to thirty seconds. `Direct3DCreate9` now sets `ProcessExecuteFlags` to disable-permanent
before any buffer exists. On the scene-load reproducer (`scripts/tools/d3d9-scene-bench.c`) a
frame went from 2,260 ms to 12 ms; in the game the character-list run went from 24 seconds
below 10 FPS to 1, and boot to the character list from over 115 s to 40 s. `DXVK_ENFORCE_NX=0`
restores Wine's behaviour for A/B runs. The same change belongs in Wine itself, keyed on the
host being Rosetta, and is a candidate for upstream discussion.

**One MoltenVK upload-buffer fix:** `dxvk-1.10.3-up-buffer-prefault.patch` touches the initial
1 MiB D3D9 `DrawPrimitiveUP` arena before FFXI starts filling it with small uploads. DXVK clears
later backing allocations but deliberately leaves its first single-slice allocation untouched.
On MoltenVK, FFXI's 80-byte and 112-byte writes then first-touch mapped Metal memory one VM page
at a time. Each page blocks the render thread, leaving a newly loaded scene below 3 fps until the
arena has been traversed. The patch prefaults that initial arena and reserves one cleared standby
slice so the first rollover does not allocate in the middle of a frame. A 200,000-call synthetic
test sustained 180,397 `DrawPrimitiveUP` calls per second, and the real rules screen reached a
stable 50 fps in 32.4 seconds instead of 123.1 seconds in the unpatched control.

**Two upstream bugs, both worth submitting** (see `docs/UPSTREAM.md`):

- `d3d9_fixed_function.cpp` — `info.pushConstSize` was assigned `m_pushConstOffset`. For
  fixed-function pixel shaders that offset is 0, so no fragment push-constant range was
  declared. Desktop drivers bind push constants anyway; MoltenVK honours the declaration, so
  every fog constant arrived zeroed and the whole world rendered in the fog colour.
- `dxvk_adapter.cpp` — D3D9 required `geometryShader`, `robustBufferAccess` and
  `shaderCullDistance` unconditionally. Metal has none of them and D3D9 needs none of them.
  Making them conditional is what let DXVK run on MoltenVK 1.4.1 instead of only on 1.2.10,
  which was the one version that falsely claimed to support them.

**One rendering change, on by default, `DXVK_KEEP_DEPTH=0` to disable:** keep the depth-stencil
attached while depth and stencil are disabled instead of detaching it. Detaching changes the
attachment set, which forces a new framebuffer and spills the render pass; FFXI toggles
`ZENABLE`/`ZWRITEENABLE` constantly, so this was ~24,000 render-pass breaks per session. The
pipeline's depth state already says "don't test, don't write", so nothing about the picture
changes.

**One client tweak, off by default, `FFXI_FPS_DIVISOR=<n>`:** patch FFXI's frame-rate divisor
(1 = 60 fps target, 2 = 30 fps, the client default). Same signature scan and pointer walk
Ashita's `fps` addon uses. It lives here because Ashita's plugin host does not load in this
install. This is the difference between being allowed past 30 fps and not.

**Four measurement probes, all off unless their variable is set** — see `docs/PERFORMANCE.md`:
`DXVK_FPS_LOG`, `DXVK_PRESENT_PROBE`, `DXVK_DRAW_PROBE`, `DXVK_PASS_PROBE`, `DXVK_FB_PROBE`,
plus `DXVK_SKIP_DRAWS` and the older `DXVK_BATCH_PROBE` / `DXVK_FF_INSTANCING`.

The upload-buffer prefault and the two upstream fixes affect a normal run. The measurement probes
remain dormant unless their environment variables are set.

---

# x87sidecar diagnostic profiler patches

`x87sidecar-profile-pid-path.patch` applies to `athei/x87sidecar` commit `4e9c738` (v1.6.0 plus
the FMA-contraction default, the Rosetta block-restart cache reset, and async-signal survival in
emitted code). It makes `%p` in both `X87_PROFILE` and `X87_SAMPLE` expand to the profiled
target's PID before any output file is removed or opened. Wine launches one cooperative sidecar
for Ashita's injector and another for the real game process, and the launcher's own helper
sidecars add more. All of them inherit the same environment, so a fixed output path lets any of
them truncate the game's profile. The block profiler needs this most: it writes its counter
section only after its target exits, and the last sidecar to open a shared path wins.

`x87sidecar-sticky-sampler.patch` adds opt-in `X87_SAMPLE_STICKY=1`. Discovery still selects the
thread seen running guest code most often. Once selected, sticky mode follows that thread through
DLLs, Rosetta runtime code, syscalls, and long stalls, and only searches again if the thread can no
longer be read. It was written against commit `238a2147` and does not apply to `4e9c738` without
a port. The sidecar installed on 2026-09-03 does not include it, so `X87_SAMPLE_STICKY=1` is
currently ignored. The setting is harmless, and standard captures still produce a guest-PC
profile, but coverage falls when the game thread runs outside the main executable for long
periods.

```sh
git clone https://github.com/athei/x87sidecar.git
cd x87sidecar
git checkout 4e9c738
git apply /path/to/x87sidecar-profile-pid-path.patch
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
cp build/bin/x87sidecar /path/to/HorizonXI-on-Mac/vendor/x87sidecar-coop
```

The launcher uses a sample path ending in `x87-sample-%p.prof`, discovers across the broad guest
range `0x10000-0x800000000000`, samples the selected thread at 1 kHz, and writes ten-second
windows. `scripts/harness/menu-run.py --x87-profile` sets `X87_PROFILE` to
`x87-block-%p.prof` inside the capture directory for one launch. Both patches affect only
opt-in diagnostics. The x87 translation code and normal launches without `X87_SAMPLE` or
`X87_PROFILE` are unchanged.

---

# LandSandBoat linkshell zone-gap patch

`lsb-linkshell-zone-backlog.patch` is a server-side patch, not a client one. It applies to a
[LandSandBoat](https://github.com/LandSandBoat/server) checkout — written against `627e5671` —
and makes a character's linkshell replay the chat it missed while crossing a zone line.

```sh
cd ~/Games/lsb/server            # or wherever lsb-server.sh put it
git apply /path/to/lsb-linkshell-zone-backlog.patch
cmake --build build --target xi_map -j 4
```

It touches five files, all under `src/map/`: `linkshell.h`, `linkshell.cpp`, `ipc_client.cpp`,
`utils/charutils.cpp` and `packets/c2s/0x00a_login.cpp`. Nothing outside `xi_map` is affected and
there is no schema change, so `git checkout` on those five files and a rebuild puts stock
behaviour back.

**Licence:** LandSandBoat is GPLv3 and this patch is a derivative of it, so this patch is GPLv3
too — unlike the rest of this repository. Do not relabel it.

**Read `docs/LINKSHELL-ZONING.md` before using it.** It has the measurements, the reason the
obvious one-line version silently does nothing, and the two limits that matter: it only helps a
server running a single `xi_map` process, and one message can still be lost to a race with the
client's own connection teardown.
