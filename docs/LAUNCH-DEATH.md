# Launcher Play dies ~1s after "Connected to server!" (2026-08-19) — SOLVED

## Symptom
Pressing Play in the launcher: injector runs, xiloader logs in, prints
`Connected to server!`, then `Closing...` one second later and the game exits
cleanly (exit 0, no crash log). The **same** invocation run by hand from a
Terminal shell reached character select every single time. Started after the
wine wrapper moved to the x10 (spinning) drive.

## What was ruled out (all verified, not guessed)
- Environment: launcher dumped its exact spawn (exe/args/cwd + all 58 env vars)
  to `last-spawn.txt`; replaying it verbatim from a shell **worked**.
- `WINE_LARGE_ADDRESS_AWARE`, `FFXI_FPS_DIVISOR`: tested manually, both fine.
- x87 sidecar, stray wineserver/sidecar processes: disabled/killed, still died.
- Ashita Sandbox `use_interface_bypass` (the old silent-exit cause): unchanged.

## Root causes (two, both needed)
1. **Foundation `Pipe` on the child's stdout.** Spawning through
   `/bin/sh -c 'exec ... >> file 2>&1'` with a file redirect — byte-identical
   otherwise — survived every time, while the `Process`+`Pipe` spawn died every
   time. Fix: `Runner.spawnViaShell` — shell spawn, stdout/stderr to a temp
   file, a 0.3s DispatchSource timer tails the file into the log pane. A pipe
   can never be re-introduced here.
2. **`wineserver -k` returned before the server actually died.** The fixed
   1.5s sleep in `RendererSetup` covered the registry flush on the SSD but not
   on the x10; a game spawned while the old server was still dying got torn
   down with it. Fix: `wineserver -w` (blocks until real termination), bounded
   at 30s.

## Verification
Fresh install of the fixed launcher into /Applications/FFXI-on-Mac.app,
`--play`: game passed the old death point, reached the FFXI login/agreement
screen (screenshot verified), horizon-loader alive minutes later. Repeated
once more on the final binary.

## If it regresses
- Confirm nothing reattached a pipe to the game's stdio.
- Check whether the launch races a dying wineserver (`wineserver -w` timing).
- The one-shot env-dump diagnostic (removed) can be re-added in
  `Runner.spawn` — see this file's git history for the snippet.
