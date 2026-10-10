"""Small pixel-art toolkit. Chunky shapes, tinted dark outlines, hard speculars.
Everything is drawn on an integer grid, one character per pixel."""
from PIL import Image

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = {}
    def set(self, x, y, c):
        if c is None: return
        if 0 <= x < self.w and 0 <= y < self.h: self.px[(x, y)] = c
    def get(self, x, y): return self.px.get((x, y))
    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.set(x, y, c)
    def ellipse(self, cx, cy, rx, ry, c, only_on=None):
        # cx,cy may be half-integers; rx,ry are radii in pixels
        for y in range(self.h):
            for x in range(self.w):
                dx = (x + 0.5 - cx) / (rx + 0.5)
                dy = (y + 0.5 - cy) / (ry + 0.5)
                if dx*dx + dy*dy <= 1.0:
                    if only_on is None or self.get(x, y) in only_on:
                        self.set(x, y, c)
    def ring(self, cx, cy, rx, ry, c, thick=1):
        inner = set()
        for y in range(self.h):
            for x in range(self.w):
                dx = (x + 0.5 - cx) / (rx - thick + 0.5)
                dy = (y + 0.5 - cy) / (ry - thick + 0.5)
                if dx*dx + dy*dy <= 1.0: inner.add((x, y))
        for y in range(self.h):
            for x in range(self.w):
                dx = (x + 0.5 - cx) / (rx + 0.5)
                dy = (y + 0.5 - cy) / (ry + 0.5)
                if dx*dx + dy*dy <= 1.0 and (x, y) not in inner: self.set(x, y, c)
    def body(self):
        return set(self.px.keys())
    def outline(self, c, chars=None):
        """One-pixel border around every filled pixel, 8-connected corners included
        so nothing leaks diagonally. Drawn only into empty space."""
        filled = set(k for k, v in self.px.items() if chars is None or v in chars)
        edge = set()
        for (x, y) in filled:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    p = (x + dx, y + dy)
                    if p not in self.px: edge.add(p)
        for (x, y) in edge: self.set(x, y, c)
    def shade_dir(self, cx, cy, rx, ry, on, tones, lx=1.0, ly=0.25):
        """Re-tone an already-filled shape by how much each pixel faces the
        light, so the highlight follows the silhouette instead of sitting on
        it as a circle. tones is (dark, mid, light) with the cut points."""
        (dark, mid, light, c1, c2) = tones
        for (x, y) in list(self.px.keys()):
            if self.px[(x, y)] not in on: continue
            dx = (x + 0.5 - cx) / (rx + 0.5)
            dy = (y + 0.5 - cy) / (ry + 0.5)
            t = dx * lx + dy * ly
            self.px[(x, y)] = dark if t < c1 else (mid if t < c2 else light)
    def shadow(self, cx, cy, rx, ry, c):
        for y in range(self.h):
            for x in range(self.w):
                if (x, y) in self.px: continue
                dx = (x + 0.5 - cx) / (rx + 0.5); dy = (y + 0.5 - cy) / (ry + 0.5)
                if dx*dx + dy*dy <= 1.0: self.set(x, y, c)
    def sparkle(self, x, y, size, c, core=None):
        """A four-point star. size 0 is a single pixel, 1 is a plus, 2 has arms."""
        self.set(x, y, core or c)
        if size >= 1:
            for d in (-1, 1):
                self.set(x + d, y, c); self.set(x, y + d, c)
        if size >= 2:
            for d in (-2, 2):
                self.set(x + d, y, c); self.set(x, y + d, c)
    def clear(self, x0, y0, x1, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.px.pop((x, y), None)
    def from_grid(self, grid, legend, ox=0, oy=0):
        for y, row in enumerate(grid):
            for x, ch in enumerate(row):
                n = legend.get(ch)
                if n: self.set(x + ox, y + oy, n)
        return self
    def translate(self, dx, dy):
        out = Canvas(self.w, self.h)
        for (x, y), v in self.px.items(): out.set(x + dx, y + dy, v)
        return out
    def merge(self, other, under=False):
        for (x, y), v in other.px.items():
            if under and (x, y) in self.px: continue
            self.set(x, y, v)
    def render(self, palette, scale=1):
        im = Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))
        p = im.load()
        for (x, y), v in self.px.items():
            col = palette.get(v)
            if col: p[x, y] = col
        if scale != 1: im = im.resize((self.w*scale, self.h*scale), Image.NEAREST)
        return im
