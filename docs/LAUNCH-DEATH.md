# Launcher Play dies ~1s after "Connected to server!" (2026-08-19) — IN PROGRESS

## Symptom
Pressing Play in the Finder-launched launcher: injector runs, xiloader logs in,
prints `Connected to server!`, then `Resolving host: macbookpro.lan` and
`Closing...` one second later. Exit 0, no crash log, no visible error.
Started after the wine wrapper moved to the x10 (spinning, external) drive.

## What is PROVEN
- The same launcher binary, launched from a Terminal shell (`nohup .../FFXI-on-Mac --play`),
  runs to the FFXI login screen every time. Verified repeatedly with screenshots.
- Launched via `open` / Finder (launchd parent), it dies at the same point every time.
- Environment is NOT the difference: the spawn env was dumped from both contexts and
  matched variable-for-variable (58 vars).
- The Foundation-`Pipe`-on-stdout and `wineserver -k` race fixes (commit a273e99) are
  real improvements but were NOT the root cause — the GUI launch still died after them.
- `--hairpin` on horizon-loader did not change the behavior (still resolves
  macbookpro.lan, still dies).
- The x87 sidecar, stray processes, and the Ashita sandbox setting are not involved.

## Root-cause theory (strong, not yet closed)
The difference between the two contexts is the **responsible process for macOS
permissions**. Terminal holds grants the app identity lacks:
1. **Removable volume access** (x10): the app prompts for this ("would like to access
   files on a removable volume") and Daniel kept having to re-approve — because every
   ad-hoc rebuild changes the app's code signature, which resets TCC. This gates the
   whole game dir but is granted-when-approved, so it explains popups, not the death.
2. **Local Network**: xiloader binds/hairpins through the machine's LAN address
   (`macbookpro.lan`) at exactly the death point. Terminal is in
   Privacy & Security → Local Network; the launcher never appears there and never
   prompts — macOS silently denies unsigned/ad-hoc apps. This matches the death.

## Signing findings (important gotchas)
- `codesign --deep` breaks x87sidecar_entitled (strips its debugger entitlement). Use
  app/bundle.sh's per-file signing, never --deep.
- Developer ID + `--options runtime` (hardened runtime) makes wine's dlopen of
  ntdll.so fail with "file system sandbox blocked open()" — the wrapper's files carry
  `com.apple.provenance` xattrs and hardened processes refuse them. So the LOCAL
  install must be signed WITHOUT hardened runtime. (Notarized DMG builds keep runtime;
  they ship the launcher only, not the wrapper.)
- Current /Applications app: signed Developer ID (team MG4YW8XX2Z), NO hardened
  runtime, sidecar re-signed with its entitlements. This gives a STABLE TCC identity:
  the x10 popup should need approving ONCE more and then stick across rebuilds —
  as long as rebuilds are signed with the same identity (HXI_SIGN_ID hash in
  package.sh comments).

## Next steps (blocked ~45min on 2026-08-19 because another automation session owns the screen)
1. Launch Play from Finder with the stable-identity build; approve the x10 popup once.
2. If it still dies post-connect, check Privacy & Security → Local Network for an
   "FFXI on Mac" row (signed apps register properly; toggle it on). If no row appears,
   flip Terminal's Local Network toggle OFF and run the manual spawn — if that dies the
   same way, Local Network is proven; escalate (options: helper LaunchAgent with its own
   identity, or ship with proper signing + one manual toggle).
3. Once GUI Play works, consider signing bundle.sh's default local build with the
   Developer ID (no runtime) so ad-hoc identity churn never comes back.
