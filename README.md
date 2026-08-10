# HorizonXI on Mac

Running **HorizonXI** (Final Fantasy XI private server) natively on Apple Silicon macOS under
Wine — no virtual machine.

> ## 📣 Open beta — [read the announcement](docs/ANNOUNCEMENT.md)
> Launcher and install script are ready for testers. It works; it is slow, and the Metal
> renderer is close but not there yet (see below). Testers wanted, especially on Apple
> Silicon with more than 8GB and on Intel Macs.

> ### 2026-08-10 — the launcher, and three renderers measured
>
> ![The launcher](docs/img/launcher.png)
>
> The launcher now has account name and password, a world dropdown (HorizonXI pinned, the rest
> ordered by community size), and a renderer picker. See [`docs/GOALS.md`](docs/GOALS.md).
>
> On the graphics side, every pathway was measured on the same M1 in the same zone:
>
> | Pathway | fps | CPU | GPU | picture |
> | --- | --- | --- | --- | --- |
> | OpenGL *(default)* | 3.2 in-zone | 185% | 9% | **complete and correct** |
> | wined3d Vulkan | 20.6 | 46% | 95% | models and terrain untextured |
> | d3d8to9 + DXVK | 29.1 | 89% | 17% | menus and UI perfect, 3D world black in-zone |
>
> Two long-standing blockers were root-caused and fixed today — DXVK's black window was
> MoltenVK assigning two uniform buffers to the same Metal binding, cured by
> `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1`; and `behaviorflags.fpu_preserve = 1` brought back
> most of the 3D pipeline. **Neither fast pathway is playable yet**, so Classic OpenGL is still
> the default and nothing has been announced to the HorizonXI community.
> Full write-up: [`docs/PATHWAYS.md`](docs/PATHWAYS.md).

> **Status: PLAYABLE.** As of 2026-08-08, Final Fantasy XI runs natively on Apple Silicon macOS
> under Wine — logged in, in-world, chat live, Ashita macros bound. As far as a full GitHub sweep
> can tell this is the first time that has happened: every other FFXI-on-a-non-Windows-machine
> project is Linux.
>
> ![Murn in Selbina](docs/img/murn-in-selbina.png)
>
> Level 75 Ninja standing on the dock in Selbina, no virtual machine involved.

Tested on: MacBook Pro M1, 8GB, macOS 26.5, Wine 10.0 (Sikarugir), HorizonXI client 1.9.0,
Ashita 4.3.1.2.

## Quick start

```sh
./scripts/install.sh /path/to/wrapper.app        # configure the prefix
"/path/to/Play HorizonXI.command"                # launch
```

Assumes the HorizonXI client is already extracted to `<prefix>/drive_c/HorizonXI` (~27GB).

## Why this repo exists

A GitHub sweep — ~318 FFXI-related repos, the Windower / AshitaXI / HorizonFFXI / LandSandBoat /
EdenServer / CatsEyeXI org listings, and code search for `FFXiMain.dll`, `horizon-loader.exe`,
`xiloader`+`WINEPREFIX` — turns up **zero** prior attempts to run FFXI on macOS:

- `Windower/Lumoria` — Windower's official FFXI installer/launcher. Vala + Flatpak, **Linux only**
- <https://gitlab.com/MattyGWS/HorizonXI-Linux-Installation> — the wiki's official pointer
- `sheik/horizonxi-linux`, `sarca571ca/horizonxi-lutris`, `TeamLinux01/HorizonXI-on-Deck`
- `jondwillis/kuluu-ffxi` — a Rust/Bevy client rebuild *on* macOS, but it drives the real client
  inside Parallels

The macOS-specific problems below are not covered by any of them.

## What was actually wrong

The symptom was a silent exit: login succeeded, the server connected, every DAT archive loaded,
and then the process closed in ~2s with no error, no crash dump and exit code 0. It never created
a window and never made a single d3d8 call, so it looked like a graphics problem. It was not.

**The PlayOnline registry layout is counter-intuitive, and every reasonable guess at it is wrong.**
HorizonXI ships the correct layout in `SquareEnix/Switch_Horizon.bat`:

```
HKLM\SOFTWARE\WOW6432Node\PlayOnlineUS\InstallFolder
    0001 = ...\SquareEnix\FINAL FANTASY XI      ← the GAME dir, not PlayOnlineViewer
    1000 = ...\SquareEnix\PlayOnlineViewer      ← POL goes in 1000
HKLM\SOFTWARE\WOW6432Node\PlayOnlineUS\Interface
    0001 = "0"                                   ← a string, not an empty key
```

Putting `PlayOnlineViewer` in `0001` — the obvious reading, and what the prefix had — makes
`FFXiMain.dll` stop loading entirely. Combined with writing to the wrong registry view (below)
and launching xiloader directly instead of through Ashita, the game aborted inside its own init
before window setup.

## Fixes this project found (macOS-specific, not in any Linux guide)

1. **The wrapper's `wineserver` cannot find its own dylibs.** Its rpath is `@loader_path/../../`,
   resolving to `SharedSupport/`, but the dylibs ship in `Contents/Frameworks/`. The usual
   workaround is exporting `DYLD_FALLBACK_LIBRARY_PATH`, which is a trap — see #2. The correct
   fix is to symlink the frameworks into the path the binary actually searches:
   [`scripts/fix-wine-rpath.sh`](scripts/fix-wine-rpath.sh).
