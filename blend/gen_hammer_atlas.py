"""PS1-style 512 atlas for the TAC-7 field hammer."""
import math
import os

import numpy as np

OUT_DIR = r"C:\Users\luigi.manzi\Documents\blend\textures"
os.makedirs(OUT_DIR, exist_ok=True)
SIZE = 512

# Atlas regions in UV (bottom-left origin)
REG = {
    "HEAD": (0.00, 0.50, 0.50, 1.00),
    "HANDLE": (0.50, 0.50, 1.00, 1.00),
    "FACE": (0.00, 0.25, 0.50, 0.50),
    "GRIP": (0.50, 0.25, 0.75, 0.50),
    "METAL": (0.75, 0.25, 1.00, 0.50),
    "STRIPES": (0.00, 0.00, 0.25, 0.25),
    "STENCIL": (0.25, 0.00, 0.50, 0.25),
    "RUBBER": (0.50, 0.00, 0.75, 0.25),
    "WRAP": (0.75, 0.00, 1.00, 0.25),
}

C = {
    "olive_dk": (24, 28, 18),
    "olive": (42, 48, 30),
    "olive_lt": (62, 66, 40),
    "olive_hi": (88, 90, 56),
    "rust": (104, 50, 26),
    "rust_lt": (132, 70, 34),
    "rust_dk": (58, 26, 16),
    "rust_hot": (148, 64, 28),
    "dirt": (34, 26, 18),
    "black": (10, 10, 9),
    "rubber": (18, 17, 16),
    "rubber_lt": (32, 30, 28),
    "metal": (48, 50, 46),
    "metal_dk": (22, 24, 22),
    "metal_hi": (78, 80, 74),
    "steel": (36, 36, 34),
    "steel_hi": (70, 68, 62),
    "iron": (28, 24, 22),
    "iron_hi": (62, 48, 38),
    "amber": (186, 124, 34),
    "amber_dk": (112, 68, 16),
    "amber_hi": (220, 168, 64),
    "yellow": (204, 170, 36),
    "yellow_dk": (120, 96, 18),
    "cloth": (48, 44, 28),
    "cloth_lt": (72, 66, 40),
    "cloth_dk": (26, 24, 16),
}


def rgb(name):
    return np.array(C[name], dtype=np.float32)


def uv_to_px(rect):
    u0, v0, u1, v1 = rect
    return (
        int(round(u0 * SIZE)),
        int(round(v0 * SIZE)),
        int(round(u1 * SIZE)),
        int(round(v1 * SIZE)),
    )


def block_noise(h, w, cell, seed):
    rng = np.random.default_rng(seed)
    gh = int(math.ceil(h / cell)) + 1
    gw = int(math.ceil(w / cell)) + 1
    g = rng.random((gh, gw)).astype(np.float32)
    g[-1] = g[0]
    g[:, -1] = g[:, 0]
    return np.repeat(np.repeat(g, cell, 0), cell, 1)[:h, :w]


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
        dx = np.minimum(np.abs(xx - cx), w - np.abs(xx - cx))
        dy = np.minimum(np.abs(yy - cy), h - np.abs(yy - cy))
        d = np.sqrt(dx * dx + dy * dy)
        img += np.clip(1.0 - d / r, 0, 1) * float(rng.uniform(0.4, 1.0))
    return np.clip(img, 0, 1)


def lerp(a, b, t):
    t = np.clip(t, 0, 1)
    if getattr(t, "ndim", 0) == 2:
        t = t[..., None]
    return a * (1.0 - t) + b * t


def posterize(img, steps=24):
    return np.round(img / 255.0 * (steps - 1)) / (steps - 1) * 255.0


FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "00100", "00100"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}


