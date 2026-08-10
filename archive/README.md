# archive — experiments that did not work

Kept because knowing what failed, and exactly how, is worth more than a clean directory. Every
item here was actually run on an M1 MacBook Pro, 8GB, macOS 26.5. See
[`../docs/PATHWAYS.md`](../docs/PATHWAYS.md) for the narrative and
[`../docs/FINDINGS.md`](../docs/FINDINGS.md) for the instrumented evidence.

| Experiment | Outcome |
| --- | --- |
| DXVK 3.0.2 (x32 d3d8 + d3d9) | loads, enumerates the M1, then `Skipping: Device does not support required feature 'geometryShader'` → `No adapters found`. Metal has no geometry shaders; **DXVK ≥2.x can never work on Apple Silicon** |
| the wrapper's own `renderer/d9vk` 32-bit `d3d9.dll` | `status=c0000135` from `load_dll` before its imports are touched — in `syswow64`, beside the executable, and as a wine builtin. Import table is clean, so the module itself is the problem |
| `vc_redist.x86.exe` for the missing UCRT | installs and provides **nothing**; the VC redist carries the VC runtime, not the `api-ms-win-crt-*` api-sets. Take those from `wine.cx32bak/lib32on64/wine/` instead |
| `d3d9.deferSurfaceCreation = True` | confirmed applied in the DXVK log; no change (tested *before* the swapeffect fix — worth one retest) |
| wine virtual desktop (`explorer /desktop=hxi,1280x720`) | still black (also pre-swapeffect) |
| Whisky as an alternative wrapper | discontinued upstream, disabled 2026-04-09. Installs, `whisky create` claims success, the bottle is empty — it no longer downloads its wine at all |
| back buffer format sweep (`fmt22`, `fmt21`, `depth_on`) | presentation works (HUD renders, ~29 FPS, 390–418 draw calls/frame) but the game's own output stays black in every variant |
| launching `horizon-loader.exe` directly to rule Ashita out | exits silently before creating a window — the long-standing xiloader-direct failure, so this isolation is not available |

## Two mistakes recorded on purpose

1. **Declaring victory on counters.** CPU 148% → 11–16% and GPU 6% → 24–32% looked like a win. It
   was not: nothing was being presented, and a renderer that never draws is also cheap. The
   acceptance test is a visible frame.
2. **Blaming Rosetta.** Every macOS wine on Apple Silicon is x86_64 under Rosetta, including
   Whisky's own engine, and D3DMetal games render fine from that arrangement. The real constraint
   is that D3DMetal ships x86_64-only DLLs and FFXI is a 32-bit game.
