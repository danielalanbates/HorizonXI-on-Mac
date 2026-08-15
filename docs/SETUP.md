# Setting up — the plain-English version

No Terminal, for most people. Three things have to be on your Mac, and the launcher tells you
which one is missing at any moment — and builds one of the three for you.

## What you need

| Piece | Where it comes from | Roughly |
| --- | --- | --- |
| **FFXI on Mac** (this launcher) | the `.dmg` on the releases page | 5 MB |
| **A Wine wrapper** | the launcher builds it — press **Install wine…** | ~250 MB download |
| **The HorizonXI game client** | HorizonXI's own installer, run through **Install the game…** | ~27 GB |

The last two are not *in* the download itself, and that is deliberate rather than laziness:

- The **game client** is Square Enix's data. Nobody may redistribute it, so you get it from your
  server's own installer (details below).
- The **Wine wrapper** is built from Wine's own upstream releases (Sikarugir, LGPL 2.1). Shipping
  a pre-built copy inside this app would mean taking on Wine's LGPL relink obligations properly
  rather than as an afterthought, so instead the launcher fetches it fresh and assembles it on
  your Mac the first time you ask it to. That takes about five minutes, once, and needs nothing
  from you but a click and (for Rosetta) your Mac password.

Anyone offering you one file with all three in it is redistributing Square Enix's client, which
they may not do.

## Installing Wine — press the button

Open **FFXI on Mac** with nothing installed yet, and the main screen offers **Install wine…**
directly. Press it and the launcher does four things, showing each as it finishes:

1. **Rosetta 2** — Apple's translation layer; FFXI is a 32-bit Intel game. Installed automatically
   if it's missing, via the normal system password prompt.
2. **Downloading Wine** — two files, about 250 MB total, fetched from
   [Sikarugir](https://github.com/Sikarugir-App/Sikarugir)'s own GitHub releases (a template `.app`
   and a wine engine). The engine is checked against a pinned SHA-256 before anything is built
   from it.
3. **Building the wrapper** — the two pieces are unpacked into each other at
   `~/Applications/FFXI on Mac Wine.app`, and Wine's internal library paths are fixed up so it
   runs from that location.
4. **Creating the Windows drive** — `wineboot` sets up a blank `drive_c`, ready for the game.

When all four are green you have a working Wine wrapper and nothing left to configure. This is the
same Wine build the manual route below produces — Sikarugir, the successor to Wineskin, an
ordinary open-source build of Wine (LGPL 2.1). It is not CrossOver and costs nothing.

If a step fails partway through, press **Install wine…** again — completed steps are skipped, so
it picks up where it stopped rather than starting over.

## Installing Wine by hand

Only worth doing if the button above fails and you want to see each piece yourself, or if you're
troubleshooting the wrapper the app built (it lives at the same place either way:
`~/Applications/FFXI on Mac Wine.app`, or older manual installs under `~/Applications/Sikarugir/`).

A "wrapper" is just a Mac app with Wine and a Windows C: drive inside it. You make one once, put
FFXI in it, and never think about it again. Every step below was done on this Mac in about ten
minutes, most of it waiting on downloads.

The Wine used here is [Sikarugir](https://github.com/Sikarugir-App/Sikarugir) — the successor to
Wineskin, an ordinary open-source build of Wine (LGPL 2.1). It is not CrossOver and costs nothing.

### 1. Install Homebrew, if you do not have it

Paste this into Terminal (Applications → Utilities → Terminal) and press Return:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Rosetta 2

FFXI is a 32-bit Windows game from 2002, so an Apple Silicon Mac needs Apple's translation layer:

```sh
softwareupdate --install-rosetta --agree-to-license
```

### 3. Install Sikarugir

```sh
brew trust Sikarugir-App/sikarugir
brew install --cask Sikarugir-App/sikarugir/sikarugir
```

That puts **Sikarugir Creator** in your Applications folder.

> **`sikarugir.com` is not this project.** The real one is the GitHub organisation linked above.
> Sikarugir's own README tells anyone who arrived from that domain to scan their Mac for malware.

### 4. Make the wrapper

Open **Sikarugir Creator**. The window has three parts: a template on the left, an engine in the
middle, a **Create** button on the right.

1. Under *No engine selected*, click **Change**.
2. Pick **`WS12WineSikarugir10.0_6`** — the top entry, and the exact build this project is tested
   on. It downloads about 160 MB, which takes a minute; the arrow next to it disappears when it
   has finished, and then you click the name again to select it.
   **Do not pick anything with `CX` in the name.** Those are CrossOver-derived and commercial.
3. **Create** turns blue. Click it.
4. It asks where to save. Type **`FFXI`** and press Return. Leave the location alone — the default
   is `~/Applications/Sikarugir/`, which is one of the places the launcher looks.

Wait a minute or two. When it finishes you have `~/Applications/Sikarugir/FFXI.app`, about 1.4 GB.
That is your wrapper. It is empty — Wine and a blank Windows drive, no game yet.

Nothing to configure. Close Sikarugir Creator; you are done with it.

## Installing the game

FFXI itself comes from the server you intend to play on. HorizonXI's installer downloads about
9.4 GB over BitTorrent and unpacks to roughly 27 GB, so start it before you do anything else and
leave it running.

You have two ways in:

**Press Install the game… in the launcher.** With a Wine wrapper already built (by the button
above, or by hand), the main screen offers this once nothing is found. Point it at HorizonXI's
Windows installer `.exe` and the launcher runs it inside the wrapper it manages — no separate
Sikarugir window to find.

**Or run the server's installer inside the wrapper directly.** If you built the wrapper by hand,
double-click your `FFXI.app` wrapper — it opens Sikarugir's own window with an **Install
Software** button. Point that at the `.exe` you downloaded and let it run. It behaves like a
Windows PC from there.

**Or copy an install you already have.** Drag the whole `HorizonXI` folder off a Windows machine
into:

```
~/Applications/Sikarugir/FFXI.app/Contents/SharedSupport/prefix/drive_c/
```

To get there in Finder: right-click `FFXI.app` → *Show Package Contents* → `SharedSupport` →
`prefix` → `drive_c`. Drop the folder in so you end up with `drive_c/HorizonXI`.

Either way, when the game files are in place, open **FFXI on Mac** and it finds the wrapper on its
own. If it doesn't, open **Setup & Diagnostics** — it names the exact thing it could not find.

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
2. **Press Install wine…** if nothing is found. Four steps, all automatic: Rosetta 2, downloading
   Wine, building the wrapper, creating the Windows drive. See above.
3. **Press Install the game…** and point it at your server's Windows installer — or, if you
   already have a wrapper from elsewhere, copy an existing `HorizonXI` folder into
   `<wrapper>/Contents/SharedSupport/prefix*/drive_c/` by hand. The launcher also looks in
   `/Applications`, `~/Applications` and every mounted volume on its own, so an existing install
   is usually found without either step.
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
