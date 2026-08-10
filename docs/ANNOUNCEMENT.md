# Open beta announcement — draft

Not posted anywhere yet. HorizonXI has no public GitHub org that accepts issues from outside
contributors, so the realistic channels are, in order of likely reach:

1. **The HorizonXI Discord** — the `#technical-support` / `#community-projects` channels are where
   the Linux install guides got picked up. This is where an announcement actually lands.
2. **The HorizonXI wiki** — <https://horizonxi.com/wiki> has an installation section that links
   MattyGWS' Linux guide. A macOS entry alongside it is the natural home.
3. **`Windower/Lumoria` or `AshitaXI` GitHub issues** — relevant only if we want the tooling
   projects aware of it, not for players.

Decide the channel before posting; the text below is written for the Discord/wiki.

---

## FINAL FANTASY XI runs natively on Apple Silicon macOS — open beta

We got HorizonXI running on an M1 MacBook Pro under Wine, with no virtual machine, no Parallels,
and no Windows licence. Character logs in, world loads, Ashita injects, macros work.

As far as we can tell this is the first time FFXI has run on macOS this way — every other
FFXI-on-a-non-Windows-machine project we could find (`Windower/Lumoria`, MattyGWS' guide,
`horizonxi-linux`, `HorizonXI-on-Deck`) is Linux only.

**What's in the box**

- `HorizonXI-on-Mac.app` — a launcher with account login, a preflight check for every part of the
  setup that can silently break, a one-click prefix repair, and graphics settings.
- `scripts/install.sh` — turns a bare Wine prefix into a working install with no GUI needed.
- `docs/FINDINGS.md` — every dead end, with the instrumented evidence, so nobody re-treads them.

**What was actually wrong** (in case it helps the Linux side too)

The PlayOnline registry layout is counter-intuitive and every reasonable guess at it is wrong.
`InstallFolder\0001` must be the *FINAL FANTASY XI* directory, not `PlayOnlineViewer`; POL goes in
`1000`. It has to be written to the 32-bit registry view, and the three FFXI COM servers must be
registered with `regsvr32 /s` — without `/s` it hangs on a dialog. HorizonXI ships the correct
layout in `SquareEnix/Switch_Horizon.bat`, which is where we eventually found it.

**Known limitations — please read before trying it**

- **It is slow.** Wine's built-in Direct3D 8 runs through OpenGL on macOS, which is the slowest
  path available. Loading screens take minutes on an M1/8GB. We tried routing D3D8 through
  d3d8to9 + DXVK to reach Metal and it broke Ashita injection; that work is ongoing and is the
  single biggest thing standing between this and "actually playable".
- Five Ashita plugins (`addons`, `screenshot`, `Nameplate`, `PacketFlow`, `thirdparty`) fail to
  load — they are built against plugin interface 4.15 and this Ashita expects 4.16.
- The build is unsigned and un-notarised, so Gatekeeper will block it until we sort that out.
- Tested on exactly one machine: M1 MacBook Pro, 8GB, macOS 26.5.

**Testers wanted**, particularly on Apple Silicon Macs with more than 8GB, and on Intel Macs where
nobody has tried this at all.

Repo: <https://github.com/danielalanbates/HorizonXI-on-Mac>

Not affiliated with HorizonXI, Square Enix, or the Ashita project.
