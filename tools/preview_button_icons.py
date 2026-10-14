"""Labeled per-theme preview of the layered icon buttons (needs Pillow).

Reads Media/button-icons.tga and the palettes and icon maps in
Core/Themes.lua, resolves the five icon roles the way UI/Style.lua does
(family map, heading fallback when a layer would be hard to see) and draws
every state with UI/IconButton.lua's alphas.

    <venv with Pillow>/python -I tools/preview_button_icons.py <out.png>
"""

import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CELL, COLUMNS, GLYPH_ROWS = 64, 16, 3
THEMES = ("dracula", "catppuccin_macchiato", "tokyonight_night", "gruvbox_dark", "verdant")
SAMPLE = ("options", "share", "undo", "refresh", "detach", "lock", "close", "list", "focus",
          "next", "minimap", "follow", "lead", "eye", "search", "info", "pause", "clear",
          "corner_north", "corner_route", "rail_looks", "rail_alerts")
STATES = ("idle", "hover", "active", "pressed", "disabled")
# Same alphas as UI/IconButton.lua: plate, border, glow.
QUIET = {"idle": (0, 0, 0), "hover": (0, .26, .20), "active": (0, 0, 0), "pressed": (0, .26, .32)}
FRAMED = {"idle": (.22, .55, 0), "hover": (.32, .95, .24), "active": (.28, .80, 0), "pressed": (.32, .95, .36)}
FLOOR = {"glyph": 3, "border": 1.8, "hover": 1.8, "active": 2.2}
VERDANT = {"accent": "0DD19E", "rings": "0DD19E", "heading": "0DD19E", "background": "040607"}
PAGE, TEXT, SOFT = (36, 39, 58), (202, 211, 245), (147, 154, 183)


def glyph_names():
    source = (ROOT / "tools" / "generate_button_icons.py").read_text(encoding="utf-8")
    icons = re.findall(r'"(\w+)"', re.search(r"\nICONS = \((.*?)\)", source, re.S).group(1))
    corner = re.findall(r'"(\w+)"', re.search(r"\nICONS = \((.*?)\)",
                        (ROOT / "tools" / "generate_corner_controls.py").read_text(encoding="utf-8"), re.S).group(1))
    rail = re.findall(r'"(\w+)"', re.search(r"\nICONS = \((.*?)\)",
                      (ROOT / "tools" / "generate_config_icons.py").read_text(encoding="utf-8"), re.S).group(1))
    return icons + ["corner_" + n for n in corner] + ["rail_" + n for n in rail]


def palettes():
    text = (ROOT / "Core" / "Themes.lua").read_text(encoding="utf-8")
    themes, family = {}, None
    for line in text.splitlines():
        found = re.search(r'\{ id = "(\w+)", name = "([^"]+)"', line)
        if found:
            family = found.group(1)
        found = re.search(r'key = "(\w+)", name = "([^"]+)"', line)
        if found:
            current = {"family": family, "name": found.group(2)}
            themes[found.group(1)] = current
        for role, hex_value in re.findall(r'(\w+) = "([0-9a-fA-F]{6})"', line):
            if found or role in ("background", "rings", "accent", "heading", "rare", "boss", "treasure",
                                 "event", "other", "quest"):
                current[role] = hex_value
    maps = {}
    for fam, body in re.findall(r"\n    (\w+) = \{ (glyph = [^}]*)\}", text):
        maps[fam] = dict(re.findall(r'(\w+) = "(\w+)"', body))
    return themes, maps


def rgb(hex_value):
    return tuple(int(hex_value[i:i + 2], 16) for i in (0, 2, 4))


