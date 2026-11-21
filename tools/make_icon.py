#!/usr/bin/env python3
"""Build the app icon and the launch-screen boss from the icon SVGs.

The icon is an Icon Composer document (`AppIcon.icon`) with two layers, so iOS 26 can draw its
Default, Dark, Clear and Tinted looks: an opaque night-sky background (plus a darker one for
Dark) and the boss on a transparent layer. No sword (the user asked).

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


def paint(svg, fill=None, tone=1.0):
    """The SVG's cells at 1024x1024; transparent where nothing is drawn unless `fill` is given."""
    pixels = [[fill or (0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    for x, y, w, h, color in RECT.findall((ROOT / svg).read_text()):
        rgb = tuple(int(int(color[i:i + 2], 16) * tone) for i in (0, 2, 4)) + (255,)
        x, y, w, h = map(int, (x, y, w, h))
        for yy in range(y, y + h):
            row = pixels[yy]
            for xx in range(x, x + w):
                row[xx] = rgb
    return pixels


ASSETS = ICON / "Assets"
write_png(ASSETS / "background.png", paint("docs/icon/1-background.svg", fill=(0, 0, 0, 255)), 6)
# Dark appearance: the same sky, dimmed so the icon sits quietly on a dark home screen.
write_png(ASSETS / "background-dark.png", paint("docs/icon/1-background.svg", fill=(0, 0, 0, 255), tone=0.5), 6)
write_png(ASSETS / "boss.png", paint("docs/icon/2-boss.svg"), 6)
(ICON / "icon.json").write_text(json.dumps({
    "fill": {"solid": "extended-srgb:0.10196,0.05098,0.12157,1.00000"},
    "groups": [{
        "layers": [
            {"image-name": "boss.png", "name": "Boss", "glass": False},
            # Two skies, swapped by appearance: the image-name specializations didn't take effect
            # in ictool, switching layers on and off does.
            {
                "image-name": "background.png", "name": "Background", "glass": False,
                "hidden-specializations": [{"appearance": "dark", "value": True}],
            },
            {
                "image-name": "background-dark.png", "name": "Background (dark)", "glass": False,
                "hidden-specializations": [{"value": True}, {"appearance": "dark", "value": False}],
            },
        ],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": False, "value": 0.5},
    }],
    "supported-platforms": {"squares": ["iOS"]},
}, indent=2) + "\n")
print(f"wrote {ICON.relative_to(ROOT)}/icon.json")

# App Store Connect subscription image: the flat icon art, 1024x1024, no transparency.
bg, boss = paint("docs/icon/1-background.svg", fill=(0, 0, 0, 255)), paint("docs/icon/2-boss.svg")
flat = [[(b[0], b[1], b[2]) if t[3] == 0 else (t[0], t[1], t[2]) for b, t in zip(brow, trow)] for brow, trow in zip(bg, boss)]
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
