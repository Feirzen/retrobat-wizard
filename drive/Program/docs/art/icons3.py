"""
icons3.py - the v3 icon set (2026-10-14).

Every icon is drawn on a 32 x 32 grid so it stays crisp at 1x (the rail),
2x (the Home tiles) and 3x (full screen). Each one has a still,
wizard\\icon-<name>.png, and a 60-frame strip, wizard\\icon-<name>-anim.png
(3 seconds at 20 frames a second). Frame 0 of every strip IS the still, so
the wizard can stop a strip on frame 0 and nothing jumps.

    python icons3.py            everything, into .\\out
    python icons3.py gears      just one

Borrows kit.py (Canvas) and pal.py (the colours). Nothing on the drive runs
this; it is kept so the icons can be redrawn.
"""
import math, os, sys
from PIL import Image
from kit import Canvas
from pal import PAL

N = 60          # frames per strip
W = H = 32

P = dict(PAL)
P.update({
    'gld_hi': (255, 246, 200, 255),
    'blu_lt': (150, 208, 255, 255), 'blu': (70, 140, 230, 255), 'blu_dk': (40, 80, 170, 255), 'blu_dp': (28, 46, 110, 255),
    'mir_lt': (214, 240, 255, 255), 'mir': (140, 196, 240, 255), 'mir_dk': (84, 132, 204, 255), 'mir_dp': (60, 84, 160, 255),
    'mc_red': (255, 18, 18, 255), 'mc_red_dk': (187, 0, 0, 255), 'mc_hi': (255, 214, 214, 255), 'mc_ink': (20, 6, 8, 255),
    'mc_white': (255, 255, 255, 255),
    'flp': (62, 72, 92, 255), 'flp_lt': (96, 108, 132, 255), 'flp_dk': (40, 46, 62, 255),
    'met_lt': (232, 236, 244, 255), 'met': (184, 190, 204, 255), 'met_dk': (120, 126, 142, 255),
    'lbl': (250, 246, 236, 255), 'lbl_ln': (180, 172, 160, 255),
    'sprk1': (255, 236, 150, 255), 'sprk2': (255, 200, 80, 200), 'sprk3': (230, 150, 40, 130),
    'pad': (205, 207, 214, 255), 'pad_lt': (236, 238, 244, 255), 'pad_dk': (150, 152, 164, 255), 'pad_hole': (40, 40, 52, 255),
    'glow1': (255, 240, 170, 170), 'glow2': (255, 220, 120, 90),
})


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * max(0.0, min(1.0, t)))


def pulse(f, a, b):
    """0 outside frames a..b, rises to 1 and back inside them."""
    if f < a or f > b: return 0.0
    return math.sin(math.pi * (f - a) / float(b - a))


def finish(c, ink='ink'):
    c.outline(ink)
    return c


# --------------------------------------------------------------------------
#  GEARS - Settings. Two gilded gears that mesh and turn, bob gently, and
#  throw off a few golden sparks once per loop.
# --------------------------------------------------------------------------
def gear(c, cx, cy, r_body, r_tooth, teeth, rot, hole):
    """One gear, drawn FLAT (no light and shadow) so turning it is just the
    same picture rotated (Steven, 2026-10-14: "design them once and rotate
    each exactly as they are"). Each pixel is sampled 6 x 6 times and goes
    to whatever covers most of it, which keeps the edges steady as it turns."""
    SS = 6
    for y in range(H):
        for x in range(W):
            votes = {}
            for sy in range(SS):
                for sx in range(SS):
                    dx = x + (sx + 0.5) / SS - cx; dy = y + (sy + 0.5) / SS - cy
                    r = math.hypot(dx, dy)
                    if r > r_tooth + 0.2: continue
                    a = math.atan2(dy, dx) - rot
                    ph = (a * teeth / (2 * math.pi)) % 1.0
                    tooth = 0.22 < ph < 0.58
                    if r > r_body and not tooth: continue
                    if r <= hole: col = 'ink'
                    elif abs(r - r_body * 0.58) < 0.7: col = 'gold_dk'
                    elif r < r_body * 0.58: col = 'gold_lt'
                    else: col = 'gold'
                    votes[col] = votes.get(col, 0) + 1
            total = sum(votes.values())
            if total * 2 >= SS * SS:
                c.set(x, y, max(votes, key=votes.get))


