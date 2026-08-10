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
