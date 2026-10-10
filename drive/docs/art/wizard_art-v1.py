# Pixel art for the Setup Wizard's tabs, drawn on the same grid and from the
# same palette as mage.png and the wordmark so it all reads as one picture.
from PIL import Image

C = {
 '.': (0,0,0,0),
 'K': (3,7,8,255),          # the outline black the mage uses
 'W': (255,255,255,255),
 'w': (226,229,236,255),
 'B': (43,126,199,255),     # wordmark blue
 'H': (126,203,255,255),    # its highlight
 'b': (20,78,133,255),      # its shadow
 'G': (255,194,60,255),     # mage hat gold
 'g': (213,153,39,255),
 'o': (145,106,41,255),     # dark gold
 'S': (98,105,122,255),     # grey iron, lit
 's': (66,72,86,255),       # grey iron, mid
 'N': (42,46,56,255),       # grey iron, shadow
 'n': (26,29,36,255),       # grey iron, deepest
 'E': (47,168,79,255),      # status green
 'e': (32,120,56,255),
 'A': (229,184,59,255),     # status amber
 'a': (168,132,38,255),
 'R': (224,82,77,255),      # status red
 'r': (160,52,48,255),
 'M': (119,119,119,255),    # status grey
 'm': (80,80,80,255),
 'L': (86,214,124,255),     # cauldron brew, lit
 'l': (44,150,80,255),      # cauldron brew, shadow
 'P': (150,80,190,255),     # potion purple
 'p': (104,54,133,255),
 'D': (120,72,40,255),      # wood
 'd': (78,46,26,255),
 'T': (168,120,66,255),     # light wood
 # per-status highlights, so a green gem highlights green and not blue
 '1': (146,236,172,255),
 '2': (255,229,140,255),
 '3': (255,166,160,255),
 '4': (196,196,196,255),
}

def draw(grid, scale=1):
    h = len(grid); w = max(len(r) for r in grid)
    im = Image.new('RGBA', (w, h), (0,0,0,0))
    px = im.load()
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            px[x, y] = C.get(ch, (0,0,0,0))
    if scale != 1:
        im = im.resize((w*scale, h*scale), Image.NEAREST)
    return im

# --- the status light, one 14x14 gem, four colours -------------------------
# Drawn once and recoloured, so all four are the same shape to the pixel.
LIGHT = [
 '....KKKKKK....',
 '..KKHHHHHHKK..',
 '.KKHHHHXXHHKK.',
 '.KHHHHXXXXXHK.',
 'KKHHXXXXXXXXKK',
 'KHHXXXXXXXXXXK',
 'KHXXXXXXXXXXSK',
 'KHXXXXXXXXXSSK',
 'KKXXXXXXXXSSKK',
 '.KXXXXXXXSSSK.',
 '.KKXXXXXSSSKK.',
 '..KKXXXSSSKK..',
 '....KKKKKKK...',
 '.....KKKK.....',
]
def light(main, shade, hi):
    return draw([r.replace('X', main).replace('H', hi).replace('S', shade)
                 for r in LIGHT])

# --- the cauldron ----------------------------------------------------------
# Rows 0..6 are the bubble field, filled in per animation frame.
CAULDRON = [
 '..............................',
 '..............................',
 '..............................',
 '..............................',
 '..............................',
 '..............................',
 '..............................',
 '..KKKKKKKKKKKKKKKKKKKKKKKKKK..',
 '.KKGGGGGGGGGGGGGGGGGGGGGGGGKK.',
 '.KggLLLLLLLLLLLLLLLLLLLLLLggK.',
 '.KSLLLLLLLLLLLLLLLLLLLLLLLLSK.',
 '.KSllllllllllllllllllllllllSK.',
 '.KSSllllllllllllllllllllllSSK.',
 '..KSSSSSSSSSSSSSSSSSSSSSSSSK..',
 '..KSSSSSSSSSSSSSSSSSSSSSSSK...',
 '...KsssssssssssssssssssssK....',
 '...KNsssssssssssssssssssNK....',
 '....KNNNNNNNNNNNNNNNNNNNK.....',
 '.....KnnnnnnnnnnnnnnnnnK......',
 '......KKKKKKKKKKKKKKKKK.......',
 '.......K...K.......K...K......',
 '......KK...KK.....KK...KK.....',
 '..............................',
]
BUBBLES = [(5,0), (10,3), (15,6), (20,1), (24,4), (8,5), (18,7)]
BUBBLE_FRAMES = 8

