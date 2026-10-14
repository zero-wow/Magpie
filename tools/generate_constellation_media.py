"""Generate deterministic, theme-tinted art for the Constellation HUD.

All generated pixels are white with alpha, so Lua can apply the existing
category/theme colour without needing one texture per colour.  The category
atlas uses nine 64px columns in a 1024px texture and four 64px state rows:

    normal, hover, selected, selected-hover

See GLYPHS and STATES below for the stable texture-coordinate contract.
"""

import argparse
import hashlib
import math
import struct
import sys
from pathlib import Path


MEDIA = Path(__file__).resolve().parents[1] / "Media"
CELL = 64
GLYPHS = (
    "rare_skull",
    "boss_skull",
    "treasure",
    "quest_available",
    "quest_objective",
    "cave",
    "event",
    "neutral_pin",
    "orbit",
)
STATES = ("normal", "hover", "selected", "selected_hover")
ATLAS_WIDTH = 1024
ATLAS_HEIGHT = CELL * len(STATES)


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def coverage(distance):
    """One-pixel anti-aliased coverage for a signed-distance shape."""
    return clamp(0.5 - distance)


def disk(x, y, cx, cy, radius):
    return math.hypot(x - cx, y - cy) - radius


def segment(x, y, x1, y1, x2, y2, radius=1.7):
    dx, dy = x2 - x1, y2 - y1
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return disk(x, y, x1, y1, radius)
    t = clamp(((x - x1) * dx + (y - y1) * dy) / length_squared)
    return math.hypot(x - x1 - t * dx, y - y1 - t * dy) - radius


def stroke(x, y, x1, y1, x2, y2, radius=1.7):
    return coverage(segment(x, y, x1, y1, x2, y2, radius))


def ring(x, y, cx, cy, radius, width=1.7):
    return coverage(abs(math.hypot(x - cx, y - cy) - radius) - width)


def ellipse_ring(x, y, cx, cy, radius_x, radius_y, width=1.25):
    distance = abs(math.hypot((x - cx) / radius_x, (y - cy) / radius_y) - 1.0)
    return coverage(distance * min(radius_x, radius_y) - width)


def polygon_strokes(x, y, points, radius=1.6, closed=True):
    result = 0.0
    count = len(points)
    last = count if closed else count - 1
    for index in range(last):
        x1, y1 = points[index]
        x2, y2 = points[(index + 1) % count]
        result = max(result, stroke(x, y, x1, y1, x2, y2, radius))
    return result


def skull(x, y, boss=False):
    # A line-art cranium remains legible when theme-tinted at 18--24 UI units.
    value = ring(x, y, 0, -4, 12.0, 1.75)
    value = max(value,
                stroke(x, y, -8, 3, -7, 11, 1.65),
                stroke(x, y, 8, 3, 7, 11, 1.65),
                stroke(x, y, -7, 11, 7, 11, 1.65),
                stroke(x, y, -5, 11, -4, 15, 1.45),
                stroke(x, y, 0, 11, 0, 15, 1.45),
                stroke(x, y, 5, 11, 4, 15, 1.45),
                polygon_strokes(x, y, ((-7, -6), (-3, -10), (-1, -5), (-5, -3)), 1.15),
                polygon_strokes(x, y, ((7, -6), (3, -10), (1, -5), (5, -3)), 1.15),
                polygon_strokes(x, y, ((0, -3), (-2, 1), (0, 3), (2, 1)), 1.0))
    if boss:
        # A crown/crest makes the boss treatment distinct without changing the
        # skull's category meaning at tiny sizes.
        value = max(value,
                    polygon_strokes(x, y, ((-11, -12), (-7, -19), (-3, -14),
                                           (0, -21), (3, -14), (7, -19),
                                           (11, -12)), 1.55, False),
                    stroke(x, y, -11, -12, 11, -12, 1.55))
    return value


def treasure(x, y):
    # Chest outline with a central crystal/latch: recognisable both as loot and
    # as a crystalline point when viewed at HUD scale.
    chest = max(
        polygon_strokes(x, y, ((-13, -1), (-9, -9), (9, -9), (13, -1)), 1.7, False),
        polygon_strokes(x, y, ((-13, -1), (-13, 10), (13, 10), (13, -1)), 1.7),
        stroke(x, y, -13, 1, 13, 1, 1.35),
    )
    crystal = polygon_strokes(x, y, ((0, -16), (5, -10), (0, -4), (-5, -10)), 1.35)
    latch = polygon_strokes(x, y, ((-2.5, 2), (2.5, 2), (2.5, 6), (-2.5, 6)), 1.05)
    return max(chest, crystal, latch)


