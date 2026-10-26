"""The four newer tabs' pictures (2026-10-11): Profile, Games, Netplay, Admin.

Same rules as motion.py, which this borrows from: 20 frames a second, a
6 second loop (120 frames), small idle motion all the time plus one bigger
moment per loop, and every loop closes on itself.

    page-profile   a classic blue wizard hat with gold stars. It floats, its
                   tip sways, the stars twinkle; once a loop it hops and
                   throws a little fountain of stars out of the tip.
    page-games     a flying broomstick. It bobs, its bristles flutter, it
                   leaves a trail of sparkle dust; once a loop it does a
                   quick dash forward with speed lines.
    page-netplay   a magic mirror on a stand. Faint shadows of far-away
                   friends drift across the glass; once a loop the glass
                   ripples and a shadow waves.
    page-admin     a sword standing point up, glowing. The glow breathes;
                   once a loop a shine runs down the blade and the tip
                   flashes.

Each also has a small still tab picture, like the others (tab-*.png).

    python motion2.py            writes all eight into ./out
    python motion2.py page-admin only that one (tab pictures always)
"""
import math, os, sys, random
from PIL import Image
from kit import Canvas
from motion import P, N, put, ease_out, ease_in, twinkle, air_sparkles, write_strip

P.update({
    # the classic wizard blue, deeper than the potion blue
    'blu_lt': (96, 150, 240, 255), 'blu': (46, 92, 196, 255),
    'blu_dk': (30, 58, 140, 255),  'blu_dp': (20, 36, 92, 255),
    # steel for the blade
    'stl_w': (244, 250, 255, 255), 'stl_lt': (206, 220, 236, 255),
    'stl': (150, 170, 196, 255),   'stl_dk': (92, 108, 134, 255),
    # the sword's glow, see-through
    'gl_c1': (130, 220, 255, 110), 'gl_c2': (130, 220, 255, 50), 'gl_c3': (180, 240, 255, 170),
    # the mirror's glass and the shadows in it
    'mir_lt': (176, 196, 226, 255), 'mir': (120, 140, 186, 255), 'mir_dk': (78, 92, 140, 255),
    'leaf': (60, 44, 30, 255),
})
# The shadows in the mirror are glass made a little darker, worked out here,
# NOT see-through colours: a see-through pixel would show the window behind
# the picture rather than the glass.
def _mix(a, b, k): return tuple(int(round(a[i] * (1 - k) + b[i] * k)) for i in range(3)) + (255,)
SHADOW_INK = (44, 38, 80)
for _g in ('mir_lt', 'mir', 'mir_dk'):
    P[_g + '_s1'] = _mix(P[_g], SHADOW_INK, .34)
    P[_g + '_s2'] = _mix(P[_g], SHADOW_INK, .16)

STAR = ["..#..", ".###.", "#####", ".###.", ".#.#."]

def star(c, x, y, col='gold', core=None):
    for j, row in enumerate(STAR):
        for i, ch in enumerate(row):
            if ch == '#': c.set(x + i - 2, y + j - 2, col)
    if core: c.set(x, y, core)

def wave(t, per=1.0, ph=0.0):
    return math.sin(2 * math.pi * (t / N * per) + ph)

# ================================================================ the hat
#  Steven's own picture (2026-10-11): docs\art\hat-source.png, his blue
#  wizard hat put back onto its own 25 x 22 pixel grid, colours snapped to
#  six. Drawn here at TWO canvas pixels per hat pixel, so the hat keeps its
#  chunky look while the tail can move in smaller steps.
#
#  The motion, all worked out from the still picture every frame:
#    - the whole top of the cone sways a little (a bend: the further a
#      pixel is from the middle of the cone, the more it turns)
#    - the floppy tail on the left flicks on its own clock
#    - once a loop a gust WHOOSHES the tail up, it flutters there, then
#      springs back down with a wobble, leaving a trail of sparkles
HERE = os.path.dirname(os.path.abspath(__file__))

