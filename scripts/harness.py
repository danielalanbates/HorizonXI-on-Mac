#!/usr/bin/env python3
"""HorizonXI-on-Mac renderer harness.

Runs the game down a named renderer pathway, screenshots the screen at intervals, and
scores every screenshot for actual picture content. Counters lie; pixels do not.

Pathways
  gl      builtin D3D8 -> wined3d -> OpenGL          (shipped baseline)
  vk      builtin D3D8 -> wined3d -> Vulkan/MoltenVK (untried before 2026-08-10)
  dxvk    D3D8 -> d3d8to9 -> DXVK 1.10.3 -> MoltenVK

Usage: harness.py <pathway> [seconds] [--label X]
"""
import os, re, subprocess, sys, time, json, shutil

W = os.environ.get("HXI_WRAPPER", "/Volumes/x10/Video Games/Mac HorizonXI/siku.app")
S = f"{W}/Contents/SharedSupport"
P = f"{S}/prefix10"
G = f"{P}/drive_c/HorizonXI"
WINE = f"{S}/wine/bin/wine"
OUT = os.environ.get("HXI_OUT", os.path.dirname(os.path.abspath(__file__)) + "/shots")
os.makedirs(OUT, exist_ok=True)


def sh(*a, **kw):
    return subprocess.run(a, capture_output=True, text=True, **kw)


def kill_all():
    for pat in ("Ashita-cli", "horizon-loader", "pol.exe", "ffxi"):
        sh("pkill", "-9", "-f", pat)
    time.sleep(1)
    sh("pkill", "wineserver")
    # wineserver must actually exit before user.reg edits stick
    for _ in range(30):
        if not sh("pgrep", "-f", "wineserver").stdout.strip():
            return True
        time.sleep(1)
    sh("pkill", "-9", "wineserver")
    time.sleep(2)
    return False


def set_renderer(value):
    """value: 'gl' | 'vulkan' | None (delete key -> wine default)"""
    env = dict(os.environ, WINEPREFIX=P, WINEDEBUG="-all")
    key = r"HKCU\Software\Wine\Direct3D"
    if value is None:
        subprocess.run([WINE, "reg", "delete", key, "/v", "renderer", "/f"],
                       env=env, capture_output=True)
    else:
        subprocess.run([WINE, "reg", "add", key, "/v", "renderer", "/t", "REG_SZ",
                        "/d", value, "/f"], env=env, capture_output=True)
    kill_all()  # flush to user.reg


def dll_override(name, value):
    env = dict(os.environ, WINEPREFIX=P, WINEDEBUG="-all")
    key = r"HKCU\Software\Wine\DllOverrides"
    if value is None:
        subprocess.run([WINE, "reg", "delete", key, "/v", name, "/f"], env=env, capture_output=True)
    else:
        subprocess.run([WINE, "reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"],
                       env=env, capture_output=True)


def use_native_d3d8(on):
    """Swap C:\\HorizonXI d3d8.dll between the d3d8to9 shim and nothing."""
    repo = os.environ.get("HXI_REPO", "")
    targets = [f"{G}/d3d8.dll", f"{G}/bootloader/d3d8.dll"]
    if on:
        src = f"{repo}/vendor/d3d8to9.dll"
        for t in targets:
            os.makedirs(os.path.dirname(t), exist_ok=True)
            shutil.copyfile(src, t)
        dll_override("d3d8", "native")
        dll_override("d3d9", "native,builtin")
    else:
        for t in targets:
            if os.path.exists(t):
                os.remove(t)
        dll_override("d3d8", None)
        dll_override("d3d9", None)


PATHWAYS = {
    "gl":   dict(renderer="gl",     shim=False, env={}),
    "vk":   dict(renderer="vulkan", shim=False, env={}),
    "dxvk": dict(renderer="gl",     shim=True,
                 env={"DXVK_HUD": "fps,drawcalls,version", "DXVK_LOG_LEVEL": "info"}),
}


