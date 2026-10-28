"""Every picture the wizard uses, drawn twice: small for the tab strip and
bigger for the corner of the page. Each function returns a Canvas."""
from kit import Canvas
import math

# ---------------------------------------------------------------- crystal ball
ORB_FRAMES = 10

def orb_page(t=0):
    c = Canvas(34, 48)
    # the stand: three tiers, brightest at the bottom
    c.rect(9, 33, 24, 36, 'org_dk')
    c.rect(9, 33, 24, 33, 'org')
    c.rect(5, 37, 28, 40, 'org')
    c.rect(5, 37, 28, 37, 'org_lt')
    c.rect(1, 41, 32, 45, 'org_lt')
    c.rect(1, 44, 32, 45, 'org')
    # the glass
    c.ellipse(17, 18, 15, 15, 'pur_dk')
    c.ellipse(18.5, 20, 11, 11, 'pur', only_on={'pur_dk'})
    # the swirl, a lighter arc that drifts round the inside
    a0 = t * (2 * math.pi / ORB_FRAMES)
    for k in range(22):
        a = a0 + k * 0.19
        r = 6.5 + 3.2 * math.sin(a * 0.9)
        x = int(round(17 + r * math.cos(a)))
        y = int(round(18 + r * math.sin(a) * 0.92))
        for oy in (0, 1):
            if c.get(x, y + oy) in ('pur', 'pur_dk'): c.set(x, y + oy, 'pur_lt')
    # sparkles inside the glass, twinkling on their own clocks
    for i, (sx, sy, ph) in enumerate([(11, 10, 0), (23, 13, 3), (13, 25, 5),
                                      (24, 24, 2), (18, 8, 6)]):
        k = (t + ph) % ORB_FRAMES
        if k < 4:
            c.sparkle(sx, sy, 1 if k in (1, 2) else 0, 'pur_lt', core='white')
    # the hard glint, upper left, the thing that makes it read as glass
    c.rect(8, 7, 11, 8, 'white'); c.rect(7, 9, 8, 12, 'white'); c.set(6, 11, 'white')
    c.outline('inkcool')
    c.shadow(17, 46, 13, 2, 'sh')
    # sparkles OUTSIDE, after the outline so they stay loose in the air
    for (sx, sy, sz, ph) in [(2, 4, 2, 0), (31, 6, 1, 4), (29, 30, 2, 2), (3, 28, 1, 6)]:
        k = (t + ph) % ORB_FRAMES
        if k < 5: c.sparkle(sx, sy, sz if k in (2, 3) else max(0, sz - 1), 'spark')
    return c

def orb_tab():
    c = Canvas(20, 24)
    c.rect(5, 17, 14, 18, 'org_dk')
    c.rect(3, 19, 16, 20, 'org')
    c.rect(1, 21, 18, 23, 'org_lt')
    c.rect(1, 23, 18, 23, 'org')
    c.ellipse(9.5, 9.5, 8, 8, 'pur_dk')
    c.ellipse(10.5, 10.5, 5, 5, 'pur', only_on={'pur_dk'})
    c.set(8, 6, 'pur_lt'); c.set(13, 9, 'pur_lt'); c.set(9, 13, 'pur_lt')
    c.rect(5, 5, 6, 5, 'white'); c.set(4, 6, 'white')
    c.outline('inkcool')
    return c

# -------------------------------------------------------------------- cauldron
def cauldron_page(t=0):
    c = Canvas(48, 44)
    # legs first, splayed, so the pot sits on top of them
    for (lx, ly) in ((9, 40), (23, 42), (37, 40)):
        c.rect(lx, 26, lx + 2, ly, 'iron_dp')
    # the ear handles, hung off the sides
    for hx in (1, 42):
        c.rect(hx, 13, hx + 5, 21, 'iron')
        c.clear(hx + 2, 15, hx + 3, 19)
    # the pot
    c.ellipse(23.5, 20, 18, 12, 'iron_dk')
    c.shade_dir(23.5, 20, 18, 12, {'iron_dk'},
                ('iron_dp', 'iron_dk', 'iron', -0.42, 0.10))
    c.shade_dir(23.5, 20, 18, 12, {'iron'},
                ('iron', 'iron', 'iron_lt', -99.0, 0.46))
    # the rim: a periwinkle band wider than the pot, with the brew inside it
    c.ellipse(23.5, 8, 19, 5, 'rim_dk')
    c.ellipse(23.5, 7, 18, 4, 'rim')
    c.ellipse(23.5, 8, 15, 3, 'grn_dp')
    c.ellipse(23.5, 7.5, 14, 2, 'grn')
    for x in range(10, 38, 4):
        if (t + x) % 8 < 4: c.set(x, 7, 'grn_lt')
    c.ellipse(19, 7, 5, 1, 'grn_lt')
    c.outline('ink')
    c.shadow(23, 43, 17, 2, 'sh')
    # bubbles rising out of the brew, on a loop
    for (bx, ph) in [(13, 0), (18, 3), (24, 6), (29, 1), (34, 4), (16, 5), (31, 7)]:
        k = (t + ph) % 8
        y = 5 - k
        if y < 0: continue
        col = 'grn_lt' if k < 3 else ('grn' if k < 6 else 'grn_dk')
        c.set(bx, y, col)
        if k < 2: c.set(bx + 1, y, col)
    return c