2. **`nohup` and `/bin/sh` are SIP-protected and strip every `DYLD_*` variable.** Any launcher
   built on `DYLD_FALLBACK_LIBRARY_PATH` breaks the moment it is backgrounded or wrapped in a
   shell script — silently. `winetricks` is `#!/bin/sh` and hits exactly this. Fix #1 removes the
   dependency on the variable entirely.
3. **`reg.exe` writes the 64-bit registry view.** The 32-bit game reads
   `HKLM\SOFTWARE\Wow6432Node\...`, so a prefix configured with plain `wine reg add` leaves the
   game seeing nothing at all. Use `C:\windows\syswow64\reg.exe` — or write both views.
4. **FFXI is three COM in-proc servers, not one** — `FFXi.FFXiEntry`, `FFXiMain.GameMain`,
   `POLCore.POLCoreCom`. `regsvr32` **needs `/s`**: without it, `FFXi.dll`'s `DllRegisterServer`
   opens a GUI dialog, and synthetic input cannot reach wine windows, so it hangs forever with
   nothing to click. [`scripts/export-ffxi-com.py`](scripts/export-ffxi-com.py) lifts the
   registration out of a working prefix if you need to clone it.
5. **Launch through `Ashita-cli.exe`, not `xiloader` directly.** With the correct registry but
   launched xiloader-direct, the game still exits silently.
6. **Wine resolves a relative exe name against `C:\windows\system32`, not the cwd.** Always pass
   the absolute `C:\...` path.
7. **A wine prefix cannot live on exFAT**, and on a removable volume every process touching it
   needs the TCC "Removable Volumes" grant — which `launchd`-spawned jobs never have. Run it from
   a terminal with Full Disk Access.
8. **Synthetic input (CGEvent) does not reach wine-hosted windows.** Any step needing a real
   keypress or click cannot be automated — prefer silent/CLI equivalents everywhere else.

## Things that look like the bug and are not

Recorded so nobody re-treads them — all tested and disproven, with the instrumented evidence in
[`docs/FINDINGS.md`](docs/FINDINGS.md):

Ashita and its addons · `gdiplus` · sound init · the `patch.ver` version check · missing
`ROM11`–`ROM13` (not in the client's own `file.txt` manifest) · the Wine version (9.0 CX24 and
10.0 Sikarugir behave identically) · new-WoW64 vs a true 32-bit prefix · DAT corruption (170
size mismatches vs `file.txt` are intentional Horizon overrides, byte-identical to a working
Windows install) · `dgVoodoo2` and the `winefix` addon, which the Linux guides recommend —
`winefix` ships with the client and its own description says it only fixes a micro-stutter.

## The launcher

`HorizonXI-on-Mac.app` — account login (password in the Keychain, written into Ashita's boot
profile at launch and never into this repo), a preflight check for every precondition that has
silently broken before, one-click prefix repair, graphics settings, and a live log.

```sh
./app/bundle.sh          # build the .app (no Xcode needed — Command Line Tools only)
./scripts/package.sh     # build dist/HorizonXI-on-Mac-<version>.dmg
```

![Main menu](docs/img/main-menu.png)

## Performance — the open problem

The game runs on wine's builtin D3D8, which goes through OpenGL and is translated on a single CPU
thread: **148% CPU with the GPU at 6%**. The GPU is starved, not unused.

Getting onto Metal is *close*. D3D8 → d3d8to9 → DXVK 1.10.3 → MoltenVK now gets all the way to a
live Vulkan device — three separate blockers solved (the `api-ms-win-crt-*` DLLs wine does not
ship, a `d3d8.dll` on **Ashita's** search path as well as the game's, and the `moltenvkcx`
MoltenVK that speaks Vulkan 1.2 rather than the default 1.1). **But it never presents a frame** —
the window stays black while the GPU does work. That last step, DXVK's swapchain onto a wine
window on macOS, is unsolved. `HXI_METAL=1 ./scripts/install.sh …` applies the configuration for
anyone who wants to attack it. DXVK 2.x/3.x cannot work on Apple Silicon at all (Vulkan 1.3 +
`geometryShader`). Details in [`docs/FINDINGS.md`](docs/FINDINGS.md).

## Known limitations

- Five Ashita plugins fail to load: built against plugin interface 4.15, this Ashita wants 4.16.
- The `.dmg` is unsigned and un-notarised, so Gatekeeper blocks it on other Macs.
- Tested on exactly one machine: M1 MacBook Pro, 8GB, macOS 26.5.

## Roadmap

- [x] Login and server connection
- [x] Ashita injection, POL plugins, DAT overlays, macro import from a Windows install
- [x] **Game window opens, D3D8 device created, game loads**
- [x] `install.sh` — bare prefix to running game, no GUI
- [x] Character select and login — driven end to end from the host
- [x] `HorizonXI-on-Mac.app` — launcher with preflight, repair, account login
- [x] `package.sh` — distributable disk image
- [ ] **Renderer on Metal** — device creation solved; presentation (black window) is not
- [ ] Bundle Wine + client acquisition for non-technical users (first-run downloader)
- [ ] Developer ID signature + notarisation
- [ ] Announcement / macOS entry on the HorizonXI wiki — draft in
      [`docs/ANNOUNCEMENT.md`](docs/ANNOUNCEMENT.md)

## Licence

GPL-3.0, matching `hxiloader` and `XIV-on-Mac`.

Not affiliated with HorizonXI, Square Enix, or the Ashita project.
