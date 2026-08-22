#!/usr/bin/env python3
"""Gaia XI per-file patcher — same algorithm as their Electron launcher:
fetch patch/manifest.json, sha256-compare every file, download mismatches from
PATCH_BASE_URL/<path>. Ignores the same paths their launcher ignores."""
import hashlib, json, os, sys, urllib.parse, urllib.request

ROOT = "/Volumes/x10/Video Games/Mac/FFXI/GaiaXI/GaiaXI"
BASE = "https://gaiaxi.evenmonkeys.workers.dev/patch"
IGNORE = ("squareenix/playonlineviewer/usr/", "squareenix/final fantasy xi/user/")
# Files this project must keep: our wine shims — never let the patch clobber them.
KEEP = {"d3d8.dll", "d3d9.dll", "dxvk.conf", "dgvoodoo.conf"}

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

req = urllib.request.Request(BASE + "/manifest.json", headers={"User-Agent": "Mozilla/5.0"})
manifest = json.load(urllib.request.urlopen(req, timeout=60))
files = manifest["files"]
todo = []
for f in files:
    rel = f["path"]
    low = rel.lower()
    if any(low.startswith(i) for i in IGNORE):
        continue
    if os.path.basename(low) in KEEP:
        continue
    dst = os.path.join(ROOT, rel)
    if os.path.exists(dst) and os.path.getsize(dst) == f.get("size", -1):
        # size fast-path; hash only when size matches but we must be sure
        if sha256(dst) == f["sha256"]:
            continue
    todo.append(f)

print(f"{len(todo)} of {len(files)} files need download "
      f"({sum(f.get('size',0) for f in todo)/1e6:.1f} MB)", flush=True)

done = 0
for f in todo:
    rel = f["path"]
    dst = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    url = BASE + "/" + urllib.parse.quote(rel)
    for attempt in range(4):
        try:
            r = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(r, timeout=120) as resp, open(dst + ".part", "wb") as out:
                while True:
                    c = resp.read(1 << 20)
                    if not c:
                        break
                    out.write(c)
            if sha256(dst + ".part") != f["sha256"]:
                raise IOError("sha mismatch")
            os.replace(dst + ".part", dst)
            break
        except Exception as e:
            if attempt == 3:
                print(f"FAILED {rel}: {e}", flush=True)
    done += 1
    if done % 200 == 0:
        print(f"{done}/{len(todo)}", flush=True)
print("PATCH COMPLETE", flush=True)
