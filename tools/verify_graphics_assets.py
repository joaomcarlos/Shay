#!/usr/bin/env python3
"""Verify sprite geometry, raw-cell order, metadata shifts and PNG integrity."""

import hashlib
import json
import math
from pathlib import Path
import subprocess

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def metadata(path):
    # Execute the requested loadfile verification before inspecting its result.
    quoted = json.dumps(str(path))
    subprocess.run(["lua", "-e", f"assert(loadfile({quoted}))()"], check=True)
    program = f"""
local t = assert(loadfile({quoted}))()
assert(type(t) == 'table')
print(t.width, t.height, t.line_length, t.lines_per_file, t.shift[1], t.shift[2])
for _, name in ipairs(t.filenames) do print(name) end
"""
    result = subprocess.run(["lua", "-e", program], check=True,
                            capture_output=True, text=True).stdout.splitlines()
    return [float(value) for value in result[0].split()], result[1:]


def verify_sheet(name, layer, count, cols, rows, size=None):
    prefix = name + ("" if layer == "base" else "-" + layer)
    folder = ROOT / "graphics/entity" / name
    values, filenames = metadata(folder / f"{prefix}.lua")
    width, height, actual_cols, actual_rows, shift_x, shift_y = values
    width, height = int(width), int(height)
    assert (actual_cols, actual_rows) == (cols, rows), prefix
    if size:
        assert (width, height) == size, prefix
    raw = ROOT / "work/raw" / name / layer
    raw_files = sorted(raw.glob("*.png"), key=lambda p: int(p.stem))
    assert [int(p.stem) for p in raw_files] == list(range(count)), prefix
    shift = json.loads((raw / "meta.json").read_text())["shift"]
    assert [shift_x, shift_y] == shift, prefix
    assert len(filenames) == math.ceil(count / (cols * rows)), prefix
    hashes = []
    checked = 0
    for file_index, suffix in enumerate(filenames):
        with Image.open(folder / (prefix + suffix)) as sheet:
            sheet.load()
            remaining = count - checked
            assert sheet.mode == "RGBA", prefix
            assert sheet.size == (cols * width,
                                  min(rows, math.ceil(remaining / cols)) * height), prefix
            assert max(sheet.size) <= 4096, prefix
            for row in range(sheet.height // height):
                for col in range(cols):
                    index = file_index * rows * cols + row * cols + col
                    if index >= count:
                        continue
                    cell = sheet.crop((col * width, row * height,
                                       (col + 1) * width, (row + 1) * height))
                    with Image.open(raw_files[index]) as original:
                        assert original.size == (width, height), raw_files[index]
                        assert original.convert("RGBA").tobytes() == cell.tobytes(), index
                    assert cell.getchannel("A").getbbox(), (prefix, index)
                    hashes.append(hashlib.sha256(cell.tobytes()).hexdigest())
                    checked += 1
    assert checked == count
    if name == "shay-sentry-bot":
        assert len(set(hashes[::4])) == 8, "directions must be distinct"
        for direction in range(8):
            assert len(set(hashes[direction * 4:direction * 4 + 4])) >= 3
    if name == "shay-grinder":
        assert len(set(hashes)) == 8, "all grinder phases must be distinct"
    print(f"PASS {prefix}: {count} cells, {width}x{height}, {cols}x{rows} grid, shift {shift}")


def main():
    for name in ("shay-mg-wagon", "shay-ramp-wagon", "shay-locomotive"):
        for layer in ("base", "mask", "shadow"):
            verify_sheet(name, layer, 16, 4, 4)
    verify_sheet("shay-sentry-bot", "base", 32, 4, 8, (40, 48))
    verify_sheet("shay-grinder", "base", 8, 8, 1, (96, 96))
    verify_sheet("shay-ramp", "base", 1, 1, 1, (64, 160))
    for name in ("shay-gun-locomotive", "shay-mg-wagon", "shay-locomotive",
                 "shay-ramp-wagon", "shay-sentry-bot"):
        path = ROOT / "graphics/icons" / f"{name}.png"
        with Image.open(path) as icon:
            icon.load()
            assert icon.mode == "RGBA" and icon.size == (64, 64), path
            assert icon.getchannel("A").getbbox(), path
        print(f"PASS icon {name}: 64x64 RGBA")
    pngs = sorted((ROOT / "graphics").rglob("*.png"))
    for path in pngs:
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            image.load()
    layouts = sorted((ROOT / "graphics").rglob("*.lua"))
    for path in layouts:
        metadata(path)
    print(f"PASS all {len(pngs)} graphics PNGs decode; all {len(layouts)} metadata files load through Lua")


if __name__ == "__main__":
    main()
