"""Generate Media/button-icons.tga: layer masks for every themed icon button.

Same family as config-icons.tga and radar-corner-controls.tga: 64px cells,
signed-distance glyphs with the 1.2 to 2.4 px stroke radii, analytic edge
coverage, white masks the addon tints. Each button stacks separate layers so
a Multi-Color theme can color them apart (UI/IconButton.lua):
  glyph      one cell per icon (rows 0-2)
  plate      the round background disk          row 3, column 0
  border     the ring at the plate's edge       row 3, column 1
  glow       a soft hover glow                  row 3, column 2
  underline  the active indicator               row 3, column 3
States (plain / hover / active / pressed / disabled) are tint and alpha now,
not baked rows. The plate, border edge and underline keep the geometry of
the old hover wash, edge and active mark from generate_config_icons.py.

Glyph N sits in row N // 16, column N % 16. The list holds this file's
button icons, then the radar corner tools ("corner_*", drawn by
generate_corner_controls.py) and the settings rail ("rail_*", drawn by
generate_config_icons.py), so all three sets share the layered look.
UI/IconButton.lua mirrors GLYPHS; keep the order in step.

Run with --preview <png> for a quick accent-tinted check (stdlib only);
tools/preview_button_icons.py renders the labeled per-theme preview.
"""

import math
import struct
import sys
import zlib
from pathlib import Path

# python -I drops the script folder from sys.path; add it back explicitly.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_config_icons import CELL, coverage, disk, ring, segment  # noqa: E402


COLUMNS = 16
GLYPH_ROWS = 3
WIDTH = CELL * COLUMNS
HEIGHT = CELL * 4
# Order matters: UI/IconButton.lua maps names to these indexes.
ICONS = ("options", "share", "undo", "refresh", "detach", "dock", "lock",
         "unlock", "close", "list", "focus", "next", "back", "minimap",
         "follow", "lead", "eye", "search", "info", "pause", "clear")
LAYERS = ("plate", "border", "glow", "underline")


def _load_sibling(name, stop):
    # Run a sibling generator's drawing code without its top-level writes:
    # everything before the first line that starts with `stop`.
    source = (Path(__file__).resolve().parent / name).read_text(encoding="utf-8")
    cut = source.find(chr(10) + stop)
    namespace = {"__name__": "button_icons_" + name}
    exec(compile(source if cut < 0 else source[:cut], name, "exec"), namespace)
    return namespace


_corner = _load_sibling("generate_corner_controls.py", "write_atlas(")
_rail = _load_sibling("generate_config_icons.py", "if __name__")
CORNER = tuple(_corner["ICONS"])
RAIL = tuple(_rail["ICONS"])
GLYPHS = ICONS + tuple("corner_" + name for name in CORNER) + tuple("rail_" + name for name in RAIL)
assert len(GLYPHS) <= COLUMNS * GLYPH_ROWS, "glyph rows are full"


def chevron(x, y, tip_x, tip_y, dir_x, dir_y, length=5.5, spread=4.5, radius=1.7):
    # Two strokes meeting at the tip, opening back along -dir.
    norm = math.hypot(dir_x, dir_y)
    dx, dy = dir_x / norm, dir_y / norm
    bx, by = tip_x - dx * length, tip_y - dy * length
    nx, ny = -dy * spread, dx * spread
    return min(segment(x, y, tip_x, tip_y, bx + nx, by + ny, radius),
               segment(x, y, tip_x, tip_y, bx - nx, by - ny, radius))


def triangle(x, y, points):
    # Filled triangle: the largest signed edge distance, either winding;
    # exact along the edges, which is all the coverage needs.
    (ax, ay), (bx, by), (cx, cy) = points
    winding = -1 if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0 else 1
    worst = -99.0
    for index in range(3):
        x1, y1 = points[index]
        x2, y2 = points[(index + 1) % 3]
        dx, dy = x2 - x1, y2 - y1
        worst = max(worst, winding * ((x - x1) * dy - (y - y1) * dx) / math.hypot(dx, dy))
    return worst


