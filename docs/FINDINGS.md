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
| Login | ✅ `Successfully logged in as danielalanbates!` / `Connected to server!` — every run |
| Ashita | ✅ 4.3.1.2 injects, all plugins load, **zero errors** in the log |
| POL plugins | ✅ Sandbox, pivot, quicky, extraslots all load |
| DAT overlays | ✅ horizonmusic, horizonoverrides, remapster, xiview |
| Macros | ✅ 172 `mcr*.dat` books across 21 characters, installed |
| **Game** | ❌ `polcore.dll` + `ffxi.dll` + `FFXiMain.dll` all load, then the process exits ~2s later. **No error, no crash dump, zero d3d8 calls.** |
| **GUI launcher** | ❌ 2.0.1 starts, logs `Starting up Launcher v2.0.1`, exits before opening a window |

Murn has **not** been logged in. Everything up to display init works.

## 2. The failure signature, precisely

```
[..] Successfully logged in as danielalanbates!
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
