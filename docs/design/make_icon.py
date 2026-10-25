"""Pulso app icon: red gradient, faint ECG-paper grid, white pulse trace with a soft glow."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4096           # render size (downsampled to 1024 for smooth edges)
out = sys.argv[1]

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# Diagonal gradient: bright red top-left -> deep red bottom-right.
top, bottom = (255, 72, 86), (176, 14, 38)
grad = Image.new("RGB", (S, S))
px = grad.load()
small = Image.new("RGB", (256, 256))
sp = small.load()
for y in range(256):
    for x in range(256):
        t = min(1, max(0, (x * 0.45 + y * 0.85) / (256 * 1.3)))
        sp[x, y] = lerp(top, bottom, t)
grad = small.resize((S, S), Image.BICUBIC)

# Soft highlight in the upper area.
hl = Image.new("L", (S, S), 0)
ImageDraw.Draw(hl).ellipse((-S * 0.2, -S * 0.55, S * 1.2, S * 0.55), fill=70)
hl = hl.filter(ImageFilter.GaussianBlur(S * 0.08))
grad = Image.composite(Image.new("RGB", (S, S), (255, 140, 150)), grad, hl)

# Faint ECG-paper grid.
grid = Image.new("L", (S, S), 0)
g = ImageDraw.Draw(grid)
step = S / 16
for i in range(17):
    w = 10 if i % 4 == 0 else 4
    a = 38 if i % 4 == 0 else 20
    g.line([(i * step, 0), (i * step, S)], fill=a, width=w)
    g.line([(0, i * step), (S, i * step)], fill=a, width=w)
grad = Image.composite(Image.new("RGB", (S, S), (255, 210, 215)), grad, grid)

# Pulse trace (normalised 0..1 coordinates): flat, P, Q, tall R, S, T, flat.
pts = [(0.12, 0.56), (0.31, 0.56), (0.345, 0.505), (0.38, 0.56), (0.425, 0.56),
       (0.455, 0.64), (0.515, 0.20), (0.575, 0.78), (0.615, 0.56), (0.66, 0.56),
       (0.71, 0.475), (0.76, 0.56), (0.88, 0.56)]
P = [(x * S, y * S) for x, y in pts]
W = int(S * 0.05)

def stroke(width, fill, size=S):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.line(P, fill=fill, width=width, joint="curve")
    r = width / 2
    for x, y in (P[0], P[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)
    return m

glow = stroke(int(W * 2.0), 105).filter(ImageFilter.GaussianBlur(S * 0.025))
img = Image.composite(Image.new("RGB", (S, S), (255, 230, 232)), grad, glow)
# Thin darker shadow under the line for depth.
shadow = stroke(W, 110).filter(ImageFilter.GaussianBlur(S * 0.012))
shadow = ImageChops.offset(shadow, 0, int(S * 0.012))
img = Image.composite(Image.new("RGB", (S, S), (120, 0, 20)), img, shadow)
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, stroke(W, 255))

img.resize((1024, 1024), Image.LANCZOS).save(out, "PNG", optimize=True)
print("ok", out)
