"""PS1-style 512 atlas for a field dynamite stick. No text, no glow."""
import math
import os

import numpy as np

OUT_DIR = r"C:\Users\luigi.manzi\Documents\blend\textures"
os.makedirs(OUT_DIR, exist_ok=True)
SIZE = 512

REG = {
    "PAPER": (0.00, 0.50, 0.50, 1.00),
    "CRIMP": (0.50, 0.50, 1.00, 1.00),
    "CORD": (0.00, 0.00, 0.50, 0.50),
    "TWINE": (0.50, 0.25, 1.00, 0.50),
    "METAL": (0.50, 0.00, 1.00, 0.25),
}

C = {
    "paper": (108, 30, 22),
    "paper_lt": (138, 48, 32),
    "paper_dk": (58, 16, 14),
    "paper_hot": (154, 58, 36),
    "kraft": (102, 70, 38),
    "kraft_dk": (62, 42, 24),
    "dirt": (34, 26, 18),
    "black": (10, 10, 9),
    "oil": (22, 18, 14),
    "cord": (32, 24, 18),
    "cord_lt": (48, 36, 26),
    "cord_dk": (14, 11, 9),
    "twine": (86, 66, 36),
    "twine_lt": (112, 88, 50),
    "twine_dk": (48, 36, 20),
    "metal": (48, 50, 46),
    "metal_dk": (22, 24, 22),
    "metal_hi": (78, 80, 74),
    "rust": (104, 50, 26),
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


def scratches(h, w, seed, n=40, axis="h"):
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w), dtype=np.float32)
    for _ in range(n):
        if axis == "h":
            y = int(rng.integers(0, h))
            x0 = int(rng.integers(0, w))
            length = int(rng.integers(6, max(7, w // 2)))
            thick = int(rng.choice([1, 1, 2]))
            val = float(rng.uniform(0.35, 1.0))
            for t in range(thick):
                yy = min(h - 1, y + t)
                img[yy, x0 : min(w, x0 + length)] = val
        else:
            x = int(rng.integers(0, w))
            y0 = int(rng.integers(0, h))
            length = int(rng.integers(8, max(9, h // 2)))
            val = float(rng.uniform(0.35, 1.0))
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


def posterize(img, steps=20):
    return np.round(img / 255.0 * (steps - 1)) / (steps - 1) * 255.0


def paint_paper(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    n1 = block_noise(h, w, 8, 11)
    n2 = block_noise(h, w, 4, 12)
    n3 = fine_noise(h, w, 13)
    n4 = block_noise(h, w, 18, 14)
    dirt = blobs(h, w, 15, n=8, radius=22)
    oil = blobs(h, w, 16, n=5, radius=14)
    crease = scratches(h, w, 17, n=18, axis="v")
    wrap = ((np.arange(w)[None, :] // 6) % 2).astype(np.float32)
    wrap = np.broadcast_to(wrap, (h, w))
    mix = n1 * 0.28 + n2 * 0.22 + n3 * 0.20 + n4 * 0.30
    col = lerp(np.broadcast_to(rgb("paper_dk"), (h, w, 3)), np.broadcast_to(rgb("paper_lt"), (h, w, 3)), mix)
    col = lerp(col, np.broadcast_to(rgb("paper"), (h, w, 3)), 0.42)
    col = lerp(col, np.broadcast_to(rgb("paper_dk"), (h, w, 3)), wrap[..., None] * 0.18)
    col = lerp(col, np.broadcast_to(rgb("kraft"), (h, w, 3)), ((n4 > 0.78) & (n3 > 0.55))[..., None] * 0.55)
    col = lerp(col, np.broadcast_to(rgb("dirt"), (h, w, 3)), dirt[..., None] * 0.32)
    col = lerp(col, np.broadcast_to(rgb("oil"), (h, w, 3)), oil[..., None] * 0.40)
    col = lerp(col, np.broadcast_to(rgb("paper_hot"), (h, w, 3)), crease[..., None] * 0.22)
    img[y0:y1, x0:x1] = posterize(col, 18)


def paint_crimp(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    n1 = block_noise(h, w, 6, 21)
    n3 = fine_noise(h, w, 22)
    dirt = blobs(h, w, 23, n=7, radius=16)
    fold = scratches(h, w, 24, n=26, axis="v")
    mix = n1 * 0.55 + n3 * 0.45
    col = lerp(np.broadcast_to(rgb("kraft_dk"), (h, w, 3)), np.broadcast_to(rgb("paper"), (h, w, 3)), mix)
    col = lerp(col, np.broadcast_to(rgb("paper_dk"), (h, w, 3)), fold[..., None] * 0.45)
    col = lerp(col, np.broadcast_to(rgb("dirt"), (h, w, 3)), dirt[..., None] * 0.35)
    col = lerp(col, np.broadcast_to(rgb("kraft"), (h, w, 3)), ((n3 > 0.82) & (n1 < 0.4))[..., None] * 0.4)
    img[y0:y1, x0:x1] = posterize(col, 16)


def paint_cord(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    n1 = block_noise(h, w, 5, 31)
    n3 = fine_noise(h, w, 32)
    fiber = scratches(h, w, 33, n=50, axis="v")
    mix = n1 * 0.5 + n3 * 0.5
    col = lerp(np.broadcast_to(rgb("cord_dk"), (h, w, 3)), np.broadcast_to(rgb("cord_lt"), (h, w, 3)), mix)
    col = lerp(col, np.broadcast_to(rgb("cord"), (h, w, 3)), 0.35)
    col = lerp(col, np.broadcast_to(rgb("cord_lt"), (h, w, 3)), fiber[..., None] * 0.28)
    specks = n3 > 0.93
    col = np.where(specks[..., None], np.broadcast_to(rgb("kraft_dk"), (h, w, 3)), col)
    img[y0:y1, x0:x1] = posterize(col, 14)


def paint_twine(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    yy, xx = np.mgrid[0:h, 0:w]
    stripe = ((xx + yy) // 5) % 2
    col = np.where(stripe[..., None] == 0, rgb("twine"), rgb("twine_dk"))
    n = fine_noise(h, w, 41)
    dirt = blobs(h, w, 42, n=5, radius=14)
    col = lerp(col, np.broadcast_to(rgb("twine_lt"), (h, w, 3)), (n * 0.22)[..., None])
    col = lerp(col, np.broadcast_to(rgb("dirt"), (h, w, 3)), dirt[..., None] * 0.3)
    img[y0:y1, x0:x1] = posterize(col, 14)


def paint_metal(img, x0, y0, x1, y1):
    h, w = y1 - y0, x1 - x0
    n1 = block_noise(h, w, 8, 51)
    n3 = fine_noise(h, w, 52)
    dirt = blobs(h, w, 53, n=6, radius=16)
    mix = n1 * 0.55 + n3 * 0.45
    col = lerp(np.broadcast_to(rgb("metal_dk"), (h, w, 3)), np.broadcast_to(rgb("metal_hi"), (h, w, 3)), mix)
    rusts = dirt > 0.55
    col = np.where(rusts[..., None], lerp(col, np.broadcast_to(rgb("rust"), (h, w, 3)), 0.65), col)
    specks = n3 > 0.92
    col = np.where(specks[..., None], np.broadcast_to(rgb("metal_hi"), (h, w, 3)), col)
    img[y0:y1, x0:x1] = posterize(col, 16)


def build():
    img = np.zeros((SIZE, SIZE, 3), dtype=np.float32)

    def px(name):
        return uv_to_px(REG[name])

    x0, y0, x1, y1 = px("PAPER")
    paint_paper(img, x0, y0, x1, y1)
    x0, y0, x1, y1 = px("CRIMP")
    paint_crimp(img, x0, y0, x1, y1)
    x0, y0, x1, y1 = px("CORD")
    paint_cord(img, x0, y0, x1, y1)
    x0, y0, x1, y1 = px("TWINE")
    paint_twine(img, x0, y0, x1, y1)
    x0, y0, x1, y1 = px("METAL")
    paint_metal(img, x0, y0, x1, y1)

    return np.clip(img, 0, 255).astype(np.uint8), REG


if __name__ == "__main__":
    pass
