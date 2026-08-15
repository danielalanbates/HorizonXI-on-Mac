# Setting up — the plain-English version

No Terminal. Three things have to be on your Mac, and the launcher tells you which one is
missing at any moment.

## What you need

| Piece | Where it comes from | Roughly |
| --- | --- | --- |
| **FFXI on Mac** (this launcher) | the `.dmg` on the releases page | 5 MB |
| **A Wine wrapper** | see below | ~1 GB |
| **The HorizonXI game client** | HorizonXI's own installer | ~27 GB |

The last two are not in the download, and that is deliberate rather than laziness:

- The **game client** is Square Enix's data. Nobody may redistribute it, so you get it from your
  server's own installer (details below).
- The **Wine wrapper** is ~1 GB on its own, and shipping a copy means taking on Wine's LGPL
  obligations properly rather than as an afterthought. Bundling it is planned; today you install
  it yourself, and it takes about five minutes.

Anyone offering you one file with all three in it is redistributing Square Enix's client, which
they may not do.

## Installing Wine

The Wine used here is [Sikarugir](https://github.com/Sikarugir-App/Sikarugir) — the successor to
Wineskin, and an ordinary open-source build of Wine (LGPL 2.1). It is not CrossOver and costs
nothing.

```sh
brew trust Sikarugir-App/sikarugir
brew install --cask Sikarugir-App/sikarugir/sikarugir
```

If you do not have Homebrew, paste the one-line installer from <https://brew.sh> first. Apple
Silicon Macs also need Rosetta 2 — `softwareupdate --install-rosetta --agree-to-license` — because
FFXI is a 32-bit x86 game.

Then open Sikarugir, create a new blank wrapper, and let it fetch a Wine engine. Anything from
**wine 10.0 or newer** works; this project is tested on `wine-10.0 (Sikarugir)`.

Two warnings worth repeating:

- **`sikarugir.com` is not the project.** The real one is the GitHub organisation linked above.
  The Sikarugir team's own README tells anyone who arrived from that domain to scan for malware.
- **If you use Kegworks or Wineskin instead, pick a pure-Wine engine, not a `CX` one.** Engines
  with `CX` in the name (e.g. `WS12WineCX64Bit`) are CrossOver-derived and commercial.

Once the wrapper exists, the launcher finds it on its own.

## Installing the game

FFXI itself comes from the server you intend to play on — the private servers each ship an
installer that downloads the client (HorizonXI's is about 9.4 GB over BitTorrent, and unpacks to
roughly 27 GB). Run that installer inside the Wine wrapper, or copy a `HorizonXI` folder from a
Windows PC into `<wrapper>/Contents/SharedSupport/prefix*/drive_c/`.

**A word on what these servers are**, since the wording elsewhere has been muddled: private
servers like HorizonXI, CatsEyeXI and Eden run [LandSandBoat](https://github.com/LandSandBoat/server)
or a fork of it — an open-source, independently written server that speaks FFXI's network
protocol. It contains none of Square Enix's code. What it *needs* is Square Enix's client, which
is why every one of them makes you install the real game rather than handing you a repack.

Square Enix has not licensed or endorsed any of this. These communities have run openly for
years, and retail FFXI has been in maintenance mode for a long time, but "long tolerated" is not
the same as "permitted", and this project does not claim otherwise. What it does claim is
narrower and firm: **no Square Enix data is redistributed here.** You supply the client.

## Steps

1. **Install the launcher.** Open the `.dmg`, drag *FFXI on Mac* to Applications, and open
   it. The download is signed with a Developer ID and notarised by Apple, so it opens with no
   warning and no right-click trick.
2. **Point it at your wrapper.** The launcher looks in `/Applications`, `~/Applications` and every
   mounted volume for a `.app` containing a Wine build and a HorizonXI client. If you have one, it
   finds it on its own and the dot at the bottom right turns to *ready to play*.
3. **Install the game** if you have not: run HorizonXI's Windows installer inside the wrapper, or
   copy an existing `HorizonXI` folder into `<wrapper>/Contents/SharedSupport/prefix*/drive_c/`.
4. **Type your account name and password**, tick *Remember me* if you want them kept — they go
   into the macOS Keychain, never into a file in this project.
5. **Press PLAY.**

If something is missing, open **Setup & Diagnostics** — every check names the exact file or
setting it could not find, and **Repair** re-runs the whole prefix configuration.

## Choosing a renderer

**Leave this on Metal / DXVK (recommended).** It draws the game correctly — full textures, fog,
UI — at around 24 fps in the world at 4K with every setting maxed on an M1 with 8 GB.

The other options are there for debugging and draw the game wrong in various ways. The launcher
says how under each one, and [`PATHWAYS.md`](PATHWAYS.md) has the measurements and the reasons.

## Which server

The **World** dropdown lists the FFXI private servers this project knows about, HorizonXI first.
Only HorizonXI is verified here — its login host is the one that has actually been tested. For any
other server, fill in the login host from that server's own installer; the field appears under the
dropdown as soon as you pick an unverified world.

## Running your own server

Picking **Local server** in that dropdown means not logging into anyone else's world: the launcher
builds [LandSandBoat](https://github.com/LandSandBoat/server) on this Mac and the client connects
to `127.0.0.1`. You still need the FFXI client itself — a server is not a game.

Press **Set up server** and the launcher will, in order: install Apple's command line tools and
Homebrew if they are missing, `brew install` LandSandBoat's dependencies (cmake, luajit, zeromq,
openssl, mariadb, pkgconf), clone the source, create the database and import the schema, and
compile the four server processes. Budget half an hour or more the first time. Every step is
skipped if it is already done, so if it stops you press the button again rather than starting over.

**Disk space.** It needs about 12 GB — roughly 5 GB of source and git history, 3 GB of build
output, and headroom for the database and the compiler's temporaries. The launcher shows what is
free before you start and refuses to begin a build below 9 GB, because running the disk to zero
half way through a compile is a worse failure than not starting one.

After setup, **Play** starts the server if it is not already up, then launches the client. The
first login with a new account name creates that account.

Everything lives in `~/Games/lsb`, and all of it is the shell script
[`scripts/lsb-server.sh`](../scripts/lsb-server.sh) — run `./lsb-server.sh status|setup|start|stop`
by hand if you would rather watch it work in a terminal.

Two things this changes about the client, both only in your local copy: the server accepts the
xiloader version that ships with the HorizonXI client rather than the newer one LandSandBoat
expects, and the client-version lock is turned off. Both are needed for a client built for one
server to talk to another, and neither is something you would do to a server other people use.
