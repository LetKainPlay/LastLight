#!/usr/bin/env python3
"""Generate all placeholder-replacement art from code, locked to art/palette/lastlight.hex.

Usage:
  python3 tools/generate_assets.py          write PNGs under art/
  python3 tools/generate_assets.py --check  fail if a PNG differs in pixels from what the code produces

Needs Pillow. Output is deterministic (no randomness; noise is a hash of the pixel position).
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PALETTE_FILE = ROOT / "art" / "palette" / "lastlight.hex"

# Names follow AGENT_03 section 4.2 (index = line number in lastlight.hex).
NAMES = [
    "void", "ink", "dusk-stone", "slate", "mist", "fog", "salt", "chalk",
    "deep-sea", "tide", "swell", "shallows", "sea-glass",
    "pine-shadow", "fir", "moss", "meadow", "sungrass",
    "basalt", "cliff", "granite", "sandstone", "dune",
    "brick-dark", "lighthouse-red", "signal-coral",
    "driftwood", "oak", "lamp-amber", "lamp-gold", "lamp-white", "skin",
]


def load_palette() -> dict[str, tuple[int, int, int, int]]:
    lines = [ln.strip() for ln in PALETTE_FILE.read_text().splitlines() if ln.strip()]
    assert len(lines) >= len(NAMES), "palette file is shorter than NAMES"
    out = {}
    for name, hex_ in zip(NAMES, lines):
        h = hex_.lstrip("#")
        out[name] = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
    return out


P = load_palette()
CLEAR = (0, 0, 0, 0)


def new(w: int, h: int, fill=CLEAR) -> Image.Image:
    return Image.new("RGBA", (w, h), fill)


def rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, colour: str) -> None:
    """Fill x0..x1, y0..y1 inclusive."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                img.putpixel((x, y), P[colour])


