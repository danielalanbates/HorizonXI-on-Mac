# HorizonXI on Mac

Running **HorizonXI** (Final Fantasy XI private server) natively on Apple Silicon macOS under
Wine — no virtual machine.

> **Status: NOT PLAYABLE YET.** Login, server connect, Ashita injection and the full DAT load all
> work. The game then exits silently before it creates its window. Nothing here is an install
> guide yet, and it will not be published as one until a character is actually standing in-game.
> What *is* here is a research record: every fix that was genuinely required, and every hypothesis
> that has been tested and disproven, so the next person does not re-tread it.

Tested on: MacBook Pro M1, 8GB, macOS 26.5, Wine 10.0 (Sikarugir), HorizonXI client 1.9.0,
Ashita 4.3.1.2.

## Why this repo exists

As of 2026-08-08 a GitHub search turns up **zero** prior attempts to run FFXI or HorizonXI on
macOS. Everything that exists is Linux:

- <https://gitlab.com/MattyGWS/HorizonXI-Linux-Installation> — the wiki's official pointer
- <https://github.com/ChrisTitusTech/ashita-ffxi> — the `winefix` + dgVoodoo2 recipe
- `sheik/horizonxi-linux`, `sarca571ca/horizonxi-lutris`, `TeamLinux01/HorizonXI-on-Deck`

The macOS-specific problems (SIP stripping `DYLD_*`, TCC on removable volumes, the wrapper's
dylib rpath) are not covered by any of them.

## Current failure signature

```
[..] Successfully logged in as danielalanbates!
[..] Connected to server!
[..] Closing...
```

No error, no crash dump, exit code 0. What the instrumented traces establish:

| Question | Answer | How |
| --- | --- | --- |
| Is it Ashita? | **No.** Identical failure with Ashita entirely removed | launched `horizon-loader.exe` directly |
| Is it a crash? | **No.** Clean teardown, every DLL gets an orderly `PROCESS_DETACH` | `WINEDEBUG=+seh,+process` — no unhandled exception |
| Does it reach graphics? | **No.** Zero `d3d8` calls, and the game never creates a window | `WINEDEBUG=+d3d,+d3d8,+wgl,+win` — only IME/DDE/OLE helper windows appear |
| How far does it get? | Loads `polcore.dll`, `FFXi.dll`, `FFXiMain.dll`; enumerates and opens every DAT archive `ROM` through `ROM10` | `WINEDEBUG=+file` |
| What is the last thing it does? | Opens and reads `patch.ver`, probes `HKLM\SOFTWARE\PlayOnlineUS\Interface`, then `UnregisterClassA("FFXiClass")` and exits | `WINEDEBUG=+relay` with `RelayFromInclude=FFXiMain.dll;polcore.dll;ffxi.dll` |

`ROM11`–`ROM13` are probed and missing, but they are **not** in the client's own `file.txt`
manifest, so that path is normal and is not the bug.

## Fixes this project found (macOS-specific, not in any Linux guide)

1. **The wrapper's `wineserver` cannot find its own dylibs.** Its rpath is `@loader_path/../../`,
   resolving to `SharedSupport/`, but the dylibs ship in `Contents/Frameworks/`. The usual
   workaround is exporting `DYLD_FALLBACK_LIBRARY_PATH`, which is a trap — see #2. The correct
   fix is to symlink the frameworks into the path the binary actually searches:
   see [`scripts/fix-wine-rpath.sh`](scripts/fix-wine-rpath.sh).
2. **`nohup` and `/bin/sh` are SIP-protected and strip every `DYLD_*` variable.** Any launcher
   built on `DYLD_FALLBACK_LIBRARY_PATH` breaks the moment it is backgrounded or wrapped in a
   shell script — silently, with a `dyld: Library not loaded` that never reaches the user.
   `winetricks` is a `#!/bin/sh` script and hits this. Fix #1 removes the dependency entirely.
3. **Wine resolves a relative exe name against `C:\windows\system32`, not the cwd.** Always pass
   the absolute `C:\...` path.
4. **`reg.exe` writes to the 64-bit registry view.** A 32-bit game reads
   `HKLM\SOFTWARE\Wow6432Node\...`. Registry set up with the 64-bit `reg.exe` is invisible to
   FFXI — use `C:\windows\syswow64\reg.exe`.
5. **`DONTTOUCH_Registry.exe` accepts NSIS `/S`** and completes silently. No GUI click needed.
6. **A wine prefix cannot live on exFAT**, and on a removable volume every process touching it
   needs the TCC "Removable Volumes" grant — which `launchd`-spawned jobs do not have.
7. **Synthetic input (CGEvent) does not reach wine-hosted windows** on this Mac, so any install
   step that needs a GUI click cannot be automated. Prefer silent/CLI equivalents.

## Roadmap

- [x] Login and server connection
- [x] Ashita injection, POL plugins, DAT overlays, macro import from a Windows install
- [ ] **Game window opens** ← blocking everything below
- [ ] `install.sh` — bare prefix to running game, no GUI
- [ ] `HorizonXI-on-Mac.app` — SwiftUI installer/launcher, modelled on
      [`marzent/XIV-on-Mac`](https://github.com/marzent/XIV-on-Mac)
- [ ] Notarised download, install guide, macOS entry on the HorizonXI wiki

## Licence

GPL-3.0, matching `hxiloader` and `XIV-on-Mac`.

Not affiliated with HorizonXI, Square Enix, or the Ashita project.