def cauldron_frame(t):
    g = [list(r) for r in CAULDRON]
    for (x, phase) in BUBBLES:
        k = (t + phase) % BUBBLE_FRAMES
        y = 7 - k
        if y < 0:
            continue
        ch = 'H' if k < 3 else ('B' if k < 6 else 'b')
        g[y][x] = ch
        if k < 2:                      # a fat bubble just off the brew
            g[y][x+1] = ch
    # the brew's surface shimmers a little too
    if t % 4 in (1, 2):
        for x in range(4, 26, 5):
            g[9][x] = 'L'
    return [''.join(r) for r in g]

# --- the potion shelf ------------------------------------------------------
POTIONS = [
 '..............................',
 '.....KKK.........KKK..........',
 '.....KwK.........KwK..........',
 '.KKK.KwK........KKwKK.........',
 '.KwK.KwK........KwwwK.........',
 'KKwKKKwwwK.....KKwwwwK........',
 'KwwwKKwwwwK....KwwwwwK........',
 'KwwwwKwwwwK...KKwwwwwwK.......',
 'KEEEEKwwwwwK..KwAAAAAAK.......',
 'KEEEEKKRRRRK..KAAAAAAAK.......',
 'KEEEEEKRRRRRK.KAAAAAAAK.......',
 'KEEEEEKRRRRRK.KAAAAAAAK.......',
 'KeEEEEKRRRRRK.KAAAAAAAK.......',
 'KeeEEEKrRRRRK.KaAAAAAAK.......',
 'KKeeeeKrrRRRK.KaaAAAAAK.......',
 '.KKKKKKKrrrrK.KKaaaaaaK.......',
 '.......KKKKKK..KKKKKKKK.......',
 '..............................',
]

# --- the save chest --------------------------------------------------------
CHEST = [
 '..............................',
 '.....KKKKKKKKKKKKKKKK.........',
 '...KKDDDDDDDDDDDDDDDDKK.......',
 '..KDTTTTTTTTTTTTTTTTTTDK......',
 '..KDTTTTTTTTTTTTTTTTTTDK......',
 '..KDddddddddddddddddddDK......',
 '..KGGGGGGGGGGGGGGGGGGGGK......',
 '..KgggggggggggggggggggGK......',
 '..KDTTTTTTTTKGGKTTTTTTDK......',
 '..KDTTTTTTTTKGGKTTTTTTDK......',
 '..KDTTTTTTTTKKKKTTTTTTDK......',
 '..KDdTTTTTTTTTTTTTTTTdDK......',
 '..KDddddddddddddddddddDK......',
 '...KDDDDDDDDDDDDDDDDDDK.......',
 '....KKKKKKKKKKKKKKKKKK........',
 '..............................',
]

# --- the crystal ball ------------------------------------------------------
# Rows 1..12 are the glass; the glint moves across it per frame.
ORB = [
 '..............................',
 '......KKKKKKKK................',
 '....KKHHHHHHHHKK..............',
 '...KHHHHHHHHHHHHK.............',
 '..KHHHHHHHHHHHHHHK............',
 '..KHHHHHHHHHHHHHHK............',
 '.KHHHHHHHHHHHHHHHHK...........',
 '.KBBHHHHHHHHHHHHHBK...........',
 '.KBBBBHHHHHHHHHBBBK...........',
 '..KBBBBBBBHHBBBBBBK...........',
 '..KbBBBBBBBBBBBBBbK...........',
 '...KbbBBBBBBBBBbbK............',
 '....KKbbbbbbbbbKK.............',
 '......KKKKKKKK................',
 '....KKKKKKKKKKKKKK............',
 '...KGGGGGGGGGGGGGGK...........',
 '..KGggggggggggggggGK..........',
 '..KGGGGGGGGGGGGGGGGK..........',
 '..KooooooooooooooooK..........',
 '...KKKKKKKKKKKKKKKK...........',
 '..............................',
]
GLINTS = [ (5,3),(6,3),(5,4),(4,4),(4,5),(5,5),(6,4),(7,3),(8,3),(7,4) ]

def orb_frame(t):
    g = [list(r) for r in ORB]
    # a small comma-shaped glint that drifts around the upper-left of the glass
    n = len(GLINTS)
    for i in range(3):
        x, y = GLINTS[(t*1 + i) % n]
        if g[y][x] in ('H', 'B'):
            g[y][x] = 'W'
    return [''.join(r) for r in g]

