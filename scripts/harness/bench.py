#!/usr/bin/env python3
"""HorizonXI-on-Mac benchmark runner.

One command per configuration variant. Applies the variant, launches the game, walks it to the
character-select screen, samples the frame rate, screenshots the window in the background and
kills the client. Every variant is measured the same way so the numbers compare.

    ./bench.py --tag baseline
    ./bench.py --tag no-argbuf --env MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0
    ./bench.py --tag dxmt --profile profiles/dxmt.json

Frame rate comes from DXVK_FPS_LOG (built into our d3d9.dll) when the pathway uses DXVK, and
otherwise from fpsvideo.py, which counts visually distinct frames in a screen recording.

Scene: character select. Heavy (~1900 draws), deterministic, needs two keypresses to reach and
no character is in the world, so killing the client afterwards is safe.
"""
import argparse, json, os, re, shutil, statistics, subprocess, sys, time

WRAP  = "/Users/daniel/Games/HorizonXI/siku.app"
SS    = f"{WRAP}/Contents/SharedSupport"
PFX   = f"{SS}/prefix10"
GAME  = f"{PFX}/drive_c/HorizonXI"
WINE  = f"{SS}/wine/bin/wine"
WORK  = "/Users/daniel/Games/hxi-workspace"
BASE  = f"{WORK}/baseline-config"
RESULTS = f"{WORK}/results"
SHOTS = f"{WORK}/shots"
FPSCSV_WIN = r"C:\HorizonXI\logs\dxvkfps.csv"
FPSCSV = f"{GAME}/logs/dxvkfps.csv"

BASE_ENV = {
    "WINEPREFIX": PFX,
    "DYLD_FALLBACK_LIBRARY_PATH": f"{WRAP}/Contents/Frameworks:/usr/lib",
    "D3DMETAL_FRAMEWORK_PATH": f"{WRAP}/Contents/Frameworks/renderer/d3dmetal/external",
    "WINEMSYNC": "1",
    "MVK_CONFIG_FAST_MATH_ENABLED": "1",
    "MVK_CONFIG_USE_COMMAND_POOLING": "1",
    "MVK_CONFIG_PREALLOCATE_DESCRIPTORS": "1",
    "MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION": "1",
    "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "1",
    "DXVK_CONFIG_FILE": r"C:\HorizonXI\dxvk.conf",
    "DXVK_FPS_LOG": FPSCSV_WIN,
    "WINEDEBUG": "-all",
}

HORIZON_PLUGINS = ["addons", "screenshot", "Nameplate", "PacketFlow", "sequencer", "thirdparty"]
HORIZON_ADDONS  = ["dynamic_entity_renamer", "allmaps", "chatmon", "checker", "distance",
                   "filterless", "fps", "instantah", "links", "macrofix", "nocombat",
                   "nolock", "recast", "timers", "tparty"]
REQUIRED_PLUGINS = ["addons", "PacketFlow"]


def sh(*a, **kw):
    return subprocess.run(a, capture_output=True, text=True, **kw)


def kill_all():
    for pat in ("Ashita-cli", "horizon-loader", "pol.exe", "ffxi", "FFXi"):
        sh("pkill", "-9", "-f", pat)
    time.sleep(1)
    sh("pkill", "wineserver")
    for _ in range(25):
        if not sh("pgrep", "-f", "wineserver").stdout.strip():
            return
        time.sleep(1)
    sh("pkill", "-9", "wineserver")
    time.sleep(2)


def write_default_txt(addons_mode, extra=()):
    if addons_mode == "full":
        plugins, addons = HORIZON_PLUGINS, HORIZON_ADDONS
    elif addons_mode == "min":
        plugins, addons = REQUIRED_PLUGINS, []
    elif addons_mode == "none":
        plugins, addons = [], []
    else:
        raise SystemExit(f"unknown addons mode {addons_mode}")
    lines = ["/load winefix", ""]
    lines += [f"/load {p}" for p in plugins]
    lines += [f"/addon load {a}" for a in addons]
    lines += ["", "/wait 3", "/ambient 255 255 255"]
    lines += list(extra)
    open(f"{GAME}/scripts/default.txt", "w").write("\n".join(lines) + "\n")


def apply_registry(overrides):
    src = open(f"{BASE}/horizonxi.ini.orig", encoding="utf-8", errors="replace").read()
    if overrides:
        out, in_reg = [], False
        for line in src.splitlines():
            s = line.strip()
            if s.startswith("["):
                in_reg = s.lower() == "[ffxi.registry]"
            if in_reg:
                m = re.match(r"^(\d{4})(\s*=\s*)(.*)$", s)
                if m and m.group(1) in overrides:
                    out.append(f"{m.group(1)} = {overrides[m.group(1)]}")
                    continue
            out.append(line)
        src = "\n".join(out) + "\n"
    open(f"{GAME}/config/boot/horizonxi.ini", "w", encoding="utf-8").write(src)


def apply_dlls(profile):
    for name, src in profile.get("dlls", {}).items():
        for d in (GAME, f"{GAME}/bootloader"):
            dst = f"{d}/{name}"
            if src is None:
                if os.path.exists(dst):
                    os.remove(dst)
            else:
                shutil.copyfile(os.path.expanduser(src), dst)


