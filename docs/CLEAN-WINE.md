# Replacing the CrossOver-derived wrapper with upstream wine

Goal: a wrapper we can legally redistribute, so the beta package can bundle everything.
The current `siku.app` is CrossOver-derived (`moltenvkcx/`, `wine.cx32bak/`, `prefixcx24/`)
and cannot ship. See `LICENSING.md`.

## Status: runs, but does not render yet

Upstream **WineHQ 11.0** (LGPL 2.1) is installed and hosting the game. What works:

- Extracted from WineHQ's own release tarball — unambiguous provenance, no CodeWeavers code.
- Ships `i386-windows` in `lib/wine/`, so it **can host FFXI's 32-bit x86 client** via wow64.
- Ships its own `libMoltenVK.dylib` at **1.4.1** — the same version our patched DXVK targets.
- Fresh prefix created, our patched DXVK `d3d9.dll` and `d3d8to9.dll` installed into
  `syswow64`, DLL overrides set.
- **The game launches.** DXVK initialises, creates a 1280x720 swapchain, MoltenVK reports
  `Created 2 swapchain images ... in layer CAMetalLayer: WineMetalView`, and `horizon-loader.exe`
  stays alive. No errors in the log.

What does not work: **the window stays black and no frames are presented.** The DXVK HUD does
not appear either, so the game is not drawing — it initialises the device and then stalls.

## Most likely cause, and where to resume

The fresh prefix has **none of FFXI's registry state**. The old prefix carries
`HKCU\Software\PlayOnlineUS\SquareEnix\FinalFantasyXI` with ~28 values (resolution, renderer
options, install paths); the new prefix has none, so the client has no configuration to boot
against.

An attempt to export those keys from the old `user.reg` and import them with `wine regedit`
produced a one-key file that did not take — the hand-rolled `.reg` export was malformed.
Resume there:

1. Export properly from the **old** prefix, preserving the full key block:
   `wine regedit /E ffxi.reg "HKEY_CURRENT_USER\Software\PlayOnlineUS"` run against the old
   prefix, rather than scraping `user.reg` by hand.
2. Import into the new prefix, then **let wineserver exit** before checking `user.reg` —
   registry writes are only flushed on wineserver shutdown.
3. Verify `grep -c PlayOnline $WINEPREFIX/user.reg` is non-zero, then relaunch.

If it still stalls after that, the next suspects in order:

- Ashita's injector may need the POL/`polcore` registry entries too, not just the FFXI ones.
- `gstreamer-runtime` was installed as a wine dependency; check whether wine is blocking on
  media initialisation (`WINEDLLOVERRIDES='winegstreamer=d'` to rule it out).
- Compare `wine` vs the CrossOver build for the `winemac.drv` display path — WineHQ uses the
  Mac driver, and the black window may be a surface-presentation mismatch rather than a game
  problem. `MTL_HUD_ENABLED=1` will show whether Metal is presenting at all.

## Launching it

`scripts/Play-WineHQ.command` runs the clean-room configuration. It carries the same measured
performance settings as the main launch script. It does not replace
`Play HorizonXI.command`, which remains the working, playable configuration.

## Why this matters beyond licensing

WineHQ's build is x86_64 like the CrossOver one, so Rosetta remains (FFXI is 32-bit x86 — see
`PHASE2-PACKAGING.md`). The win here is **redistribution rights**, not speed. Once it renders,
the beta package can bundle wine + MoltenVK + DXVK legally, and the only thing the user must
supply is the game data itself.
