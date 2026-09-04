# Which wine the game runs under

**The wrapper's own wine kills the client one second after login. Use the patched CrossOver wine.**

Measured 2026-08-21, same prefix, same boot profile, same 66-variable environment, twice each:

| wine | result |
| --- | --- |
| `siku.app/Contents/SharedSupport/wine/bin/wine` (the Sikarugir wrapper's own) | "Successfully logged in" → **"Closing..." one second later**, process gone |
| athei/wine-build `wine-cx-26.3.0-1` | logs in, reaches the world, runs indefinitely (58 fps) |

The wrapper's wine announces `err:environ:init_peb starting L"C:\HorizonXI\Ashita-cli.exe" in
experimental wow64 mode`, which the patched build does not; that is the likeliest culprit but has
not been isolated further, because the fix costs one line and the isolation does not.

This is the same *symptom* as the 2026-08-19 launch-death (docs/LAUNCH-DEATH.md, fixed by
`spawnViaShell` + `wineserver -w`) and a different cause — that one was about how Foundation wired
the child's stdio, this one is about which wine binary runs. Both had to be fixed for Play to work.

## What the launcher does

`X87Sidecar.patchedWine()` returns the installed runtime whether or not x87 acceleration is on.
Preflight blocks Play when it is absent, and `Runner.launch` refuses direct `--play` calls too.
The launcher never substitutes the incompatible wrapper Wine.

**So the patched game Wine is no longer optional.** It arrived as an x87 experiment; it is now the
only Wine that plays. First-run setup downloads the pinned 194 MB archive, verifies SHA-256
`ec2a9e4d438917a26e381c01367773df79c3b0d6f0504b8183464619cad7e661`, and installs the runtime
under Application Support. It is over 1 GB unpacked, so it is not part of the app bundle.

## `--play` works again, with one condition

`--play` had done nothing since it was written, and the reason turned out to be two separate
things:

1. It failed silently. Every failure path in `play()` set `notice`, which is `@State` read back in
   the same synchronous scope — so it still read empty and nothing was logged. Those paths now log
   to the run log as well, and `Runner.tee` mirrors the log to stderr for `--check`/`--play`.
2. **It must be started through `open`, not by running the binary.** Launched straight from a
   shell, the client comes up with no window driver at all:

       err:macdrv:macdrv_init Failed to start Cocoa app main loop
       err:winediag:nodrv_CreateWindow The explorer process failed to start.

   That is the "no window, no log" symptom recorded against `--play` for weeks. Use:

       open -a /Applications/FFXI-on-Mac.app --args --world HorizonXI --play

   Verified 2026-08-21: logs in, draws, and stays up.
