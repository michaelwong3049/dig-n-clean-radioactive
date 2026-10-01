"""Bakes the textures RadFx.luau draws the dose with.

Run:  python tools/radfx-art/make_art.py   (needs Pillow, nothing else)
Writes PNGs to tools/radfx-art/png/. They are uploaded to Roblox by hand (or through
Studio) and their ids go in src/client/RadFxArt.luau. Every texture is seeded, so a
re-run produces the same pixels.

Anything the client re-tints (vignette, rot, snow, mote) is baked WHITE or greyscale,
because ImageColor3 multiplies. Blood never changes colour, so it is baked red.
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "png")
os.makedirs(OUT, exist_ok=True)

BLOOD = (122, 10, 14)
BLOOD_DARK = (58, 4, 6)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def smooth(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


# ── value noise ─────────────────────────────────────────────────────
def make_noise(seed):
    rng = random.Random(seed)
    perm = list(range(256))
    rng.shuffle(perm)
    perm = perm + perm

    def hv(x, y):
        return perm[(perm[x & 255] + y) & 255] / 255

    def vnoise(x, y):
        xi, yi = math.floor(x), math.floor(y)
        xf, yf = x - xi, y - yi
        u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
        a = hv(xi, yi) + (hv(xi + 1, yi) - hv(xi, yi)) * u
        b = hv(xi, yi + 1) + (hv(xi + 1, yi + 1) - hv(xi, yi + 1)) * u
        return a + (b - a) * v

    def fbm(x, y):
        s, a, f = 0.0, 0.5, 1.0
        for _ in range(5):
            s += a * vnoise(x * f, y * f)
            f *= 2.03
            a *= 0.5
        return s

    return fbm


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


# ── 1. vignette ─────────────────────────────────────────────────────
# White, alpha only. Stretched over the screen as an ellipse; ImageColor3 colours it.
def vignette():
    S = 512
    img = Image.new("RGBA", (S, S))
    px = img.load()
    stops = [(0.0, 0.0), (0.48, 0.0), (0.72, 0.35), (0.9, 0.8), (1.0, 1.0)]
    for y in range(S):
        for x in range(S):
            r = math.hypot((x + 0.5) / S * 2 - 1, (y + 0.5) / S * 2 - 1)
            a = 1.0
            for (p0, a0), (p1, a1) in zip(stops, stops[1:]):
                if r <= p1:
                    t = (r - p0) / (p1 - p0)
                    t = t * t * (3 - 2 * t)
                    a = a0 + (a1 - a0) * t
                    break
            px[x, y] = (255, 255, 255, round(a * 255))
    save(img, "vignette.png")


# ── 2. rot edge ─────────────────────────────────────────────────────
# A noise-broken edge with a pale burning rim. Greyscale: the rim is near white so the
# tint shows through it, the necrotic body is dark.
def rot(name, ox, oy, seed):
    fbm = make_noise(seed)
    S = 512
    img = Image.new("RGBA", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            nx, ny = x / S * 2 - 1, y / S * 2 - 1
            d = math.hypot(nx, ny)
            n = fbm(x / S * 5 + ox, y / S * 5 + oy)
            f = d + (n - 0.5) * 0.55
            a = smooth(0.74, 0.86, f)
            rim = math.exp(-(((f - 0.76) / 0.025) ** 2))
            spot = fbm(x / S * 14 + oy, y / S * 14 + ox)
            body = 0.42 * (1 - (0.35 + 0.4 * spot))
            v = body + (1 - body) * rim * 0.3
            alpha = clamp(a * 0.92 + rim * 0.35)
            g = round(clamp(v) * 255)
            px[x, y] = (g, g, g, round(alpha * 255))
    save(img, name)


# ── 3. sensor snow ──────────────────────────────────────────────────
# Tiles: single-pixel hits, a few 2x2 hits, and at most one short streak (a particle
# crossing the sensor at an angle). More streaks than that and the storm reads as RAIN. Re-offset every frame by the client, so it never repeats.
def snow(name, seed):
    rng = random.Random(seed)
    S = 256
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    for _ in range(90):
        a = 0.4 + rng.random() * 0.6
        g = 255 if rng.random() < 0.7 else 215
        x, y = rng.randrange(S), rng.randrange(S)
        img.putpixel((x, y), (g, g, g, round(a * 255)))
    for _ in range(18):
        a = round((0.5 + rng.random() * 0.5) * 255)
        x, y = rng.randrange(S - 2), rng.randrange(S - 2)
        d.rectangle([x, y, x + 1, y + 1], fill=(245, 245, 245, a))
    for _ in range(1):
        x, y = rng.random() * S, rng.random() * S
        ang, length = rng.random() * math.pi, 4 + rng.random() * 8
        steps = int(length * 2)
        for i in range(steps):
            t = i / steps
            px_, py_ = x + math.cos(ang) * length * t, y + math.sin(ang) * length * t
            ix, iy = int(px_) % S, int(py_) % S
            a = round(0.8 * (1 - t) * 255)
            old = img.getpixel((ix, iy))
            img.putpixel((ix, iy), (255, 255, 255, max(old[3], a)))
    save(img, name)


# ── 4. mote ─────────────────────────────────────────────────────────
def mote():
    S = 64
    img = Image.new("RGBA", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            r = math.hypot((x + 0.5) / S * 2 - 1, (y + 0.5) / S * 2 - 1)
            core = math.exp(-((r / 0.18) ** 2))
            halo = clamp(1 - r) ** 2 * 0.55
            a = clamp(core + halo)
            px[x, y] = (255, 255, 255, round(a * 255))
    save(img, "mote.png")


# ── 5. blood ────────────────────────────────────────────────────────
# Out of focus on purpose: it is on the inside of the visor, inches from your eye.
def splat(name, seed):
    rng = random.Random(seed)
    S = 256
    C = S / 2
    body = Image.new("RGBA", (S, S), BLOOD + (0,))
    d = ImageDraw.Draw(body)
    for _ in range(9):
        a, dist = rng.random() * 7, rng.random() * 30
        cx, cy = C + math.cos(a) * dist, C + math.sin(a) * dist
        rx, ry = 18 + rng.random() * 26, 13 + rng.random() * 20
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=BLOOD + (round((0.55 + rng.random() * 0.3) * 255),))
    d.ellipse([C - 20, C - 15, C + 20, C + 15], fill=BLOOD_DARK + (180,))
    body = body.filter(ImageFilter.GaussianBlur(3.2))

    drops = Image.new("RGBA", (S, S), BLOOD + (0,))
    d = ImageDraw.Draw(drops)
    for _ in range(16):
        a, dist = rng.random() * 7, 58 + rng.random() * 56
        cx, cy = C + math.cos(a) * dist, C + math.sin(a) * dist
        r = 1.5 + rng.random() * 5
        col = BLOOD if rng.random() < 0.5 else BLOOD_DARK
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (round((0.5 + rng.random() * 0.4) * 255),))
    drops = drops.filter(ImageFilter.GaussianBlur(1.2))
    save(Image.alpha_composite(body, drops), name)


def drip():
    W, H = 32, 256
    img = Image.new("RGBA", (W, H), BLOOD + (0,))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        col = tuple(round(BLOOD[i] + (BLOOD_DARK[i] - BLOOD[i]) * t) for i in range(3))
        for x in range(W):
            # A thin stream that ends in a heavier bead.
            half = 5 + 6 * math.exp(-(((y - (H - 14)) / 9) ** 2))
            dx = abs(x + 0.5 - W / 2)
            a = clamp((half - dx) / 1.6) * (0.78 + 0.17 * t)
            if y > H - 3:
                a = 0
            px[x, y] = col + (round(a * 255),)
    save(img.filter(ImageFilter.GaussianBlur(0.7)), "drip.png")


def blood_rim():
    S = 512
    img = Image.new("RGBA", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            r = math.hypot((x + 0.5) / S * 2 - 1, (y + 0.5) / S * 2 - 1)
            if r < 0.72:
                a, col = 0.0, BLOOD
            elif r < 0.92:
                t = smooth(0.72, 0.92, r)
                a, col = 0.55 * t, BLOOD
            else:
                t = clamp((r - 0.92) / 0.08)
                a = 0.55 + 0.4 * t
                col = tuple(round(BLOOD[i] + (BLOOD_DARK[i] - BLOOD[i]) * t) for i in range(3))
            px[x, y] = col + (round(a * 255),)
    save(img, "blood_rim.png")


if __name__ == "__main__":
    vignette()
    rot("rot_a.png", 3.1, 7.7, 0x51A7)
    rot("rot_b.png", 11.3, 1.9, 0x7E11)
    for i in range(3):
        snow(f"snow_{i + 1}.png", 900 + i)
    mote()
    for i in range(4):
        splat(f"splat_{i + 1}.png", 100 + i)
    drip()
    blood_rim()
