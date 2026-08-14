#!/usr/bin/env python3
"""Build a de-branded copy of the client's title texture, as an XIPivot overlay.

The HorizonXI logo is one texture: entry `menu/titlwin` in `ROM/119/50.dat`, 1024x1024 DXT3.
Finding it took a while and several wrong guesses, so, for whoever reads this next:

  * It is NOT in an XIPivot overlay. Dropping HorizonXI's two overlays leaves the logo on screen.
  * It is NOT `menu/xilogo`. Both copies of that (ROM/0/2.DAT and ROM/118/112.DAT) are the stock
    FINAL FANTASY XI ONLINE logo, untouched.
  * XIPivot's fopen log cannot find it by timing: the client opens every DAT in one burst at
    startup, seconds before it draws anything.
  * Blanking candidate DATs to find it by elimination does not work either -- a zeroed DAT hangs
    the client before it renders.

What did work: scan every DAT for the image-entry signature from FFXIDat's format notes
(`datimg.py`), restrict to the 2,801 files whose mtime post-dates the 2023-08-15 base install,
and dump the ones in menu-ish groups. `menu/titlwin` is the only branded image in the set.

**The top of that texture is not branding.** Rows 0..~290 hold shared UI text -- the copyright
line, and OK / はい / いいえ / 戻る / キャンセル and the rest of the menu words. Replacing the whole
texture would delete those. Only the lower region is touched, and by default the stock
`menu/xilogo` art is composited in its place so the screen is not simply empty.

    ./brandpatch.py --out-overlay stockbrand          # write the overlay
    ./brandpatch.py --preview shots/brandpatch.png    # just render what it would look like

The output goes to a new overlay directory; nothing under SquareEnix/ is written to, so the
change is reversible by removing one line from pivot.ini.
"""
import argparse, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import datimg

GAME = "/Users/daniel/Games/HorizonXI/SquareEnix/FINAL FANTASY XI"
DATS = ("/Users/daniel/Games/HorizonXI/siku.app/Contents/SharedSupport/prefix10"
        "/drive_c/HorizonXI/polplugins/DATs")

TITLE_DAT = "ROM/119/50.dat"
TITLE_ENTRY = "titlwin"
STOCK_LOGO_DAT = "ROM/0/2.DAT"
STOCK_LOGO_ENTRY = "xilogo"

# Rows below this are branding; rows above are the shared menu wordlist and must survive.
BRAND_TOP = 296


def find(data, name):
    for off, e in datimg.entries(data):
        if e["name"] == name:
            return off, e
    raise SystemExit(f"entry {name!r} not found")


