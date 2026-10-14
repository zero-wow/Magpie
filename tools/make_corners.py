"""Generate rounded-corner face and border TGAs for VignetteRadar's Corner Roundness setting.

For each level r (UI px, measured on the classic 182 px radar face) write:
  Media/Corners/face-<r>.tga    solid white, alpha = coverage of a rounded square
  Media/Corners/border-<r>.tga  white ring of LINE texels along the same outline
256x256, 32 bpp, uncompressed, top-down (same format as radar-rounded-square.tga).
"""
import math
import os
import struct
import sys

SIZE = 256
FACE_PX = 182.0          # classic face size the art is stretched to
LINE = 1.4               # border line width in texels (matches radar-rounded-border.tga)
SS = 4                   # supersamples per axis
LEVELS = range(0, 17, 2)


def inside(x, y, radius, inset):
    """True when (x, y) lies inside the rounded square shrunk by inset."""
    lo, hi = inset, SIZE - inset
    if x < lo or x > hi or y < lo or y > hi:
        return False
    r = max(0.0, radius - inset)
    if r <= 0:
        return True
    cx = min(max(x, lo + r), hi - r)
    cy = min(max(y, lo + r), hi - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def coverage(px, py, radius, inset):
    hits = 0
    for sy in range(SS):
        for sx in range(SS):
            if inside(px + (sx + .5) / SS, py + (sy + .5) / SS, radius, inset):
                hits += 1
    return hits / (SS * SS)


def write_tga(path, alpha_rows):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    body = bytearray()
    for row in alpha_rows:
        for a in row:
            body += bytes((255, 255, 255, a))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def build(level):
    radius = level * SIZE / FACE_PX
    face, border = [], []
    for y in range(SIZE):
        frow, brow = [], []
        for x in range(SIZE):
            outer = coverage(x, y, radius, 0)
            inner = coverage(x, y, radius, LINE)
            frow.append(round(outer * 255))
            brow.append(round(max(0.0, outer - inner) * 255))
        face.append(frow)
        border.append(brow)
    return face, border


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for level in LEVELS:
        face, border = build(level)
        write_tga(os.path.join(out_dir, "face-%d.tga" % level), face)
        write_tga(os.path.join(out_dir, "border-%d.tga" % level), border)
        print("level", level, "radius texels", round(level * SIZE / FACE_PX, 2))


if __name__ == "__main__":
    main(sys.argv[1])
