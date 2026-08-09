# HorizonXI on Mac

Running **HorizonXI** (Final Fantasy XI private server) natively on Apple Silicon macOS under
Wine — no virtual machine.

> **Status: IT RUNS.** As of 2026-08-08 Final Fantasy XI renders natively on Apple Silicon
> macOS under Wine — window created, Direct3D8 device created, `GameLoaded`, input devices
> bound, music streaming through the DAT overlays. As far as a full GitHub sweep can tell, this
> is the first time that has happened: every other FFXI-on-a-non-Windows-machine project is Linux.
>
> Remaining: the character-select screen needs one real keypress. Synthetic input (CGEvent) does
> not reach wine-hosted windows on macOS, so that single step cannot be scripted.

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

## Roadmap

- [x] Login and server connection
- [x] Ashita injection, POL plugins, DAT overlays, macro import from a Windows install
- [x] **Game window opens, D3D8 device created, game loads**
- [x] `install.sh` — bare prefix to running game, no GUI
- [ ] Character select automated (blocked: needs real input into a wine window)
- [ ] `HorizonXI-on-Mac.app` — SwiftUI installer/launcher, modelled on
      [`marzent/XIV-on-Mac`](https://github.com/marzent/XIV-on-Mac)
- [ ] Frame-rate tuning, notarised download, macOS entry on the HorizonXI wiki

## Licence

GPL-3.0, matching `hxiloader` and `XIV-on-Mac`.

Not affiliated with HorizonXI, Square Enix, or the Ashita project.