def cauldron_tab():
    c = Canvas(24, 22)
    for (lx, ly) in ((4, 19), (11, 20), (18, 19)):
        c.rect(lx, 13, lx + 1, ly, 'iron_dp')
    c.ellipse(11.5, 11, 10, 6, 'iron_dk')
    c.shade_dir(11.5, 11, 10, 6, {'iron_dk'},
                ('iron_dp', 'iron_dk', 'iron', -0.40, 0.12))
    c.shade_dir(11.5, 11, 10, 6, {'iron'},
                ('iron', 'iron', 'iron_lt', -99.0, 0.50))
    c.ellipse(11.5, 5, 10, 3, 'rim_dk')
    c.ellipse(11.5, 4.5, 9, 2, 'rim')
    c.ellipse(11.5, 5, 7, 1, 'grn')
    c.set(8, 4, 'grn_lt')
    c.outline('ink')
    return c

# --------------------------------------------------------------------- potions
def _bottle(c, x, y, lt, mid, dk, tall=True):
    """One bottle: cork, glass neck, round belly, hard white specular."""
    c.rect(x + 4, y + 0, x + 9, y + 3, 'cork')
    c.rect(x + 4, y + 0, x + 5, y + 2, 'cork_lt')
    c.rect(x + 3, y + 4, x + 10, y + 6, 'red_dk')         # the collar
    c.rect(x + 3, y + 4, x + 10, y + 4, 'red')
    c.rect(x + 4, y + 7, x + 9, y + 10, 'gls')            # the neck
    c.rect(x + 4, y + 7, x + 5, y + 10, 'gls_lt')
    c.ellipse(x + 6.5, y + 16, 6, 6, dk)                  # the belly
    c.ellipse(x + 6, y + 15.5, 5, 5, mid, only_on={dk})
    c.ellipse(x + 5, y + 14.5, 3, 3, lt, only_on={mid})
    c.rect(x + 3, y + 12, x + 3, y + 14, 'white')         # the specular
    c.rect(x + 4, y + 12, x + 4, y + 12, 'white')
    c.rect(x + 2, y + 20, x + 11, y + 21, dk)             # a flat foot

def potions_page(t=0):
    c = Canvas(52, 34)
    _bottle(c, 1,  6, 'liq_r_lt', 'liq_r', 'liq_r_dk')
    _bottle(c, 19, 4, 'liq_b_lt', 'liq_b', 'liq_b_dk')
    _bottle(c, 37, 6, 'liq_g_lt', 'liq_g', 'liq_g_dk')
    c.outline('ink')
    for (bx, by, ph) in [(8, 20, 0), (26, 18, 3), (44, 20, 5),
                         (6, 24, 4), (28, 22, 1), (46, 24, 2)]:
        k = (t + ph) % 6
        if k < 3: c.set(bx, by - k * 2, 'white')
    for (sx, sy, ph) in [(15, 2, 0), (34, 1, 3), (50, 9, 4), (0, 12, 2)]:
        k = (t + ph) % 6
        if k < 3: c.sparkle(sx, sy, 1 if k == 1 else 0, 'spark')
    return c

