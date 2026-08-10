# Pathways — what has been tried, what is live, what to try next

Written for whoever (or whatever) picks this up next. The one-line summary:

> The game runs. It runs on wine's builtin D3D8 over OpenGL, which is slow. The Metal route
> (D3D8 → d3d8to9 → DXVK 1.10.3 → MoltenVK) now **presents correctly** — the DXVK HUD renders at
> ~31 FPS — but the game's own output is still black. That is the current frontier.

Read [`FINDINGS.md`](FINDINGS.md) for the instrumented evidence behind every claim here.

---

## The two renderer pathways

### Pathway A — builtin D3D8 → WineD3D → OpenGL  *(shipped, works, slow)*

This is what `scripts/install.sh` configures by default and what the launcher uses.

- **Status:** playable end to end. Login, character select, in-world, chat, Ashita macros.
- **Cost:** 148% CPU with the GPU at 6%. The GPU is *starved*, not unused — every D3D8 call is
  translated on one CPU thread. Zone loads take minutes on an M1/8GB.
- **Why it is still the default:** it is the only path that puts a picture on the screen.

### Pathway B — D3D8 → d3d8to9 → DXVK 1.10.3 → MoltenVK → Metal  *(experimental, `HXI_METAL=1`)*

Enabled with `HXI_METAL=1 ./scripts/install.sh <wrapper.app> <prefix>`.

Four separate things had to be true before this pathway got anywhere. Each failed **silently** and
each cost a debugging session, so they are worth knowing in order:

| # | Blocker | Symptom it produced | Fix |
| --- | --- | --- | --- |
| 1 | `Ashita.dll` imports `d3d8.dll` itself | `[E] Injection failed!` — looks exactly like the renderer breaking Ashita | put `d3d8.dll` in `C:\HorizonXI\` and `bootloader\` too, not only the game dirs |
| 2 | wine ships **zero** `api-ms-win-crt-*` DLLs | renderer DLL "not found" even though the file is right there | copy the 15 forwarders from `wine.cx32bak/lib32on64/wine/`. `vc_redist.x86.exe` does **not** provide these |
| 3 | default MoltenVK is Vulkan 1.1 | `DxvkAdapter: Failed to create device`, `timelineSemaphore : 0` | point `wine/lib/libMoltenVK.dylib` at `Frameworks/moltenvkcx/libMoltenVK.dylib` (Vulkan 1.2) |
| 4 | D3D8 present parameters | device live, GPU busy, **window black, nothing presented** | `presentparams.swapeffect = 1` (DISCARD) + `backbuffercount = 1` in `config/boot/<profile>.ini` |

After #4 the DXVK HUD renders: `DXVK v1.10.3 / D3D9 / Apple M1 / Vulkan 1.2.290`, ~31 FPS, 418
draw calls, 4 render passes, 11 graphics pipelines. **Presentation is solved.** The game itself
still draws black, which is now a content problem (format, render target, or depth-stencil), not
a presentation one.

**This distinction matters and is easy to get wrong.** Low CPU and busy GPU are *not* evidence of
success — a renderer that never presents is also cheap. The acceptance test is a visible frame.
An earlier pass of this work declared victory on counters alone and had to be retracted; don't
repeat it.

---

## Dead ends — do not re-tread

| Tried | Result |
| --- | --- |
| **DXVK 2.x / 3.x** | **Impossible on Apple Silicon.** Requires Vulkan 1.3 + `geometryShader`; Metal has no geometry shaders, so MoltenVK can never expose one. 3.0.2 loads, finds the M1, rejects it |
| Gcenx `DXVK-macOS` repack | omits `d3d9.dll` entirely — only d3d10core/d3d11. Use doitsujin's 1.10.3 release |
| the wrapper's own `renderer/d9vk` 32-bit d3d9 | will not even map — `status=c0000135` before its imports are touched, in `syswow64`, beside the exe, and as a wine builtin |
| `d3d9.deferSurfaceCreation = True` | applied and confirmed in the log; no change (this was pre-#4, may be worth retesting) |
| wine virtual desktop (`explorer /desktop=`) | still black (pre-#4) |
| **Whisky** | **discontinued upstream, disabled 2026-04-09.** Installs, `whisky create` claims success, bottle is empty — it no longer downloads its wine at all |
| "it's Rosetta's fault" | **wrong.** Every macOS wine on Apple Silicon is x86_64 under Rosetta, including Whisky's own engine, and D3DMetal games render fine from that arrangement |
| `WINEMSYNC=1` | never validated; it was set during a run that looked broken for unrelated reasons. Left off |

Also relevant: **D3DMetal in this wrapper ships `x86_64-windows` DLLs only.** FFXI is a 32-bit
Windows game, so D3DMetal is simply unavailable to it. 32-bit DXVK/d9vk → MoltenVK is the *only*
Metal route a 32-bit game has here.

---

## What to try next, in the order I would try it

1. **Sweep the present parameters.** `[ffxi.direct3d8]` in the boot profile exposes
   `backbufferformat`, `multisampletype`, `enableautodepthstencil`, `autodepthstencilformat` and
   `swapeffect`. A black-but-drawing frame is classic format mismatch. `scripts/sweep-present.py`
   automates this: it rewrites the ini, launches, screenshots, and moves on.
2. **Screenshot the swapchain, not the screen.** `DXVK_HUD=full` proves *what* is being presented.
   If the HUD is sharp and the scene is black, the game's render target is not reaching the back
   buffer — look at `d3d9.forceSwapchainMSAA`, and at whether Ashita's own D3D8 hooks are
   intercepting `Present`.
3. **Rule Ashita in or out.** Launch `horizon-loader.exe` directly with `--server/--user/--pass`,
   no Ashita, on Pathway B. Ashita hooks `Direct3DCreate8` and wraps the device; if the picture
   appears without it, the bug is in that interaction.
4. **Instrument DXVK.** Build 1.10.3 x32 with MinGW and log around `vkQueuePresentKHR`, the
   swapchain image acquisition, and `IDirect3DDevice9::Present`. This is the definitive answer and
   the most work.
5. **Re-test the pre-#4 dead ends.** `deferSurfaceCreation` and the virtual desktop were both
   tested *before* the swapeffect fix, when nothing could present. They deserve one more run each.

## Ground rules that save time

- **Verify with a picture.** Counters lie. `screencapture -x -o out.png` of the whole screen —
  `screencapture -l <windowid>` returns black for this window even when it is drawing.
- **Launch detached** (`start_new_session=True`) or the game dies when the shell that spawned it
  goes away. `scripts/../sweep-present.py` shows the pattern.
- **`reg delete` does not flush to `user.reg` until `wineserver` exits.** Kill it before editing
  the file, or your change silently persists.
- **Back up before every experiment.** `drive_c/dll-backup/*.builtin.dll`,
  `wine/lib/libMoltenVK.dylib.stock`, `config/boot/*.ini.premetal` all exist for this reason.
- Every experiment in this document was reverted afterwards and the game re-verified. Leave the
  machine playable.