def noise(x: int, y: int, salt: int = 0) -> int:
    n = (x * 374761393 + y * 668265263 + salt * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return (n ^ (n >> 16)) & 0xFF


def outline(img: Image.Image, colour: str = "void") -> Image.Image:
    """Pad by 1px and draw a 4-neighbour outline around opaque pixels."""
    out = new(img.width + 2, img.height + 2)
    out.paste(img, (1, 1))
    src = out.copy()
    for y in range(out.height):
        for x in range(out.width):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < src.width and 0 <= ny < src.height and src.getpixel((nx, ny))[3]:
                        out.putpixel((x, y), P[colour])
                        break
    return out


# ------------------------------------------------------------------ tiles

def tile_stone_floor() -> Image.Image:
    """16x16 interior flagstones. Every pixel depends on (x mod 16, y mod 16): seamless."""
    img = new(16, 16)
    rect(img, 0, 0, 15, 15, "dusk-stone")
    for x in range(16):  # mortar
        img.putpixel((x, 0), P["ink"])
        img.putpixel((x, 8), P["ink"])
    for y in range(16):
        img.putpixel((0 if y < 8 else 8, y), P["ink"])
    for y in range(16):
        for x in range(16):
            n = noise(x, y, 1)
            if img.getpixel((x, y)) == P["dusk-stone"]:
                if n < 28:
                    img.putpixel((x, y), P["slate"])
                elif n > 240:
                    img.putpixel((x, y), P["ink"])
    return img


def tile_stone_wall() -> Image.Image:
    """16x16 stone bricks, offset rows, lit from the top."""
    img = new(16, 16)
    rect(img, 0, 0, 15, 15, "slate")
    for y in (0, 8):
        rect(img, 0, y, 15, y, "dusk-stone")
    for y in range(16):
        x = 0 if y < 8 else 8
        img.putpixel((x, y), P["dusk-stone"])
    for y0 in (1, 9):
        for x in range(16):
            img.putpixel((x, y0), P["mist"])  # highlight under each mortar line
    for y in range(16):
        for x in range(16):
            if img.getpixel((x, y)) == P["slate"] and noise(x, y, 2) < 24:
                img.putpixel((x, y), P["dusk-stone"])
    return img


# ------------------------------------------------------------------ props

def prop_stairs(up: bool) -> Image.Image:
    """32x32 stair block seen from above; chevron shows the direction."""
    img = new(32, 32)
    shades = ["sandstone", "granite", "sandstone", "granite", "sandstone", "granite", "sandstone", "granite"]
    rect(img, 0, 0, 31, 31, "cliff")
    for i in range(8):
        y0 = i * 4
        rect(img, 1, y0, 30, y0 + 2, shades[i] if up else shades[7 - i])
        rect(img, 1, y0 + 3, 30, y0 + 3, "basalt")
    rect(img, 0, 0, 0, 31, "void")
    rect(img, 31, 0, 31, 31, "void")
    rect(img, 0, 0, 31, 0, "void")
    rect(img, 0, 31, 31, 31, "void")
    arrow = "lamp-gold"
    for k in range(5):  # chevron, 2px thick
        yy = 10 + k if up else 21 - k
        rect(img, 16 - k - 1, yy, 16 - k, yy, arrow)
        rect(img, 15 + k, yy, 16 + k, yy, arrow)
    return img


def prop_oil_barrel() -> Image.Image:
    """16x24 oak barrel with two hoops and a lid."""
    inner = new(14, 22)
    for y in range(22):
        bulge = 1 if 4 <= y <= 17 else 0
        x0, x1 = 1 - bulge, 12 + bulge
        for x in range(x0, x1 + 1):
            colour = "oak"
            if x <= x0 + 1:
                colour = "sandstone"
            elif x >= x1 - 2:
                colour = "driftwood"
            inner.putpixel((x, y), P[colour])
    for y in (5, 6, 16, 17):  # hoops
        for x in range(14):
            if inner.getpixel((x, y))[3]:
                inner.putpixel((x, y), P["ink"] if y in (5, 16) else P["slate"])
    for y in range(0, 4):  # lid
        w = (1, 3, 5, 6)[y]
        for x in range(7 - w, 7 + w):
            inner.putpixel((x, y), P["dune"] if y in (1, 2) else P["driftwood"])
    for x in range(4, 10):  # bung
        inner.putpixel((x, 2), P["driftwood"])
    return outline(inner)


# ------------------------------------------------------------------ characters

def char_keeper_idle() -> Image.Image:
    """28x44 keeper, front view: wool cap, oilskin coat, lantern-gold lit side."""
    k = new(26, 42)
    rect(k, 8, 0, 17, 5, "lighthouse-red")     # cap
    rect(k, 8, 4, 17, 5, "brick-dark")         # cap brim
    rect(k, 9, 6, 16, 15, "skin")              # face
    rect(k, 11, 10, 11, 11, "void")            # eyes
    rect(k, 14, 10, 14, 11, "void")
    rect(k, 12, 13, 13, 13, "signal-coral")    # mouth
    rect(k, 5, 16, 20, 33, "lamp-gold")        # oilskin coat
    rect(k, 16, 16, 20, 33, "lamp-amber")      # shaded side
    rect(k, 6, 17, 7, 22, "lamp-white")        # highlight
    rect(k, 12, 16, 13, 33, "lamp-amber")      # button seam
    rect(k, 2, 17, 4, 30, "lamp-gold")         # arms
    rect(k, 21, 17, 23, 30, "lamp-amber")
    rect(k, 2, 31, 4, 33, "skin")              # hands
    rect(k, 21, 31, 23, 33, "skin")
    rect(k, 7, 34, 18, 38, "dusk-stone")       # trousers
    rect(k, 12, 36, 13, 38, "ink")
    rect(k, 6, 39, 11, 41, "driftwood")        # boots
    rect(k, 14, 39, 19, 41, "driftwood")
    return outline(k)


# ------------------------------------------------------------------ more props

def draw_octagon_rings(size: int, bands: list[tuple[float, str]]) -> Image.Image:
    """Concentric octagons. bands = [(outer_radius, colour), ...] from the centre out."""
    img = new(size, size)
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            dx, dy = abs(x - c), abs(y - c)
            r = max(dx, dy, (dx + dy) * 0.7071 + 0.5)
            for outer, colour in bands:
                if r <= outer:
                    img.putpixel((x, y), P[colour])
                    break
    return img


def prop_lens() -> Image.Image:
    """64x64 Fresnel lens seen from the front: brass frame, glass rings, open centre."""
    img = draw_octagon_rings(64, [
        (7.0, "ink"), (11.0, "fog"), (14.0, "sea-glass"), (17.0, "mist"),
        (20.0, "sea-glass"), (23.0, "shallows"), (26.0, "sea-glass"),
        (28.5, "fog"), (30.0, "lamp-amber"), (31.5, "void"),
    ])
    for i in range(0, 24, 3):  # glints
        img.putpixel((12 + i // 2, 12 + i // 3), P["chalk"])
    return img


def flame(w: int, h: int, outer: str, mid: str, core: str | None) -> Image.Image:
    img = new(w, h)
    cx = (w - 1) / 2.0
    for y in range(h):
        frac = y / (h - 1)
        half = (w / 2.0) * (frac ** 0.55) * (1.0 - 0.45 * frac) * 1.25
        for x in range(w):
            if abs(x - cx) <= half:
                img.putpixel((x, y), P[outer])
    for y in range(h):
        for x in range(w):
            if img.getpixel((x, y))[3] and y > h * 0.35:
                inner = all(
                    0 <= x + dx < w and 0 <= y + dy < h and img.getpixel((x + dx, y + dy))[3]
                    for dx, dy in ((1, 0), (-1, 0), (0, -1), (0, 1)))
                if inner:
                    img.putpixel((x, y), P[mid])
    if core:
        for y in range(int(h * 0.6), h - 1):
            for x in range(w):
                if img.getpixel((x, y)) == P[mid]:
                    inner = all(img.getpixel((x + dx, y + dy)) == P[mid]
                                for dx, dy in ((1, 0), (-1, 0), (0, 1)) if 0 <= x + dx < w)
                    if inner:
                        img.putpixel((x, y), P[core])
    return img


def prop_reservoir() -> Image.Image:
    k = new(14, 12)
    rect(k, 1, 2, 12, 10, "lamp-amber")
    rect(k, 2, 3, 3, 9, "lamp-gold")
    rect(k, 1, 0, 12, 2, "driftwood")      # rim and oil surface
    rect(k, 2, 1, 11, 1, "basalt")
    rect(k, 3, 11, 10, 11, "oak")
    return outline(k)


def prop_wick_trimmer() -> Image.Image:
    k = new(12, 10)
    for i in range(6):                      # crossed blades
        k.putpixel((1 + i, 1 + i), P["fog"])
        k.putpixel((1 + i, 6 - i), P["fog"])
    rect(k, 7, 3, 10, 3, "slate")
    rect(k, 7, 5, 10, 5, "slate")
    rect(k, 8, 1, 10, 2, "driftwood")
    rect(k, 8, 6, 10, 7, "driftwood")
    return outline(k)


def prop_match_box() -> Image.Image:
    k = new(12, 8)
    rect(k, 0, 2, 11, 7, "lighthouse-red")
    rect(k, 0, 2, 11, 3, "signal-coral")
    rect(k, 1, 5, 10, 6, "brick-dark")
    rect(k, 2, 0, 8, 0, "dune")
    rect(k, 9, 0, 9, 1, "lamp-white")
    return outline(k)


def prop_oil_can() -> Image.Image:
    k = new(12, 12)
    rect(k, 2, 4, 9, 10, "lamp-gold")
    rect(k, 7, 4, 9, 10, "lamp-amber")
    rect(k, 3, 5, 3, 8, "lamp-white")
    rect(k, 4, 2, 7, 3, "slate")           # handle
    rect(k, 9, 3, 11, 3, "slate")          # spout
    rect(k, 11, 2, 11, 2, "slate")
    return outline(k)


def prop_stove() -> Image.Image:
    k = new(24, 26)
    rect(k, 8, 0, 11, 6, "slate")           # chimney
    rect(k, 2, 7, 21, 23, "slate")
    rect(k, 2, 7, 21, 9, "mist")            # hot plate
    rect(k, 3, 12, 20, 21, "ink")
    rect(k, 6, 14, 17, 21, "lamp-amber")    # fire door glow
    rect(k, 8, 16, 15, 21, "lamp-gold")
    rect(k, 10, 18, 13, 21, "lamp-white")
    rect(k, 3, 24, 5, 25, "ink")
    rect(k, 18, 24, 20, 25, "ink")
    return outline(k)


def prop_bed() -> Image.Image:
    k = new(36, 24)
    rect(k, 0, 6, 35, 21, "driftwood")      # frame
    rect(k, 0, 0, 3, 21, "oak")             # headboard
    rect(k, 4, 8, 35, 18, "salt")           # sheet
    rect(k, 14, 8, 35, 18, "lighthouse-red")  # blanket
    rect(k, 14, 8, 35, 9, "signal-coral")
    rect(k, 5, 9, 12, 14, "chalk")          # pillow
    rect(k, 5, 14, 12, 14, "fog")
    rect(k, 0, 22, 2, 23, "driftwood")
    rect(k, 33, 22, 35, 23, "driftwood")
    return outline(k)


def prop_table() -> Image.Image:
    k = new(36, 24)
    rect(k, 0, 6, 35, 10, "oak")
    rect(k, 0, 10, 35, 11, "driftwood")
    rect(k, 2, 12, 4, 23, "driftwood")
    rect(k, 31, 12, 33, 23, "driftwood")
    rect(k, 12, 1, 23, 6, "brick-dark")     # logbook
    rect(k, 12, 5, 23, 6, "dune")
    rect(k, 17, 1, 18, 5, "void")
    rect(k, 27, 2, 28, 5, "lamp-gold")      # candle
    rect(k, 27, 0, 28, 1, "lamp-white")
    return outline(k)


def prop_window() -> Image.Image:
    k = new(18, 22)
    rect(k, 0, 0, 17, 21, "oak")
    rect(k, 2, 2, 15, 19, "deep-sea")
    rect(k, 2, 2, 15, 9, "tide")
    rect(k, 8, 2, 9, 19, "oak")
    rect(k, 2, 10, 15, 11, "oak")
    rect(k, 3, 3, 4, 5, "shallows")
    rect(k, 0, 20, 17, 21, "dune")
    return outline(k)


# ------------------------------------------------------------------ UI

def ui_prompt_e() -> Image.Image:
    k = new(13, 13)
    rect(k, 0, 0, 12, 12, "chalk")
    rect(k, 12, 1, 12, 12, "fog")
    rect(k, 1, 12, 12, 12, "fog")
    ox, oy = 4, 3
    for y, row in enumerate(GLYPHS["E"][1]):
        for x, ch in enumerate(row):
            if ch == "#":
                k.putpixel((ox + x, oy + y), P["ink"])
    return outline(k, "ink")


def ui_panel() -> Image.Image:
    """24x24 nine-slice, 8px corners."""
    k = new(24, 24)
    rect(k, 0, 0, 23, 23, "ink")
    for i in range(24):
        for (x, y) in ((i, 0), (i, 23), (0, i), (23, i)):
            k.putpixel((x, y), P["void"])
        for (x, y) in ((i, 1), (i, 22), (1, i), (22, i)):
            if 1 <= i <= 22:
                k.putpixel((x, y), P["lamp-amber"])
    return k


# ------------------------------------------------------------------ bitmap font (5x7 glyphs)

def _g(spec: str, top: int = 0) -> tuple[int, list[str]]:
    return top, spec.split("/")


GLYPHS: dict[str, tuple[int, list[str]]] = {
    "A": _g(".###./#...#/#...#/#####/#...#/#...#/#...#"), "B": _g("####./#...#/#...#/####./#...#/#...#/####."),
    "C": _g(".###./#...#/#..../#..../#..../#...#/.###."), "D": _g("####./#...#/#...#/#...#/#...#/#...#/####."),
    "E": _g("#####/#..../#..../####./#..../#..../#####"), "F": _g("#####/#..../#..../####./#..../#..../#...."),
    "G": _g(".###./#...#/#..../#.###/#...#/#...#/.###."), "H": _g("#...#/#...#/#...#/#####/#...#/#...#/#...#"),
    "I": _g(".###./..#../..#../..#../..#../..#../.###."), "J": _g("..###/...#./...#./...#./...#./#..#./.##.."),
    "K": _g("#...#/#..#./#.#../##.../#.#../#..#./#...#"), "L": _g("#..../#..../#..../#..../#..../#..../#####"),
    "M": _g("#...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#"), "N": _g("#...#/##..#/#.#.#/#..##/#...#/#...#/#...#"),
    "O": _g(".###./#...#/#...#/#...#/#...#/#...#/.###."), "P": _g("####./#...#/#...#/####./#..../#..../#...."),
    "Q": _g(".###./#...#/#...#/#...#/#.#.#/#..#./.##.#"), "R": _g("####./#...#/#...#/####./#.#../#..#./#...#"),
    "S": _g(".####/#..../#..../.###./....#/....#/####."), "T": _g("#####/..#../..#../..#../..#../..#../..#.."),
    "U": _g("#...#/#...#/#...#/#...#/#...#/#...#/.###."), "V": _g("#...#/#...#/#...#/#...#/#...#/.#.#./..#.."),
    "W": _g("#...#/#...#/#...#/#.#.#/#.#.#/##.##/#...#"), "X": _g("#...#/#...#/.#.#./..#../.#.#./#...#/#...#"),
    "Y": _g("#...#/#...#/.#.#./..#../..#../..#../..#.."), "Z": _g("#####/....#/...#./..#../.#.../#..../#####"),
    "a": _g(".###./....#/.####/#...#/.####", 2), "b": _g("#..../#..../####./#...#/#...#/#...#/####."),
    "c": _g(".###./#...#/#..../#...#/.###.", 2), "d": _g("....#/....#/.####/#...#/#...#/#...#/.####"),
    "e": _g(".###./#...#/#####/#..../.###.", 2), "f": _g("..##./.#..#/.#.../###../.#.../.#.../.#..."),
    "g": _g(".####/#...#/#...#/.####/....#/#...#/.###.", 2), "h": _g("#..../#..../####./#...#/#...#/#...#/#...#"),
    "i": _g("..#../...../.##../..#../..#../..#../.###."), "j": _g("...#./...../..##./...#./...#./#..#./.##.."),
    "k": _g("#..../#..../#..#./#.#../##.../#.#../#..#."), "l": _g(".##../..#../..#../..#../..#../..#../.###."),
    "m": _g("##.#./#.#.#/#.#.#/#.#.#/#...#", 2), "n": _g("####./#...#/#...#/#...#/#...#", 2),
    "o": _g(".###./#...#/#...#/#...#/.###.", 2), "p": _g("####./#...#/#...#/####./#..../#..../#....", 2),
    "q": _g(".####/#...#/#...#/.####/....#/....#/....#", 2), "r": _g("#.##./##..#/#..../#..../#....", 2),
    "s": _g(".####/#..../.###./....#/####.", 2), "t": _g(".#.../.#.../###../.#.../.#.../.#..#/..##."),
    "u": _g("#...#/#...#/#...#/#...#/.####", 2), "v": _g("#...#/#...#/#...#/.#.#./..#..", 2),
    "w": _g("#...#/#...#/#.#.#/#.#.#/.#.#.", 2), "x": _g("#...#/.#.#./..#../.#.#./#...#", 2),
    "y": _g("#...#/#...#/#...#/.####/....#/#...#/.###.", 2), "z": _g("#####/...#./..#../.#.../#####", 2),
    "0": _g(".###./#...#/#..##/#.#.#/##..#/#...#/.###."), "1": _g("..#../.##../..#../..#../..#../..#../.###."),
    "2": _g(".###./#...#/....#/...#./..#../.#.../#####"), "3": _g(".###./#...#/....#/..##./....#/#...#/.###."),
    "4": _g("...#./..##./.#.#./#..#./#####/...#./...#."), "5": _g("#####/#..../####./....#/....#/#...#/.###."),
    "6": _g("..##./.#.../#..../####./#...#/#...#/.###."), "7": _g("#####/....#/...#./..#../.#.../.#.../.#..."),
    "8": _g(".###./#...#/#...#/.###./#...#/#...#/.###."), "9": _g(".###./#...#/#...#/.####/....#/...#./.##.."),
    ".": _g("..#..", 6), ",": _g("..#../.#...", 6), "!": _g("..#../..#../..#../..#../..#../...../..#.."),
    "?": _g(".###./#...#/....#/...#./..#../...../..#.."), ":": _g("..#../...../...../..#..", 2),
    "-": _g(".###.", 4), "'": _g("..#../..#../.#..."), "/": _g("....#/...#./...#./..#../.#.../.#.../#...."),
    "(": _g("...#./..#../.#.../.#.../.#.../..#../...#."), ")": _g(".#.../..#../...#./...#./...#./..#../.#..."),
}


def font_atlas(scale: int) -> tuple[Image.Image, str]:
    """Bitmap font, outlined, glyphs chalk on ink. Returns (atlas, BMFont text descriptor)."""
    cell_w, cell_h = 7 * scale, 11 * scale
    chars = [" "] + sorted(GLYPHS)
    cols = 16
    rows_n = (len(chars) + cols - 1) // cols
    atlas = new(cols * cell_w, rows_n * cell_h)
    lines = []
    for i, ch in enumerate(chars):
        cx, cy = (i % cols) * cell_w, (i // cols) * cell_h
        if ch != " ":
            top, rows = GLYPHS[ch]
            g = new(5, 9)
            for y, row in enumerate(rows):
                for x, c in enumerate(row):
                    if c == "#":
                        g.putpixel((x, top + y), P["chalk"])
            g = outline(g, "ink")  # 7x11
            if scale > 1:
                g = g.resize((g.width * scale, g.height * scale), Image.NEAREST)
            atlas.paste(g, (cx, cy))
        lines.append(f"char id={ord(ch)} x={cx} y={cy} width={cell_w} height={cell_h} "
                     f"xoffset=0 yoffset=0 xadvance={6 * scale} page=0 chnl=15")
    name = "pixel_font" if scale == 1 else "pixel_font_2x"
    desc = (f'info face="{name}" size={8 * scale} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 '
            f'aa=0 padding=0,0,0,0 spacing=0,0 outline=0\n'
            f'common lineHeight={12 * scale} base={8 * scale} scaleW={atlas.width} scaleH={atlas.height} pages=1 packed=0\n'
            f'page id=0 file="{name}.png"\n'
            f'chars count={len(chars)}\n' + "\n".join(lines) + "\n")
    return atlas, desc


ASSETS = {
    "art/tiles/tile_stone_floor.png": tile_stone_floor,
    "art/tiles/tile_stone_wall.png": tile_stone_wall,
    "art/sprites/prop_stairs_up.png": lambda: prop_stairs(True),
    "art/sprites/prop_stairs_down.png": lambda: prop_stairs(False),
    "art/sprites/prop_oil_barrel.png": prop_oil_barrel,
    "art/sprites/char_keeper_idle.png": char_keeper_idle,
    "art/sprites/prop_lens.png": prop_lens,
    "art/sprites/fx_flame_ember.png": lambda: flame(8, 10, "lamp-amber", "signal-coral", None),
    "art/sprites/fx_flame_steady.png": lambda: flame(12, 16, "lamp-amber", "lamp-gold", None),
    "art/sprites/fx_flame_bright.png": lambda: flame(14, 22, "lamp-amber", "lamp-gold", "lamp-white"),
    "art/sprites/prop_reservoir.png": prop_reservoir,
    "art/sprites/prop_wick_trimmer.png": prop_wick_trimmer,
    "art/sprites/prop_match_box.png": prop_match_box,
    "art/sprites/prop_oil_can.png": prop_oil_can,
    "art/sprites/prop_stove.png": prop_stove,
    "art/sprites/prop_bed.png": prop_bed,
    "art/sprites/prop_table.png": prop_table,
    "art/sprites/prop_window.png": prop_window,
    "art/ui/ui_prompt_e.png": ui_prompt_e,
    "art/ui/ui_panel.png": ui_panel,
    "art/fonts/pixel_font.png": lambda: font_atlas(1)[0],
    "art/fonts/pixel_font_2x.png": lambda: font_atlas(2)[0],
}

# Text files (BMFont descriptors) generated alongside the atlases.
TEXT_ASSETS = {
    "art/fonts/pixel_font.fnt": lambda: font_atlas(1)[1],
    "art/fonts/pixel_font_2x.fnt": lambda: font_atlas(2)[1],
}


def main() -> int:
    check = "--check" in sys.argv
    bad = 0
    for rel, make in ASSETS.items():
        img = make()
        path = ROOT / rel
        if check:
            if not path.exists():
                print(f"MISSING {rel}")
                bad += 1
            elif Image.open(path).convert("RGBA").tobytes() != img.tobytes():
                print(f"DIFFERS {rel}")
                bad += 1
            else:
                print(f"OK      {rel}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            img.save(path)
            print(f"wrote   {rel} {img.width}x{img.height}")
    for rel, make in TEXT_ASSETS.items():
        text = make()
        path = ROOT / rel
        if check:
            if not path.exists() or path.read_text() != text:
                print(f"DIFFERS {rel}")
                bad += 1
            else:
                print(f"OK      {rel}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            print(f"wrote   {rel}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
