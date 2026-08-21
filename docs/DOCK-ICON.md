# The Dock tile a running world wears

Goal: every game launch shows an FFXI-themed tile instead of a generic one.

**Status: partly done.** The launcher's own tile is this project's crystal. The *game's* tile is
still generic. What follows is what was tried, with the result, so the next attempt starts from
evidence rather than from scratch.

## Where a wine process's tile actually comes from

Not from the wrapper. Three things were measured on 2026-08-21:

1. **The wrapper's Info.plist does not decide it.** `siku.app` was restamped (its `AppIcon.icns`
   replaced with ours, `CFBundleName` set to "FFXI — HorizonXI"), and a wine process started from
   `siku.app/Contents/SharedSupport/wine/bin/wine` still showed as `wine` with wine's own tile.
2. **The window's Win32 icon does decide it — at window creation.** A wine Notepad shows a
   *Notepad* tile, so macdrv is reading the program's icon. Sending `WM_SETICON` afterwards (from
   `mousediag`, with an .ico this project generates) is accepted and logged, but the Dock tile
   does not change. The read looks like a one-shot at window creation.
3. **Running wine from inside our own .app bundle breaks wine.** Both a symlink and a hard link
   to the wine binary inside `Foo.app/Contents/MacOS/` fail: the symlink dies with
   "macdrv_init Failed to start Cocoa app main loop", and the hard link (and a plain copy) with
   "Your wine binary was not upgraded correctly". This wine resolves its own install root from
   its executable path, so it cannot be relocated into a bundle.

## What is in the tree

* `scripts/make_game_icon.py` -> `app/GameIcon.icns` — the gold variant of the launcher's crystal
  (this project's own art), so a running world reads differently from the launcher at a glance.
* `DockIcon.swift` — stamps the wine wrapper with that icon and the world's name before each
  launch, keeping the original as `AppIcon.original.icns`. Harmless and reversible
  (`DockIcon.restore`), and correct the day a launch goes through the wrapper app — but by
  finding (1) it is not what the Dock reads today.
* `addons/mousediag/ffxi-dock.ico` + the `WM_SETICON` call in `mousediag.lua` — sets the client
  window's icon. Verified to run ("dock icon: set from …"), not yet verified to move the tile.

## Also ruled out 2026-08-21 (second round)

4. **A real .app bundle around wine does not rename it either.** With `Contents/lib` and
   `Contents/share` symlinked to the wine tree, wine runs fine from inside a bundle named
   `HorizonXI.app` with our icon and `CFBundleName` — and Cmd-Tab still says **wine**, because
   winemac.so registers the Cocoa application itself. Setting `WINELOADER` to the in-bundle path
   changes nothing.
5. **`exeIcon.icns` next to the .exe is not read.** The name appears in winemac.so's strings
   alongside `create_app_icon_images` / `setApplicationIconImage:`, so this build does have a
   file-based icon path, but dropping `exeIcon.icns` in `C:\windows\system32` beside notepad.exe
   left the tile as wine's derived exe icon. The location it actually reads has not been found;
   the string is worth chasing with a disassembler rather than by guessing paths.

## What to try next, in order

1. **Set the icon before the first window exists.** `WM_SETICON` after the fact appears to be too
   late. An Ashita *plugin* (or `winefix`, which already loads first) could set the icon class
   for `FFXiClass` via `SetClassLongPtr(GCLP_HICON)` before the window is created, which is the
   handle macdrv would read at creation.
2. **Launch through the wrapper's own launcher.** Wineskin wrappers own the Dock tile through
   `siku.app/Contents/MacOS/wineskinlauncher`; a launch that goes through it would inherit the
   wrapper identity this project already stamps. The reason we do not is the launch-death work
   (docs/LAUNCH-DEATH.md): the game is spawned through a shell deliberately. Worth re-testing now
   that `spawnViaShell` is understood.
3. **Accept a per-world tile name only.** Even without the icon, giving the spawned shell a name
   ("HorizonXI" rather than `exec`) makes the Dock legible. Cheap, and independent of 1 and 2.
