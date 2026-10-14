"""Generate the settings window's page icons in the corner-control style.

Media/config-icons.tga uses the same 64px cells and the same four state rows
as radar-corner-controls.tga (plain, hover, active, active + hover): the
circular hover wash and edge plus the short active underline are lifted from
that generator, and every glyph keeps its 1.2 to 2.4 px stroke radii, so the
settings rail reads as part of the radar's own control family.

The atlas is 1024 x 256 (16 columns, power of two); unused columns stay clear.
Run with --preview <png> to also write an enlarged, accent-tinted preview.
"""

import math
import struct
import sys
from pathlib import Path


CELL = 64
COLUMNS = 16
HEIGHT = 256
# Order matters: UI/QuickConfig.lua maps page ids to these columns.
ICONS = ("radar", "looks", "alerts", "markers", "quests", "routes",
         "hud", "data", "tools", "search")
STATES = (
    # Circular hover wash, edge, icon, active underline (same as the corner atlas).
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


def ring(x, y, cx, cy, radius, width):
    return abs(math.hypot(x - cx, y - cy) - radius) - width


def ellipse_ring(x, y, cx, cy, a, b, width):
    # Approximate distance to an ellipse outline; good enough at icon scale.
    # f / |grad f| keeps the stroke even along the whole outline.
    nx, ny = (x - cx) / a, (y - cy) / b
    length = math.hypot(nx, ny)
    if length < 1e-6:
        return min(a, b) - width
    gradient = math.hypot(nx / a, ny / b) / length
    return abs(length - 1) / gradient - width


def icon_distance(icon, x, y):
    if icon == "radar":
        # A range ring, the player dot, a sweep line and one blip.
        return min(ring(x, y, 0, 0, 10.5, 1.7), disk(x, y, 0, 0, 2.4),
                   segment(x, y, 0, 0, 6.6, -6.6, 1.4), disk(x, y, -4.5, 4, 1.9))
    if icon == "looks":
        # Contrast disc: outline with the left half filled (theme and colors).
        return min(ring(x, y, 0, 0, 10, 1.7), max(disk(x, y, 0, 0, 10), x))
    if icon == "alerts":
        # Bell: dome, flared sides, rim and clapper.
        dome = max(ring(x, y, 0, -1, 7, 1.7), y + 1)
        return min(dome,
                   segment(x, y, -7, -1, -9, 6, 1.7),
                   segment(x, y, 7, -1, 9, 6, 1.7),
                   segment(x, y, -10.5, 6, 10.5, 6, 1.7),
                   disk(x, y, 0, 10.5, 2.2), disk(x, y, 0, -9.5, 1.6))
    if icon == "markers":
        # Map pin: ring head that narrows to a point, with a center dot.
        head = ring(x, y, 0, -3, 7.5, 1.7)
        if y > 1.5 and abs(x) < 5.5:
            head = 99  # open the ring where the two sides run down to the tip
        return min(head,
                   segment(x, y, -6.6, 0.6, 0, 11, 1.7),
                   segment(x, y, 6.6, 0.6, 0, 11, 1.7),
                   disk(x, y, 0, -3, 2.4))
    if icon == "quests":
        # The quest diamond with its mark (matches radar-route-types quest).
        return min(segment(x, y, 0, -12, 11, 0, 1.7),
                   segment(x, y, 11, 0, 0, 12, 1.7),
                   segment(x, y, 0, 12, -11, 0, 1.7),
                   segment(x, y, -11, 0, 0, -12, 1.7),
                   segment(x, y, 0, -5, 0, 2, 1.7),
                   disk(x, y, 0, 6, 1.7))
    if icon == "routes":
        # Start dot, a bent path and an arrowhead (matches the route tool).
        return min(disk(x, y, -10, 8, 2.8),
                   segment(x, y, -8, 6, -2, 0, 1.7),
                   segment(x, y, -2, 0, 6, 0, 1.7),
                   segment(x, y, 6, 0, 6, -9, 1.7),
                   segment(x, y, 6, -9, 2, -5, 1.7),
                   segment(x, y, 6, -9, 10, -5, 1.7))
    if icon == "hud":
        # Sphere: outline and a tilted orbit (the constellation globe).
        orbit = ellipse_ring(x, y, 0, 0, 12, 3.4, 1.2)
        if y < 0 and math.hypot(x, y) < 10.5:
            orbit = 99  # the back of the orbit passes behind the sphere
        return min(ring(x, y, 0, 0, 9, 1.7), orbit, disk(x, y, 8, -7.5, 1.8))
    if icon == "data":
        # Stacked discs: a full top lid and two lower rims.
        top = ellipse_ring(x, y, 0, -7, 9.5, 3, 1.2)
        middle = max(ellipse_ring(x, y, 0, 0.5, 9.5, 3, 1.2), -(y - 0.5))
        bottom = max(ellipse_ring(x, y, 0, 8, 9.5, 3, 1.2), -(y - 8))
        return min(top, middle, bottom,
                   segment(x, y, -9.5, -7, -9.5, 8, 1.2),
                   segment(x, y, 9.5, -7, 9.5, 8, 1.2))
    if icon == "tools":
        # Wrench: a handle and an open ring jaw.
        jaw = max(ring(x, y, 4.5, -4.5, 5.6, 1.8), -disk(x, y, 9.5, -9.5, 4.2))
        return min(jaw, segment(x, y, -9.5, 9.5, 0.6, -0.6, 2.2))
    if icon == "search":
        return min(ring(x, y, -2.5, -2.5, 7, 1.7),
                   segment(x, y, 2.6, 2.6, 10, 10, 2.2))
    raise ValueError(icon)


def build_pixels():
    width = CELL * COLUMNS
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
    glyphs = {icon: [] for icon in ICONS}
    for py in range(CELL):
        for px in range(CELL):
            x, y = px + 0.5 - CELL / 2, py + 0.5 - CELL / 2
            for icon in ICONS:
                glyphs[icon].append(coverage(icon_distance(icon, x, y)))
    pixels = bytearray(width * HEIGHT * 4)
    for state, (fill_alpha, edge_alpha, glyph_alpha, active_alpha) in enumerate(STATES):
        for column, icon in enumerate(ICONS):
            for index in range(CELL * CELL):
                px, py = index % CELL, index // CELL
                alpha = max(hover_fill[index] * fill_alpha,
                            hover_edge[index] * edge_alpha,
                            glyphs[icon][index] * glyph_alpha,
                            active_mark[index] * active_alpha)
                target = ((state * CELL + py) * width + column * CELL + px) * 4
                pixels[target:target + 4] = (255, 255, 255, round(255 * alpha))
    return width, pixels


def write_tga(width, pixels, destination):
    # 32-bit BGRA, top-left origin; white art, so BGR order does not matter.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0,
                         width, HEIGHT, 32, 0x28)
    destination.write_bytes(header + pixels)


