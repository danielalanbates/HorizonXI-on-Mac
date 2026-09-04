# vendor — third-party binaries

Redistributed so the Metal renderer and x87 acceleration work without a build on the user's Mac.
All are freely redistributable. Local modifications are listed below and in `../patches/README.md`.

| File | Upstream | Version | Licence |
| --- | --- | --- | --- |
| `d3d8to9.dll` | [crosire/d3d8to9](https://github.com/crosire/d3d8to9) | v1.15.1 | BSD 3-Clause |
| `dxvk-1.10.3-x32-d3d9-horizonxi.dll` | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) `x32/d3d9.dll` plus the project patches | v1.10.3+ | zlib |
| `x87sidecar-coop` | [athei/x87sidecar](https://github.com/athei/x87sidecar) `4e9c738` plus `x87sidecar-profile-pid-path.patch` | built 2026-09-03 | MIT |
| `x87sidecar_entitled` | [athei/x87sidecar](https://github.com/athei/x87sidecar) `rosetta_loader` | built 2026-08-12 | MIT |

## dxvk-1.10.3-x32-d3d9-horizonxi.dll

This is DXVK 1.10.3 with the cumulative HorizonXI and exact readback-fence patches, the
MoltenVK upload-buffer prefault, the NX enforcement that removes the scene-load stall under
Rosetta, and the opt-in diagnostic probes listed in `../patches/README.md`. The prefault and NX
enforcement are active in normal play. The probes do nothing unless the launcher arms a
performance capture. SHA-256 `5164ce8dae9f1defaf03c6bfad67779944884854be5df4b01da1c7519371e9b6`,
built 2026-09-03 from the patch stack in `../patches/README.md`, which was verified to reproduce
the build tree exactly.

## x87sidecar-coop

This is the unentitled cooperative binary used by the patched Wine runtime: upstream `4e9c738`
plus `../patches/x87sidecar-profile-pid-path.patch`, which expands `%p` in both `X87_SAMPLE` and
`X87_PROFILE` to the profiled target's PID. The launcher needs this because its injector and game
processes inherit one output path but run in separate sidecars. SHA-256
`81185d42b73a0390712d8cc9d99f5bc9416fb4b31ffdaf7efb26b9675fbd3ad6`. Upstream `4e9c738` carries
the FMA-contraction default, the block-restart cache reset, and async-signal survival that removed
the earlier `FFXiMain.dll+0x3d638` geometry stall. The sticky-sampler patch has not been ported
to this commit. The local patch affects diagnostics only.

## x87sidecar_entitled

Patches Rosetta 2's x87 emulation with a native ARM64 JIT — FFXI's 32-bit client runs its
floating-point math through x87, which Rosetta emulates at roughly 1% of native speed (see
`docs/X87-WALL.md`); this is the fix, worth 11.3→28.5 fps in-world at max settings. Built from
source with one local patch, `../patches/x87sidecar-attach-pid.patch`, adding an `--attach <pid>`
mode: without it the sidecar can only patch a process it launches itself, but Ashita runs the
actual game in a child process (`horizon-loader.exe`) that a launch-time wrap never reaches.

Built with the `get-task-allow` and `com.apple.security.cs.debugger` entitlements
(`x87sidecar-entitlements.plist`) required to attach to another process at all. `bundle.sh`
re-signs it individually with that plist *after* the app's own deep-sign, which otherwise
overwrites it with the app's entitlements (none) and silently breaks attaching.

**Why these exact versions.** DXVK 2.x and 3.x require Vulkan 1.3 and the `geometryShader`
feature. Metal has no geometry shaders, so MoltenVK can never expose one and those releases can
never run on Apple Silicon — 3.0.2 loads, enumerates the M1, and rejects it. 1.10.3 predates that
requirement. Gcenx's macOS repack of 1.10.3 omits `d3d9.dll` entirely, so it has to come from
doitsujin's release.

## dxvk-1.10.3-x32-d3d9-nofog.dll

DXVK 1.10.3 (doitsujin/dxvk, zlib/libpng licence), built here from the v1.10.3 tag with two
patches in `../patches/`:

* `dxvk-1.10.3-build-gcc14.patch` — build fixes only. GCC 14 / mingw-w64 14 no longer include
  `<cstdint>` transitively, and mingw now defines `_D3DDEVINFO_RESOURCEMANAGER` itself, so DXVK's
  old workaround became a redefinition.
* `dxvk-1.10.3-ffp-fog.patch` — the functional change. Fixed-function fog is bypassed, because it
  reads `render_state_t`, the uniform block MoltenVK mis-binds on Metal. See docs/PATHWAYS.md.

Build: `meson setup --cross-file build-win32.txt --buildtype release builddir32 &&
ninja -C builddir32 src/d3d9/d3d9.dll`, then `i686-w64-mingw32-strip -s`.

The unpatched `dxvk-1.10.3-x32-d3d9.dll` is kept beside it for comparison.
