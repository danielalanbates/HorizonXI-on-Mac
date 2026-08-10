# Pathways — what has been tried, what is live, what to try next

Written for whoever (or whatever) picks this up next. Read [`GOALS.md`](GOALS.md) for what Daniel
asked for, and [`FINDINGS.md`](FINDINGS.md) for the older instrumented evidence.

The one-line summary as of **2026-08-10**:

> The game is playable only on OpenGL, and OpenGL is slow: **3.2 fps in a zone**, 185% CPU, 9% GPU.
> Two GPU pathways now render — Vulkan at ~20 fps and DXVK/Metal at ~29 fps — and each is missing
> a different piece of the picture. Neither is playable yet. **The GPU gate is not passed.**

---

## Measurements

All on the same MacBook Pro M1 / 8 GB, macOS 26.5, wine-10.0 (Sikarugir), same zone (Selbina) or
the same menu. Frame rates from `WINEDEBUG=fps` (wine paths) and the DXVK HUD; GPU from
`ioreg -rc IOAccelerator`; CPU from `ps`.

| Pathway | Menu fps | In-zone fps | CPU | GPU | Picture |
| --- | --- | --- | --- | --- | --- |
| **OpenGL** (shipped) | 5.1 → **8.3** after fixes | **3.2** | 185% | 9% | complete and correct |
| **wined3d Vulkan** | **20.6** | — | 46% | 95% | geometry yes, **all models/terrain untextured** |
| **d3d8to9 + DXVK 1.10.3** | **29.3** | 29.1 | 89% | 17% | menus, character select, sky, all UI — **3D world black in-zone** |

Two things follow. The GPU is not the constraint on any pathway — OpenGL starves it at 9% while
pegging one CPU thread. And the fast pathways are *close*: each is one identified bug away.

---

## Pathway A — builtin D3D8 → wined3d → OpenGL  *(shipped, correct, slow)*

The default, and the only one that has ever put a complete textured frame of the game world on
screen. `docs/img/murn-in-selbina.png` and `docs/img/gl-world.png` are from this pathway.

**Improvement found today (kept, no downside):**

```
HKCU\Software\Wine\Direct3D  MaxVersionGL  REG_DWORD  0x40001
```

wined3d asks for an OpenGL 4.4 context. macOS caps at 4.1, the request fails
(`Couldn't create an OpenGL 4.4 context, trying fallback to a lower version`) and wined3d drops
onto a legacy path. Pinning the version it asks for measured **5.1 → 7.9 fps** at the same screen
with no visual change. `WINEMSYNC`/`WINEESYNC` and halving FFXI's background texture resolution
(`0003`/`0004` 2048 → 1024) added ~5% more; the resolution change costs visual quality, so it is
available but not the default.

The ceiling is architectural: `GL_VENDOR` is `Apple`, so it *is* the GPU driver, but every D3D8
call is translated on one CPU thread inside an x86_64 process under Rosetta, into a legacy GL
stack that Apple itself layers over Metal. 3 fps in a zone is what that costs.

## Pathway B — D3D8 → wined3d → **Vulkan** → MoltenVK → Metal  *(new; 4x faster, untextured)*

Enable with `renderer=vulkan` under `HKCU\Software\Wine\Direct3D`. This had never been tried
before today and it is a large change: **20.6 fps vs 5.1, CPU 46% vs 193%, GPU 95% vs 4%.**

It is not playable, for one precise reason:

```
warn:d3d:init_vulkan_format_info Unsupported format WINED3DFMT_DXT1 … DXT5
warn:d3d:init_vulkan_format_info Unsupported format WINED3DFMT_BC1_TYPELESS … BC7_TYPELESS
```

wined3d's Vulkan backend finds **no** BC/S3TC texture format usable, so every DXT-compressed
texture — which is all of FFXI's models and terrain — is dropped. Characters render as flat grey
silhouettes while fonts and UI, which are uncompressed, look perfect
(`docs/img/vk-untextured.png` next to the OpenGL shot of the same screen tells the whole story).

This is **not** a Metal limitation, and that is the interesting part:

- `MTLDevice.supportsBCTextureCompression` is **true** on this M1, natively *and* under Rosetta
  (`scripts/bc-probe.swift`).
- It is not a MoltenVK version problem either: identical output on the bundled MoltenVK 1.2.10 and
  on a freshly downloaded 1.4.2.

So either MoltenVK is not advertising BC through `vkGetPhysicalDeviceFormatProperties`, or
wined3d is demanding format features a compressed format cannot offer. **That question is the
single highest-value thing left in this project** — answering it turns a 4x-faster pathway into a
playable one. `warn+d3d` also shows the Vulkan backend has no representative for a dozen
fixed-function render states (`COLORKEYENABLE`, `LIGHTING`, `SPECULARENABLE`, …), so expect more
gaps behind this one.

## Pathway C — D3D8 → d3d8to9 → DXVK 1.10.3 → MoltenVK → Metal  *(new; renders, 29 fps, world black)*

Previously this pathway produced a black window with only DXVK's own HUD visible. **Two fixes
today changed that**, and both are now applied automatically by the launcher (`Renderer.swift`):

### Fix 1 — `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1`

The cause of the black window, finally named. MoltenVK's SPIRV-Cross was assigning two different
uniform buffers to the same Metal buffer index in DXVK's D3D9 fixed-function fragment shader:

