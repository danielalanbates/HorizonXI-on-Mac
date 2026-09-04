#!/usr/bin/env python3
"""Capture one HorizonXI launch without driving the game's UI.

Run this first, then press Play in FFXI on Mac and use the game normally. The launcher enables
the vendored DXVK probes for exactly one launch while this process records host-side CPU, per-
process disk I/O, memory, thread CPU time, network totals, and timed native samples.

No process command line or boot profile is written to the report. HorizonXI credentials can be
present in both, so collecting either would make a diagnostic archive unsafe to share.
"""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import ctypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time
from typing import Any


APP_SUPPORT = Path.home() / "Library/Application Support/HorizonXI-on-Mac"
REQUEST_FILE = APP_SUPPORT / "performance-capture-request.json"
CAPTURE_DIR = Path("logs/performance-captures")
DEFAULT_GAME = Path.home() / "Games/FFXI/HorizonXI"
GAME_NAME = "horizon-loader"
PROBE_VARIABLES = (
    "DXVK_FPS_LOG", "DXVK_PRESENT_PROBE", "DXVK_STALL_LOG", "DXVK_WAIT_LOG",
    "DXVK_FLUSH_LOG", "DXVK_QUEUE_LOG", "D3D9_LOCKIMAGE_PROBE", "DXVK_DRAW_PROBE",
    "DXVK_UP_PROBE", "DXVK_SAMPLE_LOG", "DXVK_FB_PROBE", "DXVK_PASS_PROBE",
    "DXVK_PRESENT_STAGE_LOG", "DXVK_SUBMIT_STAGE_LOG", "DXVK_UP_STAGE_LOG",
    "D3D9_RT_READBACK_FENCE",
)
SENSITIVE_OPTION = re.compile(
    r"(?i)(--(?:pass(?:word)?|user(?:name)?)(?:=|\s+|\"\s*,\s*\")?)([^\s\",']+)"
)
SENSITIVE_ASSIGNMENT = re.compile(
    r"(?im)^([^=\n]*(?:PASS|PASSWORD|TOKEN|SECRET|API_KEY)[^=\n]*)=.*$"
)


class RUsageInfoV4(ctypes.Structure):
    _fields_ = [("ri_uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "ri_user_time", "ri_system_time", "ri_pkg_idle_wkups",
            "ri_interrupt_wkups", "ri_pageins", "ri_wired_size",
            "ri_resident_size", "ri_phys_footprint", "ri_proc_start_abstime",
            "ri_proc_exit_abstime", "ri_child_user_time", "ri_child_system_time",
            "ri_child_pkg_idle_wkups", "ri_child_interrupt_wkups",
            "ri_child_pageins", "ri_child_elapsed_abstime", "ri_diskio_bytesread",
            "ri_diskio_byteswritten", "ri_cpu_time_qos_default",
            "ri_cpu_time_qos_maintenance", "ri_cpu_time_qos_background",
            "ri_cpu_time_qos_utility", "ri_cpu_time_qos_legacy",
            "ri_cpu_time_qos_user_initiated", "ri_cpu_time_qos_user_interactive",
            "ri_billed_system_time", "ri_serviced_system_time", "ri_logical_writes",
            "ri_lifetime_max_phys_footprint", "ri_instructions", "ri_cycles",
            "ri_billed_energy", "ri_serviced_energy", "ri_interval_max_phys_footprint",
            "ri_runnable_time",
        )
    ]


def run(argv: list[str], timeout: float = 30) -> subprocess.CompletedProcess[str]:
    """Run fixed argv without a shell so paths and diagnostics cannot become commands."""
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return subprocess.CompletedProcess(argv, 127, "", str(error))


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def redact(text: str) -> str:
    text = SENSITIVE_OPTION.sub(lambda m: m.group(1) + "[REDACTED]", text)
    return SENSITIVE_ASSIGNMENT.sub(lambda m: m.group(1) + "=[REDACTED]", text)


def game_pids() -> set[int]:
    """Find the renderer process from comm only. Never inspect or print its argument list."""
    result = run(["/bin/ps", "-Ao", "pid=", "-o", "comm="])
    found: set[int] = set()
    for line in result.stdout.splitlines():
        pid_text, _, command = line.strip().partition(" ")
        if pid_text.isdigit() and GAME_NAME in command.lower():
            found.add(int(pid_text))
    return found


def process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def wait_for_game(existing: set[int], timeout: float, stop: threading.Event) -> int | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and not stop.is_set():
        candidates = sorted(game_pids() - existing)
        if candidates:
            return candidates[-1]
        time.sleep(0.5)
    return None


def proc_rusage(pid: int) -> dict[str, int]:
    try:
        libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        function = libproc.proc_pid_rusage
        function.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
        function.restype = ctypes.c_int
        info = RUsageInfoV4()
        if function(pid, 4, ctypes.byref(info)) != 0:
            return {}
        return {
            "user_ns": info.ri_user_time,
            "system_ns": info.ri_system_time,
            "pageins": info.ri_pageins,
            "resident_bytes": info.ri_resident_size,
            "phys_footprint_bytes": info.ri_phys_footprint,
            "disk_read_bytes": info.ri_diskio_bytesread,
            "disk_write_bytes": info.ri_diskio_byteswritten,
            "instructions": info.ri_instructions,
            "cycles": info.ri_cycles,
            "runnable_ns": info.ri_runnable_time,
            "idle_wakeups": info.ri_pkg_idle_wkups,
            "interrupt_wakeups": info.ri_interrupt_wkups,
        }
    except (AttributeError, OSError):
        return {}


class ProcTaskInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "pti_virtual_size", "pti_resident_size", "pti_total_user", "pti_total_system",
        "pti_threads_user", "pti_threads_system")] + [(name, ctypes.c_int32) for name in (
        "pti_policy", "pti_faults", "pti_pageins", "pti_cow_faults", "pti_messages_sent",
        "pti_messages_received", "pti_syscalls_mach", "pti_syscalls_unix", "pti_csw",
        "pti_threadnum", "pti_numrunning", "pti_priority")]


PROC_PIDTASKINFO = 4


def proc_task_info(pid: int) -> dict[str, int]:
    """Kernel-side counters that rusage lacks: page faults, copy-on-write faults, Mach and
    BSD syscall counts, context switches, and live thread count. Faults are the direct
    signature of first-touch heap growth, which ps CPU and disk counters cannot separate from
    ordinary user-mode work."""
    try:
        libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        function = libproc.proc_pidinfo
        function.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p,
                             ctypes.c_int]
        function.restype = ctypes.c_int
        info = ProcTaskInfo()
        if function(pid, PROC_PIDTASKINFO, 0, ctypes.byref(info), ctypes.sizeof(info)) \
                != ctypes.sizeof(info):
            return {}
        return {
            "faults": info.pti_faults, "cow_faults": info.pti_cow_faults,
            "syscalls_mach": info.pti_syscalls_mach, "syscalls_unix": info.pti_syscalls_unix,
            "context_switches": info.pti_csw, "messages_sent": info.pti_messages_sent,
            "messages_received": info.pti_messages_received, "threads": info.pti_threadnum,
            "threads_running": info.pti_numrunning,
            "task_user_ns": info.pti_total_user, "task_system_ns": info.pti_total_system,
        }
    except (AttributeError, OSError):
        return {}


def ps_metrics(pid: int) -> dict[str, Any]:
    result = run([
        "/bin/ps", "-p", str(pid), "-o", "%cpu=", "-o", "%mem=", "-o", "rss=",
        "-o", "vsize=", "-o", "state=", "-o", "etime=", "-o", "comm=",
    ])
    parts = result.stdout.strip().split(maxsplit=6)
    if len(parts) != 7:
        return {}
    try:
        return {
            "cpu_percent": float(parts[0]), "memory_percent": float(parts[1]),
            "rss_kb": int(parts[2]), "vsize_kb": int(parts[3]),
            "state": parts[4], "process_elapsed": parts[5], "comm": parts[6],
        }
    except ValueError:
        return {}


def parse_clock(value: str) -> float:
    fields = value.split(":")
    try:
        if len(fields) == 2:
            return int(fields[0]) * 60 + float(fields[1])
        if len(fields) == 3:
            return int(fields[0]) * 3600 + int(fields[1]) * 60 + float(fields[2])
    except ValueError:
        pass
    return 0.0


def thread_snapshot(pid: int) -> list[dict[str, Any]]:
    """Parse only thread rows from ps -M. The aggregate row contains secret-bearing argv."""
    result = run(["/bin/ps", "-M", "-p", str(pid)])
    rows: list[dict[str, Any]] = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        # Thread rows omit USER, TT, and COMMAND: PID CPU STATE PRI STIME UTIME.
        if len(fields) != 6 or not fields[0].isdigit():
            continue
        try:
            rows.append({
                "index": len(rows), "cpu_percent": float(fields[1]), "state": fields[2],
                "system_s": parse_clock(fields[4]), "user_s": parse_clock(fields[5]),
            })
        except ValueError:
            continue
    return rows


FOOTPRINT_UNITS = {"B": 1, "KB": 1024, "MB": 1024 ** 2, "GB": 1024 ** 3}


