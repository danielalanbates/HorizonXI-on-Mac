#!/usr/bin/env python3
"""Generate the icon the *game* runs under, as opposed to the launcher's own.

Same original crystal motif as make_icon.py -- this project's art, not a reproduction of Square
Enix's crystal -- but warmer: gold-dominant facets over a deeper night backdrop, so a glance at
the Dock tells the launcher and a running world apart. Written into the wine wrapper's bundle at
launch (see DockIcon.swift), which is what the Dock shows for a game process.

    python3 scripts/make_game_icon.py   ->  app/GameIcon.icns
"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024
OUT_PNG = "/private/tmp/claude-501/-Users-daniel/bab9eae9-60f5-431d-a033-547a09bc59a5/scratchpad/game_icon_1024.png"
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# ---- macOS Big Sur-style squircle mask ----
def squircle_mask(size, corner_exp=5.0, margin=0.045):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    inset = int(size * margin)
    d.rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset],
        radius=int(size * 0.225),
        fill=255,
    )
    return m

mask = squircle_mask(S)

# ---- backdrop: indigo/violet radial + linear wash, matching Vana palette ----
backdrop = Image.new("RGB", (S, S), (10, 10, 26))
bd = ImageDraw.Draw(backdrop)
night = (7, 7, 18)
indigo = (20, 18, 48)
violet = (38, 27, 70)
for y in range(S):
    t = y / S
    r = int(violet[0] * (1 - t) + night[0] * t)
    g = int(violet[1] * (1 - t) + night[1] * t)
    b = int(violet[2] * (1 - t) + night[2] * t)
    bd.line([(0, y), (S, y)], fill=(r, g, b))

# crystal glow wash top-left, gold glow bottom-right (matches Vana.backdrop)
glow = Image.new("RGB", (S, S), (0, 0, 0))
gd = ImageDraw.Draw(glow)
for radius, center, color, strength in [
    (int(S * 0.62), (int(S * 0.24), int(S * 0.10)), (140, 212, 242), 0.30),
    (int(S * 0.55), (int(S * 0.86), int(S * 0.95)), (237, 201, 112), 0.16),
]:
    layer = Image.new("L", (S, S), 0)
    ld = ImageDraw.Draw(layer)
    ld.ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        fill=int(255 * strength),
    )
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    solid = Image.new("RGB", (S, S), color)
    glow = Image.composite(solid, glow, layer)
backdrop = ImageChops.screen(backdrop, glow)

# ---- faceted crystal ----
cx, cy = S * 0.5, S * 0.52
w, h = S * 0.30, S * 0.46

top = (cx, cy - h * 0.62)
bottom = (cx, cy + h * 0.62)
waist_l = (cx - w * 0.52, cy - h * 0.06)
waist_r = (cx + w * 0.52, cy - h * 0.06)
shoulder_l = (cx - w * 0.30, cy - h * 0.30)
shoulder_r = (cx + w * 0.30, cy - h * 0.30)

crystal = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cdraw = ImageDraw.Draw(crystal)

# Gold-dominant, where the launcher's crystal is cyan: same shape, different metal.
crystal_dim = (150, 108, 40)
crystal_mid = (223, 178, 86)
crystal_bright = (255, 243, 214)

# outline silhouette (soft glow base)
outline_pts = [top, shoulder_r, waist_r, bottom, waist_l, shoulder_l]
glow_layer = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow_layer).polygon(outline_pts, fill=255)
glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(36))
glow_solid = Image.new("RGB", (S, S), crystal_mid)
backdrop = Image.composite(
    Image.blend(backdrop, glow_solid, 0.55), backdrop, glow_layer.point(lambda p: int(p * 0.9))
)

facets = [
    ([top, shoulder_l, waist_l], (168, 122, 46)),
    ([top, shoulder_r, waist_r], crystal_mid),
    ([top, shoulder_l, shoulder_r], crystal_bright),
    ([shoulder_l, waist_l, bottom], (126, 90, 34)),
    ([shoulder_r, waist_r, bottom], (198, 152, 66)),
    ([shoulder_l, shoulder_r, bottom], (214, 172, 92)),
]
for pts, color in facets:
    cdraw.polygon(pts, fill=color + (255,))

# crisp facet edges
edges = [top, shoulder_l, waist_l, bottom, waist_r, shoulder_r, top, shoulder_r, shoulder_l, bottom]
for i in range(0, len(edges) - 1, 1):
    cdraw.line([edges[i], edges[i + 1]], fill=(18, 24, 46, 160), width=6)

# bright top facet highlight
cdraw.polygon([top, shoulder_l, shoulder_r], fill=crystal_bright + (235,))
highlight = Image.new("L", (S, S), 0)
ImageDraw.Draw(highlight).polygon(
    [top, (shoulder_l[0] * 0.4 + top[0] * 0.6, shoulder_l[1] * 0.4 + top[1] * 0.6),
     (shoulder_r[0] * 0.4 + top[0] * 0.6, shoulder_r[1] * 0.4 + top[1] * 0.6)],
    fill=255,
)
highlight = highlight.filter(ImageFilter.GaussianBlur(4))

img = backdrop.convert("RGBA")
img.alpha_composite(crystal)

hl_solid = Image.new("RGBA", (S, S), (255, 255, 255, 235))
img = Image.composite(hl_solid, img, highlight)

# ---- gold ember glow at the base, echoing Vana.gold ----
base_glow = Image.new("L", (S, S), 0)
bgd = ImageDraw.Draw(base_glow)
bgd.ellipse(
    [cx - w * 0.55, bottom[1] - h * 0.10, cx + w * 0.55, bottom[1] + h * 0.30],
    fill=170,
)
base_glow = base_glow.filter(ImageFilter.GaussianBlur(30))
gold_solid = Image.new("RGBA", (S, S), (237, 201, 112, 255))
img = Image.composite(gold_solid, img, base_glow.point(lambda p: int(p * 0.55)))
img.alpha_composite(crystal)  # re-composite crystal on top of the gold wash

# thin gold ring accent behind the crystal, evoking a compass/aetheric ring
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
rr = w * 0.98
rd.ellipse([cx - rr, cy - rr * 1.02, cx + rr, cy + rr * 1.02], outline=(237, 201, 112, 130), width=5)
ring = ring.filter(ImageFilter.GaussianBlur(1))
img.alpha_composite(ring)
img.alpha_composite(crystal)

# ---- apply squircle mask + subtle inner vignette ----
out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
out.paste(img, (0, 0), mask)

out.save(OUT_PNG)
print("wrote", OUT_PNG)
