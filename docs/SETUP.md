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

- The **game client** is Square Enix's data. Nobody may redistribute it. You install it with
  HorizonXI's own Windows installer, or copy an install you already have.
- The **Wine wrapper** used here is derived from CrossOver. Redistributing that has licence
  implications this project has not cleared, so the launcher points at a wrapper you supply
  rather than shipping one.

Anyone telling you they have a one-file download containing all three is redistributing something
they should not be.

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
