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


def shutdown():
    """FFXI's own /shutdown command. Retried, because a missed keystroke leaves a character
    logged in on the server."""
    for attempt in range(3):
        if not b.focus_game() and not b.focus_game(hide_others=True):
            time.sleep(2)
            continue
        b.press(ESC, after=1.0)                # close any open menu first
        type_command("/shutdown")
        time.sleep(12)
        if b.game_window() is None:
            return True
    return b.game_window() is None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--profile", default=None)
    ap.add_argument("--character", type=int, default=0, help="rows to move down at character select")
    ap.add_argument("--sample", type=int, default=45)
    ap.add_argument("--zone-wait", type=int, default=45)
    args = ap.parse_args()

    profile = json.load(open(args.profile)) if args.profile else {}
    profile.setdefault("addons", "full")
    for kv in args.env:
        k, _, v = kv.partition("=")
        profile.setdefault("env", {})[k] = v

    os.makedirs(b.RESULTS, exist_ok=True)
    b.kill_all()
    b.write_default_txt(profile["addons"])
    b.apply_registry(profile.get("registry", {}))
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
    subprocess.Popen([b.WINE, r"C:\HorizonXI\Ashita-cli.exe", "horizonxi.ini"],
                     cwd=b.GAME, env=env, stdout=log, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)
    time.sleep(38)

    shots = []

    def snap(stage, n):
        p = b.shot(args.tag, n)
        if p:
            shots.append(dict(path=os.path.basename(p), t=round(time.time() - t0),
                              stage=stage, **b.score(p)))

    b.focus_game() or b.focus_game(hide_others=True)
    snap("boot", 0)

    # rules-of-conduct dialog, then the title screen, until the scene gets heavy
    for i in range(6):
        b.press(RETURN, after=1.0)
        time.sleep(11)
        snap(f"enter{i+1}", i + 1)
        rows = b.read_fps_csv(b.FPSCSV)[-3:]
        if rows and min(r["draws"] for r in rows) > 1200:
            break
        b.focus_game() or b.focus_game(hide_others=True)

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
    time.sleep(args.sample)
    snap("sample", 9)
    rows = b.read_fps_csv(b.FPSCSV)[mark:]

    logged_out = shutdown()
    snap("after-shutdown", 10)
    if not logged_out:
        print("WARNING: /shutdown did not close the client; character may still be online",
              file=sys.stderr)

    fps = [r["fps"] for r in rows]
    res = dict(tag=args.tag, env=profile.get("env", {}), scene="in-world",
               samples=len(fps), logged_out=logged_out,
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
          ("tag", "fps_median", "fps_min", "fps_max", "draws", "samples", "logged_out")}))


if __name__ == "__main__":
    main()
