#!/usr/bin/env python3
"""Draws the site's app icon (an original pixel gamepad with a wizard's
sparkle) and writes every size the site needs into site/. Re-run to redraw."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__), '..', 'site')
BG, EDGE = (27, 27, 34, 255), (58, 58, 72, 255)
GREEN, GREEN_D, GREEN_L = (47, 168, 79, 255), (24, 102, 46, 255), (92, 214, 124, 255)
CREAM, GOLD, RED, SPARK = (232, 245, 236, 255), (229, 184, 59, 255), (224, 82, 77, 255), (255, 228, 138, 255)

def base32():
    im = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, 31, 31], radius=7, fill=BG, outline=EDGE)
    # pad body: outline, then fill, then a highlight row
    d.rounded_rectangle([3, 11, 28, 23], radius=4, fill=GREEN_D)
    d.rectangle([4, 21, 10, 26], fill=GREEN_D); d.rectangle([21, 21, 27, 26], fill=GREEN_D)
    d.rounded_rectangle([4, 12, 27, 22], radius=3, fill=GREEN)
    d.rectangle([5, 22, 9, 25], fill=GREEN); d.rectangle([22, 22, 26, 25], fill=GREEN)
    d.line([7, 12, 24, 12], fill=GREEN_L)
    # d-pad
    d.rectangle([7, 16, 12, 17], fill=CREAM); d.rectangle([9, 14, 10, 19], fill=CREAM)
    # buttons
    d.rectangle([21, 14, 22, 15], fill=GOLD); d.rectangle([24, 17, 25, 18], fill=RED)
    d.rectangle([18, 18, 19, 19], fill=CREAM)
    # the four-point sparkle, the wizard's mark
    cx, cy = 24, 5
    for i in range(-3, 4):
        d.point((cx + i, cy), fill=SPARK); d.point((cx, cy + i), fill=SPARK)
    d.point((cx, cy), fill=(255, 255, 255, 255))
    d.point((7, 6), fill=SPARK)
    return im

def scaled(n):
    return base32().resize((n, n), Image.NEAREST)

def tile(n, pad_ratio=0.0):
    """Square, no transparency (Apple and Android crop their own corners)."""
    im = Image.new('RGBA', (n, n), BG)
    s = int(n * (1 - pad_ratio) // 32 * 32) or n
    s = max(32, s)
    icon = base32().resize((s, s), Image.NEAREST)
    im.alpha_composite(icon, ((n - s) // 2, (n - s) // 2))
    return im.convert('RGB')

os.makedirs(OUT, exist_ok=True)
scaled(32).save(os.path.join(OUT, 'favicon-32.png'))
scaled(16 * 2).resize((16, 16), Image.NEAREST).save(os.path.join(OUT, 'favicon-16.png'))
scaled(64).save(os.path.join(OUT, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
tile(180, 0.1).save(os.path.join(OUT, 'apple-touch-icon.png'))
tile(192, 0.1).save(os.path.join(OUT, 'icon-192.png'))
tile(512, 0.1).save(os.path.join(OUT, 'icon-512.png'))

# Open Graph banner, 1200 x 630
og = Image.new('RGB', (1200, 630), BG[:3])
og.paste(scaled(320).convert('RGBA'), (110, 155), scaled(320))
d = ImageDraw.Draw(og)
bold = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 76)
reg = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 34)
d.text((500, 225), 'RetroBat Wizard', font=bold, fill=(232, 232, 236))
d.text((504, 325), 'Party and co-op retro gaming,', font=reg, fill=(154, 160, 170))
d.text((504, 370), 'set up and kept up for you.', font=reg, fill=(154, 160, 170))
for x in range(0, 1200, 8):
    d.rectangle([x, 618, x + 3, 621], fill=GREEN[:3])
og.save(os.path.join(OUT, 'og-banner.png'))
print('icons written to', os.path.abspath(OUT))
