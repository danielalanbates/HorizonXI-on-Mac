#!/usr/bin/env python3
"""Run a Windows benchmark under the installed Wine runtime and count its page faults.

This is the offline half of the loading-stall investigation: the game faults about 30,000
pages a second inside DXVK buffer allocation while a scene loads. Reproducing the same fault
storm with `scripts/tools/d3d9-buffer-bench.c` takes seconds per run and needs no account, so
a DXVK or MoltenVK change can be judged here before it goes near the game.

Wine is started plain, without the x87 sidecar. Every Wine process is stopped afterwards so a
later `menu-run.py` preflight does not find leftovers. Process names only are inspected.
"""

from __future__ import annotations

import argparse
import ctypes
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


RUNTIME = Path.home() / "Library/Application Support/HorizonXI-on-Mac/runtimes/wine-cx-26.3.0-1/wine"
PREFIX = Path.home() / "Applications/FFXI on Mac Wine.app/Contents/SharedSupport/prefix10"


class ProcTaskInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "virtual_size", "resident_size", "total_user", "total_system", "threads_user",
        "threads_system")] + [(name, ctypes.c_int32) for name in (
        "policy", "faults", "pageins", "cow_faults", "messages_sent", "messages_received",
        "syscalls_mach", "syscalls_unix", "csw", "threadnum", "numrunning", "priority")]


def task_info(pid: int) -> ProcTaskInfo | None:
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                     ctypes.c_void_p, ctypes.c_int]
    info = ProcTaskInfo()
    if libproc.proc_pidinfo(pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):
        return None
    return info


def pids_named(needle: str) -> list[int]:
    out = subprocess.run(["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        pid, _, comm = line.strip().partition(" ")
        if pid.isdigit() and comm.strip().lower().endswith(needle.lower()):
            found.append(int(pid))
    return found


def wine_pids() -> list[int]:
    out = subprocess.run(["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        pid, _, comm = line.strip().partition(" ")
        comm = comm.strip()
        if pid.isdigit() and (comm.endswith(("/wine", "/wine-preloader", "/wine64-preloader",
                                              "/wineserver")) or comm.endswith(".exe")):
            found.append(int(pid))
    return found


def stop_wine(env: dict[str, str]) -> None:
    subprocess.run([str(RUNTIME / "bin/wineserver"), "-k"], env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    for _ in range(20):
        if not wine_pids():
            return
        time.sleep(0.25)
    for pid in wine_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", type=Path,
                        help="directory holding the .exe and the d3d9.dll under test")
    parser.add_argument("exe", help="executable name inside the directory")
    parser.add_argument("args", nargs="*", help="benchmark arguments")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--env", action="append", default=[], metavar="NAME=value",
                        help="extra variable for the Wine process, repeatable")
    args = parser.parse_args()

    if wine_pids():
        print("refusing: Wine processes are already running", file=sys.stderr)
        return 3
    directory = args.directory.resolve()
    env = {**os.environ, "WINEPREFIX": str(PREFIX), "WINEDEBUG": "-all",
           "WINEDLLOVERRIDES": "d3d9=n", "DXVK_LOG_LEVEL": "warn",
           "DXVK_STATE_CACHE_PATH": str(directory)}
    for item in args.env:
        name, _, value = item.partition("=")
        env[name] = value
    if "ROSETTA_X87_PATH" in env:
        del env["ROSETTA_X87_PATH"]

    proc = subprocess.Popen([str(RUNTIME / "bin/wine"), args.exe, *args.args], cwd=directory,
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    target: int | None = None
    deadline = time.monotonic() + args.timeout
    samples: list[tuple[float, int, int, int, int, int]] = []
    last: ProcTaskInfo | None = None
    last_at = time.monotonic()
    output: list[str] = []
    try:
        while time.monotonic() < deadline:
            if target is None:
                candidates = pids_named(args.exe)
                if candidates:
                    target = candidates[0]
            if target is not None:
                info = task_info(target)
                if info is None:
                    break
                now = time.monotonic()
                if last is not None:
                    dt = now - last_at
                    samples.append((round(now - deadline + args.timeout, 2),
                                    int((info.faults - last.faults) / dt),
                                    int((info.cow_faults - last.cow_faults) / dt),
                                    int((info.syscalls_mach - last.syscalls_mach) / dt),
                                    int((info.total_system - last.total_system) / dt / 1e7),
                                    int((info.total_user - last.total_user) / dt / 1e7)))
                last, last_at = info, now
            if proc.poll() is not None and (target is None or task_info(target) is None):
                break
            time.sleep(0.25)
        if proc.poll() is None:
            proc.kill()
        output = (proc.communicate(timeout=10)[0] or "").splitlines()
    finally:
        stop_wine(env)

    frames = [line for line in output if line.startswith("frame=")]
    for line in output:
        if not line.startswith("frame="):
            print(line)
    if frames:
        print("frame times:", " ".join(line.split("seconds=")[1] for line in frames))
    if not output:
        print("benchmark produced no output; exit code", proc.returncode)
    if samples:
        peak = max(samples, key=lambda s: s[1])
        total = sum(s[1] for s in samples) * 0.5
        print(f"faults/s peak={peak[1]} cow/s={peak[2]} mach/s={peak[3]} "
              f"kernel%={peak[4]} user%={peak[5]} at t={peak[0]}s; samples={len(samples)} "
              f"approx_total_faults={int(total)}")
        for s in samples:
            print(f"  t={s[0]:5.1f} faults/s={s[1]:7d} cow/s={s[2]:5d} mach/s={s[3]:8d} "
                  f"kernel%={s[4]:3d} user%={s[5]:3d}")
    leftovers = wine_pids()
    print("leftover wine processes:", leftovers or "none")
    return 0 if not leftovers else 1


if __name__ == "__main__":
    raise SystemExit(main())
