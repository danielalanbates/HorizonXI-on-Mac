#!/usr/bin/env python3
"""In-world benchmark: log a character in, stand still, measure, log out cleanly.

Character select is a convenient scene but it is not the game. This walks all the way in, so
the number is one that matches what playing actually feels like.

    ./inworld.py --tag inworld-div1 --env FFXI_FPS_DIVISOR=1 --sample 45

It always finishes with /shutdown typed into the game's chat -- the client's own logout command
-- rather than killing the process, so the character does not stay online on the server.
"""
import argparse, importlib.util, json, os, shutil, statistics, subprocess, sys, time

WORK = "/Users/daniel/Games/hxi-workspace"
spec = importlib.util.spec_from_file_location("bench", f"{WORK}/bench.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

KEY = {'/': 44, 's': 1, 'h': 4, 'u': 32, 't': 17, 'd': 2, 'o': 31, 'w': 13, 'n': 45}
RETURN, DOWN, ESC = 36, 125, 53


def type_command(text):
    b.press(RETURN, after=1.5)                 # open the chat input
    for ch in text:
        b.press(KEY[ch], hold=0.06, after=0.12)
    time.sleep(0.6)
    b.press(RETURN, after=1.5)                 # send


def unhide_terminal():
    # The hide_others focus pass hides Terminal, which Daniel watches; always bring it back
    # when a run finishes (2026-08-20).
    import subprocess as _sp
    _sp.run(["osascript", "-e",
             'tell application "System Events" to set visible of process "Terminal" to true'],
            capture_output=True)


def shutdown(tag=None):
    """FFXI's own /shutdown command. Retried, because a missed keystroke leaves a character
    logged in on the server."""
    for attempt in range(5):
        # Focus is attempted but not required: a failed focus check used to `continue` and
        # burn every attempt without ever sending the command, which is how runs ended with
        # the character still standing in town.
        b.focus_game(hide_others=True)
        if tag:
            b.shot(tag, 30 + attempt)          # what the client looked like before typing
        # No ESC here: in FFXI, Escape *opens* the main menu in-world rather than closing
        # anything, and the Return that follows then picks a menu entry instead of opening
        # the chat line. That is why earlier runs left the character logged in.
        type_command("/shutdown")
        if tag:
            b.shot(tag, 20 + attempt)          # proof the command actually landed
        time.sleep(20)
        if b.game_window() is None:
            return True
    return b.game_window() is None


def game_pids():
    # The client's processes report a Windows command line ("C:\HorizonXI\pol.exe"), so match
    # on that rather than on a unix executable name.
    out = subprocess.run(["ps", "-Ao", "pid=,comm="], capture_output=True, text=True).stdout
    pids = []
    for line in out.splitlines():
        pid, _, comm = line.strip().partition(" ")
        # Only the wine-hosted client processes, whose comm is a Windows path. Matching on
        # "HorizonXI" alone also picks up wineserver, which lives under ~/Games/HorizonXI.
        # The client lives inside horizon-loader.exe -- it loads FFXiMain into itself, so
        # there is no pol.exe/FFXi process to find. Ashita-cli exits once it has injected.
        low = comm.lower()
        if "horizon-loader" in low or "ashita" in low or "pol.exe" in low:
            pids.append(int(pid))
    return pids


def thread_times():
    """{(pid, index): seconds of CPU} for every thread of the client, from `ps -M`."""
    acc = {}
    for pid in game_pids():
        out = subprocess.run(["ps", "-M", "-p", str(pid)], capture_output=True, text=True).stdout
        n = 0
        for line in out.splitlines()[1:]:
            # `ps -M` prints both STIME and UTIME as m:ss.ss. Taking the first match reads
            # system time only, which made a thread burning a full core look idle -- the
            # user-time column is the last one, so sum both and report the total.
            times = [t for t in line.split()
                     if ":" in t and t.replace(":", "").replace(".", "").isdigit()]
            if times:
                total = 0.0
                for t in times[:2]:
                    m, _, s = t.partition(":")
                    total += int(m) * 60 + float(s)
                acc[(pid, n)] = total
                n += 1
    return acc


def thread_delta(a, b_):
    d = sorted(((k, round(b_[k] - a.get(k, 0.0), 2)) for k in b_), key=lambda x: -x[1])
    return dict(total=round(sum(v for _, v in d), 2),
                top=[dict(pid=k[0], thread=k[1], cpu_s=v) for k, v in d[:6]])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--profile", default=None)
    ap.add_argument("--character", type=int, default=0, help="rows to move down at character select")
    ap.add_argument("--sample", type=int, default=45)
    ap.add_argument("--zone-wait", type=int, default=45)
    ap.add_argument("--no-ashita", action="store_true",
                    help="launch the bootloader directly, so a wrapper attaches to the game itself")
    ap.add_argument("--boot", default="horizonxi.ini",
                    help="boot profile to run: horizonxi.ini (live server) or lsb.ini (local)")
    args = ap.parse_args()

    profile = json.load(open(args.profile)) if args.profile else {}
    profile.setdefault("addons", "full")
    for kv in args.env:
        k, _, v = kv.partition("=")
        profile.setdefault("env", {})[k] = v

    os.makedirs(b.RESULTS, exist_ok=True)
    b.kill_all()
    b.write_default_txt(profile["addons"])
    b.apply_registry(profile.get("registry", {}), args.boot)
    dxvk_conf = profile.get("dxvk_conf")
    if dxvk_conf is None:
        shutil.copyfile(f"{b.BASE}/dxvk.conf.orig", f"{b.GAME}/dxvk.conf")
    else:
        open(f"{b.GAME}/dxvk.conf", "w").write(dxvk_conf)
    if os.path.exists(b.FPSCSV):
        os.remove(b.FPSCSV)

    env = dict(os.environ)
    env.update(b.BASE_ENV)
    env.update(profile.get("env", {}))
    for k, v in list(env.items()):
        if v in (None, ""):
            env.pop(k, None)

    log = open(f"{b.RESULTS}/{args.tag}.wine.log", "wb")
    t0 = time.time()
    # X87_WRAP launches wine underneath x87sidecar, which patches Rosetta's x87 handlers.
    # x87 measured ~85x slower than native through this wine and is the whole reason the
    # client is CPU bound, so this is the one lever that touches the actual cost.
    if args.no_ashita:
        # Launch the bootloader directly. This matters for x87sidecar: it patches the process
        # it launches, and under Ashita the game actually runs in a *child* (horizon-loader),
        # which stays unpatched -- wrapping the Ashita launch measured no change at all.
        # Credentials come from the boot profile's own .orig and are not written anywhere else.
        argv = b.loader_argv(args.boot)
    else:
        argv = [b.WINE, r"C:\HorizonXI\Ashita-cli.exe", args.boot]
    wrap = env.pop("X87_WRAP", "")
    if wrap:
        argv = wrap.split() + argv
    subprocess.Popen(argv,
                     cwd=b.GAME, env=env, stdout=log, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)

    # X87_ATTACH=<x87sidecar binary>: hook the game process once it exists.
    #
    # Ashita runs the client in a child (horizon-loader.exe), so launching wine underneath the
    # sidecar patches the wrong process -- measured, and it changed nothing. Attaching directly
    # is the way in. Done early, before the client starts rendering in earnest: Rosetta
    # translates each block once and keeps it, so anything translated before the hook lands
    # keeps running stock code.
    attach = env.get("X87_ATTACH", "")
    if attach:
        for _ in range(40):
            time.sleep(1)
            # horizon-loader.exe specifically -- Ashita-cli.exe also matches game_pids() and
            # starts first (lower pid), so taking pids[0] unfiltered attaches to the injector,
            # which does no rendering. That silent no-op cost hours the first time; see
            # docs/X87-WALL.md.
            out = subprocess.run(["ps", "-Ao", "pid=,comm="],
                                 capture_output=True, text=True).stdout
            pids = [int(pid) for line in out.splitlines()
                    for pid, _, comm in [line.strip().partition(" ")]
                    if "horizon-loader" in comm.lower()]
            if pids:
                # Ashita-cli.exe is still writing into this same process's memory for a moment
                # after the pid first appears -- attaching immediately races its injection and
                # intermittently corrupts it ("wine client error: write: Bad file descriptor",
                # "Injection failed!"). Give it a few seconds' head start.
                time.sleep(3)
                alog = open(f"{b.RESULTS}/{args.tag}.sidecar.log", "wb")
                subprocess.Popen([attach, "--attach", str(pids[0])],
                                 stdout=alog, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, start_new_session=True)
                print(f"  x87sidecar attaching to pid {pids[0]}", flush=True)
                break
        else:
            print("  WARNING: no game process appeared to attach to", file=sys.stderr)

    time.sleep(38)

    shots = []

    def snap(stage, n):
        p = b.shot(args.tag, n)
        if p:
            shots.append(dict(path=os.path.basename(p), t=round(time.time() - t0),
                              stage=stage, **b.score(p)))

    b.focus_game(hide_others=True)
    snap("boot", 0)

    # Cold DXVK pipeline caches (fresh wine, or the LSB path after the live cache was built
    # under a different wine) keep the window black for minutes; pressing Enter on schedule
    # then lands before any UI exists and the run never leaves the title screen
    # (lsb-verify, 2026-08-20). Wait for real pixels before the first key.
    for _ in range(48):   # up to 4 minutes
        pth = b.shot(args.tag, 99)
        if pth:
            import struct as _st
            with open(pth, "rb") as f:
                d = f.read()
            off = _st.unpack_from("<I", d, 10)[0] if len(d) > 14 else 0
            body = d[off::197]
            if body and sum(1 for x in body if x > 24) / len(body) > 0.02:
                break
        time.sleep(5)
    b.focus_game(hide_others=True)

    # rules-of-conduct dialog, then the title screen, until the scene gets heavy
    for i in range(6):
        b.press(RETURN, after=1.0)
        time.sleep(11)
        snap(f"enter{i+1}", i + 1)
        rows = b.read_fps_csv(b.FPSCSV)[-3:]
        if rows and min(r["draws"] for r in rows) > 1200:
            break
        b.focus_game(hide_others=True)

    for _ in range(args.character):
        b.press(DOWN, after=0.6)
    snap("charpick", 7)

    # select the character, confirm, wait for the zone to load
    b.press(RETURN, after=1.5)
    time.sleep(4)
    b.press(RETURN, after=1.5)
    time.sleep(args.zone_wait)
    snap("zonedin", 8)

    mark = len(b.read_fps_csv(b.FPSCSV))
    # Per-thread CPU time across the sample window. Percentages from `top` were ambiguous
    # (13% of a core while stalling 120 ms/frame); accumulated TIME is not. If the busiest
    # thread burns most of the wall clock it is computing; if it burns a fraction, it waits.
    open(f"{b.RESULTS}/{args.tag}.ps.txt", "w").write(
        subprocess.run(["ps", "-Ao", "pid,comm"], capture_output=True, text=True).stdout)
    threads0 = thread_times()
    time.sleep(args.sample)
    threads1 = thread_times()
    cpu = thread_delta(threads0, threads1)
    snap("sample", 9)
    rows = b.read_fps_csv(b.FPSCSV)[mark:]

    logged_out = shutdown(args.tag)
    snap("after-shutdown", 10)
    if not logged_out:
        print("WARNING: /shutdown did not close the client; character may still be online",
              file=sys.stderr)

    fps = [r["fps"] for r in rows]
    res = dict(tag=args.tag, env=profile.get("env", {}), scene="in-world",
               samples=len(fps), logged_out=logged_out, cpu=cpu, window_s=args.sample,
               fps_median=round(statistics.median(fps), 2) if fps else None,
               fps_mean=round(statistics.mean(fps), 2) if fps else None,
               fps_min=round(min(fps), 2) if fps else None,
               fps_max=round(max(fps), 2) if fps else None,
               draws=round(statistics.median([r["draws"] for r in rows]), 1) if rows else None,
               passes=round(statistics.median([r["passes"] for r in rows]), 1) if rows else None,
               shots=shots)
    json.dump(res, open(f"{b.RESULTS}/{args.tag}.json", "w"), indent=1)
    if os.path.exists(b.FPSCSV):
        shutil.copyfile(b.FPSCSV, f"{b.RESULTS}/{args.tag}.fps.csv")
    print("RESULT " + json.dumps({k: res[k] for k in
          ("tag", "fps_median", "fps_min", "fps_max", "draws", "samples", "logged_out", "cpu")}))


if __name__ == "__main__":
    try:
        main()
    finally:
        unhide_terminal()
        # Put the player's own addon list back so a later human session is not stuck
        # with the benchmark profile (missing mousediag = broken mouse).
        try:
            import shutil
            orig = f"{b.GAME}/scripts/default.txt.user-orig"
            if os.path.exists(orig):
                shutil.copyfile(orig, f"{b.GAME}/scripts/default.txt")
        except Exception:
            pass
