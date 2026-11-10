#!/usr/bin/env python3
"""Pack raw per-direction PNG cells into Factorio sprite sheets plus Lua metadata.

Input layout per layer:
    <src>/<dir>.png          cell images named by 0-based direction index
    <src>/meta.json          optional {"shift": [x_tiles, y_tiles]}

Output (per --prefix):
    <out>/<prefix>-<n>.png   packed sheets
    <out>/<prefix>.lua       sprite_load metadata, same shape vanilla uses

Cells are packed row-major, --cols per row, --rows-per-file rows per file.
--trim crops each cell to its alpha bounding box first, then re-centres it in a
uniform cell (used for generated art; vanilla-extracted cells pass verbatim).

--synth-shadow derives a shadow layer from the trimmed base alpha: darkened,
offset, blurred silhouette written to <out> as its own prefix for packing.
"""
import argparse
import json
import math
import os
import sys

from PIL import Image, ImageFilter


def load_cells(src):
    files = [f for f in os.listdir(src) if f.endswith(".png")]
    files.sort(key=lambda f: int(f[:-4]))
    return [os.path.join(src, f) for f in files]


def uniform_cells(paths, cell_size, trim):
    images = []
    max_w = max_h = 0
    for path in paths:
        im = Image.open(path).convert("RGBA")
        if trim:
            bbox = im.getbbox()
            if bbox:
                im = im.crop(bbox)
        max_w = max(max_w, im.width)
        max_h = max(max_h, im.height)
        images.append(im)
    w = cell_size[0] if cell_size else max_w
    h = cell_size[1] if cell_size else max_h
    out = []
    for im in images:
        cell = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        cell.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
        out.append(cell)
    return out, (w, h)


def pack(cells, size, cols, rows_per_file, out_dir, prefix):
    cw, ch = size
    rows = math.ceil(len(cells) / cols)
    files = math.ceil(rows / rows_per_file)
    filenames = []
    for f in range(files):
        row_start = f * rows_per_file
        row_count = min(rows_per_file, rows - row_start)
        sheet = Image.new("RGBA", (cols * cw, row_count * ch), (0, 0, 0, 0))
        for r in range(row_count):
            for c in range(cols):
                i = (row_start + r) * cols + c
                if i < len(cells):
                    sheet.paste(cells[i], (c * cw, r * ch))
        name = "-%d.png" % (f + 1)
        sheet.save(os.path.join(out_dir, prefix + name), optimize=True)
        filenames.append(name)
    return filenames


def write_metadata(out_dir, prefix, size, shift, cols, rows_per_file, filenames):
    lines = [
        "return",
        "{",
        "  width = %d," % size[0],
        "  height = %d," % size[1],
        "  shift = {%s, %s}," % (shift[0], shift[1]),
        "  line_length = %d," % cols,
        "  filenames = {",
    ]
    lines += ['    "%s",' % n for n in filenames]
    lines += ["  },", "  lines_per_file = %d," % rows_per_file, "}"]
    with open(os.path.join(out_dir, prefix + ".lua"), "w") as fh:
        fh.write("\n".join(lines) + "\n")


def synth_shadow(base_cells, size, offset, blur, opacity):
    cw, ch = size
    shadows = []
    for cell in base_cells:
        alpha = cell.split()[3].point(lambda a: int(a * opacity))
        sh = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        sh.putalpha(alpha)
        moved = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        moved.paste(sh, offset, sh)
        shadows.append(moved.filter(ImageFilter.GaussianBlur(blur)))
    return shadows


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True, help="raw cell dir for this layer")
    p.add_argument("--out", required=True, help="output graphics dir")
    p.add_argument("--prefix", required=True, help="file/metadata prefix")
    p.add_argument("--cols", type=int, default=4)
    p.add_argument("--rows-per-file", type=int, default=4)
    p.add_argument("--cell", default=None, help="fixed cell size WxH (default: max seen)")
    p.add_argument("--trim", action="store_true", help="alpha-crop cells then re-centre")
    p.add_argument("--shift", default=None, help="shift in tiles 'x,y' (default: meta.json or 0,0)")
    p.add_argument("--synth-shadow", action="store_true",
                   help="also emit <prefix>-shadow sheets+metadata from base alpha")
    p.add_argument("--shadow-offset", default="12,6", help="px 'dx,dy'")
    p.add_argument("--shadow-blur", type=float, default=6.0)
    p.add_argument("--shadow-opacity", type=float, default=0.5)
    a = p.parse_args()

    cell_size = tuple(int(v) for v in a.cell.split("x")) if a.cell else None
    paths = load_cells(a.src)
    if not paths:
        sys.exit("no cells in " + a.src)
    os.makedirs(a.out, exist_ok=True)

    cells, size = uniform_cells(paths, cell_size, a.trim)

    if a.shift:
        shift = [v.strip() for v in a.shift.split(",")]
    else:
        meta_file = os.path.join(a.src, "meta.json")
        shift = json.load(open(meta_file))["shift"] if os.path.exists(meta_file) else [0, 0]

    names = pack(cells, size, a.cols, a.rows_per_file, a.out, a.prefix)
    write_metadata(a.out, a.prefix, size, shift, a.cols, a.rows_per_file, names)
    print("%s: %d cells -> %d file(s), cell %dx%d" % (a.prefix, len(cells), len(names), *size))

    if a.synth_shadow:
        off = tuple(int(v) for v in a.shadow_offset.split(","))
        shadows = synth_shadow(cells, size, off, a.shadow_blur, a.shadow_opacity)
        s_prefix = a.prefix + "-shadow"
        s_names = pack(shadows, size, a.cols, a.rows_per_file, a.out, s_prefix)
        s_shift = [shift[0], shift[1]]
        write_metadata(a.out, s_prefix, size, s_shift, a.cols, a.rows_per_file, s_names)
        print("%s: synthesized" % s_prefix)


if __name__ == "__main__":
    main()