def icon_gears(f):
    c = Canvas(W, H)
    t = f / N
    bob = round(math.sin(2 * math.pi * t) * 1.0)
    big_rot = 2 * math.pi / 8 * t
    small_rot = -2 * math.pi / 6 * t + math.pi / 6
    gear(c, 12.5, 19.5 + bob, 7.0, 9.6, 8, big_rot, 1.6)
    gear(c, 24.5, 8.0 + bob, 4.4, 6.4, 6, small_rot, 1.1)
    finish(c, 'inkwarm')
    # sparks: golden bits that float up and fade, frames 18-50
    for k, (sx, start, drift) in enumerate([(20, 18, 1), (8, 24, -1), (28, 30, 0)]):
        age = f - start
        if 0 <= age < 20:
            x = sx + round(drift * age / 7.0)
            y = (12 - age // 2) if k != 2 else (3 - age // 4)
            col = 'sprk1' if age < 7 else ('sprk2' if age < 14 else 'sprk3')
            if 0 <= y < H and c.get(x, y) is None:
                c.set(x, y, col)
    return c


# --------------------------------------------------------------------------
#  CHEST - Games. A three-quarter view so it has depth: front face, a darker
#  side face, a domed lid. Once per loop the lid lifts, light spills out and
#  two coins hop.
# --------------------------------------------------------------------------
def poly(c, pts, col):
    """Fill a polygon given in pixel corners (even-odd, pixel centres)."""
    ys = [p[1] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        yc = y + 0.5
        xs = []
        n = len(pts)
        for k in range(n):
            (x1, y1), (x2, y2) = pts[k], pts[(k + 1) % n]
            if (y1 <= yc < y2) or (y2 <= yc < y1):
                xs.append(x1 + (yc - y1) * (x2 - x1) / (y2 - y1))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            for x in range(int(math.ceil(a - 0.5)), int(math.floor(b - 0.5)) + 1):
                c.set(x, y, col)


def icon_chest(f):
    """Games. Seen from above and to the left, so the lid's TOP shows as well
    as the front and the right side (Steven, 2026-10-14: "only two sides, no
    top"). Once per loop the lid lifts, light spills out and two coins hop."""
    c = Canvas(W, H)
    glow = pulse(f, 14, 40)
    lift = round(3 * glow)
    DX, DY = 5, 4                 # how far the back of the box sits up and right
    L, R, T, M, B = 3, 21, 11, 17, 28   # front face: left, right, lid top, seam, bottom
    # body: front, then the right side
    poly(c, [(L, M), (R + 1, M), (R + 1, B), (L, B)], 'wd')
    poly(c, [(R + 1, M), (R + 1 + DX, M - DY), (R + 1 + DX, B - DY), (R + 1, B)], 'wd_dk')
    for x in range(L, R + 1): c.set(x, B - 1, 'wd_dk')
    for x in range(L, R + 1): c.set(x, 22, 'wd_dk')                  # a plank line
    # light from inside while the lid is up
    if lift > 0:
        poly(c, [(L, M - lift), (R + 1, M - lift), (R + 1 + DX, M - DY - lift), (L + DX, M - DY - lift)], 'gold_lt')
        poly(c, [(L, M), (R + 1, M), (R + 1, M - lift), (L, M - lift)], 'glow1')
    ly = -lift
    # lid: top (light), front (mid), side (dark)
    poly(c, [(L, T + ly), (R + 1, T + ly), (R + 1 + DX, T - DY + ly), (L + DX, T - DY + ly)], 'wd_lt')
    poly(c, [(L, T + ly), (R + 1, T + ly), (R + 1, M + ly), (L, M + ly)], 'wd')
    poly(c, [(R + 1, T + ly), (R + 1 + DX, T - DY + ly), (R + 1 + DX, M - DY + ly), (R + 1, M + ly)], 'wd_dk')
    for x in range(L, R + 1): c.set(x, M - 1 + ly, 'wd_dk')           # the lid's lower edge
    # gold bands that run over the top and down the front
    for bx in (6, 17):
        for y in range(T + ly, B):
            if M + ly <= y < M: continue
            c.set(bx, y, 'gold'); c.set(bx + 1, y, 'gold_dk')
        for k in range(DY + 1):
            xx = bx + round(k * DX / DY); yy = T + ly - k
            c.set(xx, yy, 'gold_lt'); c.set(xx + 1, yy, 'gold')
    # gold corner on the back edge of the side
    for y in range(T - DY + ly, B - DY):
        if M - DY + ly <= y < M - DY: continue
        c.set(R + 1 + DX - 1, y, 'gold_dk')
    # lock
    c.rect(10, M - 2, 13, M + 2, 'gold')
    c.rect(10, M - 2, 13, M - 2, 'gold_lt')
    c.rect(11, M, 12, M + 1, 'gold_dp')
    finish(c, 'inkwarm')
    if glow > 0.2:
        for (x, y) in [(6, 4 + ly), (21, 3 + ly), (14, 2 + ly)]:
            if glow > 0.6: c.sparkle(x, y, 1, 'sprk2', 'sprk1')
            else: c.set(x, y, 'sprk1')
    # coins hop out
    for k, (cx0, start) in enumerate([(10, 18), (17, 24)]):
        age = f - start
        if 0 <= age < 18:
            yy = 10 - round(9 * math.sin(math.pi * age / 18.0)) + ly // 2
            xx = cx0 + (-1 if k == 0 else 1) * (age // 6)
            c.set(xx, yy, 'gold'); c.set(xx + 1, yy, 'gold_dk'); c.set(xx, yy - 1, 'gold_lt'); c.set(xx + 1, yy - 1, 'gold')
    # a glint that slides along the top edge while it rests
    if 46 <= f < 56:
        gx = L + 1 + (f - 46) * 2
        if c.get(gx, T) == 'wd_lt': c.set(gx, T, 'gld_hi')
    return c


# --------------------------------------------------------------------------
#  CRYSTAL BALL - Social. Purple sphere on a gold stand. Stars orbit inside;
#  once per loop it flares.
# --------------------------------------------------------------------------
def icon_ball(f):
    c = Canvas(W, H)
    cx, cy, r = 16, 13, 10
    c.ellipse(cx, cy, r, r, 'pur')
    c.shade_dir(cx, cy, r, r, {'pur'}, ('pur_dk', 'pur', 'pur_lt', -0.35, 0.55), lx=-0.8, ly=-0.6)
    # inner swirl
    t = f / N
    for k in range(3):
        a = 2 * math.pi * (t + k / 3.0)
        x = cx + round(5.5 * math.cos(a)); y = cy + round(3.0 * math.sin(a))
        c.set(x, y, 'pur_lt')
        a2 = a - 0.5
        c.set(cx + round(5.5 * math.cos(a2)), cy + round(3.0 * math.sin(a2)), 'pur_lt')
    fl = pulse(f, 24, 44)
    if fl > 0:
        rr = 1 + round(3 * fl)
        c.ellipse(cx, cy, rr, rr, 'pur_lt')
        if fl > 0.5: c.ellipse(cx, cy, rr - 1, rr - 1, 'white')
    # specular
    c.set(11, 8, 'white'); c.set(12, 7, 'white'); c.set(11, 9, 'gls_lt'); c.set(13, 7, 'gls_lt')
    # stand
    c.rect(11, 23, 20, 24, 'gold')
    c.rect(9, 25, 22, 27, 'gold_dk')
    c.rect(9, 25, 22, 25, 'gold')
    c.rect(11, 23, 20, 23, 'gold_lt')
    finish(c, 'inkcool')
    # orbiting sparkle outside, and flare rays
    a = 2 * math.pi * t
    sx = cx + round(13 * math.cos(a)); sy = cy + round(4 * math.sin(a)) - 1
    if c.get(sx, sy) is None: c.set(sx, sy, 'pur_lt')
    if fl > 0.4:
        for (dx, dy) in [(-12, 0), (12, 0), (0, -12)]:
            c.set(cx + dx, cy + dy, 'pur_lt')
    return c


# --------------------------------------------------------------------------
#  MIRROR - Play online. A hand mirror in the Terraria "magic mirror" spirit:
#  round blue glass in a gold rim on a handle. A shine sweeps the glass and
#  the glass swirls once per loop.
# --------------------------------------------------------------------------
def icon_mirror(f):
    c = Canvas(W, H)
    cx, cy, r = 16, 12, 10
    c.ellipse(cx, cy, r, r, 'gold')
    c.shade_dir(cx, cy, r, r, {'gold'}, ('gold_dk', 'gold', 'gold_lt', -0.3, 0.5), lx=-0.8, ly=-0.6)
    gr = 7.6
    c.ellipse(cx, cy, gr, gr, 'mir')
    c.shade_dir(cx, cy, gr, gr, {'mir'}, ('mir_dk', 'mir', 'mir_lt', -0.45, 0.55), lx=-0.7, ly=-0.7)
    # handle
    c.rect(15, 22, 17, 23, 'gold_dk')
    c.rect(14, 24, 18, 25, 'gold')
    c.rect(15, 26, 17, 29, 'wd')
    c.rect(15, 26, 15, 29, 'wd_lt')
    c.rect(14, 30, 18, 30, 'gold_dk')
    # gems on the rim
    c.set(16, 2, 'red_lt'); c.set(16, 3, 'red')
    c.set(6, 12, 'liq_b_lt'); c.set(26, 12, 'liq_b_lt')
    # swirl in the glass
    sw = pulse(f, 20, 50)
    t = f / N
    if sw > 0:
        for k in range(14):
            a = 2 * math.pi * (k / 14.0) * 1.6 + 2 * math.pi * t * 2
            rr = 1 + k * 0.42
            x = cx + round(rr * math.cos(a)); y = cy + round(rr * math.sin(a))
            if (x - cx) ** 2 + (y - cy) ** 2 <= 49:
                c.set(x, y, 'mir_lt' if k % 2 else 'white')
    # moving shine: two diagonal streaks that sweep across
    off = ((f * 0.5) % 30) - 12
    for d in (0, 3):
        for i in range(-8, 9):
            x = int(cx + i + off + d); y = int(cy - i)
            if (x - cx) ** 2 + (y - cy) ** 2 <= 46 and c.get(x, y) in ('mir', 'mir_lt', 'mir_dk'):
                c.set(x, y, 'mir_lt' if d else 'white')
    # fixed corner highlight
    c.set(11, 8, 'white'); c.set(12, 7, 'white'); c.set(11, 9, 'mir_lt')
    finish(c, 'inkcool')
    if sw > 0.6:
        c.sparkle(26, 3, 1, 'mir_lt', 'white')
        c.sparkle(5, 20, 0, 'mir_lt')
    return c


# --------------------------------------------------------------------------
#  POTIONS - Saves. Three little bottles: red, blue, green. Bubbles rise all
#  the time; once per loop the blue cork pops.
# --------------------------------------------------------------------------
def bottle(c, x0, liq, f, phase, pop=0):
    # body: round flask 8 wide, neck 3 wide
    cx = x0 + 4
    c.ellipse(cx, 22.5, 4, 4.5, liq + '_x')
    for y in range(13, 19): c.set(cx - 1, y, 'gls'); c.set(cx, y, 'gls'); c.set(cx + 1, y, 'gls_lt' if y < 15 else 'gls')
    c.rect(cx - 2, 18, cx + 2, 18, 'gls')
    # cork
    cy0 = 11 - pop
    c.rect(cx - 1, cy0, cx + 1, cy0 + 1, 'cork')
    c.set(cx - 1, cy0, 'cork_lt')
    if pop == 0:
        c.rect(cx - 2, 12, cx + 2, 12, 'red_dk')
    # liquid tones
    for (x, y), v in list(c.px.items()):
        if v == liq + '_x':
            dx = x + 0.5 - cx; dy = y + 0.5 - 22.5
            t = -dx * 0.8 - dy * 0.5
            c.px[(x, y)] = 'liq_%s_lt' % liq if t > 1.6 else ('liq_%s' % liq if t > -1.8 else 'liq_%s_dk' % liq)
    c.set(cx - 2, 20, 'white'); c.set(cx - 2, 21, 'gls_lt')


def icon_potions(f):
    c = Canvas(W, H)
    pop = round(4 * pulse(f, 20, 34))
    bottle(c, 1, 'r', f, 0)
    bottle(c, 12, 'b', f, 20, pop)
    bottle(c, 23, 'g', f, 40)
    finish(c, 'inkwarm')
    # bubbles
    for k, (bx, ph) in enumerate([(5, 0), (16, 13), (27, 27), (4, 31), (28, 45)]):
        age = (f + ph) % 30
        if age < 18:
            y = 25 - age // 3
            if y >= 18: c.set(bx + (age // 6) % 2, y, 'white' if age < 9 else 'gls_lt')
    if pop > 0:
        c.sparkle(16, 6 - pop // 2, 1 if pop > 2 else 0, 'liq_b_lt', 'white')
    return c


# --------------------------------------------------------------------------
#  BOOK - Help. An open spellbook. The rune glows and a page lifts and
#  settles once per loop.
# --------------------------------------------------------------------------
def icon_book(f):
    c = Canvas(W, H)
    # cover
    c.rect(2, 10, 29, 25, 'red')
    c.rect(2, 24, 29, 25, 'red_dk')
    c.rect(2, 10, 29, 10, 'red_lt')
    # pages
    c.rect(4, 8, 15, 23, 'pap')
    c.rect(16, 8, 27, 23, 'pap')
    c.rect(4, 8, 15, 8, 'pap_lt'); c.rect(16, 8, 27, 8, 'pap_lt')
    c.rect(15, 8, 16, 23, 'pap_dk')
    c.rect(4, 22, 27, 23, 'pap_dk')
    # text lines on the left
    for y in (11, 13, 15, 17, 19):
        c.rect(6, y, 13, y, 'pap_dp' if y != 11 else 'pap_dk')
    # rune on the right
    g = pulse(f, 6, 40)
    rc = 'gold' if g < 0.3 else ('gold_lt' if g < 0.7 else 'gld_hi')
    for (x, y) in [(21, 11), (22, 11), (20, 12), (23, 12), (19, 13), (24, 13), (19, 14), (24, 14), (20, 15), (23, 15), (21, 16), (22, 16),
                   (21, 13), (22, 14), (21, 14), (22, 13), (21, 18), (22, 18), (20, 19), (23, 19)]:
        c.set(x, y, rc)
    finish(c, 'inkwarm')
    if g > 0.6:
        c.sparkle(25, 5, 1, 'sprk2', 'sprk1')
    if g > 0.85:
        c.set(18, 4, 'sprk1')
    return c


# --------------------------------------------------------------------------
#  HEARTS - Health and repair. Three hearts in the Minecraft shape (the 9x9
#  sprite). A healing wave runs along them once per loop.
# --------------------------------------------------------------------------
HEART = [
    '.XX.XX...',
    'XrrXrrX..',
    'XhrrrrrX.',
    'XrrrrrrX.',
    '.XrrrrX..',
    '..XrrX...',
    '...XX....',
]
# The Minecraft heart, 9 wide including its outline. Columns 0-7 used.
HEART = [
    '.XX.XX.',
    'XhhXrrX',
    'XhrrrrX',
    'XrrrrdX',
    '.XrrdX.',
    '..XdX..',
    '...X...',
]


def icon_hearts(f):
    c = Canvas(W, H)
    for k in range(3):
        x0 = 1 + k * 10
        wave = pulse(f, 8 + k * 8, 24 + k * 8)
        y0 = 13 - round(3 * wave)
        flash = wave > 0.75
        for y, row in enumerate(HEART):
            for x, ch in enumerate(row):
                # draw each heart at 1.5x by doubling odd columns: keep it 2x instead
                col = {'X': 'mc_ink', 'r': 'mc_red', 'h': 'mc_hi', 'd': 'mc_red_dk'}.get(ch)
                if col is None: continue
                if flash and ch in 'rhd': col = 'mc_white' if ch == 'h' else 'mc_hi'
                c.set(x0 + x, y0 + y, col)
    return c


def icon_hearts_big(f):
    """Three Minecraft hearts, every heart pixel 2 x 2, so the picture is 48
    wide rather than 32 (Steven, 2026-10-14: three, not two). A healing wave
    runs along them once per loop."""
    c = Canvas(48, 32)
    for k in range(3):
        x0 = 2 + k * 15
        wave = pulse(f, 8 + k * 9, 26 + k * 9)
        y0 = 10 - round(3 * wave)
        flash = wave > 0.7
        for y, row in enumerate(HEART):
            for x, ch in enumerate(row):
                col = {'X': 'mc_ink', 'r': 'mc_red', 'h': 'mc_hi', 'd': 'mc_red_dk'}.get(ch)
                if col is None: continue
                if flash and ch in 'rhd': col = 'mc_white' if ch == 'h' else 'mc_hi'
                c.rect(x0 + 2 * x, y0 + 2 * y, x0 + 2 * x + 1, y0 + 2 * y + 1, col)
    for k, (sx, start) in enumerate([(9, 14), (24, 23), (39, 32)]):
        age = f - start
        if 0 <= age < 14:
            c.set(sx, 7 - age // 3, 'grn_lt' if age < 8 else 'grn')
            if age < 5: c.set(sx - 1, 7 - age // 3, 'grn'); c.set(sx + 1, 7 - age // 3, 'grn')
    return c


# --------------------------------------------------------------------------
#  FLOPPY - This drive. A 3.5" disk, slate blue, metal shutter, paper label.
#  The shutter slides open and back once per loop and a shine crosses it.
# --------------------------------------------------------------------------
def icon_floppy(f):
    c = Canvas(W, H)
    c.rect(4, 4, 27, 27, 'flp')
    c.rect(4, 4, 27, 4, 'flp_lt'); c.rect(4, 4, 4, 27, 'flp_lt')
    c.rect(5, 27, 27, 27, 'flp_dk'); c.rect(27, 5, 27, 27, 'flp_dk')
    c.clear(27, 4, 27, 5); c.clear(26, 4, 26, 4)          # the cut corner
    # shutter
    sl = round(5 * pulse(f, 16, 40))
    c.rect(9, 4, 21, 12, 'met')
    c.rect(9, 4, 21, 4, 'met_lt')
    c.rect(9 + sl, 6, 21, 12, 'met')
    # the window in the shutter and the disk behind it
    c.rect(16 + sl, 6, 18 + sl, 11, 'flp_dk')
    if sl > 0:
        for x in range(10, 10 + sl):
            for y in range(6, 12): c.set(x, y, 'iron_dk')
    c.rect(9, 12, 21, 12, 'met_dk')
    # label
    c.rect(8, 16, 23, 27, 'lbl')
    for y in (18, 20, 22):
        c.rect(10, y, 21, y, 'lbl_ln')
    c.rect(10, 18, 15, 18, 'red')
    # write-protect notch
    c.rect(5, 24, 6, 25, 'flp_dk')
    finish(c, 'ink')
    # shine sweeping the shutter
    g = f - 44
    if 0 <= g < 12:
        x = 9 + g
        for y in range(5, 12):
            if 9 <= x - (y - 5) // 2 <= 21: c.set(x - (y - 5) // 2, y, 'met_lt')
    return c


# --------------------------------------------------------------------------
#  KEY - Admin. A gold key on the diagonal that glints.
# --------------------------------------------------------------------------
def icon_key(f):
    c = Canvas(W, H)
    c.ring(10, 10, 6, 6, 'gold', thick=3)
    c.shade_dir(10, 10, 6, 6, {'gold'}, ('gold_dk', 'gold', 'gold_lt', -0.3, 0.45), lx=-0.8, ly=-0.6)
    for i in range(14):
        x = 14 + i; y = 14 + i
        if x < W and y < H:
            c.set(x, y, 'gold'); c.set(x + 1, y, 'gold_dk'); c.set(x, y + 1, 'gold_dk')
    for (x, y) in [(22, 26), (23, 27), (21, 27), (25, 23), (26, 24), (26, 22)]:
        c.set(x, y, 'gold')
    finish(c, 'inkwarm')
    g = pulse(f, 30, 44)
    if g > 0:
        k = round(10 * (f - 30) / 14.0)
        c.set(14 + k, 14 + k, 'gld_hi')
        if g > 0.6: c.sparkle(6, 5, 1, 'sprk2', 'sprk1')
    return c


# --------------------------------------------------------------------------
#  CONTROLLER - the rail's Controllers button. The Xbox-style pad from
#  Steven's own picture (wizard\pro-controller.png), shrunk onto the grid.
#  Still; it nods once per loop.
# --------------------------------------------------------------------------
_PAD = None


def pad_grid():
    """Steven's controller picture (docs\\art\\pad-source.png) shrunk to 28
    pixels wide. Background is found by flooding in from the edges, so the
    stick and button holes stay holes."""
    global _PAD
    if _PAD is not None: return _PAD
    src = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pad-source.png')).convert('L')
    w = 28; h = round(src.height * w / src.width)
    sm = src.resize((w, h), Image.BOX)
    on = [[sm.getpixel((x, y)) > 140 for x in range(w)] for y in range(h)]
    out = [[False] * w for _ in range(h)]
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if not (0 <= x < w and 0 <= y < h) or out[y][x] or on[y][x]: continue
        out[y][x] = True
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    _PAD = (w, h, on, out)
    return _PAD


def icon_controller(f):
    c = Canvas(W, H)
    w, h, on, outside = pad_grid()
    nod = 1 if 30 <= f < 36 else 0
    ox = (W - w) // 2; oy = (H - h) // 2 + nod
    for y in range(h):
        for x in range(w):
            if not outside[y][x]:
                col = 'pad_lt' if y < 3 else ('pad_dk' if y > h - 6 else 'pad')
                c.set(ox + x, oy + y, col)
    hole = 'pad_hole'
    # the sticks, d-pad and face buttons, placed from the source picture
    for (sx, sy) in [(5, 4), (16, 8)]:
        c.rect(ox + sx, oy + sy + 1, ox + sx + 3, oy + sy + 2, hole)
        c.rect(ox + sx + 1, oy + sy, ox + sx + 2, oy + sy + 3, hole)
    c.rect(ox + 10, oy + 8, ox + 10, oy + 11, hole); c.rect(ox + 9, oy + 9, ox + 12, oy + 10, hole)
    c.rect(ox + 9, oy + 9, ox + 11, oy + 10, hole)
    for (bx, by) in [(21, 3), (19, 5), (23, 5), (21, 7)]:
        c.rect(ox + bx, oy + by, ox + bx + 1, oy + by + 1, hole)
    finish(c, 'ink')
    return c


ICONS = {
    'gears': icon_gears, 'chest': icon_chest, 'ball': icon_ball, 'mirror': icon_mirror,
    'potions': icon_potions, 'book': icon_book, 'hearts': icon_hearts_big, 'floppy': icon_floppy,
    'key': icon_key, 'controller': icon_controller,
}


def build(name, out):
    fn = ICONS[name]
    frames = [fn(i).render(P) for i in range(N)]
    frames[0].save(os.path.join(out, 'icon-%s.png' % name))
    fw, fh = frames[0].size
    strip = Image.new('RGBA', (fw, fh * N), (0, 0, 0, 0))
    for i, im in enumerate(frames): strip.paste(im, (0, i * fh))
    strip.save(os.path.join(out, 'icon-%s-anim.png' % name), optimize=True)
    return frames


if __name__ == '__main__':
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
    os.makedirs(out, exist_ok=True)
    names = sys.argv[1:] or list(ICONS)
    for n in names: build(n, out)
    print('built', ', '.join(names))
