"""
wordmark3.py - "THE RETROBAT WIZARD" with fire that rises (2026-10-14).

Steven: put "The" where "Steven's" was, fire across all of it, and the fire
should float UP, not fall.

The letters are the old wordmark's own pixel font. That picture is 3 screen
pixels per font pixel, so it is read at 1/3 size (one sample per 3x3 cell),
"STEVEN'S" is swapped for "THE" (T and E lifted from STEVEN'S itself, H drawn
in the same style), the old fire is thrown away, and new fire is drawn:
value noise that scrolls UPWARD through a flame-shaped falloff sitting on
the top edge of every letter, plus embers that drift up and fade. Every
moving part repeats exactly every N frames, so the loop has no seam.

    python wordmark3.py <old wordmark.png> <out folder>

Writes wordmark.png (frame 0) and wordmark-anim.png (N frames stacked).
The wizard plays the strip at 50 ms a frame.
"""
import math, os, random, sys
from PIL import Image

N = 40            # frames: 2 seconds at 20 a second
SCALE = 3
TOP_ROOM = 9      # native pixels of sky above "THE" for the flames

INK = (3, 7, 8, 255)
COL = {'#': INK, 'L': (126, 203, 255, 255), 'M': (43, 126, 199, 255),
       'D': (20, 78, 133, 255), 'W': (255, 255, 255, 255)}
FIRE = [(255, 250, 220, 255), (255, 224, 112, 255), (255, 138, 32, 255), (196, 42, 24, 255), (120, 20, 20, 255)]


def read_native(path):
    a = Image.open(path).convert('RGBA')
    nw, nh = a.width // SCALE, a.height // SCALE
    rev = {v: k for k, v in COL.items()}
    g = {}
    for j in range(nh):
        for i in range(nw):
            p = a.getpixel((SCALE * i + 1, SCALE * j + 1))
            if p in rev: g[(i, j)] = rev[p]
    return g, nw, nh


def build(src, out):
    g, nw, nh = read_native(src)
    # line 1 (STEVEN'S) is native rows 7-15, line 2 is rows 17-25.
    line2 = {(x, y): v for (x, y), v in g.items() if 17 <= y <= 25 and 8 <= x <= 98}
    T = {(x - 35, y - 7): v for (x, y), v in g.items() if 35 <= x <= 41 and 7 <= y <= 15}
    E = {(x - 41, y - 7): v for (x, y), v in g.items() if 41 <= x <= 47 and 7 <= y <= 15}
    # H in the same hand: stems mid blue, the crossbar light, a white
    # highlight at the top left, the stem feet dark.
    H = {}
    body = ['X...X', 'X...X', 'X...X', 'XXXXX', 'X...X', 'X...X', 'X...X']
    for y, row in enumerate(body):
        for x, ch in enumerate(row):
            if ch != 'X': continue
            if y == 3 and 0 < x < 4: c = 'L'
            elif y == 0 and x == 0: c = 'W'
            elif y == 0: c = 'L'
            elif y == 6: c = 'D'
            else: c = 'M'
            H[(x + 1, y + 1)] = c
    for (x, y) in list(H.keys()):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in H: H.setdefault((x + dx, y + dy), None)
    H = {k: (v if v is not None else '#') for k, v in H.items()}

    # T and E keep only their letter (no fire, the cut may catch a neighbour's
    # edge column; it is outline either way).
    word = {}
    cx = 0
    for glyph in (T, H, E):
        w = max(x for x, _ in glyph) + 1
        for (x, y), v in glyph.items(): word[(cx + x, y)] = v
        cx += w - 1           # outlines overlap by one, like the original
    ww = max(x for x, _ in word) + 1
    xs2 = [x for x, _ in line2]
    mid = (min(xs2) + max(xs2)) // 2
    ox = mid - ww // 2
    text = {}
    for (x, y), v in word.items(): text[(x + ox, y + 7 + TOP_ROOM)] = v
    for (x, y), v in line2.items(): text[(x, y + TOP_ROOM)] = v
    W = nw; Hh = nh - 3 + TOP_ROOM          # drop the empty rows at the bottom
    # where each column's flames sit: just above the top-most text pixel
    base = {}
    for x in range(W):
        ys = [y for (xx, y) in text if xx == x]
        if ys: base[x] = min(ys)
    # a little fire either side, on the word ends
    rnd = random.Random(7)
    P = 24                                    # noise period in native rows
    NOISE = [[rnd.random() for _ in range(P)] for _ in range(W + 2)]

    def noise(x, y):
        y0 = math.floor(y); fy = y - y0
        a = NOISE[x][y0 % P]; b = NOISE[x][(y0 + 1) % P]
        return a + (b - a) * fy

    TONGUE = [0.45 + 0.9 * (0.5 + 0.5 * math.sin(x * 0.9 + rnd.random())) ** 2 for x in range(W + 2)]
    embers = [(rnd.randrange(W), rnd.randrange(N), rnd.choice((1, 2))) for _ in range(26)]

    frames = []
    for f in range(N):
        im = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
        px = im.load()
        shift = f * P / float(N)              # one whole noise period per loop
        for x, by in base.items():
            # flame height per column breathes on a slow sine, also looping
            hmax = (5.5 + 2.2 * math.sin(2 * math.pi * (f / N) + x * 0.45)) * TONGUE[x]
            for d in range(1, 10):
                y = by - d
                if y < 0: break
                n = (noise(x, d + shift) * 0.7 + noise(x + 1, d * 0.5 + shift) * 0.3)
                heat = (1.0 - d / max(1.0, hmax)) * 0.9 + (n - 0.5) * 1.1
                if heat <= 0.22: continue
                k = 0 if heat > 0.95 else (1 if heat > 0.7 else (2 if heat > 0.45 else (3 if heat > 0.25 else 4)))
                if k == 4 and n < 0.55: continue
                px[x, y] = FIRE[k]
        # embers: rise from the flames and fade, each on its own loop
        for (ex, ph, speed) in embers:
            if ex not in base: continue
            life = N // speed
            age = (f * speed + ph) % N
            y = base[ex] - 4 - age * 12 // N
            x = ex + (1 if (age // 8) % 2 else 0)
            if 0 <= y < Hh and 0 <= x < W:
                px[x, y] = FIRE[1] if age < N // 3 else (FIRE[2] if age < 2 * N // 3 else FIRE[3])
        # letters on top of the fire
        for (x, y), v in text.items():
            if 0 <= x < W and 0 <= y < Hh: px[x, y] = COL[v]
        frames.append(im.resize((W * SCALE, Hh * SCALE), Image.NEAREST))

    os.makedirs(out, exist_ok=True)
    frames[0].save(os.path.join(out, 'wordmark.png'))
    fw, fh = frames[0].size
    strip = Image.new('RGBA', (fw, fh * N), (0, 0, 0, 0))
    for i, fr in enumerate(frames): strip.paste(fr, (0, i * fh))
    strip.save(os.path.join(out, 'wordmark-anim.png'), optimize=True)
    return frames


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
