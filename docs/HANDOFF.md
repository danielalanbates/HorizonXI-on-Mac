# Handoff — read this first

Written 2026-08-11 at the end of a long session. This is the state of the project, what was
proven, what is still open, and the three goals that are not finished. Everything here is
measured unless it says otherwise.

---

## Daniel's goals, verbatim, and their status

> "Get to 30fps by any means necessary… When we find a solution, that is when we need to move
> to phase 2, open beta. We also need to bundle all the dependencies into a package for a less
> computer-literate user to download and try on their own. The launcher needs to have the
> standard login name and password section."

> "keep iterating until we get this working at 30fps"

| goal | status |
| --- | --- |
| **30 fps in gameplay** | **NOT MET.** 25 fps light scenes, ~15 fps medium, ~6–10 fps crowded hubs |
| Fog rendering correctly | **DONE**, verified with screenshots |
| Phase 2 installer, notarised | **DONE** — `HorizonXI-on-Mac-2.2.dmg`, Gatekeeper-accepted |
| Launcher login/password section | **DONE** — Keychain-backed, already existed |
| Bundle all dependencies | **NOT DONE** — blocked, see §5 |

Two standing constraints from Daniel that must be respected:

- **No changes that can cause visual glitches in gameplay.** He said this explicitly. It is
  the constraint that kills the big optimisation (§4).
- **Launcher must not take more than 30s to start the game.** Currently 30–31s. No headroom.
- Don't change private-server code. Nothing here does; everything lives in our `d3d9.dll`.
- Use `/shutdown` in game chat to log out, not `kill -9`, or the character stays online.

---

## 1. What was actually fixed this session (all verified)

**Fog — the four-session "black world" bug.** One word in DXVK 1.10.3,
`src/d3d9/d3d9_fixed_function.cpp`:

```cpp
info.pushConstOffset = m_pushConstOffset;
info.pushConstSize   = m_pushConstOffset;   // was wrong; should be m_pushConstSize
```

For fixed-function *pixel* shaders `m_pushConstOffset` is 0, so the declared push-constant size
was 0, so `DxvkShader::defineResourceSlots` skipped `definePushConstRange` entirely and the
pipeline layout never listed `VK_SHADER_STAGE_FRAGMENT_BIT`. Desktop drivers bind push
constants anyway; MoltenVK honours the declaration, so `render_state_t` (fog colour/scale/end/
density, alpha ref) arrived **zeroed**. `fog_end == 0` clamps the fog factor to 0, so every lit
surface became the fog colour, which FFXI sets to black. Sky/fonts/UI skip FFP fog — which is
exactly why they always looked fine.

Upstream DXVK fixed this after 1.10.3 (d8vk, DXVK 2.x-based, already has
`info.pushConstSize = sizeof(D3D9RenderStateInfo)`), which independently validates the fix.

**DXVK freed from MoltenVK 1.2.10.** DXVK's D3D9 demanded `geometryShader`,
`robustBufferAccess` and `shaderCullDistance` unconditionally. Metal has none; 1.2.10 falsely
claims all three, 1.3+ honestly refuse. None is needed by D3D9. Made conditional → DXVK 1.10.3
now runs on **MoltenVK 1.4.1**. This also retires the old "it only works on a driver that lies"
caveat.

Both are upstream-worthy fixes affecting every D3D9 game on Metal, not just FFXI.

**+42% frame rate, zero rendering risk.** Same 737-draw scene: 17.6 → 22.8 → 25.0 fps.
The biggest single find: **`WINEMSYNC` was never being set** — the launcher defaulted it on but
`Play HorizonXI.command` and the test harness both omitted it. Shipped settings:
`WINEMSYNC=1`, `MVK_CONFIG_FAST_MATH_ENABLED=1`, `MVK_CONFIG_USE_COMMAND_POOLING=1`,
`MVK_CONFIG_PREALLOCATE_DESCRIPTORS=1`,
`MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1`, plus `vendor/dxvk.conf`.
Rejected as noise: synchronous queue submits, raised command-buffer ceiling,
`mscoree/mshtml` override.

**Disk / migration.** Game moved to the internal SSD and **verified running with the external
drive unmounted**. ~33 GB reclaimed total. Everything now under `/Users/daniel/Games/HorizonXI/`.

---

## 2. Why 30 fps is hard — the measurements that matter

**The stack sustains a roughly fixed 11,000–29,000 draw calls per second.** Frame rate is that
divided by draws per frame. This is the single most important number in the project.

| scene | draws | fps |
| --- | --- | --- |
| menu, light | 391 | 29.0 |
| menu, current settings | 737 | 25.0 |
| character select, heavy | 1904 | 15.1 |
| crowded hub (Jeuno) | 2106–2179 | 6.2–7.5 |

