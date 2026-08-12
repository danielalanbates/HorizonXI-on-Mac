# Handoff — read this first

Rewritten 2026-08-11 (evening). The previous version of this file described a renderer-bound
game and a draw-call batcher as the route to 30 fps. **That model was wrong.** This session
built the instrumentation to check it and the answer came out different. Everything below is
measured; where something is a guess it says so.

---

## Daniel's goals and their honest status

> "Get to 30fps by any means necessary… When we find a solution, that is when we need to move to
> phase 2, open beta. We also need to bundle all the dependencies into a package for a less
> computer-literate user to download and try on their own. The launcher needs to have the
> standard login name and password section."

| goal | status |
| --- | --- |
| **30 fps in gameplay** | **NOT MET.** In-world ~7.5 fps. Menus 12–24 fps. Cause now understood — see below |
| Understand *why* it is not 30 fps | **DONE, and it is not what we thought.** `docs/PERFORMANCE.md` |
| Fog / correct rendering | DONE (previous session), still correct |
| Launcher with login + password | DONE — Keychain-backed, `app/Sources/HorizonXILauncher/Credentials.swift` |
| Notarised installer | DONE (previous session) — `HorizonXI-on-Mac-2.2.dmg` |
| Bundle all dependencies | **UNBLOCKED this session** — the licence blocker was a misreading. `docs/BUNDLING.md` |

Standing constraints from Daniel: no changes that can cause visual glitches; launcher must start
the game in under 30 s; don't touch private-server code; use `/shutdown` in chat to log out,
never `kill -9` while a character is in the world.

---

## 1. The one paragraph that matters

FFXI on this stack is **not renderer-bound**. Draw calls cost 1.9 µs each and about 3% of a
frame; `Present` costs 0.05 ms; everything inside DXVK adds up to a fifth of the frame at
character select and almost nothing in the world. **Discarding every single draw call
(`DXVK_SKIP_DRAWS=1`) makes the frame rate go down, not up.** Optimising DXVK, MoltenVK, render
passes or draw batching cannot get to 30 fps, because they are not what the time is being spent
on.

In the world the client spends **~120 ms per frame doing nothing at all** — one stall per frame,
outside every D3D entry point, at 13% CPU. Find that and the same Mog House is a 75 fps scene.
It is written up as a bug report with eleven hypotheses already eliminated:
**`docs/INWORLD-STALL.md`**. Start there.

---

## 2. What this session actually produced

**Instrumentation, which is the durable part.** Frame rate no longer has to be read off an
overlay. Our `d3d9.dll` has six probes, all off unless their environment variable is set:

| variable | what it gives you |
| --- | --- |
| `DXVK_FPS_LOG` | CSV per second: fps, draws, render passes, barriers, submits per frame |
| `DXVK_PRESENT_PROBE` | ms inside `Present` vs ms outside it |
| `DXVK_DRAW_PROBE` | ms inside draws, ms inside state setters, every D3D9 call counted by kind, and a histogram of the gaps *between* our entry points attributed to the call that follows |
| `DXVK_PASS_PROBE` | which DxvkContext operation forced each render-pass break |
| `DXVK_FB_PROBE` | what changed about the framebuffer each time it was rebuilt |
| `DXVK_SKIP_DRAWS` | accept draws and discard them, to price the renderer out |

Plus a harness that runs a whole configuration end-to-end from one command:
`scripts/harness/bench.py` (menus / character select) and `inworld.py` (logs a character in,
measures, logs out with `/shutdown`).

**Two real fixes.** `FFXI_FPS_DIVISOR=<n>` patches the client's frame-rate cap the way Ashita's
`fps` addon does — with it, a frame above 30 was recorded for the first time in this project
(33.6 fps). And `GetRasterStatus` no longer divides by a zero refresh rate.

**Five things closed with evidence** so nobody re-litigates them: draw batching, render-pass
churn, the Ashita overlay addons, FFXI's graphics settings, and the CrossOver licence blocker.

---

## 3. Corrections to what this project previously believed

- **"Batching draws gets us to 30 fps" (`BATCHING.md`)** — no. The 9.9× instancing ratio was
  real but it was solving the wrong problem. Draws are 3% of the frame.
- **"Disabling Ashita's 22 overlay addons is the most promising thing left"** — they never load.
  Ashita.dll is plugin interface **4.16**, every bundled plugin is **4.15**, so `PluginManager`
  rejects all of them including the `Addons` Lua host. Every measurement this project has ever
  taken was already addon-free. (Worth fixing for Daniel's actual gameplay: none of his addons
  work.)
- **"~11–29k draw calls/sec is a fixed ceiling"** — it is not a ceiling, it is a by-product.
  Frame time is a large fixed cost plus a small per-draw one.
- **"Bundling is blocked because the wrapper is CrossOver-derived"** — the wrapper's *engine* is
  `wine-10.0 (Sikarugir)`, LGPL, and the MoltenVK it loads is the stock Khronos build. The
  CrossOver leftovers (`moltenvkcx`, `wine.cx32bak`, `prefixcx24`, ~845 MB) are unused. See
  `docs/BUNDLING.md`.
- **"CPU 0% idle, so we are CPU-bound"** — in the world the process is at **13% of one core**.

---

## 4. Where to pick this up

1. **`docs/INWORLD-STALL.md`.** Worth more than everything else combined. The strongest lead is
   that the stall is in FFXI's **texture** path through **d3d8to9** — the pauses land right
   before `SetTexture`, and the one pathway ever measured fast in-zone (wined3d-Vulkan, 20.6 fps)
   was the one rendering *untextured*. d3d8to9 is the only layer in the chain that is ours and
   is not instrumented. Build it from source with the same probes and the 120 ms splits in one
   run.
2. **Fix the Ashita plugin version mismatch.** Independently worth doing — it restores Daniel's
   addons — and it makes the `addons/fpslog` Lua logger in this repo work, which measures frame
   rate on pathways that have no DXVK in them.
3. **Phase 2 packaging** on the `docs/BUNDLING.md` plan: first-run download of a pinned
   Sikarugir engine, our DLLs inside the app, game data from HorizonXI's own installer.
4. **Upstream the two DXVK fixes** (`docs/UPSTREAM.md`). They are correct, small, and affect
   every D3D9 game on Metal.

Do not promise 30 fps in beta notes. The honest line is: rendering is correct, menus run at
12–24 fps, in-world is ~7.5 fps, and the cause of the in-world figure is identified but not yet
fixed.

---

## 5. Working practices that cost time to learn

- **Install `d3d9.dll` to all five paths** or you silently test the old build. Use
  `scripts/harness/install-d3d9.sh`.
- **`patches/dxvk-1.10.3-horizonxi.patch` is the whole thing** — apply it alone to a clean
  `v1.10.3` checkout. The three older patches are in `archive/2026-08-11/patches/` and will
  conflict.
- **Driving the game:** `CGEventPostToPid` does not work; the window needs real focus. Keystrokes
  do land even when `NSWorkspace.frontmostApplication` reports another app, so don't trust that
  as a gate — drive the scene by the measured draw count instead (`bench.py --heavy-draws`).
- **Never send blind Return presses in-world.** A previous session opened the auction house that
  way and reached a transaction-fee confirmation.
- **`/shutdown` sometimes needs a second attempt.** `inworld.py` retries; check `logged_out` in
  its result and log out by hand if it is false. A character left online is the one real risk in
  this harness.
- **The character-select background is a valid oracle** — full textured landscape on a working
  build, black silhouette under a correct sky on a broken one. No login needed.
- Launch time is 30–31 s to window: ~14 s wine/Ashita, ~16 s FFXI+DXVK init.
