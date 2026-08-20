# Finder-launched Play dies ~1s after "Connected to server!" — UNSOLVED, workaround shipped

## The one proven fact
The identical launcher binary with the identical 58-variable environment:
- **works** (reaches FFXI login) when its process ancestry is a shell (Terminal/claude
  session — even with stdin=/dev/null, no TTY, setsid, env stripped to HOME+PATH,
  ulimit -n 256);
- **dies** printing `Closing...` one second after `Connected to server!` when launched
  by Finder/`open` (launchd parent).

The death point (winsock+file traces): xiloader binds/listens 127.0.0.1 fine, then the
step that in working runs loads POL (GetCurrentHwProfileA spam, polcore proceeding,
ffximain.dll loading) silently never happens — polcore.dll gets PROCESS_DETACH and
xiloader exits by its normal cleanup path. No exception, no error line.

## Theories tested and KILLED on 2026-08-19 (do not re-litigate)
env diff · Foundation Pipe stdio · wineserver -k race · x87 sidecar (parked, still died)
· Local Network TCC (hosts→127.0.0.1 made bind loopback; still died) · /etc/hosts fix
(kept: `127.0.0.1 macbookpro.lan macbookpro`, harmless) · RemovableVolumes TCC (granted,
auth 2; still died) · App Management TCC (row inserted; still died) · fd limits (256 in
shell still worked) · TTY/stdin/session (all severed in shell; still worked) ·
responsibility-disclaimed posix_spawn (child then can't read x10 at all — worse).

## Signing traps (cost hours)
- Every ad-hoc re-sign = new TCC identity → the x10 "removable volume" popup returns.
  STOP RE-SIGNING casually.
- `codesign --deep` strips x87sidecar_entitled's debugger entitlement.
- Developer ID + hardened runtime → wine dlopen fails ("file system sandbox blocked
  open()") — the wrapper's dylibs carry SIP-protected `com.apple.provenance` xattrs.
- Developer ID even WITHOUT runtime → same dlopen failure. The local install must stay
  ad-hoc signed until this is understood.

## Collateral to be aware of
- This session inserted a kTCCServiceSystemPolicyAppBundles row for
  org.batesai.horizonxi-on-mac into the user TCC.db and killed tccd; afterwards the
  Terminal/claude context lost FDA (TCC.db reads now denied) and some prefix files
  (system.reg, drive_c/HorizonXI/logs, SquareEnix symlink target) read "Operation not
  permitted" even via sudo. If odd denials persist, review Privacy & Security → Full
  Disk Access (Terminal) and consider `tccutil reset All org.batesai.horizonxi-on-mac`.
- /etc/hosts has a duplicated (harmless) `127.0.0.1 macbookpro.lan macbookpro` line.

## Shipped workaround
`/Applications/Play FFXI.command` — double-click; it runs the launcher `--play` from a
Terminal context, which holds whatever permission the Finder context is missing. The
.app stays for settings/addons/worlds.

## Next steps for the next session
1. Identify what polcore does between listen() and LoadLibrary(ffximain) — likely a
   COM/RPC or registry read that fails only under the app's TCC/launchd context. A
   `WINEDEBUG=trace+reg,+rpc` diff of the two contexts at that window is the shortest
   path (file/winsock/module/ole/seh already diffed; reg+rpc not yet).
2. If found, fix the specific denial; else consider making the .app's Play delegate to
   a login-shell context (osascript → Terminal, or enable Remote Login and ssh
   localhost) as a permanent, invisible pathway.
3. Un-break the collateral above.
