# FINDINGS — what is actually true

Consolidated from the 2026-08-07 → 2026-08-08 sessions. This is the *state* document: facts,
measurements, and dead ends. The *forward* document is [`../PLAN.md`](../PLAN.md).
Raw chronological logs live in [`../archive/`](../archive/) and are superseded by this file.

Machine: MacBook Pro **M1, 8GB RAM**, macOS 26.5.2. Internal disk ~14GB free (94% full).

---

## 1. Current status in one table

| Component | State |
| --- | --- |
| Wrapper | `/Volumes/x10/Video Games/Mac HorizonXI/siku.app` |
| Engine | Wine 10.0 (Sikarugir) — matches the Proton 10 Linux users run |
| Active prefix | `siku.app/Contents/SharedSupport/prefix10` (64-bit host, new-WoW64) |
| Client | HorizonXI **1.9.0**, ~27GB extracted (100,976 files) |
| Login | ✅ `Successfully logged in as <your-account>!` / `Connected to server!` — every run |
| Ashita | ✅ 4.3.1.2 injects, all plugins load, **zero errors** in the log |
| POL plugins | ✅ Sandbox, pivot, quicky, extraslots all load |
| DAT overlays | ✅ horizonmusic, horizonoverrides, remapster, xiview |
| Macros | ✅ 172 `mcr*.dat` books across 21 characters, installed |
| **Game** | ❌ `polcore.dll` + `ffxi.dll` + `FFXiMain.dll` all load, then the process exits ~2s later. **No error, no crash dump, zero d3d8 calls.** |
| **GUI launcher** | ❌ 2.0.1 starts, logs `Starting up Launcher v2.0.1`, exits before opening a window |

Murn has **not** been logged in. Everything up to display init works.

## 2. The failure signature, precisely

```
[..] Successfully logged in as <your-account>!
[..] Connected to server!
[..] Closing...
```

- `crashdumps=1` is set; **no dump is produced**.
- `WINEDEBUG=+module` confirms `polcore.dll`, `ffxi.dll`, `FFXiMain.dll` all load.
- `WINEDEBUG=+d3d8` shows **zero calls** — it never reaches display initialisation.
- FFXI's own `FINAL FANTASY XI Config.exe` renders a full GUI window in the same prefix
  (Windowed, 960×600, Ultra), so D3D/GDI/fonts are working.

Both this and the launcher failure are **silent**, which is why they resisted diagnosis.

## 3. Two things the Linux community does that we never did

