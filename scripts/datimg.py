#!/usr/bin/env python3
"""Find and export images embedded in FFXI DAT files.

Format from XiyanFlowC/FFXIDat's docs/FILE_FORMATS.md and FFXIDat/Image.h. An image entry is:

    uint8   type        0x91 = paletted/raw bitmap, 0xA1 = DXT
    char[8] group
    char[8] name
    uint32  version     always 0x28
    uint32  width
    uint32  height
    uint16  mipmapCount
    uint16  bitCount    4, 8 or 0x20
    uint32  ukn[6]
    -- then, for 0xA1: char[4] fourCC, uint32 textureSize, uint32 pitch, then the DXT payload
    -- for 0x91 with bitCount 8: a 256-entry BGRA palette then width*height indices
    --                     0x20: width*height BGRA

Scanning for that signature directly, rather than walking the block table, because the goal is
"which file holds this picture" across ~49,000 DATs, and a signature scan needs no assumption
about how any one file is laid out.

    ./datimg.py scan  --root "<game>/ROM" --grep-size 256x128    # list image entries
    ./datimg.py dump  --dat ROM/0/4.dat --out shots/dump         # write every image to PNG
"""
import argparse, os, struct, sys

HDR = struct.Struct("<B8s8sIIIHH24s")
assert HDR.size == 1 + 8 + 8 + 4 + 4 + 4 + 2 + 2 + 24


def printable(b):
    s = b.split(b"\0")[0]
    return all(32 <= c < 127 for c in s) and len(s) > 0


def entries(data):
    """Every plausible image header in `data`, as (offset, dict)."""
    out = []
    pos = 0
    while True:
        i = data.find(b"\x28\x00\x00\x00", pos)   # version field, the most selective constant
        if i < 0:
            break
        pos = i + 1
        start = i - 17                            # type + group + name
        if start < 0:
            continue
        try:
            t, group, name, ver, w, h, mips, bits, _ = HDR.unpack_from(data, start)
        except struct.error:
            continue
        if t not in (0x91, 0xA1) or ver != 0x28:
            continue
        if not (1 <= w <= 4096 and 1 <= h <= 4096):
            continue
        if bits not in (4, 8, 16, 0x20):
            continue
        if not printable(group) or not printable(name):
            continue
        out.append((start, {
            "type": t, "group": group.split(b"\0")[0].decode("latin-1").strip(),
            "name": name.split(b"\0")[0].decode("latin-1").strip(),
            "w": w, "h": h, "bits": bits, "mips": mips,
        }))
    return out


def decode(data, off, e):
    """(width, height, RGBA bytes) or None if the payload is not one we can render."""
    body = off + HDR.size
    w, h, bits = e["w"], e["h"], e["bits"]
    if e["type"] == 0xA1:
        fourcc = data[body:body + 4]
        size, _pitch = struct.unpack_from("<II", data, body + 4)
        payload = data[body + 12: body + 12 + size]
        return dxt(fourcc, payload, w, h)
    if bits == 0x20:
        px = data[body: body + w * h * 4]
        if len(px) < w * h * 4:
            return None
        out = bytearray(w * h * 4)
        for i in range(w * h):
            b, g, r, a = px[i * 4: i * 4 + 4]
            out[i * 4: i * 4 + 4] = bytes((r, g, b, a))
        return w, h, bytes(out)
    if bits == 8:
        pal = data[body: body + 1024]
        idx = data[body + 1024: body + 1024 + w * h]
        if len(idx) < w * h:
            return None
        out = bytearray(w * h * 4)
        for i, v in enumerate(idx):
            b, g, r, a = pal[v * 4: v * 4 + 4]
            out[i * 4: i * 4 + 4] = bytes((r, g, b, a))
        return w, h, bytes(out)
    return None