def luminance(color):
    def linear(c):
        c /= 255
        return c / 12.92 if c <= .03928 else ((c + .055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in color)
    return .2126 * r + .7152 * g + .0722 * b


def contrast(a, b):
    x, y = sorted((luminance(a), luminance(b)), reverse=True)
    return (x + .05) / (y + .05)


def resolve(theme, maps):
    if theme == "verdant":
        palette, icon_map, framed, title = VERDANT, {"glyph": "accent", "border": "rings",
                                                     "plate": "background", "hover": "accent",
                                                     "active": "accent"}, False, "Verdant (Single Color)"
    else:
        themes, _ = palettes()
        palette = themes[theme]
        icon_map, framed = maps[palette["family"]], True
        title = palette["family"].replace("tokyonight", "Tokyo Night").title() + " " + palette["name"]
        family_name = title[:-len(palette["name"]) - 1]
        if family_name.lower() == palette["name"].lower():
            title = palette["name"]
    background = rgb(palette["background"])
    roles = {}
    for layer in ("glyph", "border", "plate", "hover", "active"):
        color = rgb(palette[icon_map[layer]])
        if layer in FLOOR and contrast(color, background) < FLOOR[layer]:
            color = rgb(palette["heading"])
        roles[layer] = color
    return title, background, roles, framed, rgb(palette.get("rings", "6E738D"))


def tinted(mask, color, alpha):
    layer = Image.new("RGBA", mask.size, color + (0,))
    layer.putalpha(mask.point(lambda value: round(value * alpha)))
    return layer


def main():
    out = Path(sys.argv[1])
    atlas = Image.open(ROOT / "Media" / "button-icons.tga").convert("RGBA").getchannel("A")
    names = glyph_names()
    _, maps = palettes()

    def cell(row, column):
        return atlas.crop((column * CELL, row * CELL, column * CELL + CELL, row * CELL + CELL))

    masks = {layer: cell(GLYPH_ROWS, index) for index, layer in enumerate(("plate", "border", "glow", "underline"))}
    font_path = ROOT / "Media" / "Fonts" / "JetBrainsMono-Regular.ttf"
    bold_path = ROOT / "Media" / "Fonts" / "JetBrainsMono-Bold.ttf"
    font = ImageFont.truetype(str(font_path), 15)
    bold = ImageFont.truetype(str(bold_path), 19)
    small = ImageFont.truetype(str(font_path), 12)
    size, gap, left, pad = 48, 6, 120, 24
    block_h = 40 + len(STATES) * (size + gap) + 18
    width = left + len(SAMPLE) * (size + gap) + pad
    height = pad + 30 + len(THEMES) * (block_h + 14) + 30
    page = Image.new("RGBA", (width, height), PAGE + (255,))
    draw = ImageDraw.Draw(page)
    draw.text((pad, pad), "VignetteRadar icon buttons: layered theme roles", font=bold, fill=TEXT)
    y = pad + 36
    for theme in THEMES:
        title, background, roles, framed, rings = resolve(theme, maps)
        draw.rounded_rectangle((pad - 8, y, width - pad + 8, y + block_h), radius=12, fill=background + (255,))
        draw.text((pad + 4, y + 8), title, font=bold, fill=TEXT)
        sx = pad + 20 + int(draw.textlength(title, font=bold))
        for layer in ("glyph", "border", "plate", "hover", "active"):
            draw.rounded_rectangle((sx, y + 12, sx + 14, y + 26), radius=3, fill=roles[layer] + (255,))
            draw.text((sx + 18, y + 11), layer, font=small, fill=SOFT)
            sx += 30 + int(draw.textlength(layer, font=small))
        for row, state in enumerate(STATES):
            top = y + 40 + row * (size + gap)
            draw.text((pad + 4, top + size / 2 - 9), state, font=font, fill=SOFT)
            look = FRAMED if framed else QUIET
            for column, name in enumerate(SAMPLE):
                index = names.index(name)
                glyph = cell(index // COLUMNS, index % COLUMNS)
                tile = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
                if state == "disabled":
                    alphas, glyph_color, glyph_alpha = ((.10 if framed else 0), 0, 0), rings, .38
                else:
                    alphas = look[state]
                    glyph_color, glyph_alpha = roles["glyph"], (1 if state != "idle" else .86)
                tile.alpha_composite(tinted(masks["plate"], roles["plate"], alphas[0]))
                tile.alpha_composite(tinted(masks["glow"], roles["hover"], alphas[2]))
                tile.alpha_composite(tinted(masks["border"], roles["border"], alphas[1]))
                offset = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
                offset.alpha_composite(tinted(glyph, glyph_color, glyph_alpha), (0, 2 if state == "pressed" else 0))
                tile.alpha_composite(offset)
                if state == "active":
                    tile.alpha_composite(tinted(masks["underline"], roles["active"], .92))
                tile = tile.resize((size, size), Image.LANCZOS)
                page.alpha_composite(tile, (left + column * (size + gap), top))
        y += block_h + 14
    draw.text((pad, y + 2), "Single Color themes stay quiet (glyph only until hover); Multi-Color themes are framed.",
              font=small, fill=SOFT)
    out.parent.mkdir(parents=True, exist_ok=True)
    page.convert("RGB").save(out)
    print(f"Preview: {out}")


if __name__ == "__main__":
    main()
