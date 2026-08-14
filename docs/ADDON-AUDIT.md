# Addon audit, 2026-08-14

Daniel reported that many of these addons glitched badly for him on Windows 11 Pro ARM, so every
addon enabled in `scripts/default.txt` was compared against its upstream source.

## Method

Each addon declares `addon.name / author / version / desc` in the first few lines of its Lua
entry point. The installed copy's version and MD5 were compared against upstream:

- **[AshitaXI/Ashita-v4beta](https://github.com/AshitaXI/Ashita-v4beta)** — the bundled addons
- **[ThornyFFXI/mobdb](https://github.com/ThornyFFXI/mobdb)**, **[MiscAshita4](https://github.com/ThornyFFXI/MiscAshita4)** — Thorny's
- **[WinterSolstice8/nolock](https://github.com/WinterSolstice8/nolock)**

## Result

**13 of 18 were byte-identical to upstream** — they are current, and whatever went wrong on
Windows 11 ARM was not a stale copy: `allmaps`, `chatmon`, `checker`, `clock`, `distance`,
`filterless`, `fps`, `instantah`, `macrofix`, `nocombat`, `petinfo`, `recast`, `tparty`.

Three were behind and have been updated (originals backed up to
`~/Library/Application Support/HorizonXI-on-Mac/addon-backups/<timestamp>/`):

| addon | was | now | source |
| --- | --- | --- | --- |
| `links` | 1.0 | 1.1 | Ashita-v4beta |
| `mobdb` | 1.25 | 1.26 | ThornyFFXI/mobdb |
| `nolock` | 1.0.0 | 1.0.0, newer code | WinterSolstice8/nolock |

`mobdb` was updated file-by-file rather than replaced wholesale, because the install carries an
extra `import_custom.lua` that upstream does not ship. Nothing references it — it is an orphan
developer script with a hard-coded `C:\Ashita 4\...` path — so it was left alone rather than
deleted.

Two could not be matched to a public repo and were left untouched: `chains` 0.84 (Sippius, Ivaar,
NerfOnline — HorizonXI's own, not published separately as far as a GitHub search can tell) and
`timers` 1.0.3.3 (Lunaretic, Shiyo, The Mystic). Thorny's `tTimers` is a different, actively
maintained addon and is on HorizonXI's approved list, if `timers` keeps misbehaving.

## The thing that is actually broken

`addons/skillchain/` contains `chains.lua` and `Skillchains.lua` but **no `skillchain.lua`**.
Ashita loads `addons/<name>/<name>.lua`, so `/addon load skillchain` can never succeed no matter
what else is fixed. The working equivalent is `addons/chains/`, which is on HorizonXI's approved
list — use `/addon load chains`.

## Two plugins that cannot load at all

`Nameplate` and `PacketFlow` are enabled in `default.txt` and are compiled against Ashita plugin
interface **4.15**, while the Ashita core in this install expects **4.16**. Both are refused at
load with a clear error in the client log. They are HorizonXI's own builds and are only published
inside their 9.4 GB base archive, so there is nothing to update them from here. Anything relying
on them will not work, and that is worth knowing before blaming an addon.

## Descriptions in the launcher

The addon screen now shows each addon's own `addon.desc`, author and version, read out of the
installed Lua header at scan time. They are not written into this project, so they cannot drift
from what is actually installed. Plugins are DLLs with no readable metadata block; three carry a
usable description string in the binary (`Deeps`, `Screenshot`, `Thirdparty`) and the rest have a
one-line summary written here only where the plugin's job is unambiguous. Anything else shows no
description rather than a guess.