def nav_arrow(x, y, cx, cy, angle, size=1.0):
    # The player's map arrow (notched), turned by angle (0 points up).
    c, s = math.cos(angle), math.sin(angle)

    def at(px, py):
        return cx + (px * c - py * s) * size, cy + (px * s + py * c) * size
    tip, right, left = at(0, -7.5), at(5.5, 5.5), at(-5.5, 5.5)
    # The notch runs past the base so the two cuts never share an edge.
    notch, notch_right, notch_left = at(0, 1), at(9.8, 9), at(-9.8, 9)
    # One outer triangle minus the notch, so no seam runs down the middle.
    return max(triangle(x, y, (tip, right, left)), -triangle(x, y, (notch_left, notch_right, notch)))


def arc(x, y, cx, cy, radius, width, start, end):
    # Ring stroke kept only between two angles (radians, screen y down,
    # start < end); round caps at both ends.
    angle = math.atan2(y - cy, x - cx)
    while angle < start:
        angle += 2 * math.pi
    if angle <= end:
        return ring(x, y, cx, cy, radius, width)
    return min(disk(x, y, cx + math.cos(a) * radius, cy + math.sin(a) * radius, width)
               for a in (start, end))


def box(x, y, x1, y1, x2, y2, radius=1.7, skip=()):
    # Rectangle outline from strokes; skip names sides to leave open.
    sides = {"top": (x1, y1, x2, y1), "right": (x2, y1, x2, y2),
             "bottom": (x1, y2, x2, y2), "left": (x1, y1, x1, y2)}
    return min(segment(x, y, *points, radius) for side, points in sides.items()
               if side not in skip)


def padlock(x, y, open_lock):
    body = box(x, y, -8.5, 0, 8.5, 11, 1.7)
    hole = min(disk(x, y, 0, 4.6, 1.9), segment(x, y, 0, 4.6, 0, 7.6, 1.1))
    if open_lock:
        # The shackle swings up and free on the right.
        shackle = min(arc(x, y, 0, -8, 5.5, 1.7, math.pi, 2 * math.pi),
                      segment(x, y, -5.5, -8, -5.5, 0, 1.7),
                      segment(x, y, 5.5, -8, 5.5, -6.5, 1.7))
    else:
        shackle = min(arc(x, y, 0, -4, 5.5, 1.7, math.pi, 2 * math.pi),
                      segment(x, y, -5.5, -4, -5.5, 0, 1.7),
                      segment(x, y, 5.5, -4, 5.5, 0, 1.7))
    return min(body, hole, shackle)


