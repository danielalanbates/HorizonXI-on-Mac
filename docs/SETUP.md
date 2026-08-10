# Setting up — the plain-English version

No Terminal. Three things have to be on your Mac, and the launcher tells you which one is
missing at any moment.

## What you need

| Piece | Where it comes from | Roughly |
| --- | --- | --- |
| **HorizonXI on Mac** (this launcher) | the `.dmg` on the releases page | 5 MB |
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

1. **Install the launcher.** Open the `.dmg`, drag *HorizonXI on Mac* to Applications, and open
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

**Leave this on Classic (OpenGL)** unless you are helping debug. It is the only setting that
draws the game correctly. It is also slow — about 3 frames per second in a zone on an M1 with
8 GB — and that is the honest state of this project today.

The other two options are faster and visibly broken, in different ways. The launcher says which
under each one, and [`PATHWAYS.md`](PATHWAYS.md) has the measurements and the reasons.

## Which server

The **World** dropdown lists the FFXI private servers this project knows about, HorizonXI first.
Only HorizonXI is verified here — its login host is the one that has actually been tested. For any
other server, fill in the login host from that server's own installer; the field appears under the
dropdown as soon as you pick an unverified world.