def potions_tab():
    c = Canvas(22, 18)
    for (x, lt, mid, dk) in ((0, 'liq_r_lt', 'liq_r', 'liq_r_dk'),
                             (8, 'liq_b_lt', 'liq_b', 'liq_b_dk'),
                             (16, 'liq_g_lt', 'liq_g', 'liq_g_dk')):
        c.rect(x + 2, 1, x + 3, 2, 'cork')
        c.rect(x + 1, 3, x + 4, 4, 'red_dk')
        c.rect(x + 2, 5, x + 3, 7, 'gls')
        c.ellipse(x + 2.5, 12, 3, 3, dk)
        c.ellipse(x + 2, 11.5, 2, 2, mid, only_on={dk})
        c.set(x + 1, 10, 'white')
        c.rect(x + 0, 15, x + 5, 15, dk)
    c.outline('ink')
    return c

# ----------------------------------------------------------------------- chest
def chest_page(t=0):
    c = Canvas(46, 36)
    c.rect(4, 18, 41, 31, 'wd')                        # the body
    c.rect(4, 18, 41, 20, 'wd_lt')
    c.rect(4, 28, 41, 31, 'wd_dk')
    c.ellipse(22.5, 18, 19, 9, 'wd', only_on={None})   # the lid
    for y in range(9, 19):
        for x in range(46):
            dx = (x + 0.5 - 22.5) / 19.5; dy = (y + 0.5 - 18.5) / 9.5
            if dx*dx + dy*dy <= 1.0:
                c.set(x, y, 'wd_lt' if y < 13 else 'wd')
    c.rect(3, 16, 42, 17, 'gold_dk')                   # the band under the lid
    c.rect(3, 14, 42, 15, 'gold')
    c.rect(19, 9, 26, 31, 'gold_dk')                   # the band down the middle
    c.rect(20, 9, 24, 31, 'gold')
    c.rect(20, 9, 21, 31, 'gold_lt')
    c.rect(18, 19, 27, 25, 'gold_dk')                  # the lock
    c.rect(19, 20, 26, 24, 'gold')
    c.rect(21, 21, 24, 23, 'wd_dp')
    c.rect(4, 30, 41, 31, 'wd_dp')
    c.outline('inkwarm')
    c.shadow(22, 33, 19, 2, 'sh')
    # a hint of gold light escaping the lid, and sparkles above it
    if t % 4 in (1, 2):
        for x in range(6, 40, 3): c.set(x, 17, 'gold_lt')
    for (sx, sy, sz, ph) in [(6, 4, 2, 0), (38, 3, 1, 3), (22, 1, 2, 5), (44, 12, 1, 2)]:
        k = (t + ph) % 8
        if k < 4: c.sparkle(sx, sy, sz if k in (1, 2) else max(0, sz - 1), 'spark')
    return c

def chest_tab():
    c = Canvas(24, 17)
    c.rect(2, 8, 21, 14, 'wd')
    c.rect(2, 8, 21, 9, 'wd_lt')
    c.rect(2, 13, 21, 14, 'wd_dk')
    for y in range(3, 9):
        for x in range(24):
            dx = (x + 0.5 - 11.5) / 10.5; dy = (y + 0.5 - 8.5) / 5.5
            if dx*dx + dy*dy <= 1.0: c.set(x, y, 'wd_lt' if y < 6 else 'wd')
    c.rect(2, 7, 21, 7, 'gold')
    c.rect(10, 3, 13, 14, 'gold_dk')
    c.rect(10, 3, 11, 14, 'gold')
    c.rect(9, 8, 14, 11, 'gold_dk')
    c.rect(10, 9, 13, 10, 'gold')
    c.set(11, 9, 'wd_dp'); c.set(12, 9, 'wd_dp')
    c.outline('inkwarm')
    return c

