# Goals — as stated by Daniel, 2026-08-10

Recorded verbatim in intent so future sessions (human or AI) work to the same target.
Ordering below is the order Daniel set: **GPU first, announcement last.**

## 0. Hard gate — GPU rendering (blocks everything else)
> "before we post on horizonxi we need to get it working with gpu support though"

The shipped path burned ~193% CPU with the GPU at 4–8%. Nothing ships, and nothing is
announced, until the game is genuinely GPU-rendered.

- [x] Get the game onto a real GPU pathway
- [x] Measure it (FPS, GPU%, CPU%) and prove it in-world, not just at the menu — `docs/MAX4K.md`
- [x] Make it *smooth*, not merely GPU-backed — 43–47 fps in-world at 4K max, 2026-08-14

## 1. Run as smoothly as possible
> "Get the game running as smoothly as possible on my Mac. Take no prisoners."

Target machine: MacBook Pro M1, 8 GB. Zone loads used to take minutes — that is the bar to beat.

## 2. Finish the launcher
- [x] Standard **login name + password** fields (the Horizon launcher has them)
- [ ] Look and feel much closer to the real HorizonXI launcher
- [ ] **FFXI-themed and coloured** — fun, not utilitarian
- [ ] **Server dropdown** covering other FFXI private servers
  - HorizonXI is always the top choice
  - the rest ranked by population, ranking held behind the scenes (not shown as numbers)
- [ ] Cover the other things the real Horizon launcher does (updates, settings, news)

## 3. One-click bundle for non-technical users
> "bundle all the dependencies into a package for a less computer-literate user to download
> and try on their own"

A single downloadable artefact. No Terminal, no Homebrew, no manual wine steps.

## 4. Phase 2 — open beta
- [ ] Post a notice on the HorizonXI repo showing the launcher exists and works
- [ ] **Only after** the GPU gate above is genuinely met

## Standing working rules for this project
- Verify with **screenshots/video, pixel-accurate** — counters lie. Captures run in the
  background, and on the **HP 24uh** when it is connected.
- Prefer an existing upstream project to build from; open PRs upstream where the work belongs.
- Multiple pathways to the same goal in parallel; keep whichever measures best.
- Everything that does not work goes to `archive/` with a note on why.
- No personal information in git — credentials live only in gitignored files.
- Document thoroughly for the next AI to continue.
