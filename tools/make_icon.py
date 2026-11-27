#!/usr/bin/env python3
"""Build the app icon and the launch-screen boss from the icon SVGs.

The icon is an Icon Composer document (`AppIcon.icon`) with two layers, so iOS 26 can draw its
Default, Dark, Clear and Tinted looks: a plain background in the app's page colors (cream for
Default, night purple for Dark) and the boss on a transparent layer. No sword (the user asked).

Pure Python (no dependencies): reads the 16 px <rect> cells and writes 1024x1024 PNGs.
Usage: python3 tools/make_icon.py
"""
import json
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "DungeonsAndDeadlines/Resources/AppIcon.icon"
SIZE = 1024
RECT = re.compile(r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="#([0-9a-fA-F]{6})"/>')


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_png(path, rows, color_type):
    """rows: list of rows of RGB (color_type 2) or RGBA (color_type 6) tuples."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)
    size = len(rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"wrote {path.relative_to(ROOT)}")


# The boss on the icon: 14 px per art cell, centered a touch below the middle so it sits level.
ICON_CELL, CENTER_X, CENTER_Y = 14, 512, 520


def boss_layer():
    """The boss at icon size on a transparent 1024x1024 canvas."""
    cells = []
    for x, y, w, h, color in RECT.findall((ROOT / "docs/icon/2-boss.svg").read_text()):
        rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
        cells.append((*(int(v) // 16 for v in (x, y, w, h)), rgb))
    mid_x = (min(c[0] for c in cells) + max(c[0] + c[2] for c in cells)) / 2
    mid_y = (min(c[1] for c in cells) + max(c[1] + c[3] for c in cells)) / 2
    left, top = round(CENTER_X - mid_x * ICON_CELL), round(CENTER_Y - mid_y * ICON_CELL)
    pixels = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    for x, y, w, h, rgb in cells:
        for yy in range(top + y * ICON_CELL, top + (y + h) * ICON_CELL):
            row = pixels[yy]
            for xx in range(left + x * ICON_CELL, left + (x + w) * ICON_CELL):
                row[xx] = rgb
    return pixels


def gradient(top, bottom, bands=32):
    """A plain background fading from `top` to `bottom` (hex colors) in pixel-art bands."""
    a, b = (tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in (top, bottom))
    rows = []
    for band in range(bands):
        mix = band / (bands - 1)
        rgb = tuple(round(a[i] + (b[i] - a[i]) * mix) for i in range(3)) + (255,)
        rows += [[rgb] * SIZE for _ in range(SIZE // bands)]
    return rows


ASSETS = ICON / "Assets"
# The theme's card and deep parchment (light), card and deep night (dark).
light, dark = gradient("fff6d6", "e2cb98"), gradient("2b184f", "0e0820")
boss = boss_layer()
write_png(ASSETS / "background.png", light, 6)
write_png(ASSETS / "background-dark.png", dark, 6)
write_png(ASSETS / "boss.png", boss, 6)
(ICON / "icon.json").write_text(json.dumps({
    "fill": {"solid": "extended-srgb:1.00000,0.96471,0.83922,1.00000"},
    "groups": [{
        "layers": [
            {"image-name": "boss.png", "name": "Boss", "glass": False},
            # Two backgrounds, swapped by appearance: the image-name specializations didn't take effect
            # in ictool, switching layers on and off does.
            {
                "image-name": "background.png", "name": "Background", "glass": False,
                "hidden-specializations": [{"appearance": "dark", "value": True}, {"appearance": "tinted", "value": True}],
            },
            {
                "image-name": "background-dark.png", "name": "Background (dark)", "glass": False,
                "hidden-specializations": [
                    {"value": True}, {"appearance": "dark", "value": False}, {"appearance": "tinted", "value": False},
                ],
            },
        ],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": False, "value": 0.5},
    }],
    "supported-platforms": {"squares": ["iOS"]},
}, indent=2) + "\n")
print(f"wrote {ICON.relative_to(ROOT)}/icon.json")

# App Store Connect subscription image: the flat icon art, 1024x1024, no transparency.
flat = [[(b[0], b[1], b[2]) if t[3] == 0 else (t[0], t[1], t[2]) for b, t in zip(brow, trow)] for brow, trow in zip(light, boss)]
write_png(ROOT / "docs/appstore/subscription-image.png", flat, 2)

# Launch screen: just the boss on a transparent background, 4 px per cell (256x256).
LAUNCH = ROOT / "DungeonsAndDeadlines/Resources/Assets.xcassets/LaunchBoss.imageset/LaunchBoss.png"
CELL, GRID = 4, 64
rgba = [[(0, 0, 0, 0)] * (GRID * CELL) for _ in range(GRID * CELL)]
for x, y, w, h, color in RECT.findall((ROOT / "docs/icon/2-boss.svg").read_text()):
    rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    x, y, w, h = (int(v) // 16 for v in (x, y, w, h))
    for yy in range(y * CELL, (y + h) * CELL):
        for xx in range(x * CELL, (x + w) * CELL):
            rgba[yy][xx] = rgb
raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rgba)
size = GRID * CELL
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
LAUNCH.write_bytes(png)
print(f"wrote {LAUNCH.relative_to(ROOT)}")
