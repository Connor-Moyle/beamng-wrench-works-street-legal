"""Copy SLRR's own UI textures from your Street Legal Racing Redline install into the mod.

    python tools/slrr_ui.py [path to SLRR]

The dashboard (ui/modModules/slHud) and the phone use them when they are there and fall back to
their own drawing when not. They are not part of this repository: they belong to SLRR, so every
player copies them from their own copy of the game (the folder is in .gitignore).
"""
import os
import shutil
import sys

DEFAULT_SLRR = r"L:\SteamLibrary\steamapps\common\Street Legal Racing Redline"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "mod", "ui", "modModules", "slHud", "slrr")

# what we take, and the name it gets
FILES = {
    r"cars\textures\gauges\general\general_gauge.png": "general_gauge.png",   # speedometer, rev counter, gear box
    r"cars\textures\LongOSDGauge.png": "osd.png",                             # damage outline, ABS/ASR, nitro/turbo bars
    r"multibot\maps\ValoCity\data\minimap.png": "valo_minimap.png",
}


def main():
    slrr = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SLRR
    if not os.path.isdir(slrr):
        sys.exit("SLRR not found at %s - pass its folder: python tools/slrr_ui.py <path>" % slrr)
    os.makedirs(OUT, exist_ok=True)
    copied = 0
    for src, name in FILES.items():
        path = os.path.join(slrr, src)
        if os.path.isfile(path):
            shutil.copyfile(path, os.path.join(OUT, name))
            copied += 1
        else:
            print("missing in this install:", src)
    print("%d SLRR textures copied to %s" % (copied, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
