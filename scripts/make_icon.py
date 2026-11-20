#!/usr/bin/env python3
"""
Génère l'icône MonVoyage (PNG 1024 x 1024 sans transparence) en trois variantes :
claire, sombre et teintée, ainsi que le symbole du widget (Glyph.png, avec transparence).

Aucune dépendance : Python 3 standard uniquement (rendu par champs de distance + anti-crénelage).
La géométrie est identique à design/icon.svg.

Usage :
    python3 scripts/make_icon.py
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "MonVoyage", "Resources", "Assets.xcassets", "AppIcon.appiconset")
GLYPH_DIR = os.path.join(ROOT, "MonVoyageWidget", "Assets.xcassets", "Glyph.imageset")

SIZE = 1024

# --- Géométrie (repère 1024, y vers le bas) ---------------------------------
BODY_C, BODY_HALF, BODY_R = (512.0, 580.0), (262.0, 205.0), 78.0
HANDLE_C, HANDLE_HALF, HANDLE_R, HANDLE_W = (512.0, 352.0), (112.0, 78.0), 46.0, 17.0
ARC_C, ARC_R, ARC_W = (512.0, 580.0), 118.0, 25.0
ARC_START, ARC_SWEEP = -90.0, 270.0          # degrés, sens horaire à l'écran
DOT_R = 24.0

PALETTES = {
    "light": {"bg1": (94, 200, 255), "bg2": (91, 91, 240), "glyph1": (255, 255, 255), "glyph2": (240, 244, 255)},
    "dark": {"bg1": (24, 30, 64), "bg2": (52, 30, 100), "glyph1": (150, 215, 255), "glyph2": (165, 150, 255)},
    "tinted": {"bg1": (0, 0, 0), "bg2": (0, 0, 0), "glyph1": (255, 255, 255), "glyph2": (200, 200, 200)},
}


def sd_round_box(px, py, c, half, r):
    qx = abs(px - c[0]) - half[0] + r
    qy = abs(py - c[1]) - half[1] + r
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - r


def sd_arc(px, py):
    x, y = px - ARC_C[0], py - ARC_C[1]
    ang = math.degrees(math.atan2(y, x))           # -180..180, horaire à l'écran
    rel = (ang - ARC_START) % 360.0
    if rel <= ARC_SWEEP:
        return abs(math.hypot(x, y) - ARC_R) - ARC_W
    a0 = math.radians(ARC_START)
    a1 = math.radians(ARC_START + ARC_SWEEP)
    d0 = math.hypot(x - ARC_R * math.cos(a0), y - ARC_R * math.sin(a0))
    d1 = math.hypot(x - ARC_R * math.cos(a1), y - ARC_R * math.sin(a1))
    return min(d0, d1) - ARC_W


def coverage(d):
    return max(0.0, min(1.0, 0.5 - d))


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def glyph_alpha(px, py):
    """Couverture du symbole (valise + poignée, moins l'arc et le point du compte à rebours)."""
    body = sd_round_box(px, py, BODY_C, BODY_HALF, BODY_R)
    handle = abs(sd_round_box(px, py, HANDLE_C, HANDLE_HALF, HANDLE_R)) - HANDLE_W
    shape = min(body, handle)
    cut = min(sd_arc(px, py), math.hypot(px - ARC_C[0], py - ARC_C[1]) - DOT_R)
    return coverage(shape) * (1.0 - coverage(cut) * coverage(body - 2))


def write_png(path, width, height, rows, alpha):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)
    color_type = 6 if alpha else 2

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def render_icon(variant):
    pal = PALETTES[variant]
    rows = []
    for y in range(SIZE):
        row = bytearray()
        py = y + 0.5
        for x in range(SIZE):
            px = x + 0.5
            t = (px + py) / (2 * SIZE)
            bg = mix(pal["bg1"], pal["bg2"], t)
            if variant != "tinted":
                # Reflet doux en haut à gauche (esprit Liquid Glass).
                glow = max(0.0, 1.0 - math.hypot(px - 260, py - 200) / 620.0) ** 2 * 0.22
                bg = mix(bg, (255, 255, 255), glow)
            a = glyph_alpha(px, py)
            g = mix(pal["glyph1"], pal["glyph2"], max(0.0, min(1.0, (py - 270) / 520.0)))
            c = mix(bg, g, a)
            row.extend(int(round(max(0, min(255, v)))) for v in c)
        rows.append(row)
    return rows


def render_glyph(size=256):
    scale = SIZE / size
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            # Sur-échantillonnage 2x2 pour un petit format net.
            acc = 0.0
            for sy in (0.25, 0.75):
                for sx in (0.25, 0.75):
                    acc += glyph_alpha((x + sx) * scale, (y + sy) * scale)
            a = acc / 4.0
            row.extend((255, 255, 255, int(round(a * 255))))
        rows.append(row)
    return rows


def main():
    outputs = {"light": "AppIcon.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"}
    for variant, name in outputs.items():
        path = os.path.join(ICON_DIR, name)
        print("Rendu", variant, "->", path)
        write_png(path, SIZE, SIZE, render_icon(variant), alpha=False)
    glyph = os.path.join(GLYPH_DIR, "Glyph.png")
    print("Rendu du symbole ->", glyph)
    write_png(glyph, 256, 256, render_glyph(), alpha=True)


if __name__ == "__main__":
    main()
