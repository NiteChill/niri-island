#!/usr/bin/env python3
"""Draw assets/icons/wifi-off.svg, after Apple's wifi.slash: the Wi-Fi fan of wifi1-3.svg (the same
measures, fitted to the iPhone's glyph) cut by a gap along a diagonal slash, plus the slash.

    python3 tools/make-wifi-off.py            (writes assets/icons/wifi-off.svg)
"""
# Filled polygons of one winding (widgets/Icon fills nonzero: overlapping pieces just unite).
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'icons', 'wifi-off.svg')
APEX = 39.0; W = 13.5; BANDS = (40.0, 65.5); REACH = 46.0
WEDGE_R = 21.5; WEDGE_A = 45.0; WEDGE_C = 3.0
SLASH_W = 11.0; GAP = 5.5
# the slash: through the glyph's middle, 45 degrees down to the right
CX, CY = 0.0, 2.35; HALF = 50.0
STEPS = 48

def P(a, r, cx=0.0, cy=APEX):  # angle in degrees, clockwise from +x, y down
    t = math.radians(a); return (cx + r * math.cos(t), cy + r * math.sin(t))

def arc(cx, cy, r, a0, a1, n=STEPS):
    return [P(a0 + (a1 - a0) * i / n, r, cx, cy) for i in range(n + 1)]

def band(r):
    c = REACH - math.degrees(math.asin(W / 2 / r))
    a0, a1 = 270 - c, 270 + c
    ro, ri, h = r + W / 2, r - W / 2, W / 2
    pts = arc(0, APEX, ro, a0, a1)
    e = P(a1, r)                                  # the round end at a1, from outside to inside
    pts += arc(e[0], e[1], h, a1, a1 + 180, 16)[1:]
    pts += arc(0, APEX, ri, a1, a0)[1:]
    s = P(a0, r)                                  # the round end at a0, from inside to outside
    pts += arc(s[0], s[1], h, a0 + 180, a0 + 360, 16)[1:]
    return pts

def wedge():
    R, c, h = WEDGE_R, WEDGE_C, WEDGE_A
    l, rr = 270 - h, 270 + h
    dc = math.degrees(c / R)
    def quad(p0, p1, p2, n=8):
        return [((1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0], (1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]) for t in (i/n for i in range(1, n+1))]
    a0, a1 = P(l, c), P(rr, c)
    pts = [a0, P(l, R - c)]
    pts += quad(P(l, R - c), P(l, R), P(l + dc, R))
    pts += arc(0, APEX, R, l + dc, rr - dc)[1:]
    pts += quad(P(rr - dc, R), P(rr, R), P(rr, R - c))
    pts += [a1]
    pts += quad(a1, (0, APEX), a0)
    return pts

def area(pts):
    return sum(pts[i][0] * pts[(i+1) % len(pts)][1] - pts[(i+1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2

def clip(poly, nx, ny, d):
    """Sutherland-Hodgman against the half-plane nx*x + ny*y >= d."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        fa, fb = nx*a[0] + ny*a[1] - d, nx*b[0] + ny*b[1] - d
        if fa >= 0: out.append(a)
        if (fa >= 0) != (fb >= 0):
            t = fa / (fa - fb); out.append((a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t))
    return out

# the slash's direction and normal
ux, uy = math.cos(math.radians(45)), math.sin(math.radians(45))
nx, ny = -uy, ux
off = nx * CX + ny * CY
cut = SLASH_W / 2 + GAP
pieces = []
for shape in [wedge()] + [band(r) for r in BANDS]:
    if area(shape) < 0: shape = shape[::-1]
    for side in (1, -1):   # each side of the gap: n.p >= off + cut, and -n.p >= -(off - cut)
        p = clip(shape, side * nx, side * ny, side * off + cut)
        if len(p) >= 3: pieces.append(p)
# the slash: a round-capped bar
h = SLASH_W / 2
e0 = (CX - ux * HALF, CY - uy * HALF); e1 = (CX + ux * HALF, CY + uy * HALF)
ang = math.degrees(math.atan2(uy, ux))
slash = [(e0[0] + nx*h, e0[1] + ny*h), (e1[0] + nx*h, e1[1] + ny*h)]
slash += arc(e1[0], e1[1], h, ang + 90, ang - 90, 16)[1:]
slash += [(e0[0] - nx*h, e0[1] - ny*h)]
slash += arc(e0[0], e0[1], h, ang - 90, ang - 270, 16)[1:]
if area(slash) < 0: slash = slash[::-1]
pieces.append(slash)
F = lambda v: ('%.2f' % v).rstrip('0').rstrip('.')
d = ''.join('M' + ' L'.join(F(x) + ' ' + F(y) for x, y in p) + 'Z' for p in pieces)
# the same viewBox as wifi1-3.svg, so it sits exactly where they do
open(OUT, 'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51.22 -48.88 102.45 102.45"><path d="{d}"/></svg>\n')
print(len(pieces), 'pieces', len(d), 'chars')