def wine_reg(key, name, value, vtype="REG_SZ"):
    env = dict(os.environ, WINEPREFIX=PFX, WINEDEBUG="-all")
    if value is None:
        subprocess.run([WINE, "reg", "delete", key, "/v", name, "/f"], env=env, capture_output=True)
    else:
        subprocess.run([WINE, "reg", "add", key, "/v", name, "/t", vtype, "/d", value, "/f"],
                       env=env, capture_output=True)


def game_window():
    import Quartz
    opts = (Quartz.kCGWindowListOptionOnScreenOnly |
            Quartz.kCGWindowListExcludeDesktopElements)
    for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID):
        if (w.get("kCGWindowOwnerName") or "") == "wine" and \
           w.get("kCGWindowBounds", {}).get("Width", 0) > 400:
            return w
    return None


def focus_game(hide_others=False):
    """Give the game real keyboard focus. CGEventPostToPid does not work with wine, so the
    window has to actually be frontmost before any key is sent."""
    from AppKit import NSRunningApplication, NSWorkspace
    w = game_window()
    if not w:
        return False
    pid = w["kCGWindowOwnerPID"]
    ws = NSWorkspace.sharedWorkspace()
    if hide_others:
        for app in ws.runningApplications():
            if app.activationPolicy() == 0 and app.processIdentifier() != pid:
                app.hide()
        time.sleep(1.0)
    for _ in range(10):
        app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        if app is None:
            return False
        app.activateWithOptions_(1 << 1)
        time.sleep(0.8)
        if ws.frontmostApplication().processIdentifier() == pid:
            return True
    return False


def press(keycode, hold=0.10, after=0.4):
    import Quartz
    Quartz.CGEventPost(Quartz.kCGHIDEventTap,
                       Quartz.CGEventCreateKeyboardEvent(None, keycode, True))
    time.sleep(hold)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap,
                       Quartz.CGEventCreateKeyboardEvent(None, keycode, False))
    time.sleep(after)


def shot(tag, n):
    w = game_window()
    os.makedirs(SHOTS, exist_ok=True)
    p = f"{SHOTS}/{tag}-{n:02d}.png"
    if w:
        sh("screencapture", "-x", "-o", "-l", str(w["kCGWindowNumber"]), p)
    else:
        sh("screencapture", "-x", "-o", "-D", "1", p)
    return p if os.path.exists(p) else None