**It is CPU-bound, not GPU-bound.** Measured during a heavy scene: GPU
(`AGXAcceleratorG13G`) at **9–11%**, CPU **0.0% idle** (41% user + 59% *system* — driver
command encoding). MoltenVK's own profiler previously showed 35.4 ms/frame encoding against a
33 ms budget for 30 fps.

**Rosetta is structural.** PE headers confirm `FFXiMain.dll` and `horizon-loader.exe` are
**x86 32-bit**. Apple Silicon cannot run that natively; an arm64 wine still needs an x86
emulator for a win32 guest, so wine runs as x86_64 under Rosetta. CrossOver's arm64 support
covers 64-bit Windows titles only. Not fixable.

### Routes closed with evidence — do not re-litigate these

- **Apple GPTK / D3DMetal** — provides only d3d11/d3d12/dxgi. **No D3D9.** Cannot take this game.
- **DXMT** — d3d10core/d3d11 only. Same.
- **d8vk** (would remove the `d3d8to9` hop) — DXVK 2.x based, needs `graphicsPipelineLibrary`
  and `nullDescriptor`. Metal lacks both.
- **DXVK 2.x/3.x** — relaxing requirements walks into `nullDescriptor` → `khrPipelineLibrary`,
  which are core 2.x architecture.
- **GPU-assisted draw translation** — not possible. Translation is serial, branchy CPU work;
  GPUs cannot issue Metal API calls. Metal Indirect Command Buffers need the *application* to
  batch up front; FFXI is a 2002 immediate-mode fixed-function engine.
- **Draw-distance reduction** — no effect in hubs; the draws come from other players' models.
- **MoltenVK prefill modes** — noise.

---

## 3. Draw-call batching: the full investigation, including my own corrections

This is the one idea with real headroom, and it was measured four times. Each probe corrected
the previous one — read all four before acting.

Probe lives in `src/d3d9/d3d9_device.cpp` behind `DXVK_BATCH_PROBE=1`, writes
`/tmp/dxvk-batch-probe.log`. Raw logs in `docs/batch-probe*.log`.

1. **Group by shaders + textures** → 31×. *Optimistic — ignored the world transform.*
2. **+ world matrix + FF render states** → `trivial_merge` **1.4×**. Naive concatenation of
   adjacent draws is worthless, because draws sharing state rarely share their transform.
3. **+ vertex/index buffer identity** → `instancing_ratio` **9.7–9.9×**, with 90% of draws
   repeating a mesh+state already drawn that frame. Instancing is viable *in principle*.
4. **Consecutive-run and true-blend analysis** → the safe subset is tiny:

```
frame 5040 draws 642 ... instanceable 505 runmerges 324 opaquerun 118 blend 306 blendopaque 0
```

`blendopaque 0` is the key number: **every** blended draw in FFXI uses real alpha factors
(not `ONE`/`ZERO`), so none can be safely reordered. Merging only consecutive *opaque* runs
removes **18% of draws in a medium scene, 7.7% in a hub**.

**Conclusion.** A glitch-free batcher takes a ~28 fps scene to ~34 (crosses 30) but a hub from
~10 to ~10.8 (does not). The 31× and 9.9× figures require reordering alpha-blended geometry
across the frame, which violates Daniel's no-glitches constraint. Full detail in
`docs/BATCHING.md`.

### Half-built and waiting

`DXVK_FF_INSTANCING=1` (off by default) already makes the FF vertex shader read the WorldView
matrix **per instance**, via `gl_InstanceIndex` indexing DXVK's existing
`D3D9FF_VertexBlendData` storage buffer — no new descriptor needed. **Regression-checked with
the flag off: rendering unchanged.** Turning it on today renders wrong, because nothing fills
the array or issues an instanced draw.

Remaining CPU-side work: a deferral queue bucketed by (state signature, vertex buffer, index
buffer, primitive type, index range); per-batch matrix upload; flush as one draw with
`instanceCount = N` before the first blended draw and at frame end; blended draws submitted
immediately in order. The hard part is that flushing must be triggered by *every* state change,
which touches a lot of `D3D9DeviceEx` surface area — that is why it was not finished.

---

## 4. UNTESTED — the most promising thing left

**Disabling Ashita's overlay addons/plugins was set up but never measured.** The config loads
**22** addons and plugins, including `Nameplate`, which draws a textured plate per visible
player — potentially hundreds of draws in exactly the crowded hubs that fail worst. Overlays
cannot glitch gameplay geometry, so this is within the safety constraint.

The test was staged (`scripts/default.txt` rewritten to comment out 18 of them, backup at
`default.txt.full`) and **the run was interrupted before a number was captured**. Daniel's 22
addons have been restored. **Do this first — it is cheap and it targets the worst case.**

