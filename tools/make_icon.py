#!/usr/bin/env python3
"""Build the app icon (background + boss, no sword) and the launch-screen boss from the icon SVGs.

Pure Python (no dependencies): reads the 16 px <rect> cells and writes a 1024x1024 PNG.
Usage: python3 tools/make_icon.py
"""
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYERS = ["docs/icon/1-background.svg", "docs/icon/2-boss.svg"]  # sword left out on purpose
OUT = ROOT / "DungeonsAndDeadlines/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
RECT = re.compile(r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="#([0-9a-fA-F]{6})"/>')

pixels = [[(0, 0, 0)] * SIZE for _ in range(SIZE)]
for layer in LAYERS:
    for x, y, w, h, color in RECT.findall((ROOT / layer).read_text()):
        rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))
        x, y, w, h = map(int, (x, y, w, h))
        for yy in range(y, y + h):
            row = pixels[yy]
            for xx in range(x, x + w):
                row[xx] = rgb

raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
OUT.write_bytes(png)
print(f"wrote {OUT.relative_to(ROOT)}")

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