```
[mvk-error] VK_ERROR_INITIALIZATION_FAILED: Shader library compile failed (Error code 3):
program_source:112:135: error: cannot reserve 'buffer' resource location at index 0
fragment main0(… constant render_state_t& render_state [[buffer(0)]],
                 constant D3D9FixedFunctionPS& consts [[buffer(0)]], …)
err:   DxvkGraphicsPipeline: Failed to compile pipeline
```

Every fixed-function fragment shader failed to compile, so every game draw was skipped — while
DXVK's HUD, which uses its own shaders, drew fine. That is exactly the "GPU busy, screen black"
signature that misled three earlier sessions. Switching MoltenVK to Metal argument buffers routes
descriptors differently and the collision disappears: **zero compile failures**, and the HorizonXI
logo and the Rules of Conduct screen render at 28.9 fps (`docs/img/dxvk-menu.png`).

### Fix 2 — `behaviorflags.fpu_preserve = 1` in the boot profile

With the shaders compiling, the menus rendered but character select was still black. Setting
`fpu_preserve` brought back the sky, the clouds and the terrain silhouettes, and took render
passes from 4 to 57. FFXI changes the x87 control word; without `D3DCREATE_FPU_PRESERVE` that
corrupts D3D9's own maths. This is a one-line ini change with a large effect
(`docs/img/dxvk-charselect.png`).

### What is still wrong

In-zone the 3D world is black while nameplates, chat, the compass and the whole 2D layer render
correctly at 29 fps (`docs/img/dxvk-world-black.png`). Sky renders at character select but terrain
and models do not. The shape of the failure — vertex-coloured geometry appears, textured geometry
does not — points at texture sampling returning black rather than at presentation.

**Next thing to try:** run with `DXVK_LOG_LEVEL=debug` and look at the `CheckDeviceFormat` traffic
for `D3DFMT_P8` / `A8P8`. FFXI leans on palettised textures, DXVK's D3D9 has historically not
implemented them, and "palettised textures sample as black while uncompressed UI is fine" fits
every observation. If that is it, the options are a DXVK patch or forcing FFXI to non-palettised
assets.

Things already ruled out for this pathway: it is not the present parameters (the old
`swapeffect = 1` / `backbuffercount = 1` workaround is no longer needed — defaults work now), and
it is not the depth buffer (`enableautodepthstencil = 1` + `D24S8` changes nothing).

---

## Dead ends — do not re-tread

| Tried | Result |
| --- | --- |
| **DXVK 2.x / 3.x** | Requires Vulkan 1.3 + `geometryShader`; Metal has no geometry shaders |
| Gcenx `DXVK-macOS` repack | ships no `d3d9.dll`. Use doitsujin's 1.10.3 release |
| the wrapper's own 32-bit `d9vk` | will not map at all — `status=c0000135` before its imports load |
| **MoltenVK 1.4.2 with DXVK 1.10.3** | `DxvkAdapter: Failed to create device`. 1.2.10 (`moltenvkcx`) is the one that works |
| newer MoltenVK to fix BC | 1.2.10 and 1.4.2 behave identically; not a version problem |
| `MVK_CONFIG_ADVERTISE_EXTENSIONS=0` | kills `VK_KHR_swapchain` too; the game crashes on launch |
| FFXI texture compression off (`0011 = 0`) | no change to the Vulkan untextured look |
| launching `horizon-loader.exe` directly, no Ashita | exits with `Closing…` before creating a window; Ashita cannot be ruled out this way |
| wine virtual desktop, `deferSurfaceCreation` | no effect (both pre-date the argument-buffers fix; worth one retest each) |
| **Whisky** | discontinued upstream; `whisky create` claims success and leaves an empty bottle |
| "it's Rosetta's fault" | wrong. Every macOS wine on Apple Silicon is x86_64 under Rosetta |

**D3DMetal is unavailable to this game, permanently.** The wrapper ships `x86_64-windows` D3DMetal
DLLs only, and FFXI is a 32-bit Windows game. 32-bit DXVK or wined3d-Vulkan into MoltenVK is the
only Metal route it has.

---

## Ground rules that save time

- **Verify with a picture.** Counters lie. A renderer that never presents is also cheap and fast.
  `screencapture -x -o -D 2` writes the HP 24uh in the background without stealing focus.
- **Kill `wineserver` before every registry change.** `reg` edits do not reach a running one, so a
  run can look like a success on the pathway you *think* you switched to while quietly using the
  old one. This produced a false victory in an earlier session.
- **Confirm the banner before believing a screenshot** — `DXVK: v1.10.3` in the log for DXVK,
  `renderer=vulkan` plus MoltenVK's `Created VkInstance` for Pathway B.
- **Launch detached** (`start_new_session=True`) or the game dies with the shell that spawned it.
- **Back up before every experiment.** `drive_c/dll-backup/*.builtin.dll`,
  `wine/lib/libMoltenVK.dylib.stock`, `config/boot/*.ini.vkbak` all exist for this reason.
- Leave the machine playable. Every experiment here was reverted and the OpenGL path re-verified
  afterwards.

## Tooling

`scripts/harness.py` runs a pathway end to end: switches renderer, kills the stale wineserver,
launches, samples fps/CPU/GPU on an interval, screenshots every display in the background and
scores each frame for actual picture content. `scripts/drive.py` clicks through Rules of Conduct →
character select → login using window-relative coordinates, so a full in-zone verification is one
command rather than twenty minutes of hand-driving.
