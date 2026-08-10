# FINAL FANTASY XI runs natively on Apple Silicon macOS — open beta

*2026-08-09*

HorizonXI runs on an M1 MacBook Pro under Wine. No virtual machine, no Parallels, no Windows
licence. The character logs in, the world loads, Ashita injects, chat is live.

![Murn logged in](img/murn-logged-in-2026-08-09.png)

*Murn — Tarutaru Ninja 75, on the dock in Selbina, on a Mac.*

As far as a full GitHub sweep can tell, this is the first time FFXI has run on macOS this way.
Every other FFXI-on-a-non-Windows-machine project — `Windower/Lumoria`, MattyGWS' guide,
`sheik/horizonxi-linux`, `TeamLinux01/HorizonXI-on-Deck` — is Linux only.

## What you get

- **`HorizonXI-on-Mac.app`** — a launcher with account login, a preflight check for every part of
  the setup that can silently break, one-click prefix repair, graphics settings and a live log.
  Your password goes in the macOS Keychain, never into a config file this project ships.
- **`scripts/install.sh`** — bare Wine prefix to running game, no GUI needed.
- **`docs/FINDINGS.md`** — every dead end with the instrumented evidence behind it, so nobody has
  to re-tread them.

## What was actually wrong

The PlayOnline registry layout is counter-intuitive, and every reasonable guess at it is wrong.
`InstallFolder\0001` must be the **FINAL FANTASY XI** directory, not `PlayOnlineViewer`; POL goes
in `1000`. It has to be written to the **32-bit** registry view, and the three FFXI COM servers
must be registered with `regsvr32 /s` — without `/s` it hangs on a dialog no synthetic click can
reach. HorizonXI ships the correct layout in `SquareEnix/Switch_Horizon.bat`, which is where it
was eventually found. This may be useful to the Linux side too.

## Read this before you try it

**It is slow.** Loading screens take around four minutes on an M1 with 8GB. The cause is measured,
not guessed:

| | |
| --- | --- |
| GPU device utilization | 6% |
| Game CPU | 148% (~1.5 cores) |

The GPU is idle because it is starved. Wine's built-in Direct3D 8 translates every call on one CPU
thread — D3D8 → WineD3D → OpenGL → Metal — and that thread is the ceiling. The fix is removing
translation layers, not "turning on the GPU".

Getting to Metal has been investigated properly and the results are in
[`docs/FINDINGS.md` §9](FINDINGS.md). Three things are now known:

- `Ashita.dll` imports `d3d8.dll` itself, so a native D3D8 shim must sit on **Ashita's** search
  path, not just the game's. Miss that and you get `[E] Injection failed!`, which looks like the
  renderer breaking Ashita and is not.
- This wine build ships **zero `api-ms-win-crt-*` DLLs**, and every renderer DLL imports a dozen
  of them, so none of them can load in a stock prefix. Fifteen working 32-bit forwarders exist in
  the wrapper's own `wine.cx32bak/lib32on64/wine/`.
- **DXVK 2.x/3.x cannot work on Apple Silicon at all**: it requires Vulkan 1.3 and
  `geometryShader`, and Metal has no geometry shaders, so MoltenVK can never expose it. DXVK 3.0.2
  loads, finds the M1, and rejects it.

What is still needed is a **32-bit D3D9-on-Metal/Vulkan** implementation. The wrapper's D3DMetal
is x86_64-only, and its 32-bit `d9vk` will not map (`c0000335`-class load failure) even as a wine
builtin. **This is the single biggest thing standing between here and "actually playable", and
help on it is very welcome — especially from anyone who has built DXVK 1.10.3's `d3d9.dll` for
32-bit macOS.**

Other known limitations:

- Five Ashita plugins (`addons`, `screenshot`, `Nameplate`, `PacketFlow`, `thirdparty`) fail to
  load — built against plugin interface 4.15, this Ashita expects 4.16.
- The `.dmg` is unsigned and un-notarised, so Gatekeeper blocks it on other Macs.
- The client itself (~27GB) and the Wine wrapper are not bundled. You supply both;
  `scripts/Install FFXI on Mac.command` walks you through the rest.
- Only **HorizonXI** is tested. The launcher has buttons for Eden, CatsEyeXI and Nasomi, but
  their login hosts are left blank on purpose rather than guessed at — fill them in from each
  server's own installer.
- Tested on exactly one machine: M1 MacBook Pro, 8GB, macOS 26.5.

## Testers wanted

Especially Apple Silicon Macs with more than 8GB, and Intel Macs, where nobody has tried this at
all. Open an issue with your machine, macOS version, and how long a zone load takes.

Not affiliated with HorizonXI, Square Enix, or the Ashita project.
