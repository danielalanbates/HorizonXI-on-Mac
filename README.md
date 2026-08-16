# FFXI on Mac

Play Final Fantasy XI on an Apple Silicon Mac. No Windows, no virtual machine, no Boot Camp.

You get a normal Mac app: press **Install wine…**, press **Install the game…**, type your account
name and password, pick your server, press **Play**.

<div align="center">

### [⬇️ Download FFXI on Mac 2.6 (.dmg)](https://github.com/danielalanbates/HorizonXI-on-Mac/releases/download/v2.6/FFXI-on-Mac-2.6.dmg)

[![Download](https://img.shields.io/badge/Download-FFXI%20on%20Mac%202.6-2ea44f?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/danielalanbates/HorizonXI-on-Mac/releases/download/v2.6/FFXI-on-Mac-2.6.dmg)

5 MB · Apple Silicon · macOS 13 or later · signed and notarised by Apple, so it just opens

</div>

That file is the whole setup now. There's no Homebrew, no separate Wine app to install, no engine
to pick from a list — the launcher fetches and builds its own Wine wrapper the first time you press
**Install wine…**. You still need the game client itself, explained in
[What you need](#what-you-need) below. Figure five to ten minutes the first time, mostly spent
waiting on downloads.

![Murn in Selbina](docs/img/murn-in-selbina.png)

It works with **HorizonXI**, CatsEyeXI, Eden and other FFXI private servers, and it can also run
a server on your own Mac if you want to play offline.

---

## Is it good enough to actually play?

Yes, with one caveat: it is not a smooth 60 fps game.

| Measured on an M1 MacBook Pro, 8 GB | Frame rate |
| --- | --- |
| Out in the world, every setting maxed at 4K | ~24 fps |
| Out in the world, max settings (benchmark zone) | ~28 fps |

That's playable for questing, crafting, chatting and most party content. If you want to know why
it isn't faster, the whole investigation is written up in [`docs/MAX4K.md`](docs/MAX4K.md) — short
version: the game itself pauses waiting on the graphics card, and it is not something the Mac side
can skip without breaking the game.

More powerful Macs (M2/M3/M4, more memory) have not been tested yet. **If you have one, please
try it and open an issue with your numbers** — that is the single most useful thing anyone can
contribute right now.

---

## What you need

Three pieces. The app tells you which one is missing at any moment, and builds one of the three
for you.

| Piece | Size | Where it comes from |
| --- | --- | --- |
| **FFXI on Mac** (this app) | 5 MB | the Releases page here |
| **Wine** | ~250 MB download | the app fetches and builds it — press **Install wine…** |
| **The FFXI game client** | ~27 GB | your server's own installer, run through **Install the game…** |

Neither of the last two is in the download itself. The client is Square Enix's data and nobody
may redistribute it, so you install it through your server's own installer. Wine is free and open
source (Sikarugir, LGPL 2.1) — the app downloads it from Sikarugir's own GitHub releases and
assembles it into a wrapper on your Mac, so you never touch Homebrew, a cask, or Sikarugir Creator
yourself. If anyone offers you a single file with all three in it, they are handing out Square
Enix's client, which they may not do.

**What these servers are:** HorizonXI, CatsEyeXI and Eden run
[LandSandBoat](https://github.com/LandSandBoat/server) or a fork of it — an open-source server
written independently, containing none of Square Enix's code. It needs Square Enix's *client*,
which is why they all make you install the real game. Square Enix has not licensed or endorsed
any of it; these communities have simply run openly for years while retail FFXI sits in
maintenance mode. This project redistributes no Square Enix data at all.

## Setting it up

1. **Install the app.** Open the `.dmg`, drag *FFXI on Mac* to Applications, open it. It's signed
   and notarised by Apple, so no right-click-to-open trick needed.
2. **Press Install wine…** With nothing installed yet, the launcher offers this straight on its
   main screen. It installs Rosetta 2 if needed, downloads Wine from Sikarugir's GitHub releases
   (~250 MB), assembles the wrapper, and creates a blank Windows drive — four steps, shown as they
   go green. No Terminal, no Homebrew, no picking an engine off a list.
3. **Press Install the game…** Point it at your server's Windows installer and let it run inside
   the wrapper the app just built — or copy an existing `HorizonXI` folder from a Windows PC into
   the wrapper's `drive_c` by hand. Detail in
   [Installing the game](docs/SETUP.md#installing-the-game).
4. **Type your account name and password.** Tick *Remember me* and they go into the macOS
   Keychain — never into a file, never into this repo.
5. **Press Play.**

Stuck? Open **Setup & Diagnostics** in the app. Every check names the exact file or setting it
couldn't find, and **Repair** re-runs the whole setup for you.

**"FFXI on Mac would like access to Developer Tools"** — you may see this macOS prompt the first
time the app starts Wine. It is Apple's wording for *"this app wants to run a program that
isn't from an identified developer"*: the Wine binaries come from Sikarugir's GitHub releases and
are ad-hoc signed, not notarised, so macOS asks before letting a notarised app run them. Allow
it. The app doesn't touch Xcode or anything else under that heading; the permission is exactly
"may run Wine". Terminal shows the same prompt for the same reason.

### Doing it by hand

If the buttons fail, or you want to see each piece, this is everything the app does. Ten minutes,
mostly downloads. Everything below is free and open source; the only non-free thing involved is
the game client, which comes from your server.

1. **Rosetta 2** (FFXI is a 32-bit Windows game; Apple Silicon needs the translation layer).
   In Terminal (Applications → Utilities):
   ```sh
   softwareupdate --install-rosetta --agree-to-license
   ```
2. **Homebrew**, if you don't have it:
   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
3. **Sikarugir** (Wine for macOS, LGPL — the successor to Wineskin; *not* `sikarugir.com`, which
   is unrelated to the real project):
   ```sh
   brew trust Sikarugir-App/sikarugir
   brew install --cask Sikarugir-App/sikarugir/sikarugir
   ```
4. **Make the wrapper.** Open *Sikarugir Creator* → under *No engine selected* click **Change** →
   pick **`WS12WineSikarugir10.0_6`** (the build this project is tested on; nothing with `CX` in
   the name, those are CrossOver-derived) → wait for its download arrow to vanish, click the name
   again → **Create** → name it `FFXI`, keep the default location. Result:
   `~/Applications/Sikarugir/FFXI.app` (~1.4 GB, empty Windows drive inside).
5. **Put the game in it.** Either double-click `FFXI.app` → **Install Software** → your server's
   Windows installer `.exe` and let it run; or drag an existing `HorizonXI` folder from a Windows
   PC into `FFXI.app/Contents/SharedSupport/prefix/drive_c/` (right-click the app → *Show Package
   Contents*). HorizonXI's installer pulls ~9.4 GB by torrent and unpacks to ~27 GB.
6. **Metal renderer (optional but recommended).** The app's **Renderer** menu does this for you;
   by hand, copy `vendor/d3d8to9.dll` as `d3d8.dll` and `vendor/dxvk-1.10.3-x32-d3d9-horizonxi.dll`
   as `d3d9.dll` into both `drive_c/HorizonXI/` and `drive_c/HorizonXI/SquareEnix/FINAL FANTASY XI/`,
   then in the wrapper: `wine reg add "HKCU\Software\Wine\DllOverrides" /v "*d3d8" /d native /f`
   and the same for `*d3d9`. Details: [`scripts/install.sh`](scripts/install.sh) is the exact
   sequence Repair runs.
7. **Register the game's COM servers** (Repair does this too):
   `wine regsvr32 /s "C:\HorizonXI\SquareEnix\FINAL FANTASY XI\FFXi.dll"` and likewise
   `FFXiMain.dll`, `FFXiVersions.dll`, and
   `"C:\HorizonXI\SquareEnix\PlayOnlineViewer\viewer\com\polcore.dll"`.
8. Open **FFXI on Mac**; it finds the wrapper. If not, **Setup & Diagnostics** names what's missing.

### Where the game lives, and other worlds

The app itself can live anywhere — Applications, a USB stick, your Desktop; everything it runs
ships inside it. The game data is separate and big (a full client is ~27 GB), so **you choose
where it goes**, per world, the first time you pick a world that isn't installed yet: the app
shows a *Game data* card with **Download…** and **Choose folder…**. Any drive is fine, external
included; the wrapper stays small and is shared by every world. The choice is remembered per
world.

Pick the world from the **CHANGE WORLD** menu; the app writes that server's login host into its own
Ashita boot profile and keeps your account per world. How each world's client is obtained is
different, because each community distributes it differently — the app does whichever applies:

| World | Download… does | Then |
| --- | --- | --- |
| HorizonXI | fetches their client the way their launcher does — a 9.4 GB torrent + their updates (needs `brew install aria2`) | Play |
| CatsEyeXI | runs **CatsEyeXI's own launcher** inside the wrapper; it installs their client into the folder you chose | Play |
| Eden, FFEra, Gaia XI, ValhallaXI | opens their download page — each ships a Windows installer/launcher | run it in the wrapper (**Setup & Diagnostics → Install the game…**), then **Choose folder…** |
| Supernova, OmicronXI | opens their guide — both are *bring-your-own retail client* + their patch/DATs | **Choose folder…** at your retail install |
| Tabula Rasa XI | nothing — their site is offline (2026-08); Discord only | — |

**Client version.** Each server insists on a minimum retail patch level of the FFXI client and
answers an older one with *"The game's data has been updated. Please update to continue."* The
app checks this before Play and tells you both numbers. HorizonXI's updates are public and the
app applies them; other servers ship theirs only through their own launcher, which is why the
CatsEye route runs theirs.

Status of the CatsEye route, honestly: their launcher opens and renders inside the wrapper, but
in testing its **Continue** button did not respond to automated clicks — a real mouse hasn't been
tried yet. If it works for you, please say so in an issue; if it doesn't, the fallback is to run
their launcher on any Windows machine and copy the `catseyexi-client` folder to the folder you
chose.

## Addons

Ashita addons work — HXUI, statustimers, the usual set. The app's **Addons** screen only shows you
the ones your server actually allows, and names where that list came from. On HorizonXI an
unapproved addon can get you banned, so this matters more than it sounds.

Three plugins still don't load: `Nameplate`, `PacketFlow` and `Deeps`. They were built against an
older version of Ashita than the one shipped here, so you'll see red "different interface version"
lines in the log at startup. Harmless — everything else loads. Details and the fix we're waiting
on: [`docs/ADDONS.md`](docs/ADDONS.md).

## Running your own server

Pick **Local server** in the World dropdown and press **Set up server**. The app installs the
tools it needs and builds [LandSandBoat](https://github.com/LandSandBoat/server) on your Mac —
about half an hour and 12 GB of disk the first time. After that, pressing Play starts the server
and the game together. You still need the FFXI client; a server isn't a game.

## Troubleshooting

**The game window opens and closes right away.** Almost always the prefix configuration. Hit
**Repair** in Setup & Diagnostics.

**Red plugin errors when the game starts.** Expected — see Addons above.

**It won't find my wrapper.** The wrapper has to be a `.app` on an APFS or HFS+ volume. A Wine
prefix cannot live on an exFAT drive, and won't work from one.

**The world looks black or untextured.** Make sure the renderer is set to *Metal / DXVK
(recommended)*. The other options are there for debugging and are known to draw incorrectly.

Anything else — [open an issue](../../issues). Include your Mac model, macOS version, your server,
and what the log pane says.

## Helping out

This has been tested on exactly one Mac. Useful contributions, roughly in order:

- **Frame rates from other Macs.** Model, memory, macOS version, where you were standing.
- **Servers other than HorizonXI.** Login hosts, addon rules, anything that didn't work.
- **Bug reports with the log pane contents.** The log usually says exactly what went wrong.
- **Code.** See [`CONTRIBUTING.md`](CONTRIBUTING.md).

Questions are welcome, including basic ones. Nobody here was born knowing what a Wine prefix is.

## Under the hood

For anyone curious, or working on something similar — the technical record lives in `docs/`:

- [`docs/X87-WALL.md`](docs/X87-WALL.md) — the big one. FFXI's floating-point math ran at ~1% of
  native speed under Rosetta. Fixing that took the game from 11 fps to 28.
- [`docs/MAX4K.md`](docs/MAX4K.md) — where the remaining frames go, and the fast trick that turned
  out to break the game.
- [`docs/FINDINGS.md`](docs/FINDINGS.md) — why the game exited silently for weeks, and the dozen
  things that looked like the cause and weren't.
- [`docs/ADDONS.md`](docs/ADDONS.md), [`docs/BRANDING.md`](docs/BRANDING.md),
  [`docs/PATHWAYS.md`](docs/PATHWAYS.md) — addons, title-screen art, and the three renderers
  compared.

Building it yourself needs only Apple's Command Line Tools:

```sh
./app/bundle.sh          # build the .app
./scripts/package.sh     # build the .dmg
```

Tested on: MacBook Pro M1, 8 GB, macOS 26.5, Wine 10.0 (Sikarugir), HorizonXI client 1.9.0,
Ashita 4.3.1.2. The **Install wine…** button itself has only been verified up through a working
`drive_c` — its wiring into a totally empty-Mac first run has not yet been driven end-to-end by
a real user.

## Credits

Standing on other people's work: [Ashita](https://github.com/AshitaXI),
[DXVK](https://github.com/doitsujin/dxvk), [d3d8to9](https://github.com/crosire/d3d8to9),
[MoltenVK](https://github.com/KhronosGroup/MoltenVK),
[x87sidecar](https://github.com/athei/x87sidecar),
[LandSandBoat](https://github.com/LandSandBoat/server), and the HorizonXI team.

## Licence

GPL-3.0. Third-party components and their licences: [`vendor/NOTICE.md`](vendor/NOTICE.md).

Not affiliated with HorizonXI, Square Enix, or the Ashita project. Final Fantasy XI is a trademark
of Square Enix Holdings Co., Ltd.