Found late, and they are the strongest untried levers. Source:
[ChrisTitusTech/ashita-ffxi](https://github.com/ChrisTitusTech/ashita-ffxi) (Ashita v4 on Arch, updated Feb 2025).

1. **`winefix` — an Ashita addon written specifically for running FFXI under Wine.**
   Enabled with `/load winefix` in the profile `.ini`. Distributed via the Ashita Discord / a
   Mega mirror; **not in any public Ashita repo** (checked `AshitaXI/*` — it is not there).
   Our install has **no `addons/winefix`**.
2. **dgVoodoo2 2.8.2** extracted into the **`SquareEnix\PlayOnlineViewer` directory where
   `pol.exe` lives** — *not* the FFXI game directory — with Wine library overrides
   `*d3d8`, `*d3dimm`, `*ddraw` set to native, VRAM 1024MB in `dgVoodooCpl.exe`.
   Our install has **no dgVoodoo2 anywhere**.

Their winetricks set is `corefonts win10 gdiplus dotnet48 vcrun2022`. We installed a genuine
MS VC++ runtime by hand but never `gdiplus` or `corefonts`, and never ran winetricks at all.

**`gdiplus` is a credible direct cause of a silent exit before display init**, and dgVoodoo2 is
explicitly described upstream as being there "to prevent crashes."

## 4. Every fix that was genuinely required to get this far

| # | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| 1 | instant `dyld` crash, `libinotify.0.dylib` not loaded | `wineserver` rpath is `@loader_path/../../` → resolves to `SharedSupport/`, but the dylibs ship in `Contents/Frameworks/` | `export DYLD_FALLBACK_LIBRARY_PATH="$W/Contents/Frameworks:/usr/lib"` + symlinks |
| 2 | same crash returned when detaching | **`nohup` is SIP-protected → macOS strips all `DYLD_*` on exec** | never `nohup`; detach with `setsid` / `start_new_session=True` |
| 3 | wine died between tool calls | parent shell exit killed the process group | proper detachment |
| 4 | "no support for encryption", no TrueType fonts | same rpath bug hiding `libgnutls.30.dylib` / `libfreetype.6.dylib` | same DYLD fix |
| 5 | 82s freeze then clean teardown | **not graphics** — `xiloader` sat at its interactive console prompt with no console attached | run in a real terminal, or pass `--user/--pass` |
| 6 | `Failed to login. Expected xiloader version mismatch` | client was v1.1.2 from a 2023 zip | copied v**1.9.0** `bootloader/`, `plugins/`, `resources/`, `docs/`, `Ashita.dll`, `Ashita-cli.exe`, `version.json` from the VM |
| 7 | `unimplemented function msvcp140.dll.?_Throw_Cpp_error` | Ashita 4.3.1.2 needs a genuine MS VC++ runtime | copied **x86** `msvcp140`/`_1`/`_2`, `vcruntime140`, `concrt140` from the VM's `C:\Windows\SysWOW64` + `native,builtin` overrides |
| 8 | `Failed to initialize instance of polcore!` | outdated `Sandbox.dll` | copied updated POL plugins from the VM |
| 9 | `POL plugin is missing required exports` | 2023 plugin DLLs vs Ashita 4.3.1.2 | copied `Sandbox.dll`, `pivot.dll`, `quicky.dll`, `extraslots.dll` |
| 10 | `pivot => failed` ×4 | `pivot.ini` `root_path` was the VM's `C:\Games\HorizonXI\...` | corrected to `C:\HorizonXI\polplugins\DATs` |
| 11 | pivot overlays missing | only 3 of 4 DAT overlays present | copied **horizonoverrides** (13MB) + **remapster** (404MB) |
| 12 | (silent) | `FFXiMain.dll` differed from the VM (2,890,320 vs 2,896,464 bytes) | copied the VM's `FFXiMain.dll`, `file.txt`, `patch.cfg`, `patch.txt`, `patch2.cfg` — only 5 files in the FFXI root differed |
| 13 | no PlayOnline registry | prefix had none | created `HKLM\Software\PlayOnlineUS\InstallFolder` etc. + `HKCU\...\FinalFantasyXI` video settings |
| 14 | registry installer never ran | `DONTTOUCH_Registry.exe` is an NSIS GUI installer sitting on a License checkbox | **it accepts NSIS `/S` and completes silently** — no click needed; it ran to exit 0 and changed exactly one key (a `SystemInfo\QCheck` timestamp), i.e. the registry was already correct |
| 15 | Electron launcher `ANGLE Could not create D3D11 device` | wine's builtin d3d11 insufficient for ANGLE | installed **D3DMetal** `d3d11.dll`+`dxgi.dll` as `native` (64-bit — fine for Electron, useless for the 32-bit game) |
| 16 | Electron `Error: open EBADF` at `process.getStderr` | **our bug** — Electron's stderr was piped through `grep` | redirect to a real file |
| 17 | launcher 2.0.0 `TypeError: Use delete() to clear values` | upstream bug: `launcherStorage` migration `0.0.0 → 1.1.4` calls `set()` with `undefined` on a fresh profile | writes version `2.0.0` before dying, so it only breaks on **first** run; also avoided by using 2.0.1 |

## 4b. Session 2026-08-08 (evening) — instrumented run, executed

Everything below was actually run, not planned.

**A0 done.** `VM-CONFIG-BACKUP/` (1016 files) is now mirrored to
`iCloud/Backups/HorizonXI-VM-CONFIG-BACKUP` and `brctl download`ed. File count verified equal on
both sides. It is no longer single-copy.

**Fix 18 — the rpath bug is now fixed at the source, not worked around.** 94 dylibs from
`siku.app/Contents/Frameworks/` are symlinked into `SharedSupport/wine/lib/`, which is where the
binaries' rpath actually points. Verified: `wine cmd /c echo %AppData%` now works with **no
`DYLD_*` set at all**. This kills the `nohup`/SIP footgun permanently (FINDINGS §7.3) and is a
prerequisite for O2 — a launcher cannot rely on an env var that SIP deletes. It is also what
unblocked `winetricks`, which is `#!/bin/sh` and was hitting exactly this.

**A1.1 done — `gdiplus` installed** (winetricks, native override). **No change.** The §3
hypothesis that gdiplus is the silent-exit cause is now **disproven**.

**A3.1 done — Ashita is exonerated.** `horizon-loader.exe` launched directly with `--server/--user
/--pass`, no Ashita anywhere: login succeeds, connects, and the process closes ~2s later with the
*identical* signature. **The bug is not in Ashita, not in the addons, and not in the imported VM
config.** A3.2/A3.3/A3.4 are therefore moot and should not be run.

### What the instrumentation actually established

| Instrument | Result |
| --- | --- |
| `+seh,+process,+exception` | **No unhandled exception, no `TerminateProcess`.** Every non-`STATUS_LONGJUMP` exception is one caught `RPC_S_SERVER_UNAVAILABLE`. Exit is a clean, orderly `PROCESS_DETACH` of every DLL. The game *chooses* to exit. |
| `+d3d,+d3d8,+wgl,+win` | Zero d3d8 calls confirmed, and — new — **the game never creates a window at all.** The only `CreateWindowEx` calls are wine's own IME/DDE/`OleMainThreadWndClass` helpers. |
| `+file` | Last file ever touched: **`patch.ver`**, opened *relative* (cwd is temporarily the FFXI dir), read 288 bytes, then `RtlSetCurrentDirectory` back to `C:\HorizonXI\`, then exit. |
| `+reg` | Last registry activity is the FFXI `0000`–`0045` video settings block, then `PlayOnlineUS\DebugPatch` (fails, benign), then `PlayOnlineUS\Interface` (fails). |
| `+relay`, `RelayFromInclude=FFXiMain.dll;polcore.dll;ffxi.dll` | **The decisive trace.** See below. |

### The exact last sequence before death

```
CreateFileA "…/ROM10/FTABLE10.DAT"   → opened          ← ROM..ROM10 all load fine
FindFirstFileA "…/ROM11/FTABLE11.DAT" → GetFullPathNameA  ← failure path, no open
FindFirstFileA "…/ROM12/FTABLE12.DAT" → GetFullPathNameA
FindFirstFileA "…/ROM13/FTABLE13.DAT" → GetFullPathNameA
CreateFileA "patch.ver"               → opened, 288 bytes read
RegOpenKeyExA HKLM "SOFTWARE\PlayOnlineUS\Interface" → 2 (not found)
UnregisterClassA "FFXiClass"
PeekMessageA → CoFreeUnusedLibraries → CoUninitialize → exit
```

Two things this pins down that were previously guesses:

1. **`polcore.dll` is loaded at `0x10000000`**, so the `Interface` probe (`ret=1004a04b`) is
   polcore's, not the game's.
2. **`UnregisterClassA("FFXiClass")` is called but `RegisterClass` never is.** FFXI tears down a
   window class it never created — i.e. its init function bailed *before* window setup and the
   cleanup path runs unconditionally. This is why there is no window and no d3d: it is not a
   graphics failure at all. **dgVoodoo2 (A1.2–A1.4) cannot fix this** and should be deprioritised.

### Ruled out this session

| Hypothesis | Test | Verdict |
| --- | --- | --- |
| `gdiplus` missing is the cause | installed it | **WRONG** |
| Ashita/addons/imported VM config | ran with no Ashita at all | **WRONG** |
| It is a crash or an unhandled exception | `+seh` | **WRONG** — clean voluntary exit |
| It is a graphics/display-init failure | never registers a window class | **WRONG** — dies earlier than that |
| Sound init (last subsystem in the `+reg` trace) | set FFXI registry `0007` (Sound Enabled) = 0 | **WRONG** |
| `patch.ver` version check | moved `patch.ver` away entirely | **WRONG** — identical failure |
| `ROM11`–`ROM13` missing | they are **not in the client's own `file.txt` manifest** | **normal**, not the bug |
| `HKLM\…\PlayOnlineUS\Interface` missing | created it (both registry views) | **WRONG** |
| The 32-bit registry view (`Wow6432Node`) is missing `InstallFolder` | added it with `syswow64\reg.exe` | **WRONG, and actively harmful** — see below |

**Trap worth recording.** `reg.exe` under the 64-bit wine writes the 64-bit view; a 32-bit process
reads `HKLM\SOFTWARE\Wow6432Node\…`. That view genuinely lacks `InstallFolder`, which looks like an
obvious bug. It is not: writing `InstallFolder` into the 32-bit view made things **worse** —
`FFXiMain.dll` then stopped loading at all. `FFXi.dll` evidently prefers that value and cannot
resolve from it. Reverted; baseline restored and re-verified. Do not "fix" this.

### A4 executed — the engine is not the variable

A **second, independent prefix** was built from scratch on the other engine already on disk:
`wine.cx24bak` = **Wine 9.0 (CrossOver 24 sources, free/open — not the paid CrossOver app)**,
at `SharedSupport/prefixcx24n`. The 27GB client was *symlinked*, not copied, so this cost 320MB.

Building it surfaced something the hand-patched `prefix10` had hidden: **FFXI is three COM
in-proc servers, not one.** A clean prefix fails loudly and in sequence —

```
Failed to initialize instance of FFxi!   → CLSID {989D790D-…} = FFXi.FFXiEntry     (FFXi.dll)
                                         → CLSID {1027DC46-…} = FFXiMain.GameMain  (FFXiMain.dll)
                                         → CLSID {3501F5DD-…} = POLCore.POLCoreCom (polcore.dll)
```

`regsvr32` on `FFXi.dll` **hangs** (its `DllRegisterServer` puts up a GUI dialog, and synthetic
input cannot reach wine windows — FINDINGS §7.2). The working method is to lift the 59 relevant
registry sections out of `prefix10/system.reg` and import them; a script that does this is the
first real piece of the O2 installer.

With all three registered, `prefixcx24n` reaches **exactly the same silent close** as `prefix10`.

> **Wine 9.0 (CX24) and Wine 10.0 (Sikarugir) fail identically.** The engine, the engine version,
> and the accumulated hand-patching of `prefix10` are all eliminated in one shot. The failure also
> reproduces in a prefix built clean, which means it is *reproducible* — the A4/M0 requirement.

Also checked and clean: `PlayOnlineViewer/usr/` (the POL account/session blobs) is byte-identical
to the VM backup — no missing session state. `polcore`'s 45 `GetCurrentHwProfileA` calls (a wine
**semi-stub**) all return TRUE and all occur *before* the abort point, so the stub is not the
cause; nor is polcore's `Iphlpapi` interface-stats probe, which resolves every symbol it asks for.

**Daniel has ruled out CrossOver (the paid product).** A5 is struck from the plan. The free
CX-sourced engine above is the substitute and it has now been tried.

### Where that leaves it

The failure is now bounded much more tightly than before: FFXI finishes loading all its game data,
then aborts inside its own initialisation, before any window or graphics work, with no error path
taken. The remaining untried levers are, in order: **Lane B** (Procmon diff against the working VM
install — now the highest-value action, because the trace above gives an exact place to diff), and
**A5** (CrossOver trial). Lane A's remaining sub-items are largely exhausted.

## 5. Hypotheses tested and DISPROVEN — do not re-tread

| Hypothesis | How tested | Verdict |
| --- | --- | --- |
| new-WoW64 breaks the 32-bit game | built a complete true 32-bit prefix (`prefix32`) with WS11WineCX32Bit21.2.0 / `wine32on64` | **WRONG** — identical failure |
| Square Enix binaries can't run under this wine | ran `FINAL FANTASY XI Config.exe` | **WRONG** — renders a full GUI window |
| Windows version too new | prefix set to Win7 (6.1) then WinXP (5.1) | **WRONG** — no change |
| ROM/DAT game data mismatch | sample-compared ROM, ROM2, ROM3, ROM9, sound vs VM | **WRONG** — identical |
| `polcore.dll` outdated | byte-size compare vs VM | **WRONG** — identical (548,352 bytes) |
| polcore registry / `InstallFolder` wrong | see §6 — it is a COM activation, and the CLSID *is* registered | **WRONG** — reframes every `InstallFolder` experiment as a dead end |
| polcore CLSID mismatch (US/EU/JP) | byte-searched all three GUIDs in `horizon-loader.exe` — all present | **WRONG** |
| polcore missing a dependency | `DllRegisterServer` ran and succeeded, so it loads and resolves imports | **WRONG** |
| crash reporter causes the launcher breakpoint | `--disable-crash-reporter`, `--disable-breakpad` | **WRONG** |
| renderer causes the launcher breakpoint | identical crash address under DXMT **and** D3DMetal | **WRONG** |
| SwiftShader would rescue Electron | `--use-angle=swiftshader`, `--disable-gpu`, `--in-process-gpu` | **WRONG** |
| DXVK could supply D3D11 to Electron | installed DXVK `d3d11.dll` | **FAILED** — that DXVK build ships no `dxgi.dll`, so d3d11 won't load at all |

## 6. polcore static analysis (2026-08-08)

`polcore.dll` = `SquareEnix/PlayOnlineViewer/viewer/com/polcore.dll`, 548,352 bytes (an identical
copy sits under `patchfiles/`).

- It is an **ATL COM in-proc server**, not a plain DLL. `horizon-loader.exe` obtains it with
  `CoCreateInstance` — the strings `CoCreateInstance`, `polcore.dll`, `polcoreeu.dll`,
  `Failed to initialize instance of polcore!` and `Failed to initialize instance of FFxi!` are all
  in the loader. So the old failure was a **COM activation failure**.
- It advertises three CLSIDs (`POLCoreCom Class`): `{07974581-…}`, `{3501F5DD-…}`, `{E5966FB3-…}`
  — almost certainly US / EU / JP.
- The prefix registry already has `{3501F5DD-…}` fully registered: `InprocServer32` →
  `C:\HorizonXI\SquareEnix\PlayOnlineViewer\viewer\com\polcore.dll`, `ThreadingModel=Apartment`,
  ProgID `POLCore.POLCoreCom.1`, TypeLib `{3B0B8E16-…}`, under
  `Software\Classes\Wow6432Node\CLSID\…` (the correct 32-bit view).

**This is now historical** — polcore initialises fine in the current prefix. Kept because the
never-run diagnostic below is still the cleanest way to probe COM activation if it regresses:

```bat
rem C:\windows\syswow64\cscript.exe //nologo probe.vbs   — NOT wscript.exe (modal dialog, hangs headless)
Set o = CreateObject("POLCore.POLCoreCom.1")
```

## 7. Environment gotchas — these cost hours each

1. **Wine resolves relative exe names against `C:\windows\system32`, not the cwd**, even when the
   subprocess cwd is set. Produced
   `err:module:process_init L"C:\windows\system32\FINAL FANTASY XI Config.exe" not found`.
   **Always pass the absolute `C:\...` path.** Both `.command` scripts now do.
2. **Synthetic input does not reach wine windows on this Mac.** CGEvent clicks and keystrokes work
   on native apps (Sikarugir Creator, Parallels dialogs) but are ignored by wine-hosted windows,
   even after `NSRunningApplication.activateWithOptions_`. Verified twice, mouse and keyboard.
   **Any wine GUI step must be done by hand** — or driven by a CLI/silent-install equivalent.
3. **`nohup` strips `DYLD_*`** (SIP). Silently breaks the wine wrapper. Use `setsid`.
4. **exFAT cannot host a wine prefix** (no symlinks/permissions). Fine for holding downloads.
5. **x10's root is `root:wheel`** and not user-writable — everything lives under `Video Games/`.
6. **Parallels Standard**: `prlctl resume`, `start`, `stop` are all Pro-only. VM control needs the
   GUI (the Actions menu works via AppleScript menu clicks).
7. **The client is ~27GB extracted**, not the ~12GB the zip implies.
8. **`/Volumes/x10` is TCC "Removable Volumes".** A process without that grant gets a hard
   `Operation not permitted` on every path under it — this persists with sandboxing disabled, so
   it is TCC. **launchd-spawned jobs hold no grants and can do nothing here.** Terminal has Full
   Disk Access, so anything run from Terminal (including this CLI) works.

### TCC route map (settled — stop re-probing)

| Route | Result |
| --- | --- |
| `ls` direct from a launchd job | `Operation not permitted` |
| same with the harness sandbox disabled | `Operation not permitted` — proves TCC, not the sandbox |
| `osascript -e 'do shell script …'` | `Operation not permitted` |
| `tell application "System Events" to do shell script` | `Operation not permitted` |
| `tell application "Terminal" to do shell script` | `Operation not permitted` — runs in the scripting-addition host, inherits nothing |
| `tell application "Finder" to get name of every item of …` | ✅ works, steals no focus — but **listing only** |
| `tell application "Finder" to duplicate … ` | ❌ `-8067` — will not copy contents out |
| `tell application "Terminal" to do script` (new window) | works — but **steals focus** |

Consequence: **unattended launchd ticks cannot make progress on this project.** Run it
interactively from Terminal.

**2026-08-08 17:17 — the resume automation was itself an instance of this.**
`~/Library/LaunchAgents/com.batesai.horizonxi-resume.plist` ran
`…/BatesAI/horizonxi/resume.sh` on `StartCalendarInterval {Minute 7}` with **no `Hour` key**, i.e.
*every hour*, spawning a `horizonxi-resume-worker` → `claude` session each time. Process ancestry
of that worker is `launchd → horizonxi-resume-worker → zsh`, never Terminal, so every tick hit
`Operation not permitted` on `/Volumes/x10` before doing anything. `resume.log` shows the ticks
consuming the Claude session limit hourly (12 transcripts, most dying on "You've hit your session
limit"). **The job has been unloaded.** Re-enabling it as-is cannot work; a resume job must be
launched from Terminal (or from a process that has inherited Terminal's Full Disk Access grant)
to hold the TCC grant. TCC grants are per-binary and cannot be self-assigned from the CLI —
granting one is a manual System Settings step for Daniel. Two `do script` gotchas: it silently fails into the stdin of a tab
with a foreground process (always open a *new* window), and the window must `exit` to close.

## 8. The macro rescue (complete)

HorizonXI macros are **client-side** and are destroyed by an OS wipe — they do not come back on
login. Recovered without booting Windows and without writing anything to the VM:

1. `open <path>.pvm` to resume
2. macOS blocks with *"Parallels Desktop.app would like to access files on a network volume"* —
   **Allow** is mandatory
3. Parallels Mounter → **Read Only**
4. **Partitions do not appear in `/Volumes`.** They mount at `/Volumes/.PEVolumes/PEVolume{uuid}`
   over `smbfs`, read-only + `nobrowse`. Find them with `mount | grep PEVolume`.
5. C: = the volume containing `Windows/`, `Users/`, `Program Files/`

Real install path in the VM, read from the launcher's own `storage.json`:
`C:\Users\daniel\Documents\Horizonxi\HorizonXI\Game`

Recovered to `Mac HorizonXI/VM-CONFIG-BACKUP/`:
`FFXI-USER/` (172 `mcr*.dat`, 21 characters, 6.4MB), `config/`, `scripts/default.txt` (138 lines),
`PlayOnlineViewer-usr/`.

Macros live in `SquareEnix\FINAL FANTASY XI\USER\<charhex>\` as `mcr.dat`/`mcr.sys`/`mcr.ttl` —
**not** in `PlayOnlineViewer\usr`, which only holds account/session blobs.

**Dead end:** the iCloud Google-Drive backup of the HorizonXI install has the complete folder tree
but **zero files**.

## 9. Disk layout

`/Volumes/x10/Video Games/Mac HorizonXI/`

| Path | What | Keep? |
| --- | --- | --- |
| `siku.app/Contents/SharedSupport/prefix10` | **active** Wine 10 prefix, holds the game | yes |
| `…/prefix` | original 64-bit prefix | revert point |
| `…/prefix32` | true 32-bit prefix (wine32on64) — proven not to help | droppable once Lane A closes |
| `…/wine` | Wine 10.0 Sikarugir engine | yes |
| `…/wine.cx24bak` | CrossOver 24 engine | revert point |
| `…/wine.cx32bak` | CrossOver 21 32-bit engine | droppable with prefix32 |
| `VM-CONFIG-BACKUP/` | the rescued macros/config — **irreplaceable** | **back this up off x10** |
| `Play HorizonXI.command`, `wine-here.sh`, `Fix Registry.command` | launch/helper scripts | yes |
| `HorizonXI-Launcher-2.0.0.Setup.exe` + `.nupkg` | 350MB, superseded by 2.0.1 | droppable |
| `HorizonXI/config.stock/`, `scripts/default.txt.stock` | pristine configs | revert points |

`Fix Registry.command` still points at the **old `prefix`**, not `prefix10` — stale, fix or delete.

## 10. Prior art

No macOS effort exists anywhere as of 2026-08-08. Linux only:

- <https://gitlab.com/MattyGWS/HorizonXI-Linux-Installation> — the wiki's official pointer
- <https://github.com/ChrisTitusTech/ashita-ffxi> — **the winefix + dgVoodoo2 recipe**
- `sheik/horizonxi-linux`, `sarca571ca/horizonxi-lutris`, `TeamLinux01/HorizonXI-on-Deck`
- AUR `horizonxi-launcher-bin`

Linux users run the **GUI launcher** (`lib/net45/HorizonXI-Launcher.exe`) on **launcher 2.0.1**
under **Proton-CachyOS 10.0** — a modern Wine, which is what retroactively killed the
32-bit-engine theory. Our xiloader-direct approach was off the supported path entirely.

## 11. Security note

Daniel's password is currently in `config/boot/horizonxi.ini` on the `command` line
(`--user … --pass …`, chmod 600) to enable autologin. Remove those two arguments to disable.
It has never been written to iCloud, a log, or any remote service; the one Ashita log that
captured it was scrubbed.

---

## 9. The Metal renderer investigation (2026-08-09) — why D3D8 is still on OpenGL

The performance problem is **CPU-bound, not GPU-bound**. Measured mid-session:

| | |
| --- | --- |
| GPU device utilization (`ioreg -c IOAccelerator`) | **6%** |
| `horizon-loader.exe` CPU | **148%** (~1.5 cores) |

The GPU is starved. Wine's builtin D3D8 translates on one thread — D3D8 → WineD3D → OpenGL →
Metal. So the goal is deleting translation layers, not "enabling the GPU".

Four things were established, each of which cost a run to find:

1. **`Ashita.dll` imports `d3d8.dll` directly.** With `*d3d8`=native, wine refuses the builtin and
   looks for a native file on *Ashita.dll's* search path. Put the shim only in the game
   directories and you get `err:module:import_dll Library d3d8.dll (which is needed by
   L"C:\HorizonXI\Ashita.dll") not found` → `[E] Injection failed!`. This is what made the first
   two attempts look like "the renderer breaks Ashita". It does not; the DLL was simply not where
   Ashita could see it.

2. **This wine build ships zero `api-ms-win-crt-*` DLLs.** Every modern renderer DLL —
   d3d8to9 (MSVC), DXVK (MinGW), d9vk — imports 12 to 15 of them, so *none of them can load in a
   stock prefix*. `vc_redist.x86.exe` does not help: it carries the VC runtime, not the UCRT
   api-sets. Fifteen working 32-bit forwarders were recovered from the wrapper's own
   `wine.cx32bak/lib32on64/wine/` and copied into `syswow64`, after which DXVK loaded cleanly.

3. **DXVK 2.x/3.x is impossible on Apple Silicon.** With the api-sets in place, DXVK 3.0.2's
   `d3d8.dll` + `d3d9.dll` load and initialise, then:
   ```
   info:  Found device: Apple M1 (MoltenVK 0.2.2209)
   info:    Skipping: Device does not support required feature 'geometryShader'
   warn:  DXVK: No adapters found. ... A Vulkan 1.3 capable setup is required.
   terminate called after throwing an instance of 'dxvk::DxvkError'
   ```
   Metal has no geometry shaders, so MoltenVK cannot expose the feature. This is a hard ceiling,
   not a configuration problem, and it is why Gcenx's macOS DXVK repack is pinned at 1.10.3.

4. **The wrapper's own 32-bit `d9vk` d3d9 will not map at all** — `status=c0000135` from
   `load_dll`, before any of its imports are touched, whether installed as native in `syswow64`,
   next to the executables, or as a builtin in `wine/lib/wine/i386-windows/`. Its import table is
   clean (advapi32, gdi32, kernel32, user32, the api-sets), so the failure is in the module
   itself, not a missing dependency.

### The Metal path — device yes, picture no

**Upstream DXVK 1.10.3's x32 `d3d9.dll` works.** It predates the Vulkan 1.3 requirement, does not
ask for `geometryShader`, maps cleanly, and enumerates the M1. Pair it with `d3d8to9` for the
D3D8→D3D9 hop. (Gcenx's macOS repack of the same version omits `d3d9.dll`; take it from
doitsujin's release instead.)

That alone still failed at `vkCreateDevice` — `err: DxvkAdapter: Failed to create device`, with
`timelineSemaphore : 0`. The cause is the **MoltenVK the wrapper loads by default**: it reports
`Driver 0.2.2209 / Vulkan 1.1.334`. The wrapper ships a second one at
`Contents/Frameworks/moltenvkcx/libMoltenVK.dylib` reporting `Driver 0.2.2018 / Vulkan 1.2.290`.
Repointing `SharedSupport/wine/lib/libMoltenVK.dylib` at that one makes device creation succeed
and the game window appear.

**And then it renders nothing.** The window is created, DXVK reports a live device, the GPU shows
real utilization — and the window stays black. Watched for six minutes; the OpenGL path draws its
splash in about forty seconds and reaches the menu in one to four. Counters on the same scene:

| | builtin D3D8 (OpenGL) | d3d8to9 + DXVK 1.10.3 |
| --- | --- | --- |
| Game CPU | 148% | 11–16% |
| GPU device utilization | 6% | 24–32% |

Those numbers are **not** a speedup. A renderer that never presents a frame is also cheap, and
some of that CPU drop is simply work not being done. Taking the counters as success was the
mistake here; the acceptance test is a visible frame, not a busy GPU.

`d3d9.deferSurfaceCreation = True` — DXVK's own option for exactly this class of wine
presentation failure — was tried and changes nothing; the option is confirmed applied in the log
(`info: d3d9.deferSurfaceCreation = True`) and the window is still black.

Running the whole thing inside a **wine virtual desktop** (`explorer /desktop=hxi,1280x720`),
which changes how the window and its HWND are created and is a known fix for DXVK presentation
elsewhere, also leaves the window black.

So: **unsolved, and reverted.** Three distinct presentation mechanisms tried (plain window,
`deferSurfaceCreation`, virtual desktop); all black. The next moves are bigger than
configuration: build DXVK 1.10.3 from source with a patched macOS presenter, or test the same
D3D8→D3D9 chain under a different wrapper (Whisky, or a newer CrossOver wine) to find out whether
this is DXVK's problem or this wine build's `winemac.drv`. What is genuinely new is that the three blockers above are gone —
the DLLs load, Ashita injects, and `vkCreateDevice` succeeds. What remains is presentation:
getting DXVK's swapchain onto the wine window on macOS. `scripts/install.sh` can still apply the
whole configuration for anyone who wants to attack that (`HXI_METAL=1`, off by default). Backups:
`drive_c/dll-backup/*.builtin.dll` and `wine/lib/libMoltenVK.dylib.stock`.
Backups live in `prefix10/drive_c/dll-backup/`. Note that `reg delete` does not flush to
`user.reg` until `wineserver` exits — kill it before editing, or the change silently persists.

### The reason, found last: the whole wine build is x86_64 under Rosetta

```
$ file siku.app/Contents/SharedSupport/wine/bin/wine
... Mach-O 64-bit executable x86_64
```

Every piece of this stack — `wine`, `wineserver`, the game — is Intel code being translated by
Rosetta 2 on an M1. macOS itself flagged it during this session: *"This version of 'siku' includes
a component that will not work with a future release of macOS."*

That single fact explains the whole session:

- **The OpenGL path is slow** partly because it is Rosetta-translated x86 wine doing the D3D8 →
  OpenGL translation, on one thread. Two translation layers stacked.
- **DXVK creates a device but never presents.** Vulkan→Metal surface and drawable handling from a
  Rosetta process is exactly where MoltenVK is least reliable, and no amount of DXVK configuration
  (`deferSurfaceCreation`, virtual desktop, a different MoltenVK) reaches it.
- **D3DMetal only ships x86_64 DLLs in this wrapper** — consistent with a wrapper built for Intel.

So the fix is not to patch DXVK. **It is a native arm64 wine wrapper.** On arm64 wine, D3DMetal
and DXVK are both known to work, and the Rosetta tax on the CPU side disappears at the same time.
Whisky is not the answer either — it was discontinued upstream (disabled 2026-04-09) and no longer
downloads its wine libraries at all; a bottle created with `whisky create` comes up empty.

Next step, and it needs a decision rather than more experiments: get a native arm64 wine
(Kegworks, or a current CrossOver), build a fresh prefix, and re-run `scripts/install.sh` there.
The client can be symlinked rather than copied — there is not 27GB free on the internal disk.