def parse_footprint(text: str) -> dict[str, int]:
    """Dirty bytes per region category from `footprint -p PID`. IOAccelerator and IOKit are
    Metal allocations; MALLOC_* and VM_ALLOCATE are the Wine heap and mapped buffers. Watching
    these per second shows which allocator churns while the game faults."""
    result: dict[str, int] = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 8 or parts[0] == "---":
            continue
        try:
            dirty = float(parts[0]) * FOOTPRINT_UNITS[parts[1]]
            regions = int(parts[6])
        except (ValueError, KeyError):
            continue
        category = "_".join(parts[7:]).lower().replace("(", "").replace(")", "")
        category = re.sub(r"[^a-z0-9_]+", "_", category).strip("_")
        if category in ("total",):
            continue
        result[category + "_dirty_bytes"] = int(dirty)
        result[category + "_regions"] = regions
    match = re.search(r"phys_footprint:\s+([0-9.]+)\s+([KMG]?B)", text)
    if match:
        result["phys_footprint_bytes"] = int(float(match.group(1)) * FOOTPRINT_UNITS[match.group(2)])
    return result


def footprint_stats(pid: int) -> dict[str, int]:
    result = run(["/usr/bin/footprint", "-p", str(pid)], timeout=10)
    return parse_footprint(result.stdout)


def vm_stats() -> dict[str, int]:
    result = run(["/usr/bin/vm_stat"])
    page_match = re.search(r"page size of (\d+) bytes", result.stdout)
    page_size = int(page_match.group(1)) if page_match else 4096
    values: dict[str, int] = {"page_size": page_size}
    for line in result.stdout.splitlines():
        match = re.match(r"([^:]+):\s+([0-9]+)\.", line)
        if match:
            key = re.sub(r"[^a-z0-9]+", "_", match.group(1).lower()).strip("_")
            values[key + "_bytes"] = int(match.group(2)) * page_size
    return values


GPU_FIELDS = {
    "Device Utilization %": "device_utilization_percent",
    "Renderer Utilization %": "renderer_utilization_percent",
    "Tiler Utilization %": "tiler_utilization_percent",
    "In use system memory": "in_use_system_memory_bytes",
    "Alloc system memory": "allocated_system_memory_bytes",
    "recoveryCount": "recovery_count",
    "lastRecoveryTime": "last_recovery_time",
}


def parse_gpu_stats(text: str) -> dict[str, int]:
    """Keep only safe numeric counters from IOAccelerator's statistics property."""
    line = next((item for item in text.splitlines() if '"PerformanceStatistics"' in item), "")
    raw = {name: int(value) for name, value in re.findall(r'"([^"]+)"=(-?\d+)', line)}
    return {output: raw[name] for name, output in GPU_FIELDS.items() if name in raw}


def gpu_stats() -> dict[str, int]:
    result = run(["/usr/sbin/ioreg", "-r", "-c", "IOAccelerator", "-l"], timeout=10)
    return parse_gpu_stats(result.stdout)


