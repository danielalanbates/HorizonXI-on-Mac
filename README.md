# FFXI on Mac

Play Final Fantasy XI on an Apple Silicon Mac. No Windows, no virtual machine, no Boot Camp.

You get a normal Mac app: type your account name and password, pick your server, press **Play**.

**[Download FFXI on Mac 2.5](https://github.com/danielalanbates/HorizonXI-on-Mac/releases/latest)**
— 3 MB, signed and notarised by Apple. Apple Silicon, macOS 13 or later.

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

Three pieces. The app tells you which one is missing at any moment.

| Piece | Size | Where it comes from |
| --- | --- | --- |
| **FFXI on Mac** (this app) | 5 MB | the Releases page here |
| **Wine** | ~1 GB | free, two Homebrew commands — [instructions](docs/SETUP.md#installing-wine) |
| **The FFXI game client** | ~27 GB | your server's own installer |

Neither of those two is in the download. The client is Square Enix's data and nobody may
redistribute it. Wine is free and open source (Sikarugir, LGPL 2.1) — bundling it is planned, and
for now you install it yourself in about five minutes. If anyone offers you a single file with
all three in it, they are handing out Square Enix's client, which they may not do.

**What these servers are:** HorizonXI, CatsEyeXI and Eden run
[LandSandBoat](https://github.com/LandSandBoat/server) or a fork of it — an open-source server
written independently, containing none of Square Enix's code. It needs Square Enix's *client*,
which is why they all make you install the real game. Square Enix has not licensed or endorsed
any of it; these communities have simply run openly for years while retail FFXI sits in
maintenance mode. This project redistributes no Square Enix data at all.

## Setting it up

1. **Install the app.** Open the `.dmg`, drag *FFXI on Mac* to Applications, open it. It's signed
   and notarised by Apple, so no right-click-to-open trick needed.
2. **Let it find your wrapper.** It searches `/Applications`, `~/Applications` and any connected
   drive for a Wine wrapper containing an FFXI install. When it finds one, the dot in the bottom
   corner turns to *ready to play*.
3. **Install the game** if you haven't already — run your server's Windows installer inside the
   wrapper, or copy over a `HorizonXI` folder from a Windows PC.
4. **Type your account name and password.** Tick *Remember me* and they go into the macOS
   Keychain — never into a file, never into this repo.
5. **Press Play.**

Stuck? Open **Setup & Diagnostics** in the app. Every check names the exact file or setting it
couldn't find, and **Repair** re-runs the whole setup for you.

Longer walkthrough: [`docs/SETUP.md`](docs/SETUP.md).

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
Ashita 4.3.1.2.

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
