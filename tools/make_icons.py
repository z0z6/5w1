#!/usr/bin/env python3
"""Generator ikon aplikacji (narzędzie developerskie): icons/*.png
   Tło = płytka PCB, pierwszy plan = fluorescencyjna kulka + wyładowanie na układ scalony.
   Uruchomienie: python3 tools/make_icons.py   (wymaga Pillow, numpy)"""
import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling

def offset_poly(pts, off):
    """Równoległe przesunięcie łamanej (miter)."""
    n = len(pts); normals = []
    for i in range(n - 1):
        dx, dy = pts[i+1][0]-pts[i][0], pts[i+1][1]-pts[i][1]
        l = math.hypot(dx, dy) or 1; normals.append((-dy/l, dx/l))
    out = []
    for i in range(n):
        if i == 0: nx, ny = normals[0]; k = 1.0
        elif i == n-1: nx, ny = normals[-1]; k = 1.0
        else:
            a, b = normals[i-1], normals[i]
            nx, ny = a[0]+b[0], a[1]+b[1]
            dot = a[0]*b[0]+a[1]*b[1]; k = 1.0/(1.0+dot)
        out.append((pts[i][0]+nx*off*k, pts[i][1]+ny*off*k))
    return out

def background(size):
    S = size * SS
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    top = np.array([0x13, 0x6b, 0x3c], np.float32); bot = np.array([0x05, 0x26, 0x17], np.float32)
    img = (top[None,None,:]*(1-yy[...,None]) + bot[None,None,:]*yy[...,None])
    im = Image.fromarray(img.astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(im, "RGBA")
    bundles = [
        ([(-0.05,0.22),(0.20,0.22),(0.30,0.32),(0.30,0.62),(0.42,0.74),(1.05,0.74)], 5, 0.030),
        ([(-0.05,0.86),(0.30,0.86),(0.40,0.96),(1.05,0.96)], 4, 0.028),
        ([(0.62,-0.05),(0.62,0.12),(0.72,0.22),(1.05,0.22)], 3, 0.030),
        ([(0.10,-0.05),(0.10,0.08),(0.18,0.16),(0.18,0.40)], 3, 0.028),
        ([(0.85,1.05),(0.85,0.90),(0.95,0.80),(1.05,0.80)], 3, 0.028),
    ]
    for pts, k, sp in bundles:
        for j in range(k):
            off = (j-(k-1)/2)*sp
            P = [(x*S, y*S) for x, y in offset_poly(pts, off)]
            d.line(P, fill=(60, 190, 120, 200), width=int(0.011*S), joint="curve")
            d.line(P, fill=(120, 235, 170, 90), width=int(0.004*S), joint="curve")
            for q in (P[0], P[-1]):
                pass
        # pady na końcach wiązki widocznych w kadrze
        for end in (pts[0], pts[-1]):
            if -0.01 < end[0] < 1.01 and -0.01 < end[1] < 1.01:
                for j in range(k):
                    off = (j-(k-1)/2)*sp
                    ex, ey = offset_poly(pts, off)[0 if end is pts[0] else -1]
                    r = 0.018*S
                    d.ellipse((ex*S-r, ey*S-r, ex*S+r, ey*S+r), fill=(217, 138, 74, 255))
                    r2 = r*0.4
                    d.ellipse((ex*S-r2, ey*S-r2, ex*S+r2, ey*S+r2), fill=(8, 20, 14, 255))
    # winieta
    r = np.sqrt((xx-0.5)**2 + (yy-0.5)**2)
    vig = np.clip((r-0.35)/0.55, 0, 1)**1.5 * 0.55
    arr = np.array(im).astype(np.float32)
    arr[..., :3] *= (1-vig[..., None])
    return Image.fromarray(arr.astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)

def glow(layer, radius, strength=1.0):
    g = layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        a = np.array(g).astype(np.float32); a[..., 3] = np.clip(a[..., 3]*strength, 0, 255)
        g = Image.fromarray(a.astype(np.uint8), "RGBA")
    return g

def star4(d, cx, cy, r, color):
    pts = []
    for i in range(8):
        a = i*math.pi/4; rr = r if i % 2 == 0 else r*0.28
        pts.append((cx+math.cos(a)*rr, cy+math.sin(a)*rr))
    d.polygon(pts, fill=color)

def foreground(size, seed=7):
    S = size * SS
    rnd = random.Random(seed)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # --- układ scalony
    cx, cy, h = 0.68*S, 0.28*S, 0.12*S
    chip = Image.new("RGBA", (S, S), (0, 0, 0, 0)); cd = ImageDraw.Draw(chip)
    # nóżki
    for i in range(6):
        t = cy - h*0.78 + i*(h*1.56/5)
        for side in (-1, 1):
            x0 = cx + side*h
            cd.rectangle((x0 - (0.0 if side > 0 else 0.035*S), t-0.011*S, x0 + (0.035*S if side > 0 else 0.0), t+0.011*S), fill=(196, 202, 212, 255))
    for i in range(6):
        t = cx - h*0.78 + i*(h*1.56/5)
        for side in (-1, 1):
            y0 = cy + side*h
            cd.rectangle((t-0.011*S, y0 - (0.0 if side > 0 else 0.035*S), t+0.011*S, y0 + (0.035*S if side > 0 else 0.0)), fill=(196, 202, 212, 255))
    cd.rounded_rectangle((cx-h, cy-h, cx+h, cy+h), radius=0.02*S, fill=(16, 20, 28, 255), outline=(70, 84, 104, 255), width=int(0.006*S))
    # cyfra "5" jako pixel-art
    glyph = ["11111", "10000", "11110", "00001", "00001", "10001", "01110"]
    px = 0.016*S; gx0 = cx - 2.5*px; gy0 = cy - 3.5*px
    for r_, row in enumerate(glyph):
        for c_, v in enumerate(row):
            if v == "1":
                cd.rectangle((gx0+c_*px, gy0+r_*px, gx0+(c_+1)*px-1, gy0+(r_+1)*px-1), fill=(0, 229, 255, 255))
    cd.ellipse((cx-h+0.018*S, cy-h+0.018*S, cx-h+0.034*S, cy-h+0.034*S), fill=(230, 235, 245, 255))
    # cień + układ
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((cx-h+0.012*S, cy-h+0.02*S, cx+h+0.012*S, cy+h+0.02*S), radius=0.02*S, fill=(0, 0, 0, 160))
    im = Image.alpha_composite(im, shadow.filter(ImageFilter.GaussianBlur(0.012*S)))
    im = Image.alpha_composite(im, chip)
    # poświata cyfry
    gl = Image.new("RGBA", (S, S), (0, 0, 0, 0)); gd = ImageDraw.Draw(gl)
    for r_, row in enumerate(glyph):
        for c_, v in enumerate(row):
            if v == "1":
                gd.rectangle((gx0+c_*px, gy0+r_*px, gx0+(c_+1)*px, gy0+(r_+1)*px), fill=(0, 229, 255, 255))
    im = Image.alpha_composite(im, glow(gl, 0.012*S, 1.0))

    # --- kulka
    mx, my, mr = 0.35*S, 0.65*S, 0.19*S
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0)); hd = ImageDraw.Draw(halo)
    hd.ellipse((mx-mr*1.25, my-mr*1.25, mx+mr*1.25, my+mr*1.25), fill=(0, 220, 255, 150))
    im = Image.alpha_composite(im, glow(halo, 0.05*S))
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    dx, dy = (xx-mx)/mr, (yy-my)/mr
    rr = np.sqrt(dx*dx + dy*dy)
    inside = rr <= 1.0
    z = np.sqrt(np.clip(1 - rr*rr, 0, 1))
    # światło z lewego-górnego rogu
    lx, ly, lz = -0.45, -0.55, 0.70
    ln = math.sqrt(lx*lx+ly*ly+lz*lz); lx, ly, lz = lx/ln, ly/ln, lz/ln
    diff = np.clip(dx*lx + dy*ly + z*lz, 0, 1)
    spec = np.clip(diff, 0, 1)**28
    rim = (1 - z)**2.2
    base = np.array([0.0, 0.80, 1.0], np.float32); deep = np.array([0.0, 0.25, 0.45], np.float32)
    col = deep[None,None,:]*(1-diff[...,None]) + base[None,None,:]*diff[...,None]
    col = col + np.array([0.0, 0.55, 0.65], np.float32)[None,None,:]*rim[...,None]*0.9   # fluorescencyjny rąbek
    col = col + spec[...,None]*1.2
    # iskierki ładunku na powierzchni
    for _ in range(26):
        a = rnd.random()*math.tau; rad = rnd.random()**0.5*0.88
        sx, sy = mx + math.cos(a)*rad*mr, my + math.sin(a)*rad*mr
        r0 = rnd.uniform(0.006, 0.014)*S
        m = ((xx-sx)**2 + (yy-sy)**2) <= r0*r0
        c = rnd.choice([(0.9,1.0,1.0),(1.0,0.5,0.95),(1.0,1.0,0.8)])
        for k in range(3): col[..., k][m] = c[k]
    rgba = np.zeros((S, S, 4), np.float32)
    rgba[..., :3] = np.clip(col, 0, 1)*255
    rgba[..., 3] = inside*255
    ball = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    # antyaliasing krawędzi
    mask = ball.split()[3].filter(ImageFilter.GaussianBlur(SS*0.6)); ball.putalpha(mask)
    im = Image.alpha_composite(im, ball)

    # --- wyładowanie elektryczne
    ax, ay = mx + 0.707*mr, my - 0.707*mr
    bx, by = 0.585*S, 0.39*S
    pts = [(ax, ay)]
    n = 7
    for i in range(1, n):
        t = i/n
        px_, py_ = ax+(bx-ax)*t, ay+(by-ay)*t
        j = 0.028*S
        pts.append((px_+rnd.uniform(-j, j), py_+rnd.uniform(-j, j)))
    pts.append((bx, by))
    arc = Image.new("RGBA", (S, S), (0, 0, 0, 0)); ad = ImageDraw.Draw(arc)
    ad.line(pts, fill=(120, 230, 255, 255), width=int(0.026*S), joint="curve")
    im = Image.alpha_composite(im, glow(arc, 0.014*S, 2.0))
    core = Image.new("RGBA", (S, S), (0, 0, 0, 0)); cdd = ImageDraw.Draw(core)
    cdd.line(pts, fill=(255, 255, 255, 255), width=int(0.011*S), joint="curve")
    im = Image.alpha_composite(im, core)
    # drugie, krótsze odgałęzienie
    ax2, ay2 = mx + 0.97*mr, my - 0.2*mr
    pts2 = [(ax2, ay2), (ax2+0.04*S, ay2-0.02*S), (ax2+0.07*S, ay2+0.015*S), (ax2+0.11*S, ay2-0.01*S)]
    br = Image.new("RGBA", (S, S), (0, 0, 0, 0)); brd = ImageDraw.Draw(br)
    brd.line(pts2, fill=(255, 120, 240, 255), width=int(0.009*S), joint="curve")
    im = Image.alpha_composite(im, glow(br, 0.006*S, 2.0))
    im = Image.alpha_composite(im, br)

    # --- gwiazdki retro
    st = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sd2 = ImageDraw.Draw(st)
    star4(sd2, 0.60*S, 0.60*S, 0.035*S, (255, 212, 0, 255))
    star4(sd2, 0.21*S, 0.42*S, 0.03*S, (255, 43, 214, 255))
    star4(sd2, 0.54*S, 0.78*S, 0.024*S, (255, 255, 255, 255))
    star4(sd2, 0.80*S, 0.58*S, 0.026*S, (0, 229, 255, 255))
    im = Image.alpha_composite(im, glow(st, 0.008*S, 1.5))
    im = Image.alpha_composite(im, st)
    return im.resize((size, size), Image.LANCZOS)

