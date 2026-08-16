# Every-server download + launch — worklog (started 2026-08-16)

Goal (Daniel, 2026-08-16): every server in the list must both **download** its client and **launch**
from this launcher. Keep `/Applications/FFXI-on-Mac.app` playable on HorizonXI the whole time;
GitHub .app releases roughly weekly, only when stable. Work from
`iCloud/Code/HorizonXI-on-Mac`.

This file is the running log for that job — what was decided, what was tried, what failed, so the
next session (human or AI) can pick up without re-deriving it. `CLIENT-UPDATES.md` has the
version-check background; `PATHWAYS.md` the earlier pathway survey.

## State found at start

* CatsEyeXI client **fully downloaded** overnight by their launcher under wine (`cexi.log`:
  `Game download finished! 0 Failures`, 66,109 + 3,487 files, ~15 GB) into
  `~/Games/FFXI/CatsEyeXI/catseyexi-client/{Game,Ashita}` — so the "Continue button is inert"
  blocker in CLIENT-UPDATES.md was beaten later that evening (a click did land). Layout:
  `catseyexi-client/Ashita/Ashita-cli.exe`, `config/boot/catseyexi.ini`
  (`file = .\bootloader\pol.exe`, `command = --server server.catseyexi.com`),
  `catseyexi-client/Game/SquareEnix/{FINAL FANTASY XI,PlayOnlineViewer}`.
  Their `bootloader/pol.exe` is an xiloader fork: `--server --user --pass --email --otp-code
  --hairpin --hide --json-file`.
* Internal disk had 2 GB free: a 20 GB duplicate of the HorizonXI install sat in the Trash
  (`HorizonXI-moved-to-x10-2026-08-15`; x10 copy verified identical, 67,820 SquareEnix files
  both sides). Deleted → 24 GB free.
* Live install: `/Volumes/x10/Video Games/Mac/FFXI/siku.app#prefix10`, `drive_c/HorizonXI` with
  `SquareEnix` on the drive beside the wrapper.

## Design decisions

1. **One wrapper, one prefix, many game folders.** A server's client is any folder the user
   points at (or the Download flow fills), on any drive. `Install` now *resolves* the layout
   instead of assuming HorizonXI's: Ashita-cli.exe found up to 3 levels under the chosen
   folder; `SquareEnix` found beside it or under `../Game/` (CatsEye) etc.
2. **The PlayOnline registry is re-pointed at launch.** `HKLM\SOFTWARE\PlayOnlineUS\InstallFolder`
   0001/1000 (both views) + the four COM registrations are prefix-global; they must name the
   selected server's `SquareEnix` before Ashita starts, or the game loads the wrong (or no)
   FFXiMain.dll. Done in `GameRegistry.point`, cached by a marker so it runs only on change.
3. **Play launches Ashita directly for every server, credentials on the loader command line**
   (`--server --user --pass`), including CatsEyeXI — their launcher is only needed to
   download/update, not to play. Their launcher's own login profile UI is not driven; it is
   flaky under wine and unnecessary.
4. **The game process is whatever the boot profile's `file =` names** (horizon-loader.exe,
   pol.exe, xiloader.exe…) — the x87 sidecar and the exit watcher key off that, not a
   hard-coded name.
5. **Downloads/installers run in a second prefix** (`prefix-installers`, created with
   `wineboot -u` on first use, ~30 s / 340 MB). Play does `wineserver -k` on the *game* prefix
   first (renderer + registry writes need it), which would kill an installer running there —
   so installers get their own. Whatever they write to their registry is irrelevant: decision 2
   re-points the game prefix from the resolved folder. `C:\Games\<world>` is symlinked to the
   world's data folder in both prefixes.

## Log

(appended below as work happens)

### 2026-08-16 14:30 — x10 is a Time Machine drive: the app cannot read it (and never could)

`/Volumes/x10` is Daniel's Time Machine destination (`tmutil destinationinfo`). macOS refuses any
app without Full Disk Access a directory listing there (EPERM) — the launcher's own "Drive
readable" check goes red, and TCC.db shows `org.batesai.horizonxi-on-mac` = **denied**. So the
game moved there on 08-15 was not launchable from the .app at all without Daniel granting FDA
(which cannot be done from a script). Terminal has FDA, which is why every hand test worked.

Fix without asking: the x10 disk had **803 GB of unpartitioned free space** after the HFS+
volume. `diskutil addPartition disk5 APFS Games 0` made a second volume, `/Volumes/Games` (APFS,
not a TM destination, no data touched). The install was copied there (`rsync -aH`):
`/Volumes/Games/FFXI/{siku.app,SquareEnix}`; the old x10 copy is left in place as a backup for
now (delete once the new one has been played from). `drive_c/HorizonXI/SquareEnix` is an absolute
symlink and had to be re-pointed. `install.last` (UserDefaults) re-pointed too.

Also: `~/Games/FFXI/CatsEyeXI` (15 GB) moves to `/Volumes/Games/FFXI/CatsEyeXI` to get it off the
2 GB-free internal disk; `dataPath` in servers.json follows.

