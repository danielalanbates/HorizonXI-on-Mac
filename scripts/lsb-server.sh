#!/bin/zsh
# lsb-server.sh — set up, build, run and stop a local LandSandBoat server on this Mac.
#
# This is what the launcher's "Local server (LandSandBoat)" world runs. Picking that world means
# the user is not logging into anybody's server: the whole FFXI server stack is built from source
# here and the client connects to 127.0.0.1. Everything below is idempotent, so `setup` can be
# re-run after a failure and it resumes where it stopped rather than starting over.
#
#   ./lsb-server.sh status     key=value lines describing what is and is not done yet
#   ./lsb-server.sh setup      do whatever is still missing: deps, source, database, build
#   ./lsb-server.sh start      start mariadb (if needed) and the four server processes
#   ./lsb-server.sh stop       stop them again
#
# Environment:
#   LSB_ROOT       where everything lives                (default ~/Games/lsb)
#   LSB_FORCE=1    run setup even below the disk floor
#   LSB_JOBS       compile jobs (default: cores, capped by RAM — see pick_jobs)
#
set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

# zsh sets $0 to the *function name*, not the script path, inside a function -- captured here,
# at top level, so cmd_watchdog_spawn can re-invoke this same script from within cmd_start.
SELF="${0:A}"

# A Docker-hosted test server (scripts/lsb-docker.sh) takes over the whole contract when its
# image has been built or LSB_BACKEND=docker is set. The launcher keeps calling this script by
# name, so the choice lives here rather than in Swift. Everything below is the Homebrew build.
if [[ "${LSB_BACKEND:-}" == "docker" ]] \
   || { [[ -z "${LSB_BACKEND:-}" ]] && [[ -x "${SELF:h}/lsb-docker.sh" ]] \
        && command -v docker >/dev/null 2>&1 \
        && docker image inspect lsb-local/server:latest >/dev/null 2>&1; }; then
  exec /bin/zsh "${SELF:h}/lsb-docker.sh" "$@"
fi

LSB_ROOT="${LSB_ROOT:-$HOME/Games/lsb}"
SRC="$LSB_ROOT/server"
RUN="$LSB_ROOT/run"
PASSFILE="$LSB_ROOT/.dbpass"
REPO_URL="${LSB_REPO:-https://github.com/LandSandBoat/server.git}"

DB_NAME=xidb
DB_USER=xiuser

# Space. Measured on a completed install: 0.9 GB source + 1.0 GB .git + 3.1 GB build tree +
# 0.2 GB database, plus ~0.6 GB of Homebrew dependencies and whatever CMake's CPM downloads
# while configuring. NEED is what makes for a comfortable install; FLOOR is where setup refuses
# to start, because running the disk to zero mid-build is a worse failure than not starting.
NEED_GB="${LSB_NEED_GB:-12}"
FLOOR_GB="${LSB_FLOOR_GB:-9}"

# Order matters: connect and search come up first, then world, then map.
SERVERS=(xi_connect xi_search xi_world xi_map)

# Homebrew packages. Mirrors LandSandBoat's own Linux build dependencies
# (docker/ubuntu.Dockerfile) with the macOS equivalents.
BREW_PKGS=(cmake luajit zeromq openssl@3 mariadb pkgconf)