def rounded(im, frac=0.2):
    s = im.size[0]
    m = Image.new("L", (s*4, s*4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, s*4-1, s*4-1), radius=int(s*4*frac), fill=255)
    m = m.resize((s, s), Image.LANCZOS)
    out = im.copy(); out.putalpha(m); return out

if __name__ == "__main__":
    import os
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")
    os.makedirs(here, exist_ok=True)
    bg432, fg432 = background(432), foreground(432)
    bg432.save(os.path.join(here, "icon_bg_432.png"))
    # warstwa adaptacyjna: zawartość w bezpiecznej strefie (okrągła maska ~ promień 0.30)
    k = 0.64
    small = fg432.resize((int(432*k), int(432*k)), Image.LANCZOS)
    safe = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    safe.alpha_composite(small, ((432-small.width)//2, (432-small.height)//2))
    safe.save(os.path.join(here, "icon_fg_432.png"))
    full = lambda n: Image.alpha_composite(background(n), foreground(n))
    rounded(full(192)).save(os.path.join(here, "icon_192.png"))
    rounded(full(512)).save(os.path.join(here, "icon.png"))
    # ekran startowy: ikona na ciemnym tle
    sp = Image.new("RGBA", (512, 512), (10, 4, 32, 255))
    ic = rounded(full(320)); sp.alpha_composite(ic, (96, 96))
    sp.save(os.path.join(here, "splash.png"))
    print("ikony wygenerowane")
