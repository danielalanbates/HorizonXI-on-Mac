# Licensing

## This project's own code — MIT

The launcher (`app/`), the scripts (`scripts/`) and the documentation are MIT.

Chosen deliberately for contribution: MIT is the shortest, most familiar and lowest-friction
licence for anyone who wants to fork this, patch it, or ship something built on it, and it is
compatible with essentially everything downstream — including GPL projects that may want to
pull these fixes in. Apache 2.0 was the alternative and carries an explicit patent grant,
which is genuinely useful for a graphics translation project; it was passed over because the
extra ceremony works against "anyone can pick this up", which is the goal here.

## Components we do NOT own, and the terms that actually govern them

Picking a licence for this repo has **no effect** on any of these. We cannot relicense other
people's work, and neither can anyone else who republishes it.

| component | licence | can we redistribute? |
| --- | --- | --- |
| DXVK (and our patches to it) | zlib/libpng | **yes** — patches stay zlib, being derivative |
| d3d8to9 | BSD 3-Clause | **yes** |
| MoltenVK | Apache 2.0 | **yes** |
| wine (upstream, WineHQ) | LGPL 2.1 | **yes** |
| **CrossOver / CodeWeavers builds** | proprietary, commercial | **no** |
| FFXI game data | Square Enix, all rights reserved | **no** — never |

Our DXVK patches in `patches/` are derivative works of DXVK and are therefore **zlib**, not
MIT. That is deliberate: it is also what upstream DXVK requires for contributions, so those
fixes can be submitted without a relicensing problem.

## On "it's on GitHub with an open licence, so it's safe"

It is not, and this is worth being blunt about because the failure mode is expensive.

A LICENSE file is a *claim of ownership*, not proof of it. If someone copies proprietary code
and attaches MIT to it, they had no right to grant that licence, so nobody downstream receives
a valid one. "It said MIT on GitHub" is not a defence — the liability follows whoever ships
the result. A convincing repackage of a commercial product with a permissive licence attached
is the **most** dangerous case, precisely because it looks clean.

The safe test is provenance, not the licence file: does the code trace back to a project that
genuinely owns it?

## Why we do not need a CrossOver substitute at all

CrossOver is CodeWeavers' **commercial distribution of wine** plus proprietary additions.
Wine itself is LGPL 2.1 and free for anyone to use, modify and redistribute.

So the answer is not to find a clone of CrossOver. It is to use **real wine**:

- **WineHQ's official macOS build** (`wine-stable`, currently 11.0) — WineHQ's own release,
  LGPL 2.1, unambiguous provenance.
- Or wine built from source, which is the fully clean option and lets us carry our own patches.

Homebrew marks the official cask as failing the macOS Gatekeeper check. That is a
**notarisation** gap, not a licensing one, and it does not affect us: we sign and notarise our
own `.dmg` with the project's Developer ID anyway.

Things to avoid while shopping for an engine: Kegworks and Wineskin ship *both* pure-wine
engines and CrossOver-derived ones (names containing `CX`, e.g. `WS12WineCX64Bit`). The
pure-wine engines are fine; the `CX` ones are not.

## Current status of the shipped wrapper

**Corrected 2026-08-14.** An earlier version of this file said the wrapper in use (`siku.app`)
was CrossOver-derived. It is not, and that mistake made bundling look blocked when it wasn't.

The wine that actually runs the game is [Sikarugir](https://github.com/Sikarugir-App/Sikarugir)
wine 10.0 — an open-source Wineskin fork of upstream WineHQ, **LGPL 2.1**. `wine --version`
reports `wine-10.0 (Sikarugir)`, the binaries carry no CodeWeavers strings, and `ntdll.so`
carries upstream wine's new-WoW64 strings rather than CodeWeavers' `wine32on64`.

The wrapper *does* contain CrossOver leftovers — `Frameworks/moltenvkcx/`,
`SharedSupport/wine.cx32bak/`, `SharedSupport/prefixcx24/` — but nothing in the live path loads
any of them, and they are excluded from any package (and can be deleted outright, reclaiming
about 845 MB). Evidence and md5s: [`docs/BUNDLING.md`](docs/BUNDLING.md).

So every component in the live stack is redistributable, and bundling for a public beta is a
packaging job — LGPL source/relink obligations for wine, nothing more. Tracked in
`docs/PHASE2-PACKAGING.md`.