def sha256(path: Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError:
        return None


def file_identity(path: Path) -> dict[str, Any]:
    identity: dict[str, Any] = {"path": str(path), "exists": path.is_file()}
    if not path.is_file():
        return identity
    identity["size"] = path.stat().st_size
    identity["sha256"] = sha256(path)
    identity["file"] = run(["/usr/bin/file", "-b", str(path)]).stdout.strip()
    if "d3d9" in path.name.lower():
        try:
            data = path.read_bytes()
            identity["supported_probes"] = [
                variable for variable in PROBE_VARIABLES if variable.encode() in data
            ]
        except OSError:
            pass
    if "x87sidecar" in path.name.lower():
        try:
            data = path.read_bytes()
            identity["supported_features"] = {
                "target_pid_sample_paths": (
                    b"cannot expand %%p because the target pid" in data
                ),
                "guest_pc_sampler": b"x87sidecar guest-pc sample profile" in data,
            }
        except OSError:
            pass
    return identity


def identities(game: Path) -> list[dict[str, Any]]:
    prefix = Path.home() / "Applications/FFXI on Mac Wine.app/Contents/SharedSupport/prefix10"
    candidates = [
        Path("/Applications/FFXI-on-Mac.app/Contents/Resources/dxvk-1.10.3-x32-d3d9-horizonxi.dll"),
        Path("/Applications/FFXI-on-Mac.app/Contents/Resources/x87sidecar-coop"),
        game / "d3d9.dll",
        game / "bootloader/d3d9.dll",
        game / "SquareEnix/FINAL FANTASY XI/d3d9.dll",
        game / "SquareEnix/PlayOnlineViewer/d3d9.dll",
        prefix / "drive_c/windows/syswow64/d3d9.dll",
        game / "d3d8.dll",
        game / "d3d8to9.dll",
    ]
    runtimes = APP_SUPPORT / "runtimes"
    if runtimes.is_dir():
        candidates.extend(sorted(runtimes.glob("*/wine/bin/wine")))
    return [file_identity(path) for path in candidates]


def system_manifest(game: Path, session: str, level: str, duration: int) -> dict[str, Any]:
    commands = {
        "sw_vers": ["/usr/bin/sw_vers"],
        "uname": ["/usr/bin/uname", "-a"],
        "hardware": ["/usr/sbin/sysctl", "-n", "hw.model", "hw.memsize", "machdep.cpu.brand_string"],
        "volume": ["/bin/df", "-k", str(game)],
        "disk": ["/usr/sbin/diskutil", "info", str(game)],
        "graphics": ["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"],
    }
    return {
        "session": session, "level": level, "duration_s": duration,
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "game_directory": str(game),
        "commands": {name: run(argv, timeout=60).stdout.strip() for name, argv in commands.items()},
        "files": identities(game),
        "privacy": "Process argv and boot profiles are intentionally excluded.",
    }


def write_request(game: Path, session: str, level: str, timeout: int) -> None:
    request = {
        "session": session,
        "expiresAt": time.time() + timeout + 60,
        "gameDirectory": str(game.resolve()),
        "level": level,
    }
    atomic_json(REQUEST_FILE, request)


def remove_own_request(session: str) -> None:
    try:
        current = json.loads(REQUEST_FILE.read_text())
        if current.get("session") == session:
            REQUEST_FILE.unlink(missing_ok=True)
    except (OSError, json.JSONDecodeError):
        pass


def write_redacted(source: Path, destination: Path) -> None:
    try:
        destination.write_text(redact(source.read_text(errors="replace")))
    except OSError:
        pass


def static_process_files(pid: int, output: Path, label: str) -> None:
    for name, argv in {
        f"vmmap-{label}.txt": ["/usr/bin/vmmap", "-summary", str(pid)],
        f"footprint-{label}.txt": ["/usr/bin/footprint", "-p", str(pid), "-f", "bytes"],
        f"open-files-{label}.txt": ["/usr/sbin/lsof", "-nP", "-p", str(pid)],
    }.items():
        result = run(argv, timeout=60)
        (output / name).write_text(redact(result.stdout + result.stderr))


def start_stream(argv: list[str], path: Path) -> tuple[subprocess.Popen[bytes], Any] | None:
    try:
        handle = path.open("wb")
        process = subprocess.Popen(argv, stdout=handle, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL)
        return process, handle
    except OSError as error:
        path.write_text(str(error) + "\n")
        return None


def native_sample(pid: int, seconds: int, interval_ms: int,
                  destination: Path, stop: threading.Event) -> None:
    if stop.is_set() or not process_exists(pid):
        return
    result = run(["/usr/bin/sample", str(pid), str(seconds), str(interval_ms),
                  "-mayDie", "-file",
                  str(destination)], timeout=seconds + 45)
    if result.returncode and not destination.exists():
        destination.write_text(result.stdout + result.stderr)


def marker_reader(path: Path, started: float, stop: threading.Event, lock: threading.Lock) -> None:
    while not stop.is_set():
        line = sys.stdin.readline()
        if not line:
            return
        label = line.strip() or "manual marker"
        record = {"epoch": time.time(), "elapsed": round(time.monotonic() - started, 3),
                  "label": label}
        with lock:
            with path.open("a") as handle:
                handle.write(json.dumps(record, sort_keys=True) + "\n")


def read_numeric_csv(path: Path) -> list[dict[str, float]]:
    if not path.is_file():
        return []
    rows: list[dict[str, float]] = []
    try:
        with path.open(newline="", errors="replace") as handle:
            reader = csv.DictReader(handle)
            for raw in reader:
                row: dict[str, float] = {}
                for key, value in raw.items():
                    try:
                        row[key] = float(value) if key is not None and value is not None else 0.0
                    except ValueError:
                        pass
                if row:
                    rows.append(row)
    except (OSError, csv.Error):
        pass
    return rows


def median_fields(rows: list[dict[str, float]]) -> dict[str, float]:
    keys = sorted({key for row in rows for key in row})
    return {key: round(statistics.median([row[key] for row in rows if key in row]), 3)
            for key in keys}


def stage_summary(path: Path, idle_phases: set[str] | None = None) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        with path.open(newline="", errors="replace") as handle:
            rows = list(csv.DictReader(handle))
    except (OSError, csv.Error):
        return {}
    parsed = []
    for row in rows:
        try:
            parsed.append({**row, "phase_ms": float(row.get("phase_ms", 0))})
        except (TypeError, ValueError):
            continue
    if not parsed:
        return {}
    idle_phases = idle_phases or set()
    longest = max(parsed, key=lambda row: row["phase_ms"])
    active = [row for row in parsed if row.get("phase") not in idle_phases]
    longest_active = max(active, key=lambda row: row["phase_ms"], default=None)
    last = parsed[-1]
    summary = {
        "samples": len(parsed),
        "last_phase": last.get("phase", "unknown"),
        "last_phase_ms": round(last["phase_ms"], 3),
        "longest_phase": longest.get("phase", "unknown"),
        "longest_phase_ms": round(longest["phase_ms"], 3),
    }
    if longest_active:
        summary["longest_active_phase"] = longest_active.get("phase", "unknown")
        summary["longest_active_phase_ms"] = round(longest_active["phase_ms"], 3)
    return summary


def x87_summary(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"status": "no_log"}
    try:
        log = path.read_text(errors="replace")
    except OSError:
        return {"status": "no_log"}
    services = log.count("[rosettax87] cooperative service registered:")
    attaches = log.count("[rosettax87] cooperative attach:")
    failures = log.count("cooperative handshake receive failed")
    rates = [int(value) for value in re.findall(r"sidecar:\s+(\d+) req/s", log)]
    sampler_starts = log.count("[rosettax87] X87_SAMPLE: sampling to")
    sampler_latches = log.count("[rosettax87] X87_SAMPLE: LATCHED onto")
    sampler_failures = log.count("[rosettax87] X87_SAMPLE: FAILED")
    disabled = "x87 acceleration is off for this world" in log
    if disabled:
        status = "disabled"
    elif failures:
        status = "handshake_failed"
    elif attaches >= 2 and any(rates):
        status = "active"
    elif attaches:
        status = "handshake_seen_no_throughput"
    else:
        status = "no_handshake_evidence"
    result: dict[str, Any] = {
        "status": status,
        "services_registered": services,
        "cooperative_attaches": attaches,
        "handshake_failures": failures,
        "throughput_samples": len(rates),
        "samplers_started": sampler_starts,
        "samplers_latched": sampler_latches,
        "sampler_failures": sampler_failures,
    }
    if rates:
        result.update({
            "throughput_median_requests_s": round(statistics.median(rates), 1),
            "throughput_max_requests_s": max(rates),
            "throughput_nonzero_samples": sum(rate > 0 for rate in rates),
        })
    return result


def parse_x87_scalar(value: str) -> Any:
    if re.fullmatch(r"-?0x[0-9a-fA-F]+", value):
        return int(value, 0)
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if re.fullmatch(r"-?(?:\d+\.\d*|\d*\.\d+)", value):
        return float(value)
    return value


def parse_x87_record(text: str) -> dict[str, Any]:
    """Parse one self-contained x87sidecar guest-PC profile record."""
    if "# x87sidecar guest-pc sample profile" not in text:
        return {}
    header: dict[str, Any] = {}
    raw_sections: dict[str, list[str]] = {}
    section: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            raw_sections.setdefault(section, [])
            continue
        if line.startswith("end_window "):
            header["end_window"] = parse_x87_scalar(line.split(maxsplit=1)[1])
            continue
        if section is not None:
            raw_sections[section].append(line)
            continue
        key, separator, value = line.partition(" ")
        if separator:
            header[key] = parse_x87_scalar(value.strip())

    modules = []
    for line in raw_sections.get("modules", []):
        fields = line.split(maxsplit=4)
        if len(fields) != 5:
            continue
        try:
            modules.append({
                "base": int(fields[0], 0), "size": int(fields[1], 0),
                "kind": fields[2], "state": fields[3], "path": fields[4],
            })
        except ValueError:
            continue

    def address_rows(name: str, field_names: tuple[str, ...]) -> list[dict[str, Any]]:
        rows = []
        for line in raw_sections.get(name, []):
            fields = line.split(maxsplit=len(field_names) - 1)
            if len(fields) != len(field_names):
                continue
            try:
                row = {key: value for key, value in zip(field_names, fields)}
                for key in ("tid", "pc", "count", "svc"):
                    if key in row:
                        row[key] = int(row[key], 0)
                rows.append(row)
            except ValueError:
                continue
        return rows

    stacks = []
    for line in raw_sections.get("stacks", []):
        fields = line.split(maxsplit=2)
        if len(fields) != 3:
            continue
        try:
            stacks.append({
                "tid": int(fields[0], 0),
                "pcs": [int(value, 0) for value in fields[1].split(";")],
                "count": int(fields[2]),
            })
        except ValueError:
            continue

    return {
        "header": header,
        "modules": modules,
        "leaves": address_rows("leaves", ("tid", "pc", "count")),
        "host_leaves": address_rows(
            "host_leaves", ("tid", "pc", "count", "reason")),
        "host_syscalls": address_rows(
            "host_syscalls", ("tid", "pc", "svc", "count")),
        "stacks": stacks,
    }


def read_x87_windows(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return []
    records: list[dict[str, Any]] = []
    current: list[str] = []
    for line in lines:
        if line == "# x87sidecar guest-pc sample profile":
            if current:
                parsed = parse_x87_record("\n".join(current))
                if parsed.get("header", {}).get("end_window") is not None:
                    records.append(parsed)
            current = [line]
        elif current:
            current.append(line)
    if current:
        parsed = parse_x87_record("\n".join(current))
        # A kill during an append can leave the last record incomplete. The
        # explicit trailer is the commit marker; never treat a partial record as data.
        if parsed.get("header", {}).get("end_window") is not None:
            records.append(parsed)
    return records


HOST_SYSCALL_NAMES = {
    3: "read", 4: "write", 93: "select", 184: "sigreturn", 301: "psynch_mutexwait",
    302: "psynch_mutexdrop", 305: "psynch_cvwait", 334: "__semwait_signal", 363: "kevent64",
    372: "thread_selfid", 374: "kevent_qos", 375: "kevent_id", 515: "ulock_wait",
    516: "ulock_wake", 544: "ulock_wait2",
    # Negative numbers are Mach traps.
    -26: "mach_reply_port", -27: "thread_self_trap", -28: "task_self_trap",
    -31: "mach_msg_trap", -33: "semaphore_signal_trap", -36: "semaphore_wait_trap",
    -47: "mach_msg2_trap", -59: "swtch_pri", -60: "swtch", -61: "thread_switch",
    -10: "_kernelrpc_mach_vm_allocate_trap", -12: "_kernelrpc_mach_vm_deallocate_trap",
    -14: "_kernelrpc_mach_vm_protect_trap", -15: "_kernelrpc_mach_vm_map_trap",
}

_EXPORT_CACHE: dict[str, list[tuple[int, str]]] = {}


def pe_exports(path: str) -> list[tuple[int, str]]:
    """Sorted (rva, name) export table of a 32-bit PE on disk, or [] when unavailable.

    FFXiMain.dll is packed, so its runtime code has no usable exports; Wine's own DLLs and
    d3d9.dll do. Used to turn `ucrtbase.dll+0x658bc` into `ucrtbase.dll!memset+0x2c`."""
    if path in _EXPORT_CACHE:
        return _EXPORT_CACHE[path]
    result: list[tuple[int, str]] = []
    _EXPORT_CACHE[path] = result
    try:
        data = Path(path).read_bytes()
    except OSError:
        return result
    try:
        import struct
        if data[:2] != b"MZ":
            return result
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe:pe + 4] != b"PE\0\0":
            return result
        sections = struct.unpack_from("<H", data, pe + 6)[0]
        optional_size = struct.unpack_from("<H", data, pe + 20)[0]
        optional = pe + 24
        magic = struct.unpack_from("<H", data, optional)[0]
        directory = optional + (96 if magic == 0x10B else 112)
        export_rva = struct.unpack_from("<I", data, directory)[0]
        if not export_rva:
            return result
        table = optional + optional_size
        headers = []
        for index in range(sections):
            at = table + index * 40
            virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
                "<IIII", data, at + 8)
            headers.append((virtual_address, max(virtual_size, raw_size), raw_offset))

        def to_offset(rva: int) -> int | None:
            for virtual_address, size, raw_offset in headers:
                if virtual_address <= rva < virtual_address + size:
                    return raw_offset + rva - virtual_address
            return None

        export = to_offset(export_rva)
        if export is None:
            return result
        count, names, functions, name_table, ordinals = struct.unpack_from(
            "<IIIII", data, export + 20)
        function_offset = to_offset(functions)
        name_offset = to_offset(name_table)
        ordinal_offset = to_offset(ordinals)
        if None in (function_offset, name_offset, ordinal_offset):
            return result
        addresses = [struct.unpack_from("<I", data, function_offset + 4 * i)[0]
                     for i in range(count)]
        named: dict[int, str] = {}
        for i in range(names):
            name_rva = struct.unpack_from("<I", data, name_offset + 4 * i)[0]
            ordinal = struct.unpack_from("<H", data, ordinal_offset + 2 * i)[0]
            at = to_offset(name_rva)
            if at is None:
                continue
            end = data.index(b"\0", at)
            named[ordinal] = data[at:end].decode("ascii", "replace")
        for ordinal, rva in enumerate(addresses):
            if rva:
                result.append((rva, named.get(ordinal, f"ordinal{ordinal + 1}")))
        result.sort()
    except (struct.error, ValueError, IndexError):
        result.clear()
    return result


SYMBOL_MAPS = Path(__file__).resolve().parent / "symbols"
_MAP_CACHE: dict[str, list[tuple[int, str]]] = {}


def symbol_map(path: str) -> list[tuple[int, str]]:
    """Text symbols for a stripped module, keyed by its name and the first twelve hex digits of
    its SHA-256, from `scripts/harness/symbols/<name>-<sha12>.map`. DXVK's d3d9.dll exports
    almost nothing, so its map comes from the unstripped build instead."""
    if path in _MAP_CACHE:
        return _MAP_CACHE[path]
    result: list[tuple[int, str]] = []
    _MAP_CACHE[path] = result
    digest = sha256(Path(path))
    if not digest:
        return result
    stem = Path(path).name.lower().removesuffix(".dll")
    candidate = SYMBOL_MAPS / f"{stem}-{digest[:12]}.map"
    if not candidate.is_file():
        return result
    for line in candidate.read_text(errors="replace").splitlines():
        if not line or line.startswith("#"):
            continue
        rva, _, name = line.partition(" ")
        try:
            result.append((int(rva, 0), name.strip()))
        except ValueError:
            continue
    result.sort()
    return result


