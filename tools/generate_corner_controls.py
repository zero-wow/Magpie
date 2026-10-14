"""Generate matching theme-tinted atlases for radar controls and route types.

The four rows are normal, hover, on, and on-hover. Each 64px cell has a
transparent gutter so the game can filter the atlas without neighboring art
bleeding into a button. The addon tints the white art with its current accent.
"""

import math
import struct
from pathlib import Path


CELL = 64
HEIGHT = 256
ICONS = ("config", "target", "legend", "minus", "plus", "north",
         "trail", "eye", "player", "close", "route", "tracker",
         "clear", "arrow", "minimize", "constellation")
ROUTE_ICONS = ("rare", "treasure", "quest", "zygor")
STATES = (
    # Circular hover wash, edge, icon, active underline. Active art never
    # acquires a separate square tile: it belongs to the same icon family.
    (0.00, 0.00, 0.76, 0.00),
    (0.06, 0.20, 1.00, 0.00),
    (0.00, 0.00, 1.00, 0.92),
    (0.08, 0.26, 1.00, 1.00),
)


def coverage(distance):
    return max(0.0, min(1.0, 0.5 - distance))


def segment(x, y, x1, y1, x2, y2, radius=2.3):
    dx, dy = x2 - x1, y2 - y1
    length_squared = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / length_squared))
    return math.hypot(x - x1 - t * dx, y - y1 - t * dy) - radius


def disk(x, y, cx, cy, radius):
    return math.hypot(x - cx, y - cy) - radius


def icon_distance(icon, x, y):
    if icon == "config":
        return min(abs(math.hypot(x, y) - 8) - 1.9, disk(x, y, 0, 0, 3.5))
    if icon == "target":
        return min(abs(math.hypot(x, y) - 8) - 1.7,
                   disk(x, y, 0, 0, 2.5),
                   segment(x, y, -12, 0, -9, 0, 1.6),
                   segment(x, y, 9, 0, 12, 0, 1.6),
                   segment(x, y, 0, -12, 0, -9, 1.6),
                   segment(x, y, 0, 9, 0, 12, 1.6))
    if icon == "legend":
        return min(min(disk(x, y, -9, row, 2.5),
                       segment(x, y, -3, row, 9, row, 1.25))
                   for row in (-8, 0, 8))
    if icon == "minus":
        return segment(x, y, -9, 0, 9, 0, 2.4)
    if icon == "plus":
        return min(segment(x, y, -9, 0, 9, 0, 2.4),
                   segment(x, y, 0, -9, 0, 9, 2.4))
    if icon == "north":
        return min(segment(x, y, -8, 9, -8, -9, 1.9),
                   segment(x, y, -8, -9, 8, 9, 1.9),
                   segment(x, y, 8, 9, 8, -9, 1.9))
    if icon == "trail":
        return min(disk(x, y, -10, 8, 2.5), disk(x, y, -1, 0, 2.5),
                   disk(x, y, 10, -8, 2.5),
                   segment(x, y, -8, 6, -3, 2, 1.2),
                   segment(x, y, 1, -2, 8, -6, 1.2))
    if icon == "route":
        return min(disk(x, y, -10, 8, 2.8),
                   segment(x, y, -8, 6, -2, 0, 1.7),
                   segment(x, y, -2, 0, 6, 0, 1.7),
                   segment(x, y, 6, 0, 6, -9, 1.7),
                   segment(x, y, 6, -9, 2, -5, 1.7),
                   segment(x, y, 6, -9, 10, -5, 1.7))
    if icon == "eye":
        return min(segment(x, y, -11, 0, -6, -4, 1.7),
                   segment(x, y, -6, -4, 0, -6, 1.7),
                   segment(x, y, 0, -6, 6, -4, 1.7),
                   segment(x, y, 6, -4, 11, 0, 1.7),
                   segment(x, y, -11, 0, -6, 4, 1.7),
                   segment(x, y, -6, 4, 0, 6, 1.7),
                   segment(x, y, 0, 6, 6, 4, 1.7),
                   segment(x, y, 6, 4, 11, 0, 1.7),
                   disk(x, y, 0, 0, 3.3))
    if icon == "player":
        skull = min(disk(x, y, 0, -3, 9), max(abs(x) - 5, abs(y - 6) - 5))
        openings = min(disk(x, y, -3, -4, 2.1), disk(x, y, 3, -4, 2.1),
                       disk(x, y, 0, 2, 1.25), disk(x, y, -2, 9, .7),
                       disk(x, y, 2, 9, .7))
        return max(skull, -openings)
    if icon == "tracker":
        return min(abs(x + 9) + abs(y + 7) - 3.3,
                   segment(x, y, -2, -7, 10, -7, 1.4),
                   segment(x, y, -10, 1, 10, 1, 1.4),
                   segment(x, y, -10, 8, 7, 8, 1.4))
    if icon == "clear":
        return min(segment(x, y, -11, -11, -4, -11, 1.6),
                   segment(x, y, -11, -11, -11, -4, 1.6),
                   segment(x, y, 11, -11, 4, -11, 1.6),
                   segment(x, y, 11, -11, 11, -4, 1.6),
                   segment(x, y, -11, 11, -4, 11, 1.6),
                   segment(x, y, -11, 11, -11, 4, 1.6),
                   segment(x, y, 11, 11, 4, 11, 1.6),
                   segment(x, y, 11, 11, 11, 4, 1.6))
    if icon == "arrow":
        return min(segment(x, y, -9, 6, 0, -10, 2),
                   segment(x, y, 0, -10, 9, 6, 2),
                   segment(x, y, 0, -7, 0, 10, 1.8))
    if icon == "minimize":
        return min(segment(x, y, -9, 9, 9, 9, 1.8),
                   segment(x, y, -7, -7, 0, 2, 2),
                   segment(x, y, 0, 2, 7, -7, 2))
    if icon == "constellation":
        return min(disk(x, y, -10, 5, 2.8), disk(x, y, 0, -9, 3),
                   disk(x, y, 10, 3, 2.8), disk(x, y, 1, 10, 2.4),
                   segment(x, y, -8, 3, -2, -7, 1.1),
                   segment(x, y, 2, -7, 8, 1, 1.1),
                   segment(x, y, 8, 5, 2, 9, 1.1))
    if icon == "minimap":
        # Minimap Underlay: a round map with a terrain ridge and a north tick.
        return min(abs(math.hypot(x, y) - 10) - 1.5,
                   segment(x, y, -7, 3, -3, -2, 1.4),
                   segment(x, y, -3, -2, 1, 2, 1.4),
                   segment(x, y, 1, 2, 6, -4, 1.4),
                   segment(x, y, 0, -15, 0, -11, 1.5))
    if icon == "rare":
        return min(*(segment(x, y, math.cos(a) * 4, math.sin(a) * 4,
                             math.cos(a) * 11, math.sin(a) * 11, 1.7)
                     for a in (0, math.pi / 3, 2 * math.pi / 3, math.pi,
                               4 * math.pi / 3, 5 * math.pi / 3)),
                   disk(x, y, 0, 0, 4))
    if icon == "treasure":
        return min(segment(x, y, -10, -3, 10, -3, 1.7),
                   segment(x, y, -10, -3, -8, 9, 1.7),
                   segment(x, y, 10, -3, 8, 9, 1.7),
                   segment(x, y, -8, 9, 8, 9, 1.7),
                   segment(x, y, -8, -8, 8, -8, 1.7),
                   segment(x, y, -8, -8, -10, -3, 1.7),
                   segment(x, y, 8, -8, 10, -3, 1.7),
                   segment(x, y, 0, -2, 0, 3, 2))
    if icon == "quest":
        return min(segment(x, y, 0, -12, 11, 0, 1.7),
                   segment(x, y, 11, 0, 0, 12, 1.7),
                   segment(x, y, 0, 12, -11, 0, 1.7),
                   segment(x, y, -11, 0, 0, -12, 1.7),
                   segment(x, y, 0, -5, 0, 2, 1.7),
                   disk(x, y, 0, 6, 1.7))
    if icon == "zygor":
        return min(segment(x, y, -10, -8, 9, -8, 1.9),
                   segment(x, y, 9, -8, -9, 8, 1.9),
                   segment(x, y, -9, 8, 10, 8, 1.9),
                   segment(x, y, 10, 8, 5, 3, 1.7))
    return min(segment(x, y, -8, -8, 8, 8, 2),
               segment(x, y, -8, 8, 8, -8, 2))


