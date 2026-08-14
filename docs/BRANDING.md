# Where the HorizonXI branding comes from

Written 2026-08-14, because the obvious answer is wrong and someone will otherwise try it twice.

Daniel plays the local **LandSandBoat** server through this install, and the client still shows the
HorizonXI logo on the login screen and HorizonXI's wording in the menus. It should show the stock
Square Enix ones — LSB ships no branding of its own, so "the LandSandBoat version" *is* stock.

## What it is not

The install has an XIPivot DAT-overlay stack, configured in
`config/pivot/pivot.ini`, and two of the four overlays are HorizonXI's:

    [overlays]
    0=horizonmusic          <- HorizonXI's music replacements (1.3 GB with the rest)
    1=horizonoverrides      <- 29 DAT files
    2=remapster             <- third-party UI mod, not server branding
    3=xiview                <- third-party UI mod, not server branding

Disabling the two HorizonXI overlays is the obvious fix, and it does not work. Tested: rewrote
`pivot.ini` to load only `remapster` and `xiview`, launched, and confirmed from Ashita's log that
the change took effect —

    pivot | addOverlay: 'remapster'
    pivot | addOverlay: 'xiview'

— and the login screen still shows the HORIZON XI logo, unchanged.

## What it is

The branding is baked into the base client DATs that HorizonXI's own installer wrote, under
`SquareEnix/FINAL FANTASY XI/ROM*`. The overlay mechanism is layered *on top of* an already-branded
client, so removing the overlay reveals more branding rather than less.

File dates *do* narrow it down, which is the useful part of this note. The bulk of the tree —
50,260 DATs — carries one timestamp, 2023-08-15, the client build HorizonXI started from.
**1,973 DATs under `ROM/` are newer than that**, and those are the ones HorizonXI wrote:

    128 each in ROM/376 .. ROM/382     a whole added content block
     ~80 each in ROM/17,18,22,24       and neighbours
       5 in ROM/0, 17 in ROM/1, 9 in ROM/2

`ROM/0` holds the menu and title resources, and its five modified files stand out further:

    ROM/0/4.dat   ROM/0/5.dat   ROM/0/6.dat   ROM/0/7.dat   ROM/0/12.DAT

Four of the five are **lowercase `.dat` among uppercase `.DAT` siblings** — the signature of files
replaced by hand rather than by the game's own patcher. `ROM/0/12.DAT` is a menu DAT that the
`xiview` overlay also overrides, which is consistent.

That is where to look for the login logo first. It is a strong lead, not a confirmed answer: no
one has opened these files yet.

## What would actually replace it

XIPivot works — `xiview`'s overrides are visibly being applied in the same log — so the mechanism
for replacing a DAT is already installed and proven. What is missing is the replacement file:

1. Identify which DAT holds the login logo and the branded menu strings. Nothing in this repo
   knows that yet; it is a search through the ROM tree by content, not by name.
2. Supply a stock version of it. **This project has no stock DATs** — the only client on this
   machine is HorizonXI's — and game data is Square Enix's and is never redistributed here, so it
   has to come from the user's own untouched retail install, or the texture has to be authored.
3. Drop it into `polplugins/DATs/<name>/ROM/.../n.DAT` and add `<name>` to `pivot.ini`.

Step 2 is the real blocker, and it is a question for Daniel rather than a thing to solve quietly:
either point at a stock install to copy from, or accept an authored replacement image.

## If it is done, do it per profile

`pivot.ini` is global, one file for the whole install, while the branding should differ between
the HorizonXI profile (branded, as that server intends) and the local LSB profile (stock). The
launcher already rewrites `[ffxi.registry]` per boot profile before launching, from
`Graphics.swift`; the same shape works here — write `pivot.ini` at launch based on which world is
selected. Nothing in the launcher does this yet.
