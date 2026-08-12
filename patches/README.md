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

## What is in it

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

Only the two upstream fixes and `DXVK_KEEP_DEPTH` affect a normal run.
