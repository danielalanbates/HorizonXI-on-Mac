#!/usr/bin/env python3
"""Is anything blinking in and out of the world?

Daniel reported NPCs flickering once per second with D3D9_RT_READBACK_NOWAIT on. A still
screenshot cannot show that -- the shots this project normally takes are seconds apart, so an
entity that vanishes for one frame in ten looks identical in every one of them. This grabs a
burst of frames a fraction of a second apart and reports how much each differs from the one
before, which is what flicker looks like numerically: a standing camera in a static scene holds
a low, flat difference, and geometry popping in and out shows up as spikes.

    python3 blinkprobe.py --tag nowait-on --shots 40 --interval 0.25

Run it while the client is already standing in the world (launch.py, then drive_inworld.py
--no-logout). Frames are captured as BMP: PNG bytes are compressed, so comparing those measures
how well each frame happened to compress rather than how different the pictures are.
"""
import argparse, importlib.util, os, struct, subprocess, time

WORK = "/Users/daniel/Games/hxi-workspace"
spec = importlib.util.spec_from_file_location("bench", f"{WORK}/bench.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

OUT = f"{WORK}/shots/blink"


def capture(tag, n, wid):
    path = f"{OUT}/{tag}-{n:03d}.bmp"
    subprocess.run(["screencapture", "-x", "-o", "-t", "bmp", "-l", str(wid), path],
                   capture_output=True)
    return path if os.path.exists(path) else None


def pixels(path):
    """Raw pixel bytes of a BMP, subsampled. Full 4K frames are 33 MB each and comparing every
    byte of 40 of them is slower than the capture itself; every 97th byte (a prime, so the
    stride does not land on the same channel every time) is plenty to see an object appear."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 14:
        return b""
    offset = struct.unpack_from("<I", data, 10)[0]
    return data[offset::97]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--shots", type=int, default=40)
    ap.add_argument("--interval", type=float, default=0.25)
    ap.add_argument("--keep-png", type=int, default=6,
                    help="also save this many PNGs, evenly spaced, for looking at by eye")
    args = ap.parse_args()

    win = b.game_window()
    if win is None:
        raise SystemExit("no game window -- is the client in the world?")
    wid = win.get("kCGWindowNumber")

    os.makedirs(OUT, exist_ok=True)
    frames = []
    for i in range(args.shots):
        p = capture(args.tag, i, wid)
        if p:
            frames.append(p)
        time.sleep(args.interval)
    print(f"captured {len(frames)} frames")

    every = max(1, len(frames) // max(1, args.keep_png))
    for i, p in enumerate(frames):
        if i % every == 0:
            subprocess.run(["sips", "-s", "format", "png", "-Z", "1400", p,
                            "--out", p.replace(".bmp", ".png")], capture_output=True)

    prev, diffs = None, []
    for p in frames:
        cur = pixels(p)
        if prev and cur:
            n = min(len(cur), len(prev))
            differing = sum(1 for x, y in zip(prev[:n], cur[:n]) if abs(x - y) > 8)
            diffs.append(differing / n)
        prev = cur
    for p in frames:
        os.remove(p)

    if diffs:
        s = sorted(diffs)
        print(f"frame-to-frame difference over {len(diffs)} pairs: "
              f"min {s[0]:.4f}  median {s[len(s)//2]:.4f}  p90 {s[int(len(s)*0.9)]:.4f}  "
              f"max {s[-1]:.4f}")
        print("spikes (>3x median): "
              f"{sum(1 for d in diffs if d > 3 * max(s[len(s)//2], 1e-6))} of {len(diffs)}")


if __name__ == "__main__":
    main()
