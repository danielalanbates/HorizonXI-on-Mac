#!/bin/zsh
# lsb-docker.sh — a local-only LandSandBoat test server in Docker.
#
# Same contract as lsb-server.sh (status / setup / start / stop, key=value status lines), so the
# launcher's "Local server" world can drive it, but the server is built and run in containers
# instead of from a Homebrew toolchain. It exists so end-to-end runs can log a throwaway
# character in and zone without touching anybody's real world.
#
#   ./lsb-docker.sh status     key=value lines: image, database, running services
#   ./lsb-docker.sh setup      build the arm64 server image from the checkout, fetch navmeshes,
#                              create and populate the database
#   ./lsb-docker.sh start      bring the stack up on 127.0.0.1 and wait for the login port
#   ./lsb-docker.sh stop       bring it down (data volume kept)
#   ./lsb-docker.sh reset      stop and delete the database volume
#   ./lsb-docker.sh logs       follow the server logs
#   ./lsb-docker.sh sql "..."  run a query against xidb as root
#
# Credentials are plain text on purpose. Nothing here is reachable off this Mac.
#
#   MariaDB   127.0.0.1:3306   root / root       xidb: xiadmin / password
#   Login     127.0.0.1:54231  any account name; the loader offers to create it on first connect
#
# Environment:
#   LSB_SRC    LandSandBoat checkout to build from
#              (default /Users/developer/go/src/github.com/LandSandBoat/server)
#   LSB_JOBS   compile jobs inside the build container (default 4; see cmd_setup)
#
set -euo pipefail

HERE="${0:A:h}"
STACK="$HERE/lsb-docker"
COMPOSE=(docker compose --project-name lsb-local -f "$STACK/docker-compose.yml")
LSB_SRC="${LSB_SRC:-/Users/developer/go/src/github.com/LandSandBoat/server}"
IMAGE=lsb-local/server:latest
MESH_VOLUME=lsb-navmeshes
XIMESH_VOLUME=lsb-ximeshes
DB_VOLUME=lsb-local_lsb-database

say()  { print -r -- "$@"; }
step() { print -r -- "==> $*"; }
warn() { print -r -- "!!  $*"; }
die()  { print -r -- "!!  $*" >&2; exit 1; }

have_docker()  { docker info >/dev/null 2>&1; }
have_image()   { docker image inspect "$IMAGE" >/dev/null 2>&1; }
have_meshes()  { docker volume inspect "$MESH_VOLUME" "$XIMESH_VOLUME" >/dev/null 2>&1; }
have_source()  { [[ -d "$LSB_SRC/.git" ]]; }

services_running() {
  "${COMPOSE[@]}" ps --status running --services 2>/dev/null || true
}

db_running() {
  services_running | grep -qx database
}

db_ready() {
  db_running || return 1
  local n
  n="$("${COMPOSE[@]}" exec -T database mariadb -uroot -proot -N -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='xidb'" 2>/dev/null || echo 0)"
  (( ${n:-0} > 100 ))
}

running_list() {
  { services_running | grep -E '^(connect|search|world|map)$' || true; } | tr '\n' ' ' | sed 's/ $//'
}

# ---------------------------------------------------------------------------------------------

cmd_status() {
  local up
  up="$(running_list)"
  say "root=$STACK"
  say "source=$(have_source && echo 1 || echo 0)"
  say "docker=$(have_docker && echo 1 || echo 0)"
  say "built=$(have_image && echo 1 || echo 0)"
  say "meshes=$(have_meshes && echo 1 || echo 0)"
  say "dbRunning=$(db_running && echo 1 || echo 0)"
  say "dbReady=$(db_ready && echo 1 || echo 0)"
  say "running=$([[ -n "$up" ]] && echo 1 || echo 0)"
  say "up=$up"
  # Keys the launcher's LocalServer.Status also reads; a Docker stack has no Homebrew or disk
  # floor to report, so answer in the affirmative rather than leave it thinking setup is due.
  say "brew=1"; say "clt=1"; say "depsMissing="; say "spaceOK=1"
  say "freeGB=$(df -g "$HOME" | awk 'NR==2{print $4}')"; say "needGB=4"; say "floorGB=2"
}