def score(path):
    try:
        from PIL import Image
        import numpy as np
    except Exception:
        return {}
    im = Image.open(path).convert("RGB")
    im.thumbnail((640, 400))
    a = np.asarray(im).astype(np.int16)
    return dict(lit=round(float((a.max(axis=2) > 24).mean()), 4),
                colors=int(len(np.unique((a // 32).reshape(-1, 3), axis=0))))


def read_fps_csv(path):
    rows = []
    if not os.path.exists(path):
        return rows
    for line in open(path, errors="replace"):
        p = line.strip().split(",")
        if len(p) < 9 or p[0] == "epoch":
            continue
        try:
            rows.append(dict(epoch=int(p[0]), elapsed=float(p[1]), fps=float(p[2]),
                             draws=float(p[3]), passes=float(p[4]), barriers=float(p[5]),
                             submits=float(p[6]), cschunks=float(p[7]), gpuidle=float(p[8])))
        except ValueError:
            continue
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--addons", default=None, choices=["full", "min", "none"])
    ap.add_argument("--env", action="append", default=[], help="KEY=VALUE, repeatable")
    ap.add_argument("--boot-wait", type=int, default=38, help="seconds before the first keypress")
    ap.add_argument("--sample", type=int, default=45, help="seconds of steady-state sampling")
    ap.add_argument("--video", action="store_true", help="also measure with the video counter")
    ap.add_argument("--heavy-draws", type=int, default=1200,
                    help="draw count that means the heavy scene has been reached")
    ap.add_argument("--enters", type=int, default=2,
                    help="Return presses after boot: 0 stops at the rules screen (light scene), 2 reaches character select (heavy)")
    ap.add_argument("--no-ashita", action="store_true",
                    help="launch the bootloader directly, with no Ashita hook")
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()

    profile = json.load(open(args.profile)) if args.profile else {}
    if args.addons:
        profile["addons"] = args.addons
    profile.setdefault("addons", "full")
    for kv in args.env:
        k, _, v = kv.partition("=")
        profile.setdefault("env", {})[k] = v

    for d in (RESULTS, SHOTS, f"{GAME}/logs"):
        os.makedirs(d, exist_ok=True)
    kill_all()

    write_default_txt(profile["addons"], profile.get("script_extra", []))
    apply_registry(profile.get("registry", {}))
    dxvk_conf = profile.get("dxvk_conf")
    if dxvk_conf is None:
        shutil.copyfile(f"{BASE}/dxvk.conf.orig", f"{GAME}/dxvk.conf")
    else:
        open(f"{GAME}/dxvk.conf", "w").write(dxvk_conf)
    apply_dlls(profile)
    if "renderer" in profile:
        subprocess.run([f"{WORK}/renderer.sh", profile["renderer"]], check=True)
    for k, v in profile.get("wine_reg", {}).items():
        key, name = k.rsplit("\\", 1)
        wine_reg(key, name, v)

    if os.path.exists(FPSCSV):
        os.remove(FPSCSV)

    env = dict(os.environ)
    env.update(BASE_ENV)
    env.update(profile.get("env", {}))
    for k, v in list(env.items()):
        if v in (None, ""):
            env.pop(k, None)

    if args.no_ashita:
        # Launch the private-server bootloader directly, with no Ashita injection at all.
        # Credentials come from the user's own Ashita ini and are never written anywhere else.
        cmd = None
        for line in open(f"{BASE}/horizonxi.ini.orig", encoding="utf-8", errors="replace"):
            m = re.match(r"^\s*command\s*=\s*(.+?)\s*$", line)
            if m and "--server" in m.group(1):
                cmd = m.group(1).split()
        if cmd is None:
            raise SystemExit("could not find the loader command line in the Ashita ini")
        argv = [WINE, r"C:\HorizonXI\bootloader\horizon-loader.exe"] + cmd
    else:
        argv = [WINE, r"C:\HorizonXI\Ashita-cli.exe", "horizonxi.ini"]

    log = open(f"{RESULTS}/{args.tag}.wine.log", "wb")
    t0 = time.time()
    subprocess.Popen(argv, cwd=GAME, env=env, stdout=log, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)

    # --- walk to character select ------------------------------------------------------
    deadline = time.time() + args.boot_wait
    while time.time() < deadline:
        time.sleep(2)
    shots = []
    p = shot(args.tag, 0)
    if p:
        shots.append(dict(path=os.path.basename(p), t=round(time.time() - t0), stage="boot", **score(p)))

    focused = focus_game() or focus_game(hide_others=True) if args.enters else None
    print(f"  focus={focused}", flush=True)
    # Keep pressing Return until the scene actually gets heavy. The rules-of-conduct dialog
    # and the title screen each need one press, and focus does not always take on the first
    # try, so this is driven by the measured draw count rather than a fixed number of presses.
    if args.enters:
        for i in range(6):
            press(36, after=1.0)             # 36 = Return
            time.sleep(11)
            p = shot(args.tag, i + 1)
            if p:
                shots.append(dict(path=os.path.basename(p), t=round(time.time() - t0),
                                  stage=f"enter{i+1}", **score(p)))
            recent = read_fps_csv(FPSCSV)[-3:]
            if recent and min(r["draws"] for r in recent) > args.heavy_draws:
                break
            focus_game() or focus_game(hide_others=True)

    # --- sample -------------------------------------------------------------------------
    mark = len(read_fps_csv(FPSCSV))
    video = None
    if args.video:
        vp = subprocess.Popen([sys.executable, f"{WORK}/fpsvideo.py", str(min(args.sample, 20))],
                              stdout=subprocess.PIPE, text=True)
    time.sleep(args.sample)
    if args.video:
        try:
            video = json.loads(vp.communicate(timeout=60)[0])
        except Exception:
            video = dict(error="video measure failed")
    p = shot(args.tag, 9)
    if p:
        shots.append(dict(path=os.path.basename(p), t=round(time.time() - t0), stage="sample", **score(p)))

    rows = read_fps_csv(FPSCSV)[mark:]
    fps = [r["fps"] for r in rows]
    res = dict(
        tag=args.tag, profile=args.profile, addons=profile["addons"],
        env=profile.get("env", {}), registry=profile.get("registry", {}),
        renderer=profile.get("renderer"), dlls=profile.get("dlls"),
        samples=len(fps),
        fps_median=round(statistics.median(fps), 2) if fps else None,
        fps_mean=round(statistics.mean(fps), 2) if fps else None,
        fps_min=round(min(fps), 2) if fps else None,
        fps_max=round(max(fps), 2) if fps else None,
        draws=round(statistics.median([r["draws"] for r in rows]), 1) if rows else None,
        passes=round(statistics.median([r["passes"] for r in rows]), 1) if rows else None,
        barriers=round(statistics.median([r["barriers"] for r in rows]), 1) if rows else None,
        submits=round(statistics.median([r["submits"] for r in rows]), 2) if rows else None,
        cschunks=round(statistics.median([r["cschunks"] for r in rows]), 1) if rows else None,
        gpuidle_us=round(statistics.median([r["gpuidle"] for r in rows]), 0) if rows else None,
        video=video, shots=shots,
    )
    json.dump(res, open(f"{RESULTS}/{args.tag}.json", "w"), indent=1)
    if os.path.exists(FPSCSV):
        shutil.copyfile(FPSCSV, f"{RESULTS}/{args.tag}.fps.csv")
    if not args.keep:
        kill_all()

    print("RESULT " + json.dumps({k: res[k] for k in
          ("tag", "fps_median", "fps_min", "fps_max", "draws", "passes", "barriers",
           "submits", "samples", "video")}))


if __name__ == "__main__":
    main()
