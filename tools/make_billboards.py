"""Sponsor billboard atlases for West Coast USA (sl_billboards, #47): python tools/make_billboards.py

West Coast USA's stock billboards (dragbillboard_sign01..08, material 'billboards') all use one 2048x1024 atlas of sixteen 512x256 ads
(assets/materials/billboard_label.zip: t_billboards_b.color.dds). For every sponsor, club and crew name this writes the same atlas with five of
the ads (the tyre, shock-absorber and oil ones those signs show) replaced by that name's own ad, as mod/art/street_legal/billboards/<slug>.jpg.
sl_billboards puts the right one on the material while the career has that sponsor (or club, or crew), and the original back when it stops.
The ads are drawn here (a gradient, the name in bold letters, a tagline and a chequered stripe): nothing is copied from anywhere.
"""
import io
import os
import re
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "mod", "art", "street_legal", "billboards")
GAME = r"I:\SteamLibrary\steamapps\common\BeamNG.drive"
ATLAS = "assets/materials/billboard_label/billboards/t_billboards_b.color.dds"
TILE_W, TILE_H = 512, 256
# (column, row) of the ads that are replaced: the tyre, shock absorber, oil and burger/juice signs
REPLACED = [(3, 3), (0, 3), (1, 3), (2, 3), (2, 0)]
FONT_HEAD, FONT_TAG = r"C:\Windows\Fonts\impact.ttf", r"C:\Windows\Fonts\arialbd.ttf"

# name -> (slug, tagline, colours (top, bottom), text colour)
ADS = {
    "Valo Tyre & Wheel": ("valo-tyre-wheel", "GRIP YOU CAN TRUST", ((18, 64, 160), (6, 20, 70)), (255, 255, 255)),
    "Redline Speed Shop": ("redline-speed-shop", "EVERYTHING FOR THE FAST", ((200, 20, 20), (70, 4, 4)), (255, 255, 255)),
    "Nightrun Energy": ("nightrun-energy", "RUN ALL NIGHT", ((30, 20, 70), (5, 5, 20)), (255, 214, 0)),
    "the Southside Kings": ("southside-kings", "OWN THE SOUTH", ((120, 30, 140), (35, 8, 45)), (255, 220, 80)),
    "Riverbed Runners": ("riverbed-runners", "FOLLOW THE RIVER", ((20, 120, 110), (5, 40, 38)), (255, 255, 255)),
    "the North End crew": ("north-end-crew", "NORTH END FOREVER", ((60, 70, 85), (15, 18, 24)), (255, 255, 255)),
    "Ring Road Ghosts": ("ring-road-ghosts", "NOBODY SEES US GO", ((90, 90, 100), (10, 10, 14)), (200, 240, 255)),
    "Club 1": ("club-1", "THE CLUB FOR STARTERS", ((40, 130, 60), (8, 40, 16)), (255, 255, 255)),
    "Club 2": ("club-2", "STEP UP", ((210, 130, 20), (80, 40, 4)), (255, 255, 255)),
    "Club 3": ("club-3", "ONLY THE BEST", ((190, 160, 40), (60, 48, 6)), (20, 20, 20)),
}


def gradient(size, top, bottom):
    w, h = size
    im = Image.new("RGB", size)
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return im


def fit(draw, text, font_path, box_w, max_h):
    size = max_h
    while size > 8:
        font = ImageFont.truetype(font_path, size)
        l, t, r, b = draw.textbbox((0, 0), text, font=font)
        if r - l <= box_w and b - t <= max_h:
            return font, (r - l, b - t, l, t)
        size -= 2
    font = ImageFont.truetype(font_path, 8)
    return font, (0, 0, 0, 0)


def ad(name):
    slug, tagline, (top, bottom), ink = ADS[name]
    im = gradient((TILE_W, TILE_H), top, bottom)
    d = ImageDraw.Draw(im)
    # a chequered stripe along the bottom and a slanted band behind the name
    for i in range(0, TILE_W, 16):
        for j, y in enumerate((TILE_H - 32, TILE_H - 16)):
            if (i // 16 + j) % 2 == 0:
                d.rectangle([i, y, i + 15, y + 15], fill=(240, 240, 240))
    d.polygon([(0, 70), (TILE_W, 40), (TILE_W, 170), (0, 190)], fill=tuple(max(0, c - 40) for c in top))
    font, (w, h, ox, oy) = fit(d, name.upper(), FONT_HEAD, TILE_W - 50, 90)
    d.text(((TILE_W - w) // 2 - ox, 115 - h // 2 - oy), name.upper(), font=font, fill=ink)
    font2, (w2, h2, ox2, oy2) = fit(d, tagline, FONT_TAG, TILE_W - 80, 26)
    d.text(((TILE_W - w2) // 2 - ox2, 195 - oy2), tagline, font=font2, fill=(235, 235, 235))
    return slug, im


def tiles():
    """The overlay fallback (release.py --billboards overlay): only our own five-ad tiles, no pixel of the game's atlas.
    mod/art/street_legal/billboards/tiles/<slug>_<n>.png, n = 1..5 in the order of REPLACED (sl/core/billboards.lua draws them into the game's own atlas)."""
    out = os.path.join(OUT, "tiles")
    os.makedirs(out, exist_ok=True)
    for name in ADS:
        slug, tile = ad(name)
        for n in range(1, len(REPLACED) + 1):
            tile.save(os.path.join(out, "%s_%d.png" % (slug, n)), optimize=True)
    print("tiles written to", out)


def main():
    z = zipfile.ZipFile(os.path.join(GAME, "content", "assets", "materials", "billboard_label.zip"))
    atlas = Image.open(io.BytesIO(z.read(ATLAS))).convert("RGB")
    assert atlas.size == (2048, 1024), atlas.size
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for name in ADS:
        slug, tile = ad(name)
        out = atlas.copy()
        for col, row in REPLACED:
            out.paste(tile, (col * TILE_W, row * TILE_H))
        path = os.path.join(OUT, slug + ".jpg")
        out.save(path, quality=88, optimize=True)
        total += os.path.getsize(path)
        print(slug, os.path.getsize(path) // 1024, "KB")
    print("total %.1f MB" % (total / 1048576))


if __name__ == "__main__":
    if "--tiles" in sys.argv:
        tiles()          # (needs no game files)
    else:
        main()