def quest_available(x, y):
    return max(stroke(x, y, -6, -11, -2, -15, 2.0),
               stroke(x, y, -2, -15, 5, -15, 2.0),
               stroke(x, y, 5, -15, 8, -10, 2.0),
               stroke(x, y, 8, -10, 4, -3, 2.0),
               stroke(x, y, 4, -3, 0, 1, 2.0),
               stroke(x, y, 0, 1, 0, 5, 1.8),
               coverage(disk(x, y, 0, 13, 2.7)))


def quest_objective(x, y):
    return max(polygon_strokes(x, y, ((0, -15), (14, 0), (0, 15), (-14, 0)), 2.0),
               polygon_strokes(x, y, ((0, -7), (7, 0), (0, 7), (-7, 0)), 1.25))


def cave(x, y):
    return max(stroke(x, y, -15, 14, -15, 0, 2.0),
               stroke(x, y, -15, 0, -8, -11, 2.0),
               stroke(x, y, -8, -11, 0, -15, 2.0),
               stroke(x, y, 0, -15, 8, -11, 2.0),
               stroke(x, y, 8, -11, 15, 0, 2.0),
               stroke(x, y, 15, 0, 15, 14, 2.0),
               stroke(x, y, -15, 14, -5, 14, 2.0),
               stroke(x, y, 5, 14, 15, 14, 2.0),
               stroke(x, y, -5, 14, -5, 5, 1.55),
               stroke(x, y, -5, 5, 5, 5, 1.55),
               stroke(x, y, 5, 5, 5, 14, 1.55))


def event(x, y):
    points = []
    for index in range(10):
        angle = -math.pi / 2 + index * math.pi / 5
        radius = 15 if index % 2 == 0 else 6.7
        points.append((math.cos(angle) * radius, math.sin(angle) * radius))
    return max(polygon_strokes(x, y, points, 1.75), coverage(disk(x, y, 0, 0, 2.1)))


def neutral_pin(x, y):
    outline = max(ring(x, y, 0, -5, 10.5, 1.85),
                  stroke(x, y, -9, -1, 0, 16, 1.85),
                  stroke(x, y, 9, -1, 0, 16, 1.85))
    return max(outline, ring(x, y, 0, -5, 3.0, 1.05))


def orbit(x, y):
    # Toolbar glyph: a small sphere and two inclined orbital paths.
    return max(ring(x, y, 0, 0, 11, 1.65),
               ellipse_ring(x, y, 0, 0, 17, 6.3, 1.35),
               ellipse_ring(x * 0.86 + y * 0.5, -x * 0.5 + y * 0.86,
                            0, 0, 16, 5.4, 1.15),
               coverage(disk(x, y, 13, -6, 2.15)))


GLYPH_DRAWERS = {
    "rare_skull": skull,
    "boss_skull": lambda x, y: skull(x, y, boss=True),
    "treasure": treasure,
    "quest_available": quest_available,
    "quest_objective": quest_objective,
    "cave": cave,
    "event": event,
    "neutral_pin": neutral_pin,
    "orbit": orbit,
}


def state_treatment(x, y, state):
    radial = disk(x, y, 0, 0, 24)
    if state == "normal":
        return 0.0, 0.80
    if state == "hover":
        return coverage(radial) * 0.14, 1.0
    if state == "selected":
        return max(ring(x, y, 0, 0, 22, 0.85) * 0.58,
                   coverage(disk(x, y, 0, 0, 2.2)) * 0.44), 1.0
    return max(coverage(radial) * 0.18,
               ring(x, y, 0, 0, 22, 0.95) * 0.78,
               coverage(disk(x, y, 0, 0, 2.2)) * 0.58), 1.0


def encode_tga(width, height, alpha_at):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0,
                         width, height, 32, 0x28)
    pixels = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            alpha = round(255 * clamp(alpha_at(x + 0.5, y + 0.5)))
            target = (y * width + x) * 4
            pixels[target:target + 4] = (255, 255, 255, alpha)
    return header + pixels