def icon_distance(icon, x, y):
    if icon == "options":
        # Three sliders: a track each, with a hollow knob cut into it.
        parts = []
        for row, knob in ((-8, -4), (0, 5), (8, -1)):
            track = max(segment(x, y, -11, row, 11, row, 1.3), -disk(x, y, knob, row, 4.3))
            parts.append(min(track, ring(x, y, knob, row, 3, 1.3)))
        return min(parts)
    if icon == "share":
        # Three linked nodes.
        return min(disk(x, y, 7.5, -8, 3), disk(x, y, -7.5, 0, 3), disk(x, y, 7.5, 8, 3),
                   segment(x, y, -7.5, 0, 7.5, -8, 1.3),
                   segment(x, y, -7.5, 0, 7.5, 8, 1.3))
    if icon == "undo":
        # Back-pointing arrow that loops round and returns underneath.
        return min(segment(x, y, -9, -4, 2, -4, 1.7),
                   arc(x, y, 2, 2, 6, 1.7, -math.pi / 2, math.pi / 2),
                   segment(x, y, 2, 8, -5, 8, 1.7),
                   chevron(x, y, -10, -4, -1, 0))
    if icon == "refresh":
        # A ring open at the top right, with the arrowhead at the top.
        start, end = -math.pi / 9, 3 * math.pi / 2
        return min(arc(x, y, 0, 1, 8.5, 1.7, start, end),
                   chevron(x, y, 3, -7.5, 1, 0, 5.5, 4.6))
    if icon == "detach":
        # A panel with its corner open and an arrow leaving it.
        return min(box(x, y, -10, -6, 6, 10, 1.7, ("top", "right")),
                   segment(x, y, -10, -6, -3, -6, 1.7),
                   segment(x, y, 6, 3, 6, 10, 1.7),
                   segment(x, y, -2, 2, 10, -10, 1.7),
                   chevron(x, y, 10.5, -10.5, 1, -1, 6.5, 4.6))
    if icon == "dock":
        # The same panel with an arrow coming home into its corner.
        return min(box(x, y, -10, -6, 6, 10, 1.7, ("top", "right")),
                   segment(x, y, -10, -6, -3, -6, 1.7),
                   segment(x, y, 6, 3, 6, 10, 1.7),
                   segment(x, y, 11, -11, 0, 0, 1.7),
                   chevron(x, y, -1, 1, -1, 1, 6.5, 4.6))
    if icon == "lock":
        return padlock(x, y, False)
    if icon == "unlock":
        return padlock(x, y, True)
    if icon == "close":
        return min(segment(x, y, -8, -8, 8, 8, 2),
                   segment(x, y, -8, 8, 8, -8, 2))
    if icon == "list":
        # Rows with a scroll thumb on the right.
        return min(segment(x, y, -11, -8, 4, -8, 1.4),
                   segment(x, y, -11, 0, 4, 0, 1.4),
                   segment(x, y, -11, 8, 4, 8, 1.4),
                   segment(x, y, 10, -10, 10, 10, 0.8),
                   segment(x, y, 10, -9, 10, -1, 2))
    if icon == "focus":
        # Viewfinder brackets round a dot.
        corners = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                corners.append(segment(x, y, 10 * sx, 10 * sy, 4.5 * sx, 10 * sy, 1.7))
                corners.append(segment(x, y, 10 * sx, 10 * sy, 10 * sx, 4.5 * sy, 1.7))
        return min(min(corners), disk(x, y, 0, 0, 3))
    if icon == "next":
        # Skip forward: a play triangle and a bar.
        return min(segment(x, y, -8, -9, 4, 0, 1.7), segment(x, y, 4, 0, -8, 9, 1.7),
                   segment(x, y, -8, 9, -8, -9, 1.7), segment(x, y, 9, -9, 9, 9, 2))
    if icon == "back":
        return min(segment(x, y, 8, -9, -4, 0, 1.7), segment(x, y, -4, 0, 8, 9, 1.7),
                   segment(x, y, 8, 9, 8, -9, 1.7), segment(x, y, -9, -9, -9, 9, 2))
    if icon == "minimap":
        # A round map with the player arrow and a north tick.
        return min(ring(x, y, 0, 1, 10, 1.6),
                   chevron(x, y, 0, -2.5, 0, -1, 6, 4.4, 1.6),
                   segment(x, y, 0, -12.5, 0, -10, 1.6))
    if icon == "follow":
        # The player chevron with the trail ahead of it.
        return min(nav_arrow(x, y, -6, 6, math.pi / 4, 1.3),
                   disk(x, y, 4, -4, 1.9), disk(x, y, 7.8, -7.8, 1.9), disk(x, y, 11.6, -11.6, 1.9))
    if icon == "lead":
        # A trail behind, a flag where it leads.
        return min(disk(x, y, -11, 10, 2.1), disk(x, y, -6.5, 5.5, 2.1), disk(x, y, -2, 1, 2.1),
                   segment(x, y, 4, 9, 4, -11, 1.6),
                   segment(x, y, 4, -11, 11, -7.5, 1.6),
                   segment(x, y, 11, -7.5, 4, -4, 1.6))
    if icon == "eye":
        # The corner atlas eye.
        return min(segment(x, y, -11, 0, -6, -4, 1.7), segment(x, y, -6, -4, 0, -6, 1.7),
                   segment(x, y, 0, -6, 6, -4, 1.7), segment(x, y, 6, -4, 11, 0, 1.7),
                   segment(x, y, -11, 0, -6, 4, 1.7), segment(x, y, -6, 4, 0, 6, 1.7),
                   segment(x, y, 0, 6, 6, 4, 1.7), segment(x, y, 6, 4, 11, 0, 1.7),
                   disk(x, y, 0, 0, 3.3))
    if icon == "search":
        # The settings window's search glass.
        return min(ring(x, y, -2.5, -2.5, 7, 1.7), segment(x, y, 2.6, 2.6, 10, 10, 2.2))
    if icon == "info":
        return min(ring(x, y, 0, 0, 10.5, 1.6), disk(x, y, 0, -5, 2),
                   segment(x, y, 0, -0.5, 0, 6, 1.8))
    if icon == "pause":
        return min(segment(x, y, -4.5, -8, -4.5, 8, 2.3), segment(x, y, 4.5, -8, 4.5, 8, 2.3))
    if icon == "clear":
        # A bin: lid, handle, tapered body and two ribs.
        return min(segment(x, y, -10, -7, 10, -7, 1.6), segment(x, y, -3, -10.5, 3, -10.5, 1.5),
                   segment(x, y, -7, -7, -6, 10, 1.6), segment(x, y, 7, -7, 6, 10, 1.6),
                   segment(x, y, -6, 10, 6, 10, 1.6),
                   segment(x, y, -2.3, -3, -2.1, 6, 1.1), segment(x, y, 2.3, -3, 2.1, 6, 1.1))
    raise ValueError(icon)


