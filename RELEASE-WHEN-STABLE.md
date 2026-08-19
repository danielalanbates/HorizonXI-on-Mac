# Standing instruction: ship an official release once the client is definitively stable

**From Daniel, 2026-08-17. This is a standing directive, not a one-off task.**

Whenever the HorizonXI-on-Mac client reaches a state that is *definitively stable*,
roll out an official release. Do not wait to be asked again — the ask has already been
made, permanently, right here.

## What "definitively stable" means
Not "it launched once." All of these, verified, not assumed:

- Client boots to the world reliably across several consecutive cold launches (no
  crash before addons load, no silent exit).
- Mouse works: cursor visible in-window, and addon/ImGui windows can be hovered and
  clicked. See `docs/MOUSE.md` — the click path still has an open rough edge
  (`io.MousePos` reading ImGui's -FLT_MAX sentinel) that must be closed first.
- No Wine window can end up unclosable (the `winedbg --auto` reaper is in the launch
  path; `scripts/quit-wine.sh` works).
- Frame rate holds at the project's max-settings target — never benchmark or ship with
  reduced effects, use `scripts/max.json` / `max4k.json`.
- A normal play session survives without needing manual intervention.

## What rolling out a release means
1. Confirm `/Applications/FFXI-on-Mac.app` is the single current build and is playable.
2. Archive every prior version/build out of the active tree first — keep exactly one
   current version live.
3. Fold the working fixes out of the diagnostic addon into their own proper addon.
   Right now the cursor fix and the shell->game command channel both live inside
   `mousediag`, which is a debug tool, not a shipping component.
4. Tag and cut a GitHub release with real notes covering what changed and what is
   still known-broken. There is NO release cadence (the old "roughly weekly" rule is
   gone, per Daniel 2026-08-19): a release goes out only when the launcher is
   extremely stable and vetted — every criterion above verified fresh, and several
   real play sessions on the current build without a single manual intervention.
   Rare, well-vetted releases beat frequent ones.
5. Say plainly in the notes what was verified and what wasn't. No "works" claims that
   were not actually tested.

## Why this note exists
This project has repeatedly reached a good state mid-session and then lost it to the
next round of experiments. Cutting a release at the stable point is what makes the
good state recoverable.
