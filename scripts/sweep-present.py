#!/usr/bin/env python3
"""Sweep D3D8 present-parameter and DXVK variations, screenshotting each.

The game draws (418 calls/frame) and DXVK presents (the HUD is visible), but the game's own
output is black. That points at the back buffer format / depth-stencil setup rather than
presentation, so vary those and look at the pictures.
"""
import os, re, subprocess, sys, time

S = "/Volumes/x10/Video Games/Mac HorizonXI/siku.app/Contents/SharedSupport"
W = "/Volumes/x10/Video Games/Mac HorizonXI/siku.app"
P = f"{S}/prefix10"
G = f"{P}/drive_c/HorizonXI"
INI = f"{G}/config/boot/horizonxi.ini"
OUT = "/private/tmp/claude-501/-Users-daniel/e76088d1-7627-4973-8b4e-9377b2f8d1cd/scratchpad"

# name -> (ini overrides, extra env)
CASES = {
    # D3DFMT_X8R8G8B8 = 22, A8R8G8B8 = 21, R5G6B5 = 23
    "fmt22":      ({"presentparams.backbufferformat": "22"}, {}),
    "fmt21":      ({"presentparams.backbufferformat": "21"}, {}),
    "depth_on":   ({"presentparams.enableautodepthstencil": "1",
                    "presentparams.autodepthstencilformat": "75"}, {}),   # D3DFMT_D24S8
    "swap_flip":  ({"presentparams.swapeffect": "3"}, {}),                # FLIP
    "swap_copy":  ({"presentparams.swapeffect": "2"}, {}),                # COPY
    "latency1":   ({}, {"DXVK_CONFIG": "d3d9.maxFrameLatency = 1;d3d9.presentInterval = 0"}),
    "nofloat":    ({}, {"DXVK_CONFIG": "d3d9.floatEmulation = False"}),
    "deferred":   ({}, {"DXVK_CONFIG": "d3d9.deferSurfaceCreation = True;d3d9.maxFrameLatency = 1"}),
}

BASE = {
    "presentparams.backbufferformat": "-1",
    "presentparams.backbuffercount": "1",
    "presentparams.multisampletype": "-1",
    "presentparams.swapeffect": "1",
    "presentparams.enableautodepthstencil": "-1",
    "presentparams.autodepthstencilformat": "-1",
}


def set_ini(overrides):
    s = open(INI, encoding="utf-8", errors="replace").read()
    vals = dict(BASE); vals.update(overrides)
    for k, v in vals.items():
        s = re.sub(rf"(?m)^({re.escape(k)}\s*=\s*).*$", lambda m: m.group(1) + v, s)
    open(INI, "w", encoding="utf-8").write(s)


def run(name, env_extra, seconds):
    subprocess.run(["pkill", "-9", "-f", "horizon-loader"], capture_output=True)
    time.sleep(2)
    env = dict(os.environ)
    env.update({
        "WINEPREFIX": P, "WINEDEBUG": "-all",
        "D3DMETAL_FRAMEWORK_PATH": f"{W}/Contents/Frameworks/renderer/d3dmetal/external",
        "DXVK_HUD": "fps,drawcalls",
    })
    env.update(env_extra)
    log = open(f"/tmp/sweep_{name}.log", "wb")
    subprocess.Popen([f"{S}/wine/bin/wine", r"C:\HorizonXI\Ashita-cli.exe", "horizonxi.ini"],
                     cwd=G, env=env, stdout=log, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)
    time.sleep(seconds)
    subprocess.run(["caffeinate", "-u", "-t", "1"], capture_output=True)
    subprocess.run(["screencapture", "-x", "-o", f"{OUT}/sweep_{name}.png"], capture_output=True)


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(CASES)
    for name in wanted:
        overrides, env_extra = CASES[name]
        set_ini(overrides)
        run(name, env_extra, 150)
        print(name, "captured", flush=True)
    subprocess.run(["pkill", "-9", "-f", "horizon-loader"], capture_output=True)
