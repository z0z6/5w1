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
    """Sam mikroprocesor w gnieździe (bez kulki): metalowa pokrywa z grawerem "5", złote styki, zaczep."""
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = 0.5 * S

    # poświata neonowa pod gniazdem
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0)); hd = ImageDraw.Draw(halo)
    hd.rounded_rectangle((cx-0.36*S, cy-0.36*S, cx+0.36*S, cy+0.36*S), radius=0.06*S, fill=(0, 229, 255, 110))
    im = Image.alpha_composite(im, halo.filter(ImageFilter.GaussianBlur(0.045*S)))

    # cień
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sd = ImageDraw.Draw(sh)
    sd.rounded_rectangle((cx-0.33*S+0.012*S, cy-0.33*S+0.02*S, cx+0.33*S+0.012*S, cy+0.33*S+0.02*S), radius=0.04*S, fill=(0, 0, 0, 170))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(0.012*S)))

    d = ImageDraw.Draw(im)
    # gniazdo (socket): ciemna ramka z rzędami złotych otworów
    sw = 0.33*S
    d.rounded_rectangle((cx-sw, cy-sw, cx+sw, cy+sw), radius=0.04*S, fill=(16, 20, 28, 255), outline=(84, 98, 120, 255), width=int(0.008*S))
    pitch = 0.026*S
    n = int(2*sw/pitch)
    for i in range(n):
        for j in range(n):
            x = cx - sw + (i+0.5)*pitch*(2*sw/(n*pitch)); y = cy - sw + (j+0.5)*pitch*(2*sw/(n*pitch))
            # tylko pas między substratem a krawędzią gniazda
            dx, dy = abs(x-cx), abs(y-cy)
            m = max(dx, dy)
            if 0.255*S < m < 0.315*S:
                r = 0.0055*S
                d.ellipse((x-r, y-r, x+r, y+r), fill=(222, 178, 70, 255))
    # zaczep dociskowy (dźwignia) po prawej
    d.rounded_rectangle((cx+sw-0.004*S, cy-0.22*S, cx+sw+0.03*S, cy+0.22*S), radius=0.01*S, fill=(190, 196, 208, 255), outline=(110, 118, 132, 255), width=int(0.004*S))
    d.ellipse((cx+sw+0.006*S, cy-0.24*S, cx+sw+0.03*S, cy-0.2*S), fill=(150, 156, 170, 255))

    # substrat procesora (zielony) ze złotymi padami na brzegu
    pw = 0.25*S
    d.rounded_rectangle((cx-pw, cy-pw, cx+pw, cy+pw), radius=0.02*S, fill=(20, 90, 52, 255), outline=(8, 48, 28, 255), width=int(0.006*S))
    for k in range(14):
        t = -pw*0.86 + k*(pw*1.72/13)
        for (x0, y0, x1, y1) in (
            (cx+t-0.007*S, cy-pw+0.006*S, cx+t+0.007*S, cy-pw+0.022*S),
            (cx+t-0.007*S, cy+pw-0.022*S, cx+t+0.007*S, cy+pw-0.006*S),
            (cx-pw+0.006*S, cy+t-0.007*S, cx-pw+0.022*S, cy+t+0.007*S),
            (cx+pw-0.022*S, cy+t-0.007*S, cx+pw-0.006*S, cy+t+0.007*S)):
            d.rectangle((x0, y0, x1, y1), fill=(230, 188, 80, 255))
    # znacznik pinu 1 (trójkąt w rogu)
    d.polygon([(cx-pw+0.004*S, cy-pw+0.004*S), (cx-pw+0.05*S, cy-pw+0.004*S), (cx-pw+0.004*S, cy-pw+0.05*S)], fill=(236, 196, 90, 255))
    # drobne kondensatory SMD wokół pokrywy
    for (px, py) in ((-0.215, -0.1), (-0.215, 0.1), (0.215, -0.1), (0.215, 0.1), (-0.1, 0.215), (0.1, 0.215)):
        d.rectangle((cx+px*S-0.012*S, cy+py*S-0.008*S, cx+px*S+0.012*S, cy+py*S+0.008*S), fill=(196, 150, 80, 255))

    # metalowa pokrywa (IHS): gradient + fazowanie
    hw = 0.19*S
    x0, y0, x1, y1 = int(cx-hw), int(cy-hw), int(cx+hw), int(cy+hw)
    w_, h_ = x1-x0, y1-y0
    yy, xx = np.mgrid[0:h_, 0:w_].astype(np.float32)
    g = (xx/w_ + yy/h_)/2.0
    base = 0.86 - 0.34*g + 0.10*np.sin(g*9.0)
    arr = np.zeros((h_, w_, 4), np.float32)
    arr[..., 0] = np.clip(base*212, 0, 255); arr[..., 1] = np.clip(base*218, 0, 255); arr[..., 2] = np.clip(base*228, 0, 255); arr[..., 3] = 255
    lid = Image.fromarray(arr.astype(np.uint8), "RGBA")
    mask = Image.new("L", (w_, h_), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w_-1, h_-1), radius=int(0.025*S), fill=255)
    lid.putalpha(mask)
    im.alpha_composite(lid, (x0, y0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((x0, y0, x1, y1), radius=int(0.025*S), outline=(250, 252, 255, 255), width=int(0.006*S))
    d.rounded_rectangle((x0+0.01*S, y0+0.01*S, x1-0.01*S, y1-0.01*S), radius=int(0.02*S), outline=(120, 128, 142, 200), width=int(0.004*S))
    # grawer: pikselowa cyfra "5" + linie opisu
    glyph = ["11111", "10000", "11110", "00001", "00001", "10001", "01110"]
    px = 0.021*S; gx0 = cx - 2.5*px; gy0 = cy - 4.1*px
    for r_, row in enumerate(glyph):
        for c_, v in enumerate(row):
            if v == "1":
                d.rectangle((gx0+c_*px+0.002*S, gy0+r_*px+0.002*S, gx0+(c_+1)*px+0.002*S, gy0+(r_+1)*px+0.002*S), fill=(255, 255, 255, 210))
                d.rectangle((gx0+c_*px, gy0+r_*px, gx0+(c_+1)*px-1, gy0+(r_+1)*px-1), fill=(36, 48, 70, 255))
    for k, wl in enumerate((0.20, 0.13)):
        yy_ = cy + 0.115*S + k*0.026*S
        d.rectangle((cx-wl*S/2*1.0, yy_, cx+wl*S/2*1.0, yy_+0.011*S), fill=(60, 72, 94, 255))
    # odblask
    spec = Image.new("RGBA", (S, S), (0, 0, 0, 0)); spd = ImageDraw.Draw(spec)
    spd.polygon([(x0+0.02*S, y0+0.02*S), (x0+0.2*S, y0+0.02*S), (x0+0.02*S, y0+0.2*S)], fill=(255, 255, 255, 70))
    im = Image.alpha_composite(im, spec.filter(ImageFilter.GaussianBlur(0.004*S)))

    # iskierki (jak w grze)
    st = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sd2 = ImageDraw.Draw(st)
    star4(sd2, 0.80*S, 0.22*S, 0.034*S, (255, 212, 0, 255))
    star4(sd2, 0.19*S, 0.78*S, 0.03*S, (255, 43, 214, 255))
    star4(sd2, 0.22*S, 0.2*S, 0.022*S, (255, 255, 255, 255))
    star4(sd2, 0.8*S, 0.8*S, 0.026*S, (0, 229, 255, 255))
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
