"""PS1-style 512 atlas + emission map for the field tablet."""
import os
import math
import numpy as np

OUT_DIR = r"C:\Users\luigi.manzi\Documents\blend\textures"
os.makedirs(OUT_DIR, exist_ok=True)
SIZE = 512

# Atlas regions in UV (bottom-left origin) and pixels (top-left numpy, converted later)
# We paint in Blender-space: y=0 at bottom. numpy array [y from bottom].
REG = {
    "SCREEN":  (0.00, 0.00, 0.50, 0.375),
    "RUBBER":  (0.50, 0.00, 0.75, 0.1875),
    "METAL":   (0.75, 0.00, 1.00, 0.1875),
    "AMBER":   (0.50, 0.1875, 0.75, 0.375),
    "RED":     (0.75, 0.1875, 1.00, 0.375),
    "STRIPES": (0.00, 0.375, 0.25, 0.50),
    "STENCIL": (0.25, 0.375, 0.50, 0.50),
    "LEDS":    (0.50, 0.375, 0.75, 0.50),
    "SPEAKER": (0.75, 0.375, 1.00, 0.50),
    "OLIVE":   (0.00, 0.50, 0.50, 1.00),
    "RUST":    (0.50, 0.50, 1.00, 1.00),
}


def uv_to_px(rect):
    u0, v0, u1, v1 = rect
    x0 = int(round(u0 * SIZE))
    y0 = int(round(v0 * SIZE))
    x1 = int(round(u1 * SIZE))
    y1 = int(round(v1 * SIZE))
    return x0, y0, x1, y1


# --- palette (sRGB 0-255) ---
C = {
    "olive_dk":  (24, 28, 18),
    "olive":     (42, 48, 30),
    "olive_lt":  (62, 66, 40),
    "olive_hi":  (88, 90, 56),
    "rust":      (104, 50, 26),
    "rust_lt":   (132, 70, 34),
    "rust_dk":   (58, 26, 16),
    "dirt":      (34, 26, 18),
    "black":     (10, 10, 9),
    "rubber":    (18, 17, 16),
    "rubber_lt": (32, 30, 28),
    "metal":     (48, 50, 46),
    "metal_dk":  (22, 24, 22),
    "metal_hi":  (78, 80, 74),
    "amber":     (186, 124, 34),
    "amber_dk":  (112, 68, 16),
    "amber_hi":  (220, 168, 64),
    "red":       (156, 34, 26),
    "red_dk":    (88, 18, 16),
    "red_hi":    (210, 56, 40),
    "yellow":    (204, 170, 36),
    "yellow_dk": (120, 96, 18),
    "crt_bg":    (6, 18, 10),
    "crt_dim":   (16, 48, 26),
    "crt_mid":   (36, 118, 58),
    "crt_lit":   (78, 214, 104),
    "crt_hot":   (176, 255, 168),
    "crt_amber": (210, 170, 40),
}


def rgb(name):
    return np.array(C[name], dtype=np.float32)


def block_noise(h, w, cell, seed):
    rng = np.random.default_rng(seed)
    gh = int(math.ceil(h / cell)) + 1
    gw = int(math.ceil(w / cell)) + 1
    g = rng.random((gh, gw)).astype(np.float32)
    g[-1] = g[0]
    g[:, -1] = g[:, 0]
    out = np.repeat(np.repeat(g, cell, 0), cell, 1)[:h, :w]
    return out


def fine_noise(h, w, seed):
    rng = np.random.default_rng(seed)
    return rng.random((h, w)).astype(np.float32)


