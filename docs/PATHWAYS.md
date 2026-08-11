# Pathways — what has been tried, what is live, what to try next

Written for whoever (or whatever) picks this up next. Read [`GOALS.md`](GOALS.md) for what Daniel
asked for, and [`FINDINGS.md`](FINDINGS.md) for the older instrumented evidence.

The one-line summary as of **2026-08-10**:

> **Done: 29 fps in a zone, world rendering correctly — FFXI's cap is 30.**
> The black world on DXVK was fixed-function **fog**, and the untextured Vulkan render was five
> missing rows in wined3d's format table. Both are fixed and both are one-line-ish changes to
> other people's code, written up in `UPSTREAM.md` and `../patches/`.
>
> | pathway | in-zone fps | picture |
> | --- | --- | --- |
> | **Metal / DXVK 1.10.3 (patched)** | **29** | **correct** (no distance fog) |
> | Vulkan / wined3d (patched) | 8-10 | correct |
> | Classic OpenGL | 3.2 | correct |

---

## Measurements

All on the same MacBook Pro M1 / 8 GB, macOS 26.5, wine-10.0 (Sikarugir), same zone (Selbina) or
the same menu. Frame rates from `WINEDEBUG=fps` (wine paths) and the DXVK HUD; GPU from
`ioreg -rc IOAccelerator`; CPU from `ps`.

| Pathway | Menu fps | In-zone fps | CPU | GPU | Picture |
| --- | --- | --- | --- | --- | --- |
| **OpenGL** (shipped) | 5.1 → **8.3** after fixes | **3.2** | 185% | 9% | complete and correct |
| **wined3d Vulkan** *(DXT-patched)* | **20.6** | **7.0–10** | 123% | 93% | **correct** |
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

**Solved on 2026-08-10.** It was never a Metal, MoltenVK or 32-bit limitation. wined3d keeps a
static table in `dlls/wined3d/utils.c` (`init_vulkan_format_info`) mapping wined3d format ids to
VkFormats. It lists the D3D10-era names — `WINED3DFMT_BC1_UNORM` and friends — but **not the
D3D8/9 FourCC aliases**, which are different enum values entirely:

```c
WINED3DFMT_BC1_UNORM  = 100          /* in the table   */
WINED3DFMT_DXT1       = 'DXT1'       /* 0x31545844 — not in the table */
```

FFXI is a D3D8 game, so it creates every texture as `DXT1`/`DXT3`/`DXT5`. wined3d looks the id up,
misses, logs `Unsupported format WINED3DFMT_DXT1` **before it ever asks Vulkan anything**, and
drops the texture. The GL backend's equivalent table does have the DXT rows, which is exactly why
OpenGL looked correct and Vulkan did not.

The source fix is five extra rows. Since there is no wine build here, `scripts/dxt-patch.py`
rewrites five rows *in place* in the shipped `wined3d.dll` — the BC4/BC5/BC6H/BC7 entries, which a
2002 D3D8 game can never request — remapping them to DXT1-5. Same table, same size, no relocation,
reversible from the `.orig` backup it writes.

**Result: the Vulkan pathway renders the game correctly**, in-zone, on the GPU
(`docs/img/vk-dxt-charselect.png`, `docs/img/vk-dxt-world.png`):

| | before the patch | after |
| --- | --- | --- |
| in-zone fps | — (untextured) | **7.0**, and **8–10** with the MoltenVK knobs below |
| textures | grey silhouettes | correct |
| CPU / GPU | 46% / 95% | 123% / 93% |

Against OpenGL's 3.2 fps in the same zone that is a **2–3x speed-up with the picture intact** —
the first pathway that is both GPU-accelerated and visually correct.

Worth another ~30%: MoltenVK 1.4.2 in place of the bundled 1.2.10, plus
`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1`, `MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1` and
`MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0`. (1.4.2 is fine for wined3d; only DXVK 1.10.3 rejects it.)

### Still short of the 30 fps target — and now we know why

MoltenVK's own profiler (`MVK_CONFIG_PERFORMANCE_TRACKING=1`) on this pathway, in a zone:

| activity | avg per frame |
| --- | --- |
| **Encode VkCommandBuffer to MTLCommandBuffer** | **35.4 ms** |
| Retrieve a CAMetalDrawable | 32.0 ms |
| Present swapchains on GPU | 32.2 ms |
| vkQueueSubmit() encoding | 0.009 ms |
| **Frame interval** | **69.7 ms (14 fps)** |

Command-buffer *encoding alone* is longer than the entire 33 ms budget for 30 fps. That is CPU
time inside MoltenVK translating wined3d's commands into Metal, at roughly 1,100 draw calls a
frame.

Crucially, **DXVK sustains 29 fps at the same draw-call count on the same MoltenVK**. So this is
not a MoltenVK ceiling — it is wined3d's Vulkan backend issuing far more state and descriptor
churn per draw than DXVK does. Optimising it means changing wined3d, not settings.

Things that do **not** help, all measured:
- 640x360 with 512px background textures — *slower*, and the GPU stayed at 93%. Not fill rate.
- `backbuffercount = 2` (the one-image swapchain warning) — no change, ~8-10 fps either way.

