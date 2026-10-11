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
    # a 6 x 6 cross (Steven, 2026-10-11: the old 7 x 8 one was too big)
    for x in range(7, 13):
        px[(x, 16)] = (K, 'dpad'); px[(x, 17)] = (K, 'dpad')
    for y in range(14, 20):
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

# The homepage loop (Steven, 2026-10-11): a burst of button presses, then a
# rest, then again. Each press throws a few one-pixel sparks off the button
# that was pressed. CYCLE is the whole loop in seconds; PRESSES are
# (button, when as a percent of the loop). Nothing happens after REST_FROM.
CYCLE = 7.0
REST_FROM = 64
PRESSES = [('a', 3), ('b', 9), ('a', 14), ('dpad', 19), ('a', 24), ('a', 28),
           ('b', 33), ('dpad', 38), ('menu', 43), ('a', 48), ('b', 53), ('a', 58)]
# where sparks leave each button, and the directions they fly (pixels)
SPARK_FROM = {
    'a':    [((24, 12), (1, -4)), ((26, 14), (4, -2)), ((23, 12), (-1, -5))],
    'b':    [((21, 15), (0, -4)), ((22, 16), (3, -3)), ((20, 16), (-2, -4))],
    'dpad': [((9, 13), (-1, -4)), ((10, 13), (1, -5)), ((7, 15), (-4, -2))],
    'menu': [((15, 13), (-1, -3)), ((18, 13), (1, -3))],
}

def anim_svg():
    """The homepage picture: a pad being played in bursts. Buttons press, the
    pad shakes, a few one-pixel sparks pop off each pressed button, then it
    rests. Pure SVG + CSS, so it plays in an <img>, and it holds still for
    people who ask their system for less motion."""
    groups = {}
    for (x, y), (c, part) in sorted(pad_pixels().items()):
        groups.setdefault(part, []).append('<rect x="%d" y="%d" width="1.02" height="1.02" fill="%s"/>' % (x, y, hexc(c)))
    css = ['*{animation-duration:%.1fs;animation-iteration-count:infinite}' % CYCLE]
    # shake only while the buttons are going
    sh = ['0%{transform:translate(0,0) rotate(0)}']
    offs = ['translate(-.5px,.5px) rotate(-2deg)', 'translate(.5px,0) rotate(1.5deg)',
            'translate(0,-.5px) rotate(-1deg)', 'translate(0,0) rotate(0)']
    t, i = 2.0, 0
    while t < REST_FROM:
        sh.append('%.1f%%{transform:%s}' % (t, offs[i % 4])); t += 3.2; i += 1
    sh.append('%d%%{transform:translate(0,0) rotate(0)}100%%{transform:translate(0,0) rotate(0)}' % REST_FROM)
    css.append('.pad{transform-origin:16px 17px;animation-name:shake;animation-timing-function:steps(1,end)}')
    css.append('@keyframes shake{' + ''.join(sh) + '}')
    # each button dims for a moment at each of its presses
    for part in ('a', 'b', 'dpad', 'menu'):
        kf = ['0%{filter:none}']
        for p, at in PRESSES:
            if p == part:
                kf.append('%d%%{filter:brightness(.5)}%.1f%%{filter:none}' % (at, at + 2.5))
        kf.append('100%{filter:none}')
        css.append('.%s{animation-name:p%s;animation-timing-function:steps(1,end)}' % (part, part))
        css.append('@keyframes p%s{%s}' % (part, ''.join(kf)))
    # sparks: one-pixel dots, each with its own short window in the loop
    sparks = []
    n = 0
    for k, (part, at) in enumerate(PRESSES):
        spots = SPARK_FROM[part]
        pick = [spots[(k + j) % len(spots)] for j in range(2)]
        for j, ((x, y), (dx, dy)) in enumerate(pick):
            fill = '#ffffff' if (k + j) % 2 == 0 else hexc(SPARK)
            sparks.append('<rect class="sp sp%d" x="%d" y="%d" width="1" height="1" fill="%s"/>' % (n, x, y, fill))
            go = at + 0.5 * j
            css.append('.sp%d{animation-name:f%d}' % (n, n))
            css.append('@keyframes f%d{0%%{opacity:0;transform:translate(0,0)}%.1f%%{opacity:0;transform:translate(0,0)}'
                       '%.1f%%{opacity:1;transform:translate(0,0)}%.1f%%{opacity:0;transform:translate(%dpx,%dpx)}'
                       '100%%{opacity:0;transform:translate(%dpx,%dpx)}}'
                       % (n, go - 0.1, go, go + 7, dx, dy, dx, dy))
            n += 1
    css.append('.sp{opacity:0;animation-timing-function:ease-out}')
    css.append('@media (prefers-reduced-motion:reduce){*{animation:none!important}.sp{opacity:0}}')
    body = ''.join('<g class="%s">%s</g>' % (part, ''.join(rs)) for part, rs in groups.items() if part != 'body')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 0 36 30" shape-rendering="crispEdges">'
            '<style>' + ''.join(css) + '</style>' +
            '<g class="pad"><g>' + ''.join(groups['body']) + '</g>' + body + '</g>' + ''.join(sparks) + '</svg>\n')

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