def launch(pathway, label):
    cfg = PATHWAYS[pathway]
    kill_all()
    set_renderer(cfg["renderer"])
    use_native_d3d8(cfg["shim"])
    kill_all()
    env = dict(os.environ)
    env.update({
        "WINEPREFIX": P,
        "WINEDEBUG": os.environ.get("HXI_WINEDEBUG", "-all"),
        "DYLD_FALLBACK_LIBRARY_PATH": f"{W}/Contents/Frameworks:/usr/lib",
        "D3DMETAL_FRAMEWORK_PATH": f"{W}/Contents/Frameworks/renderer/d3dmetal/external",
    })
    env.update(cfg["env"])
    env.update(json.loads(os.environ.get("HXI_ENV_JSON", "{}")))
    logp = f"{OUT}/{label}.log"
    log = open(logp, "wb")
    subprocess.Popen([WINE, r"C:\HorizonXI\Ashita-cli.exe", "horizonxi.ini"],
                     cwd=G, env=env, stdout=log, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)
    return logp


def displays():
    out = sh("system_profiler", "SPDisplaysDataType").stdout
    return "HP 24uh" in out


def shot(label, n):
    """Capture every display in the background; return list of paths."""
    paths = []
    for d in (1, 2):
        p = f"{OUT}/{label}-{n:02d}-D{d}.png"
        r = sh("screencapture", "-x", "-o", "-D", str(d), p)
        if r.returncode == 0 and os.path.exists(p):
            paths.append(p)
    return paths


def score(path):
    """Fraction of pixels that are not near-black, plus distinct-colour count."""
    from PIL import Image
    import numpy as np
    im = Image.open(path).convert("RGB")
    im.thumbnail((640, 400))
    a = np.asarray(im).astype(np.int16)
    lit = (a.max(axis=2) > 24).mean()
    q = (a // 32).reshape(-1, 3)
    colors = len(np.unique(q, axis=0))
    return dict(path=os.path.basename(path), lit=round(float(lit), 4), colors=int(colors))


def gpu_pct():
    out = sh("ioreg", "-rc", "IOAccelerator", "-w0").stdout
    m = re.search(r'"Device Utilization %"=(\d+)', out)
    return int(m.group(1)) if m else -1


def cpu_pct():
    out = sh("ps", "-Ao", "pcpu,comm").stdout
    tot = 0.0
    for line in out.splitlines():
        if "horizon-loader" in line or "Ashita" in line or "pol.exe" in line:
            try:
                tot += float(line.split()[0])
            except Exception:
                pass
    return round(tot, 1)


def main():
    pathway = sys.argv[1]
    seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    label = pathway
    if "--label" in sys.argv:
        label = sys.argv[sys.argv.index("--label") + 1]
    logp = launch(pathway, label)
    samples = []
    n = 0
    t0 = time.time()
    while time.time() - t0 < seconds:
        time.sleep(30)
        n += 1
        rec = dict(t=int(time.time() - t0), gpu=gpu_pct(), cpu=cpu_pct(),
                   frames=[score(p) for p in shot(label, n)])
        samples.append(rec)
        print(json.dumps(rec), flush=True)
    banner = ""
    try:
        txt = open(logp, errors="replace").read()
        for pat in (r"DXVK: (v[\d.]+)", r"wined3d.*", r"Created VkInstance for Vulkan version ([\d.]+)"):
            m = re.search(pat, txt)
            if m:
                banner += m.group(0)[:120] + " | "
    except Exception:
        pass
    res = dict(pathway=pathway, label=label, banner=banner, samples=samples)
    json.dump(res, open(f"{OUT}/{label}.json", "w"), indent=1)
    print("RESULT", json.dumps(dict(pathway=pathway, banner=banner,
                                    best=max((f["lit"] for s in samples for f in s["frames"]), default=0),
                                    gpu_max=max((s["gpu"] for s in samples), default=0),
                                    cpu_max=max((s["cpu"] for s in samples), default=0))))


if __name__ == "__main__":
    main()
