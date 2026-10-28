"""Simple pixel title cards for games that have no artwork anywhere
(2026-10-11: Age of War on the Flash shelf, the Browser Games shelf).

    python title_cards.py "Game Name" <out folder> [file stem] [theme]

writes <stem>-image.png (16:9, the main picture) and <stem>-thumb.png
(3:4, box art). Drawn small and blown up 4x with hard edges, so they match
the drive's pixel style. Themes: sky (default), dusk, night, sea.
Nothing on the drive runs this.
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

THEMES = {
    'sky':   [(60, 120, 220), (84, 150, 232), (112, 178, 240), (146, 204, 246), (186, 226, 250), (220, 240, 252)],
    'dusk':  [(46, 30, 70), (84, 40, 78), (140, 52, 70), (196, 84, 60), (236, 140, 70), (250, 190, 100)],
    'night': [(14, 14, 34), (22, 22, 52), (32, 30, 72), (44, 40, 92), (58, 52, 110), (74, 66, 128)],
    'sea':   [(20, 60, 120), (24, 84, 150), (30, 110, 176), (40, 140, 196), (60, 170, 210), (90, 200, 224)],
}
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def scene(W, H, theme):
    im = Image.new('RGBA', (W, H)); d = ImageDraw.Draw(im)
    bands = THEMES.get(theme, THEMES['sky']); bh = (H * 3 // 4) // len(bands) + 1
    for i, c in enumerate(bands): d.rectangle([0, i * bh, W, (i + 1) * bh], fill=c)
    g = H * 3 // 4
    d.rectangle([0, g, W, H], fill=(64, 140, 60)); d.rectangle([0, g, W, g + 1], fill=(110, 190, 80))
    d.rectangle([0, g + 6, W, H], fill=(92, 66, 44))
    for cx, cy in ((W // 5, H // 4), (W * 3 // 4, H // 6)):        # two pixel clouds
        for dx, dy, w in ((0, 0, 14), (4, -3, 8), (-4, 2, 10)):
            d.rectangle([cx + dx - w // 2, cy + dy, cx + dx + w // 2, cy + dy + 3], fill=(250, 250, 255))
    if theme == 'night':
        for k in range(30): d.point(((k * 37) % W, (k * 53) % (g - 4)), fill=(255, 250, 220))
    return im

def title(im, text, y_frac=0.32):
    W, H = im.size; d = ImageDraw.Draw(im)
    size = 17
    while size > 7:
        f = ImageFont.truetype(FONT, size)
        lines = [text] if d.textlength(text, font=f) <= W - 12 else wrap(text, f, d, W - 12)
        if all(d.textlength(l, font=f) <= W - 12 for l in lines) and len(lines) <= 3: break
        size -= 1
    mask = Image.new('L', (W, H)); md = ImageDraw.Draw(mask)
    lh = size + 3; y0 = int(H * y_frac) - lh * len(lines) // 2
    for i, l in enumerate(lines):
        md.text(((W - d.textlength(l, font=f)) / 2, y0 + i * lh), l, font=f, fill=255)
    m = np.array(mask.point(lambda v: 255 if v > 110 else 0)) > 0
    def grow(a):
        o = np.zeros_like(a)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1): o |= np.roll(np.roll(a, dx, 1), dy, 0)
        return o
    o1 = grow(m); o2 = grow(o1)
    a = np.array(im); a[o2] = (34, 22, 34, 255)
    ys, xs = np.nonzero(m)
    for yy, xx in zip(ys, xs):
        t = ((yy - y0) % lh) / max(1, size)
        a[yy, xx] = (255, 232, 160, 255) if t < .4 else ((255, 194, 60, 255) if t < .8 else (206, 140, 34, 255))
    return Image.fromarray(a)

def wrap(text, f, d, width):
    words, lines, cur = text.split(), [], ''
    for w in words:
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=f) <= width or not cur: cur = t
        else: lines.append(cur); cur = w
    if cur: lines.append(cur)
    return lines

def make(name, out, stem=None, theme='sky'):
    stem = stem or name
    os.makedirs(out, exist_ok=True)
    title(scene(160, 90, theme), name).resize((640, 360), Image.NEAREST).save(os.path.join(out, stem + '-image.png'))
    title(scene(90, 120, theme), name, .3).resize((360, 480), Image.NEAREST).save(os.path.join(out, stem + '-thumb.png'))

if __name__ == '__main__':
    make(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None, sys.argv[4] if len(sys.argv) > 4 else 'sky')
