#!/usr/bin/env python3
"""Renderer-agnostic frame-rate estimate by screen capture.

Records the game window region for N seconds and counts how many frames are visually
distinct (ffmpeg mpdecimate). Distinct frames per second is the presented frame rate, as long
as the scene actually changes every frame -- true for FFXI's animated scenes, not true for a
frozen menu, so cross-check against DXVK_FPS_LOG on a DXVK run before trusting it elsewhere.

    ./fpsvideo.py 20
"""
import json, re, subprocess, sys


def game_window():
    import Quartz
    opts = (Quartz.kCGWindowListOptionOnScreenOnly |
            Quartz.kCGWindowListExcludeDesktopElements)
    for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID):
        if (w.get("kCGWindowOwnerName") or "") == "wine" and \
           w.get("kCGWindowBounds", {}).get("Width", 0) > 400:
            return w
    return None


def measure(seconds=20, scale=2):
    w = game_window()
    if not w:
        return dict(error="no game window")
    b = w["kCGWindowBounds"]
    # avfoundation captures the display in physical pixels; window bounds are points.
    x, y = int(b["X"] * scale), int(b["Y"] * scale)
    cw, ch = int(b["Width"] * scale), int(b["Height"] * scale)
    # Trim the title bar and a margin so window chrome/shadow never counts as a change.
    y += 60
    ch -= 80
    cw -= 40
    x += 20
    vf = f"crop={cw}:{ch}:{x}:{y},mpdecimate=hi=64*12:lo=64*5:frac=0.33"
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-loglevel", "info",
           "-f", "avfoundation", "-capture_cursor", "0", "-framerate", "60",
           "-i", "1", "-t", str(seconds), "-vf", vf, "-an", "-f", "null", "-"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    kept = None
    for m in re.finditer(r"frame=\s*(\d+)", p.stderr):
        kept = int(m.group(1))
    drops = None
    m = re.search(r"(\d+) frames? (?:successfully )?decoded", p.stderr)
    return dict(seconds=seconds, unique_frames=kept,
                fps=round(kept / seconds, 2) if kept else None,
                crop=[cw, ch, x, y],
                stderr_tail=p.stderr.strip().splitlines()[-3:] if kept is None else None)


if __name__ == "__main__":
    print(json.dumps(measure(int(sys.argv[1]) if len(sys.argv) > 1 else 20), indent=1))