hover_fill, hover_edge, active_mark = [], [], []
for py in range(CELL):
    for px in range(CELL):
        x, y = px + 0.5 - CELL / 2, py + 0.5 - CELL / 2
        distance = disk(x, y, 0, 0, 25)
        outer = coverage(distance)
        inner = coverage(distance + 1.5)
        hover_fill.append(outer)
        hover_edge.append(max(0, outer - inner))
        active_mark.append(coverage(segment(x, y, -4, 15, 4, 15, 1.3)))


def write_atlas(icons, name):
    width = CELL * len(icons)
    glyphs = {icon: [] for icon in icons}
    for py in range(CELL):
        for px in range(CELL):
            x, y = px + 0.5 - CELL / 2, py + 0.5 - CELL / 2
            for icon in icons:
                glyphs[icon].append(coverage(icon_distance(icon, x, y)))
    pixels = bytearray(width * HEIGHT * 4)
    for state, (fill_alpha, edge_alpha, glyph_alpha, active_alpha) in enumerate(STATES):
        for column, icon in enumerate(icons):
            for index in range(CELL * CELL):
                px, py = index % CELL, index // CELL
                alpha = max(hover_fill[index] * fill_alpha,
                            hover_edge[index] * edge_alpha,
                            glyphs[icon][index] * glyph_alpha,
                            active_mark[index] * active_alpha)
                target = ((state * CELL + py) * width + column * CELL + px) * 4
                pixels[target:target + 4] = (255, 255, 255, round(255 * alpha))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0,
                         width, HEIGHT, 32, 0x28)
    destination = Path(__file__).resolve().parents[1] / "Media" / name
    destination.write_bytes(header + pixels)
    print(f"Generated {destination.name}: {len(icons)} icons, {len(STATES)} states")


write_atlas(ICONS, "radar-corner-controls.tga")
write_atlas(ROUTE_ICONS, "radar-route-types.tga")
# One cell, same four state rows, for the Minimap Underlay corner toggle.
write_atlas(("minimap",), "radar-minimap-underlay.tga")