def atlas_bytes():
    def alpha_at(x, y):
        column, row = int(x) // CELL, int(y) // CELL
        if column >= len(GLYPHS):
            return 0.0
        local_x = x - column * CELL - CELL / 2
        local_y = y - row * CELL - CELL / 2
        wash, glyph_scale = state_treatment(local_x, local_y, STATES[row])
        glyph = GLYPH_DRAWERS[GLYPHS[column]](local_x, local_y) * glyph_scale
        return max(wash, glyph)

    return encode_tga(ATLAS_WIDTH, ATLAS_HEIGHT, alpha_at)


def base_ring_bytes():
    width, height = 64, 32

    def alpha_at(x, y):
        # The narrow ellipse is the mapped point's exact ground anchor.
        return max(ellipse_ring(x, y, 32, 16, 13.5, 5.0, 1.25),
                   coverage(disk(x, y, 32, 16, 1.7)) * 0.72)

    return encode_tga(width, height, alpha_at)


def selected_halo_bytes():
    width = height = 64

    def alpha_at(x, y):
        # Two horizontal rings brighten the mapped base without implying height.
        outer = ellipse_ring(x, y, 32, 32, 23, 9, 1.15) * 0.70
        inner = ellipse_ring(x, y, 32, 32, 15, 5.5, 0.9) * 0.48
        glow = coverage(disk(x, y, 32, 32, 17)) * 0.06
        return max(outer, inner, glow)

    return encode_tga(width, height, alpha_at)


def trail_bytes():
    width, height = 64, 16

    def alpha_at(x, y):
        # One soft ant per repeat. WoW scrolls this texture on each route line.
        return coverage(disk(x, y, 17, 8, 8.5))

    return encode_tga(width, height, alpha_at)


ASSETS = {
    "constellation-glyphs.tga": (ATLAS_WIDTH, ATLAS_HEIGHT, atlas_bytes),
    "constellation-base-ring.tga": (64, 32, base_ring_bytes),
    "constellation-selected-halo.tga": (64, 64, selected_halo_bytes),
    "constellation-trail.tga": (64, 16, trail_bytes),
}


def validate_tga(name, expected_width, expected_height, data):
    expected_length = 18 + expected_width * expected_height * 4
    if len(data) != expected_length:
        raise ValueError(f"{name}: expected {expected_length} bytes, got {len(data)}")
    header = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if header[2] != 2 or header[8:11] != (expected_width, expected_height, 32):
        raise ValueError(f"{name}: not an uncompressed 32-bit {expected_width}x{expected_height} TGA")
    if header[11] != 0x28:
        raise ValueError(f"{name}: expected top-origin alpha TGA descriptor")
    pixels = data[18:]
    alpha = pixels[3::4]
    if any(channel != 255 for channel in pixels[0::4] + pixels[1::4] + pixels[2::4]):
        raise ValueError(f"{name}: RGB pixels must remain white for theme tinting")
    if not any(value == 0 for value in alpha) or not any(value > 0 for value in alpha):
        raise ValueError(f"{name}: needs both transparent gutter and visible artwork")
    if name == "constellation-glyphs.tga":
        # Every state/slot must have visible content and the corner gutter must
        # be transparent, preventing atlas bleed when WoW filters it.
        if alpha[0] != 0:
            raise ValueError(f"{name}: atlas corner gutter is not transparent")
        for row in range(len(STATES)):
            for column in range(len(GLYPHS)):
                visible = False
                for py in range(CELL):
                    start = ((row * CELL + py) * expected_width + column * CELL) * 4 + 3
                    if any(pixels[start:start + CELL * 4:4]):
                        visible = True
                        break
                if not visible:
                    raise ValueError(f"{name}: empty {STATES[row]}/{GLYPHS[column]} slot")


def build_assets():
    built = {}
    for name, (width, height, render) in ASSETS.items():
        data = render()
        validate_tga(name, width, height, data)
        built[name] = data
    return built


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true",
                        help="validate that checked-in media exactly matches this generator")
    args = parser.parse_args()
    built = build_assets()
    mismatches = []
    for name, data in built.items():
        destination = MEDIA / name
        if args.verify:
            if not destination.is_file() or destination.read_bytes() != data:
                mismatches.append(name)
            continue
        destination.write_bytes(data)
        digest = hashlib.sha256(data).hexdigest()[:12]
        print(f"generated {name}: {len(data)} bytes, sha256 {digest}")
    if mismatches:
        print("out-of-date or missing: " + ", ".join(mismatches), file=sys.stderr)
        return 1
    if args.verify:
        print("verified deterministic constellation media: " + ", ".join(built))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
