#!/usr/bin/env python3
"""Extract a subset of vanilla rolling-stock directions as raw cells for pack_sprites.

Vanilla stock sheets: N files per layer, 4 cols x 8 rows of direction cells
(index == direction index, north first, clockwise). Locomotive has 256
directions, wagons 128.

Writes <out>/<layer>/<i>.png for our direction i (i * total/dirs), plus a
meta.json carrying each layer's vanilla shift (in tiles).
"""
import argparse
import json
import os
import re

from PIL import Image

STOCK = {
    "locomotive": {"dir": "graphics/entity/locomotive", "prefix": "locomotive", "total": 256},
    "cargo-wagon": {"dir": "graphics/entity/cargo-wagon", "prefix": "cargo-wagon", "total": 128},
}
COLS, ROWS = 4, 8
LAYERS = {"base": "", "mask": "-mask", "shadow": "-shadow"}


def vanilla_shift(graphics_dir, prefix):
    path = os.path.join(graphics_dir, prefix + ".lua")
    m = re.search(r"by_pixel\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)", open(path).read())
    return [float(m.group(1)) / 32, float(m.group(2)) / 32]


def extract_layer(graphics_dir, prefix, out_dir, dirs, total):
    cw = ch = None
    cache = {}
    for i in range(dirs):
        vi = i * (total // dirs)
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
    p.add_argument("--stock", choices=sorted(STOCK), required=True)
    p.add_argument("--out", required=True, help="raw output root, one subdir per layer")
    p.add_argument("--dirs", type=int, default=16)
    a = p.parse_args()

    stock = STOCK[a.stock]
    graphics = os.path.join(a.factorio, stock["dir"])
    for layer, suffix in LAYERS.items():
        prefix = stock["prefix"] + suffix
        out_dir = os.path.join(a.out, layer)
        os.makedirs(out_dir, exist_ok=True)
        cw, ch = extract_layer(graphics, prefix, out_dir, a.dirs, stock["total"])
        shift = vanilla_shift(graphics, prefix)
        with open(os.path.join(out_dir, "meta.json"), "w") as fh:
            json.dump({"shift": shift}, fh)
        print("%s: %d cells of %dx%d, shift %s" % (prefix, a.dirs, cw, ch, shift))


if __name__ == "__main__":
    main()