FFXI caps at 30 and this pathway does 8–10. The remaining cost is **not** pixels: dropping the
window to 640x360 and background textures to 512 made it *slower*, not faster, and the GPU sits at
93% either way. That points at per-draw-call overhead — descriptor and barrier churn in wined3d's
Vulkan backend, and command-buffer submission through MoltenVK — rather than fill rate. Settings
will not close a 3x gap here.

Two leads worth taking, in order:

**DXVK is the only realistic route to 30**, because it already runs at 29. What it needs is its
black-world bug fixed, not more speed. See Pathway C.

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

### Fix 3 — bypass fixed-function fog  *(this was the black world)*

Found by building DXVK 1.10.3 from source and bisecting the fixed-function fragment shader.
The last thing that happens to every FFP fragment, immediately before the colour is stored, is:

```cpp
current = DoFixedFunctionFog(m_module, fogCtx);   // fogCtx.RenderState = m_rsBlock
m_module.opStore(m_ps.out.COLOR, current);
```

Fog reads its parameters out of `render_state_t` — **the same uniform block MoltenVK mis-binds**,
the one that collides at `[[buffer(0)]]` with `D3D9FixedFunctionPS`. With garbage fog parameters
the fog factor saturates and every lit surface is replaced by the fog colour. The sky, the 2D UI
and the fonts do not go through FFP fog, which is exactly why those always rendered while the
whole world was black.

Bypassing fog restores the picture completely: `docs/img/dxvk-fixed-menu.png`,
`docs/img/dxvk-fixed-charselect.png`, `docs/img/dxvk-fixed-world.png` — **29 fps in Selbina**.
The cost is no distance fog. The proper fix is to make `render_state_t` bind correctly on
MoltenVK; until then this is the trade, and it is worth it.

Patch: `patches/dxvk-1.10.3-ffp-fog.patch`. Built DLL: `vendor/dxvk-1.10.3-x32-d3d9-nofog.dll`.

### Building DXVK for this

`brew install meson ninja mingw-w64 glslang`, then from a v1.10.3 checkout:

```sh
meson setup --cross-file build-win32.txt --buildtype release builddir32
ninja -C builddir32 src/d3d9/d3d9.dll     # d3d10/d3d11 do not build with mingw 14; not needed
i686-w64-mingw32-strip -s builddir32/src/d3d9/d3d9.dll
```

`patches/dxvk-1.10.3-build-gcc14.patch` carries the two build fixes required by modern GCC.

### Why not DXVK 2.x or 3.x

Tested, not guessed: DXVK 3.0.2 on MoltenVK 1.4.2 (Vulkan 1.4) still rejects the M1 for
`geometryShader`. Relaxing that and `robustBufferAccess` in a source build gets further, then it
wants `shaderCullDistance`, then `nullDescriptor`, then `khrPipelineLibrary` — DXVK 2.x's core
architecture. Those are not peripheral features and faking them would produce exactly the kind of
lying-driver situation that caused the original black window. **1.10.3 is the last usable
version on MoltenVK**, which is why macOS DXVK stalled there.

**`d3d8to9` is not the culprit — ruled out 2026-08-10.** d8vk 1.0 (AlpyneDreams/d8vk) is a
completely independent D3D8 implementation built on the same DXVK 1.10 core, with no d3d8to9 and
no separate d3d9.dll in the chain. It behaves *identically*: 29 fps at the menu, black world
in-zone. Whatever is wrong lives in DXVK's own D3D9/Vulkan core or in how it lands textures on
MoltenVK, not in the D3D8 translation layer.

`d3d9.forceSamplerTypeSpecConstants = True` — DXVK's documented workaround for games that sample
black — makes no difference either.

**Current best hypothesis: compressed-texture uploads.** The failure now has a sibling to compare
against. On the Vulkan pathway, missing DXT support rendered world surfaces **white**; on DXVK
they render **black**, while the uncompressed UI and fonts are perfect on both. DXVK definitely
*accepts* BC formats — it logs no format complaints at all — so the suspicion is that the block
data never lands correctly in the image on MoltenVK. Worth doing next: dump a known DXT texture
back out of DXVK, or force a non-compressed texture path, and compare.

**A second lead, and its caveat.** `DXVK_LOG_LEVEL=debug` produces exactly one repeated complaint, and
it repeats a lot — **1126 times** by character select:

```
warn:  ConvertFormat: Unknown format encountered: 65
```

65 is `D3DFMT_W11V11U10`, a **D3D8-only** bump-map format that was removed in D3D9. d3d8to9 passes
it through unchanged and DXVK has no idea what it is. That is a genuine translation gap and it is
worth pursuing.

Be careful with it, though: it is not proven to be *the* cause. FFXI's bump mapping is already off
(`ffxi.registry 0017 = 0`), and zeroing `0018`–`0021`, `0034` and `0035` did not reduce the count.
`ConvertFormat` is also reached from `CheckDeviceFormat`, so 1126 hits may be capability probing
rather than 1126 failed texture uploads. Confirm which before building anything on it.

One trap found while bisecting those keys: **`0034` is Window Mode** (0 = full screen). Setting it
to 0 sends the game into fullscreen, `EnterFullscreenMode` fails on macOS, and the process exits —
which reads as "the experiment produced zero format errors" when really it produced zero frames.
Always check the game is still alive before believing a count went down.

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
