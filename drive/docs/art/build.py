"""Renders every picture the wizard uses into <out>. Nothing on the drive runs
this; it exists so the art can be changed later without redrawing from scratch."""
import os
from PIL import Image
from pal import PAL
import pieces

TABS = [
    ('tab-play',     pieces.hat_tab),
    ('tab-health',   pieces.potions_tab),
    ('tab-profiles', pieces.orb_tab),
    ('tab-saves',    pieces.chest_tab),
    ('tab-features', pieces.cauldron_tab),
    ('tab-help',     pieces.book_tab),
]
# name, draw(t), frames.  The Play tab has none: the mage and the wordmark
# already own that page and a second moving thing would be noise.
PAGES = [
    ('page-health',   pieces.potions_page,  6),
    ('page-profiles', pieces.orb_page,      pieces.ORB_FRAMES),
    ('page-saves',    pieces.chest_page,    8),
    ('page-features', pieces.cauldron_page, 8),
    ('page-help',     pieces.book_page,     8),
]
LIGHTS = [('okg_lt', 'okg', 'okg_dp'), ('liq_a_lt', 'liq_a', 'liq_a_dk'),
          ('liq_r_lt', 'liq_r', 'liq_r_dk'), ('gry_lt', 'gry', 'gry_dk')]

def union_bbox(frames):
    box = None
    for f in frames:
        b = f.getbbox()
        if b is None: continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                     max(box[2], b[2]), max(box[3], b[3]))
    return box

def build(out):
    os.makedirs(out, exist_ok=True)
    made = {}

    # the tab pictures: one frame each, deliberately still
    for name, fn in TABS:
        im = fn().render(PAL, 1)
        im = im.crop(im.getbbox())
        im.save(os.path.join(out, name + '.png'))
        made[name] = im.size

    # the page pictures: drawn at 2x, because these are meant to be looked at
    for name, fn, count in PAGES:
        frames = [fn(t).render(PAL, 2) for t in range(count)]
        box = union_bbox(frames)
        frames = [f.crop(box) for f in frames]
        w, h = frames[0].size
        sheet = Image.new('RGBA', (w, h * count), (0, 0, 0, 0))
        for i, f in enumerate(frames): sheet.alpha_composite(f, (0, i * h))
        sheet.save(os.path.join(out, name + '-anim.png'))
        frames[0].save(os.path.join(out, name + '.png'))
        made[name] = frames[0].size
        made[name + '-anim'] = sheet.size

    # the status lights: ok, warn, bad, unknown, always in that order
    strip = Image.new('RGBA', (14 * 4, 14), (0, 0, 0, 0))
    for i, (lt, mid, dk) in enumerate(LIGHTS):
        strip.alpha_composite(pieces.light(lt, mid, dk).render(PAL, 1), (i * 14, 0))
    strip.save(os.path.join(out, 'lights.png'))
    made['lights'] = strip.size
    return made

if __name__ == '__main__':
    for k, v in sorted(build(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')).items()):
        print(k, v)