def export_symbol(path: str, offset: int) -> str | None:
    exports = symbol_map(path) or pe_exports(path)
    if not exports:
        return None
    import bisect
    index = bisect.bisect_right([rva for rva, _ in exports], offset) - 1
    if index < 0:
        return None
    rva, name = exports[index]
    # Beyond 64 KiB from the nearest export the attribution is a guess, so leave it bare.
    if offset - rva > 0x10000:
        return None
    return f"{name}+0x{offset - rva:x}"


def module_location(pc: int, modules: list[dict[str, Any]]) -> dict[str, Any]:
    matches = [module for module in modules
               if module["base"] <= pc < module["base"] + module["size"]]
    if not matches:
        return {"location": f"0x{pc:x}", "module": "unknown", "offset": f"0x{pc:x}"}
    module = max(matches, key=lambda item: item["base"])
    name = module["path"].replace("\\", "/").rstrip("/").split("/")[-1] or "unknown"
    offset = pc - module["base"]
    location = f"{name}+0x{offset:x}"
    symbol = export_symbol(module["path"], offset) if module.get("kind") == "pe" else None
    if symbol:
        location = f"{name}!{symbol}"
    return {"location": location, "module": name, "offset": f"0x{offset:x}"}


# Modules that only ever appear as helpers on a stack. A stall attributed to one of these is
# blamed on the nearest caller outside the set, which is where the work was requested.
RUNTIME_MODULES = ("ucrtbase.dll", "msvcrt.dll", "ntdll.dll", "kernel32.dll", "kernelbase.dll",
                   "d3d9.dll", "d3d8.dll", "d3d8to9.dll", "dxvk", "libmoltenvk", "libvulkan",
                   "libsystem", "libdispatch", "wine")


def caller_attribution(record: dict[str, Any], limit: int = 12) -> list[dict[str, Any]]:
    """For each sampled stack, name the innermost frame that is not a runtime helper.

    The leaf histogram says `memset`; this says who asked for it. Frames are stored
    root-first, so the walk runs from the leaf backwards."""
    modules = record.get("modules", [])
    samples = max(1, int(record.get("header", {}).get("samples", 0)))
    counts: Counter[str] = Counter()
    leaves: dict[str, Counter[str]] = {}
    for row in record.get("stacks", []):
        located = [module_location(pc, modules) for pc in row["pcs"]]
        if not located:
            continue
        leaf = located[-1]["location"]
        owner = next((item["location"] for item in reversed(located)
                      if not item["module"].lower().startswith(RUNTIME_MODULES)), None)
        key = owner or f"runtime-only ({located[0]['location']})"
        counts[key] += row["count"]
        leaves.setdefault(key, Counter())[leaf] += row["count"]
    return [{"caller": caller, "count": count,
             "percent_of_samples": round(count / samples * 100, 2),
             "leaves": [{"location": leaf, "count": n}
                        for leaf, n in leaves[caller].most_common(3)]}
            for caller, count in counts.most_common(limit)]


def inclusive_module_share(record: dict[str, Any], limit: int = 10) -> list[dict[str, Any]]:
    """Samples whose stack passes through each module at least once."""
    modules = record.get("modules", [])
    samples = max(1, int(record.get("header", {}).get("samples", 0)))
    counts: Counter[str] = Counter()
    for row in record.get("stacks", []):
        seen = {module_location(pc, modules)["module"] for pc in row["pcs"]}
        for module in seen:
            counts[module] += row["count"]
    return [{"module": module, "count": count,
             "percent_of_samples": round(count / samples * 100, 2)}
            for module, count in counts.most_common(limit)]


def x87_hotspots(record: dict[str, Any], limit: int = 12) -> list[dict[str, Any]]:
    counts: Counter[int] = Counter()
    for row in record.get("leaves", []):
        counts[row["pc"]] += row["count"]
    samples = max(1, int(record.get("header", {}).get("samples", sum(counts.values()))))
    result = []
    for pc, count in counts.most_common(limit):
        result.append({
            "pc": f"0x{pc:x}", "count": count,
            "percent_of_samples": round(count / samples * 100, 2),
            **module_location(pc, record.get("modules", [])),
        })
    return result


def x87_module_hotspots(record: dict[str, Any], limit: int = 10) -> list[dict[str, Any]]:
    counts: Counter[str] = Counter()
    samples = max(1, int(record.get("header", {}).get("samples", 0)))
    for row in record.get("leaves", []):
        counts[module_location(row["pc"], record.get("modules", []))["module"]] += row["count"]
    return [{"module": module, "count": count,
             "percent_of_samples": round(count / samples * 100, 2)}
            for module, count in counts.most_common(limit)]


def x87_record_summary(record: dict[str, Any], limit: int = 12) -> dict[str, Any]:
    header = record.get("header", {})
    keep = (
        "pid", "written", "rate_hz", "effective_hz", "elapsed_s", "profiled_s",
        "samples", "resolved", "in_range", "not_translated", "unavailable",
        "samples_dropped", "missed_ticks", "overrun_ticks", "avg_us", "avg_depth",
        "threads_seen", "latch_events", "sticky", "window_seq", "window_start_s", "window_end_s",
    )
    result = {key: header[key] for key in keep if key in header}
    elapsed = header.get("elapsed_s")
    profiled = header.get("profiled_s")
    if (isinstance(elapsed, (int, float)) and elapsed > 0
            and isinstance(profiled, (int, float))):
        coverage = round(min(100.0, max(0.0, profiled / elapsed * 100.0)), 1)
        result["coverage_percent"] = coverage
        result["coverage_status"] = "adequate" if coverage >= 90.0 else "inadequate"
    samples = max(1, int(header.get("samples", 0)))
    guest_count = sum(row["count"] for row in record.get("leaves", []))
    host_count = sum(row["count"] for row in record.get("host_leaves", []))
    result["guest_leaf_percent"] = round(guest_count / samples * 100, 2)
    result["host_leaf_percent"] = round(host_count / samples * 100, 2)
    result["top_guest_leaves"] = x87_hotspots(record, limit)
    result["top_guest_modules"] = x87_module_hotspots(record, limit)

    host_counts: Counter[tuple[int, str]] = Counter()
    for row in record.get("host_leaves", []):
        host_counts[(row["pc"], row["reason"])] += row["count"]
    result["top_host_leaves"] = [
        {"pc": f"0x{pc:x}", "reason": reason, "count": count,
         "percent_of_samples": round(count / samples * 100, 2),
         **module_location(pc, record.get("modules", []))}
        for (pc, reason), count in host_counts.most_common(limit)
    ]

    syscall_counts: Counter[int] = Counter()
    for row in record.get("host_syscalls", []):
        syscall_counts[row["svc"]] += row["count"]
    result["top_host_syscalls"] = [
        {"svc": svc, "name": HOST_SYSCALL_NAMES.get(svc, f"syscall {svc}"), "count": count,
         "percent_of_samples": round(count / samples * 100, 2)}
        for svc, count in syscall_counts.most_common(limit)
    ]
    result["callers"] = caller_attribution(record, limit)
    result["inclusive_modules"] = inclusive_module_share(record, limit)

    stack_counts: Counter[tuple[int, ...]] = Counter()
    for row in record.get("stacks", []):
        stack_counts[tuple(row["pcs"])] += row["count"]
    result["top_guest_stacks"] = [
        {"count": count, "percent_of_samples": round(count / samples * 100, 2),
         "locations": [module_location(pc, record.get("modules", []))["location"]
                       for pc in stack]}
        for stack, count in stack_counts.most_common(min(limit, 8))
    ]
    return result


def merge_x87_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    merged: dict[str, Any] = {"header": {"samples": 0}, "modules": [], "leaves": [],
                              "host_leaves": [], "host_syscalls": [], "stacks": []}
    known_modules: set[tuple[int, int, str]] = set()
    for record in records:
        merged["header"]["samples"] += int(record.get("header", {}).get("samples", 0))
        for section in ("leaves", "host_leaves", "host_syscalls", "stacks"):
            merged[section].extend(record.get(section, []))
        for module in record.get("modules", []):
            key = (module["base"], module["size"], module["path"])
            if key not in known_modules:
                known_modules.add(key)
                merged["modules"].append(module)
    return merged


def x87_profile_start_epoch(record: dict[str, Any]) -> float | None:
    header = record.get("header", {})
    written = header.get("written")
    elapsed = header.get("elapsed_s")
    if not isinstance(written, str) or not isinstance(elapsed, (int, float)):
        return None
    try:
        return dt.datetime.fromisoformat(written.replace("Z", "+00:00")).timestamp() - elapsed
    except ValueError:
        return None


def fps_window_summary(fps: list[dict[str, float]], start: float, end: float) -> dict[str, Any]:
    values = [row["fps"] for row in fps
              if "fps" in row and start <= row.get("epoch", -1) < end]
    if not values:
        return {"samples": 0, "classification": "unknown"}
    median = statistics.median(values)
    classification = "slow" if median < 10 else "recovered" if median >= 30 else "intermediate"
    return {"samples": len(values), "minimum": round(min(values), 2),
            "median": round(median, 2), "maximum": round(max(values), 2),
            "classification": classification}


