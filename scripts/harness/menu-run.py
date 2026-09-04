#!/usr/bin/env python3
"""Run one bounded HorizonXI launch through the menus and clean up.

The run arms `capture-performance.py`, launches the installed app the same way the Play button
does, waits for the rules screen by watching the DXVK frame log, takes a screenshot of the game
window, sends one Return, waits for the main menu, and stops. With `--characters` it sends one
more Return to open the character list, which is the furthest an unattended run may go. The
number of Returns is capped per mode, so a run can never log a character in.

Cleanup is two-phase. The game process is terminated first and the run waits for its x87sidecar
to observe the exit and append the block-profile counter section. Only then are the remaining
Wine processes swept. Every temporary launchd variable is removed on exit, including on Ctrl-C.

The run reads process names only. Loader arguments and boot profiles can contain account
credentials, so neither is ever inspected or written.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys
import time
from typing import Any, Callable


HERE = Path(__file__).resolve().parent
RECORDER = HERE / "capture-performance.py"
WINDOW_SOURCE = HERE / "game-window.swift"
WINDOW_TOOL = HERE / ".build" / "game-window"
APP = Path("/Applications/FFXI-on-Mac.app")
APP_BUNDLE_ID = "org.batesai.horizonxi-on-mac"
DEFAULT_GAME = Path.home() / "Games/FFXI/HorizonXI"
CAPTURE_DIR = Path("logs/performance-captures")
RUNTIMES = Path.home() / "Library/Application Support/HorizonXI-on-Mac/runtimes"
PREFIX = Path.home() / "Applications/FFXI on Mac Wine.app/Contents/SharedSupport/prefix10"

# Process names the sweep may stop. Matching is by comm suffix only.
RELATED_SUFFIXES = (
    "/FFXI-on-Mac", "/wine", "/wine-preloader", "/wine64-preloader", "/wineserver",
    "/x87sidecar-coop", "/x87sidecar_entitled", "Ashita-cli.exe", "horizon-loader.exe",
    "wineboot.exe", "pol.exe", "FFXiMain.dll", "explorer.exe", "plugplay.exe", "rpcss.exe",
    "svchost.exe", "winedevice.exe", "services.exe", "conhost.exe",
)
SIDECAR_SUFFIXES = ("/x87sidecar-coop", "/x87sidecar_entitled")
GAME_SUFFIXES = ("horizon-loader.exe", "Ashita-cli.exe", "pol.exe", "FFXiMain.dll")

# launchd variables that must be clear before a run so an old experiment cannot leak in.
GUARDED_VARIABLES = ("X87_PROFILE", "X87_SAMPLE", "X87_ENABLE_FMA_CONTRACT",
                     "DXVK_ENFORCE_NX", "WINE_DISABLE_NX_COMPAT",
                     "FFXI_ON_MAC_DISABLE_X87", "X87_STOCK_HASH_LIST", "X87_LOG_HASH_LIST",
                     "X87_DISABLE_X87_IR", "X87_DISABLE_ALL_FUSIONS", "X87_DISABLE_CACHE",
                     "X87_ENABLE_BRIDGE", "X87_BRIDGE_V2", "X87_NO_IR_CACHE", "X87_NO_TCO_CACHE")
OVERRIDE_PREFIXES = ("X87_", "DXVK_", "FFXI_ON_MAC_", "D3D9_", "MVK_", "WINE_DISABLE_NX_COMPAT",
                     "PERFSCENE_")
ADDON_SOURCE = HERE / "addons" / "perfscene"
# The in-world stage is only ever allowed against the local test world. A real world's
# character list must never receive the third Return.
LOCAL_WORLDS = ("Local LSB (Docker)", "Local server")
BLOCK_COUNTER_TAG = b"CNT0"

# Scene signatures from the DXVK frame log. The rules screen draws a few hundred primitives,
# the top-level menu draws several hundred more. Three consecutive matching rows are required.
RULES_SCENE = ("rules", lambda row: row["fps"] >= 30 and 250 <= row["draws"] <= 500)
MENU_SCENE = ("main menu", lambda row: row["fps"] >= 30 and 500 <= row["draws"] <= 1100)
CHARACTERS_SCENE = ("character list", lambda row: row["fps"] >= 30 and row["draws"] >= 1200)
# The world itself is recognised by the perfscene addon's marker, not by draw counts.
WORLD_TIMEOUT = 90


def log(message: str) -> None:
    print(f"[menu-run {time.strftime('%H:%M:%S')}] {message}", flush=True)


def run(argv: list[str], timeout: float = 30, **kwargs: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, text=True, capture_output=True, timeout=timeout, check=False,
                          **kwargs)


def process_rows() -> list[tuple[int, str]]:
    """Return (pid, comm) pairs. `comm` never includes arguments."""
    result = run(["/bin/ps", "-axo", "pid=,comm="], timeout=10)
    rows: list[tuple[int, str]] = []
    for line in result.stdout.splitlines():
        pid_text, separator, command = line.strip().partition(" ")
        if separator and pid_text.isdigit():
            rows.append((int(pid_text), command.strip()))
    return rows


def matching(suffixes: tuple[str, ...]) -> list[tuple[int, str]]:
    return [(pid, command) for pid, command in process_rows()
            if any(command.endswith(suffix) for suffix in suffixes)]


def process_exists(pid: int | None) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def send_signal(pids: list[int], signum: int) -> None:
    for pid in pids:
        try:
            os.kill(pid, signum)
        except OSError:
            pass


def launchctl_get(name: str) -> str:
    return run(["/bin/launchctl", "getenv", name], timeout=10).stdout.strip()


def launchctl_set(name: str, value: str) -> None:
    run(["/bin/launchctl", "setenv", name, value], timeout=10)


def launchctl_unset(name: str) -> None:
    run(["/bin/launchctl", "unsetenv", name], timeout=10)


def parse_override(text: str) -> tuple[str, str]:
    name, separator, value = text.partition("=")
    if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", name):
        raise argparse.ArgumentTypeError(f"override must look like NAME=value: {text!r}")
    if not name.startswith(OVERRIDE_PREFIXES):
        raise argparse.ArgumentTypeError(
            f"{name} is not a diagnostic variable; allowed prefixes: "
            + ", ".join(OVERRIDE_PREFIXES))
    return name, value


def block_profile_complete(path: Path) -> bool:
    """A sidecar block profile ends with counter sections only if it outlived its target."""
    try:
        with path.open("rb") as handle:
            handle.seek(max(0, path.stat().st_size - 512 * 1024))
            return BLOCK_COUNTER_TAG in handle.read()
    except OSError:
        return False


def ensure_window_tool() -> Path | None:
    if WINDOW_TOOL.is_file() and WINDOW_TOOL.stat().st_mtime >= WINDOW_SOURCE.stat().st_mtime:
        return WINDOW_TOOL
    WINDOW_TOOL.parent.mkdir(parents=True, exist_ok=True)
    build = run(["/usr/bin/xcrun", "swiftc", "-O", "-o", str(WINDOW_TOOL), str(WINDOW_SOURCE)],
                timeout=300)
    if build.returncode != 0:
        log(f"could not build game-window helper: {build.stderr.strip()[:400]}")
        return None
    return WINDOW_TOOL


def read_available(process: subprocess.Popen[str], sink: list[str], timeout: float = 0.0) -> None:
    if process.stdout is None:
        return
    while True:
        ready, _, _ = select.select([process.stdout], [], [], timeout)
        timeout = 0.0
        if not ready:
            return
        line = process.stdout.readline()
        if not line:
            return
        sink.append(line.rstrip("\n"))
        print(f"  recorder: {line.rstrip()}", flush=True)


def fps_rows(path: Path) -> list[dict[str, float]]:
    if not path.is_file():
        return []
    rows: list[dict[str, float]] = []
    try:
        with path.open(newline="", errors="replace") as handle:
            for raw in csv.DictReader(handle):
                try:
                    rows.append({"elapsed": float(raw["elapsed"]), "fps": float(raw["fps"]),
                                 "draws": float(raw["draws"])})
                except (KeyError, TypeError, ValueError):
                    continue
    except (OSError, csv.Error):
        return []
    return rows


class MenuRun:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.game_dir: Path = args.game_dir
        self.session: str | None = None
        self.session_dir: Path | None = None
        self.recorder: subprocess.Popen[str] | None = None
        self.recorder_lines: list[str] = []
        self.game_pid: int | None = None
        self.window_tool: Path | None = None
        self.window: dict[str, Any] | None = None
        self.set_variables: list[str] = []
        self.returns_sent = 0
        self.started = time.monotonic()
        self.record: dict[str, Any] = {
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "overrides": {name: value for name, value in args.env},
            "x87_profile": bool(args.x87_profile),
            "phases": {},
            "screenshots": [],
            "events": [],
        }

    # -- bookkeeping -------------------------------------------------------------------

    def event(self, label: str, **fields: Any) -> None:
        entry = {"elapsed": round(time.monotonic() - self.started, 2), "label": label, **fields}
        self.record["events"].append(entry)
        log(label + ("" if not fields else " " + json.dumps(fields, sort_keys=True)))

    def deadline_passed(self) -> bool:
        return time.monotonic() - self.started >= self.args.limit

    def write_record(self) -> None:
        if self.session_dir is None:
            return
        try:
            self.session_dir.mkdir(parents=True, exist_ok=True)
            (self.session_dir / "menu-run.json").write_text(
                json.dumps(self.record, indent=2, sort_keys=True) + "\n")
        except OSError:
            pass

    # -- preflight ---------------------------------------------------------------------

    def preflight(self) -> bool:
        stale = matching(RELATED_SUFFIXES)
        if stale:
            log("refusing to launch with related processes running:")
            for pid, command in stale:
                log(f"  {pid} {command}")
            return False
        leaked = {name: launchctl_get(name)
                  for name in GUARDED_VARIABLES + tuple(n for n, _ in self.args.env)}
        leaked = {name: value for name, value in leaked.items() if value}
        if leaked:
            log("refusing to launch while launchd still carries diagnostic variables: "
                + ", ".join(sorted(leaked)))
            log("clear them with: launchctl unsetenv NAME")
            return False
        if not APP.is_dir():
            log(f"missing app bundle: {APP}")
            return False
        if not self.args.no_return:
            self.window_tool = ensure_window_tool()
            if self.window_tool is None:
                return False
        if self.args.scenario:
            if self.args.world not in LOCAL_WORLDS:
                log(f"refusing an in-world scenario against {self.args.world!r}; "
                    f"only {LOCAL_WORLDS} are allowed")
                return False
            if not self.install_addon():
                return False
        return True

    def install_addon(self) -> bool:
        """Copy the perfscene addon into the game and make the local world's boot script load
        it. The boot script is a copy of default.txt plus one line, named after the profile so
        the HorizonXI profile is never touched."""
        target = self.game_dir / "addons" / "perfscene"
        try:
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy(ADDON_SOURCE / "perfscene.lua", target / "perfscene.lua")
            scripts = self.game_dir / "scripts"
            default = (scripts / "default.txt").read_text(errors="replace")
            boot = scripts / "perfscene.txt"
            if self.args.minimal_addons:
                # Ashita core plugins and binds only; the three addons the scenario needs.
                kept = [line for line in default.splitlines()
                        if not line.startswith("/addon load")]
                boot.write_text("\n".join(kept).rstrip("\n")
                                + "\n/addon load fps\n/addon load drawdistance\n"
                                + "/addon load perfscene\n")
            elif "/addon load perfscene" not in default:
                boot.write_text(default.rstrip("\n") + "\n/addon load perfscene\n")
            else:
                boot.write_text(default)
            profile = self.game_dir / "config" / "boot" / self.args.profile
            text = profile.read_text(errors="replace")
            lines = text.splitlines(keepends=True)
            for index, line in enumerate(lines):
                if line.strip().startswith("script") and "=" in line and not line.startswith(";"):
                    eol = "\r\n" if line.endswith("\r\n") else "\n"
                    lines[index] = "script      = perfscene.txt" + eol
                    break
            profile.write_text("".join(lines))
        except OSError as error:
            log(f"could not install the perfscene addon: {error}")
            return False
        self.event("perfscene addon installed", boot_script="scripts/perfscene.txt")
        return True

    def markers_path(self) -> Path:
        assert self.session_dir is not None
        return self.session_dir / "perfscene-markers.jsonl"

    def wait_for_marker(self, label: str, timeout: float) -> bool:
        """Wait for the addon to append a marker with this label to the capture directory."""
        assert self.recorder is not None
        deadline = min(time.monotonic() + timeout, self.started + self.args.limit)
        seen = 0
        while time.monotonic() < deadline:
            read_available(self.recorder, self.recorder_lines)
            if not process_exists(self.game_pid):
                self.event(f"{label}: game exited")
                return False
            try:
                rows = self.markers_path().read_text(errors="replace").splitlines()
            except OSError:
                rows = []
            for row in rows[seen:]:
                try:
                    marker = json.loads(row)
                except json.JSONDecodeError:
                    continue
                log(f"marker: {marker.get('label')}" + (
                    f" zone={marker['zone']}" if "zone" in marker else ""))
                if marker.get("label") == label:
                    self.record["phases"][label.replace(" ", "_") + "_s"] = round(
                        time.monotonic() - self.started, 1)
                    return True
            seen = len(rows)
            time.sleep(1)
        self.event(f"{label}: timed out")
        return False

    # -- recorder ----------------------------------------------------------------------

    def arm_recorder(self) -> bool:
        argv = [sys.executable, str(RECORDER), "--game-dir", str(self.game_dir),
                "--duration", str(self.args.capture_seconds),
                "--wait-timeout", str(self.args.wait_timeout),
                "--level", self.args.level, "--no-archive"]
        if self.args.sample_at:
            argv += ["--sample-at", self.args.sample_at,
                     "--sample-seconds", str(self.args.sample_seconds),
                     "--sample-interval-ms", str(self.args.sample_interval_ms)]
        self.recorder = subprocess.Popen(argv, cwd=HERE.parent.parent, stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                         text=True, bufsize=1, start_new_session=True)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and self.session is None:
            read_available(self.recorder, self.recorder_lines, timeout=1)
            for line in self.recorder_lines:
                match = re.search(r"Capture (\S+) armed", line)
                if match:
                    self.session = match.group(1)
                    break
            if self.recorder.poll() is not None:
                break
        if self.session is None:
            log("the recorder did not arm")
            return False
        self.session_dir = self.game_dir / CAPTURE_DIR / self.session
        self.record["session"] = self.session
        self.record["session_dir"] = str(self.session_dir)
        self.event("recorder armed", session=self.session)
        return True

    # -- launch ------------------------------------------------------------------------

    def wine_session_path(self) -> str:
        assert self.session_dir is not None
        return "Z:" + str(self.session_dir).replace("/", "\\")

    def apply_variables(self) -> None:
        variables = {name: value.replace("{session}", self.wine_session_path())
                     for name, value in self.args.env}
        if self.args.scenario and self.session_dir is not None:
            variables["PERFSCENE_SCENARIO"] = self.args.scenario
            variables["PERFSCENE_MARKERS"] = self.wine_session_path() + "\\perfscene-markers.jsonl"
        if self.args.x87_profile and self.session_dir is not None:
            variables["X87_PROFILE"] = str(self.session_dir / "x87-block-%p.prof")
        for name, value in variables.items():
            launchctl_set(name, value)
            self.set_variables.append(name)
            if launchctl_get(name) != value:
                raise RuntimeError(f"launchctl did not accept {name}")
        if variables:
            self.event("launchd variables set", names=sorted(variables))

    def clear_variables(self) -> None:
        for name in self.set_variables:
            launchctl_unset(name)
        remaining = [name for name in self.set_variables if launchctl_get(name)]
        self.record["launchd_variables_cleared"] = not remaining
        if remaining:
            log(f"WARNING: launchd variables still set: {remaining}")
        elif self.set_variables:
            self.event("launchd variables cleared", names=sorted(self.set_variables))
        self.set_variables = []

    def launch(self) -> bool:
        assert self.recorder is not None
        opened = run(["/usr/bin/open", "-a", str(APP), "--args", "--world", self.args.world,
                      "--play"], timeout=20)
        if opened.returncode != 0:
            log(f"open failed: {(opened.stdout + opened.stderr).strip()}")
            return False
        self.event("app launched")
        deadline = time.monotonic() + self.args.wait_timeout
        while time.monotonic() < deadline and self.game_pid is None:
            read_available(self.recorder, self.recorder_lines, timeout=1)
            for line in self.recorder_lines:
                match = re.search(r"Found game PID (\d+)", line)
                if match:
                    self.game_pid = int(match.group(1))
                    break
            if self.recorder.poll() is not None:
                break
        if self.game_pid is None:
            log("the game process did not appear")
            return False
        self.record["game_pid"] = self.game_pid
        self.event("game process found", pid=self.game_pid)
        return True

    # -- scene handling ----------------------------------------------------------------

    def wait_for_scene(self, scene: tuple[str, Callable[[dict[str, float]], bool]],
                       timeout: float) -> bool:
        assert self.recorder is not None and self.session_dir is not None
        label, predicate = scene
        fps_path = self.session_dir / "fps.csv"
        deadline = min(time.monotonic() + timeout, self.started + self.args.limit)
        last: tuple[float, float, float] | None = None
        while time.monotonic() < deadline:
            read_available(self.recorder, self.recorder_lines)
            if not process_exists(self.game_pid):
                self.event(f"{label}: game exited")
                return False
            rows = fps_rows(fps_path)[-3:]
            if rows:
                current = (rows[-1]["elapsed"], rows[-1]["fps"], rows[-1]["draws"])
                if current != last:
                    log(f"{label}: t={current[0]:.1f}s fps={current[1]:.2f} draws={current[2]:.0f}")
                    last = current
                if len(rows) == 3 and all(predicate(row) for row in rows):
                    self.record["phases"][label.replace(" ", "_") + "_stable_s"] = rows[-1]["elapsed"]
                    self.event(f"{label} stable", elapsed=rows[-1]["elapsed"],
                               draws=rows[-1]["draws"])
                    return True
            time.sleep(1)
        self.event(f"{label}: timed out")
        return False

    def screenshot(self, label: str) -> None:
        if self.window_tool is None or self.session_dir is None or self.game_pid is None:
            return
        found = run([str(self.window_tool), "find", str(self.game_pid)], timeout=15)
        if found.returncode != 0:
            log(f"screenshot {label}: {found.stderr.strip()}")
            return
        try:
            self.window = json.loads(found.stdout)
        except json.JSONDecodeError:
            return
        path = self.session_dir / f"screen-{label}.png"
        shot = run(["/usr/sbin/screencapture", "-x", "-l", str(self.window["window_id"]),
                    str(path)], timeout=20)
        if shot.returncode == 0 and path.is_file():
            self.record["screenshots"].append(path.name)
            self.event("screenshot", file=path.name)

    def send_one_return(self) -> bool:
        if self.returns_sent >= self.args.max_returns:
            raise RuntimeError(f"Return {self.returns_sent + 1} exceeds the "
                               f"{self.args.max_returns} allowed for this run")
        assert self.window_tool is not None and self.game_pid is not None
        result = run([str(self.window_tool), "return", str(self.game_pid)], timeout=30)
        output = (result.stdout + result.stderr).strip()
        if result.returncode != 0:
            self.event("Return refused", detail=output)
            return False
        self.returns_sent += 1
        self.record["returns_sent"] = self.returns_sent
        self.event("Return sent", detail=output)
        return True

    # -- cleanup -----------------------------------------------------------------------

    def cleanup(self) -> None:
        # Phase 1: the game process this run launched, then a bounded wait for its sidecar.
        # Only that pid. A game the driver did not start belongs to a person at the keyboard,
        # and a bounded run once terminated one mid character creation. If another game
        # process is alive, leave it and the rest of the Wine stack alone entirely.
        foreign = [pid for pid, _ in matching(GAME_SUFFIXES) if pid != self.game_pid]
        if foreign:
            self.event("cleanup skipped: a game process this run did not launch is alive",
                       pids=foreign)
            self.record["leftover_processes"] = [
                f"{pid} {command}" for pid, command in matching(RELATED_SUFFIXES)]
            return
        targets = [self.game_pid] if self.game_pid and process_exists(self.game_pid) else []
        if targets:
            self.event("cleanup phase 1", pids=targets)
            send_signal(targets, signal.SIGTERM)
            waited = 0.0
            while waited < self.args.sidecar_grace:
                time.sleep(0.5)
                waited += 0.5
                if not matching(GAME_SUFFIXES) and not matching(SIDECAR_SUFFIXES):
                    break
            self.record["sidecar_grace_used_s"] = waited
            self.event("cleanup phase 1 done", waited_s=waited,
                       sidecars_left=len(matching(SIDECAR_SUFFIXES)))

        # Phase 2: the broad sweep.
        remaining = [pid for pid, _ in matching(RELATED_SUFFIXES)]
        if remaining:
            send_signal(remaining, signal.SIGTERM)
            time.sleep(5)
        remaining = [pid for pid, _ in matching(RELATED_SUFFIXES)]
        if remaining:
            send_signal(remaining, signal.SIGKILL)
            time.sleep(2)
        for server in sorted(RUNTIMES.glob("*/wine/bin/wineserver")):
            try:
                subprocess.run([str(server), "-k"], env={**os.environ, "WINEPREFIX": str(PREFIX)},
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
            except (OSError, subprocess.TimeoutExpired):
                pass
        run(["/usr/bin/osascript", "-e", f'tell application id "{APP_BUNDLE_ID}" to quit'],
            timeout=15)

        if self.recorder is not None:
            try:
                self.recorder.wait(timeout=90)
            except subprocess.TimeoutExpired:
                self.recorder.terminate()
                try:
                    self.recorder.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    self.recorder.kill()
            read_available(self.recorder, self.recorder_lines)

        leftovers = matching(RELATED_SUFFIXES)
        self.record["leftover_processes"] = [f"{pid} {command}" for pid, command in leftovers]
        if leftovers:
            log("WARNING: related processes remain:")
            for pid, command in leftovers:
                log(f"  {pid} {command}")
        else:
            self.event("cleanup complete: no related processes remain")

    def collect_profile(self) -> None:
        if not self.args.x87_profile or self.session_dir is None or self.game_pid is None:
            return
        profile = self.session_dir / f"x87-block-{self.game_pid}.prof"
        complete = profile.is_file() and block_profile_complete(profile)
        self.record["x87_block_profile"] = {
            "file": profile.name, "exists": profile.is_file(), "complete": complete,
            "size": profile.stat().st_size if profile.is_file() else 0,
        }
        self.event("x87 block profile", file=profile.name, complete=complete)
        analyzer = self.args.profile_analyzer
        if complete and analyzer and Path(analyzer).is_file():
            report = self.session_dir / "x87-block-analysis.txt"
            result = run([analyzer, "--rank-by", "emit", "--max-rows", "120", "--hot-addrs", "100",
                          "--frag-rows", "60", str(profile)], timeout=300)
            report.write_text(result.stdout + result.stderr)
            self.record["x87_block_profile"]["analysis"] = report.name
            self.event("x87 block profile analyzed", file=report.name)

    # -- main flow ---------------------------------------------------------------------

    def execute(self) -> int:
        if not self.preflight():
            return 3
        try:
            if not self.arm_recorder():
                return 4
            self.apply_variables()
            if not self.launch():
                return 5
            if not self.wait_for_scene(RULES_SCENE, self.args.rules_timeout):
                return 6
            time.sleep(2)
            self.screenshot("rules")
            if self.args.no_return:
                self.event("stopping at the rules screen as requested")
            else:
                if not self.send_one_return():
                    return 7
                if not self.wait_for_scene(MENU_SCENE, self.args.menu_timeout):
                    return 8
                time.sleep(3)
                self.screenshot("main-menu")
                if self.args.characters:
                    # "Select Character" is highlighted on the top-level menu. One more Return
                    # opens the character list, which is the authorized limit. Logging in
                    # would need a third Return and that is refused by max_returns.
                    if not self.send_one_return():
                        return 9
                    if not self.wait_for_scene(CHARACTERS_SCENE, self.args.menu_timeout):
                        return 10
                    time.sleep(3)
                    self.screenshot("characters")
                    if self.args.scenario:
                        # Local test world only (checked in preflight). The third Return
                        # picks the highlighted character; the lobby's confirmation is the
                        # fourth. The addon marks "in world" once the party zone is real.
                        for _ in range(2):
                            if not self.send_one_return():
                                return 11
                            time.sleep(2)
                        if not self.wait_for_marker("in world", WORLD_TIMEOUT):
                            return 12
                        self.screenshot("world")
                        if not self.wait_for_marker("done", self.args.limit):
                            return 13
                        self.screenshot("scenario-done")
            hold_until = min(time.monotonic() + self.args.hold, self.started + self.args.limit)
            self.event("holding", seconds=round(hold_until - time.monotonic(), 1))
            while time.monotonic() < hold_until and process_exists(self.game_pid):
                read_available(self.recorder, self.recorder_lines) if self.recorder else None
                time.sleep(1)
            self.screenshot("end")
            return 0
        finally:
            self.record["returns_sent"] = self.returns_sent
            if process_exists(self.game_pid):
                self.screenshot("final")
            self.cleanup()
            self.clear_variables()
            self.collect_profile()
            self.record["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            self.write_record()
            if self.session_dir and (self.session_dir / "summary.txt").is_file():
                print((self.session_dir / "summary.txt").read_text(), end="")
            if self.session_dir:
                log(f"session: {self.session_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game-dir", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--world", default="HorizonXI")
    parser.add_argument("--level", choices=("standard", "standard-nosample", "deep"),
                        default="standard-nosample",
                        help="recorder level; standard adds the 1 kHz guest-PC sampler")
    parser.add_argument("--limit", type=int, default=180,
                        help="hard wall-clock limit for the whole game session in seconds")
    parser.add_argument("--capture-seconds", type=int, default=150)
    parser.add_argument("--wait-timeout", type=int, default=150,
                        help="seconds to wait for the game process; it can take 40 to 50")
    parser.add_argument("--rules-timeout", type=int, default=100)
    parser.add_argument("--menu-timeout", type=int, default=60)
    parser.add_argument("--hold", type=int, default=25,
                        help="seconds to keep recording after the target scene settles")
    parser.add_argument("--sidecar-grace", type=float, default=8.0,
                        help="seconds to let x87sidecar finalize after the game exits")
    parser.add_argument("--no-return", action="store_true",
                        help="stop at the rules screen without sending any key")
    parser.add_argument("--characters", action="store_true",
                        help="after the main menu, send one more Return to open the character "
                             "list and measure that transition too; never logs in")
    parser.add_argument("--scenario", default="",
                        help="local test world only: log the test character in and run this "
                             "perfscene scenario (city, field); implies --characters")
    parser.add_argument("--sample-at", default="",
                        help="native /usr/bin/sample start offsets in seconds after the game "
                             "process appears, comma-separated; passed to the recorder")
    parser.add_argument("--sample-seconds", type=int, default=5)
    parser.add_argument("--sample-interval-ms", type=int, default=10)
    parser.add_argument("--minimal-addons", action="store_true",
                        help="scenario runs load only fps, drawdistance and perfscene instead "
                             "of the world's full addon list, for an addon-cost A/B")
    parser.add_argument("--profile", default="lsb-docker.ini",
                        help="boot profile the scenario stage edits to load the addon")
    parser.add_argument("--x87-profile", action="store_true",
                        help="collect an x87sidecar block-execution profile for this launch")
    parser.add_argument("--profile-analyzer", default=os.environ.get("X87_PROFILE_ANALYZE"),
                        help="path to x87sidecar's profile_analyze; runs on a complete profile")
    parser.add_argument("--env", action="append", type=parse_override, default=[],
                        metavar="NAME=value",
                        help="one-launch diagnostic override set through launchd and removed "
                             "afterwards; repeatable; X87_, DXVK_, D3D9_, MVK_, FFXI_ON_MAC_ only; "
                             "{session} expands to the capture directory as a Wine path")
    args = parser.parse_args()
    args.game_dir = args.game_dir.expanduser().resolve()
    if args.scenario:
        args.characters = True
    args.max_returns = 0 if args.no_return else (4 if args.scenario else 2 if args.characters else 1)
    if not args.game_dir.is_dir():
        parser.error(f"game directory does not exist: {args.game_dir}")
    if not RECORDER.is_file():
        parser.error(f"missing recorder: {RECORDER}")
    if not shutil.which("swiftc") and not WINDOW_TOOL.is_file() and not args.no_return:
        parser.error("swiftc is required to build the game-window helper")

    runner = MenuRun(args)

    def interrupted(signum: int, _frame: Any) -> None:
        raise KeyboardInterrupt(signum)

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    try:
        return runner.execute()
    except KeyboardInterrupt:
        log("interrupted; cleanup already ran")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
