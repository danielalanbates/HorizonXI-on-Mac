#!/usr/bin/env python3
"""Find which client DAT holds the HorizonXI title-screen branding, by elimination.

The problem: HorizonXI's installer replaced files inside the base client, so the logo is baked
into the DATs rather than layered on top by an overlay. Dropping the two HorizonXI XIPivot
overlays does nothing (verified: only remapster and xiview loaded, logo still there). Timing the
DAT opens from XIPivot's fopen log does not isolate it either -- the client opens every DAT in
one burst at startup, seconds before anything renders.

So: elimination. XIPivot can redirect any ROM path to an overlay directory, so this blanks one
candidate DAT at a time -- an all-zero file of the same length, in an overlay, leaving the real
file untouched -- launches to the rules screen where the logo is drawn, and screenshots it.
Whichever blank makes the logo disappear (or corrupt) is the file that holds it.

    ./brandprobe.py --candidates ROM/0/4.dat ROM/0/5.dat ROM/0/6.dat ROM/0/7.dat

Every run restores pivot.ini from a backup, including on failure; nothing under SquareEnix/ is
ever written to.
"""
import argparse, os, shutil, subprocess, sys, time

WORK = "/Users/daniel/Games/hxi-workspace"
PREFIX = ("/Users/daniel/Games/HorizonXI/siku.app/Contents/SharedSupport/prefix10"
          "/drive_c/HorizonXI")
GAME = "/Users/daniel/Games/HorizonXI/SquareEnix/FINAL FANTASY XI"
PIVOT_INI = f"{PREFIX}/config/pivot/pivot.ini"
DATS = f"{PREFIX}/polplugins/DATs"
OVERLAY = "brandprobe"
SHOTS = f"{WORK}/shots"


def say(m):
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)


def stage(rel):
    """An all-zero stand-in for `rel`, same length, inside the probe overlay."""
    src = os.path.join(GAME, rel.replace("/", os.sep))
    dst = os.path.join(DATS, OVERLAY, rel)
    if os.path.exists(os.path.join(DATS, OVERLAY)):
        shutil.rmtree(os.path.join(DATS, OVERLAY))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(b"\0" * os.path.getsize(src))
    return dst


def set_overlays(names):
    with open(PIVOT_INI) as f:
        text = f.read()
    head = text.split("[overlays]")[0]
    body = "[overlays]\n" + "".join(f"{i}={n}\n" for i, n in enumerate(names))
    with open(PIVOT_INI, "w") as f:
        f.write(head + body)


def current_overlays():
    with open(PIVOT_INI) as f:
        text = f.read()
    out = []
    for line in text.split("[overlays]")[-1].splitlines():
        if "=" in line:
            out.append(line.split("=", 1)[1].strip())
    return [o for o in out if o]


def window_id():
    import Quartz
    for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly,
                                               Quartz.kCGNullWindowID):
        if str(w.get("kCGWindowName", "")) == "FINAL FANTASY XI":
            return w.get("kCGWindowNumber")
    return None


def kill_client():
    for pat in ("Ashita-cli", "horizon-loader"):
        subprocess.run(["pkill", "-f", pat], capture_output=True)
    time.sleep(3)


def run_once(tag, boot, profile, settle):
    kill_client()
    log = f"{WORK}/logs/{tag}.out"
    with open(log, "w") as f:
        subprocess.Popen([sys.executable, "-u", f"{WORK}/launch.py", "--tag", tag,
                          "--boot", boot, "--profile", profile],
                         stdout=f, stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(120):
        time.sleep(2)
        if os.path.exists(log) and "rendering" in open(log, errors="replace").read():
            break
    else:
        say(f"{tag}: never rendered")
        return None
    time.sleep(settle)
    wid = window_id()
    if wid is None:
        say(f"{tag}: no game window")
        return None
    os.makedirs(SHOTS, exist_ok=True)
    shot = f"{SHOTS}/{tag}.png"
    subprocess.run(["screencapture", "-l", str(wid), "-x", shot], check=False)
    return shot if os.path.exists(shot) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", nargs="+", required=True)
    ap.add_argument("--boot", default="lsb.ini")
    ap.add_argument("--profile", default=f"{WORK}/profiles/lsb-max4k.json")
    ap.add_argument("--settle", type=int, default=25)
    ap.add_argument("--control", action="store_true", help="also shoot with no probe overlay")
    args = ap.parse_args()

    backup = PIVOT_INI + ".brandprobe-backup"
    if not os.path.exists(backup):
        shutil.copy2(PIVOT_INI, backup)
    original = current_overlays()
    say(f"overlays in use: {original}")

    try:
        if args.control:
            set_overlays(original)
            shot = run_once("brand-control", args.boot, args.profile, args.settle)
            say(f"control -> {shot}")

        for rel in args.candidates:
            tag = "brand-" + rel.replace("/", "_").replace(".", "_")
            stage(rel)
            set_overlays(original + [OVERLAY])
            say(f"blanking {rel}")
            shot = run_once(tag, args.boot, args.profile, args.settle)
            say(f"{rel} -> {shot}")
    finally:
        kill_client()
        shutil.copy2(backup, PIVOT_INI)
        probe = os.path.join(DATS, OVERLAY)
        if os.path.exists(probe):
            shutil.rmtree(probe)
        say("pivot.ini restored, probe overlay removed")


if __name__ == "__main__":
    main()