def x87_profiles_summary(output: Path, game_pid: int,
                         fps: list[dict[str, float]]) -> dict[str, Any]:
    profiles = []
    game_profile: dict[str, Any] | None = None
    game_record: dict[str, Any] | None = None
    game_windows: list[dict[str, Any]] = []
    for path in sorted(output.glob("x87-sample-*.prof")):
        try:
            record = parse_x87_record(path.read_text(errors="replace"))
        except OSError:
            continue
        if not record:
            continue
        profile_pid = record.get("header", {}).get("pid")
        windows = read_x87_windows(Path(str(path) + ".windows"))
        item = {
            "file": path.name,
            "role": "game" if profile_pid == game_pid else "auxiliary",
            "profile": x87_record_summary(record),
            "window_records": len(windows),
        }
        profiles.append(item)
        if profile_pid == game_pid:
            game_profile = item
            game_record = record
            game_windows = windows

    result: dict[str, Any] = {
        "status": "captured" if game_profile else "game_profile_missing",
        "profile_files": len(profiles), "profiles": profiles,
    }
    if game_profile is None or game_record is None:
        return result

    start_epoch = x87_profile_start_epoch(game_record)
    window_summaries = []
    grouped: dict[str, list[dict[str, Any]]] = {"slow": [], "intermediate": [],
                                                "recovered": [], "unknown": []}
    for record in game_windows:
        header = record.get("header", {})
        start_s = float(header.get("window_start_s", 0))
        end_s = float(header.get("window_end_s", start_s))
        fps_summary = (fps_window_summary(fps, start_epoch + start_s, start_epoch + end_s)
                       if start_epoch is not None else {"samples": 0, "classification": "unknown"})
        classification = fps_summary["classification"]
        grouped[classification].append(record)
        window_summaries.append({
            **x87_record_summary(record, limit=5),
            "fps": fps_summary,
        })

    result["game_profile"] = game_profile
    result["windows"] = window_summaries
    result["phase_hotspots"] = {}
    for classification in ("slow", "intermediate", "recovered"):
        records = grouped[classification]
        if not records:
            continue
        merged = merge_x87_records(records)
        phase = x87_record_summary(merged)
        result["phase_hotspots"][classification] = {
            "windows": len(records),
            "samples": merged["header"]["samples"],
            "top_guest_leaves": phase["top_guest_leaves"],
            "top_guest_modules": phase["top_guest_modules"],
            "callers": phase["callers"],
            "inclusive_modules": phase["inclusive_modules"],
            "top_host_syscalls": phase["top_host_syscalls"][:6],
            "top_guest_stacks": phase["top_guest_stacks"][:4],
        }
    return result


def wait_for_guest_profile(output: Path, pid: int, timeout: float = 4.0) -> None:
    """Let a terminating sidecar finish its bounded final profile write."""
    profile = output / f"x87-sample-{pid}.prof"
    windows = Path(str(profile) + ".windows")
    deadline = time.monotonic() + timeout
    previous: tuple[int, int, int, int] | None = None
    stable = 0
    while time.monotonic() < deadline:
        try:
            signature = (
                profile.stat().st_size, profile.stat().st_mtime_ns,
                windows.stat().st_size if windows.exists() else 0,
                windows.stat().st_mtime_ns if windows.exists() else 0,
            )
        except OSError:
            signature = None
        if signature is not None and signature == previous and not Path(str(profile) + ".tmp").exists():
            stable += 1
            if stable >= 2:
                return
        else:
            stable = 0
        previous = signature
        time.sleep(0.2)


def wait_for_block_profile(output: Path, pid: int, timeout: float = 10.0) -> None:
    """The sidecar appends block counters after its target exits; give that write time."""
    profile = output / f"x87-block-{pid}.prof"
    if not profile.exists():
        return
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if block_profile_complete(profile):
            return
        time.sleep(0.25)


def stable_time(rows: list[dict[str, float]], threshold: float, count: int = 5) -> float | None:
    for index in range(0, len(rows) - count + 1):
        window = rows[index:index + count]
        if all(row.get("fps", 0) >= threshold for row in window):
            return window[0].get("elapsed")
    return None


def pipeline_compiler_summary(rows: list[dict[str, float]]) -> dict[str, Any]:
    """Relate the FPS collapse to DXVK's asynchronous pipeline workers.

    Older diagnostic DLLs do not emit these columns. Returning an empty result keeps their
    captures readable while making a current capture answer whether low FPS overlaps compilation.
    """
    if not rows or not any("compiler_busy" in row for row in rows):
        return {}

    usable = [row for row in rows if "fps" in row]
    if not usable:
        return {}

    busy = [row for row in usable if row.get("compiler_busy", 0) > 0]
    idle = [row for row in usable if row.get("compiler_busy", 0) == 0]
    low = [row for row in usable if row["fps"] < 10]

    growing: list[dict[str, float]] = []
    previous_graphics = usable[0].get("graphics_pipelines", 0)
    previous_compute = usable[0].get("compute_pipelines", 0)
    for row in usable[1:]:
        graphics = row.get("graphics_pipelines", previous_graphics)
        compute = row.get("compute_pipelines", previous_compute)
        if graphics > previous_graphics or compute > previous_compute:
            growing.append(row)
        previous_graphics = graphics
        previous_compute = compute

    def median_fps(items: list[dict[str, float]]) -> float | None:
        values = [row["fps"] for row in items]
        return round(statistics.median(values), 2) if values else None

    first = usable[0]
    last = usable[-1]
    return {
        "samples": len(usable),
        "samples_compiler_busy": len(busy),
        "samples_pipeline_growing": len(growing),
        "graphics_pipelines_first": int(first.get("graphics_pipelines", 0)),
        "graphics_pipelines_last": int(last.get("graphics_pipelines", 0)),
        "compute_pipelines_first": int(first.get("compute_pipelines", 0)),
        "compute_pipelines_last": int(last.get("compute_pipelines", 0)),
        "fps_median_compiler_busy": median_fps(busy),
        "fps_median_compiler_idle": median_fps(idle),
        "fps_median_pipeline_growing": median_fps(growing),
        "low_fps_samples": len(low),
        "low_fps_samples_compiler_busy": sum(
            row.get("compiler_busy", 0) > 0 for row in low),
        "low_fps_samples_pipeline_growing": sum(row in growing for row in low),
    }


def correlated_timeline(
    process: list[dict[str, float]], fps: list[dict[str, float]]
) -> list[dict[str, float]]:
    timeline: list[dict[str, float]] = []
    for previous, current in zip(process, process[1:]):
        seconds = current.get("epoch", 0) - previous.get("epoch", 0)
        if seconds <= 0:
            continue
        nearest = min(fps, key=lambda row: abs(row.get("epoch", 0) - current.get("epoch", 0)),
                      default={})
        if not nearest or abs(nearest.get("epoch", 0) - current.get("epoch", 0)) > 2:
            continue
        row = {
            "epoch": current.get("epoch", 0), "elapsed": current.get("elapsed", 0),
            "fps": nearest.get("fps", 0), "draws": nearest.get("draws", 0),
            # proc_pid_rusage undercounts Rosetta-translated execution on current macOS. ps %CPU
            # includes it, so use that for correlation and retain rusage as an explicit cross-check.
            "cpu_cores": current.get("cpu_percent", 0) / 100.0,
            "rusage_cpu_cores": ((current.get("user_ns", 0) + current.get("system_ns", 0))
                - (previous.get("user_ns", 0) + previous.get("system_ns", 0))) / 1e9 / seconds,
            "disk_read_mb_s": (current.get("disk_read_bytes", 0)
                - previous.get("disk_read_bytes", 0)) / 1024 / 1024 / seconds,
            "disk_write_mb_s": (current.get("disk_write_bytes", 0)
                - previous.get("disk_write_bytes", 0)) / 1024 / 1024 / seconds,
            "pageins_s": (current.get("pageins", 0) - previous.get("pageins", 0)) / seconds,
            "instructions_s": (current.get("instructions", 0)
                - previous.get("instructions", 0)) / seconds,
            "phys_footprint_mb": current.get("phys_footprint_bytes", 0) / 1024 / 1024,
        }
        if "faults" in current and "faults" in previous:
            # proc_pidinfo counters. The task clock includes Rosetta time that rusage misses,
            # so its kernel share is the honest split between game code and page-fault or
            # syscall handling. Older captures lack these columns and keep the short row.
            row.update(task_counter_rates(previous, current, seconds))
        timeline.append({key: round(value, 4) for key, value in row.items()})
    return timeline


def task_counter_rates(previous: dict[str, float], current: dict[str, float],
               seconds: float) -> dict[str, float]:
    return {
        "faults_s": (current.get("faults", 0) - previous.get("faults", 0)) / seconds,
        "cow_faults_s": (current.get("cow_faults", 0)
            - previous.get("cow_faults", 0)) / seconds,
        "syscalls_s": ((current.get("syscalls_mach", 0) + current.get("syscalls_unix", 0))
            - (previous.get("syscalls_mach", 0) + previous.get("syscalls_unix", 0)))
            / seconds,
        "context_switches_s": (current.get("context_switches", 0)
            - previous.get("context_switches", 0)) / seconds,
        "task_cpu_cores": ((current.get("task_user_ns", 0) + current.get("task_system_ns", 0))
            - (previous.get("task_user_ns", 0) + previous.get("task_system_ns", 0)))
            / 1e9 / seconds,
        "kernel_share": kernel_share(previous, current),
        "threads": current.get("threads", 0),
    }


def kernel_share(previous: dict[str, float], current: dict[str, float]) -> float:
    user = current.get("task_user_ns", 0) - previous.get("task_user_ns", 0)
    system = current.get("task_system_ns", 0) - previous.get("task_system_ns", 0)
    total = user + system
    return system / total if total > 0 else 0.0


