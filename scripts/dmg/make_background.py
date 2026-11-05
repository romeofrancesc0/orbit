#!/usr/bin/env python3
"""Draws the background of the installer window (scripts/dmg/background.tiff).

Run it only when the design changes; the result is committed. Needs Pillow.
The layout (window size, where the two icons sit) lives in settings.py: keep them in sync.
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 660, 400                    # window, in points
APP_X, APPS_X, ICON_Y = 180, 480, 190   # icon centres, in points
HEADLINE = "Drag Orbit into Applications"

PEACH = (246, 193, 119)
PINK = (236, 106, 154)
INK = (28, 26, 52)
MUTED = (122, 120, 146)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def font(size, bold=False):
    for path, index in (("/System/Library/Fonts/HelveticaNeue.ttc", 1 if bold else 0),
                        ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0)):
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def render(scale):
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h), (247, 246, 251))

    # a soft, warm glow coming down from the top edge, like the notch icon
    glow = Image.new("RGB", (w, h), (247, 246, 251))
    gd = ImageDraw.Draw(glow)
    r = 150 * scale
    gd.ellipse([w // 2 - r * 2, -r * 2 - 10 * scale, w // 2 + r * 2, r], fill=lerp((247, 246, 251), PEACH, 0.45))
    glow = glow.filter(ImageFilter.GaussianBlur(70 * scale))
    img = Image.blend(img, glow, 0.9)

    d = ImageDraw.Draw(img)

    # headline
    f = font(22 * scale, bold=True)
    tw = d.textlength(HEADLINE, font=f)
    d.text(((w - tw) / 2, 46 * scale), HEADLINE, font=f, fill=INK)

    # arrow between the two icons: a gradient shaft with a head
    x0, x1 = (APP_X + 92) * scale, (APPS_X - 92) * scale
    y = ICON_Y * scale
    shaft = Image.new("RGB", (w, h))
    sd = ImageDraw.Draw(shaft)
    for x in range(int(x0) - 4 * scale, int(x1) + 8 * scale):
        sd.line([(x, 0), (x, h)], fill=lerp(PEACH, PINK, min(1, max(0, (x - x0) / (x1 - x0)))))
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    t = 5 * scale
    head = 17 * scale
    md.rounded_rectangle([x0, y - t / 2, x1 - head * 0.6, y + t / 2], radius=t / 2, fill=255)
    md.line([(x1 - head, y - head), (x1, y)], fill=255, width=int(t))
    md.line([(x1 - head, y + head), (x1, y)], fill=255, width=int(t))
    for cx, cy in ((x1 - head, y - head), (x1 - head, y + head), (x1, y)):
        md.ellipse([cx - t / 2, cy - t / 2, cx + t / 2, cy + t / 2], fill=255)
    img.paste(shaft, (0, 0), mask)

    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "background.tiff")
    with tempfile.TemporaryDirectory() as tmp:
        one, two = os.path.join(tmp, "bg.png"), os.path.join(tmp, "bg@2x.png")
        render(1).save(one, dpi=(72, 72))
        render(2).save(two, dpi=(144, 144))
        # a two-representation TIFF is what Finder reads to pick the sharp one on Retina
        subprocess.run(["tiffutil", "-cat", one, two, "-out", out], check=True, capture_output=True)
    print("wrote", out)


if __name__ == "__main__":
    main()
