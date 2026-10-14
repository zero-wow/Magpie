"""Generate blank.tga: a fully transparent 32x32 texture.

The Minimap Underlay hands it to Minimap:SetBlipTexture and SetPlayerTexture
while "Duplicate Icons" is set to Radar Wins, so only the terrain shows.
"""

from pathlib import Path
import struct


MEDIA = Path(__file__).resolve().parents[1] / "Media"
SIZE = 32


def main():
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    pixels = bytes((0, 0, 0, 0)) * (SIZE * SIZE)
    (MEDIA / "blank.tga").write_bytes(header + pixels)


if __name__ == "__main__":
    main()
