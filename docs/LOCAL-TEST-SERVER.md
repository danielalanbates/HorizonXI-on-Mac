# Local test server in Docker

A LandSandBoat world that exists only on this Mac, so an unattended run can log a throwaway
character in, zone, and log out without touching anyone's real world. It is the server behind
the launcher's **Local server** entry once its image is built; the Homebrew build in
`scripts/lsb-server.sh` remains the path for a Mac without Docker.

Every credential below is deliberately plain text. Nothing here listens on anything but
127.0.0.1.

## What is where

| Piece | Location |
| --- | --- |
| Driver script | `scripts/lsb-docker.sh` (`status`, `setup`, `start`, `stop`, `reset`, `logs`, `sql`) |
| Compose stack | `scripts/lsb-docker/docker-compose.yml`, project name `lsb-local` |
| Server source | `/Users/developer/go/src/github.com/LandSandBoat/server` (`LSB_SRC` to override) |
| Server image | `lsb-local/server:latest`, built from that checkout for `linux/arm64` |
| Meshes | Docker volumes `lsb-navmeshes` and `lsb-ximeshes`, loaded from `ghcr.io/landsandboat/ximeshes` (xi_map needs both; the upstream compose example mounts only the first) |
| Database | Docker volume `lsb-local_lsb-database`, MariaDB 12.3 |
| Server logs | `scripts/lsb-docker/log/` |

## Credentials and ports

| What | Value |
| --- | --- |
| MariaDB root | `root` / `root` on 127.0.0.1:3306 |
| MariaDB game user | `xiadmin` / `password`, database `xidb` |
| Game account | `hxitest` / `hxitest1` (account id 1000), stored in the launcher for the **Local LSB (Docker)** world; any other name is created on first connect |
| Test character | `Hxitest`, Hume Warrior in Bastok Mines, `gmlevel = 5` (every `!command`, including `!godmode`, `!zone`, `!spawnmob`, `!additem`, `!speed`, the reload and crash tools) |
| Login (auth) | 127.0.0.1:54231 |
| Login (view) | 127.0.0.1:54001 |
| Login (data) and map | 127.0.0.1:54230 TCP and UDP |
| Search | 127.0.0.1:54002 |
| World HTTP API | 127.0.0.1:8088 |

The launcher's boot profile for the local world is `config/boot/lsb.ini` in the game folder,
written with `--server 127.0.0.1` and the account typed into the launcher.

## Setup

```sh
scripts/lsb-docker.sh setup    # navmesh volume, arm64 image (10 to 20 minutes), database
scripts/lsb-docker.sh start    # up on 127.0.0.1, waits for the login port
scripts/lsb-docker.sh status   # key=value lines the launcher reads
scripts/lsb-docker.sh stop
```

`lsb-server.sh` hands every command to `lsb-docker.sh` as soon as the image exists, or when
`LSB_BACKEND=docker` is set, so the launcher needs no change.

## Two deliberate deviations from upstream

- **xiloader 2.0 accepted.** The checkout pins `SupportedXiloaderVersion = { 2, 1, 0 }` and
  HorizonXI's bootloader reports 2.0. `patches/lsb-local-test-server.patch`, applied by setup,
  relaxes the pin to 2.0 in `src/login/auth_session.h` and adds the `BUILD_JOBS` argument to
  `docker/ubuntu.Dockerfile`. The same loader edit is what `lsb-server.sh` makes for the
  Homebrew build.
- **Client version lock off.** `XI_LOGIN_VER_LOCK=0` in the compose file, because the HorizonXI
  client is not a stock retail patch level. Account and character creation are on.

## Memory

Docker Desktop's VM has 8 GB on this Mac. The first build attempt with twelve parallel jobs got
`cc1plus` OOM-killed on `xi_map`'s Lua bindings and took MariaDB down with it. `setup` therefore
stops the database and builds with `BUILD_JOBS=4` (`LSB_JOBS` to change), which the Dockerfile
now honours. Once the image is built the running stack is small.

## The GM character

`Hxitest` was created through the client and finished by hand after a driver cleanup killed the
session mid-creation; the rows match what the server's own `saveCharacter` writes. `gmlevel` is
the switch for in-game `!commands`. LandSandBoat's own guide uses 4; 5 additionally unlocks the
reload, crash and battlefield tools, which are useful on a throwaway world. Set it from the
database and zone once, or from the `xi_map` console with `gm Hxitest 5` for an instant change:

```sh
scripts/lsb-docker.sh sql "UPDATE chars SET gmlevel = 5 WHERE charname = 'Hxitest'"
```

Commands the performance runs lean on, all level 1 or above: `!godmode` (no death), `!zone`
(any zone by id or autotranslate), `!speed`, `!spawnmob` and `!fakespawn` (load a scene with
entities), `!additem`, `!hide`. Each script under `scripts/commands/` in the LSB checkout
documents its own arguments.

## Database access

```sh
scripts/lsb-docker.sh sql "SELECT id, login FROM accounts"
scripts/lsb-docker.sh sql "SELECT charid, charname, pos_zone FROM chars"
```

Zone IPs in `zone_settings` are `127.0.0.1` out of the box, which is what a client on this Mac
needs. `reset` drops the database volume; `setup` rebuilds it.
