#!/usr/bin/env python3
"""Extract a subset of vanilla locomotive directions as raw cells for pack_sprites.

Vanilla sheets: 8 files per layer, 4 cols x 8 rows of direction cells, 256
directions total (cell index == direction index, north first, clockwise).

Writes <out>/<layer>/<i>.png for our direction i = i * (256 / dirs), plus a
meta.json carrying each layer's vanilla shift (in tiles) so packed sheets keep
the same registration.
"""
import argparse
import json
import os
import re
import sys

from PIL import Image

LAYERS = {
    "base": "locomotive",
    "mask": "locomotive-mask",
    "shadow": "locomotive-shadow",
}
COLS, ROWS, FILES, TOTAL = 4, 8, 8, 256


def vanilla_shift(graphics_dir, prefix):
    path = os.path.join(graphics_dir, prefix + ".lua")
    m = re.search(r"by_pixel\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)", open(path).read())
    return [float(m.group(1)) / 32, float(m.group(2)) / 32]


def extract_layer(graphics_dir, prefix, out_dir, dirs):
    cw = ch = None
    cache = {}
    for i in range(dirs):
        vi = i * (TOTAL // dirs)
        f = vi // (COLS * ROWS)
        local = vi % (COLS * ROWS)
        if f not in cache:
            sheet = Image.open(os.path.join(graphics_dir, "%s-%d.png" % (prefix, f + 1))).convert("RGBA")
            cache[f] = sheet
            cw, ch = sheet.width // COLS, sheet.height // ROWS
        row, col = divmod(local, COLS)
        cell = cache[f].crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
        cell.save(os.path.join(out_dir, "%d.png" % i))
    return cw, ch


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--factorio", default=os.path.expanduser(
        "~/.local/share/Steam/steamapps/common/Factorio/data/base"))
    p.add_argument("--out", required=True, help="raw output root, one subdir per layer")
    p.add_argument("--dirs", type=int, default=16)
    a = p.parse_args()

    graphics = os.path.join(a.factorio, "graphics/entity/locomotive")
    for layer, prefix in LAYERS.items():
        out_dir = os.path.join(a.out, layer)
        os.makedirs(out_dir, exist_ok=True)
        cw, ch = extract_layer(graphics, prefix, out_dir, a.dirs)
        shift = vanilla_shift(graphics, prefix)
        with open(os.path.join(out_dir, "meta.json"), "w") as fh:
            json.dump({"shift": shift}, fh)
        print("%s: %d cells of %dx%d, shift %s" % (prefix, a.dirs, cw, ch, shift))


if __name__ == "__main__":
    main()