def draw_text(img, x, y, text, color, scale=1):
    col = np.array(color, dtype=np.float32)
    cx = int(x)
    h, w = img.shape[:2]
    for ch in text:
        glyph = FONT.get(ch, FONT[" "])
        for row, bits in enumerate(glyph):
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
        chips = (n4 > 0.93) & (n3 > 0.82) & (dirt > 0.35)
        col = np.where(chips[..., None], np.broadcast_to(rgb("rust_dk"), (h, w, 3)), col)
        wear = (n1 > 0.86) & (n3 > 0.7)
        col = np.where(wear[..., None], lerp(col, np.broadcast_to(hi, (h, w, 3)), 0.4), col)
    elif kind == "metal":
        specks = n3 > 0.92
        col = np.where(specks[..., None], np.broadcast_to(hi, (h, w, 3)), col)
        rusts = dirt > 0.65
        col = np.where(rusts[..., None], lerp(col, np.broadcast_to(rgb("rust"), (h, w, 3)), 0.7), col)
    elif kind == "iron":
        rusts = (dirt > 0.42) | ((n4 > 0.72) & (n3 > 0.55))
        col = np.where(rusts[..., None], lerp(col, np.broadcast_to(rgb("rust"), (h, w, 3)), 0.78), col)
        pits = (n3 > 0.88) & (n2 < 0.4)
        col = np.where(pits[..., None], np.broadcast_to(lo, (h, w, 3)), col)
        flakes = (n1 > 0.82) & (n3 > 0.62)
        col = np.where(flakes[..., None], lerp(col, np.broadcast_to(rgb("rust_lt"), (h, w, 3)), 0.55), col)
        scale = (n4 < 0.22) & (n2 > 0.6)
        col = np.where(scale[..., None], lerp(col, np.broadcast_to(rgb("iron"), (h, w, 3)), 0.65), col)
    elif kind == "rubber":
        dimple = ((np.arange(h)[:, None] // 3 + np.arange(w)[None, :] // 3) % 2).astype(np.float32)
        col = lerp(col, np.broadcast_to(lo, (h, w, 3)), dimple * 0.25)
    elif kind == "plastic":
        gloss = n3 * 0.2 + n2 * 0.15
        col = lerp(col, np.broadcast_to(hi, (h, w, 3)), gloss)
    elif kind == "cloth":
        weave = ((np.arange(h)[:, None] // 2 + np.arange(w)[None, :] // 3) % 2).astype(np.float32)
        col = lerp(col, np.broadcast_to(lo, (h, w, 3)), weave * 0.22)
        fray = scratches(h, w, seed + 9, n=16, axis="h")
        col = lerp(col, np.broadcast_to(hi, (h, w, 3)), fray[..., None] * 0.3)
    col = lerp(col, np.broadcast_to(hi, (h, w, 3)), sc_h[..., None] * 0.35)
    col = lerp(col, np.broadcast_to(lo, (h, w, 3)), sc_v[..., None] * 0.25)
    img[y0:y1, x0:x1] = posterize(col, 20)


def paint_head(img, x0, y0, x1, y1):
    paint_material(img, x0, y0, x1, y1, rgb("iron_hi"), rgb("rust_lt"), rgb("rust_dk"), 41, "iron")
    h, w = y1 - y0, x1 - x0
    n = fine_noise(h, w, 140)
    bn = block_noise(h, w, 12, 141)
    # leftover olive paint on the cheeks
    leftover = (bn > 0.78) & (n > 0.45)
    patch = img[y0:y1, x0:x1]
    patch = np.where(
        leftover[..., None],
        lerp(patch, np.broadcast_to(rgb("olive"), (h, w, 3)), 0.55),
        patch,
    )
    img[y0:y1, x0:x1] = posterize(patch, 18)


def paint_handle(img, x0, y0, x1, y1):
    paint_material(img, x0, y0, x1, y1, rgb("steel"), rgb("steel_hi"), rgb("black"), 52, "iron")
    h, w = y1 - y0, x1 - x0
    sc = scratches(h, w, 160, n=40, axis="v")
    patch = img[y0:y1, x0:x1]
    patch = lerp(patch, np.broadcast_to(rgb("metal_dk"), (h, w, 3)), sc[..., None] * 0.45)
    rust = blobs(h, w, 161, n=10, radius=22)
    patch = lerp(patch, np.broadcast_to(rgb("rust_dk"), (h, w, 3)), rust[..., None] * 0.4)
    img[y0:y1, x0:x1] = posterize(patch, 18)


def paint_face(img, x0, y0, x1, y1):
    paint_material(img, x0, y0, x1, y1, rgb("metal"), rgb("metal_hi"), rgb("iron"), 63, "metal")
    h, w = y1 - y0, x1 - x0
    n = fine_noise(h, w, 200)
    bn = block_noise(h, w, 6, 201)
    # impact flats
    hits = blobs(h, w, 202, n=14, radius=16)
    patch = img[y0:y1, x0:x1]
    patch = lerp(patch, np.broadcast_to(rgb("metal_hi"), (h, w, 3)), hits[..., None] * 0.55)
    chips = (bn > 0.84) & (n > 0.6)
    patch = np.where(chips[..., None], np.broadcast_to(rgb("black"), (h, w, 3)), patch)
    ring = blobs(h, w, 203, n=3, radius=40)
    patch = lerp(patch, np.broadcast_to(rgb("rust"), (h, w, 3)), (1.0 - ring)[..., None] * 0.22)
    sc = scratches(h, w, 204, n=28, axis="h")
    patch = lerp(patch, np.broadcast_to(rgb("metal_dk"), (h, w, 3)), sc[..., None] * 0.4)
    img[y0:y1, x0:x1] = posterize(patch, 16)


def paint_grip(img, x0, y0, x1, y1):
    paint_material(img, x0, y0, x1, y1, rgb("olive"), rgb("olive_lt"), rgb("olive_dk"), 74, "paint")
    h, w = y1 - y0, x1 - x0
    yy = np.arange(h)[:, None]
    tape = ((yy // 7) % 2).astype(np.float32)
    tape = np.broadcast_to(tape, (h, w))
    patch = img[y0:y1, x0:x1]
    patch = lerp(patch, np.broadcast_to(rgb("olive_dk"), (h, w, 3)), tape[..., None] * 0.28)
    dirt = blobs(h, w, 210, n=6, radius=14)
    patch = lerp(patch, np.broadcast_to(rgb("dirt"), (h, w, 3)), dirt[..., None] * 0.3)
    img[y0:y1, x0:x1] = posterize(patch, 18)


def paint_stripes(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    yy, xx = np.mgrid[0:h, 0:w]
    stripe = ((xx + yy) // 7) % 2
    col = np.where(stripe[..., None] == 0, rgb("yellow"), rgb("black"))
    n = fine_noise(h, w, 99)
    col = lerp(col, np.broadcast_to(rgb("dirt"), (h, w, 3)), (n * 0.18)[..., None])
    dirt = blobs(h, w, 77, n=6, radius=16)
    col = lerp(col, np.broadcast_to(rgb("olive_dk"), (h, w, 3)), dirt * 0.35)
    img[y0:y1, x0:x1] = posterize(col, 16)


def paint_stencil(img, x0, y0, x1, y1):
    paint_material(img, x0, y0, x1, y1, rgb("olive_dk"), rgb("olive"), rgb("black"), 11, "paint")
    draw_text(img, x0 + 10, y0 + 96, "TAC-7", C["yellow"], scale=2)
    draw_text(img, x0 + 10, y0 + 72, "SLEDGE", C["yellow"], scale=2)
    draw_text(img, x0 + 10, y0 + 46, "UNIT 09", C["yellow"], scale=1)
    draw_text(img, x0 + 10, y0 + 30, "SN 4417", C["olive_hi"], scale=1)
    draw_text(img, x0 + 10, y0 + 16, "4.2 KG", C["olive_lt"], scale=1)
    rect_outline(img, x0 + 4, y0 + 4, x1 - 4, y1 - 4, C["yellow_dk"], 1)


def build():
    img = np.zeros((SIZE, SIZE, 3), dtype=np.float32)

    def px(name):
        return uv_to_px(REG[name])

    x0, y0, x1, y1 = px("HEAD")
    paint_head(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("HANDLE")
    paint_handle(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("FACE")
    paint_face(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("GRIP")
    paint_grip(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("METAL")
    paint_material(img, x0, y0, x1, y1, rgb("metal"), rgb("metal_hi"), rgb("metal_dk"), 4, "metal")

    x0, y0, x1, y1 = px("STRIPES")
    paint_stripes(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("STENCIL")
    paint_stencil(img, x0, y0, x1, y1)

    x0, y0, x1, y1 = px("RUBBER")
    paint_material(img, x0, y0, x1, y1, rgb("rubber"), rgb("rubber_lt"), rgb("black"), 3, "rubber")

    x0, y0, x1, y1 = px("WRAP")
    paint_material(img, x0, y0, x1, y1, rgb("cloth"), rgb("cloth_lt"), rgb("cloth_dk"), 88, "cloth")

    img = np.clip(img, 0, 255).astype(np.uint8)
    return img, REG


if __name__ == "__main__":
    pass