def glyph_distance(name, x, y):
    if name.startswith("corner_"):
        return _corner["icon_distance"](name[7:], x, y)
    if name.startswith("rail_"):
        return _rail["icon_distance"](name[5:], x, y)
    return icon_distance(name, x, y)


def layer_alpha(layer, x, y):
    radius = math.hypot(x, y)
    if layer == "plate":
        return coverage(disk(x, y, 0, 0, 25))
    if layer == "border":
        return max(0.0, coverage(disk(x, y, 0, 0, 25)) - coverage(disk(x, y, 0, 0, 23.5)))
    if layer == "glow":
        # Soft falloff that fades out just past the plate.
        return max(0.0, 1 - (radius / 28) ** 2) ** 1.6
    return coverage(segment(x, y, -4, 15, 4, 15, 1.3))


def build_pixels():
    pixels = bytearray(WIDTH * HEIGHT * 4)

    def put(row, column, alpha_at):
        for py in range(CELL):
            for px in range(CELL):
                x, y = px + 0.5 - CELL / 2, py + 0.5 - CELL / 2
                target = ((row * CELL + py) * WIDTH + column * CELL + px) * 4
                pixels[target:target + 4] = (255, 255, 255, round(255 * alpha_at(x, y)))

    for index, name in enumerate(GLYPHS):
        row, column = divmod(index, COLUMNS)
        put(row, column, lambda x, y, name=name: coverage(glyph_distance(name, x, y)))
    for column, layer in enumerate(LAYERS):
        put(GLYPH_ROWS, column, lambda x, y, layer=layer: layer_alpha(layer, x, y))
    return pixels


def write_tga(pixels, destination):
    # 32-bit BGRA, top-left origin; white art, so BGR order does not matter.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, WIDTH, HEIGHT, 32, 0x28)
    destination.write_bytes(header + pixels)


def write_png(width, height, rgb, destination):
    rows = b"".join(b"\x00" + bytes(rgb[y * width * 3:(y + 1) * width * 3]) for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    destination.write_bytes(png)


def write_preview(pixels, destination):
    # Quick check: every glyph over the plate and border masks, accent tinted
    # on Catppuccin Macchiato. The labeled per-theme preview is
    # tools/preview_button_icons.py.
    base, plate, edge, glyph = (36, 39, 58), (73, 77, 100), (183, 189, 248), (198, 160, 246)
    pad = 16
    width, height = pad * 2 + COLUMNS * CELL, pad * 2 + GLYPH_ROWS * CELL
    rgb = bytearray(base * (width * height))

    def alpha(row, column, px, py):
        return pixels[((row * CELL + py) * WIDTH + column * CELL + px) * 4 + 3] / 255

    for index in range(len(GLYPHS)):
        row, column = divmod(index, COLUMNS)
        for py in range(CELL):
            for px in range(CELL):
                color = list(base)
                for tint, amount in ((plate, alpha(GLYPH_ROWS, 0, px, py) * .6),
                                     (edge, alpha(GLYPH_ROWS, 1, px, py) * .7),
                                     (glyph, alpha(row, column, px, py))):
                    color = [c * (1 - amount) + t * amount for c, t in zip(color, tint)]
                target = ((pad + row * CELL + py) * width + pad + column * CELL + px) * 3
                rgb[target:target + 3] = bytes(round(c) for c in color)
    write_png(width, height, rgb, destination)


def main():
    pixels = build_pixels()
    destination = Path(__file__).resolve().parents[1] / "Media" / "button-icons.tga"
    write_tga(pixels, destination)
    print(f"Generated {destination.name}: {len(GLYPHS)} glyphs, {len(LAYERS)} layers, {WIDTH}x{HEIGHT}")
    if "--preview" in sys.argv:
        preview = Path(sys.argv[sys.argv.index("--preview") + 1])
        preview.parent.mkdir(parents=True, exist_ok=True)
        write_preview(pixels, preview)
        print(f"Preview: {preview}")


if __name__ == "__main__":
    main()