# --- the help book ---------------------------------------------------------
BOOK = [
 '..............................',
 '...KKKKKKKKKKKKKKKKKKKKKK.....',
 '..KBBBBBBBBBKKBBBBBBBBBBK.....',
 '.KBwwwwwwwwwKKwwwwwwwwwwBK....',
 'KBwwwwwwwwwwKKwwwwwwwwwwwBK...',
 'KBwKKKKKKwwwKKwwwKKKKKKwwBK...',
 'KBwwwwwwwwwwKKwwwwwwwwwwwBK...',
 'KBwKKKKKKKwwKKwwKKKKKKKwwBK...',
 'KBwwwwwwwwwwKKwwwwwwwwwwwBK...',
 'KBwKKKKKKwwwKKwwwKKKKKwwwBK...',
 'KBwwwwwwwwwwKKwwwwwwwwwwwBK...',
 'KBwKKKKKKKwwKKwwKKKKKKKwwBK...',
 'KBwwwwwwwwwwKKwwwwwwwwwwwBK...',
 '.KBbbbbbbbbbKKbbbbbbbbbbBK....',
 '..KBBBBBBBBBKKBBBBBBBBBBK.....',
 '...KKKKKKKKKKKKKKKKKKKKKK.....',
 '..............................',
]


# --- the wizard's hat (the Play tab) ---------------------------------------
HAT = [
 '..............................',
 '.....K........................',
 '....KHK.......................',
 '...KHHHK......................',
 '....KHK.....KKK...............',
 '.....K.....KHHBK..............',
 '..........KHHBBBK.............',
 '..........KHBBBBK.............',
 '.........KHHBBBBK.............',
 '.........KHBBBBBBK............',
 '........KHHBBBBBBK............',
 '........KHBBBBBBBbK...........',
 '.......KHHBBBBBBBbK...........',
 '.......KHBBBBBBBBbbK..........',
 '......KHHBBBBBBBBbbK..........',
 '......KHBBBBBBBBBbbbK.........',
 '.....KHHBBBBBBBBBbbbK.........',
 '.....KHBBBBBBBBBBbbbbK........',
 '....KGGGGGGGGGGGGGGGGGK.......',
 '...KGGGGGGGGGGGGGGGGGGGK......',
 '...KgggggggggggggggggggGK.....',
 '..KoooooooooooooooooooooGK....',
 '..KKKKKKKKKKKKKKKKKKKKKKKK....',
 '..............................',
]

STATES = [('E','e','1'), ('A','a','2'), ('R','r','3'), ('M','m','4')]

def _union_bbox(frames):
    box = None
    for f in frames:
        b = f.getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0],b[0]), min(box[1],b[1]),
                                     max(box[2],b[2]), max(box[3],b[3]))
    return box

def build(out='/home/claude/work/art/'):
    strip = Image.new('RGBA', (14*4, 14), (0,0,0,0))
    for i, (m, s, hi) in enumerate(STATES):
        strip.alpha_composite(light(m, s, hi), (i*14, 0))
    strip.save(out+'lights.png')

    made = {}
    statics = [('tab-play',HAT), ('tab-health',POTIONS), ('tab-saves',CHEST),
               ('tab-help',BOOK)]
    for name, grid in statics:
        im = draw(grid).crop(draw(grid).getbbox())
        im.save(out+name+'.png'); made[name] = im.size

    # animated ones: frames stacked vertically, same shape as wordmark-anim.png
    for name, fn, count in [('tab-features', cauldron_frame, BUBBLE_FRAMES),
                            ('tab-profiles', orb_frame, len(GLINTS))]:
        frames = [draw(fn(t)) for t in range(count)]
        box = _union_bbox(frames)
        frames = [f.crop(box) for f in frames]
        w, h = frames[0].size
        sheet = Image.new('RGBA', (w, h*count), (0,0,0,0))
        for i, f in enumerate(frames):
            sheet.alpha_composite(f, (0, i*h))
        sheet.save(out+name+'-anim.png')
        frames[0].save(out+name+'.png')     # the still, if animation is off
        made[name] = frames[0].size
        made[name+'-anim'] = sheet.size
    return strip, made

if __name__ == '__main__':
    out = '/home/claude/work/art/'
    strip, made = build(out)
    for k in sorted(made): print(k, made[k])
    names = ['tab-play','tab-health','tab-profiles','tab-saves','tab-features','tab-help']
    ims = [Image.open(out+n+'.png') for n in names]
    W = sum(i.width for i in ims) + 20*(len(ims)+1)
    H = max(i.height for i in ims)
    sheet = Image.new('RGBA', ((W)*3, (H+20)*3+120), (27,27,34,255))
    x = 60
    for i in ims:
        b = i.resize((i.width*3, i.height*3), Image.NEAREST)
        sheet.alpha_composite(b, (x, 30)); x += b.width + 60
    sheet.alpha_composite(strip.resize((14*4*4,14*4), Image.NEAREST), (60, H*3+70))
    sheet.convert('RGB').save(out+'wizard-art-sheet.png')