def load_source(name):
    """A source picture as {(x, y): colour name}, its colours added to P."""
    im = Image.open(os.path.join(HERE, name)).convert('RGBA')
    px = im.load(); out = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b_, a_ = px[x, y]
            if a_ < 128: continue
            key = 'src_%d_%d_%d' % (r, g, b_)
            P[key] = (r, g, b_, 255)
            out[(x, y)] = key
    return out, im.width, im.height

HAT, HAT_W, HAT_H = load_source('hat-source.png')
WHOOSH = 58

def smooth(e0, e1, v):
    u = min(1.0, max(0.0, (v - e0) / (e1 - e0)))
    return u * u * (3 - 2 * u)

def whoosh(t):
    """How far the gust lifts the tail, in degrees."""
    a = t - WHOOSH
    if a < 0 or a >= 56: return 0.0
    if a < 6: return 68 * ease_out(a / 6)
    if a < 16: return 68 + 5 * math.sin(a * 1.3)
    u = a - 16
    return 68 * math.exp(-u / 7.5) * math.cos(u * 0.42)

def rot(x, y, cx, cy, deg):
    r = math.radians(deg); c_, s_ = math.cos(r), math.sin(r)
    dx, dy = x - cx, y - cy
    return cx + c_ * dx - s_ * dy, cy + s_ * dx + c_ * dy

def profile_frame(t):
    K = 2                                   # canvas pixels per hat pixel
    ox, oy = 7, 12                          # where the hat sits on the canvas
    c = Canvas(66, 62)
    dy = round(1.4 * wave(t, 2))
    w = whoosh(t)
    bend = 3.0 * wave(t, 2, .7) + 0.22 * w            # the cone's sway
    flick = 7.0 * wave(t, 4, .3) + 3.0 * wave(t, 6, 1.9) + w   # the tail
    P1 = (ox + 11.5 * K, oy + 11.5 * K)               # middle of the cone
    J = (ox + 7.0 * K, oy + 5.5 * K)                  # where the tail joins
    def bend_deg(x, y):
        r = math.hypot(x - P1[0], y - P1[1])
        return bend * smooth(4, 24, r)
    def flick_deg(x, y):
        r = math.hypot(x - J[0], y - J[1])
        return flick * smooth(1, 12, r)
    def src(x, y):
        """Which hat pixel lands here: (layer, colour) or None."""
        # undo the bend (it turns about P1 and keeps the distance to P1)
        bx, by = rot(x + .5, y + .5, P1[0], P1[1], -bend_deg(x + .5, y + .5))
        # the tail: undo its flick as well
        fx, fy = rot(bx, by, J[0], J[1], -flick_deg(bx, by))
        hx, hy = int(math.floor((fx - ox) / K)), int(math.floor((fy - oy) / K))
        if hx <= 6 and 3 <= hy <= 8 and (hx, hy) in HAT: return HAT[(hx, hy)]
        hx, hy = int(math.floor((bx - ox) / K)), int(math.floor((by - oy) / K))
        if hy < 10 and not (hx <= 6 and 3 <= hy <= 8) and (hx, hy) in HAT: return HAT[(hx, hy)]
        hx, hy = int(math.floor((x + .5 - ox) / K)), int(math.floor((y + .5 - oy) / K))
        if hy >= 10 and (hx, hy) in HAT: return HAT[(hx, hy)]
        return None
    for y in range(c.h):
        for x in range(c.w):
            v = src(x, y - dy)
            if v: c.set(x, y, v)
    c.shadow(ox + 12.5 * K, oy + 22.5 * K + 1, 19 - max(0, -dy), 1, 'sh')
    # where the tip of the tail is right now, for the sparkle trail
    def tip(tt):
        ww = whoosh(tt)
        bd = 3.0 * wave(tt, 2, .7) + 0.22 * ww
        fl = 7.0 * wave(tt, 4, .3) + 3.0 * wave(tt, 6, 1.9) + ww
        x0, y0 = ox + 1.5 * K, oy + 8.5 * K
        x1, y1 = rot(x0, y0, J[0], J[1], fl * smooth(1, 12, math.hypot(x0 - J[0], y0 - J[1])))
        r = math.hypot(x1 - P1[0], y1 - P1[1])
        return rot(x1, y1, P1[0], P1[1], bd * smooth(4, 24, r))
    a = t - WHOOSH
    if 0 <= a < 34:
        for back in range(0, 14, 2):
            tt = t - back
            if tt < WHOOSH: break
            x, y = tip(tt)
            age = back + (a % 2)
            col = 'gold' if back % 4 else 'spark'
            if age < 5: c.sparkle(int(round(x)), int(round(y + dy)) - 1, 1, col, core='white')
            elif age < 10: put(c, x, y + dy - 1, 'gold_lt', True)
            else: put(c, x, y + dy - 1, 'gold_dk', True)
    # the gust itself: pale streaks rushing up past the tail
    if 0 <= a < 14:
        for k, (sx, sy) in enumerate([(4, 34), (9, 40), (2, 26)]):
            yy = sy - a * 2.4 - k * 3
            for i in range(5):
                put(c, sx + i * .6, yy - i, 'gls_lt' if i < 2 else 'gls', True)
    air_sparkles(c, t, [(3, 6, 1, 5), (60, 10, 2, 40), (58, 44, 1, 80), (2, 46, 2, 100), (40, 3, 1, 25)])
    return c

