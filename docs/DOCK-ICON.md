# The Dock tile a running world wears

## The mechanism, from wine's source (2026-08-21)

No guessing needed — `dlls/winemac.drv` says exactly what it does:

    window.c:1234   pthread_once(&app_icon_once, set_app_icon);   // once, at first window creation
    window.c:795    set_app_icon()  -> create_app_icon_images()
    image.c:250     create_app_icon_images() -> KeUserDispatchCallback(app_icon_callback)
    dllmain.c:255   macdrv_app_icon() -> EnumResourceNamesW(NULL, RT_GROUP_ICON, get_first_resource, ...)

So the Dock tile is **the first `RT_GROUP_ICON` resource of the running .exe**, read once, when the
first window appears. That settles three things at once:

* `WM_SETICON` can never move it (window icons are a different thing entirely), which is why the
  addon's attempt logged success and changed nothing.
* No addon can fix it either: the icon is latched before any Lua runs.
* `exeIcon.icns` is a CrossOver-ism, not this path.

And the reason FFXI in particular gets a generic tile:

    $ wrestool -l bootloader/horizon-loader.exe
    --type=16 ... [type=version]
    --type=24 ... [manifest]

**`horizon-loader.exe` carries no icon resource at all.** wine logs "found no RT_GROUP_ICON
resource" and falls back to its own tile. The game is not being denied its icon; it has none.

## What was built, and where it stopped

`tools/icon-into-exe.c` (i686-mingw, runs under wine) adds an .ico to an exe through Windows' own
`BeginUpdateResource`/`UpdateResource`/`EndUpdateResource`, so there is no hand-rolled PE surgery.
It works: six icon images plus the group directory land in a **copy** of the loader, `wrestool`
lists them, and the patched copy behaves identically standalone (byte-identical `--help` output).

    ./scripts/theme-loader.sh     # builds the tool, patches a copy, leaves the original alone

**Ashita will not boot the patched copy.** The injector prints its banner and then nothing — no
injection, no login, no window — both when the copy is renamed (`horizon-loader-ffxi.exe`) and when
it keeps the original name in a sibling folder (`bootloader-ffxi/horizon-loader.exe`). The exe
itself is fine, so something in the Ashita/loader boot chain rejects a modified binary.

**Next**, in the order worth trying:

1. Find out what rejects it. Ashita's own log for those runs is the place to look — if the loader
   is hashed or signature-checked, this pathway is closed and step 2 is the answer.
2. **Patch winemac.drv instead of the game.** `wine-coop` is this project's own wine build, and a
   small patch there could read the app name *and* icon from environment variables — fixing the
   generic tile and the "wine" in Cmd-Tab together, for every world, without touching a single
   third-party binary. It needs a wine source build, which is the real cost.
3. Check whether `pol.exe` / `xiloader.exe` in the same folder already carry icons and whether
   Horizon accepts being booted through one of them.

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

## 2026-08-26: SOLVED — CX_ROOT icon fallback, no wine rebuild needed

The winemac.drv patch route (above) turned out to be unnecessary. Reading
`set_app_icon()` in the CX wine source (athei/wine `cx-26-patched`,
`dlls/winemac.drv/window.c:832`) shows CrossOver Hack 13440 already provides an
env-driven fallback:

* when the exe has **no** RT_GROUP_ICON resource, `create_app_icon_images()`
  returns NULL, and wine loads `$CX_ROOT/../../Resources/exeIcon.icns` instead.
* `horizon-loader.exe` has no icon resource, so it always takes this path.

So the fix is just to point `CX_ROOT` at a bundle-shaped folder that holds our
icon at `Contents/Resources/exeIcon.icns` (two levels up from CX_ROOT). No wine
build, no touching the server's binary.

**Verified 2026-08-26.** An icon-less test exe run under `wine-coop` with
`CX_ROOT` set showed the gold crystal tile in the Dock (running dot beneath it),
and a live `horizon-loader.exe` launch through the launcher showed the same gold
crystal. See `DockIcon.cxRoot()` (builds the folder under Application Support and
returns the CX_ROOT path) and `Runner.launchClient` (sets `env["CX_ROOT"]`).

CX_ROOT is otherwise read only by `localspl` (ps2pdf, printing) and the
round-rect icon mask PNG — which this project deliberately does not ship, so the
crystal is drawn as-is.
