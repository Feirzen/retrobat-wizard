#!/usr/bin/env python3
"""Draws the site's app icon (an original grey pixel gamepad with purple
buttons and a wizard's sparkle) and writes every size the site needs into site/. Re-run to redraw."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__), '..', 'site')
BG, EDGE = (27, 27, 34, 255), (58, 58, 72, 255)
# A grey pad with purple buttons (Steven, 2026-10-10: the old green one was
# clunky). Original shape: a rounded bar with two round grips.
D, M, L, S = (46, 46, 56, 255), (170, 172, 182, 255), (206, 208, 216, 255), (132, 134, 146, 255)
K, KL = (58, 58, 70, 255), (84, 84, 100, 255)
P, PL, PD = (150, 92, 230, 255), (196, 150, 255, 255), (98, 56, 160, 255)
SPARK = (255, 228, 138, 255)
PURPLE = P

def pad_pixels():
    """{(x, y): (colour, part)} on a 32 x 32 grid. part is body, dpad, a, b
    or menu, so the animated version can press each one on its own."""
    def inside(x, y):
        cx, cy = x + 0.5, y + 0.5
        if 6 <= cx <= 26 and 10.5 <= cy <= 20.5:
            return True
        return any((cx - gx) ** 2 + (cy - 17.0) ** 2 <= 6.4 ** 2 for gx in (9.0, 23.0))
    mask = {(x, y) for y in range(32) for x in range(32) if inside(x, y)}
    px = {}
    for (x, y) in mask:
        if any((x + dx, y + dy) not in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            c = D
        elif (x, y - 1) in mask and (x, y - 2) not in mask:
            c = L
        elif (x, y + 1) in mask and (x, y + 2) not in mask:
            c = S
        else:
            c = M
        px[(x, y)] = (c, 'body')
    for x in range(6, 13):
        px[(x, 16)] = (K, 'dpad'); px[(x, 17)] = (K, 'dpad')
    for y in range(13, 21):
        px[(9, y)] = (K, 'dpad'); px[(10, y)] = (K, 'dpad')
    px[(9, 16)] = (KL, 'dpad')
    def btn(x, y, part):
        for dx in range(3):
            for dy in range(3):
                if (dx, dy) in ((0, 0), (2, 0), (0, 2), (2, 2)):
                    continue
                px[(x + dx, y + dy)] = (P, part)
        px[(x + 1, y)] = (PL, part); px[(x, y + 1)] = (PL, part)
        px[(x + 2, y + 1)] = (PD, part); px[(x + 1, y + 2)] = (PD, part)
    btn(23, 13, 'a'); btn(20, 16, 'b')
    for x in (14, 15, 17, 18):
        px[(x, 14)] = (K, 'menu')
    return px

def base32():
    im = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, 31, 31], radius=7, fill=BG, outline=EDGE)
    for (x, y), (c, _) in pad_pixels().items():
        im.putpixel((x, y), c)
    # the four-point sparkle, the wizard's mark
    cx, cy = 25, 4
    for i in range(-2, 3):
        im.putpixel((cx + i, cy), SPARK); im.putpixel((cx, cy + i), SPARK)
    im.putpixel((cx, cy), (255, 255, 255, 255)); im.putpixel((6, 5), SPARK)
    return im

def hexc(c):
    return '#%02x%02x%02x' % c[:3]

def anim_svg():
    """The homepage picture: the pad being played hard. Buttons press, the
    pad shakes, sparks fly off. Pure SVG + CSS, so it plays in an <img>, and
    it holds still for people who ask their system for less motion."""
    groups = {}
    for (x, y), (c, part) in sorted(pad_pixels().items()):
        groups.setdefault(part, []).append('<rect x="%d" y="%d" width="1.02" height="1.02" fill="%s"/>' % (x, y, hexc(c)))
    sparks = []
    spots = [(12, 12, -6, -7), (16, 11, 1, -9), (22, 11, 6, -7), (25, 15, 8, -3), (20, 15, 4, -8), (8, 14, -8, -4), (14, 13, -3, -8)]
    for i, (x, y, dx, dy) in enumerate(spots):
        sparks.append(('<g class="spark s%d">' % i) + '<rect x="%d" y="%d" width="1" height="1" fill="#fff"/>'
                      '<rect x="%d" y="%d" width="1" height="1" fill="%s"/><rect x="%d" y="%d" width="1" height="1" fill="%s"/>'
                      '<rect x="%d" y="%d" width="1" height="1" fill="%s"/><rect x="%d" y="%d" width="1" height="1" fill="%s"/></g>'
                      % (x, y, x - 1, y, hexc(SPARK), x + 1, y, hexc(SPARK), x, y - 1, hexc(SPARK), x, y + 1, hexc(SPARK)))
    kf = []
    for i, (x, y, dx, dy) in enumerate(spots):
        kf.append('.s%d{--dx:%dpx;--dy:%dpx;animation-delay:%.2fs}' % (i, dx, dy, i * 0.23))
    style = (
        '.pad{transform-origin:16px 17px;animation:shake .9s steps(2,end) infinite}'
        '@keyframes shake{0%{transform:translate(0,0) rotate(0)}25%{transform:translate(-.5px,.5px) rotate(-2deg)}'
        '50%{transform:translate(.5px,0) rotate(1.5deg)}75%{transform:translate(0,-.5px) rotate(-1deg)}100%{transform:translate(0,0) rotate(0)}}'
        '.a,.b,.dpad,.menu{animation:press .5s steps(1,end) infinite}'
        '.a{animation-duration:.42s}.b{animation-duration:.58s;animation-delay:.2s}'
        '.dpad{animation-duration:.7s;animation-delay:.1s}.menu{animation-duration:2.3s}'
        '@keyframes press{0%{filter:none}50%{filter:brightness(.55)}}'
        '.spark{opacity:0;animation:fly 1.6s ease-out infinite}'
        '@keyframes fly{0%{opacity:0;transform:translate(0,0) scale(.6)}10%{opacity:1}'
        '70%{opacity:.9}100%{opacity:0;transform:translate(var(--dx),var(--dy)) scale(1)}}'
        + ''.join(kf) +
        '@media (prefers-reduced-motion:reduce){*{animation:none!important}.spark{opacity:0}}'
    )
    body = ''.join('<g class="%s">%s</g>' % (part, ''.join(rs)) for part, rs in groups.items() if part != 'body')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 0 36 30" shape-rendering="crispEdges">'
            '<style>' + style + '</style>' + ''.join(sparks) +
            '<g class="pad"><g>' + ''.join(groups['body']) + '</g>' + body + '</g></svg>\n')

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
    d.rectangle([x, 618, x + 3, 621], fill=PURPLE[:3])
og.save(os.path.join(OUT, 'og-banner.png'))
open(os.path.join(OUT, 'pad-anim.svg'), 'w').write(anim_svg())
print('icons written to', os.path.abspath(OUT))