def to565(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def from565(c):
    return (((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31)


def encode_dxt3(w, h, rgba):
    """Straightforward DXT3: explicit 4-bit alpha, and a 4-colour ramp between the two extreme
    colours in each block. Not a quality encoder -- but the pixels it has to survive are flat
    white line art and full transparency, where the naive choice is also the right one."""
    out = bytearray()
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            px = []
            for y in range(4):
                for x in range(4):
                    o = (min(by + y, h - 1) * w + min(bx + x, w - 1)) * 4
                    px.append(rgba[o:o + 4])
            abits = 0
            for i, p in enumerate(px):
                abits |= (p[3] >> 4) << (4 * i)
            out += abits.to_bytes(8, "little")

            lum = [p[0] * 299 + p[1] * 587 + p[2] * 114 for p in px]
            hi, lo = px[lum.index(max(lum))], px[lum.index(min(lum))]
            c0, c1 = to565(hi[0], hi[1], hi[2]), to565(lo[0], lo[1], lo[2])
            if c0 < c1:
                c0, c1 = c1, c0
            if c0 == c1:
                c1 = max(0, c0 - 1)
            a, b = from565(c0), from565(c1)
            ramp = [a, b,
                    tuple((2 * a[i] + b[i]) // 3 for i in range(3)),
                    tuple((a[i] + 2 * b[i]) // 3 for i in range(3))]
            lut = 0
            for i, p in enumerate(px):
                best, bd = 0, 1 << 30
                for j, c in enumerate(ramp):
                    d = sum((c[k] - p[k]) ** 2 for k in range(3))
                    if d < bd:
                        best, bd = j, d
                lut |= best << (2 * i)
            out += struct.pack("<HHI", c0, c1, lut)
    return bytes(out)


def scale_into(dst, dw, dh, src, sw, sh, x0, y0, tw, th):
    """Nearest-neighbour composite of src into dst at (x0, y0), scaled to tw x th."""
    for y in range(th):
        sy = min(sh - 1, y * sh // th)
        for x in range(tw):
            sx = min(sw - 1, x * sw // tw)
            s = src[(sy * sw + sx) * 4:(sy * sw + sx) * 4 + 4]
            if s[3] == 0:
                continue
            o = ((y0 + y) * dw + (x0 + x)) * 4
            if 0 <= o < len(dst) - 3:
                dst[o:o + 4] = s


def build():
    title = open(os.path.join(GAME, TITLE_DAT), "rb").read()
    toff, tent = find(title, TITLE_ENTRY)
    w, h, rgba = datimg.decode(title, toff, tent)
    px = bytearray(rgba)

    # Where the server's artwork actually sits, measured rather than guessed. The game draws a
    # sub-rect of this texture and the mapping is not obvious -- a centred replacement came out
    # clipped off the left edge of the screen. Fitting the replacement into the same bounding box
    # the original branding occupied sidesteps the question entirely.
    x0, y0, x1, y1 = w, h, 0, 0
    for y in range(BRAND_TOP, h):
        row = y * w
        for x in range(w):
            if rgba[(row + x) * 4 + 3] > 8:
                x0, y0 = min(x0, x), min(y0, y)
                x1, y1 = max(x1, x), max(y1, y)
    if x1 <= x0 or y1 <= y0:
        raise SystemExit("no branding found below BRAND_TOP -- is this already patched?")
    print(f"branding bounding box: x {x0}..{x1}, y {y0}..{y1}")

    # Clear the branded region to fully transparent.
    for y in range(BRAND_TOP, h):
        for x in range(w):
            o = (y * w + x) * 4
            px[o:o + 4] = b"\0\0\0\0"

    # Composite the stock FFXI logo where the server logo used to sit.
    stock = open(os.path.join(GAME, STOCK_LOGO_DAT), "rb").read()
    soff, sent = find(stock, STOCK_LOGO_ENTRY)
    sw, sh, spx = datimg.decode(stock, soff, sent)
    # The stock xilogo texture is not only the logo: its top ~43% is a baked copyright block that
    # the title screen draws separately. Crop to the artwork, or the screen ends up with the
    # copyright twice.
    crop_top = sh * 43 // 100
    cropped = bytearray()
    for y in range(crop_top, sh):
        cropped += spx[(y * sw) * 4:((y + 1) * sw) * 4]
    ch = sh - crop_top

    # Fit inside the measured box, preserving the logo's aspect ratio and centring it there.
    NUDGE_X_BOX = 130
    x0 += NUDGE_X_BOX                          # see the note on NUDGE_X below
    box_w, box_h = x1 - x0 + 1, y1 - y0 + 1
    scale = min(box_w / sw, box_h / ch)
    target_w, target_h = int(sw * scale), int(ch * scale)
    # The game does not draw this texture from x=0: at 1440 px wide the left ~175 texture pixels
    # fall off the left of the window. HorizonXI's own logo was clipped by it too -- the shipped
    # title screen reads "ORIZON XI", with the H cut in half. Faithfully reproducing the original
    # placement therefore reproduces the defect, so the replacement is nudged right until it is
    # wholly on screen. Measured from shots/brandtest4.png, where the logo was cut mid-"F".
    px_x = x0 + (box_w - target_w) // 2
    px_y = y0 + (box_h - target_h) // 2
    if px_x + target_w > w:                    # never run off the right edge instead
        px_x = w - target_w
    print(f"stock logo placed at x {px_x}..{px_x + target_w}, y {px_y}..{px_y + target_h}")
    scale_into(px, w, h, bytes(cropped), sw, ch, px_x, px_y, target_w, target_h)
    return title, toff, tent, w, h, bytes(px)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-overlay")
    ap.add_argument("--preview")
    args = ap.parse_args()

    title, toff, tent, w, h, px = build()

    if args.preview:
        os.makedirs(os.path.dirname(args.preview) or ".", exist_ok=True)
        datimg.png(args.preview, w, h, px)
        print(f"preview -> {args.preview}")

    if not args.out_overlay:
        return

    body = toff + datimg.HDR.size
    size = struct.unpack_from("<I", title, body + 4)[0]
    payload = encode_dxt3(w, h, px)
    if len(payload) != size:
        raise SystemExit(f"re-encoded payload is {len(payload)} bytes, entry expects {size}")

    patched = title[:body + 12] + payload + title[body + 12 + size:]
    assert len(patched) == len(title), "patched DAT changed length"

    dst = os.path.join(DATS, args.out_overlay, TITLE_DAT)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(patched)
    print(f"overlay -> {dst} ({len(patched)} bytes, same as source)")


if __name__ == "__main__":
    main()