# Two edits to the checkout before building, kept as patches/lsb-local-test-server.patch so a
# fresh clone gets them back: the xiloader pin relaxed from 2.1 to 2.0 (HorizonXI's bootloader
# reports 2.0 and the login server rejects by major.minor), and a BUILD_JOBS build arg in the
# Dockerfile so the compile can be capped below the Docker VM's memory.
ensure_source_patch() {
  # Beside the stack when bundled into the app, one level up in the repository.
  local patch="$STACK/lsb-local-test-server.patch"
  [[ -f "$patch" ]] || patch="$HERE/../patches/lsb-local-test-server.patch"
  [[ -f "$patch" ]] || { warn "lsb-local-test-server.patch not found; building unpatched"; return; }
  if git -C "$LSB_SRC" apply --check --reverse "$patch" >/dev/null 2>&1; then
    step "source: local test-server patch already applied"; return
  fi
  if git -C "$LSB_SRC" apply --check "$patch" >/dev/null 2>&1; then
    step "source: applying patches/lsb-local-test-server.patch"
    git -C "$LSB_SRC" apply "$patch"
  else
    warn "patches/lsb-local-test-server.patch does not apply to $LSB_SRC; building unpatched"
  fi
}

cmd_setup() {
  have_docker || die "Docker is not running"
  have_source || die "no LandSandBoat checkout at $LSB_SRC (LSB_SRC=... to point elsewhere)"
  mkdir -p "$STACK/log"

  if ! have_meshes; then
    # xi_map refuses to start without ximeshes as well as navmeshes; the upstream compose
    # example mounts only the latter. The mesh image carries both.
    step "meshes: loading ghcr.io/landsandboat/ximeshes into volumes $MESH_VOLUME and $XIMESH_VOLUME"
    docker run --rm -v "$MESH_VOLUME:/navmeshes" -v "$XIMESH_VOLUME:/ximeshes" \
      ghcr.io/landsandboat/ximeshes:latest
  else
    step "meshes: volumes $MESH_VOLUME and $XIMESH_VOLUME present"
  fi

  if ! have_image; then
    ensure_source_patch
    # Docker Desktop's VM has 8 GB here; twelve parallel g++ jobs on xi_map's Lua bindings get
    # the compiler OOM-killed, and a running MariaDB beside them goes first. Four jobs fit.
    "${COMPOSE[@]}" stop database >/dev/null 2>&1 || true
    step "image: building $IMAGE for linux/arm64 from $LSB_SRC (about 25 minutes at 4 jobs)"
    docker build --platform linux/arm64 -f "$LSB_SRC/docker/ubuntu.Dockerfile" --target service \
      --tag "$IMAGE" --build-arg BUILD_JOBS="${LSB_JOBS:-4}" \
      --build-arg REPO_URL="https://github.com/LandSandBoat/server" \
      --build-arg COMMIT_SHA="$(git -C "$LSB_SRC" rev-parse HEAD)" \
      "$LSB_SRC"
  else
    step "image: $IMAGE present (delete it to rebuild)"
  fi

  step "database: starting mariadb and importing the schema"
  "${COMPOSE[@]}" up -d database
  "${COMPOSE[@]}" run --rm database-update
  step "local test server ready on 127.0.0.1; accounts are created on first login"
}

wait_for_port() {
  local port="$1" tries="${2:-60}"
  for ((i = 0; i < tries; i++)); do
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

cmd_start() {
  have_docker || die "Docker is not running"
  have_image || die "server image is not built; run setup first"
  db_ready 2>/dev/null || step "database: not populated yet; database-update runs before the servers"
  step "starting connect, search, world, map"
  "${COMPOSE[@]}" up -d
  if wait_for_port 54231 90 && wait_for_port 54001 30; then
    step "login server is listening on 127.0.0.1:54231"
  else
    "${COMPOSE[@]}" ps; die "login server did not come up; see: $0 logs"
  fi
  # xi_map takes a few more seconds to load zones; the client tolerates that, the harness waits.
  say "up=$(running_list)"
}

cmd_stop() {
  have_docker || { say "docker not running; nothing to stop"; return; }
  step "stopping the stack (database volume kept)"
  "${COMPOSE[@]}" down --remove-orphans
}

cmd_reset() {
  cmd_stop
  step "deleting database volume $DB_VOLUME"
  docker volume rm "$DB_VOLUME" >/dev/null 2>&1 || true
}

cmd_logs() { "${COMPOSE[@]}" logs -f --tail 200 connect search world map; }

cmd_sql() {
  "${COMPOSE[@]}" exec -T database mariadb -uroot -proot xidb -e "$1"
}

case "${1:-}" in
  status) cmd_status ;;
  setup)  cmd_setup ;;
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  reset)  cmd_reset ;;
  logs)   cmd_logs ;;
  sql)    cmd_sql "${2:?query}" ;;
  *) die "usage: $0 status|setup|start|stop|reset|logs|sql" ;;
esac