def scratches(h, w, seed, n=40, col=1.0, axis="h"):
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w), dtype=np.float32)
    for _ in range(n):
        if axis == "h":
            y = int(rng.integers(0, h))
            x0 = int(rng.integers(0, w))
            length = int(rng.integers(4, max(5, w // 3)))
            thick = int(rng.choice([1, 1, 1, 2]))
            val = float(rng.uniform(0.4, 1.0)) * col
            for t in range(thick):
                yy = min(h - 1, y + t)
                img[yy, x0 : min(w, x0 + length)] = val
        else:
            x = int(rng.integers(0, w))
            y0 = int(rng.integers(0, h))
            length = int(rng.integers(3, max(4, h // 4)))
            val = float(rng.uniform(0.4, 1.0)) * col
            img[y0 : min(h, y0 + length), x] = val
    return img


def blobs(h, w, seed, n=12, radius=18):
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w), dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(n):
        cx = float(rng.uniform(0, w))
        cy = float(rng.uniform(0, h))
        r = float(rng.uniform(radius * 0.4, radius))
        # wrap-friendly min dist
        dx = np.minimum(np.abs(xx - cx), w - np.abs(xx - cx))
        dy = np.minimum(np.abs(yy - cy), h - np.abs(yy - cy))
        d = np.sqrt(dx * dx + dy * dy)
        img += np.clip(1.0 - d / r, 0, 1) * float(rng.uniform(0.4, 1.0))
    return np.clip(img, 0, 1)


def lerp(a, b, t):
    t = np.clip(t, 0, 1)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1.0 - t) + b * t


def posterize(img, steps=24):
    return np.round(img / 255.0 * (steps - 1)) / (steps - 1) * 255.0


# 5x7 pixel font (rows top->bottom)
FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "X": ["10001", "01010", "00100", "00100", "00100", "01010", "10001"],
    "Y": ["10001", "01010", "00100", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "00100", "00100"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "#": ["01010", "11111", "01010", "01010", "01010", "11111", "01010"],
}


def blit_text(img, x, y, text, color, scale=1, origin="bl"):
    """Draw text. y is from bottom if origin=bl (our array). Glyphs drawn upward."""
    cx = x
    col = np.array(color, dtype=np.float32)
    for ch in text:
        glyph = FONT.get(ch, FONT[" "])
    # we'll implement below with proper loop
    pass


def draw_text(img, x, y, text, color, scale=1):
    """y from bottom, text baseline at y, grows up."""
    col = np.array(color, dtype=np.float32)
    cx = int(x)
    h, w = img.shape[:2]
    for ch in text:
        glyph = FONT.get(ch, FONT[" "])
        gh, gw = 7 * scale, 5 * scale
        for row, bits in enumerate(glyph):
            # glyph row 0 is top of character
            py = y + (6 - row) * scale
            for col_i, bit in enumerate(bits):
                if bit != "1":
                    continue
                for sy in range(scale):
                    for sx in range(scale):
                        px = cx + col_i * scale + sx
                        yy = py + sy
                        if 0 <= yy < h and 0 <= px < w:
                            img[yy, px] = col
        cx += 6 * scale
    return cx


def fill_rect(img, x0, y0, x1, y1, color):
    img[y0:y1, x0:x1] = color


def rect_outline(img, x0, y0, x1, y1, color, t=1):
    fill_rect(img, x0, y0, x1, y0 + t, color)
    fill_rect(img, x0, y1 - t, x1, y1, color)
    fill_rect(img, x0, y0, x0 + t, y1, color)
    fill_rect(img, x1 - t, y0, x1, y1, color)


def paint_material(img, x0, y0, x1, y1, base, hi, lo, seed, kind="paint"):
    h, w = y1 - y0, x1 - x0
    n1 = block_noise(h, w, 8, seed)
    n2 = block_noise(h, w, 4, seed + 1)
    n3 = fine_noise(h, w, seed + 2)
    n4 = block_noise(h, w, 20, seed + 3)
    dirt = blobs(h, w, seed + 4, n=7, radius=18)
    sc_h = scratches(h, w, seed + 5, n=22, axis="h")
    sc_v = scratches(h, w, seed + 6, n=8, axis="v")
    mix = n1 * 0.30 + n2 * 0.22 + n3 * 0.22 + n4 * 0.26
    col = lerp(np.broadcast_to(lo, (h, w, 3)), np.broadcast_to(hi, (h, w, 3)), mix)
    col = lerp(col, np.broadcast_to(base, (h, w, 3)), 0.48)
    col = lerp(col, np.broadcast_to(rgb("dirt"), (h, w, 3)), dirt * 0.28)
    if kind == "paint":
        # rare paint chips, not a camo checker
        chips = (n4 > 0.93) & (n3 > 0.82) & (dirt > 0.35)
        col = np.where(chips[..., None], np.broadcast_to(rgb("rust_dk"), (h, w, 3)), col)
        wear = (n1 > 0.86) & (n3 > 0.7)
        col = np.where(wear[..., None], lerp(col, np.broadcast_to(hi, (h, w, 3)), 0.4), col)
    elif kind == "metal":
        specks = n3 > 0.92
        col = np.where(specks[..., None], np.broadcast_to(hi, (h, w, 3)), col)
        rusts = dirt > 0.65
        col = np.where(rusts[..., None], lerp(col, np.broadcast_to(rgb("rust"), (h, w, 3)), 0.7), col)
    elif kind == "rubber":
        # dimpled
        dimple = ((np.arange(h)[:, None] // 3 + np.arange(w)[None, :] // 3) % 2).astype(np.float32)
        col = lerp(col, np.broadcast_to(lo, (h, w, 3)), dimple * 0.25)
    elif kind == "plastic":
        gloss = n3 * 0.2 + n2 * 0.15
        col = lerp(col, np.broadcast_to(hi, (h, w, 3)), gloss)
    # scratches
    col = lerp(col, np.broadcast_to(hi, (h, w, 3)), sc_h[..., None] * 0.35)
    col = lerp(col, np.broadcast_to(lo, (h, w, 3)), sc_v[..., None] * 0.25)
    img[y0:y1, x0:x1] = posterize(col, 20)


def paint_stripes(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    yy, xx = np.mgrid[0:h, 0:w]
    stripe = ((xx + yy) // 7) % 2
    col = np.where(stripe[..., None] == 0, rgb("yellow"), rgb("black"))
    n = fine_noise(h, w, 99)
    col = lerp(col, np.broadcast_to(rgb("dirt"), (h, w, 3)), (n * 0.18)[..., None])
    # wear
    dirt = blobs(h, w, 77, n=6, radius=16)
    col = lerp(col, np.broadcast_to(rgb("olive_dk"), (h, w, 3)), dirt * 0.35)
    img[y0:y1, x0:x1] = posterize(col, 16)


def paint_stencil(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    # dark plate
    paint_material(img, x0, y0, x1, y1, rgb("olive_dk"), rgb("olive"), rgb("black"), 11, "paint")
    # yellow stencil text
    # local coords
    draw_text(img, x0 + 8, y0 + 36, "TAC-7", C["yellow"], scale=2)
    draw_text(img, x0 + 8, y0 + 16, "UNIT 09", C["yellow"], scale=1)
    # faded serial
    draw_text(img, x0 + 8, y0 + 6, "SN 4417", C["olive_hi"], scale=1)


def paint_leds(img, emit, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    paint_material(img, x0, y0, x1, y1, rgb("metal_dk"), rgb("metal"), rgb("black"), 21, "metal")
    # three LED pads
    pads = [
        (8, 16, C["crt_lit"], C["crt_hot"]),
        (48, 16, C["amber_hi"], C["amber"]),
        (88, 16, C["red_hi"], C["red"]),
    ]
    for px, py, hi, lo in pads:
        fill_rect(img, x0 + px, y0 + py, x0 + px + 28, y0 + py + 28, lo)
        fill_rect(img, x0 + px + 4, y0 + py + 4, x0 + px + 24, y0 + py + 24, hi)
        # emit
        fill_rect(emit, x0 + px + 2, y0 + py + 2, x0 + px + 26, y0 + py + 26, hi)


def paint_speaker(img, x0, y0, x1, y1):
    paint_material(img, x0, y0, x1, y1, rgb("metal_dk"), rgb("metal"), rgb("black"), 33, "metal")
    # hole grid
    for iy in range(5):
        for ix in range(8):
            px = x0 + 10 + ix * 14
            py = y0 + 8 + iy * 11
            fill_rect(img, px, py, px + 6, py + 6, C["black"])
            fill_rect(img, px + 1, py + 1, px + 5, py + 5, C["dirt"])


def paint_screen(img, emit, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    # background phosphor
    bg = np.broadcast_to(rgb("crt_bg"), (h, w, 3)).copy()
    n = fine_noise(h, w, 7)
    bn = block_noise(h, w, 4, 8)
    bg = lerp(bg, np.broadcast_to(rgb("crt_dim"), (h, w, 3)), (n * 0.25 + bn * 0.12)[..., None])
    # static specks
    specks = n > 0.97
    bg[specks] = rgb("crt_mid")
    img[y0:y1, x0:x1] = bg
    emit[y0:y1, x0:x1] = bg * 0.35

    def S(x, y, x2, y2, col, e=None):
        fill_rect(img, x0 + x, y0 + y, x0 + x2, y0 + y2, col)
        if e is not None:
            fill_rect(emit, x0 + x, y0 + y, x0 + x2, y0 + y2, e)

    # outer bezel glow
    rect_outline(img, x0 + 2, y0 + 2, x1 - 2, y1 - 2, C["crt_dim"], 2)
    rect_outline(emit, x0 + 2, y0 + 2, x1 - 2, y1 - 2, C["crt_mid"], 2)

    # header bar
    S(6, h - 22, w - 6, h - 6, C["crt_dim"], C["crt_mid"])
    draw_text(img, x0 + 10, y0 + h - 20, "TAC-7", C["crt_lit"], 1)
    draw_text(emit, x0 + 10, y0 + h - 20, "TAC-7", C["crt_hot"], 1)
    draw_text(img, x0 + 52, y0 + h - 20, "LINK OK", C["crt_hot"], 1)
    draw_text(emit, x0 + 52, y0 + h - 20, "LINK OK", C["crt_hot"], 1)
    # signal pips
    for i in range(5):
        col = C["crt_lit"] if i < 4 else C["crt_dim"]
        S(w - 52 + i * 8, h - 18, w - 52 + i * 8 + 6, h - 10, col, C["crt_hot"] if i < 4 else C["crt_dim"])

    # main radar pane
    rx0, ry0, rx1, ry1 = 8, 28, 168, h - 26
    S(rx0, ry0, rx1, ry1, C["crt_bg"], (4, 14, 8))
    rect_outline(img, x0 + rx0, y0 + ry0, x0 + rx1, y0 + ry1, C["crt_mid"], 1)
    rect_outline(emit, x0 + rx0, y0 + ry0, x0 + rx1, y0 + ry1, C["crt_lit"], 1)

    # grid
    for gx in range(rx0 + 16, rx1, 16):
        S(gx, ry0 + 1, gx + 1, ry1 - 1, C["crt_dim"], C["crt_dim"])
    for gy in range(ry0 + 16, ry1, 16):
        S(rx0 + 1, gy, rx1 - 1, gy + 1, C["crt_dim"], C["crt_dim"])

    # radar circles + cross
    cx = (rx0 + rx1) // 2
    cy = (ry0 + ry1) // 2
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    for rad in (18, 36, 54):
        ring = np.abs(dist - rad) < 1.0
        mask = np.zeros((h, w), dtype=bool)
        mask[ry0:ry1, rx0:rx1] = True
        ring &= mask
        img[y0:y1, x0:x1][ring] = rgb("crt_mid")
        emit[y0:y1, x0:x1][ring] = rgb("crt_lit")

    # crosshair
    S(cx, ry0 + 2, cx + 1, ry1 - 2, C["crt_mid"], C["crt_lit"])
    S(rx0 + 2, cy, rx1 - 2, cy + 1, C["crt_mid"], C["crt_lit"])

    # sweep wedge (about 50 degrees)
    ang = np.arctan2(yy - cy, xx - cx)
    sweep = (ang > 0.35) & (ang < 1.15) & (dist < 56) & (xx >= rx0) & (xx < rx1) & (yy >= ry0) & (yy < ry1)
    fade = np.clip(1.0 - (ang - 0.35) / 0.80, 0, 1)
    sw = np.zeros((h, w, 3), dtype=np.float32)
    sw[sweep] = rgb("crt_mid") * fade[sweep][..., None] * 0.85
    base = img[y0:y1, x0:x1]
    img[y0:y1, x0:x1] = np.clip(base + sw, 0, 255)
    em = emit[y0:y1, x0:x1]
    emit[y0:y1, x0:x1] = np.clip(em + sw * 1.4, 0, 255)

    # blips
    blips = [(cx + 22, cy + 10), (cx - 18, cy + 28), (cx + 8, cy - 24), (cx - 30, cy - 8)]
    for bx, by in blips:
        S(bx - 1, by - 1, bx + 2, by + 2, C["crt_hot"], C["crt_hot"])
        S(bx, by, bx + 1, by + 1, C["crt_hot"], C["crt_hot"])

    # corner brackets
    for bx, by, sx, sy in [
        (rx0 + 2, ry1 - 10, 1, 1),
        (rx1 - 10, ry1 - 10, 1, 1),
        (rx0 + 2, ry0 + 2, 1, 1),
        (rx1 - 10, ry0 + 2, 1, 1),
    ]:
        S(bx, by, bx + 8, by + 2, C["crt_lit"], C["crt_hot"])
        S(bx, by, bx + 2, by + 8, C["crt_lit"], C["crt_hot"])

    # right meters
    mx0 = 174
    S(mx0, 28, w - 8, h - 26, C["crt_bg"], (4, 14, 8))
    rect_outline(img, x0 + mx0, y0 + 28, x0 + w - 8, y0 + h - 26, C["crt_mid"], 1)
    draw_text(img, x0 + mx0 + 4, y0 + h - 42, "SIG", C["crt_lit"], 1)
    draw_text(emit, x0 + mx0 + 4, y0 + h - 42, "SIG", C["crt_hot"], 1)
    for i, filled in enumerate([1, 1, 1, 1, 0]):
        col = C["crt_lit"] if filled else C["crt_dim"]
        S(mx0 + 4 + i * 13, h - 56, mx0 + 14 + i * 13, h - 46, col, C["crt_hot"] if filled else C["crt_dim"])
    draw_text(img, x0 + mx0 + 4, y0 + h - 72, "RNG", C["crt_mid"], 1)
    for i, filled in enumerate([1, 1, 0, 0, 0]):
        col = C["crt_lit"] if filled else C["crt_dim"]
        S(mx0 + 4 + i * 13, h - 86, mx0 + 14 + i * 13, h - 76, col, C["crt_hot"] if filled else C["crt_dim"])
    draw_text(img, x0 + mx0 + 4, y0 + 70, "BAT", C["crt_amber"], 1)
    draw_text(emit, x0 + mx0 + 4, y0 + 70, "BAT", C["amber_hi"], 1)
    for i, filled in enumerate([1, 1, 1, 0, 0]):
        col = C["crt_amber"] if filled else C["crt_dim"]
        S(mx0 + 4 + i * 13, 52, mx0 + 14 + i * 13, 62, col, C["amber"] if filled else C["crt_dim"])
    draw_text(img, x0 + mx0 + 4, y0 + 36, "47.2N", C["crt_mid"], 1)
    draw_text(img, x0 + mx0 + 4, y0 + 26, "08.1E", C["crt_mid"], 1)

    # waveform footer
    S(8, 8, w - 8, 24, C["crt_bg"], (4, 14, 8))
    rect_outline(img, x0 + 8, y0 + 8, x0 + w - 8, y0 + 24, C["crt_dim"], 1)
    # polyline wave
    prev = None
    for i in range(8, w - 8):
        t = i / 20.0
        amp = 6 * math.sin(t) + 2.5 * math.sin(t * 2.7 + 0.4) + 1.2 * math.sin(t * 6.1)
        yy = int(16 + amp)
        yy = max(9, min(23, yy))
        img[y0 + yy, x0 + i] = rgb("crt_lit")
        emit[y0 + yy, x0 + i] = rgb("crt_hot")
        if prev is not None:
            a, b = sorted((prev, yy))
            img[y0 + a : y0 + b + 1, x0 + i] = rgb("crt_mid")
            emit[y0 + a : y0 + b + 1, x0 + i] = rgb("crt_lit")
        prev = yy

    # scanlines
    sl = img[y0:y1, x0:x1]
    sl[::2] = sl[::2] * 0.72
    ems = emit[y0:y1, x0:x1]
    ems[::2] = ems[::2] * 0.65
    img[y0:y1, x0:x1] = sl
    emit[y0:y1, x0:x1] = ems

    # slight vignette
    yy, xx = np.mgrid[0:h, 0:w]
    nx = (xx / max(w - 1, 1) - 0.5) * 2
    ny = (yy / max(h - 1, 1) - 0.5) * 2
    vig = np.clip(1.15 - 0.45 * (nx * nx + ny * ny), 0.55, 1.0)
    img[y0:y1, x0:x1] *= vig[..., None]
    emit[y0:y1, x0:x1] *= vig[..., None]


def build():
    img = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    emit = np.zeros((SIZE, SIZE, 3), dtype=np.float32)

    def px(name):
        return uv_to_px(REG[name])

    x0, y0, x1, y1 = px("OLIVE")
    paint_material(img, x0, y0, x1, y1, rgb("olive"), rgb("olive_lt"), rgb("olive_dk"), 1, "paint")

    x0, y0, x1, y1 = px("RUST")
    paint_material(img, x0, y0, x1, y1, rgb("rust"), rgb("rust_lt"), rgb("rust_dk"), 2, "metal")

    x0, y0, x1, y1 = px("RUBBER")
    paint_material(img, x0, y0, x1, y1, rgb("rubber"), rgb("rubber_lt"), rgb("black"), 3, "rubber")

    x0, y0, x1, y1 = px("METAL")
    paint_material(img, x0, y0, x1, y1, rgb("metal"), rgb("metal_hi"), rgb("metal_dk"), 4, "metal")

    x0, y0, x1, y1 = px("AMBER")
    paint_material(img, x0, y0, x1, y1, rgb("amber"), rgb("amber_hi"), rgb("amber_dk"), 5, "plastic")

    x0, y0, x1, y1 = px("RED")
    paint_material(img, x0, y0, x1, y1, rgb("red"), rgb("red_hi"), rgb("red_dk"), 6, "plastic")

    x0, y0, x1, y1 = px("STRIPES")
    paint_stripes(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("STENCIL")
    paint_stencil(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("LEDS")
    paint_leds(img, emit, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("SPEAKER")
    paint_speaker(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("SCREEN")
    paint_screen(img, emit, x0, y0, x1, y1)

    img = np.clip(img, 0, 255).astype(np.uint8)
    emit = np.clip(emit, 0, 255).astype(np.uint8)

    # flip to top-left for PNG save via blender later; return bottom-left arrays
    return img, emit, REG


if __name__ == "__main__":
    # executed inside Blender usually
    pass