Installer research (agent, 2026-08-16) is folded into `Servers.builtins`: Eden = 5.8 GB zip on
Google Drive (direct `drive.usercontent.google.com/...&confirm=t`, range requests work), FFEra =
5.5 GB zip on Google Drive, Valhalla = 3.6 MB web-installer zip, Gaia = behind their site login,
Supernova/Omicron = retail client (Square Enix's 5-part 7.7 GB download from gdl.square-enix.com,
`FFXIFullSetup_US.part1.exe` + `.part2-5.rar`) + their FFXI-UpdatePatch.zip, Tabula Rasa = defunct
(site parked, repo dead since 2024-05). HorizonXI: magnet-only (verified: aria2c pulls it at
14–20 MiB/s, 40+ peers — the earlier "stalls" were metadata timing).

### 2026-08-16 15:00–15:45 — launch pipeline verified to the login handshake

Built the multi-server launch changes and drove them on the real .app (Developer-ID signed,
`/Applications/FFXI-on-Mac.app` kept playable throughout):

* **HorizonXI** — Play injects Ashita, the x87 sidecar attaches to `horizon-loader.exe`, the
  loader resolves `play.horizonxi.com`, connects, and reaches the login step. Auth itself
  returned "Invalid username or password" / "Bad json reply from remote" — that is credentials,
  not the launcher: the stored test passwords are stale. The loader that works is the 2.0.x LSB
  fork (`horizon-loader.exe.bak`, 1.05 MB, == the fresh 2.0.3 client's loader). A **stale 87 KB
  2023 loader** was sitting as the live `horizon-loader.exe` and only ever showed the menu (no
  connect) — moved aside to `horizon-loader.exe.2023-87k` and replaced with the 2.0.x one. Note
  for the app: it should prefer the loader that ships with the *current* client, not whatever is
  named in a hand-edited profile.
* **CatsEyeXI** — same result: injects, `pol.exe` (their LSB 2.0.1 fork) connects to
  `server.catseyexi.com`, reaches login, "Invalid username or password" (the test account
  `ffxionmac` was never actually created on their server). The **SquareEnix-resolver bug that
  blocked this is fixed**: their client puts `FINAL FANTASY XI` under `…/Game/`, not
  `…/SquareEnix/FINAL FANTASY XI`; `Install.resolveSquareEnix` now finds it and the version
  check reads the right `patch.cfg` (their client is 30251227_0, past CatsEye's 30251204_1 gate).
* **Local server** — LSB is built and running; stock `xiloader` reaches it but autologin fell
  back to the menu (a local-account/handshake matter, not the launcher). Left for a later pass.

Code added this session:
* `Install.resolveAshitaDir` / `resolveSquareEnix` — find the two things a launch needs under
  whatever folder the user points at, per world, capped-depth, skipping ROM trees.
* `GameRegistry.point` — re-points `HKLM\…\PlayOnlineUS\InstallFolder` (both views) + the four
  COM registrations at the selected world's SquareEnix before each launch, cached by a marker.
* `Credentials.fixBootLoader` / `bootLoaderName` — a copied profile's `file =` is rewritten to a
  loader that actually exists in the world's `bootloader/`; the exit-watcher and sidecar key off
  that name (`Runner.currentGameExe`), not a hard-coded `horizon-loader.exe`.
* `Runner`: second wine prefix for installers (`prefix-installers`), `runInstaller` now fetches
  with resumable curl and unpacks zips, `runLocalInstaller`, `installRetail`, `cancelInstaller`;
  login-failure detection (`Failed to login` / `Bad json` / `version mismatch` / `already logged
  in`) surfaces the loader's verdict to the UI and stops the loader instead of hanging on an
  invisible menu; the whole log is teed to `~/Library/Application Support/HorizonXI-on-Mac/
  launcher.log` for after-the-fact diagnosis.
* `--play [--world <name>]` launch args for unattended tests / Shortcuts.
* `scripts/retail-client.sh` — the SE-client + PlayOnline + Ashita/xiloader pipeline for the
  bring-your-own-retail worlds (Supernova, Omicron). **Untested end-to-end.**

### What's proven vs. not (be honest)

* **Proven:** HorizonXI + CatsEyeXI download and launch to the login handshake on this Mac.
  HorizonXI's full torrent update chain (1.x → 2.0.3) downloads and extracts. The layout
  resolver, per-world registry, installer prefix, and login-failure surfacing all work.
* **Not proven:** actually logging in and seeing the 3D world (blocked on real credentials, and
  the Mac auto-locked while unattended — GUI can't be driven from a locked session). Eden / FFEra
  / Valhalla / Gaia installer runs. The retail pipeline. The local-server autologin.

### Next session

1. With Daniel's real HorizonXI password, confirm a full login + zone-in + a screenshot of the
   world. (The launch half is done; only auth is untested.)
2. Drive one website-installer world (Eden is the cleanest: direct 5.8 GB Drive zip) through
   Download… end to end, fix whatever the installer's wine run needs.
3. Run `retail-client.sh` once for Supernova on a spare folder; it will surface the SE-installer
   GUI steps that need automating.
4. Consider notarizing the .app (currently Developer-ID signed but `spctl` rejects = unnotarized;
   the x87sidecar entitlements are the usual snag — see `docs/dev` notes).