# ------------------------------------------------------------------------ book
def book_page(t=0):
    c = Canvas(50, 38)
    # the crimson cover, sitting a little proud of the pages all round
    c.rect(1, 11, 48, 35, 'red')
    c.rect(0, 14, 49, 32, 'red')
    c.rect(1, 31, 48, 35, 'red_dk')
    c.rect(0, 28, 49, 32, 'red_dk')
    c.rect(1, 11, 48, 12, 'red_lt')
    # the two pages, meeting at the spine
    for side in (0, 1):
        x0 = 6 if side == 0 else 26
        x1 = 24 if side == 0 else 44
        for i, y in enumerate(range(9, 31)):
            inset = max(0, 3 - i) if i < 4 else 0
            c.rect(x0 + inset, y, x1 - inset, y, 'pap')
        c.rect(x0, 28, x1, 30, 'pap_dk')
    c.rect(24, 9, 25, 30, 'pap_dp')                     # the spine crease
    c.rect(6, 10, 9, 29, 'pap_lt'); c.rect(27, 10, 30, 29, 'pap_lt')
    # a gold panel on the left page, an emblem on the right
    c.rect(8, 13, 22, 21, 'gold_dk')
    c.rect(9, 14, 21, 20, 'pap_lt')
    for y in (24, 26, 28):
        c.rect(8, y, 21, y, 'gold_dk')
    c.ring(35, 17, 7, 6, 'gold', thick=1)
    c.rect(32, 14, 33, 16, 'gold'); c.rect(37, 14, 38, 16, 'gold')
    c.rect(33, 17, 37, 17, 'gold')
    c.rect(34, 18, 36, 20, 'gold')
    for y in (24, 26, 28):
        c.rect(28, y, 42, y, 'gold_dk')
    c.outline('inkwarm')
    # sparkles in the air around it, the reference's signature
    for (sx, sy, sz, ph) in [(6, 3, 2, 0), (16, 6, 1, 4), (30, 2, 2, 2),
                             (44, 6, 1, 6), (48, 20, 1, 3), (0, 20, 1, 5)]:
        k = (t + ph) % 8
        if k < 4: c.sparkle(sx, sy, sz if k in (1, 2) else max(0, sz - 1), 'spark')
    return c

def book_tab():
    c = Canvas(26, 18)
    c.rect(0, 5, 25, 17, 'red')
    c.rect(0, 14, 25, 17, 'red_dk')
    for side in (0, 1):
        x0 = 3 if side == 0 else 14
        x1 = 11 if side == 0 else 22
        for i, y in enumerate(range(4, 15)):
            inset = 1 if i < 2 else 0
            c.rect(x0 + inset, y, x1 - inset, y, 'pap')
    c.rect(12, 4, 13, 14, 'pap_dp')
    c.rect(3, 4, 4, 13, 'pap_lt'); c.rect(14, 4, 15, 13, 'pap_lt')
    for y in (6, 8, 10, 12):
        c.rect(4, y, 10, y, 'gold_dk'); c.rect(15, y, 21, y, 'gold_dk')
    c.outline('inkwarm')
    return c

# ------------------------------------------------------------------------- hat
def hat_tab():
    # Built from a left edge and a right edge rather than from an ellipse,
    # because a wizard's hat has to LEAN and no ellipse will do that. The tip
    # sits left of the brim's middle and the body sweeps down to the right.
    c = Canvas(24, 23)
    L = [7, 7, 7, 7, 6, 6, 6, 5, 5, 5, 4, 4, 3, 3, 2, 2]
    R = [9, 9, 10, 11, 11, 12, 13, 14, 14, 15, 16, 17, 17, 18, 19, 20]
    for y in range(16):
        c.rect(L[y], y, R[y], y, 'pur')
        c.rect(L[y], y, L[y] + 1, y, 'pur_lt')
        c.rect(max(L[y] + 2, R[y] - 2), y, R[y], y, 'pur_dk')
    c.rect(1, 16, 22, 18, 'gold')
    c.rect(1, 16, 22, 16, 'gold_lt')
    c.rect(1, 19, 22, 20, 'gold_dk')
    c.rect(2, 21, 21, 21, 'gold_dp')
    c.outline('inkcool')
    c.sparkle(3, 4, 2, 'spark')
    c.sparkle(21, 8, 1, 'spark')
    return c

# ------------------------------------------------------------------ the lights
def light(lt, mid, dk, ink='ink'):
    """One 14x14 gem: mid fill, lighter upper left, hard white specular,
    darker lower right, and a lit rim along the bottom."""
    c = Canvas(14, 14)
    c.ellipse(6.5, 6.5, 6, 6, dk)
    c.ellipse(5.5, 5.5, 5, 5, mid, only_on={dk})
    c.ellipse(4.5, 4.5, 3, 3, lt, only_on={mid})
    c.rect(3, 3, 4, 3, 'white'); c.rect(3, 4, 3, 4, 'white')
    for (x, y) in [(6, 12), (7, 12), (8, 11), (5, 12), (9, 11)]:
        if c.get(x, y) == dk: c.set(x, y, mid)
    c.outline(ink)
    return c