def dxt(fourcc, payload, w, h):
    """Minimal DXT1/3/5 decode -- enough to look at, which is all this is for."""
    # The fourCC is stored byte-reversed in these files: "3TXD" on disk is DXT3.
    fmt = fourcc.decode("latin-1", "replace").strip("\0")
    if fmt not in ("DXT1", "DXT2", "DXT3", "DXT4", "DXT5"):
        fmt = fourcc[::-1].decode("latin-1", "replace").strip("\0")
    if fmt not in ("DXT1", "DXT2", "DXT3", "DXT4", "DXT5"):
        return None
    bw, bh = (w + 3) // 4, (h + 3) // 4
    block = 8 if fmt == "DXT1" else 16
    out = bytearray(w * h * 4)
    p = 0
    for by in range(bh):
        for bx in range(bw):
            if p + block > len(payload):
                return w, h, bytes(out)
            blk = payload[p:p + block]
            p += block
            alpha = [255] * 16
            if fmt in ("DXT2", "DXT3"):
                bits = int.from_bytes(blk[:8], "little")
                alpha = [((bits >> (4 * i)) & 0xF) * 17 for i in range(16)]
                blk = blk[8:]
            elif fmt in ("DXT4", "DXT5"):
                a0, a1 = blk[0], blk[1]
                bits = int.from_bytes(blk[2:8], "little")
                tbl = [a0, a1]
                if a0 > a1:
                    tbl += [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                else:
                    tbl += [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                alpha = [tbl[(bits >> (3 * i)) & 7] for i in range(16)]
                blk = blk[8:]
            c0, c1 = struct.unpack_from("<HH", blk, 0)
            lut = int.from_bytes(blk[4:8], "little")

            def rgb(c):
                return (((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63,
                        (c & 31) * 255 // 31)
            a, b = rgb(c0), rgb(c1)
            if c0 > c1 or fmt != "DXT1":
                cols = [a, b,
                        tuple((2 * a[i] + b[i]) // 3 for i in range(3)),
                        tuple((a[i] + 2 * b[i]) // 3 for i in range(3))]
            else:
                cols = [a, b, tuple((a[i] + b[i]) // 2 for i in range(3)), (0, 0, 0)]
            for i in range(16):
                x, y = bx * 4 + i % 4, by * 4 + i // 4
                if x >= w or y >= h:
                    continue
                c = cols[(lut >> (2 * i)) & 3]
                o = (y * w + x) * 4
                out[o:o + 4] = bytes((c[0], c[1], c[2], alpha[i]))
    return w, h, bytes(out)


def png(path, w, h, rgba):
    import zlib
    raw = b"".join(b"\0" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(tag, body):
        c = tag + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def cmd_scan(args):
    minw, minh = (0, 0)
    if args.min_size:
        minw, minh = (int(v) for v in args.min_size.lower().split("x"))
    total = 0
    for root, _dirs, files in os.walk(args.root):
        for fn in sorted(files):
            if not fn.lower().endswith(".dat"):
                continue
            p = os.path.join(root, fn)
            try:
                data = open(p, "rb").read()
            except OSError:
                continue
            for off, e in entries(data):
                if e["w"] < minw or e["h"] < minh:
                    continue
                if args.newer_than and os.path.getmtime(p) <= args.newer_than:
                    continue
                total += 1
                print(f"{os.path.relpath(p, args.root)}\t+{off}\t{e['group']}/{e['name']}"
                      f"\t{e['w']}x{e['h']}\ttype={e['type']:#x}\tbits={e['bits']}")
    print(f"# {total} image entries", file=sys.stderr)


def cmd_dump(args):
    os.makedirs(args.out, exist_ok=True)
    data = open(args.dat, "rb").read()
    n = 0
    for off, e in entries(data):
        got = decode(data, off, e)
        if not got:
            continue
        w, h, rgba = got
        stem = f"{os.path.basename(args.dat)}_{off}_{e['group']}_{e['name']}_{w}x{h}"
        stem = "".join(c if c.isalnum() or c in "._-" else "_" for c in stem)
        png(os.path.join(args.out, stem + ".png"), w, h, rgba)
        n += 1
    print(f"{n} images -> {args.out}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("--root", required=True)
    s.add_argument("--min-size")
    s.add_argument("--newer-than", type=float, default=0)
    s.set_defaults(fn=cmd_scan)
    d = sub.add_parser("dump")
    d.add_argument("--dat", required=True)
    d.add_argument("--out", required=True)
    d.set_defaults(fn=cmd_dump)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
