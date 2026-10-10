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


ASSETS = {
    "art/tiles/tile_stone_floor.png": tile_stone_floor,
    "art/tiles/tile_stone_wall.png": tile_stone_wall,
    "art/sprites/prop_stairs_up.png": lambda: prop_stairs(True),
    "art/sprites/prop_stairs_down.png": lambda: prop_stairs(False),
    "art/sprites/prop_oil_barrel.png": prop_oil_barrel,
    "art/sprites/char_keeper_idle.png": char_keeper_idle,
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
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
