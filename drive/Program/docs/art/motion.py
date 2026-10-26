"""The moving pictures, second generation (2026-09-23).

Every page picture now runs at 20 frames a second instead of 8, loops every
6 seconds, and has two layers of motion:
  * IDLE  - small, always-on life: bubbles, glints, drifting sparks, a glow
            that breathes. Never still, never busy.
  * EVENT - one bigger moment per loop, the "spell": a cork pops, the ball
            flares, the chest lid bumps open, the brew bloops, a page flips.
The mage on the Play tab gets the full treatment: float, blink, pixel aura,
drifting sparks, and a spell cast with a spiral of sparks once every 8 s.

Every loop closes on itself: anything random is seeded once, and every
particle's position is worked out from (frame - its start) modulo the loop,
so frame N-1 flows straight back into frame 0.

Nothing on the drive runs this. `python motion.py` writes the finished
strips into ./out, which are then copied into _ClaudeWorkspace\\wizard.
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter
from kit import Canvas
from pal import PAL

FPS = 20
N = 120            # page loops: 6 s
NM = 160           # mage loop: 8 s

P = dict(PAL)
P.update({
    'gl_r1': (255, 112, 88, 80),  'gl_r2': (255, 112, 88, 40),
    'gl_b1': (110, 168, 255, 80), 'gl_b2': (110, 168, 255, 40),
    'gl_g1': (126, 236, 120, 80), 'gl_g2': (126, 236, 120, 40),
    'gl_p1': (200, 158, 244, 90), 'gl_p2': (200, 158, 244, 45),
    'gl_y1': (255, 232, 160, 150), 'gl_y2': (255, 232, 160, 70),
    'stm1': (206, 246, 122, 170), 'stm2': (206, 246, 122, 90),
    'dust': (180, 170, 160, 160),
    'fire_r': (222, 46, 46, 255), 'fire_o': (247, 128, 34, 255),
    'fire_y': (255, 194, 60, 255), 'fire_w': (255, 244, 200, 255),
})

def cp(c):
    n = Canvas(c.w, c.h); n.px = dict(c.px); return n

def put(c, x, y, col, empty_only=False):
    x, y = int(round(x)), int(round(y))
    if empty_only and (x, y) in c.px: return
    c.set(x, y, col)

def ease_out(u): return 1 - (1 - u) ** 3
def ease_in(u): return u ** 3
def ease_io(u): return 4*u*u*u if u < .5 else 1 - (-2*u + 2) ** 3 / 2
def clamp(v, a, b): return max(a, min(b, v))

def twinkle(c, x, y, a, life, big=2, col='spark'):
    """A sparkle that grows and shrinks over `life` frames: 0,1,2,1,0."""
    if a < 0 or a >= life: return
    u = a / life
    size = 0 if u < .2 or u > .8 else (1 if u < .4 or u > .6 else big)
    c.sparkle(x, y, min(size, big), col, core='white' if size else None)

def air_sparkles(c, t, spots, life=12):
    for (x, y, sz, start) in spots:
        twinkle(c, x, y, (t - start) % N, life, sz)

def ring_mask(cx, cy, rx, ry, w, h):
    out = []
    for y in range(h):
        for x in range(w):
            dx = (x + .5 - cx) / rx; dy = (y + .5 - cy) / ry
            d = dx*dx + dy*dy
            if .75 <= d <= 1.25: out.append((x, y))
    return out

# =================================================================== potions
def bottle(c, x, y, lt, mid, dk, cork_dy=0):
    cy = y + cork_dy
    c.rect(x + 4, cy + 0, x + 9, cy + 3, 'cork')
    c.rect(x + 4, cy + 0, x + 5, cy + 2, 'cork_lt')
    c.rect(x + 3, y + 4, x + 10, y + 6, 'red_dk')
    c.rect(x + 3, y + 4, x + 10, y + 4, 'red')
    c.rect(x + 4, y + 7, x + 9, y + 10, 'gls')
    c.rect(x + 4, y + 7, x + 5, y + 10, 'gls_lt')
    c.ellipse(x + 6.5, y + 16, 6, 6, dk)
    c.ellipse(x + 6, y + 15.5, 5, 5, mid, only_on={dk})
    c.ellipse(x + 5, y + 14.5, 3, 3, lt, only_on={mid})
    c.rect(x + 3, y + 12, x + 3, y + 14, 'white')
    c.rect(x + 4, y + 12, x + 4, y + 12, 'white')
    c.rect(x + 2, y + 20, x + 11, y + 21, dk)

POT = [  # x, y, colours, glow pair, phase
    (5,  14, ('liq_r_lt', 'liq_r', 'liq_r_dk'), ('gl_r1', 'gl_r2'), 0),
    (23, 12, ('liq_b_lt', 'liq_b', 'liq_b_dk'), ('gl_b1', 'gl_b2'), 40),
    (41, 14, ('liq_g_lt', 'liq_g', 'liq_g_dk'), ('gl_g1', 'gl_g2'), 80),
]
POP = 70   # the blue cork pops here

def cork_offset(t):
    a = t - POP
    if a < 0 or a > 30: return 0
    if a < 4: return -round(9 * ease_out(a / 4))
    if a < 18: return -9 + (1 if (a // 3) % 2 else 0)
    if a < 25: return -round(9 * (1 - ease_in((a - 18) / 7)))
    if a < 27: return -1
    return 0

def float_dy(t, i):
    """Each bottle floats on its own phase: up to 2px up, twice a loop."""
    return -round(1 + math.sin(2 * math.pi * (t / N * 2) + i * 2.1))

def potions_frame(t):
    c = Canvas(60, 48)
    shake = 0
    if POP - 8 <= t < POP: shake = (1 if (t // 2) % 2 else -1)
    for i, (x, y, cols, gl, ph) in enumerate(POT):
        dx = shake if i == 1 else 0
        bottle(c, x + dx, y + float_dy(t, i), *cols, cork_dy=cork_offset(t) if i == 1 else 0)
    c.outline('ink')
    # breathing glow round each belly, dithered, staggered so it ripples
    for i, (x, y0, cols, gl, ph) in enumerate(POT):
        y = y0 + float_dy(t, i)
        s = math.sin(2 * math.pi * ((t + ph) / N * 2))
        col = gl[0] if s > .2 else (gl[1] if s > -.5 else None)
        if i == 1 and 0 <= t - POP < 24: col = gl[0]
        if col is None: continue
        bx0 = x + dx if False else x
        for py_ in range(y + 6, y + 27):
            for px_ in range(x - 4, x + 18):
                if (px_, py_) in c.px: continue
                dd = ((px_ + .5 - x - 6.5) ** 2 + (py_ + .5 - y - 16) ** 2) ** .5
                if dd <= 9 and (px_ + py_) % 2 == 0: put(c, px_, py_, col)
                elif dd <= 11 and (px_ % 2 == 0) and ((px_ + py_) % 4 == 0): put(c, px_, py_, gl[1])
    # bubbles inside the liquid
    rnd = random.Random(3)
    for i, (x, y0, cols, gl, ph) in enumerate(POT):
        y = y0 + float_dy(t, i)
        for k in range(4):
            start = (k * 30 + ph + rnd.randint(0, 12)) % N
            a = (t - start) % N
            if a >= 22: continue
            bx = x + 5 + rnd.choice([0, 1, 2, 3]) + (1 if (a // 6) % 2 else 0)
            by = y + 20 - a * 9 / 22
            if c.get(int(bx), int(round(by))) in cols:
                put(c, bx, by, 'white' if a > 14 else cols[0])
    # the fizz out of the popped bottle
    x, y = POT[1][0], POT[1][1] + float_dy(t, 1)
    for k in range(14):
        s = POP + 1 + k * 1.3
        a = t - s
        if a < 0 or a >= 16: continue
        r = random.Random(100 + k)
        vx = r.uniform(-.55, .55); vy = -r.uniform(.9, 1.5)
        px_ = x + 6.5 + vx * a + math.sin(a * .6 + k) * .6
        py_ = y + 3 + vy * a + .03 * a * a
        col = 'white' if a < 4 else ('liq_b_lt' if a < 10 else 'liq_b')
        put(c, px_, py_, col)
        if a < 6 and k % 3 == 0: put(c, px_ + 1, py_, 'liq_b_lt')
    if POP <= t < POP + 10:
        a = t - POP
        for (sx, sy) in [(x + 1, y - 6), (x + 12, y - 5), (x + 6, y - 12)]:
            twinkle(c, sx, sy, a, 10, 2)
    air_sparkles(c, t, [(2, 6, 1, 0), (20, 3, 2, 22), (37, 5, 1, 50),
                        (57, 9, 2, 90), (48, 2, 1, 35), (10, 1, 2, 105)])
    for i, (x, y0, cols, gl, ph) in enumerate(POT):
        up = -float_dy(t, i)
        c.shadow(x + 6.5, y0 + 25, 6 - up, 1, 'sh')
    return c

# ============================================================== crystal ball
FLARE = 80

def orb_frame(t):
    c = Canvas(52, 62)
    ox, oy = 9, 8
    cx, cy = ox + 17, oy + 18
    # orbiting motes, the half behind the ball drawn first
    motes = []
    for k in range(3):
        a = 2 * math.pi * (t / N * 2 + k / 3)
        mx, my = cx + 22 * math.cos(a), cy + 2 + 6 * math.sin(a)
        motes.append((mx, my, math.sin(a) > 0, a))
    def draw_motes(front):
        for (mx, my, f, a) in motes:
            if f != front: continue
            for j in (2, 1):
                aa = a - j * .12
                put(c, cx + 22 * math.cos(aa), cy + 2 + 6 * math.sin(aa), 'pur_lt' if j == 1 else 'pur', not front)
            c.sparkle(int(round(mx)), int(round(my)), 1, 'pur_lt', core='white')
    # stand
    c.rect(ox + 9, oy + 33, ox + 24, oy + 36, 'org_dk'); c.rect(ox + 9, oy + 33, ox + 24, oy + 33, 'org')
    c.rect(ox + 5, oy + 37, ox + 28, oy + 40, 'org'); c.rect(ox + 5, oy + 37, ox + 28, oy + 37, 'org_lt')
    c.rect(ox + 1, oy + 41, ox + 32, oy + 45, 'org_lt'); c.rect(ox + 1, oy + 44, ox + 32, oy + 45, 'org')
    # glass
    c.ellipse(cx, cy, 15, 15, 'pur_dk')
    c.ellipse(cx + 1.5, cy + 2, 11, 11, 'pur', only_on={'pur_dk'})
    # inner core, breathing
    s = .5 + .5 * math.sin(2 * math.pi * t / N * 3)
    rr = 3 + round(2 * s)
    for y in range(c.h):
        for x in range(c.w):
            d = ((x + .5 - cx) ** 2 + (y + .5 - cy - 1) ** 2) ** .5
            if d <= rr and c.get(x, y) in ('pur', 'pur_dk'):
                c.set(x, y, 'pur_lt' if d > 1.2 or s < .6 else 'white')
    # two mist arcs swirling in opposite directions
    for arc, (spd, r0, amp) in enumerate([(2, 7.0, 2.6), (-3, 4.5, 1.5)]):
        a0 = 2 * math.pi * t / N * spd + arc * 2
        for k in range(18):
            a = a0 + k * .2
            r = r0 + amp * math.sin(a * .9 + arc)
            x = int(round(cx + r * math.cos(a))); y = int(round(cy + r * math.sin(a) * .92))
            if c.get(x, y) in ('pur', 'pur_dk', 'pur_lt'):
                c.set(x, y, 'pur_lt' if k > 4 else 'gls_lt')
    # the flare: a bright ripple from the middle out to the glass
    a = t - FLARE
    if 0 <= a < 14:
        r = 1 + a * 1.1
        for y in range(c.h):
            for x in range(c.w):
                d = ((x + .5 - cx) ** 2 + (y + .5 - cy) ** 2) ** .5
                if r - 1.6 <= d <= r and c.get(x, y) in ('pur', 'pur_dk', 'pur_lt', 'gls_lt'):
                    c.set(x, y, 'white' if a < 8 else 'pur_lt')
    # inner sparkles
    for (sx, sy, st) in [(-6, -8, 0), (6, -5, 40), (-4, 7, 70), (7, 6, 100), (1, -10, 20)]:
        aa = (t - st) % N
        if aa < 10: c.sparkle(cx + sx, cy + sy, 1 if 3 <= aa < 7 else 0, 'pur_lt', core='white')
    # glint
    c.rect(ox + 8, oy + 7, ox + 11, oy + 8, 'white'); c.rect(ox + 7, oy + 9, ox + 8, oy + 12, 'white'); c.set(ox + 6, oy + 11, 'white')
    draw_motes(False)
    c.outline('inkcool')
    c.shadow(cx, oy + 46, 13, 2, 'sh')
    draw_motes(True)
    # glints running along the stand
    g = (t * 2) % N
    if g < 34:
        gx = ox + 1 + g
        for yy in (oy + 41, oy + 42):
            if c.get(gx, yy) == 'org_lt': c.set(gx, yy, 'white')
    # the burst of sparks after the flare
    a = t - FLARE - 5
    if 0 <= a < 18:
        for k in range(8):
            ang = k * math.pi / 4 + .2
            d = 17 + a * 1.1
            x = cx + d * math.cos(ang); y = cy + d * math.sin(ang) * .9
            sz = 2 if a < 6 else (1 if a < 12 else 0)
            c.sparkle(int(round(x)), int(round(y)), sz, 'spark' if k % 2 else 'pur_lt', core='white')
    air_sparkles(c, t, [(3, 3, 2, 10), (48, 8, 1, 45), (46, 36, 2, 95), (2, 34, 1, 70)])
    return c

# ===================================================================== chest
LID = 70

def lid_offset(t):
    a = t - LID
    if a < 0 or a > 34: return 0
    if a < 4: return -round(7 * ease_out(a / 4))
    if a < 26: return -7 + (1 if (a // 4) % 2 else 0)
    if a < 30: return -round(7 * (1 - ease_in((a - 26) / 4)))
    return 0

def chest_frame(t):
    c = Canvas(58, 56)
    ox, oy = 6, 18
    ld = lid_offset(t)
    # body
    c.rect(ox + 4, oy + 18, ox + 41, oy + 31, 'wd')
    c.rect(ox + 4, oy + 18, ox + 41, oy + 20, 'wd_lt')
    c.rect(ox + 4, oy + 28, ox + 41, oy + 31, 'wd_dk')
    c.rect(ox + 19, oy + 18, ox + 26, oy + 31, 'gold_dk')
    c.rect(ox + 20, oy + 18, ox + 24, oy + 31, 'gold')
    c.rect(ox + 20, oy + 18, ox + 21, oy + 31, 'gold_lt')
    c.rect(ox + 18, oy + 19, ox + 27, oy + 25, 'gold_dk')
    c.rect(ox + 19, oy + 20, ox + 26, oy + 24, 'gold')
    c.rect(ox + 21, oy + 21, ox + 24, oy + 23, 'wd_dp')
    c.rect(ox + 4, oy + 30, ox + 41, oy + 31, 'wd_dp')
    # light spilling from the gap when the lid lifts
    if ld < 0:
        c.rect(ox + 5, oy + 18 + ld, ox + 40, oy + 17, 'gold_lt')
        c.rect(ox + 8, oy + 18 + ld // 2, ox + 37, oy + 18 + ld // 2, 'white')
    # lid
    ly = oy + ld
    for y in range(9, 19):
        for x in range(46):
            dx = (x + .5 - 22.5) / 19.5; dy = (y + .5 - 18.5) / 9.5
            if dx * dx + dy * dy <= 1.0 and y < 18:
                c.set(ox + x, ly + y, 'wd_lt' if y < 13 else 'wd')
    c.rect(ox + 3, ly + 16, ox + 42, ly + 17, 'gold_dk')
    c.rect(ox + 3, ly + 14, ox + 42, ly + 15, 'gold')
    c.rect(ox + 19, ly + 9, ox + 26, ly + 17, 'gold_dk')
    c.rect(ox + 20, ly + 9, ox + 24, ly + 17, 'gold')
    c.rect(ox + 20, ly + 9, ox + 21, ly + 17, 'gold_lt')
    # the glint that sweeps across the gold, twice a loop
    for g0 in (8, 48):
        a = t - g0
        if 0 <= a < 22:
            pos = -6 + a * 3.2
            for (x, y), v in list(c.px.items()):
                if v in ('gold', 'gold_lt', 'gold_dk'):
                    k = (x - ox) + (y - oy) * .6 - pos
                    if 0 <= k < 2: c.px[(x, y)] = 'white'
                    elif 2 <= k < 4: c.px[(x, y)] = 'gold_lt'
    c.outline('inkwarm')
    c.shadow(ox + 22, oy + 33, 19, 2, 'sh')
    # rays of golden light fanning out of the gap
    a = t - LID
    if 2 <= a < 28:
        gy = oy + 17 + ld // 2
        L = 6 + (a % 4) if a < 24 else 4
        for (sx, ang) in ((ox + 4, 200), (ox + 4, 225), (ox + 41, 340), (ox + 41, 315),
                          (ox + 13, 250), (ox + 32, 290), (ox + 22, 270)):
            ang = math.radians(ang)
            start = 2 if sx in (ox + 4, ox + 41) else 10
            for d in range(start, start + L + (4 if sx == ox + 22 else 0)):
                if (d + a) % 3 == 0: continue
                put(c, sx + d * math.cos(ang), gy + d * math.sin(ang), 'gold_lt' if d < start + L // 2 else 'gold', True)
    for k in range(8):
        s = LID + 3 + k * 2
        a = t - s
        if a < 0 or a > 30: continue
        r = random.Random(40 + k)
        vx = r.uniform(-1.0, 1.0); vy = -r.uniform(2.6, 3.3)
        x = ox + 21 + vx * a; y = oy + 16 + ld + vy * a + .2 * a * a
        if a > 8 and y > oy + 16 + lid_offset(t): continue
        x, y = int(round(x)), int(round(y))
        flip = (a // 2) % 3
        if flip == 0:
            c.rect(x, y, x + 2, y + 2, 'gold'); c.set(x, y, 'gold_lt'); c.rect(x, y + 2, x + 2, y + 2, 'gold_dk')
        elif flip == 1:
            c.rect(x + 1, y, x + 1, y + 2, 'gold_dk'); c.set(x + 1, y, 'gold_lt')
        else:
            c.rect(x, y, x + 2, y + 2, 'gold_dk'); c.set(x + 1, y + 1, 'gold')
        if a < 12 and k % 2 == 0: c.sparkle(x + 1, y - 3, 1, 'spark', core='white')
    # the thud: a puff of dust at the base
    a = t - LID - 30
    if 0 <= a < 8:
        for side in (-1, 1):
            for k in range(3):
                put(c, ox + 22 + side * (20 + a + k * 2), oy + 31 - k - a // 3, 'dust', True)
    air_sparkles(c, t, [(4, 8, 2, 0), (50, 10, 1, 30), (28, 2, 2, 60), (55, 26, 1, 90), (1, 24, 1, 15)])
    return c

# ================================================================== cauldron
BLOOP = 60

def cauldron_frame(t):
    c = Canvas(62, 64)
    ox, oy = 7, 18
    flare = 1.0 + (1.2 if 0 <= t - BLOOP - 12 < 10 else 0)
    # the fire under the pot, drawn first so the pot sits in front of it
    for x in range(ox + 11, ox + 37):
        k = x - ox
        h = 3 + 1.6 * math.sin(k * 1.7 + 2 * math.pi * t / N * 6) + 1.2 * math.sin(k * .9 - 2 * math.pi * t / N * 9)
        h = int(round(clamp(h * flare, 1, 10)))
        base = oy + 38
        for j in range(h):
            col = 'fire_r' if j < h * .35 else ('fire_o' if j < h * .7 else ('fire_y' if j < h - 1 else 'fire_w'))
            c.set(x, base - j, col)
    # embers from the fire
    for k in range(5):
        s = k * 24 + 5
        a = (t - s) % N
        if a < 14:
            put(c, ox + 14 + k * 5 + math.sin(a * .7) * 1.2, oy + 36 - a * .9, 'fire_y' if a < 7 else 'fire_o')
    for (lx, ly) in ((9, 40), (23, 42), (37, 40)):
        c.rect(ox + lx, oy + 26, ox + lx + 2, oy + ly, 'iron_dp')
    for hx in (1, 42):
        c.rect(ox + hx, oy + 13, ox + hx + 5, oy + 21, 'iron')
        c.clear(ox + hx + 2, oy + 15, ox + hx + 3, oy + 19)
    pcx, pcy = ox + 23.5, oy + 20
    c.ellipse(pcx, pcy, 18, 12, 'iron_dk')
    c.shade_dir(pcx, pcy, 18, 12, {'iron_dk'}, ('iron_dp', 'iron_dk', 'iron', -.42, .10))
    c.shade_dir(pcx, pcy, 18, 12, {'iron'}, ('iron', 'iron', 'iron_lt', -99.0, .46))
    # firelight on the bottom of the pot
    fl = 1 if (t // 3) % 3 else 0
    for (x, y), v in list(c.px.items()):
        if v in ('iron_dp', 'iron_dk', 'iron') and y >= pcy + 9 + fl and ox + 12 < x < ox + 36 and y <= pcy + 12:
            c.px[(x, y)] = 'org_dk' if y == pcy + 12 or (y == pcy + 11 and flare > 1) else 'iron_lt'
    c.ellipse(pcx, oy + 8, 19, 5, 'rim_dk')
    c.ellipse(pcx, oy + 7, 18, 4, 'rim')
    c.ellipse(pcx, oy + 8, 15, 3, 'grn_dp')
    c.ellipse(pcx, oy + 7.5, 14, 2, 'grn')
    # the brew's surface shimmer, drifting sideways
    for x in range(ox + 10, ox + 38):
        if (x + t // 3) % 7 < 2 and c.get(x, oy + 7) == 'grn': c.set(x, oy + 7, 'grn_lt')
    c.ellipse(ox + 19, oy + 7, 5, 1, 'grn_lt')
    # the big bloop: a dome that swells out of the brew
    a = t - BLOOP
    if 0 <= a < 12:
        r = 1.5 + a * 5.5 / 12
        bx, by = ox + 26, oy + 7
        for y in range(int(by - r - 1), int(by) + 1):
            for x in range(int(bx - r - 1), int(bx + r + 2)):
                if (x + .5 - bx) ** 2 + (y + .5 - by) ** 2 <= r * r:
                    c.set(x, y, 'grn')
        c.set(int(bx - r / 2), int(by - r + 1), 'grn_lt'); c.set(int(bx - r / 2) + 1, int(by - r + 1), 'white')
    c.outline('ink')
    c.shadow(ox + 23, oy + 43, 17, 2, 'sh')
    # little surface bubbles that swell and pop
    for k, (bx, st) in enumerate([(14, 0), (31, 17), (21, 41), (35, 63), (17, 88), (28, 104)]):
        a = (t - st) % N
        x, y = ox + bx, oy + 6
        if a < 6:
            c.set(x, y, 'grn_lt')
            if a >= 3: c.set(x, y - 1, 'grn_lt'); c.set(x + 1, y, 'grn_lt')
        elif a < 9:
            for (dx, dy) in ((-1, -1), (2, -1), (0, -2), (1, -2)):
                put(c, x + dx, y + dy - (a - 6), 'grn_lt' if a < 8 else 'grn', True)
    # steam wisps
    for k in range(9):
        s = k * 13 + (k * 7) % 5
        a = (t - s) % N
        if a >= 44: continue
        x = ox + 12 + (k * 11) % 24 + math.sin(a * .18 + k) * 2.2
        y = oy + 3 - a * .55
        col = 'stm1' if a < 24 else 'stm2'
        put(c, x, y, col, True); put(c, x, y - 1, col, True)
        if a < 18: put(c, x + 1, y, col, True)
    # the splash after the bloop
    a = t - BLOOP - 12
    if 0 <= a < 20:
        for k in range(10):
            r = random.Random(70 + k)
            vx = r.uniform(-1.3, 1.3); vy = -r.uniform(1.4, 2.4)
            x = ox + 26 + vx * a; y = oy + 5 + vy * a + .16 * a * a
            put(c, x, y, 'grn_lt' if a < 8 else 'grn')
            if a < 5: put(c, x, y + 1, 'grn')
        if a < 5:
            for (dx, dy) in ((-3, 0), (3, 0), (0, -3), (-2, -2), (2, -2)):
                put(c, ox + 26 + dx * (1 + a * .5), oy + 6 + dy * (1 + a * .5), 'white', True)
    air_sparkles(c, t, [(3, 10, 1, 20), (58, 14, 2, 80), (50, 2, 1, 50)])
    return c

# ====================================================================== book
FLIP = 70
RUNES = [["010", "111", "010"], ["110", "010", "011"], ["101", "010", "101"],
         ["111", "001", "011"], ["010", "101", "010"], ["100", "111", "001"]]

def book_frame(t):
    c = Canvas(58, 58)
    ox, oy = 4, 18
    c.rect(ox + 1, oy + 11, ox + 48, oy + 35, 'red')
    c.rect(ox + 0, oy + 14, ox + 49, oy + 32, 'red')
    c.rect(ox + 1, oy + 31, ox + 48, oy + 35, 'red_dk')
    c.rect(ox + 0, oy + 28, ox + 49, oy + 32, 'red_dk')
    c.rect(ox + 1, oy + 11, ox + 48, oy + 12, 'red_lt')
    for side in (0, 1):
        x0 = 6 if side == 0 else 26
        x1 = 24 if side == 0 else 44
        for i, y in enumerate(range(9, 31)):
            inset = max(0, 3 - i) if i < 4 else 0
            c.rect(ox + x0 + inset, oy + y, ox + x1 - inset, oy + y, 'pap')
        c.rect(ox + x0, oy + 28, ox + x1, oy + 30, 'pap_dk')
    c.rect(ox + 24, oy + 9, ox + 25, oy + 30, 'pap_dp')
    c.rect(ox + 6, oy + 10, ox + 9, oy + 29, 'pap_lt'); c.rect(ox + 27, oy + 10, ox + 30, oy + 29, 'pap_lt')
    c.rect(ox + 8, oy + 13, ox + 22, oy + 21, 'gold_dk')
    c.rect(ox + 9, oy + 14, ox + 21, oy + 20, 'pap_lt')
    for y in (24, 26, 28): c.rect(ox + 8, oy + y, ox + 21, oy + y, 'gold_dk')
    # the emblem glows in a slow pulse
    pulse = math.sin(2 * math.pi * t / N * 2)
    ec = 'gold_lt' if pulse > .5 else 'gold'
    c.ring(ox + 35, oy + 17, 7, 6, ec, thick=1)
    c.rect(ox + 32, oy + 14, ox + 33, oy + 16, ec); c.rect(ox + 37, oy + 14, ox + 38, oy + 16, ec)
    c.rect(ox + 33, oy + 17, ox + 37, oy + 17, ec); c.rect(ox + 34, oy + 18, ox + 36, oy + 20, ec)
    for y in (24, 26, 28): c.rect(ox + 28, oy + y, ox + 42, oy + y, 'gold_dk')
    # the page flip: the right page lifts, swings over the spine and lands
    a = t - FLIP
    if 0 <= a < 16:
        th = math.pi * ease_io(a / 16)
        xe = 25 + 19 * math.cos(th)
        lift = 6 * math.sin(th)
        lo, hi = (25, xe) if xe >= 25 else (xe, 25)
        back = xe < 25
        for x in range(int(math.floor(lo)), int(math.ceil(hi)) + 1):
            u = abs(x - 25) / 19 if 19 else 0
            top = 9 - lift * u; bot = 30 - lift * u * .3
            for y in range(int(round(top)), int(round(bot)) + 1):
                col = 'pap_dk' if back else 'pap'
                if y >= bot - 2: col = 'pap_dp' if back else 'pap_dk'
                c.set(ox + x, oy + y, col)
            c.set(ox + x, oy + int(round(top)) - 1, 'inkwarm')
        ex = int(round(xe))
        for y in range(int(round(9 - lift)), int(round(30 - lift * .3)) + 1):
            c.set(ox + ex, oy + y, 'inkwarm')
    c.outline('inkwarm')
    # glowing runes lifting off the pages
    for k in range(6):
        s = k * 20 + 3
        a = (t - s) % N
        if a >= 40: continue
        g = RUNES[k]
        x = ox + (9, 30, 15, 38, 20, 33)[k] + math.sin(a * .15 + k) * 2
        y = oy + 20 - a * .55
        col = 'gold_lt' if a < 16 else ('gold' if a < 30 else 'gold_dk')
        if a > 34 and a % 2: continue
        for yy in range(3):
            for xx in range(3):
                if g[yy][xx] == '1': put(c, x + xx, y + yy, col, True)
    # sparkle burst at the top of the spine as the page lands
    a = t - FLIP - 14
    if 0 <= a < 12:
        for k in range(6):
            ang = -math.pi / 2 + (k - 2.5) * .45
            d = 3 + a * 1.4
            c.sparkle(int(round(ox + 25 + d * math.cos(ang))), int(round(oy + 8 + d * math.sin(ang))),
                      2 if a < 4 else (1 if a < 8 else 0), 'spark', core='white')
    air_sparkles(c, t, [(6, 8, 2, 0), (20, 4, 1, 40), (40, 6, 2, 80), (55, 22, 1, 20), (1, 26, 1, 100)])
    return c

# ====================================================================== mage
SPR = [".............KKKK.", "...........KKKOOK.", "..........KKOOODK.", "........KKKOOODKK.", "......KKKOOOODDK..", "KKKKKKKOOOODDDKK..", "KOOOOOOOODDDDDK...", "KKDDDDOOOODDDDK...", ".KKKKDDDDOOODKK...", "....KKKKDDDDDDKK..", "....KEKKKKKDDDDKK.", "..KKKEKKEKKKKDDDKK", ".KKBKKKKOKKKKBKDDK", ".KBKKKKKKKKKKKBKKK", ".KBBBKKKBBBBBBBK..", "KKKBBBBBBKKKBBKK..", "KHHKBBBKKBBBBBBK..", "KHHKBBKKKBBBBBBK..", "KKKBBBOOKBBBBBBK..", ".KBKBBOOKBBBBBBK..", ".KBKBBKKKBBBBBKK..", ".KBBKBBBBKBBBBK...", ".KBBBKBBBKBBBBKK..", "KKBBBBKKBBKBBBBKK.", "KBBBBBBBBBBKKBBBK.", "KKKKKKKKKKKKKKKKK."]
MC = {'K': (20, 20, 26, 255), 'B': (31, 100, 168, 255), 'O': (240, 174, 50, 255),
      'D': (180, 120, 40, 255), 'E': (240, 174, 50, 255)}
CYAN = [(255, 255, 255), (216, 247, 255), (159, 230, 255), (95, 192, 255), (58, 134, 238), (37, 82, 184)]
GOLDS = [(255, 251, 230), (255, 231, 163), (255, 210, 122), (240, 174, 50), (201, 134, 42)]
GLOW = (111, 195, 255)
CELL = 4; MW, MH = 150, 150
MOX = (MW - 18 * CELL) // 2; MOY = 30
CAST = 100   # cast starts here in the 160-frame loop

def mage_pose(t):
    """bob (art px, + is down) and hand raise 0..1 and charge 0..1"""
    idle = round(-2 * (1 - math.cos(2 * math.pi * t / 80)) / 2)
    a = t - CAST
    if a < 0 or a >= 58: return idle, 0.0, 0.0
    if a < 6:  return idle + round(3 * ease_out(a / 6)), -.1, 0.0
    if a < 10: u = (a - 6) / 4; return round(3 - 8 * ease_out(u)), ease_out(u), 0.0
    if a < 21: return -5 - (a - 10) // 5, 1.0, (a - 10) / 11
    if a < 45: return -6 + (a - 21) // 8, 1.0, max(0, 1 - (a - 21) / 6)
    u = (a - 45) / 13
    return round(-3 * (1 - ease_io(u)) + idle * ease_io(u)), 1 - ease_io(u), 0.0

def mage_frame(t, glow_cache):
    im = Image.new('RGBA', (MW, MH), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bob, raise_, charge = mage_pose(t)
    a = t - CAST
    flash = max(0.0, 1 - (a - 21) / 18) if 21 <= a < 39 else 0.0
    breath = .5 + .5 * math.sin(2 * math.pi * t / 80 + math.pi)
    aura = clamp(.35 + .25 * breath + charge * .35 + flash * .7, 0, 1)
    oy = MOY + bob
    # soft glow (pre-blurred silhouette)
    g = glow_cache.copy()
    alpha = g.getchannel('A').point(lambda v: int(v * (.35 + aura * .55)))
    g.putalpha(alpha)
    im.alpha_composite(g, (0, bob))
    # dithered outer ring and solid inner ring
    d1, d2 = MAGE_RINGS
    for (x, y) in d2:
        bx, by = MOX + x * CELL, oy + y * CELL
        flip = (x + y + t // 3) & 1
        col = GLOW + (int(255 * aura * .5),)
        d.rectangle([bx + (2 if flip else 0), by, bx + (2 if flip else 0) + 1, by + 1], fill=col)
        d.rectangle([bx + (0 if flip else 2), by + 2, bx + (0 if flip else 2) + 1, by + 3], fill=col)
    ringcol = ((191, 234, 255) if aura > .85 else GLOW) + (int(255 * (.45 + aura * .55)),)
    for (x, y) in d1:
        d.rectangle([MOX + x * CELL, oy + y * CELL, MOX + x * CELL + 3, oy + y * CELL + 3], fill=ringcol)
    # shadow, a stepped ellipse that shrinks as he rises
    lift = clamp(-bob / 6, -.3, 1)
    sw = 56 * (1 - lift * .3); sa = int(90 * (1 - lift * .45))
    for k, dy in ((.55, -2), (.9, -1), (1, 0), (.9, 1), (.55, 2)):
        w = int(sw * k) // 2 * 2
        d.rectangle([MW // 2 - w // 2, MOY + 26 * CELL + 10 + dy, MW // 2 + w // 2 - 1, MOY + 26 * CELL + 10 + dy], fill=(0, 0, 0, sa))
    parts = mage_particles(t, raise_, bob)
    for p in parts:
        if not p[4]: draw_mp(d, p)
    # the body
    blink = t in (38, 39, 40, 128)
    raised = raise_ > .05
    for y, row in enumerate(SPR):
        for x, ch in enumerate(row):
            if ch == '.': continue
            if ch == 'E': ch = 'K' if blink else 'E'
            if ch == 'H': col = MC['B'] if raised else MC['O']
            else: col = MC[ch]
            d.rectangle([MOX + x * CELL, oy + y * CELL, MOX + x * CELL + 3, oy + y * CELL + 3], fill=col)
    if raised:
        hx, hy = hand_pos(raise_, bob)
        gl = charge + flash * .6
        if gl > 0:
            glim = Image.new('RGBA', (MW, MH), (0, 0, 0, 0))
            ImageDraw.Draw(glim).ellipse([hx - 6 - 8 * gl, hy - 6 - 8 * gl, hx + 6 + 8 * gl, hy + 6 + 8 * gl],
                                        fill=(200, 240, 255, int(200 * min(1, gl))))
            glim = glim.filter(ImageFilter.GaussianBlur(4))
            im.alpha_composite(glim)
        d.rectangle([hx - 8, hy - 8, hx + 7, hy + 7], fill=MC['K'])
        palm = (255, 243, 196, 255) if gl > .5 and t % 2 else MC['O']
        d.rectangle([hx - 4, hy - 4, hx + 3, hy + 3], fill=palm)
    for p in parts:
        if p[4]: draw_mp(d, p)
    # shockwave ring at the release
    if 21 <= a < 33:
        u = (a - 21) / 12
        R = 14 + 52 * ease_out(u)
        cy = MOY + 26 * CELL + 4 + bob
        for i in range(56):
            ang = i / 56 * 2 * math.pi
            x = int(MW / 2 + math.cos(ang) * R) // 2 * 2; y = int(cy + math.sin(ang) * R * .3) // 2 * 2
            d.rectangle([x, y, x + 1, y + 1], fill=(159, 230, 255, int(230 * (1 - u))))
    return im

def hand_pos(r, bob):
    hx = MOX + (0 + (-2 - 0) * r) * CELL + 8
    hy = MOY + (15 + (10 - 15) * r) * CELL + 8 + bob
    return int(hx) // 2 * 2, int(hy) // 2 * 2

def draw_mp(d, p):
    x, y, size, col, front = p
    x = int(round(x)) // 2 * 2; y = int(round(y)) // 2 * 2
    if size == 'plus':
        for (dx, dy) in ((0, 0), (-2, 0), (2, 0), (0, -2), (0, 2)):
            c = (255, 255, 255, col[3]) if (dx, dy) == (0, 0) else col
            d.rectangle([x + dx, y + dy, x + dx + 1, y + dy + 1], fill=c)
    else:
        d.rectangle([x, y, x + size - 1, y + size - 1], fill=col)

def pal_at(pal, u, alpha=255):
    return pal[min(len(pal) - 1, int(u * len(pal)))] + (alpha,)

def mage_particles(t, raise_, bob):
    out = []
    rnd = random.Random(11)
    # idle sparks drifting up off the aura, 26 of them spread round the loop
    edge = MAGE_RINGS[0]
    for k in range(26):
        s = rnd.randrange(NM); life = rnd.randint(22, 44)
        ex, ey = edge[rnd.randrange(len(edge))]
        sx = MOX + ex * CELL + rnd.uniform(0, 4); sy = MOY + ey * CELL + rnd.uniform(0, 4)
        vy = rnd.uniform(.5, 1.1); ph = rnd.uniform(0, 6.28)
        r = rnd.random(); size = 'plus' if r < .18 else (4 if r < .4 else 2)
        pal = GOLDS if rnd.random() < .22 else CYAN
        front = rnd.random() < .7
        a = (t - s) % NM
        if a >= life: continue
        if (a + k) % 9 == 0: continue            # retro flicker, same every loop
        u = a / life
        fade = int(255 * min(1, a / 4, (life - a) / 6))
        out.append((sx + math.sin(a * .25 + ph) * 2.5, sy - vy * a + bob * 0, size, pal_at(pal, u, fade), front))
    a = t - CAST
    hx, hy = hand_pos(1.0, mage_pose(t)[0])
    # charge: sparks pulled into the palm
    if 10 <= a < 22:
        rr = random.Random(21)
        for k in range(18):
            s = 10 + k * .6; life = 6
            aa = a - s
            ang = rr.uniform(0, 6.28); dist = rr.uniform(24, 44)
            if 0 <= aa < life:
                e = ease_in(aa / life)
                x = hx + math.cos(ang) * dist * (1 - e); y = hy + math.sin(ang) * dist * .8 * (1 - e)
                out.append((x, y, 2 if k % 3 else 4, pal_at(CYAN if k % 4 else GOLDS, aa / life * .5), True))
    # the swirl: sparks spiralling out round him, back half passing behind
    if 21 <= a < 21 + 40:
        rr = random.Random(31)
        cx = MW / 2
        for k in range(34):
            delay = k * .45 + rr.uniform(0, .6)
            life = rr.uniform(20, 26)
            r1 = rr.uniform(48, 64); rise = rr.uniform(38, 60); spin = rr.uniform(1.0, 1.3) * 2 * math.pi
            sq = rr.uniform(.32, .4); jit = rr.uniform(-3, 3)
            pal = GOLDS if rr.random() < .3 else CYAN
            size = 4 if rr.random() < .4 else 2
            aa = a - 21 - delay
            if aa < 0: continue
            if aa >= life:
                # pop into embers
                ab = aa - life
                if ab < 6:
                    u = 1.0; th = math.pi + spin * 1.0 + spin * .25
                    r0 = cx - hx
                    x = cx + math.cos(th) * r1 + jit; y = hy - rise + 4 + math.sin(th) * r1 * sq
                    for m in range(3):
                        ang = m * 2.1 + k
                        out.append((x + math.cos(ang) * ab * 1.5, y + math.sin(ang) * ab * 1.5 - ab * .5, 2,
                                    pal_at(pal, .5 + ab / 12, int(255 * (1 - ab / 6))), True))
                continue
            u = aa / life
            th = math.pi + spin * ease_out(u) + spin * .25 * u
            r0 = cx - hx
            r = r0 + (r1 - r0) * ease_out(min(1, u * 1.6))
            cyy = hy - rise * ease_in(u) + 4
            x = cx + math.cos(th) * r + jit; y = cyy + math.sin(th) * r * sq
            front = math.sin(th) > -.05
            col = pal_at(pal, u)
            # afterimages
            for j in (3, 2, 1):
                uj = max(0, (aa - j) / life)
                thj = math.pi + spin * ease_out(uj) + spin * .25 * uj
                rj = r0 + (r1 - r0) * ease_out(min(1, uj * 1.6))
                out.append((cx + math.cos(thj) * rj + jit, hy - rise * ease_in(uj) + 4 + math.sin(thj) * rj * sq, 2,
                            pal_at(pal, min(1, u + j * .12), int(255 * (.8 - j * .18))), front))
            out.append((x, y, size, col, front))
    return out

def mage_rings():
    sil = {(x, y) for y, r in enumerate(SPR) for x, ch in enumerate(r) if ch != '.'}
    def dil(s):
        o = set(s)
        for (x, y) in s:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)): o.add((x + dx, y + dy))
        return o
    d1 = dil(sil); d2 = dil(d1)
    return sorted(d1 - sil), sorted(d2 - d1), d2

MAGE_RINGS = mage_rings()[:2]

def mage_glow():
    _, _, d2 = mage_rings()
    g = Image.new('RGBA', (MW, MH), (0, 0, 0, 0)); dd = ImageDraw.Draw(g)
    for (x, y) in d2:
        dd.rectangle([MOX + x * CELL, MOY + y * CELL, MOX + x * CELL + 3, MOY + y * CELL + 3], fill=GLOW + (255,))
    a = g.filter(ImageFilter.GaussianBlur(7))
    b = g.filter(ImageFilter.GaussianBlur(2))
    out = Image.new('RGBA', (MW, MH), (0, 0, 0, 0))
    out.alpha_composite(a)
    b.putalpha(b.getchannel('A').point(lambda v: int(v * .5)))
    out.alpha_composite(b)
    return out

# ===================================================================== build
PAGES = [('page-health', potions_frame), ('page-profiles', orb_frame),
         ('page-saves', chest_frame), ('page-features', cauldron_frame),
         ('page-help', book_frame)]

def union_bbox(frames):
    box = None
    for f in frames:
        b = f.getbbox()
        if b is None: continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box

def write_strip(out, name, frames):
    box = union_bbox(frames)
    frames = [f.crop(box) for f in frames]
    w, h = frames[0].size
    sheet = Image.new('RGBA', (w, h * len(frames)), (0, 0, 0, 0))
    for i, f in enumerate(frames): sheet.alpha_composite(f, (0, i * h))
    sheet.save(os.path.join(out, name + '-anim.png'), optimize=True)
    frames[0].save(os.path.join(out, name + '.png'))
    return frames, (w, h, len(frames))

def build(out, only=None):
    os.makedirs(out, exist_ok=True)
    made = {}
    for name, fn in PAGES:
        if only and name not in only: continue
        frames = [fn(t).render(P, 2) for t in range(N)]
        made[name] = write_strip(out, name, frames)
    if not only or 'mage' in only:
        gc = mage_glow()
        frames = [mage_frame(t, gc) for t in range(NM)]
        made['mage'] = write_strip(out, 'mage', frames)
    return made

if __name__ == '__main__':
    import sys
    here = os.path.dirname(os.path.abspath(__file__))
    for k, (fr, info) in build(os.path.join(here, 'out'), sys.argv[1:] or None).items():
        print(k, info)
