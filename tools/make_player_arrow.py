"""Generate Media/player-arrow.tga: a solid white arrowhead pointing up, for the
Minimap Underlay's player marker (tinted in game). 64x64, 32 bpp, top-down.

Usage: python -I tools/make_player_arrow.py <out.tga>
"""
import struct
import sys

SIZE, SS = 64, 4
# Arrowhead with a notch at the back, like Blizzard's minimap arrow.
POLY = [(32, 4), (56, 58), (32, 45), (8, 58)]


def inside(x, y):
    hit = False
    n = len(POLY)
    for i in range(n):
        x1, y1 = POLY[i]
        x2, y2 = POLY[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def main(path):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    body = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            hits = sum(inside(x + (sx + .5) / SS, y + (sy + .5) / SS) for sy in range(SS) for sx in range(SS))
            body += bytes((255, 255, 255, round(hits * 255 / (SS * SS))))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


if __name__ == "__main__":
    main(sys.argv[1])