Related and also untested: FFXI's in-game "number of characters displayed" setting, which
directly reduces draws in hubs. It is a legitimate game setting, not a hack.

---

## 5. Licensing and the bundling blocker

Repo is **MIT** (`LICENSE`, rationale in `LICENSING.md`). DXVK patches stay **zlib** as
derivative works — which is also what upstream DXVK requires, so the two fixes above can be
submitted upstream without a relicensing problem.

**The blocker:** the wrapper in use (`siku.app`) is CrossOver-derived (`moltenvkcx/`,
`wine.cx32bak/`, `prefixcx24/`). CodeWeavers' commercial build cannot be redistributed, so
`scripts/package.sh` deliberately excludes it.

Daniel asked whether it could be kept in the same repo under CrossOver's own licence, in a
separate folder. **No** — directory structure does not grant redistribution rights. The
legitimate version is: *the user supplies their own CrossOver install* (as they already supply
the game data), with bundled upstream wine as the default path.

### Clean-room wine: renders, but 4× slower — UNRESOLVED

Upstream **WineHQ 11.0** (LGPL 2.1) is extracted at `/Users/daniel/Games/WineHQ`, with a clean
prefix at `/Users/daniel/Games/HorizonXI/prefix-winehq` and `scripts/Play-WineHQ.command`.

- **It renders correctly.** Full landscape, textures, fog. The blocker was that the fresh
  prefix had none of FFXI's registry state; fixed by exporting
  `HKEY_CURRENT_USER\Software\PlayOnlineUS` with `wine regedit /E` from the old prefix
  (scraping `user.reg` by hand produces a malformed `.reg` — don't).
- **But it runs at 4.7 fps vs 25.0 on the CrossOver wrapper**, same scene. Warm, not a
  first-run artefact.
- Ruled out: wow64 (both builds have identical `i386-windows` / `x86_64-unix` layouts) and
  msync alone (worth ~30%, not 4×).
- **This gap is the top open question for bundling.** Daniel's instinct — study what CrossOver
  does that upstream wine doesn't — is the right next step.

Note: macOS 26 Gatekeeper **deletes** `Wine Stable.app` from `/Applications` right after the
Homebrew cask installs it. Extract the tarball from
`~/Library/Caches/Homebrew/downloads/` manually instead.

---

## 6. Blocked on Daniel

- Which of the three bundling routes: first-run downloader of a redistributable engine
  (recommended), build wine from source, or user-supplied CrossOver.
- Whether to relax the no-glitches constraint to allow reordering blended draws. That is where
  30 fps in hubs lives. He ruled it out; it should not be assumed.

---

## 7. Working practices that cost time to learn

- **Install `d3d9.dll` to all five paths** or you silently test the old build:
  `drive_c/HorizonXI/`, `drive_c/HorizonXI/bootloader/`, `SquareEnix/FINAL FANTASY XI/`,
  `SquareEnix/PlayOnlineViewer/`, `drive_c/windows/syswow64/`.
- **`patches/dxvk-1.10.3-metal-features-and-fog-probes.patch` is a superset** — it contains the
  GCC 14 `<cstdint>` fixes. Apply it alone to a clean `v1.10.3` checkout; applying the gcc14
  patch first conflicts.
- **Driving the game headlessly:** `CGEventPostToPid` does *not* work. The window needs real
  focus, which only succeeds after hiding every other regular app and retrying
  `activateWithOptions_` until `frontmostApplication()` matches. See `scripts/drive2.py`.
- **Never send blind Enter presses in-world.** Doing so opened the auction house and reached a
  "transaction fee" confirmation. Backed out with Escape only. Use `scripts/game-shutdown.py`
  or `cmd.py`-style typed commands.
- **The character-select background is a valid oracle** — full textured landscape on a working
  build, black silhouette under a correct sky on a broken one. No login needed.
- **DXVK's state cache has never been written**, because every test ended in `kill -9`. It only
  flushes on clean exit. A real `/shutdown` should populate it and cut startup — untested.
- Launch time is **30–31s to window**: ~14s wine/Ashita, ~16s FFXI+DXVK init.

---

## 8. Suggested order for the next session

1. **Measure the Ashita overlay test** (§4). Cheap, safe, targets the worst case. Unfinished.
2. **Test FFXI's character-display-limit setting** in hubs. Same rationale.
3. **Explain the WineHQ 4× gap** (§5). Unblocks legal bundling. Daniel specifically asked for
   a CrossOver-vs-wine comparison here.
4. **Build the opaque-consecutive batcher** (§3). Multi-day, gets medium scenes over 30, will
   not fix hubs.
5. **Upstream both DXVK fixes.** They are correct, small and well-evidenced.

Do not promise 30 fps in beta notes. Promise correct rendering and ~25 fps in normal play,
lower in crowded hubs.