def stall_phase_summary(timeline: list[dict[str, float]]) -> dict[str, Any]:
    """Contrast the sub-10 FPS seconds with the recovered seconds on the kernel-side counters.

    A loading stall that is really page-fault or syscall bound shows a fault rate and kernel
    share far above the recovered baseline while instructions per second stay flat or drop. A
    stall that is user-mode work shows the opposite. Both ratios are reported so a single number
    cannot mislead when one phase is empty."""
    slow = [row for row in timeline if row.get("fps", 0) < 10]
    recovered = [row for row in timeline if row.get("fps", 0) >= 30]
    if not slow or not recovered or not any("faults_s" in row for row in timeline):
        return {}

    def med(rows: list[dict[str, float]], key: str) -> float:
        values = [row[key] for row in rows if key in row]
        return round(statistics.median(values), 3) if values else 0.0

    keys = ("faults_s", "cow_faults_s", "syscalls_s", "context_switches_s", "kernel_share",
            "instructions_s", "cpu_cores", "task_cpu_cores", "threads")
    result: dict[str, Any] = {
        "slow_seconds": len(slow), "recovered_seconds": len(recovered),
        "slow": {key: med(slow, key) for key in keys},
        "recovered": {key: med(recovered, key) for key in keys},
    }
    ratios = {}
    for key in ("faults_s", "syscalls_s", "context_switches_s", "instructions_s"):
        base = result["recovered"][key]
        ratios[key] = round(result["slow"][key] / base, 2) if base else None
    result["slow_over_recovered"] = ratios
    slow_kernel = result["slow"]["kernel_share"]
    if slow_kernel >= 0.6 and (ratios["faults_s"] or 0) >= 3:
        result["reading"] = "kernel-bound: page faults dominate the slow seconds"
    elif slow_kernel >= 0.6:
        result["reading"] = "kernel-bound: syscalls or waits dominate the slow seconds"
    elif result["slow"]["cpu_cores"] < 0.3:
        result["reading"] = "idle: the process is mostly waiting during the slow seconds"
    else:
        result["reading"] = "user-bound: translated game code dominates the slow seconds"
    return result


def low_fps_windows(timeline: list[dict[str, float]], threshold: float = 10.0,
                    gap: float = 3.0) -> list[dict[str, Any]]:
    """Group consecutive slow seconds into windows so a run reads as a few named stalls."""
    windows: list[dict[str, Any]] = []
    current: list[dict[str, float]] = []
    for row in timeline:
        if row.get("fps", 0) < threshold:
            if current and row["elapsed"] - current[-1]["elapsed"] > gap:
                windows.append(current)
                current = []
            current.append(row)
    if current:
        windows.append(current)
    result = []
    for rows in windows:
        result.append({
            "start_s": rows[0]["elapsed"], "end_s": rows[-1]["elapsed"],
            "seconds": len(rows), "min_fps": min(row["fps"] for row in rows),
            "median_faults_s": round(statistics.median(
                [row["faults_s"] for row in rows if "faults_s" in row] or [0]), 1),
            "median_kernel_share": round(statistics.median(
                [row["kernel_share"] for row in rows if "kernel_share" in row] or [0]), 3),
            "median_cpu_cores": round(statistics.median(
                [row.get("cpu_cores", 0) for row in rows]), 3),
            "footprint_change_mb": round(rows[-1].get("phys_footprint_mb", 0)
                                         - rows[0].get("phys_footprint_mb", 0), 1),
            "draws": rows[-1].get("draws", 0),
        })
    return result


def footprint_churn(path: Path, timeline: list[dict[str, float]]) -> dict[str, Any]:
    """Sum of positive per-second growth in each footprint category, split into the slow and
    recovered seconds. Growth that keeps recurring while the total stays flat is memory that
    is being freed and re-faulted rather than accumulated."""
    if not path.is_file():
        return {}
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    if len(rows) < 3:
        return {}
    slow_seconds = {round(row["elapsed"]) for row in timeline if row.get("fps", 0) < 10}
    keys = sorted({key for row in rows for key in row if key.endswith("_dirty_bytes")})
    growth: dict[str, dict[str, float]] = {"slow": {}, "recovered": {}}
    for previous, current in zip(rows, rows[1:]):
        phase = "slow" if round(current["elapsed"]) in slow_seconds else "recovered"
        for key in keys:
            delta = current.get(key, 0) - previous.get(key, 0)
            if delta > 0:
                growth[phase][key] = growth[phase].get(key, 0) + delta
    result: dict[str, Any] = {"samples": len(rows)}
    for phase in ("slow", "recovered"):
        seconds = max(1, sum(1 for row in rows[1:]
                             if (round(row["elapsed"]) in slow_seconds) == (phase == "slow")))
        ranked = sorted(growth[phase].items(), key=lambda item: item[1], reverse=True)[:6]
        result[phase] = {
            "seconds": seconds,
            "growth_mb_per_s": {key.removesuffix("_dirty_bytes"): round(value / 1048576 / seconds, 2)
                                for key, value in ranked},
        }
    return result


BLOCK_COUNTER_TAG = b"CNT0"


def block_profile_complete(path: Path) -> bool:
    """x87sidecar appends the block counter sections only after its target exits. A profile
    without the tag was cut off by cleanup order and profile_analyze rejects it."""
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - 512 * 1024))
            return BLOCK_COUNTER_TAG in handle.read()
    except OSError:
        return False


def block_profiles_summary(output: Path, game_pid: int) -> dict[str, Any]:
    profiles = []
    for path in sorted(output.glob("x87-block-*.prof")):
        match = re.search(r"x87-block-(\d+)\.prof$", path.name)
        profile_pid = int(match.group(1)) if match else None
        profiles.append({
            "file": path.name,
            "role": "game" if profile_pid == game_pid else "auxiliary",
            "size": path.stat().st_size,
            "complete": block_profile_complete(path),
        })
    game = next((item for item in profiles if item["role"] == "game"), None)
    if not profiles:
        status = "none"
    elif game is None:
        status = "no game profile"
    elif game["complete"]:
        status = "complete"
    else:
        status = "incomplete: counters missing, the sidecar was killed before its target exited"
    return {"status": status, "profiles": profiles}


