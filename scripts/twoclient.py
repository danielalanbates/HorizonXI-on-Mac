#!/usr/bin/env python3
"""Launch one FFXI client (lsb.ini or lsb2.ini) and walk it into the world.
   python3 twoclient.py launch <1|2>   -> starts, walks in, exits (client keeps running)
   python3 twoclient.py shot <1|2> <path>
   python3 twoclient.py cmd <1|2> "<chat command>"
   python3 twoclient.py pids
"""
import os, sys, time, json, subprocess
import Quartz
from AppKit import NSWorkspace, NSRunningApplication

WRAP = "/Volumes/Games/FFXI/siku.app"
SS = f"{WRAP}/Contents/SharedSupport"
PFX = f"{SS}/prefix10"
GAME = f"{PFX}/drive_c/HorizonXI"
WINE = f"{SS}/wine/bin/wine"
STATE = os.path.dirname(os.path.abspath(__file__)) + "/twoclient-state.json"
ENV = {
    "WINEPREFIX": PFX,
    "DYLD_FALLBACK_LIBRARY_PATH": f"{WRAP}/Contents/Frameworks:/usr/lib",
    "D3DMETAL_FRAMEWORK_PATH": f"{WRAP}/Contents/Frameworks/renderer/d3dmetal/external",
    "WINEMSYNC": "1", "MVK_CONFIG_FAST_MATH_ENABLED": "1", "MVK_CONFIG_USE_COMMAND_POOLING": "1",
    "MVK_CONFIG_PREALLOCATE_DESCRIPTORS": "1", "MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION": "1",
    "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "1", "DXVK_CONFIG_FILE": r"C:\HorizonXI\dxvk.conf",
    "WINEDEBUG": "-all",
}
RETURN, DOWN, ESC = 36, 125, 53


def load_state():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save_state(s):
    json.dump(s, open(STATE, "w"))


def loader_pids():
    out = subprocess.run(["ps", "-Ao", "pid=,comm="], capture_output=True, text=True).stdout
    return sorted(int(l.split()[0]) for l in out.splitlines() if "horizon-loader" in l.lower())


def windows():
    opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
    return [w for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
            if (w.get("kCGWindowOwnerName") or "") == "wine" and w["kCGWindowBounds"]["Width"] > 300]


def win_for(pid):
    ws = [w for w in windows() if w["kCGWindowOwnerPID"] == pid]
    return max(ws, key=lambda w: w["kCGWindowBounds"]["Width"] * w["kCGWindowBounds"]["Height"]) if ws else None


def frontmost_pid():
    out = subprocess.run(["osascript", "-e",
                          'tell application "System Events" to unix id of first process whose frontmost is true'],
                         capture_output=True, text=True, timeout=10).stdout.strip()
    return int(out) if out else -1


def focus(pid, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if frontmost_pid() == pid:
            return True
        subprocess.run(["osascript", "-e",
                        f'tell application "System Events" to set frontmost of (first process whose unix id is {pid}) to true'],
                       capture_output=True)
        time.sleep(0.5)
        if frontmost_pid() == pid:
            return True
        w = win_for(pid)
        if w:
            b = w["kCGWindowBounds"]
            x, y = b["X"] + b["Width"] / 2.0, b["Y"] + 12.0
            for ev in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
                e = Quartz.CGEventCreateMouseEvent(None, ev, (x, y), Quartz.kCGMouseButtonLeft)
                Quartz.CGEventPost(Quartz.kCGSessionEventTap, e)
                time.sleep(0.1)
        time.sleep(1)
    return frontmost_pid() == pid


def press(pid, key, hold=0.1, after=0.5):
    if frontmost_pid() != pid and not focus(pid):
        raise SystemExit(f"client pid {pid} not frontmost; refusing to type")
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None, key, True))
    time.sleep(hold)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None, key, False))
    time.sleep(after)


def shot(pid, path):
    w = win_for(pid)
    if not w:
        return False
    subprocess.run(["screencapture", "-x", "-o", "-l", str(w["kCGWindowNumber"]), path])
    return os.path.exists(path)


def launch(n):
    boot = "lsb.ini" if n == 1 else "lsb2.ini"
    before = set(loader_pids())
    env = dict(os.environ, **ENV)
    if n == 2:
        env["FLCLIENT"] = "2"
    log = open(f"{os.path.dirname(STATE)}/client{n}.wine.log", "wb")
    subprocess.Popen([WINE, r"C:\HorizonXI\Ashita-cli.exe", boot], cwd=GAME, env=env,
                     stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
    # reaper for winedbg crash dialogs
    subprocess.Popen(["/bin/sh", "-c", "while pgrep -qf horizon-loader.exe; do pkill -f 'winedbg --auto'; sleep 2; done"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    pid = None
    for _ in range(90):
        time.sleep(1)
        new = [p for p in loader_pids() if p not in before]
        if new:
            pid = new[0]
            break
    if not pid:
        raise SystemExit("no horizon-loader appeared")
    print(f"client {n} loader pid {pid}", flush=True)
    st = load_state(); st[str(n)] = pid; save_state(st)
    for _ in range(150):
        time.sleep(1)
        if win_for(pid):
            break
    print("window up; waiting for first frame (DXVK)", flush=True)
    time.sleep(75)
    return pid


def walk_in(pid, n):
    d = os.path.dirname(STATE)
    focus(pid)
    shot(pid, f"{d}/c{n}-boot.png")
    for i in range(6):
        press(pid, RETURN, after=1.0)
        time.sleep(10)
        shot(pid, f"{d}/c{n}-enter{i+1}.png")
        focus(pid)
    press(pid, RETURN, after=1.5)
    time.sleep(4)
    press(pid, RETURN, after=1.5)
    time.sleep(45)
    shot(pid, f"{d}/c{n}-zonedin.png")


def cmd(n, text):
    suffix = "" if n == 1 else "2"
    with open(f"{GAME}/addons/mousediag/cmd{suffix}.txt", "a") as f:
        f.write(text + "\n")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "launch":
        n = int(a[1]); pid = launch(n); walk_in(pid, n)
    elif a[0] == "walk":
        n = int(a[1]); walk_in(load_state()[str(n)], n)
    elif a[0] == "shot":
        print(shot(load_state()[a[1]], a[2]))
    elif a[0] == "cmd":
        cmd(int(a[1]), a[2])
    elif a[0] == "pids":
        print(load_state(), loader_pids())
    elif a[0] == "focus":
        print(focus(load_state()[a[1]]))
