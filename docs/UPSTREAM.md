# Upstream reports

Two bugs found in this project's own debugging that are not ours to fix. Both are written up so
they can be filed verbatim. Neither has been filed yet — filing is a public action on someone
else's tracker and is Daniel's call.

Environment for both: MacBook Pro M1 (Apple M1, 8 GB), macOS 26.5, wine-10.0 (Sikarugir /
Gcenx build) running x86_64 under Rosetta, 32-bit Windows game (Final Fantasy XI).

---

## 1. MoltenVK — SPIRV-Cross assigns two uniform buffers to the same Metal binding

**Where:** KhronosGroup/MoltenVK
**Affects:** MoltenVK 1.2.10. Any D3D9 fixed-function title under DXVK 1.10.3.
**Severity:** total — the application renders nothing at all.

Compiling DXVK's D3D9 fixed-function fragment shader produces Metal source in which
`render_state_t` and `D3D9FixedFunctionPS` are both assigned `[[buffer(0)]]`:

```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Shader library compile failed (Error code 3):
program_source:112:135: error: cannot reserve 'buffer' resource location at index 0
fragment main0_out main0(main0_in in [[stage_in]],
                         constant render_state_t& render_state [[buffer(0)]],
                         constant D3D9FixedFunctionPS& consts [[buffer(0)]], …)
[mvk-error] VK_ERROR_INVALID_SHADER_NV: Fragment shader function could not be compiled into pipeline.
```

DXVK then reports `DxvkGraphicsPipeline: Failed to compile pipeline` for every fixed-function
pipeline. Its own HUD, which does not use those shaders, still draws — so the window shows a
frame-rate counter and draw-call count over a completely black scene, which is a very misleading
failure mode.

**Workaround:** `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1`. With argument buffers the collision
disappears, pipeline compilation succeeds, and the game renders.

**Suggested fix:** the descriptor-binding assignment should not hand the same Metal buffer index
to two distinct descriptors when argument buffers are off.

---

## 2. wine — wined3d's Vulkan backend rejects every BC/S3TC texture format on MoltenVK

**Where:** WineHQ Bugzilla, component `wined3d`
**Affects:** wine 10.0, `HKCU\Software\Wine\Direct3D` `renderer=vulkan`, on macOS/MoltenVK.
**Severity:** high — every compressed texture is dropped, so 3D content renders untextured.

With the Vulkan renderer selected, adapter init logs:

```
warn:d3d:init_vulkan_format_info Unsupported format WINED3DFMT_DXT1
warn:d3d:init_vulkan_format_info Unsupported format WINED3DFMT_DXT2 … DXT5
warn:d3d:init_vulkan_format_info Unsupported format WINED3DFMT_BC1_TYPELESS … BC7_TYPELESS
```

The game then renders correct geometry with correct fonts and UI — those textures are
uncompressed — and every model and terrain surface as flat untextured grey.
See `docs/img/vk-untextured.png` beside `docs/img/gl-charselect.png`, which is the same screen on
the OpenGL renderer.

**This does not look like a hardware limitation.** On the same machine:

- `MTLDevice.supportsBCTextureCompression` is `true`, both natively and in an x86_64 process
  under Rosetta (`scripts/bc-probe.swift`).
- The behaviour is identical on MoltenVK 1.2.10 and on 1.4.2, so it is not a MoltenVK version
  issue.
- DXVK 1.10.3 on the same MoltenVK does **not** complain about BC formats at all, which suggests
  the formats are in fact available and wined3d's acceptance check is what rejects them.

**Worth checking:** whether `init_vulkan_format_info` requires format features a block-compressed
format can never advertise (blit destination, storage image, etc.) rather than just
`SAMPLED_IMAGE`.

Also visible on the same run, and probably worth a separate report — the Vulkan backend has no
representative for a dozen fixed-function render states:

```
err:d3d:validate_state_table State STATE_RENDER(WINED3D_RS_COLORKEYENABLE) should have a representative.
… LIGHTING, SPECULARENABLE, COLORVERTEX, NORMALIZENORMALS, RANGEFOGENABLE, VERTEXBLEND,
  AMBIENTMATERIALSOURCE, DIFFUSEMATERIALSOURCE, EMISSIVEMATERIALSOURCE,
  SPECULARMATERIALSOURCE, LOCALVIEWER
```