def build_summary(output: Path, duration: float, pid: int, level: str) -> dict[str, Any]:
    fps = read_numeric_csv(output / "fps.csv")
    process = read_numeric_csv(output / "process.csv")
    summary: dict[str, Any] = {
        "pid": pid, "capture_duration_s": round(duration, 2), "level": level,
        "fps_samples": len(fps), "probe_files": sorted(path.name for path in output.iterdir()),
    }
    if fps:
        values = [row["fps"] for row in fps if "fps" in row]
        summary["fps"] = {
            "minimum": round(min(values), 2), "median": round(statistics.median(values), 2),
            "maximum": round(max(values), 2),
            # DXVK normally emits one row per second, but a frame that itself takes several
            # seconds delays the next row. This is a sample count, not elapsed wall time.
            "samples_below_10": sum(value < 10 for value in values),
            "stable_30_elapsed_s": stable_time(fps, 30),
            "stable_50_elapsed_s": stable_time(fps, 50),
            "first_30_samples": median_fields(fps[:30]),
            "last_30_samples": median_fields(fps[-30:]),
        }
        pipeline_compiler = pipeline_compiler_summary(fps)
        if pipeline_compiler:
            summary["pipeline_compiler"] = pipeline_compiler
    if len(process) >= 2:
        first, last = process[0], process[-1]
        wall = max(0.001, last.get("epoch", 0) - first.get("epoch", 0))
        ps_cpu = [row["cpu_percent"] for row in process if "cpu_percent" in row]
        summary["host_process"] = {
            "samples": len(process),
            "coverage_duration_s": round(wall, 2),
            "coverage_percent": round(min(100.0, wall / max(0.001, duration) * 100), 1),
            "cpu_core_average": round(statistics.mean(ps_cpu) / 100.0, 3) if ps_cpu else 0.0,
            "rusage_cpu_core_average": round(((last.get("user_ns", 0) + last.get("system_ns", 0))
                - (first.get("user_ns", 0) + first.get("system_ns", 0))) / 1e9 / wall, 3),
            "disk_read_mb": round((last.get("disk_read_bytes", 0)
                - first.get("disk_read_bytes", 0)) / 1024 / 1024, 3),
            "disk_write_mb": round((last.get("disk_write_bytes", 0)
                - first.get("disk_write_bytes", 0)) / 1024 / 1024, 3),
            "pageins": int(last.get("pageins", 0) - first.get("pageins", 0)),
            "peak_footprint_mb": round(max(row.get("phys_footprint_bytes", 0)
                for row in process) / 1024 / 1024, 1),
        }
    timeline = correlated_timeline(process, fps)
    if timeline:
        with (output / "timeline.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(timeline[0]))
            writer.writeheader(); writer.writerows(timeline)
        slow = [row for row in timeline if row["fps"] < 10]
        recovered = [row for row in timeline if row["fps"] >= 30]
        summary["correlated_phases"] = {
            "slow_below_10_fps": median_fields(slow),
            "recovered_at_least_30_fps": median_fields(recovered),
        }
        stall_phases = stall_phase_summary(timeline)
        if stall_phases:
            summary["stall_phases"] = stall_phases
        summary["low_fps_windows"] = low_fps_windows(timeline)
        churn = footprint_churn(output / "footprint.jsonl", timeline)
        if churn:
            summary["footprint_churn"] = churn
    probe_summaries = {}
    for name in ("present.csv", "stalls.csv", "waits.csv", "flushes.csv",
                 "queue.csv", "lock-images.csv", "draw.csv", "draw-up.csv"):
        rows = read_numeric_csv(output / name)
        if rows:
            probe_summaries[name] = {
                "samples": len(rows), "first_30_samples": median_fields(rows[:30]),
                "last_30_samples": median_fields(rows[-30:]),
            }
    summary["probes"] = probe_summaries
    stage_watchdogs = {
        # These phases mean the renderer thread is idle. Long gaps here are evidence that the
        # game has not supplied another frame, not that Present or queue submission is stuck.
        "present": stage_summary(output / "present-stages.csv", {"outside_present"}),
        "submit": stage_summary(output / "submit-stages.csv", {"waiting"}),
        "draw_up": stage_summary(output / "draw-up-stages.csv", {"outside_call"}),
    }
    summary["stage_watchdogs"] = {name: value for name, value in stage_watchdogs.items() if value}
    active_stalls = [
        (name, value["longest_active_phase"], value["longest_active_phase_ms"])
        for name, value in stage_watchdogs.items()
        if value and "longest_active_phase_ms" in value
    ]
    longest_active = max(active_stalls, key=lambda item: item[2], default=None)
    present = stage_watchdogs["present"]
    submit = stage_watchdogs["submit"]
    if longest_active and longest_active[2] >= 2_000:
        summary["likely_bottleneck"] = {
            "classification": "renderer_stall",
            "lane": longest_active[0],
            "phase": longest_active[1],
            "observed_ms": longest_active[2],
        }
    elif (present.get("longest_phase") == "outside_present"
          and present.get("longest_phase_ms", 0) >= 2_000
          and submit.get("longest_phase") == "waiting"
          and submit.get("longest_phase_ms", 0) >= 2_000):
        summary["likely_bottleneck"] = {
            "classification": "game_between_frames",
            "outside_present_ms": present["longest_phase_ms"],
            "submit_waiting_ms": submit["longest_phase_ms"],
        }

    gpu = read_numeric_csv(output / "gpu.csv")
    if gpu:
        utilization = [row.get("device_utilization_percent", 0) for row in gpu]
        summary["host_gpu"] = {
            "scope": "system-wide IOAccelerator counters",
            "device_utilization_median_percent": round(statistics.median(utilization), 2),
            "device_utilization_max_percent": round(max(utilization), 2),
            "recovery_count_max": int(max(row.get("recovery_count", 0) for row in gpu)),
        }
    summary["x87"] = x87_summary(output / "launcher.log")
    summary["guest_pc_profiles"] = x87_profiles_summary(output, pid, fps)
    summary["block_profiles"] = block_profiles_summary(output, pid)
    expected = ["fps.csv", "present.csv", "stalls.csv", "waits.csv", "flushes.csv",
                "queue.csv", "lock-images.csv", "present-stages.csv", "submit-stages.csv",
                "draw-up-stages.csv"]
    if level == "deep":
        expected.extend(["draw.csv", "draw-up.csv", "framebuffers.log", "passes.log"])
    summary["missing_probe_files"] = [name for name in expected if not (output / name).is_file()]
    atomic_json(output / "summary.json", summary)

    lines = [f"HorizonXI performance capture {output.name}", ""]
    if "fps" in summary:
        f = summary["fps"]
        lines.append(f"FPS min/median/max: {f['minimum']} / {f['median']} / {f['maximum']}")
        lines.append(f"Samples below 10 FPS: {f['samples_below_10']}")
        lines.append(f"First stable 30 FPS: {f['stable_30_elapsed_s']} s")
        lines.append(f"First stable 50 FPS: {f['stable_50_elapsed_s']} s")
    else:
        lines.append("No DXVK FPS rows were found. Confirm the updated launcher consumed the request.")
    if "host_process" in summary:
        h = summary["host_process"]
        lines.extend(["", f"Host telemetry coverage: {h['coverage_duration_s']} s "
                      f"({h['coverage_percent']}% of capture)",
                      f"Average CPU cores used: {h['cpu_core_average']}",
                      f"Rosetta-blind rusage CPU cross-check: {h['rusage_cpu_core_average']}",
                      f"Disk read/write: {h['disk_read_mb']} / {h['disk_write_mb']} MB",
                      f"Page-ins: {h['pageins']}",
                      f"Peak physical footprint: {h['peak_footprint_mb']} MB"])
    if "pipeline_compiler" in summary:
        compiler = summary["pipeline_compiler"]
        lines.extend([
            "",
            f"DXVK compiler busy samples: {compiler['samples_compiler_busy']} / "
            f"{compiler['samples']}",
            f"Graphics pipelines first/last: "
            f"{compiler['graphics_pipelines_first']} / "
            f"{compiler['graphics_pipelines_last']}",
            f"FPS median while compiler busy/idle: "
            f"{compiler['fps_median_compiler_busy']} / "
            f"{compiler['fps_median_compiler_idle']}",
            f"Low-FPS samples overlapping compiler/growth: "
            f"{compiler['low_fps_samples_compiler_busy']} / "
            f"{compiler['low_fps_samples_pipeline_growing']} of "
            f"{compiler['low_fps_samples']}",
        ])
    if "stall_phases" in summary:
        phases = summary["stall_phases"]
        ratios = phases["slow_over_recovered"]
        lines.extend([
            "",
            f"Slow seconds vs recovered: faults/s {phases['slow']['faults_s']} vs "
            f"{phases['recovered']['faults_s']} (x{ratios['faults_s']}), "
            f"syscalls/s {phases['slow']['syscalls_s']} vs "
            f"{phases['recovered']['syscalls_s']} (x{ratios['syscalls_s']})",
            f"Kernel share of CPU, slow vs recovered: {phases['slow']['kernel_share']} vs "
            f"{phases['recovered']['kernel_share']}; instructions/s x"
            f"{ratios['instructions_s']}",
            f"Stall reading: {phases['reading']}",
        ])
    if "footprint_churn" in summary:
        churn = summary["footprint_churn"]
        for phase in ("slow", "recovered"):
            rendered = ", ".join(f"{name} {value}" for name, value
                                 in churn[phase]["growth_mb_per_s"].items())
            lines.append(f"Footprint growth MB/s while {phase}: {rendered or 'none'}")
    if summary.get("low_fps_windows"):
        with_counters = "stall_phases" in summary
        rendered = "; ".join(
            f"{w['start_s']:.0f}-{w['end_s']:.0f}s ({w['seconds']}s, min {w['min_fps']} FPS, "
            + (f"{w['median_faults_s']:.0f} faults/s, kernel {w['median_kernel_share']:.2f}, "
               if with_counters else f"{w['median_cpu_cores']:.2f} cores, ")
            + f"{w['footprint_change_mb']:+.0f} MB)"
            for w in summary["low_fps_windows"])
        lines.append(f"Low-FPS windows: {rendered}")
    if "host_gpu" in summary:
        g = summary["host_gpu"]
        lines.append(f"System GPU utilization median/max: "
                     f"{g['device_utilization_median_percent']} / "
                     f"{g['device_utilization_max_percent']}%")
    x87 = summary["x87"]
    lines.append(f"x87 acceleration: {x87['status']} "
                 f"({x87.get('cooperative_attaches', 0)} cooperative handshakes, "
                 f"{x87.get('throughput_nonzero_samples', 0)} active throughput samples)")
    guest_profiles = summary["guest_pc_profiles"]
    if guest_profiles["status"] == "captured":
        profile = guest_profiles["game_profile"]["profile"]
        coverage = ""
        if "coverage_percent" in profile:
            coverage = (f", {profile.get('profiled_s', 0)}/{profile.get('elapsed_s', 0)} s "
                        f"profiled ({profile['coverage_percent']}%, "
                        f"{profile['coverage_status']})")
        lines.append(f"Guest-PC sampler: captured {profile.get('samples', 0)} samples at "
                     f"{profile.get('effective_hz', 0)} Hz{coverage} in "
                     f"{guest_profiles['game_profile']['window_records']} windows")
        for phase, label in (("slow", "Slow-window hotspots"),
                             ("recovered", "Recovered-window hotspots")):
            phase_summary = guest_profiles.get("phase_hotspots", {}).get(phase)
            if not phase_summary:
                continue
            hotspots = phase_summary["top_guest_leaves"][:5]
            if not hotspots:
                continue
            rendered = ", ".join(
                f"{item['location']} {item['percent_of_samples']}%" for item in hotspots)
            lines.append(f"{label}: {rendered}")
            callers = phase_summary.get("callers", [])[:4]
            if callers:
                lines.append(f"{label} callers: " + ", ".join(
                    f"{item['caller']} {item['percent_of_samples']}%" for item in callers))
            syscalls = phase_summary.get("top_host_syscalls", [])[:3]
            if syscalls:
                lines.append(f"{label} host syscalls: " + ", ".join(
                    f"{item['name']} {item['percent_of_samples']}%" for item in syscalls))
    else:
        lines.append("Guest-PC sampler: no profile for the game process")
    block = summary.get("block_profiles", {})
    if block.get("status", "none") != "none":
        lines.append(f"x87 block profile: {block['status']}")
    if "likely_bottleneck" in summary:
        bottleneck = summary["likely_bottleneck"]
        if bottleneck["classification"] == "renderer_stall":
            lines.extend(["", f"Likely renderer stall: {bottleneck['lane']} / "
                          f"{bottleneck['phase']} for at least "
                          f"{bottleneck['observed_ms']} ms"])
        else:
            lines.extend(["", "Likely bottleneck: game code between frames",
                          f"Longest gap before Present: "
                          f"{bottleneck['outside_present_ms']} ms",
                          f"Longest idle submit wait: "
                          f"{bottleneck['submit_waiting_ms']} ms"])
    if summary["missing_probe_files"]:
        lines.extend(["", "Missing probe files: " + ", ".join(summary["missing_probe_files"])])
    (output / "summary.txt").write_text("\n".join(lines) + "\n")
    return summary


def capture(pid: int, output: Path, args: argparse.Namespace, stop: threading.Event) -> dict[str, Any]:
    started = time.monotonic()
    output.mkdir(parents=True, exist_ok=True)
    marker_lock = threading.Lock()
    markers = output / "markers.jsonl"
    markers.write_text(json.dumps({"epoch": time.time(), "elapsed": 0,
                                   "label": "game process found"}) + "\n")
    if sys.stdin.isatty():
        print("Type a scene label and press Return whenever the screen changes.", flush=True)
        threading.Thread(target=marker_reader,
                         args=(markers, started, stop, marker_lock), daemon=True).start()

    process_snapshot = threading.Thread(
        target=static_process_files, args=(pid, output, "start"), daemon=True)
    process_snapshot.start()

    streams: list[tuple[subprocess.Popen[bytes], Any]] = []
    iostat = start_stream(["/usr/sbin/iostat", "-w", "1", "-c", str(args.duration + 1)],
                          output / "iostat.txt")
    if iostat:
        streams.append(iostat)
    nettop = start_stream(["/usr/bin/nettop", "-n", "-x", "-P", "-L",
                           str(args.duration + 1), "-s", "1", "-p", str(pid),
                           "-J", "bytes_in,bytes_out"], output / "network.csv")
    if nettop:
        streams.append(nettop)

    fields = [
        "epoch", "elapsed", "cpu_percent", "memory_percent", "rss_kb", "vsize_kb",
        "state", "process_elapsed", "user_ns", "system_ns", "pageins", "resident_bytes",
        "phys_footprint_bytes", "disk_read_bytes", "disk_write_bytes", "instructions",
        "cycles", "runnable_ns", "idle_wakeups", "interrupt_wakeups",
        "faults", "cow_faults", "syscalls_mach", "syscalls_unix", "context_switches",
        "messages_sent", "messages_received", "threads", "threads_running",
        "task_user_ns", "task_system_ns",
    ]
    process_file = (output / "process.csv").open("w", newline="")
    process_writer = csv.DictWriter(process_file, fieldnames=fields, extrasaction="ignore")
    process_writer.writeheader()
    threads_file = (output / "threads.jsonl").open("w")
    memory_file = (output / "system-memory.jsonl").open("w")
    footprint_file = (output / "footprint.jsonl").open("w")
    gpu_fields = ["epoch", "elapsed", *GPU_FIELDS.values()]
    gpu_file = (output / "gpu.csv").open("w", newline="")
    gpu_writer = csv.DictWriter(gpu_file, fieldnames=gpu_fields, extrasaction="ignore")
    gpu_writer.writeheader()

    sample_offsets = sorted(set(args.sample_at))
    samples_started: set[int] = set()
    sample_threads: list[threading.Thread] = []
    next_threads = 0.0
    while not stop.is_set() and process_exists(pid):
        elapsed = time.monotonic() - started
        if elapsed >= args.duration:
            break
        now = time.time()
        row: dict[str, Any] = {"epoch": round(now, 3), "elapsed": round(elapsed, 3)}
        row.update(ps_metrics(pid))
        row.update(proc_rusage(pid))
        row.update(proc_task_info(pid))
        process_writer.writerow(row)
        process_file.flush()
        # About 90 ms for an 800 MB process and it neither suspends nor maps the target.
        footprint_file.write(json.dumps({"epoch": now, "elapsed": round(elapsed, 3),
                                         **footprint_stats(pid)}, sort_keys=True) + "\n")
        footprint_file.flush()

        if elapsed >= next_threads:
            threads_file.write(json.dumps({"epoch": now, "elapsed": round(elapsed, 3),
                                           "threads": thread_snapshot(pid)},
                                          sort_keys=True) + "\n")
            threads_file.flush()
            memory_file.write(json.dumps({"epoch": now, "elapsed": round(elapsed, 3),
                                          **vm_stats()}, sort_keys=True) + "\n")
            memory_file.flush()
            gpu_writer.writerow({"epoch": round(now, 3), "elapsed": round(elapsed, 3),
                                 **gpu_stats()})
            gpu_file.flush()
            next_threads += 5

        for offset in sample_offsets:
            if elapsed >= offset and offset not in samples_started:
                samples_started.add(offset)
                worker = threading.Thread(target=native_sample,
                    args=(pid, args.sample_seconds, args.sample_interval_ms,
                          output / f"sample-{offset:03d}s.txt", stop),
                    daemon=True)
                worker.start()
                sample_threads.append(worker)

        stop.wait(max(0.05, 1.0 - (time.monotonic() - started - int(elapsed))))

    duration = time.monotonic() - started
    process_file.close(); threads_file.close(); memory_file.close(); gpu_file.close()
    footprint_file.close()
    for worker in sample_threads:
        worker.join(timeout=args.sample_seconds + 45)
    process_snapshot.join(timeout=90)
    static_process_files(pid, output, "end")
    for process, handle in streams:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        handle.close()

    if not process_exists(pid):
        wait_for_guest_profile(output, pid)
        wait_for_block_profile(output, pid)

    for name in ("launcher.log", "launcher.log.1", "last-spawn.txt"):
        write_redacted(APP_SUPPORT / name, output / name)
    return build_summary(output, duration, pid, args.level)


def parse_offsets(value: str) -> list[int]:
    if not value.strip():
        return []
    try:
        offsets = [int(item.strip()) for item in value.split(",")]
    except ValueError as error:
        raise argparse.ArgumentTypeError("sample offsets must be comma-separated seconds") from error
    if any(offset < 0 for offset in offsets):
        raise argparse.ArgumentTypeError("sample offsets cannot be negative")
    return offsets


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, default=DEFAULT_GAME,
                        help=f"Ashita/game directory (default: {DEFAULT_GAME})")
    parser.add_argument("--duration", type=int, default=900,
                        help="maximum seconds to record; capture stops sooner when the game exits "
                             "(default: 900)")
    parser.add_argument("--wait-timeout", type=int, default=600,
                        help="seconds to wait for Play to start the game (default: 600)")
    parser.add_argument("--level", choices=("standard", "standard-nosample", "deep"),
                        default="standard",
                        help="deep adds heavier DXVK draw probes; standard-nosample keeps the "
                             "standard probes but disables the 1 kHz guest-PC sampler")
    parser.add_argument("--pid", type=int,
                        help="attach host collectors to an existing PID; DXVK probes need a new launch")
    parser.add_argument("--sample-at", type=parse_offsets, default=parse_offsets(""),
                        help="optional /usr/bin/sample start times in seconds, comma-separated; "
                             "empty by default because Rosetta stacks can unwind incorrectly")
    parser.add_argument("--sample-seconds", type=int, default=5,
                        help="duration of each native sample (default: 5)")
    parser.add_argument("--sample-interval-ms", type=int, default=1,
                        help="milliseconds between native samples (default: 1; use 20 or more "
                             "to reduce target suspension while diagnosing long stalls)")
    parser.add_argument("--no-archive", action="store_true",
                        help="leave only the capture directory, without a .tar.gz copy")
    args = parser.parse_args()
    args.game_dir = args.game_dir.expanduser().resolve()
    if (args.duration < 1 or args.wait_timeout < 1 or args.sample_seconds < 1
            or args.sample_interval_ms < 1):
        parser.error("durations must be positive")
    if not args.game_dir.is_dir():
        parser.error(f"game directory does not exist: {args.game_dir}")

    session = dt.datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{args.level}"
    output = args.game_dir / CAPTURE_DIR / session
    output.mkdir(parents=True, exist_ok=False)
    atomic_json(output / "manifest.json",
                system_manifest(args.game_dir, session, args.level, args.duration))
    stop = threading.Event()

    def stop_capture(_signum: int, _frame: Any) -> None:
        stop.set()

    signal.signal(signal.SIGINT, stop_capture)
    signal.signal(signal.SIGTERM, stop_capture)

    if args.pid:
        if not process_exists(args.pid):
            parser.error(f"PID {args.pid} is not running")
        pid = args.pid
        print(f"Attaching host collectors to PID {pid}. DXVK probes require an armed launch.")
    else:
        existing = game_pids()
        if existing:
            parser.error("a HorizonXI game process is already running; exit it or use --pid")
        write_request(args.game_dir, session, args.level, args.wait_timeout)
        print(f"Capture {session} armed. Press Play in FFXI on Mac.", flush=True)
        print(f"Waiting up to {args.wait_timeout} seconds without reading process arguments.", flush=True)
        pid = wait_for_game(existing, args.wait_timeout, stop)
        if pid is None:
            remove_own_request(session)
            print("No new game process appeared; the capture request was removed.", file=sys.stderr)
            return 2
        print(f"Found game PID {pid}. Recording until it exits or {args.duration} seconds pass.",
              flush=True)

    try:
        summary = capture(pid, output, args, stop)
    finally:
        remove_own_request(session)

    archive = None
    if not args.no_archive:
        archive = shutil.make_archive(str(output), "gztar", root_dir=output.parent,
                                      base_dir=output.name)
    print((output / "summary.txt").read_text(), end="")
    print(f"Capture: {output}")
    if archive:
        print(f"Archive: {archive}")
    if not summary.get("fps_samples") and not args.pid:
        print("WARNING: the launcher did not produce DXVK probe data. Rebuild and reinstall the app.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
