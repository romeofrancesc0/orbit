#!/usr/bin/env python3
"""Draws the Orbit icon: concentric arcs around a point.

Writes the transparent layer Resources/AppIcon.icon/Assets/orbit.png (the navy background and the
glass effect come from icon.json, applied by Icon Composer / Xcode) and docs/icon.png, a preview
of the finished icon. Run it only when the design changes. Needs Pillow and numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
N, SS = 1024, 2
S = N * SS

STOPS = [(0.00, (252, 200, 118)), (0.38, (240, 104, 150)), (0.72, (126, 98, 236)), (1.00, (88, 176, 255))]
CORE = [(0, (255, 238, 205)), (1, (244, 128, 150))]

# (radius, from°, to°), in layer pixels at 1024; angles clockwise from 3 o'clock.
ARCS = [
    (386, -62, 214),
    (302, 18, 262),
    (218, 92, 330),
    (134, 168, 388),
]
STROKE = 54
CORE_R = 44


def gradient(size, stops, angle):
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w]
    a = math.radians(angle)
    t = np.clip(((xs - w / 2) * math.cos(a) + (ys - h / 2) * math.sin(a)) / (w * 0.72) + 0.5, 0, 1)
    out = np.stack([np.interp(t, [p for p, _ in stops], [c[i] for _, c in stops]) for i in range(3)], axis=-1)
    return Image.fromarray(out.astype("uint8")).convert("RGBA")


def painted(mask, stops, angle):
    g = gradient(mask.size, stops, angle)
    g.putalpha(mask)
    return g


def glow(layer, radius, strength):
    alpha = layer.split()[3].filter(ImageFilter.GaussianBlur(radius)).point(lambda v: int(min(255, v * strength)))
    color = layer.resize((S // 8, S // 8)).filter(ImageFilter.GaussianBlur(5)).resize((S, S))
    color.putalpha(alpha)
    return color


def arc_mask(r, start, end):
    c, w, r, rr = S // 2, STROKE * SS, r * SS, STROKE * SS / 2
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.arc([c - r, c - r, c + r, c + r], start, end, fill=255, width=int(w))
    for ang in (start, end):  # rounded ends
        a = math.radians(ang)
        x, y = c + (r - rr) * math.cos(a), c + (r - rr) * math.sin(a)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)
    return m


def layer():
    c = S // 2
    parts = []
    for r, a, b in ARCS:
        p = painted(arc_mask(r, a, b), STOPS, 38)
        parts += [glow(p, 34 * SS / 2, 0.5), p]
    dot = Image.new("L", (S, S), 0)
    ImageDraw.Draw(dot).ellipse([c - CORE_R * SS, c - CORE_R * SS, c + CORE_R * SS, c + CORE_R * SS], fill=255)
    core = painted(dot, CORE, 50)
    parts += [glow(core, 44 * SS / 2, 0.9), core]
    big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for p in parts:
        big = Image.alpha_composite(big, p)
    return big.resize((N, N), Image.LANCZOS)


def squircle(size, n=5.0):
    ys, xs = np.mgrid[0:size, 0:size]
    x, y = (xs - size / 2 + 0.5) / (size / 2), (ys - size / 2 + 0.5) / (size / 2)
    return Image.fromarray(((np.abs(x) ** n + np.abs(y) ** n <= 1) * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(0.8))


def preview(art):
    bg = gradient((N, N), [(0, (28, 28, 69)), (1, (5, 5, 15))], 90)
    icon = Image.alpha_composite(bg, art)
    icon.putalpha(squircle(N))
    return icon.resize((512, 512), Image.LANCZOS)


if __name__ == "__main__":
    art = layer()
    art.save(os.path.join(ROOT, "Resources/AppIcon.icon/Assets/orbit.png"))
    preview(art).save(os.path.join(ROOT, "docs/icon.png"))
    print("wrote orbit.png and docs/icon.png")