say()  { print -r -- "$@"; }
step() { print -r -- "==> $*"; }
warn() { print -r -- "!!  $*"; }
die()  { print -r -- "!!  $*" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
# environment discovery

brew_prefix() {
  if [[ -x /opt/homebrew/bin/brew ]]; then print -r -- /opt/homebrew
  elif [[ -x /usr/local/bin/brew ]]; then print -r -- /usr/local
  else return 1
  fi
}

BREW_PREFIX="$(brew_prefix || true)"
BREW="${BREW_PREFIX:+$BREW_PREFIX/bin/brew}"
MBIN="${BREW_PREFIX:+$BREW_PREFIX/opt/mariadb/bin}"
[[ -n "$BREW_PREFIX" ]] && export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/opt/mariadb/bin:$PATH"

# Free GB on the volume that holds (or will hold) LSB_ROOT. Walks up until it finds a directory
# that exists, so this answers correctly before anything has been created.
free_gb() {
  local d="${1:-$LSB_ROOT}"
  while [[ ! -d "$d" && "$d" != "/" ]]; do d="${d:h}"; done
  df -k "$d" | awk 'NR==2 {printf "%.1f", $4/1048576}'
}

# Compile jobs. C++ link steps here run to well over a gigabyte each, and this project's target
# machine has 8 GB, so cap by RAM as well as by cores — an oversubscribed build swaps and can
# take the machine down with it.
pick_jobs() {
  if [[ -n "${LSB_JOBS:-}" ]]; then print -r -- "$LSB_JOBS"; return; fi
  local cores ramgb byram
  cores=$(sysctl -n hw.ncpu)
  ramgb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  byram=$(( ramgb / 2 ))
  (( byram < 1 )) && byram=1
  (( byram < cores )) && print -r -- "$byram" || print -r -- "$cores"
}

have_clt() { xcode-select -p >/dev/null 2>&1 && [[ -x /usr/bin/c++ ]]; }

deps_missing() {
  local missing=()
  [[ -n "$BREW" ]] || { print -r -- "${BREW_PKGS[@]}"; return; }
  for p in "${BREW_PKGS[@]}"; do
    "$BREW" list --versions "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  print -r -- "${missing[@]}"
}

db_running() {
  [[ -n "$MBIN" && -x "$MBIN/mariadb-admin" ]] || return 1
  "$MBIN/mariadb-admin" --protocol=socket ping >/dev/null 2>&1
}

# Which account can administer this server over the local socket. Homebrew's mariadb gives the
# installing macOS user a DBA account authenticated by the socket itself, and `root` is *not* it
# — root@localhost maps to the OS user literally named root, so `-u root` is refused on a normal
# Mac. Try the real user first, then root for the setups where that is how it was built.
db_admin_user() {
  local u
  for u in "${USER:-$(id -un)}" root; do
    if "$MBIN/mariadb" --protocol=socket -u "$u" -N -B -e "SELECT 1" >/dev/null 2>&1; then
      print -r -- "$u"; return 0
    fi
  done
  return 1
}

# The database counts as imported once the schema is really in it. A bare CREATE DATABASE leaves
# zero tables, and a run that died during the import leaves a handful; a complete LandSandBoat
# schema is several hundred, so 100 cleanly separates "imported" from "started and failed".
# Ask as the server's own account when there is one — that is the account that actually has to
# be able to read the schema, so this tests the credentials as well as the import.
db_ready() {
  db_running || return 1
  local n q admin
  q="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME'"
  if [[ -f "$PASSFILE" ]]; then
    n=$("$MBIN/mariadb" --protocol=socket -u "$DB_USER" -p"$(<"$PASSFILE")" -N -B -e "$q" 2>/dev/null) || n=""
  fi
  if [[ -z "$n" ]] && admin="$(db_admin_user)"; then
    n=$("$MBIN/mariadb" --protocol=socket -u "$admin" -N -B -e "$q" 2>/dev/null) || n=""
  fi
  [[ -n "$n" && "$n" -gt 100 ]]
}

built() {
  for s in "${SERVERS[@]}"; do [[ -x "$SRC/$s" ]] || return 1; done
  return 0
}

# The pid of a running server process, whether or not this script is the thing that started it.
# The pid file alone is not enough: these get launched by hand during development too, and a
# second copy does not fail politely — it dies on "bind: Address already in use" and takes the
# rest of the start sequence with it. Matching the process name adopts whatever is already up.
pid_of() {
  local s="$1" pf="$RUN/$s.pid" pid
  if [[ -f "$pf" ]]; then
    pid="$(<"$pf")"
    if kill -0 "$pid" 2>/dev/null; then print -r -- "$pid"; return 0; fi
  fi
  pid="$(pgrep -x "$s" 2>/dev/null | head -1)"
  [[ -n "$pid" ]] || return 1
  print -r -- "$pid"
}

running_list() {
  local out=() s
  for s in "${SERVERS[@]}"; do
    pid_of "$s" >/dev/null && out+=("$s")
  done
  print -r -- "${out[@]}"
}

# ---------------------------------------------------------------------------------------------
# status — the launcher parses this; keep it key=value, one per line, and never fail

cmd_status() {
  local free need_ok up
  free="$(free_gb)"
  # `bc` is not guaranteed; awk is.
  need_ok=$(awk -v f="$free" -v n="$NEED_GB" 'BEGIN{print (f+0 >= n+0) ? 1 : 0}')
  up="$(running_list)"
  say "root=$LSB_ROOT"
  say "freeGB=$free"
  say "needGB=$NEED_GB"
  say "floorGB=$FLOOR_GB"
  say "spaceOK=$need_ok"
  say "brew=$([[ -n "$BREW" ]] && echo 1 || echo 0)"
  say "clt=$(have_clt && echo 1 || echo 0)"
  say "depsMissing=$(deps_missing)"
  say "source=$([[ -d "$SRC/.git" ]] && echo 1 || echo 0)"
  say "built=$(built && echo 1 || echo 0)"
  say "dbRunning=$(db_running && echo 1 || echo 0)"
  say "dbReady=$(db_ready && echo 1 || echo 0)"
  say "running=$([[ -n "$up" ]] && echo 1 || echo 0)"
  say "up=$up"
}

# ---------------------------------------------------------------------------------------------
# setup steps

check_space() {
  local free ok
  free="$(free_gb)"
  ok=$(awk -v f="$free" -v n="$FLOOR_GB" 'BEGIN{print (f+0 >= n+0) ? 1 : 0}')
  step "disk: ${free} GB free on ${LSB_ROOT:h}, ${NEED_GB} GB recommended"
  if [[ "$ok" != 1 ]]; then
    warn "Not enough free space. A local server needs about ${NEED_GB} GB —"
    warn "roughly 5 GB of source and history, 3 GB of build output, and headroom for the"
    warn "database and the compiler's temporary files. You have ${free} GB."
    warn "Free up space and run setup again (or set LSB_FORCE=1 to override)."
    [[ "${LSB_FORCE:-0}" == 1 ]] || exit 2
    warn "LSB_FORCE=1 — continuing anyway."
  elif [[ $(awk -v f="$free" -v n="$NEED_GB" 'BEGIN{print (f+0 >= n+0) ? 1 : 0}') != 1 ]]; then
    warn "Below the ${NEED_GB} GB recommendation but above the ${FLOOR_GB} GB floor — continuing."
  fi
}

ensure_clt() {
  have_clt && { step "command line tools: present"; return; }
  step "command line tools: missing — opening Apple's installer"
  xcode-select --install >/dev/null 2>&1 || true
  die "Finish the Command Line Tools install that just opened, then run setup again."
}

ensure_brew() {
  [[ -n "$BREW" ]] && { step "homebrew: $BREW_PREFIX"; return; }
  step "homebrew: not installed — installing (this asks for your password)"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  BREW_PREFIX="$(brew_prefix || true)"
  [[ -n "$BREW_PREFIX" ]] || die "Homebrew install did not complete. Install it from https://brew.sh and run setup again."
  BREW="$BREW_PREFIX/bin/brew"
  MBIN="$BREW_PREFIX/opt/mariadb/bin"
  export PATH="$BREW_PREFIX/bin:$MBIN:$PATH"
}

ensure_deps() {
  local missing=(${=$(deps_missing)})
  if (( ${#missing} == 0 )); then step "dependencies: all present"; return; fi
  step "dependencies: installing ${missing[*]}"
  "$BREW" install "${missing[@]}"
}

ensure_source() {
  if [[ -d "$SRC/.git" ]]; then
    step "source: $SRC (already cloned)"
  else
    step "source: cloning LandSandBoat into $SRC"
    mkdir -p "$LSB_ROOT"
    git clone --recurse-submodules "$REPO_URL" "$SRC"
  fi
  mkdir -p "$RUN"
}

# The one source change this needs. LandSandBoat pins the loader protocol to xiloader 2.1, and
# the loader that ships with the HorizonXI client is 2.0 — so without this the client we already
# have is rejected at login by our own server. Upstream is right to pin it for a public server;
# on a loopback instance that only this Mac can reach, it is the difference between the option
# working and not.
ensure_patch() {
  local f="$SRC/src/login/auth_session.h"
  [[ -f "$f" ]] || { warn "auth_session.h not found — skipping loader-version patch"; return; }
  if grep -q 'SupportedXiloaderVersion = { 2, 0, 0 }' "$f"; then
    step "loader version: already accepts xiloader 2.0"
    return
  fi
  step "loader version: allowing the client's xiloader 2.0"
  /usr/bin/sed -i '' \
    's/SupportedXiloaderVersion = { 2, 1, 0 }/SupportedXiloaderVersion = { 2, 0, 0 }/' "$f"
}

# The server reads settings/default/*.lua first and then settings/*.lua on top. A fresh clone has
# only the defaults, so seed the overrides from them and edit the two values that matter.
ensure_settings() {
  local d="$SRC/settings"
  mkdir -p "$d"
  for f in "$d"/default/*.lua; do
    [[ -f "$d/${f:t}" ]] || cp "$f" "$d/${f:t}"
  done

  if [[ ! -f "$PASSFILE" ]]; then
    umask 077
    print -r -- "lsb_local_$(od -An -tx1 -N6 /dev/urandom | tr -d ' \n')" > "$PASSFILE"
    chmod 600 "$PASSFILE"
  fi
  local pw; pw="$(<"$PASSFILE")"

  /usr/bin/sed -i '' \
    -e "s/^\( *\)SQL_LOGIN *=.*/\1SQL_LOGIN = '$DB_USER',/" \
    -e "s/^\( *\)SQL_PASSWORD *=.*/\1SQL_PASSWORD = '$pw',/" \
    -e "s/^\( *\)SQL_DATABASE *=.*/\1SQL_DATABASE = '$DB_NAME',/" \
    "$d/network.lua"

  # The client is HorizonXI's, whose version string will not match a stock LandSandBoat's.
  # Turning the version lock off is what lets that client connect; CLIENT_VER then does not
  # matter, so leave it at whatever upstream ships.
  /usr/bin/sed -i '' -e "s/^\( *\)VER_LOCK *=.*/\1VER_LOCK = 0,/" "$d/login.lua"
  step "settings: SQL user '$DB_USER', database '$DB_NAME', client version lock off"
}

ensure_venv() {
  local py="$SRC/.venv/bin/python"
  if [[ ! -x "$py" ]]; then
    step "python: creating $SRC/.venv"
    /usr/bin/env python3 -m venv "$SRC/.venv"
  fi
  if ! "$py" -c 'import mariadb' >/dev/null 2>&1; then
    step "python: installing the database tool's dependencies"
    "$SRC/.venv/bin/pip" install --quiet --upgrade pip setuptools wheel
    # The mariadb connector compiles against the Homebrew client library.
    MARIADB_CONFIG="$MBIN/mariadb_config" \
      "$SRC/.venv/bin/pip" install --quiet --upgrade -r "$SRC/tools/requirements.txt"
  else
    step "python: dependencies present"
  fi
}

start_db() {
  db_running && { step "mariadb: already running"; return; }
  [[ -d "$BREW_PREFIX/var/mysql" ]] || {
    step "mariadb: initialising the data directory"
    "$MBIN/mariadb-install-db" --datadir="$BREW_PREFIX/var/mysql" >/dev/null
  }
  step "mariadb: starting"
  mkdir -p "$RUN"
  nohup "$MBIN/mariadbd-safe" --datadir="$BREW_PREFIX/var/mysql" \
        >"$RUN/mariadb.log" 2>&1 &
  disown 2>/dev/null || true
  touch "$RUN/.mariadb-ours"
  local i
  for i in {1..60}; do
    db_running && { step "mariadb: up"; return; }
    sleep 1
  done
  die "mariadb did not come up — see $RUN/mariadb.log"
}

ensure_db() {
  start_db
  local pw admin
  pw="$(<"$PASSFILE")"
  admin="$(db_admin_user)" || die \
    "no account can administer the local mariadb over its socket. Neither '$USER' nor 'root' was accepted."

  # Grant on the database name rather than creating the database here: that is enough privilege
  # for LandSandBoat's own dbtool to create and populate it, and it keeps this account scoped to
  # its own schema instead of the whole server.
  "$MBIN/mariadb" --protocol=socket -u "$admin" <<SQL
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$pw';
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$pw';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$pw';
ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$pw';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

  if db_ready; then
    step "database: $DB_NAME already imported"
  else
    step "database: importing the schema (this takes a few minutes)"
    ( cd "$SRC" && "$SRC/.venv/bin/python" tools/dbtool.py setup "$DB_NAME" )
    db_ready || die "the schema import did not complete — re-run setup"
  fi
  ( cd "$SRC" && "$SRC/.venv/bin/python" tools/dbtool.py migrate ) || \
    warn "migrations reported a problem — the server may still run"
}

ensure_build() {
  if built; then step "build: server binaries already present"; return; fi
  local jobs; jobs="$(pick_jobs)"
  step "build: compiling with $jobs jobs (20-40 minutes on a laptop)"
  # Call cmake directly rather than tools/build.py: the preset does not set a job count, and on
  # an 8 GB machine an uncapped parallel build is what takes the machine down.
  cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo
  cmake --build "$SRC/build" -j "$jobs"
  built || die "the build finished but the server binaries are missing — see the log above"
  step "build: done"
}

cmd_setup() {
  check_space
  ensure_clt
  ensure_brew
  ensure_deps
  ensure_source
  ensure_patch
  ensure_settings
  ensure_venv
  ensure_db
  ensure_build
  step "setup complete — the local server is ready to start"
}

# ---------------------------------------------------------------------------------------------
# run control

cmd_start() {
  built || die "not built yet — run setup first"
  [[ -f "$PASSFILE" ]] || die "no database password file — run setup first"
  start_db
  db_ready || die "database $DB_NAME is not imported — run setup first"
  mkdir -p "$RUN"

  local s pf pid
  for s in "${SERVERS[@]}"; do
    pf="$RUN/$s.pid"
    if pid="$(pid_of "$s")"; then
      step "$s: already running (pid $pid)"
      print -r -- "$pid" > "$pf"
      continue
    fi
    step "$s: starting"
    ( cd "$SRC" && nohup "./$s" >"$RUN/$s.log" 2>&1 & print -r -- $! > "$pf" )
    sleep 2
    kill -0 "$(<"$pf")" 2>/dev/null || {
      warn "$s exited immediately — last lines of $RUN/$s.log:"
      tail -n 15 "$RUN/$s.log" 2>/dev/null || true
      die "$s failed to start"
    }
  done

  # xi_map is the one that has to survive its own start-up: it loads every zone before it will
  # accept a connection, and a database or settings problem shows up there rather than earlier.
  sleep 3
  local up; up="$(running_list)"
  step "running: ${up:-none}"
  [[ "$up" == *xi_map* ]] || die "xi_map did not stay up — see $RUN/xi_map.log"
  step "local server ready on 127.0.0.1 — accounts are created on first login"

  cmd_watchdog_spawn
}

# ---------------------------------------------------------------------------------------------
# watchdog — this build's xi_map crashes every 15-20 minutes on real engine bugs (a Lua error
# in mob spell-choice AI, and separately a null-pointer in pathfinding's UpdateSpeed) that are
# out of scope to fix here. Losing xi_map silently disconnects anyone in-world with a timeout,
# which reads as "the launcher is broken" rather than "the server crashed" -- so restart
# whichever process died instead of leaving it down until someone notices.

cmd_watchdog() {
  step "watchdog: monitoring ${SERVERS[*]} every 15s"
  # Declared once, outside the loop: re-declaring `local s` on every iteration is what made
  # cmd_stop's version of this same loop echo stray "s=xi_map" lines (see its comment above).
  local s
  while true; do
    sleep 15
    for s in "${SERVERS[@]}"; do
      pid_of "$s" >/dev/null && continue
      step "watchdog: $s is down — restarting"
      ( cd "$SRC" && nohup "./$s" >>"$RUN/$s.log" 2>&1 & print -r -- $! > "$RUN/$s.pid" )
    done
  done
}

# One watchdog per machine, not one per `start` call -- a second copy would just double-restart
# on top of the first and both would race to write the same .pid files.
cmd_watchdog_spawn() {
  local wpf="$RUN/watchdog.pid"
  if [[ -f "$wpf" ]] && kill -0 "$(<"$wpf")" 2>/dev/null; then
    return
  fi
  ( nohup "$SELF" watchdog >>"$RUN/watchdog.log" 2>&1 & print -r -- $! > "$wpf" )
  step "watchdog: started (pid $(<"$wpf"))"
}

cmd_stop() {
  # All declared up front: re-running `local` on a name that is already local makes zsh echo it,
  # which turns up as stray "i=6" lines in the launcher's log.
  local s pid i
  # Kill the watchdog *first* -- stopping the servers while it is still running just teaches it
  # to immediately restart the one that goes down first.
  local wpf="$RUN/watchdog.pid"
  if [[ -f "$wpf" ]] && pid="$(<"$wpf")" && kill -0 "$pid" 2>/dev/null; then
    step "watchdog: stopping (pid $pid)"
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$wpf"
  # Reverse order: map first, then world, so zones get to save their state before the process
  # holding the world session goes away.
  for s in "${(Oa)SERVERS[@]}"; do
    if pid="$(pid_of "$s")"; then
      step "$s: stopping (pid $pid)"
      kill "$pid" 2>/dev/null || true
      for i in {1..10}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      if kill -0 "$pid" 2>/dev/null; then
        warn "$s did not exit on request — forcing"
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$RUN/$s.pid"
  done

  # Only stop the database if this script started it. A mariadb the user runs for their own work
  # is not ours to shut down.
  if [[ -f "$RUN/.mariadb-ours" ]] && db_running; then
    local admin
    if admin="$(db_admin_user)"; then
      step "mariadb: stopping"
      "$MBIN/mariadb-admin" --protocol=socket -u "$admin" shutdown >/dev/null 2>&1 || true
    fi
    rm -f "$RUN/.mariadb-ours"
  fi
  step "stopped"
}

case "${1:-status}" in
  status)   cmd_status ;;
  setup)    cmd_setup ;;
  start)    cmd_start ;;
  stop)     cmd_stop ;;
  watchdog) cmd_watchdog ;;
  *) die "usage: lsb-server.sh [status|setup|start|stop|watchdog]" ;;
esac
