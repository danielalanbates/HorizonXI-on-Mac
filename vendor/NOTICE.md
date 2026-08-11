# vendor — third-party binaries

Redistributed so `HXI_METAL=1 ./scripts/install.sh` works without a network round-trip. Both are
freely redistributable; neither is modified.

| File | Upstream | Version | Licence |
| --- | --- | --- | --- |
| `d3d8to9.dll` | [crosire/d3d8to9](https://github.com/crosire/d3d8to9) | v1.15.1 | BSD 3-Clause |
| `dxvk-1.10.3-x32-d3d9.dll` | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) `x32/d3d9.dll` | v1.10.3 | zlib |

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