def profile_tab():
    """The tab picture is Steven's hat itself, one pixel per pixel."""
    c = Canvas(HAT_W, HAT_H)
    for (x, y), v in HAT.items(): c.set(x, y, v)
    return c

# ============================================================== the broom
DASH = 70

def dash_dx(t):
    a = t - DASH
    if a < 0 or a >= 26: return 0
    if a < 3: return -round(2 * a / 3)                 # wind up
    if a < 8: return -2 + round(10 * ease_out((a - 3) / 5))
    if a < 26: return round(8 * (1 - ease_in((a - 8) / 18)))
    return 0

def broom(c, ox, oy, tilt, flutter, t=0):
    """A broom flying left to right, handle in front, bristles behind.
    tilt (-1..1) lifts the nose; flutter wiggles the bristle tips."""
    # handle: a thick line from the tail to the nose
    x0, y0 = ox + 18, oy + 22
    x1, y1 = ox + 58, oy + 12 - tilt * 2
    steps = int(abs(x1 - x0))
    for i in range(steps + 1):
        u = i / steps
        x = x0 + (x1 - x0) * u; y = y0 + (y1 - y0) * u
        put(c, x, y - 1, 'wd_lt'); put(c, x, y, 'wd'); put(c, x, y + 1, 'wd_dk')
    put(c, x1 + 1, y1, 'wd'); put(c, x1 + 1, y1 - 1, 'wd_lt')
    # bristles: a solid fan behind the tail, straw-striped, ragged at the
    # end, tied with a gold band. Since 2026-10-11 they stream in the wind
    # (Steven: "bristles move more"): a ripple runs down the fan from the
    # band to the ends, each edge rippling on its own, and every ragged tip
    # whips about on its own clock. Whole waves per loop, so it closes.
    L = 18
    T = 2 * math.pi * t / N
    for i in range(0, L + 1):
        x = x0 - i
        u = i / L
        off = flutter * 1.7 * math.sin(T * 3 - i * .45) * u ** 1.3
        top = 2.5 + 5.0 * u ** .8 + flutter * .9 * math.sin(T * 5 - i * .6) * u
        bot = 2.5 + 5.0 * u ** .8 + flutter * .9 * math.sin(T * 4 - i * .5 + 1.7) * u
        mid = y0 + .4 * i * u + off
        for yy in range(int(math.floor(mid - top)), int(math.ceil(mid + bot)) + 1):
            v = (yy - mid) / (top if yy < mid else bot)
            col = 'pap_dk' if v > .55 else ('pap_lt' if v < -.45 else 'pap')
            if (yy - int(round(off)) + (i // 3)) % 3 == 0 and abs(v) < .8: col = 'pap_dk' if v > 0 else 'pap'
            c.set(int(x), yy, col)
    endoff = flutter * 1.7 * math.sin(T * 3 - L * .45)
    for j in range(-6, 7):                          # the ragged, whipping tips
        n = 2 + (j * 7 + 3) % 3 + int(round(1 + math.sin(T * 6 + j * 2.1)))
        f = flutter * 1.4 * math.sin(T * 5 + j * 1.3)
        for k in range(1, n + 1):
            put(c, x0 - L - k, y0 + .4 * L + endoff + j * 1.05 + f * k / n, 'pap_dk' if abs(j) > 3 else 'pap')
    for j in range(-3, 4):
        put(c, x0 - 3, y0 + j, 'gold' if j < 2 else 'gold_dk'); put(c, x0 - 2, y0 + j, 'gold_dk')
    put(c, x0 - 3, y0 - 3, 'gold_lt')

def games_frame(t):
    c = Canvas(84, 50)
    dx = dash_dx(t)
    dy = round(2 * wave(t, 2))
    tilt = wave(t, 2, -.8)
    flutter = 1.4 + .6 * wave(t, 2)
    if 0 <= t - DASH < 26: flutter += 1.2 * math.sin(math.pi * (t - DASH) / 26)
    ox, oy = 10 + dx, 12 + dy
    broom(c, ox, oy, tilt, flutter, t)
    c.outline('ink')
    # trail of sparkle dust behind the bristles, drifting back and fading
    for k in range(6):
        st = k * 20
        a = (t - st) % N
        if a >= 40: continue
        x = ox + 2 - a * .9 + (k % 3)
        y = oy + 21 + (k % 3 - 1) * 3 + math.sin(a * .25 + k) * 1.5
        if x < 1: continue
        if a < 12: c.sparkle(int(round(x)), int(round(y)), 1, 'gold_lt', core='white')
        elif a < 26: put(c, x, y, 'gold')
        else: put(c, x, y, 'gold_dk')
    # the dash: speed lines streaming back
    a = t - DASH
    if 3 <= a < 22:
        for k, ly in enumerate((oy + 6, oy + 14, oy + 28, oy + 34)):
            ln = 10 - abs(a - 9)
            if ln <= 1: continue
            sx = ox - 2 - k * 3
            for i in range(int(ln) * 2):
                if (i + a) % 3: put(c, sx - i, ly, 'gls_lt' if i < 4 else 'gls', True)
    c.shadow(ox + 40, 47, 18 - dy, 1, 'sh')
    air_sparkles(c, t, [(80, 6, 1, 10), (76, 36, 2, 55), (6, 4, 2, 90)])
    return c

def games_tab():
    """Diagonal, so it fills a square instead of one long thin line: the
    handle runs up to the top right, the bristles fan out bottom left."""
    c = Canvas(24, 24)
    for i in range(0, 15):                     # the handle, 45 degrees
        x, y = 8 + i, 15 - i
        c.set(x, y, 'wd'); c.set(x + 1, y, 'wd_lt'); c.set(x, y + 1, 'wd_dk')
    c.set(22, 1, 'wd_lt')
    # the bristles: a fan pointing down-left from the band
    for d in range(0, 8):                      # distance back along the broom
        hw = 1 + d * .55
        cx, cy = 7 - d * .75, 16 + d * .75
        for k in range(-int(round(hw)), int(round(hw)) + 1):
            x = int(round(cx + k * .75)); y = int(round(cy + k * .75))
            col = 'pap_lt' if k < -hw / 3 else ('pap_dk' if k > hw / 3 else 'pap')
            c.set(x, y, col); c.set(x - 1, y, col)
    for k in range(-2, 3):                     # the gold band
        c.set(8 + k, 15 + k, 'gold' if k < 1 else 'gold_dk')
    c.outline('ink')
    return c

# ============================================================== the mirror
RIPPLE = 72

def mirror_glass(cx, cy, rx, ry):
    pts = set()
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            dx = (x + .5 - cx) / (rx + .5); dy = (y + .5 - cy) / (ry + .5)
            if dx * dx + dy * dy <= 1: pts.add((x, y))
    return pts

def figure(c, x, y, glass, k, wave_arm=0):
    """A faint person, head and shoulders like a profile picture (Steven,
    2026-10-11: the first ones looked like chess pieces). Soft edged: the
    rim one step fainter than the middle. Only inside the glass. k is '_s1'
    (clearer) or '_s2' (fainter), added to whichever glass tone is under
    each pixel."""
    cx = x + .5
    inside = {}
    for yy in range(y - 1, y + 15):
        for xx in range(x - 8, x + 9):
            px, py = xx + .5, yy + .5
            hd = ((px - cx) / 2.6) ** 2 + ((py - (y + 2.4)) / 3.0) ** 2      # head
            sh = ((px - cx) / 6.8) ** 2 + ((py - (y + 14.0)) / 8.0) ** 2     # shoulders
            nk = abs(px - cx) <= 1.6 and y + 4.5 <= py <= y + 7.5           # neck
            d = min(hd, sh)
            if d <= 1 or nk: inside[(xx, yy)] = d
    if wave_arm:
        # a hand up beside the head, swaying side to side
        hx = x + 6 + (1 if wave_arm > 0 else 0)
        for (ax, ay) in [(x + 5, y + 8), (x + 5, y + 7), (hx, y + 6), (hx, y + 5), (hx, y + 4),
                         (hx, y + 3), (hx + 1, y + 3), (hx, y + 2), (hx + 1, y + 2)]:
            inside[(ax, ay)] = .5
    for (px, py), d in inside.items():
        g = c.get(px, py)
        if (px, py) not in glass or g not in ('mir_lt', 'mir', 'mir_dk'): continue
        edge = d > .62 or any((px + ex, py + ey) not in inside for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        c.set(px, py, g + ('_s2' if (edge or k == '_s2') else '_s1'))

def netplay_frame(t):
    c = Canvas(52, 66)
    cx, cy, rx, ry = 26, 26, 15, 21
    # the stand: two feet and a stem
    c.rect(cx - 2, cy + ry + 1, cx + 1, cy + ry + 8, 'wd_dk')
    c.rect(cx - 2, cy + ry + 1, cx - 2, cy + ry + 8, 'wd')
    c.rect(cx - 12, cy + ry + 9, cx + 11, cy + ry + 11, 'wd')
    c.rect(cx - 12, cy + ry + 9, cx + 11, cy + ry + 9, 'wd_lt')
    # the gold frame
    c.ellipse(cx, cy, rx + 3, ry + 3, 'gold_dk')
    c.ellipse(cx - .5, cy - .5, rx + 2, ry + 2, 'gold', only_on={'gold_dk'})
    for (x, y) in list(c.px):
        if c.get(x, y) == 'gold' and (x - cx) < -8 and (y - cy) < -6: c.set(x, y, 'gold_lt')
    # the glass, with a soft vertical gradient
    glass = mirror_glass(cx, cy, rx, ry)
    for (x, y) in glass:
        u = (y - (cy - ry)) / (2 * ry)
        c.set(x, y, 'mir_lt' if u < .3 else ('mir' if u < .75 else 'mir_dk'))
    # a little crown ornament on top
    c.rect(cx - 3, cy - ry - 5, cx + 2, cy - ry - 3, 'gold')
    c.set(cx - 1, cy - ry - 6, 'gold_lt'); c.set(cx, cy - ry - 6, 'gold_lt')
    c.set(cx - 1, cy - ry - 5, 'red'); c.set(cx, cy - ry - 5, 'red_lt')
    # THE SHADOWS: two far-away friends drifting slowly across the glass,
    # fading in near the middle and out at the edges. They loop exactly.
    for k, (sp, ph, yy) in enumerate([(1, 0.0, 24), (-1, .5, 28)]):
        u = ((t / N) * sp + ph) % 1.0
        x = int(round(cx - rx - 4 + u * (2 * rx + 8)))
        fade = 1 - abs(u - .5) * 2
        col = '_s1' if fade > .5 else ('_s2' if fade > .15 else None)
        if col is None: continue
        w = 0
        a = t - RIPPLE - 6
        if k == 0 and 0 <= a < 30: w = 1 if (a // 4) % 2 else -1
        figure(c, x, yy, glass, col, w)
    # the shimmer: a pale diagonal band sweeping across every 3 seconds
    s = (t * 3) % (N // 2 * 3)
    if s < 60:
        band = -20 + s * 1.1
        for (x, y) in glass:
            v = (x - (cx - rx)) + (y - (cy - ry)) * .5
            if band <= v < band + 3: c.set(x, y, 'gls_lt' if band + 1 <= v < band + 2 else 'mir_lt')
    # the ripple: rings spreading from the middle of the glass
    a = t - RIPPLE
    if 0 <= a < 22:
        r = 1 + a * 1.2
        for (x, y) in glass:
            d = (((x + .5 - cx) / 1.0) ** 2 + ((y + .5 - cy) / 1.35) ** 2) ** .5
            if r - 1.3 <= d <= r: c.set(x, y, 'stl_w' if a < 10 else 'gls_lt')
            elif r - 6 <= d <= r - 4.8 and a > 4: c.set(x, y, 'mir_lt')
    # hard glint, upper left
    for (x, y) in [(cx - 9, cy - 13), (cx - 10, cy - 12), (cx - 10, cy - 11), (cx - 11, cy - 10), (cx - 11, cy - 9), (cx - 8, cy - 14)]:
        if (x, y) in glass: c.set(x, y, 'white')
    c.outline('ink')
    c.shadow(cx, cy + ry + 13, 14, 1, 'sh')
    air_sparkles(c, t, [(4, 6, 2, 20), (48, 12, 1, 60), (47, 44, 2, 100), (3, 40, 1, 75)])
    return c

def netplay_tab():
    c = Canvas(20, 26)
    cx, cy = 9.5, 9.5
    c.rect(8, 18, 11, 21, 'wd_dk')
    c.rect(4, 22, 15, 23, 'wd')
    c.ellipse(cx, cy, 8, 10, 'gold_dk')
    c.ellipse(cx - .5, cy - .5, 7, 9, 'gold', only_on={'gold_dk'})
    g = mirror_glass(cx, cy, 5, 7)
    for (x, y) in g: c.set(x, y, 'mir_lt' if y < 7 else ('mir' if y < 13 else 'mir_dk'))
    for (x, y) in [(10, 8), (11, 8), (9, 9), (10, 9), (11, 9), (12, 9), (10, 10), (11, 10), (9, 11), (10, 11), (11, 11), (12, 11), (9, 12), (10, 12), (11, 12), (12, 12)]:
        if (x, y) in g: c.set(x, y, 'mir_dk')
    c.set(6, 5, 'white'); c.set(6, 6, 'white'); c.set(7, 4, 'white')
    c.outline('ink')
    return c

# =============================================================== the sword
#  Steven's own picture (2026-10-11): docs\art\sword-source.png, his sword
#  put back onto its own 11 x 48 grid, colours snapped to five. Drawn one
#  canvas pixel per sword pixel. The magic is faint yellow-gold flames that
#  flicker in and out of existence along the blade; once a loop they flare
#  up together and the blade catches a shine.
SWORD, SWORD_W, SWORD_H = load_source('sword-source.png')
FLARE_S = 70
# the blade's light colours, which the shine turns white
BLADE = set(v for v in SWORD.values() if sum(P[v][:3]) > 520)

P.update({
    # Gold, not brown: see-through dark-gold over a dark window reads as
    # mud, so the flames are light and fairly solid, and "faint" comes from
    # them being small, few and short-lived instead.
    'fl_o': (255, 186, 52, 150),    # flame edge
    'fl_m': (255, 212, 90, 205),    # flame body
    'fl_i': (255, 246, 190, 235),   # flame heart
    'fl_g': (255, 222, 120, 55),    # the glow along the blade's edge
})

FLAME = [  # a flame by height: rows from the top, '#' body, '+' heart
    ["#"],
    ["#", "#"],
    [".#.", "#+#", ".#."],
    [".#.", "#+#", "#+#", ".#."],
    [".#..", ".##.", "#++#", "#++#", ".##."],
    [".#..", "..#.", ".##.", "#++#", "#++#", ".##."],
]

def flame(c, x, y, h, lean, dim):
    """One flame with its BOTTOM at (x, y). dim 0 normal, 1 fainter."""
    rows = FLAME[max(0, min(len(FLAME) - 1, h))]
    w = len(rows[0])
    for j, row in enumerate(rows):
        shift = int(round(lean * (len(rows) - 1 - j) / max(1, len(rows) - 1)))
        for i, ch in enumerate(row):
            if ch == '.': continue
            col = ('fl_i' if ch == '+' else 'fl_m') if not dim else ('fl_m' if ch == '+' else 'fl_o')
            if j == 0 and len(rows) > 2: col = 'fl_o'
            put(c, x - w // 2 + i + shift, y - len(rows) + 1 + j, col, True)

def admin_frame(t):
    c = Canvas(40, 62)
    ox, oy = (c.w - SWORD_W) // 2, 9
    dy = round(1.2 * wave(t, 2))
    for (x, y), v in SWORD.items():
        c.set(ox + x, oy + y + dy, v)
    # the shine: a bright band running down the blade at the flare
    a = t - FLARE_S
    if 0 <= a < 16:
        sy = oy + dy + a * 2.4
        for (x, y), v in SWORD.items():
            yy = oy + y + dy
            if v in BLADE and sy <= yy < sy + 3: c.set(ox + x, yy, 'white')
    flare = 1.0 if 0 <= a < 28 else 0.0
    # a soft glow along the blade's edges, breathing; solid, not dotted
    s = .5 + .5 * wave(t, 3)
    if s > .35 or flare:
        for (x, y), v in SWORD.items():
            if y > 34: continue                   # blade only, not the hilt
            for ex in (-1, 1):
                put(c, ox + x + ex, oy + y + dy, 'fl_g', True)
    # THE FLAMES. Each has a fixed spot, start and length worked out once,
    # so the loop closes; within its life it grows, wavers, shrinks, and now
    # and then blinks out for a frame - "in and out of existence".
    rnd = random.Random(11)
    flames = []
    for i in range(22):
        side = -1 if i % 2 else 1
        y = rnd.randint(2, 33)
        flames.append((side, y, rnd.randint(0, N - 1), rnd.randint(12, 20), rnd.random()))
    for i in range(10):                           # extra ones, only in the flare
        flames.append((-1 if i % 2 else 1, rnd.randint(2, 33), FLARE_S + rnd.randint(0, 10), rnd.randint(10, 16), rnd.random()))
    for k, (side, y, st, life, ph) in enumerate(flames):
        age = (t - st) % N
        if k >= 22 and not (0 <= t - st < life): continue
        if age >= life: continue
        u = age / life
        h = int(round((math.sin(math.pi * u)) * (4 + 1.5 * flare) + .3 * math.sin(age * 1.7 + ph * 6)))
        if h < 0: continue
        if ((age * 7 + k * 3) % 11) == 0: continue        # blinks out
        # the blade's edge at that height
        row = [x for (x, yy) in SWORD if yy == y]
        if not row: continue
        ex = ox + (max(row) + 2 if side > 0 else min(row) - 2)
        rise = int(age * .35)
        lean = math.sin(age * .6 + ph * 5) * .8
        flame(c, ex, oy + y + dy - rise, h, lean, dim=(u > .75))
    # a flame or two licking off the tip
    tipy = oy + dy
    for k in range(3):
        age = (t - k * 40 - 13) % N
        if age < 18:
            h = int(round(math.sin(math.pi * age / 18) * (4 + 2 * flare)))
            if ((age * 5 + k) % 9) != 0: flame(c, ox + SWORD_W // 2, tipy - 1 - int(age * .3), h, math.sin(age * .5 + k) * .7, dim=False)
    # sparks off the tip at the flare
    b = a - 14
    if 0 <= b < 14:
        for k in range(6):
            ang = k * math.pi / 3 + .3
            d = 3 + b * .9
            x = ox + SWORD_W // 2 + d * math.cos(ang); y = tipy - 2 + d * math.sin(ang) * .8
            if b < 10: c.sparkle(int(round(x)), int(round(y)), 1 if b < 5 else 0, 'gold_lt', core='white')
    c.shadow(ox + SWORD_W / 2, oy + SWORD_H + 3, 7, 1, 'sh')
    air_sparkles(c, t, [(3, 10, 1, 30), (36, 20, 2, 75), (35, 50, 1, 105), (4, 48, 2, 8)])
    return c

def admin_tab():
    """Steven's sword, small and on the diagonal so it fits the tab: point
    to the top right, the same cream blade, gold guard and dark grip."""
    c = Canvas(22, 22)
    cols = sorted(set(SWORD.values()), key=lambda v: sum(P[v][:3]))
    dark, olive, mid, light = cols[0], cols[1], cols[-2], cols[-1]
    gold = max(cols, key=lambda v: P[v][0] + P[v][1] - 2 * P[v][2])
    for i in range(0, 12):                     # the blade
        x, y = 8 + i, 13 - i
        c.set(x, y, light); c.set(x + 1, y, mid); c.set(x, y + 1, mid)
    c.set(20, 1, light)
    for k in range(-3, 4): c.set(7 + k, 14 + k, gold if abs(k) < 3 else olive)   # the guard
    c.set(6, 15, olive); c.set(5, 16, dark); c.set(4, 17, olive); c.set(3, 18, dark)  # the grip
    c.set(2, 19, gold); c.set(1, 20, gold); c.set(2, 20, olive); c.set(1, 19, olive)  # the pommel
    c.outline(dark)
    return c

# ================================================================== build
PAGES = [('page-profile', profile_frame), ('page-games', games_frame),
         ('page-netplay', netplay_frame), ('page-admin', admin_frame)]
TABS = [('tab-profile', profile_tab), ('tab-games', games_tab),
        ('tab-netplay', netplay_tab), ('tab-admin', admin_tab)]

def build(out, only=None):
    os.makedirs(out, exist_ok=True)
    made = {}
    for name, fn in TABS:
        im = fn().render(P, 1)
        im = im.crop(im.getbbox())
        im.save(os.path.join(out, name + '.png'))
        made[name] = im.size
    for name, fn in PAGES:
        if only and name not in only: continue
        frames = [fn(t).render(P, 2) for t in range(N)]
        made[name] = write_strip(out, name, frames)[1]
    return made

if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    for k, v in build(os.path.join(here, 'out'), sys.argv[1:] or None).items():
        print(k, v)
