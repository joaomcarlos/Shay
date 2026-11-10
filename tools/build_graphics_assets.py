#!/usr/bin/env python3
"""Build stock sheets, support sprites and icons from staged source artwork.

Requires Pillow. Run from any directory; sources are relative to the repo root.
The saved artwork in work/generated is required for the support sprites.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
STOCK = ("shay-mg-wagon", "shay-ramp-wagon", "shay-locomotive")


def clean_crop(image):
    """Remove nearly invisible alpha specks before measuring the silhouette."""
    image = image.convert("RGBA")
    image.putalpha(image.getchannel("A").point(lambda a: a if a > 8 else 0))
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("empty source image")
    return image.crop(bounds)


def fitted(image, size, inner):
    image = clean_crop(image)
    image.thumbnail(inner, Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", size)
    cell.paste(image, ((size[0] - image.width) // 2,
                      (size[1] - image.height) // 2))
    return cell


def write_cells(name, cells, shift=(0, 0)):
    folder = ROOT / "work/raw" / name / "base"
    folder.mkdir(parents=True, exist_ok=True)
    for index, cell in enumerate(cells):
        cell.save(folder / f"{index}.png", optimize=True)
    (folder / "meta.json").write_text(json.dumps({"shift": list(shift)}) + "\n")


def pack(name, prefix, cols, rows, layer="base"):
    subprocess.run([
        sys.executable, str(ROOT / "tools/pack_sprites.py"),
        "--src", str(ROOT / "work/raw" / name / layer),
        "--out", str(ROOT / "graphics/entity" / name),
        "--prefix", prefix, "--cols", str(cols), "--rows-per-file", str(rows),
    ], check=True)


def sentry():
    # Rows: N, NE, E, SE, S, SW, W, NW. Columns: four walk phases.
    # Two pixels of vertical travel, returning smoothly across the loop boundary.
    cells = []
    for direction in range(8):
        source = ROOT / "work/generated/shay-sentry-bot" / f"{direction}.png"
        with Image.open(source) as image:
            still = fitted(image, (40, 48), (36, 42))
        for bob in (0, -1, -2, -1):
            cell = Image.new("RGBA", still.size)
            cell.paste(still, (0, bob))
            cells.append(cell)
    write_cells("shay-sentry-bot", cells)
    pack("shay-sentry-bot", "shay-sentry-bot", 4, 8)


def grinder():
    # Source is a four-column, two-row turnaround of the rotating flutes.
    cells = []
    with Image.open(ROOT / "work/generated/shay-grinder/source.png") as sheet:
        for index in range(8):
            col, row = index % 4, index // 4
            box = (round(col * sheet.width / 4), round(row * sheet.height / 2),
                   round((col + 1) * sheet.width / 4),
                   round((row + 1) * sheet.height / 2))
            cells.append(fitted(sheet.crop(box), (96, 96), (88, 88)))
    write_cells("shay-grinder", cells)
    pack("shay-grinder", "shay-grinder", 8, 1)


def ramp():
    with Image.open(ROOT / "work/generated/shay-ramp/source.png") as image:
        cell = fitted(image, (64, 160), (56, 152))
    write_cells("shay-ramp", [cell])
    pack("shay-ramp", "shay-ramp", 1, 1)


def tint_icon(source, tint):
    # Vanilla icon files also contain mipmaps to the right of the 64px icon.
    with Image.open(source) as image:
        icon = image.convert("RGBA").crop((0, 0, 64, 64))
    grey = ImageOps.grayscale(icon)
    colors = ImageOps.colorize(grey, (12, 15, 18), tint, mid=(67, 70, 71),
                              midpoint=90).convert("RGBA")
    colors.putalpha(icon.getchannel("A"))
    return colors


def icons(vanilla):
    folder = ROOT / "graphics/icons"
    folder.mkdir(parents=True, exist_ok=True)
    recipes = (
        ("shay-gun-locomotive", "locomotive", (255, 160, 65)),
        ("shay-locomotive", "locomotive", (134, 221, 133)),
        ("shay-mg-wagon", "cargo-wagon", (115, 181, 255)),
        ("shay-ramp-wagon", "cargo-wagon", (250, 126, 120)),
    )
    for name, source, tint in recipes:
        tint_icon(vanilla / "graphics/icons" / f"{source}.png", tint).save(
            folder / f"{name}.png", optimize=True)
    with Image.open(ROOT / "work/generated/shay-sentry-bot/3.png") as image:
        fitted(image, (64, 64), (58, 58)).save(
            folder / "shay-sentry-bot.png", optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vanilla", type=Path, default=Path.home() /
                        ".local/share/Steam/steamapps/common/Factorio/data/base")
    args = parser.parse_args()
    for name in STOCK:
        for layer in ("base", "mask", "shadow"):
            prefix = name + ("" if layer == "base" else "-" + layer)
            pack(name, prefix, 4, 4, layer)
    sentry()
    grinder()
    ramp()
    icons(args.vanilla)


if __name__ == "__main__":
    main()
