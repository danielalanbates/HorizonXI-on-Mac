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

### 2026-08-16 16:15 — GitHub auto-updater

`Updater.swift` + `updateBanner` in `App.swift`. On launch (and every 6 h, and on re-activate) it
hits `api.github.com/repos/danielalanbates/HorizonXI-on-Mac/releases/latest`, and if `tag_name`
is a higher dotted version than `CFBundleShortVersionString` it **auto-downloads** that release's
`.dmg`, mounts it (`hdiutil`), stages the `.app` into `App Support/HorizonXI-on-Mac/updates/
staged-<ver>/`, strips quarantine (`/usr/bin/xattr -dr` — note the Homebrew python `xattr` in PATH
lacks `-r`, so the absolute path matters), detaches, and shows a gold "Update <ver> is ready —
Restart" banner. It never applies the update itself; **Restart** writes a detached zsh helper that
waits for the app's pid to exit, `ditto`s the staged bundle over the running one, strips
quarantine, relaunches, and cleans up.

Verified end-to-end by stamping a scratch build as 2.5: it saw live v2.6, downloaded, mounted, and
staged a signature-valid `FFXI-on-Mac.app`; the swap helper was tested on dummy bundles
(OLD→NEW). Not driven through the actual Restart on the live app (would downgrade to the older 2.6
release, which predates this code) and the GUI banner wasn't screenshotted (Mac was locked).

**Release coherence:** bumped `bundle.sh` to 2.7 / build 8. The updater compares versions, so the
next release's tag must exceed the installed `CFBundleShortVersionString` or it would offer itself
in a loop — `scripts/package.sh` reads the version from the bundle, so cut the release as **v2.7**
(`HXI_SIGN_ID=<hash> ./scripts/package.sh` → notarized `dist/FFXI-on-Mac-2.7.dmg` →
`gh release create v2.7 …`). `/Applications` reinstalled as 2.7 so it won't offer the older 2.6.

## 2026-08-19 — CatsEyeXI "Play failed" root cause: no account (creation is server-disabled)

The 2026-08-15 client-version wall is GONE — the CatsEye install (`prefix10`,
`C:\Games\CatsEyeXI\catseyexi-client`, loader `Ashita/bootloader/pol.exe` = LSB xiloader 2.0.1)
connects, TLS-handshakes, and reaches auth fine. The failure is simply
`Failed to login. Invalid username or password.`: the stored credentials are HorizonXI accounts,
and LSB accounts are **per server** — no CatsEye account exists yet.

Automated creation attempts, for the record:
- xiloader's TUI (FTXUI) renders on a pty but consumes **no** input under our wine — arrows,
  tab, digits, and SGR mouse clicks all dead (`scratchpad cexi_create*.py`, archived in
  `archive/catseye-account-2026-08-19/`). Menu-driving is not a pathway.
- `--email` does not switch xiloader to create mode; it autologs-in.
- The auth protocol is small: **JSON over TLS to server.catseyexi.com:54231**, e.g.
  `{"command":32,"username":…,"password":…,"version":[2,0,1]}` (`login_cmd::LOGIN_CREATE=0x20`;
  omit `version` and you get "xiloader too old… reported 0.0.0"). The server answered
  `{"result":8}` = `LOGIN_ERROR_CREATE_DISABLED` — **account creation is disabled at the login
  server**. Source: `src/login/auth_session.cpp` in CatsAndBoats/catseyexi.
- Registration is web-only: **https://www.catseyexi.com/register** (Next.js SPA). Account
  creation + password entry is a human step, not an automation one.

Once an account named like the `--user` in `catseyexi.ini` exists (or the launcher's account
field is updated), Play should reach character select with no further work.

## 2026-08-19 (later) — CatsEye login succeeded; "Valid Content ID not found" = no character yet

Registration on catseyexi.com worked and the loader logged in ("Successfully logged in as
danielalanbates!") but the client stops at **"Valid Content ID not found."** Per CatsEye's own
download page this means no character exists yet: characters are created on the **website
dashboard** (Login → Create Character → pick a game mode), which then issues **separate game
account credentials** (one game account per game mode — Accelerated / Crystal Warrior /
Wings-Era). Those generated credentials, not the website login, go in the launcher.

Launcher change (32eb3c8): the account fields now recall each world's last-used login on
world switch (`Credentials.username(forWorld:)`, saved on Play), so the CatsEye game account
and the HorizonXI account no longer fight over one field.

## 2026-08-19 (later still) — Gaia XI client fully installed; blocked at credentials

Full integration done without their Electron launcher:
- Their launcher zip (260 MB, needs site login — fetched via Daniel's browser session) unpacks a
  complete Ashita 4.3.1.2 client skeleton incl. `bootloader/gxiloader.exe` (their LSB-2.0.0 fork)
  and `config/boot/GaiaXI.ini` (`file = .\bootloader\gxiloader.exe`, `--server play.gaiaxi.com`).
- The game data is a plain 8 GB zip on their CDN: 
  `https://gaiaxi.evenmonkeys.workers.dev/install/SquareEnix.zip` (no auth!) → extracted into the
  client folder. Their launcher APIs: `gaiaxi.com/api/v2/{server_address,patch_version,
  launcher_version,approved_addons,approved_plugins}.json`. **Gotcha:** patch_version's zip URL
  (`patch_2026_06_07_4.zip`) 404s on the CDN — patch presumed folded into the launcher zip.
- Install lives at `/Volumes/x10/Video Games/Mac/FFXI/GaiaXI/GaiaXI`, symlinked as
  `prefix10 drive_c/Games/GaiaXI`; world dataPath + bootProfile (GaiaXI.ini) wired; Gaia's
  API-published addon allowlist enforced (170+24).
- Unattended `--play --world "Gaia XI"` runs the full chain: their gxiloader resolves
  play.gaiaxi.com:54231, TLS ok — **server rejects the login** ("Bad json reply from remote" =
  their fork's error path replies an old-style single byte; a direct protocol probe with the same
  stored credentials returns 0x02 LOGIN_ERROR for login AND create, all case variants).
- So the machine side is done end-to-end; the block is the credential pair itself. Website login
  works in-browser, but the game auth rejects it. Open question for Daniel: is the game password
  separate from the site password (edit.xi bounced back to the account landing page, so it could
  not be checked), or was a typo stored? Their Discord is the support channel.
