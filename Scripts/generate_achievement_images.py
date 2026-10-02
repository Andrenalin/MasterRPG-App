#!/usr/bin/env python3
"""Draws the 1024x1024 Game Center achievement images in a pen-and-paper RPG sketch style.

Everything is procedural (Pillow + numpy): wobbly ink strokes, hatching, misregistered
watercolour washes and an aged paper background. No text is drawn except digits, so one
image serves every localization.

Usage:
    python3 Scripts/generate_achievement_images.py [out_dir] [name ...]
    python3 Scripts/generate_achievement_images.py --sheet sheet.png [out_dir] [name ...]

Names are the achievement names from Docu/GameCenterAchievements.csv.
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048          # working canvas, downsampled to 1024
K = S / 1000      # design units (0...1000) to pixels
INK = (38, 30, 27)
PAPER = (242, 230, 203)
COL = {
    "red": (181, 68, 55), "ochre": (216, 172, 80), "green": (112, 148, 90),
    "blue": (88, 122, 158), "brown": (158, 110, 74), "grey": (166, 162, 156),
    "purple": (126, 90, 138), "cream": (238, 228, 202), "gold": (224, 180, 62),
    "white": (252, 248, 238), "dark": (92, 82, 74), "sky": (150, 182, 205),
}


def rad(a):
    return math.radians(a)


# ---------------------------------------------------------------- geometry (design units)

def ell(cx, cy, rx, ry=None, rot=0.0, n=56, a0=0, a1=360):
    ry = rx if ry is None else ry
    full = abs(a1 - a0) >= 360
    out = []
    for i in range(n + (0 if full else 1)):
        a = rad(a0 + (a1 - a0) * i / n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        c, s = math.cos(rad(rot)), math.sin(rad(rot))
        out.append((cx + x * c - y * s, cy + x * s + y * c))
    return out


def bez(p0, p1, p2, p3, n=22):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((
            u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
        ))
    return out


def smooth(pts, closed=False, n=10):
    m = len(pts)
    out = []
    for i in range(m if closed else m - 1):
        p0 = pts[(i - 1) % m] if (closed or i > 0) else pts[0]
        p1 = pts[i]
        p2 = pts[(i + 1) % m]
        p3 = pts[(i + 2) % m] if (closed or i + 2 < m) else pts[-1]
        for k in range(n):
            t = k / n
            out.append(tuple(
                0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t
                       + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                       + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t**3)
                for j in (0, 1)))
    if not closed:
        out.append(pts[-1])
    return out


def xf(pts, ang=0.0, sc=1.0, ox=0.0, oy=0.0):
    c, s = math.cos(rad(ang)), math.sin(rad(ang))
    return [(ox + sc * (x * c - y * s), oy + sc * (x * s + y * c)) for x, y in pts]


def rrect(x0, y0, x1, y1, r):
    return (ell(x1 - r, y0 + r, r, a0=-90, a1=0, n=10) + ell(x1 - r, y1 - r, r, a0=0, a1=90, n=10)
            + ell(x0 + r, y1 - r, r, a0=90, a1=180, n=10) + ell(x0 + r, y0 + r, r, a0=180, a1=270, n=10))


def heart(cx, cy, sc, rot=0.0):
    """A heart whose tip sits on (cx, cy); `rot` turns it around that tip."""
    pts = []
    for i in range(60):
        t = 2 * math.pi * i / 60
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x, -y - 17))
    return xf(pts, rot, sc, cx, cy)


def star4(cx, cy, r):
    k = 0.2
    return xf([(0, -r), (r * k, -r * k), (r, 0), (r * k, r * k), (0, r), (-r * k, r * k),
               (-r, 0), (-r * k, -r * k)], 0, 1, cx, cy)


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


GLYPHS = {
    "0": [("e", None)],
    "1": [("l", [(0.2, 0.3), (0.5, 0.0), (0.5, 1.45)]), ("l", [(0.22, 1.45), (0.8, 1.45)])],
    "2": [("s", [(0.05, 0.35), (0.2, 0.08), (0.55, 0.0), (0.85, 0.2), (0.85, 0.5), (0.5, 0.9),
                 (0.05, 1.45)])],
}


def glyph_strokes(text, x, y, size, gap=1.1):
    strokes = []
    for ch in text:
        for kind, data in GLYPHS[ch]:
            if kind == "e":
                pts = ell(0.45, 0.725, 0.4, 0.7, n=30)
            elif kind == "l":
                pts = data
            else:
                pts = smooth(data, n=8) + [(0.95, 1.45)]
            strokes.append([(x + px * size, y + py * size) for px, py in pts])
        x += gap * size
    return strokes


# ---------------------------------------------------------------- paper

def noise_field(rng, cells):
    if cells >= S:
        f = rng.normal(size=(S, S)).astype(np.float32)
    else:
        small = Image.fromarray(rng.normal(size=(cells, cells)).astype(np.float32))
        f = np.asarray(small.resize((S, S), Image.BICUBIC), dtype=np.float32)
    return (f - f.mean()) / (f.std() + 1e-6)


def make_paper(seed):
    rng = np.random.default_rng(seed)
    lum = 1 + 0.030 * noise_field(rng, 9) + 0.018 * noise_field(rng, 70) + 0.012 * noise_field(rng, S)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / (S - 1) - 0.5
    d = np.sqrt(xx**2 + yy**2) * 2
    v = np.clip((d - 0.6) / 0.8, 0, 1) ** 1.6
    base = np.array(PAPER, dtype=np.float32) / 255
    paper = base[None, None, :] * lum[..., None]
    paper *= (1 - 0.22 * v)[..., None] * np.stack([1 - 0.0 * v, 1 - 0.05 * v, 1 - 0.14 * v], -1)
    fib = Image.new("L", (S, S), 0)
    fd = ImageDraw.Draw(fib)
    r2 = random.Random(seed)
    for _ in range(420):
        x, y = r2.uniform(0, S), r2.uniform(0, S)
        a = r2.uniform(0, 6.28)
        length = r2.uniform(20, 90)
        fd.line([(x, y), (x + length * math.cos(a), y + length * math.sin(a))], fill=r2.randint(10, 40), width=1)
    fib = np.asarray(fib.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255
    paper *= (1 - 0.35 * fib)[..., None]
    return np.clip(paper, 0, 1)


# ---------------------------------------------------------------- the sketch canvas

class Sketch:
    def __init__(self, seed):
        self.seed = seed
        self.rng = random.Random(seed)
        self.ink = Image.new("L", (S, S), 0)
        self.d = ImageDraw.Draw(self.ink)
        self.wash = Image.new("RGB", (S, S), (255, 255, 255))
        n = Image.fromarray(np.random.default_rng(seed + 1).random((22, 22)).astype(np.float32))
        n = np.asarray(n.resize((S, S), Image.BICUBIC), dtype=np.float32)
        self.tex = Image.fromarray((225 + 30 * np.clip(n, 0, 1)).astype(np.uint8))

    # -- primitives
    def _resample(self, pts, step):
        out = [pts[0]]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            length = math.hypot(x1 - x0, y1 - y0)
            n = max(1, int(length / step))
            for i in range(1, n + 1):
                out.append((x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n))
        return out

    def _wobble(self, pts, amp):
        p1, p2, p3 = (self.rng.uniform(0, 6.28) for _ in range(3))
        out = []
        for i, (x, y) in enumerate(pts):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            tx, ty = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(tx, ty) or 1
            nx, ny = -ty / ln, tx / ln
            o = amp * (0.6 * math.sin(i * 0.23 + p1) + 0.4 * math.sin(i * 0.57 + p2)
                       + 0.25 * math.sin(i * 0.09 + p3)) + self.rng.uniform(-amp, amp) * 0.12
            out.append((x + nx * o, y + ny * o))
        return out

    def stroke(self, pts, w=5.0, jit=1.5, closed=False, passes=2, step=6.0):
        pts = [(x * K, y * K) for x, y in pts]
        if closed:
            pts = pts + [pts[0]]
        base = self._resample(pts, step * K)
        for ps in reversed(range(passes)):
            path = base
            if ps > 0 and closed and len(base) > 8:
                sh = self.rng.randrange(1, len(base) - 4)
                path = base[sh:-1] + base[:sh + 3]
            path = self._wobble(path, jit * K * (1 + 0.7 * ps))
            ww = w * K * (1.0 if ps == 0 else 0.5)
            fill = 255 if ps == 0 else 150
            phase = self.rng.uniform(0, 6.28)
            for i in range(len(path) - 1):
                width = max(1, int(ww * (0.82 + 0.28 * math.sin(i * 0.19 + phase))))
                self.d.line([path[i], path[i + 1]], fill=fill, width=width)
                r = width / 2
                x, y = path[i]
                self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def mask(self, pts, off=(0, 0)):
        m = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m).polygon([((x + off[0]) * K, (y + off[1]) * K) for x, y in pts], fill=255)
        return m

    def fill(self, pts, color, a=0.55, off=None, edge=0.5):
        off = off or (self.rng.uniform(-5, 5), self.rng.uniform(-5, 5))
        m = self.mask(pts, off)
        bb = m.getbbox()
        if not bb:
            return
        pad = 40
        bb = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(S, bb[2] + pad), min(S, bb[3] + pad))
        mc = m.crop(bb)
        blur = mc.filter(ImageFilter.GaussianBlur(4.5 * K))
        edge_img = ImageChops.subtract(mc, blur)
        alpha = ImageChops.add(mc.point(lambda v: int(v * a)), edge_img.point(lambda v: int(v * edge)))
        alpha = ImageChops.multiply(alpha, self.tex.crop(bb))
        region = self.wash.crop(bb)
        tint = ImageChops.multiply(region, Image.new("RGB", region.size, COL[color]))
        self.wash.paste(Image.composite(tint, region, alpha), bb[:2])

    def hatch(self, pts, angle=45, gap=7.0, w=1.5, band=(10, 10), full=False, jit=0.8):
        m = self.mask(pts)
        region = m if full else ImageChops.subtract(m, self.mask(pts, off=(-band[0], -band[1])))
        bb = region.getbbox()
        if not bb:
            return
        x0, y0, x1, y1 = bb
        tmp = Image.new("L", (x1 - x0, y1 - y0), 0)
        td = ImageDraw.Draw(tmp)
        cx, cy = (x1 - x0) / 2, (y1 - y0) / 2
        D = math.hypot(x1 - x0, y1 - y0) / 2 + 6
        a = rad(angle)
        dx, dy = math.cos(a), math.sin(a)
        nx, ny = -dy, dx
        s = -D
        while s < D:
            t = -D
            prev = None
            while t <= D:
                j = self.rng.uniform(-jit, jit) * K
                p = (cx + nx * (s + j) + dx * t, cy + ny * (s + j) + dy * t)
                if prev:
                    td.line([prev, p], fill=255, width=max(1, int(w * K)))
                prev = p
                t += 36.0
            s += gap * K * self.rng.uniform(0.85, 1.15)
        tmp = ImageChops.multiply(tmp, region.crop(bb))
        cur = self.ink.crop(bb)
        self.ink.paste(ImageChops.lighter(cur, tmp), (x0, y0))

    def solid(self, pts):
        self.d.polygon([(x * K, y * K) for x, y in pts], fill=255)
        self.stroke(pts, w=2.2, jit=0.8, closed=True, passes=1)

    def erase(self, pts, grow=6):
        P = [(x * K, y * K) for x, y in pts]
        m = Image.new("L", (S, S), 0)
        md = ImageDraw.Draw(m)
        md.polygon(P, fill=255)
        md.line(P + [P[0]], fill=255, width=int(grow * 2 * K), joint="curve")
        self.ink.paste(0, mask=m)
        self.wash.paste((255, 255, 255), mask=m)

    # -- conveniences
    def shape(self, pts, color=None, w=5.0, shade=None, a=0.55, jit=1.5, closed=True, hatch_gap=7.0):
        if color:
            self.fill(pts, color, a)
        if shade:
            self.hatch(pts, band=shade, gap=hatch_gap)
        self.stroke(pts, w=w, jit=jit, closed=closed)

    def line(self, a, b, w=4.0, jit=1.2):
        self.stroke([a, b], w=w, jit=jit, passes=1)

    def dot(self, cx, cy, r):
        self.solid(ell(cx, cy, r, n=18))

    def sparkle(self, cx, cy, r, color="gold"):
        pts = star4(cx, cy, r)
        self.fill(pts, color, 0.7)
        self.stroke(pts, w=3, jit=0.8, closed=True, passes=1)

    def ground(self, cx, y, w):
        for i in range(3):
            yy = y + i * 14
            ww = w * (1 - i * 0.22)
            self.stroke([(cx - ww / 2, yy), (cx + ww / 2, yy + self.rng.uniform(-3, 3))], w=3, jit=2.5, passes=1)

    def rays(self, cx, cy, r0, r1, n, start=0, span=360, w=3.5):
        for i in range(n):
            a = rad(start + span * i / n + self.rng.uniform(-3, 3))
            r = r1 * self.rng.uniform(0.85, 1.1)
            self.stroke([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)),
                         (cx + r * math.cos(a), cy + r * math.sin(a))], w=w, jit=1, passes=1)

    def frame(self):
        self.stroke(rrect(36, 36, 964, 964, 200), w=5, jit=2.4, closed=True)
        self.stroke(rrect(54, 54, 946, 946, 186), w=2.6, jit=3.2, closed=True, passes=1)

    # -- output
    def finish(self, path):
        paper = make_paper(self.seed)
        img = paper * (np.asarray(self.wash, dtype=np.float32) / 255)
        ink = self.ink.filter(ImageFilter.GaussianBlur(1.1))
        a = np.asarray(ink, dtype=np.float32) / 255
        grain = Image.fromarray(np.random.default_rng(self.seed + 7).integers(0, 255, (S, S), dtype=np.uint8))
        g = np.asarray(grain.filter(ImageFilter.GaussianBlur(1.3)), dtype=np.float32) / 255
        g = (g - g.mean()) / (g.std() + 1e-6)
        a = np.clip(a * np.clip(0.9 + 0.09 * g, 0.55, 1.05), 0, 1)
        halo = np.asarray(self.ink.filter(ImageFilter.GaussianBlur(6)), dtype=np.float32) / 255
        img = img * (1 - 0.10 * halo[..., None])
        inkc = np.array(INK, dtype=np.float32) / 255
        img = img * (1 - a[..., None]) + inkc * a[..., None]
        out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
        out = out.resize((1024, 1024), Image.LANCZOS)
        out.save(path, "PNG", optimize=True)
        return out


# ---------------------------------------------------------------- reusable drawings

def d20(s, cx, cy, r, color, digit=None, rot=0):
    V = [(cx + r * math.cos(rad(-90 + 60 * k + rot)), cy + r * math.sin(rad(-90 + 60 * k + rot))) for k in range(6)]
    T = [(cx + 0.5 * r * math.cos(rad(a + rot)), cy + 0.5 * r * math.sin(rad(a + rot))) for a in (-90, 30, 150)]
    s.fill(V, color, 0.62)
    s.fill(T, "cream", 0.3)
    s.hatch(V, band=(r * 0.16, r * 0.16), gap=6)
    s.stroke(V, w=6, closed=True)
    s.stroke(T, w=4.5, closed=True)
    for ti, vs in ((0, (5, 0, 1)), (1, (1, 2, 3)), (2, (3, 4, 5))):
        for v in vs:
            s.line(T[ti], V[v], w=3.6)
    if digit:
        size = r * 0.26
        width = (len(digit) - 1) * 1.1 * size + 0.9 * size
        for st in glyph_strokes(digit, cx - width / 2, cy - 0.45 * size - 0.1 * r, size):
            s.stroke(st, w=4.2, jit=0.7, passes=1, step=3)


PIPS = {
    1: [(.5, .5)], 2: [(.28, .28), (.72, .72)], 3: [(.25, .25), (.5, .5), (.75, .75)],
    4: [(.28, .28), (.72, .28), (.28, .72), (.72, .72)],
    5: [(.28, .28), (.72, .28), (.5, .5), (.28, .72), (.72, .72)],
    6: [(.28, .24), (.72, .24), (.28, .5), (.72, .5), (.28, .76), (.72, .76)],
}


def cube(s, cx, cy, sz, pips=(1, 2, 3), color="cream", wline=5):
    A = (cx, cy - sz)
    B = (cx + .866 * sz, cy - .5 * sz)
    C = (cx, cy)
    D = (cx - .866 * sz, cy - .5 * sz)
    E = (cx, cy + sz)
    F = (cx + .866 * sz, cy + .5 * sz)
    G = (cx - .866 * sz, cy + .5 * sz)
    top, left, right = [A, B, C, D], [D, C, E, G], [C, B, F, E]
    s.fill(top, color, 0.25)
    s.fill(left, color, 0.55)
    s.fill(right, color, 0.7)
    s.hatch(right, angle=60, gap=8, full=True, w=1.2)
    s.hatch(left, band=(sz * .15, sz * .15), gap=8)
    for f in (top, left, right):
        s.stroke(f, w=wline, closed=True)

    def face(origin, e1, e2, n):
        for u, v in PIPS[n]:
            pts = []
            for t in range(16):
                a = 2 * math.pi * t / 16
                uu, vv = u + 0.1 * math.cos(a), v + 0.1 * math.sin(a)
                pts.append((origin[0] + uu * e1[0] + vv * e2[0], origin[1] + uu * e1[1] + vv * e2[1]))
            s.solid(pts)

    face(D, (C[0] - D[0], C[1] - D[1]), (A[0] - D[0], A[1] - D[1]), pips[0])
    face(D, (C[0] - D[0], C[1] - D[1]), (G[0] - D[0], G[1] - D[1]), pips[1])
    face(C, (B[0] - C[0], B[1] - C[1]), (E[0] - C[0], E[1] - C[1]), pips[2])


def sword(s, cx, cy, ang, length):
    m = -0.4 * length + 26
    sn, cs = math.sin(rad(ang)), math.cos(rad(ang))
    ox, oy = cx + m * sn, cy - m * cs
    blade = [(0, -length), (-21, -length * .84), (-21, 0), (21, 0), (21, -length * .84)]
    guard = rect(-72, 0, 72, 24)
    grip = rect(-10, 24, 10, 24 + length * .2)
    pom = ell(0, 24 + length * .2 + 16, 17, n=20)
    s.shape(xf(blade, ang, 1, ox, oy), "grey", w=4.5, shade=(8, 8), a=.5)
    s.stroke(xf([(0, -length * .86), (0, -10)], ang, 1, ox, oy), w=2.2, jit=.8, passes=1)
    s.shape(xf(grip, ang, 1, ox, oy), "brown", w=4, a=.7)
    s.shape(xf(guard, ang, 1, ox, oy), "ochre", w=4.5, a=.7)
    s.shape(xf(pom, ang, 1, ox, oy), "ochre", w=4, a=.7)


def figure(s, cx, base, sc, kind, body):
    sh = ell(cx, base, 92 * sc, 100 * sc, a0=180, a1=360, n=24)
    hy = base - 100 * sc - 46 * sc
    head = ell(cx, hy, 60 * sc, 64 * sc, n=30)
    if kind == "rogue":
        hood = smooth([(cx - 88 * sc, hy + 70 * sc), (cx - 82 * sc, hy - 30 * sc), (cx - 20 * sc, hy - 105 * sc),
                       (cx + 18 * sc, hy - 122 * sc), (cx + 82 * sc, hy - 30 * sc), (cx + 88 * sc, hy + 70 * sc)], n=8)
        s.shape(hood, "dark", w=4.5, a=.7)
    s.erase(sh + [(cx - 92 * sc, base)], grow=2)
    s.shape(sh + [(cx - 92 * sc, base)], body, w=5, shade=(14 * sc, 14 * sc), a=.6)
    s.erase(head, grow=2)
    s.shape(head, "cream", w=4.5, a=.45)
    for dx in (-22, 22):
        s.dot(cx + dx * sc, hy + 2 * sc, 4.2 * sc)
    s.stroke(ell(cx, hy + 16 * sc, 22 * sc, 14 * sc, a0=20, a1=160, n=10), w=3, jit=.5, passes=1)
    if kind == "wizard":
        s.shape(ell(cx, hy - 40 * sc, 100 * sc, 20 * sc, n=30), "blue", w=4.5, a=.7)
        cone = smooth([(cx - 66 * sc, hy - 42 * sc), (cx - 30 * sc, hy - 120 * sc), (cx + 5 * sc, hy - 190 * sc),
                       (cx + 55 * sc, hy - 215 * sc), (cx + 40 * sc, hy - 160 * sc), (cx + 66 * sc, hy - 42 * sc)], n=6)
        s.shape(cone, "blue", w=4.5, shade=(12 * sc, 12 * sc), a=.7)
        s.sparkle(cx - 5 * sc, hy - 100 * sc, 14 * sc)
    elif kind == "warrior":
        helmet = ell(cx, hy - 6 * sc, 70 * sc, 66 * sc, a0=180, a1=360, n=24)
        s.shape(helmet + [(cx + 70 * sc, hy - 6 * sc)], "grey", w=5, shade=(10 * sc, 10 * sc), a=.7)
        for sg in (-1, 1):
            horn = smooth([(cx + sg * 66 * sc, hy - 30 * sc), (cx + sg * 100 * sc, hy - 40 * sc),
                           (cx + sg * 118 * sc, hy - 100 * sc), (cx + sg * 86 * sc, hy - 62 * sc),
                           (cx + sg * 70 * sc, hy - 54 * sc)], n=6)
            s.shape(horn, "cream", w=4, a=.6)
        s.stroke([(cx, hy - 70 * sc), (cx, hy - 5 * sc)], w=5 * sc, jit=.6, passes=1)
    elif kind == "cleric":
        s.shape(ell(cx, hy - 92 * sc, 56 * sc, 14 * sc, n=30), "gold", w=4.5, a=.8)
    elif kind == "bard":
        cap = ell(cx, hy - 22 * sc, 68 * sc, 48 * sc, a0=180, a1=360, n=20)
        s.shape(cap + [(cx + 68 * sc, hy - 22 * sc), (cx + 110 * sc, hy - 14 * sc), (cx - 68 * sc, hy - 14 * sc)],
                "green", w=4.5, a=.7)
        feather = smooth([(cx + 30 * sc, hy - 58 * sc), (cx + 70 * sc, hy - 120 * sc), (cx + 120 * sc, hy - 150 * sc),
                          (cx + 100 * sc, hy - 100 * sc), (cx + 60 * sc, hy - 62 * sc)], n=6)
        s.shape(feather, "red", w=3.5, a=.7)


# ---------------------------------------------------------------- the 20 achievements

def first_game(s):
    s.ground(500, 872, 360)
    bowl = ell(500, 790, 205, 72, a0=0, a1=180, n=24) + [(295, 790)]
    s.shape(bowl, "ochre", shade=(18, 18), a=.65)
    s.shape(ell(500, 790, 205, 38, n=40), "ochre", w=5, a=.5)
    s.shape(ell(330, 790, 40, 26, n=24), "ochre", w=4, a=.3)
    s.shape(rect(440, 400, 560, 770), "cream", shade=(24, 24), a=.5)
    s.shape(ell(500, 400, 60, 14, n=30), "white", w=4.5, a=.4)
    drip = smooth([(556, 405), (572, 440), (566, 480), (552, 470), (550, 430)], n=6)
    s.shape(drip, "white", w=3.5, a=.5)
    s.line((500, 400), (500, 372), w=5)
    flame = smooth([(500, 218), (538, 292), (546, 338), (500, 372), (454, 338), (464, 290)], closed=True, n=8)
    s.shape(flame, "ochre", w=5, a=.8)
    inner = smooth([(500, 290), (520, 330), (500, 358), (480, 330)], closed=True, n=8)
    s.shape(inner, "red", w=3, a=.7)
    s.rays(500, 305, 135, 180, 9, start=-170, span=160, w=3.5)
    s.sparkle(715, 250, 26)
    s.sparkle(290, 300, 20)


def regular_adventurer(s):
    s.ground(500, 850, 420)
    body = [(335, 410), (665, 410), (650, 770), (625, 790), (375, 790), (350, 770)]
    s.shape(body, "brown", w=5.5, shade=(30, 30), a=.65)
    for y in (500, 690):
        s.stroke(bez((338 + (y - 410) * .03, y), (450, y + 22), (550, y + 22), (662 - (y - 410) * .03, y)), w=6, jit=.8)
        s.fill([(338, y - 12), (662, y - 12), (660, y + 18), (340, y + 18)], "grey", .45)
    for x in (420, 500, 580):
        s.stroke([(x, 520), (x, 675)], w=2.5, jit=1.2, passes=1)
        s.stroke([(x, 715), (x, 780)], w=2.5, jit=1.2, passes=1)
    handle = smooth([(662, 470), (770, 480), (805, 560), (770, 660), (650, 690)], n=8)
    s.stroke(handle, w=14, jit=1.2)
    s.stroke(smooth([(662, 500), (748, 510), (768, 565), (742, 640), (655, 660)], n=8), w=5, jit=1)
    foam = smooth([(325, 415), (305, 360), (350, 310), (400, 335), (440, 288), (505, 300), (545, 275),
                   (600, 305), (650, 295), (695, 350), (675, 415)], closed=True, n=8)
    s.shape(foam, "white", w=5, shade=(14, 14), a=.4)
    for cx_, cy_, r in ((470, 330, 14), (565, 340, 11), (400, 365, 12), (625, 360, 12)):
        s.stroke(ell(cx_, cy_, r, n=14), w=2.6, jit=.6, passes=1)
    s.stroke(smooth([(330, 415), (322, 470), (336, 505)], n=6), w=5, jit=1)
    for x, y, r in ((300, 250, 16), (700, 235, 12), (350, 200, 10)):
        s.stroke(ell(x, y, r, n=14), w=3, jit=.6, passes=1)


def veteran_adventurer(s):
    sword(s, 500, 510, 42, 700)
    sword(s, 500, 510, -42, 700)
    outline = ([(320, 320), (680, 320), (680, 520)] + bez((680, 520), (680, 650), (590, 735), (500, 800))
               + bez((500, 800), (410, 735), (320, 650), (320, 520)))
    outline = [(500 + (x - 500) * .9, 560 + (y - 560) * .9) for x, y in outline]
    s.erase(outline, grow=8)
    s.fill(outline, "red", .6)
    inner = [(500 + (x - 500) * .86, 560 + (y - 560) * .86 + 6) for x, y in outline]
    s.hatch(outline, band=(26, 26), gap=7)
    s.stroke(outline, w=7, jit=1.6, closed=True)
    s.stroke(inner, w=3.2, jit=1.4, closed=True, passes=1)
    band = [(360, 440), (500, 505), (640, 440), (640, 515), (500, 580), (360, 515)]
    s.fill(band, "gold", .65)
    for y0 in (440, 515, 590):
        s.stroke([(360, y0), (500, y0 + 65), (640, y0)], w=5 if y0 != 515 else 4, jit=1)
    s.sparkle(500, 385, 24)
    s.sparkle(880, 540, 20)
    s.sparkle(120, 540, 20)


def storyteller(s):
    s.ground(500, 850, 520)
    cover = [(130, 395), (130, 770), (500, 790), (870, 770), (870, 395)]
    s.shape(cover, "brown", w=5.5, a=.7, shade=(20, 20))
    left = bez((160, 380), (260, 325), (400, 335), (500, 405)) + [(500, 740)] + bez((500, 740), (400, 685), (260, 690), (160, 735))
    right = bez((500, 405), (600, 335), (740, 325), (840, 380)) + [(840, 735)] + bez((840, 735), (740, 690), (600, 685), (500, 740))
    s.shape(left, "cream", w=5, a=.45)
    s.shape(right, "cream", w=5, a=.45, shade=(16, 16))
    for i in range(6):
        y = 440 + i * 46
        s.stroke([(205, y - 10 + i * 2), (320, y - 18 + i * 2), (460, y + 10 - i * 2)], w=2.6, jit=1.2, passes=1)
        if i < 3:
            s.stroke([(550, y + 4), (680, y - 22), (790, y - 8)], w=2.6, jit=1.2, passes=1)
    s.stroke(smooth([(560, 600), (610, 640), (700, 640), (780, 610)], n=8), w=2.6, jit=1.2, passes=1)
    s.stroke([(500, 405), (500, 740)], w=5, jit=1.2)
    vane = smooth([(610, 470), (660, 330), (760, 205), (880, 130), (862, 250), (800, 350), (710, 430)], closed=True, n=8)
    s.erase(vane, grow=5)
    s.shape(vane, "blue", w=4.5, a=.6)
    s.stroke([(612, 472), (700, 340), (790, 230), (872, 132)], w=5, jit=1)
    for t in (.25, .4, .55, .7, .85):
        px, py = 612 + (872 - 612) * t, 472 + (132 - 472) * t
        s.line((px, py), (px + 52 * (1 - t) + 18, py + 32 * (1 - t) + 20), w=2.4, jit=.6)
        s.line((px, py), (px - 30 * (1 - t) - 10, py - 40 * (1 - t) - 18), w=2.4, jit=.6)
    s.sparkle(255, 260, 22)
    s.sparkle(440, 200, 16)


def loyal_hero(s):
    s.ground(450, 862, 400)
    for feather in ([(500, 265), (468, 200), (478, 130), (540, 88), (606, 90), (566, 142), (548, 204), (538, 264)],
                    [(520, 266), (540, 190), (600, 128), (690, 112), (666, 172), (622, 218), (572, 264)],
                    [(540, 270), (600, 216), (684, 200), (726, 234), (664, 258), (592, 282)]):
        s.shape(smooth(feather, closed=True, n=8), "red", w=4.5, a=.65, shade=(12, 12))
    helm = smooth([(360, 520), (350, 385), (420, 285), (500, 255), (580, 285), (650, 385), (640, 525),
                   (640, 700), (565, 765), (500, 775), (435, 765), (360, 700)], closed=True, n=8)
    s.shape(helm, "grey", w=6.5, shade=(34, 34), a=.7)
    s.solid(rect(392, 438, 608, 478))
    s.stroke([(500, 258), (500, 436)], w=5, jit=1)
    s.stroke([(500, 480), (500, 720)], w=4, jit=1.2)
    for y in (540, 590, 640):
        for x in (435, 565):
            s.dot(x, y, 7)
    s.stroke(smooth([(372, 520), (420, 500), (500, 485), (580, 500), (628, 520)], n=6), w=4, jit=1, passes=1)
    h = heart(770, 812, 4.6, 0)
    s.erase(h, grow=5)
    s.shape(h, "red", w=5.5, a=.75, shade=(12, 12))
    s.sparkle(255, 330, 22)
    s.sparkle(790, 400, 18)


def campaigner(s):
    s.ground(500, 862, 560)
    s.shape([(280, 770), (500, 330), (720, 770)], "brown", w=6.5, shade=(46, 46), a=.65)
    s.solid([(440, 770), (500, 585), (560, 770)])
    s.stroke([(500, 330), (500, 585)], w=3.5, jit=1, passes=1)
    s.stroke([(500, 330), (172, 800)], w=2.4, jit=1.2, passes=1)
    s.stroke([(500, 330), (835, 800)], w=2.4, jit=1.2, passes=1)
    for x in (172, 835):
        s.stroke([(x, 790), (x, 815)], w=5, jit=.5, passes=1)
    s.stroke([(500, 330), (500, 150)], w=5, jit=1)
    flag = smooth([(500, 150), (570, 150), (650, 178), (590, 205), (500, 222)], n=6)
    s.shape(flag, "red", w=4.5, a=.7)
    s.sparkle(780, 250, 22)
    s.sparkle(230, 330, 18)
    fl = smooth([(846, 700), (876, 745), (862, 780), (830, 780), (815, 740)], closed=True, n=8)
    s.shape(fl, "ochre", w=4, a=.8)
    s.shape(smooth([(842, 738), (856, 765), (835, 770)], closed=True, n=6), "red", w=2.5, a=.7)
    s.stroke([(805, 800), (885, 770)], w=8, jit=1, passes=1)
    s.stroke([(805, 770), (885, 800)], w=8, jit=1, passes=1)
    s.rays(846, 700, 62, 92, 5, start=-150, span=120, w=3)


def well_travelled(s):
    s.fill(ell(500, 500, 300, n=60), "cream", .45)
    s.stroke(ell(500, 500, 330, n=70), w=6, jit=1.6, closed=True)
    s.stroke(ell(500, 500, 296, n=70), w=3.6, jit=1.6, closed=True)
    for i in range(48):
        a = rad(i * 7.5)
        r0 = 296 if i % 4 else 286
        s.line((500 + r0 * math.cos(a), 500 + r0 * math.sin(a)), (500 + 330 * math.cos(a), 500 + 330 * math.sin(a)), w=2.4, jit=.5)
    diag = []
    for k in range(4):
        diag.append((500 + 215 * math.cos(rad(45 + 90 * k)), 500 + 215 * math.sin(rad(45 + 90 * k))))
        diag.append((500 + 55 * math.cos(rad(90 + 90 * k)), 500 + 55 * math.sin(rad(90 + 90 * k))))
    s.shape(diag, "grey", w=4, shade=(10, 10), a=.55)
    pts = [(500, 175), (535, 465), (825, 500), (535, 535), (500, 825), (465, 535), (175, 500), (465, 465)]
    s.fill(pts, "ochre", .5)
    tips = [(500, 175), (825, 500), (500, 825), (175, 500)]
    inner = [(535, 465), (535, 535), (465, 535), (465, 465)]
    for i, tip in enumerate(tips):
        s.fill([tip, inner[i], (500, 500)], "red" if i % 2 == 0 else "brown", .65)
    s.stroke(pts, w=5.5, jit=1.2, closed=True)
    for tip in tips:
        s.line(tip, (500, 500), w=3, jit=1)
    s.shape([(500, 108), (470, 165), (530, 165)], "red", w=4, a=.7)
    s.dot(500, 500, 14)
    s.sparkle(805, 220, 22)
    s.sparkle(190, 800, 18)


def dice_initiate(s):
    s.ground(500, 868, 420)
    cube(s, 520, 500, 255, pips=(1, 2, 3), color="cream", wline=6)
    for r, a0, a1 in ((150, 140, 215), (190, 150, 210), (230, 155, 205)):
        s.stroke(ell(520, 520, r, n=14, a0=a0, a1=a1), w=3, jit=.8, passes=1)
    s.sparkle(780, 230, 24)
    s.sparkle(210, 250, 18)
    s.rays(520, 500, 330, 372, 5, start=-70, span=70, w=3)


def dice_legend(s):
    for sg in (-1, 1):
        for i in range(12):
            ang = 100 + i * 10.5 if sg < 0 else 80 - i * 10.5
            x = 500 + 300 * math.cos(rad(ang))
            y = 480 + 300 * math.sin(rad(ang))
            tang = ang + 90 + (35 if sg < 0 else -35)
            s.shape(xf(ell(0, 0, 44, 17, n=18), tang, 1, x, y), "green", w=3.8, a=.7, shade=(5, 5))
            s.stroke(xf([(-40, 0), (40, 0)], tang, 1, x, y), w=2, jit=.4, passes=1)
        s.stroke(ell(500, 480, 300, n=20, a0=100, a1=215) if sg < 0 else ell(500, 480, 300, n=20, a0=-35, a1=80),
                 w=3, jit=1, passes=1)
    d20(s, 500, 480, 215, "purple")
    s.sparkle(500, 118, 36)
    s.sparkle(280, 170, 20)
    s.sparkle(720, 170, 20)
    s.shape([(500, 790), (440, 860), (400, 835), (440, 790)], "red", w=4, a=.7)
    s.shape([(500, 790), (560, 860), (600, 835), (560, 790)], "red", w=4, a=.7)
    s.dot(500, 792, 12)


def critical_moment(s):
    spikes = []
    for i in range(32):
        a = rad(i * 360 / 32 - 90)
        r = 410 if i % 2 == 0 else 300
        spikes.append((500 + r * math.cos(a), 500 + r * math.sin(a)))
    s.shape(spikes, "gold", w=5.5, a=.65, shade=(22, 22))
    s.stroke(ell(500, 500, 270, n=60), w=3, jit=2, closed=True, passes=1)
    d20(s, 500, 505, 185, "red", digit="20")
    s.sparkle(190, 200, 30)
    s.sparkle(810, 170, 24)
    s.sparkle(830, 820, 28)
    s.sparkle(170, 800, 20)


def unlucky_hero(s):
    s.ground(500, 868, 380)
    d20(s, 500, 640, 190, "grey", digit="1")
    s.stroke([(405, 480), (440, 530), (418, 560), (470, 610), (455, 640)], w=3.8, jit=.6, passes=1)
    cloud = smooth([(255, 372), (232, 305), (285, 258), (345, 268), (385, 205), (470, 195), (525, 235), (590, 205),
                    (655, 240), (665, 300), (725, 318), (735, 372), (680, 405), (300, 405)], closed=True, n=8)
    s.shape(cloud, "dark", w=6, shade=(30, 30), a=.55)
    for x in (300, 340, 380, 610, 650, 690):
        s.stroke([(x, 420 + (x % 20)), (x - 14, 475 + (x % 17))], w=3, jit=.6, passes=1)
    bolt = [(535, 395), (465, 485), (512, 485), (452, 585), (590, 462), (538, 462), (588, 395)]
    s.erase(bolt, grow=6)
    s.shape(bolt, "gold", w=5, a=.8)
    s.sparkle(780, 600, 16, "grey")


def multimedia_maestro(s):
    s.ground(500, 892, 560)
    s.shape(xf(rect(-150, -120, 150, 120), -7, 1, 330, 340), "brown", w=6, a=.6, shade=(12, 12))
    inner = xf(rect(-122, -92, 122, 92), -7, 1, 330, 340)
    s.fill(inner, "sky", .6)
    s.stroke(inner, w=3.5, jit=1, closed=True)
    mtn = xf([(-122, 92), (-60, -10), (-15, 45), (50, -40), (122, 92)], -7, 1, 330, 340)
    s.shape(mtn, "green", w=3.8, a=.7, shade=(10, 10))
    sx, sy = xf([(70, -52)], -7, 1, 330, 340)[0]
    s.shape(ell(sx, sy, 22, n=20), "gold", w=3.5, a=.8)
    h1, h2 = (640, 475), (745, 440)
    for h in (h1, h2):
        s.solid(ell(h[0], h[1], 33, 23, rot=-20, n=24))
    s.stroke([(h1[0] + 32, h1[1] - 8), (h1[0] + 32, 290)], w=6, jit=.8)
    s.stroke([(h2[0] + 32, h2[1] - 8), (h2[0] + 32, 255)], w=6, jit=.8)
    s.solid([(h1[0] + 30, 290), (h2[0] + 34, 255), (h2[0] + 34, 285), (h1[0] + 30, 322)])
    s.sparkle(840, 330, 18)
    scroll = rect(330, 640, 670, 790)
    s.fill(scroll, "cream", .55)
    s.hatch(scroll, band=(14, 14), gap=7)
    s.stroke(scroll, w=5.5, jit=1.3, closed=True)
    for cx_ in (330, 670):
        s.shape(ell(cx_, 715, 28, 86, n=28), "cream", w=5, a=.6)
        s.stroke(ell(cx_, 715, 12, 44, n=20), w=3, jit=.6, passes=1)
    s.stroke(smooth([(390, 740), (450, 690), (520, 745), (580, 705)], n=8), w=3, jit=1, passes=1)
    s.stroke([(600, 700), (640, 745)], w=7, jit=1, passes=1, step=3)
    s.stroke([(640, 700), (600, 745)], w=7, jit=1, passes=1, step=3)


def full_party(s):
    s.ground(500, 732, 760)
    base = 700
    for cx_, kind, body in ((185, "rogue", "green"), (815, "bard", "ochre"),
                            (342, "warrior", "red"), (658, "cleric", "purple")):
        figure(s, cx_, base, 1.0, kind, body)
    figure(s, 500, base + 10, 1.18, "wizard", "blue")
    s.sparkle(150, 300, 22)
    s.sparkle(860, 270, 24)
    s.sparkle(300, 190, 16)
    s.sparkle(720, 170, 16)


def epic_session(s):
    s.ground(500, 888, 460)
    glass = (bez((365, 262), (365, 380), (480, 440), (490, 500)) + bez((490, 500), (480, 560), (365, 620), (365, 740))
             + [(635, 740)] + bez((635, 740), (635, 620), (520, 560), (510, 500))
             + bez((510, 500), (520, 440), (635, 380), (635, 262)))
    s.shape(glass, "sky", w=6, a=.4, shade=(14, 14))
    sand_top = bez((395, 370), (440, 420), (480, 445), (492, 480)) + bez((508, 480), (520, 445), (560, 420), (605, 370))
    s.fill(sand_top, "ochre", .75)
    s.stroke([(500, 500), (500, 690)], w=3, jit=.6, passes=1)
    mound = bez((385, 735), (440, 720), (470, 650), (500, 640)) + bez((500, 640), (530, 650), (560, 720), (615, 735))
    s.shape(mound, "ochre", w=3.5, a=.75)
    for y in (221, 751):
        s.shape(rect(320, y, 680, y + 38), "brown", w=6, a=.7, shade=(14, 14))
    for x in (335, 665):
        s.shape(rect(x - 9, 250, x + 9, 752), "brown", w=4.5, a=.55)
    s.sparkle(180, 300, 30)
    s.sparkle(830, 220, 26)
    s.sparkle(800, 640, 22)
    s.sparkle(200, 700, 18)
    s.rays(500, 500, 330, 380, 8, start=-20, span=40, w=3)
    s.rays(500, 500, 330, 380, 8, start=160, span=40, w=3)


def dice_overlord(s):
    s.ground(500, 880, 560)
    cube(s, 255, 720, 100, pips=(6, 4, 5), color="cream", wline=5)
    cube(s, 745, 725, 100, pips=(3, 5, 6), color="cream", wline=5)
    d20(s, 500, 610, 175, "red")
    crown = [(375, 440), (350, 290), (430, 360), (500, 260), (570, 360), (650, 290), (625, 440)]
    s.erase(crown + [(625, 470), (375, 470)], grow=5)
    s.shape(crown, "gold", w=6, a=.8, shade=(14, 14))
    s.shape(rect(372, 438, 628, 480), "gold", w=6, a=.8, shade=(10, 10))
    for x, c in ((420, "red"), (500, "blue"), (580, "red")):
        s.shape(ell(x, 459, 13, n=14), c, w=3, a=.8)
    for p in ((350, 285), (500, 255), (650, 285)):
        s.shape(ell(p[0], p[1], 15, n=14), "red", w=3.5, a=.8)
    s.rays(500, 340, 190, 235, 7, start=-160, span=140, w=3.5)
    s.sparkle(180, 330, 22)
    s.sparkle(840, 360, 22)


def fortunes_favorite(s):
    s.ground(500, 880, 300)
    s.stroke(smooth([(500, 480), (505, 600), (470, 740), (420, 860)], n=10), w=13, jit=1.3)
    for phi in (-135, -45, 45, 135):
        c, sn = math.cos(rad(phi)), math.sin(rad(phi))
        tx, ty = 500 + 14 * c, 480 + 14 * sn
        s.shape(heart(tx, ty, 7.6, phi + 90), "green", w=6, a=.65, shade=(14, 14))
        s.stroke([(tx, ty), (tx + 150 * c, ty + 150 * sn)], w=3, jit=1, passes=1)
    s.dot(500, 480, 11)
    s.sparkle(190, 220, 28)
    s.sparkle(820, 190, 22)
    s.sparkle(840, 780, 26)
    s.sparkle(180, 700, 18)
    s.rays(500, 480, 330, 372, 6, start=-30, span=60, w=3)


def cursed_dice(s):
    s.ground(500, 925, 640)
    cube(s, 320, 790, 82, pips=(1, 1, 1), color="purple", wline=5)
    cube(s, 680, 790, 82, pips=(1, 1, 1), color="purple", wline=5)
    s.shape(ell(500, 410, 215, 195, n=60), "cream", w=6.5, a=.5, shade=(30, 30))
    jaw = smooth([(385, 540), (395, 650), (440, 705), (500, 712), (560, 705), (605, 650), (615, 540)], n=8)
    s.erase(jaw, grow=4)
    s.shape(jaw, "cream", w=6, a=.5, shade=(20, 20))
    for x in (445, 500, 555):
        s.stroke([(x, 640), (x, 705)], w=3.6, jit=.8, passes=1)
    s.stroke([(405, 640), (595, 640)], w=3.6, jit=1, passes=1)
    for ex in (410, 590):
        s.solid(ell(ex, 440, 62, 56, n=30))
    s.solid([(500, 505), (472, 570), (528, 570)])
    s.stroke([(530, 235), (500, 290), (525, 330), (490, 385)], w=3.6, jit=.5, passes=1)
    s.stroke([(715, 150), (850, 150), (850, 285)], w=3.2, jit=.8, passes=1)
    s.stroke([(850, 150), (715, 285)], w=2.2, jit=.6, passes=1)
    for r in (50, 100, 150):
        s.stroke(smooth([(850 - r, 150), (850 - r * .6, 150 + r * .6), (850, 150 + r)], n=6), w=2.2, jit=.6, passes=1)
    s.sparkle(160, 230, 18, "purple")


def both_sides(s):
    s.ground(500, 850, 640)
    s.shape(ell(500, 385, 135, 125, n=40), "cream", w=5.5, a=.45)
    s.stroke(smooth([(380, 330), (430, 285), (520, 280), (600, 305), (625, 340)], n=8), w=4, jit=1, passes=1)
    for ex in (455, 545):
        s.stroke(ell(ex, 350, 32, 30, n=20), w=4.5, jit=.7)
        s.dot(ex + 6, 352, 11)
        s.stroke(smooth([(ex - 36, 308), (ex, 296), (ex + 36, 312)], n=6), w=4, jit=.6, passes=1)
    left = [(215, 440), (385, 405), (385, 790), (215, 820)]
    right = [(615, 405), (785, 440), (785, 820), (615, 790)]
    mid = [(385, 405), (615, 405), (615, 790), (385, 790)]
    for panel in (left, right, mid):
        s.erase(panel, grow=3)
    s.shape(left, "brown", w=6, a=.6, shade=(14, 14))
    s.shape(right, "brown", w=6, a=.6, shade=(14, 14))
    s.shape(mid, "ochre", w=6, a=.55, shade=(18, 18))
    d20(s, 500, 595, 100, "red")
    crown = [(260, 590), (250, 530), (285, 560), (310, 515), (335, 560), (370, 530), (360, 590)]
    s.shape(crown, "gold", w=4.5, a=.8)
    s.shape(rect(256, 590, 364, 612), "gold", w=4.5, a=.8)
    s.shape([(700, 520), (689, 540), (689, 670), (711, 670), (711, 540)], "grey", w=4, a=.55)
    s.shape(rect(668, 670, 732, 694), "ochre", w=4, a=.7)
    s.stroke([(700, 694), (700, 744)], w=9, jit=.6, passes=1)


def hundred_hour_club(s):
    s.ground(500, 868, 340)
    s.stroke(ell(500, 262, 38, n=24), w=7, jit=1, closed=True)
    s.stroke(ell(500, 262, 22, n=20), w=3.5, jit=.8, closed=True, passes=1)
    s.shape(rect(468, 288, 532, 330), "gold", w=5.5, a=.75, shade=(10, 10))
    chain = bez((540, 255), (640, 190), (730, 260), (800, 200))
    s.stroke(chain, w=6, jit=1)
    for i in range(1, 6):
        x, y = chain[i * 4]
        s.stroke(ell(x, y, 15, 9, rot=i * 25, n=14), w=3.2, jit=.5, closed=True, passes=1)
    s.shape(ell(500, 575, 245, n=70), "gold", w=7, a=.8, shade=(40, 40))
    s.shape(ell(500, 575, 205, n=70), "cream", w=4.5, a=.5)
    for i in range(60):
        a = rad(i * 6 - 90)
        big = i % 5 == 0
        r0 = 205 - (30 if big else 14)
        s.line((500 + r0 * math.cos(a), 575 + r0 * math.sin(a)),
               (500 + 196 * math.cos(a), 575 + 196 * math.sin(a)), w=4 if big else 2, jit=.4)
    size = 46
    for st in glyph_strokes("100", 500 - (2 * 1.1 * size + .9 * size) / 2, 620, size):
        s.stroke(st, w=4, jit=.6, passes=1, step=3)
    s.stroke([(500, 575), (500 + 110 * math.cos(rad(-120)), 575 + 110 * math.sin(rad(-120)))], w=8, jit=.6, passes=1, step=3)
    s.stroke([(500, 575), (500 + 160 * math.cos(rad(-35)), 575 + 160 * math.sin(rad(-35)))], w=5.5, jit=.6, passes=1, step=3)
    s.dot(500, 575, 13)
    s.sparkle(190, 300, 24)
    s.sparkle(840, 760, 20)


def grand_campaign(s):
    s.ground(500, 872, 700)
    s.shape([(120, 780), (300, 420), (470, 780)], "grey", w=5, shade=(30, 30), a=.5)
    s.shape([(530, 780), (730, 400), (900, 780)], "grey", w=5, shade=(30, 30), a=.5)
    s.stroke([(300, 420), (270, 480), (300, 500), (330, 480), (300, 420)], w=3, jit=.8, passes=1)
    s.stroke([(730, 400), (700, 460), (730, 480), (765, 455), (730, 400)], w=3, jit=.8, passes=1)
    towers = [rect(250, 400, 380, 785), rect(620, 400, 750, 785)]
    keep = rect(375, 480, 625, 785)
    for t in towers + [keep]:
        s.erase(t, grow=4)
    for t in towers:
        s.shape(t, "grey", w=6, shade=(24, 24), a=.6)
    s.shape(keep, "grey", w=6, shade=(24, 24), a=.55)
    for x0 in (250, 620):
        s.shape([(x0 - 18, 400), (x0 + 65, 255), (x0 + 148, 400)], "red", w=6, shade=(18, 18), a=.7)
        s.stroke([(x0 + 65, 255), (x0 + 65, 170)], w=4.5, jit=.6, passes=1)
        s.shape([(x0 + 65, 170), (x0 + 130, 190), (x0 + 65, 212)], "red", w=3.5, a=.7)
        s.solid(rect(x0 + 58, 450, x0 + 72, 500))
    for i in range(5):
        x = 375 + i * 52
        s.shape(rect(x, 440, x + 32, 482), "grey", w=4.5, a=.55)
    s.solid([(445, 785), (445, 690)] + ell(500, 690, 55, 55, a0=180, a1=360, n=14) + [(555, 785)])
    for x in (470, 500, 530):
        s.stroke([(x, 640), (x, 780)], w=2.2, jit=.5, passes=1, step=3)
    for y in (700, 740):
        s.stroke([(450, y), (550, y)], w=2.2, jit=.5, passes=1, step=3)
    for y in (560, 610):
        for x in (275, 335, 645, 705):
            s.stroke([(x, y), (x + 38, y)], w=2.4, jit=.6, passes=1, step=3)
    for x, y in ((500, 540),):
        s.solid(rect(x - 6, y - 24, x + 6, y + 8))
    s.sparkle(520, 170, 26)
    s.sparkle(160, 300, 20)
    s.sparkle(850, 240, 20)


ICONS = [
    ("first_game", first_game), ("regular_adventurer", regular_adventurer),
    ("veteran_adventurer", veteran_adventurer), ("storyteller", storyteller),
    ("loyal_hero", loyal_hero), ("campaigner", campaigner), ("well_travelled", well_travelled),
    ("dice_initiate", dice_initiate), ("dice_legend", dice_legend),
    ("critical_moment", critical_moment), ("unlucky_hero", unlucky_hero),
    ("multimedia_maestro", multimedia_maestro), ("full_party", full_party),
    ("epic_session", epic_session), ("dice_overlord", dice_overlord),
    ("fortunes_favorite", fortunes_favorite), ("cursed_dice", cursed_dice),
    ("both_sides", both_sides), ("hundred_hour_club", hundred_hour_club),
    ("grand_campaign", grand_campaign),
]


def main(argv):
    sheet = None
    if argv and argv[0] == "--sheet":
        sheet, argv = argv[1], argv[2:]
    out_dir = Path(argv[0]) if argv else Path("Docu/GameCenterAchievements/images")
    wanted = set(argv[1:])
    out_dir.mkdir(parents=True, exist_ok=True)
    images = []
    for index, (name, draw) in enumerate(ICONS):
        if wanted and name not in wanted:
            continue
        sk = Sketch(1000 + index * 17)
        draw(sk)
        sk.frame()
        images.append(sk.finish(out_dir / f"{name}.png"))
        print("drew", name, flush=True)
    if sheet and images:
        cell, cols = 320, 5
        rows = (len(images) + cols - 1) // cols
        grid = Image.new("RGB", (cols * cell, rows * cell), (255, 255, 255))
        for i, im in enumerate(images):
            grid.paste(im.resize((cell, cell), Image.LANCZOS), ((i % cols) * cell, (i // cols) * cell))
        grid.save(sheet)


if __name__ == "__main__":
    main(sys.argv[1:])