def write_preview(width, pixels, destination):
    from PIL import Image

    atlas = Image.frombytes("RGBA", (width, HEIGHT), bytes(pixels))
    used = atlas.crop((0, 0, CELL * len(ICONS), HEIGHT))
    accent = (13, 209, 158)
    face = (16, 22, 26)
    scale = 2
    # Below the new icons, the existing corner controls for a stroke comparison.
    corner_path = Path(__file__).resolve().parents[1] / "Media" / "radar-corner-controls.tga"
    corner = Image.open(corner_path).convert("RGBA").crop((0, 0, used.width, HEIGHT))
    size = (used.width * scale, used.height * scale)
    out = Image.new("RGB", (size[0] + 32, size[1] * 2 + 48), face)
    for index, source in enumerate((used, corner)):
        tint = Image.new("RGBA", source.size, accent + (255,))
        tint.putalpha(source.getchannel("A"))
        tint = tint.resize(size, Image.LANCZOS)
        out.paste(tint, (16, 16 + index * (size[1] + 16)), tint)
    out.save(destination)


def main():
    width, pixels = build_pixels()
    destination = Path(__file__).resolve().parents[1] / "Media" / "config-icons.tga"
    write_tga(width, pixels, destination)
    print(f"Generated {destination.name}: {len(ICONS)} icons, {len(STATES)} states")
    if "--preview" in sys.argv:
        preview = Path(sys.argv[sys.argv.index("--preview") + 1])
        write_preview(width, pixels, preview)
        print(f"Preview: {preview}")


if __name__ == "__main__":
    main()
