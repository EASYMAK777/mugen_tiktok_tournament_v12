"""
Creates flags.sff - an SFF v2 sprite file with country flag images.
Each flag is stored as group=0, index=N where N is the country index.
Run once to generate the file, then the Lua mod loads it at runtime.

Usage:
    python create_flags_sff.py
"""

import struct
import io
from PIL import Image, ImageDraw

# ============================================================
# Country definitions: (code, name, flag drawing function)
# ============================================================
FLAG_W = 48
FLAG_H = 32


def _tri_h(draw, c1, c2, c3):
    """Horizontal tricolor."""
    h = FLAG_H // 3
    draw.rectangle([0, 0, FLAG_W, h], fill=c1)
    draw.rectangle([0, h, FLAG_W, h * 2], fill=c2)
    draw.rectangle([0, h * 2, FLAG_W, FLAG_H], fill=c3)


def _tri_v(draw, c1, c2, c3):
    """Vertical tricolor."""
    w = FLAG_W // 3
    draw.rectangle([0, 0, w, FLAG_H], fill=c1)
    draw.rectangle([w, 0, w * 2, FLAG_H], fill=c2)
    draw.rectangle([w * 2, 0, FLAG_W, FLAG_H], fill=c3)


def _bi_h(draw, c1, c2):
    """Horizontal bicolor."""
    h = FLAG_H // 2
    draw.rectangle([0, 0, FLAG_W, h], fill=c1)
    draw.rectangle([0, h, FLAG_W, FLAG_H], fill=c2)


def flag_usa(img, draw):
    # Stripes
    sh = FLAG_H / 13
    for i in range(13):
        c = (178, 34, 52) if i % 2 == 0 else (255, 255, 255)
        draw.rectangle([0, int(i * sh), FLAG_W, int((i + 1) * sh)], fill=c)
    # Blue canton
    bw = int(FLAG_W * 0.4)
    bh = int(7 * sh)
    draw.rectangle([0, 0, bw, bh], fill=(60, 59, 110))
    # Stars (simplified dots)
    for row in range(3):
        for col in range(3):
            x = 4 + col * int(bw / 3.5)
            y = 2 + row * int(bh / 3.5)
            draw.rectangle([x, y, x + 2, y + 2], fill=(255, 255, 255))


def flag_uk(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(0, 36, 125))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    # White diagonals
    draw.line([(0, 0), (FLAG_W, FLAG_H)], fill=(255, 255, 255), width=4)
    draw.line([(FLAG_W, 0), (0, FLAG_H)], fill=(255, 255, 255), width=4)
    # Red diagonals
    draw.line([(0, 0), (FLAG_W, FLAG_H)], fill=(207, 20, 43), width=2)
    draw.line([(FLAG_W, 0), (0, FLAG_H)], fill=(207, 20, 43), width=2)
    # White cross
    draw.rectangle([cx - 4, 0, cx + 4, FLAG_H], fill=(255, 255, 255))
    draw.rectangle([0, cy - 3, FLAG_W, cy + 3], fill=(255, 255, 255))
    # Red cross
    draw.rectangle([cx - 2, 0, cx + 2, FLAG_H], fill=(207, 20, 43))
    draw.rectangle([0, cy - 2, FLAG_W, cy + 2], fill=(207, 20, 43))


def flag_canada(img, draw):
    w3 = FLAG_W // 4
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(255, 255, 255))
    draw.rectangle([0, 0, w3, FLAG_H], fill=(255, 0, 0))
    draw.rectangle([FLAG_W - w3, 0, FLAG_W, FLAG_H], fill=(255, 0, 0))
    # Maple leaf (simplified diamond)
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.polygon([(cx, cy - 8), (cx + 6, cy + 4), (cx, cy + 8), (cx - 6, cy + 4)],
                 fill=(255, 0, 0))


def flag_japan(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(255, 255, 255))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    r = min(FLAG_W, FLAG_H) // 4
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(188, 0, 45))


def flag_brazil(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(0, 155, 58))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    # Yellow diamond
    draw.polygon([(cx, 2), (FLAG_W - 4, cy), (cx, FLAG_H - 2), (4, cy)],
                 fill=(255, 223, 0))
    # Blue circle
    r = min(FLAG_W, FLAG_H) // 5
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0, 39, 118))


def flag_mexico(img, draw):
    _tri_v(draw, (0, 104, 71), (255, 255, 255), (206, 17, 38))
    # Small emblem dot
    cx = FLAG_W // 2
    cy = FLAG_H // 2
    draw.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=(0, 104, 71))


def flag_france(img, draw):
    _tri_v(draw, (0, 35, 149), (255, 255, 255), (237, 41, 57))


def flag_germany(img, draw):
    _tri_h(draw, (0, 0, 0), (221, 0, 0), (255, 206, 0))


def flag_italy(img, draw):
    _tri_v(draw, (0, 146, 70), (255, 255, 255), (206, 43, 55))


def flag_spain(img, draw):
    h4 = FLAG_H // 4
    draw.rectangle([0, 0, FLAG_W, h4], fill=(198, 11, 30))
    draw.rectangle([0, h4, FLAG_W, FLAG_H - h4], fill=(255, 196, 0))
    draw.rectangle([0, FLAG_H - h4, FLAG_W, FLAG_H], fill=(198, 11, 30))


def flag_argentina(img, draw):
    _tri_h(draw, (108, 172, 228), (255, 255, 255), (108, 172, 228))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(245, 195, 15))


def flag_colombia(img, draw):
    h2 = FLAG_H // 2
    h4 = FLAG_H * 3 // 4
    draw.rectangle([0, 0, FLAG_W, h2], fill=(252, 209, 22))
    draw.rectangle([0, h2, FLAG_W, h4], fill=(0, 56, 147))
    draw.rectangle([0, h4, FLAG_W, FLAG_H], fill=(206, 17, 38))


def flag_south_korea(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(255, 255, 255))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    r = min(FLAG_W, FLAG_H) // 4
    # Red/blue circle (simplified)
    draw.pieslice([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=(205, 46, 58))
    draw.pieslice([cx - r, cy - r, cx + r, cy + r], 0, 180, fill=(0, 71, 160))


def flag_china(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(222, 41, 16))
    # Stars (simplified)
    draw.polygon([(8, 4), (10, 10), (4, 7), (12, 7), (6, 10)], fill=(255, 222, 0))
    for pos in [(16, 2), (18, 6), (18, 10), (16, 14)]:
        draw.rectangle([pos[0], pos[1], pos[0] + 2, pos[1] + 2], fill=(255, 222, 0))


def flag_india(img, draw):
    _tri_h(draw, (255, 153, 51), (255, 255, 255), (19, 136, 8))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], outline=(0, 0, 128), width=1)


def flag_russia(img, draw):
    _tri_h(draw, (255, 255, 255), (0, 57, 166), (213, 43, 30))


def flag_australia(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(0, 0, 139))
    # Union jack simplified in corner
    bw, bh = FLAG_W // 2, FLAG_H // 2
    draw.line([(0, 0), (bw, bh)], fill=(255, 255, 255), width=2)
    draw.line([(bw, 0), (0, bh)], fill=(255, 255, 255), width=2)
    draw.rectangle([bw // 2 - 1, 0, bw // 2 + 1, bh], fill=(255, 255, 255))
    draw.rectangle([0, bh // 2 - 1, bw, bh // 2 + 1], fill=(255, 255, 255))
    draw.rectangle([bw // 2, 0, bw // 2, bh], fill=(207, 20, 43))
    draw.rectangle([0, bh // 2, bw, bh // 2], fill=(207, 20, 43))
    # Southern cross (dots)
    for pos in [(35, 22), (38, 12), (32, 8), (28, 16), (34, 17)]:
        draw.rectangle([pos[0], pos[1], pos[0] + 2, pos[1] + 2], fill=(255, 255, 255))


def flag_turkey(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(227, 10, 23))
    cx, cy = FLAG_W // 2 - 2, FLAG_H // 2
    r = 7
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255))
    draw.ellipse([cx - r + 3, cy - r + 1, cx + r - 1, cy + r - 1], fill=(227, 10, 23))
    # Star
    sx = cx + 6
    draw.polygon([(sx, cy - 3), (sx + 1, cy - 1), (sx + 3, cy), (sx + 1, cy + 1),
                  (sx, cy + 3), (sx - 1, cy + 1), (sx - 3, cy), (sx - 1, cy - 1)],
                 fill=(255, 255, 255))


def flag_poland(img, draw):
    _bi_h(draw, (255, 255, 255), (220, 20, 60))


def flag_netherlands(img, draw):
    _tri_h(draw, (174, 28, 40), (255, 255, 255), (33, 70, 139))


def flag_sweden(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(0, 106, 167))
    # Yellow cross
    draw.rectangle([14, 0, 20, FLAG_H], fill=(254, 204, 2))
    draw.rectangle([0, FLAG_H // 2 - 3, FLAG_W, FLAG_H // 2 + 3], fill=(254, 204, 2))


def flag_norway(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(186, 12, 47))
    # White cross
    draw.rectangle([13, 0, 21, FLAG_H], fill=(255, 255, 255))
    draw.rectangle([0, FLAG_H // 2 - 4, FLAG_W, FLAG_H // 2 + 4], fill=(255, 255, 255))
    # Blue cross
    draw.rectangle([15, 0, 19, FLAG_H], fill=(0, 32, 91))
    draw.rectangle([0, FLAG_H // 2 - 2, FLAG_W, FLAG_H // 2 + 2], fill=(0, 32, 91))


def flag_portugal(img, draw):
    w_split = int(FLAG_W * 0.4)
    draw.rectangle([0, 0, w_split, FLAG_H], fill=(0, 102, 0))
    draw.rectangle([w_split, 0, FLAG_W, FLAG_H], fill=(255, 0, 0))
    # Emblem circle
    draw.ellipse([w_split - 5, FLAG_H // 2 - 5, w_split + 5, FLAG_H // 2 + 5],
                 fill=(255, 255, 0))


def flag_peru(img, draw):
    _tri_v(draw, (206, 17, 38), (255, 255, 255), (206, 17, 38))


def flag_chile(img, draw):
    h2 = FLAG_H // 2
    draw.rectangle([0, 0, FLAG_W, h2], fill=(255, 255, 255))
    draw.rectangle([0, h2, FLAG_W, FLAG_H], fill=(213, 43, 30))
    # Blue canton
    bw = FLAG_W // 3
    draw.rectangle([0, 0, bw, h2], fill=(0, 57, 166))
    # White star
    cx, cy = bw // 2, h2 // 2
    draw.polygon([(cx, cy - 4), (cx + 2, cy), (cx, cy + 4), (cx - 2, cy)],
                 fill=(255, 255, 255))


def flag_venezuela(img, draw):
    _tri_h(draw, (252, 209, 22), (0, 56, 147), (206, 17, 38))
    # Stars
    cx = FLAG_W // 2
    for dx in [-8, -4, 0, 4, 8]:
        draw.rectangle([cx + dx, FLAG_H // 2 - 1, cx + dx + 1, FLAG_H // 2 + 1],
                       fill=(255, 255, 255))


def flag_ecuador(img, draw):
    h2 = FLAG_H // 2
    h4 = FLAG_H * 3 // 4
    draw.rectangle([0, 0, FLAG_W, h2], fill=(255, 223, 0))
    draw.rectangle([0, h2, FLAG_W, h4], fill=(0, 79, 163))
    draw.rectangle([0, h4, FLAG_W, FLAG_H], fill=(206, 17, 38))


def flag_nigeria(img, draw):
    _tri_v(draw, (0, 135, 68), (255, 255, 255), (0, 135, 68))


def flag_egypt(img, draw):
    _tri_h(draw, (206, 17, 38), (255, 255, 255), (0, 0, 0))
    # Eagle emblem (simplified)
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(197, 163, 25))


def flag_south_africa(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(255, 255, 255))
    h3 = FLAG_H // 3
    draw.rectangle([0, 0, FLAG_W, h3 - 1], fill=(222, 56, 49))
    draw.rectangle([0, FLAG_H - h3 + 1, FLAG_W, FLAG_H], fill=(0, 119, 73))
    # Green Y
    draw.polygon([(0, 0), (FLAG_W // 3, FLAG_H // 2), (0, FLAG_H)], fill=(0, 119, 73))
    # Gold borders
    draw.line([(0, h3), (FLAG_W, h3)], fill=(255, 184, 28), width=2)
    draw.line([(0, FLAG_H - h3), (FLAG_W, FLAG_H - h3)], fill=(255, 184, 28), width=2)


def flag_philippines(img, draw):
    h2 = FLAG_H // 2
    draw.rectangle([0, 0, FLAG_W, h2], fill=(0, 56, 168))
    draw.rectangle([0, h2, FLAG_W, FLAG_H], fill=(206, 17, 38))
    # White triangle
    draw.polygon([(0, 0), (FLAG_W // 3, FLAG_H // 2), (0, FLAG_H)], fill=(255, 255, 255))
    # Sun
    draw.ellipse([4, FLAG_H // 2 - 3, 10, FLAG_H // 2 + 3], fill=(252, 209, 22))


def flag_thailand(img, draw):
    sh = FLAG_H / 5
    draw.rectangle([0, 0, FLAG_W, int(sh)], fill=(237, 28, 36))
    draw.rectangle([0, int(sh), FLAG_W, int(sh * 2)], fill=(255, 255, 255))
    draw.rectangle([0, int(sh * 2), FLAG_W, int(sh * 3)], fill=(44, 44, 120))
    draw.rectangle([0, int(sh * 3), FLAG_W, int(sh * 4)], fill=(255, 255, 255))
    draw.rectangle([0, int(sh * 4), FLAG_W, FLAG_H], fill=(237, 28, 36))


def flag_jamaica(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(0, 150, 57))
    # Gold X
    draw.line([(0, 0), (FLAG_W, FLAG_H)], fill=(255, 204, 0), width=4)
    draw.line([(FLAG_W, 0), (0, FLAG_H)], fill=(255, 204, 0), width=4)
    # Black triangles
    draw.polygon([(0, 0), (FLAG_W // 2 - 3, FLAG_H // 2), (0, FLAG_H)], fill=(0, 0, 0))
    draw.polygon([(FLAG_W, 0), (FLAG_W // 2 + 3, FLAG_H // 2), (FLAG_W, FLAG_H)], fill=(0, 0, 0))


def flag_puerto_rico(img, draw):
    sh = FLAG_H / 5
    for i in range(5):
        c = (206, 17, 38) if i % 2 == 0 else (255, 255, 255)
        draw.rectangle([0, int(i * sh), FLAG_W, int((i + 1) * sh)], fill=c)
    # Blue triangle
    draw.polygon([(0, 0), (FLAG_W // 3 + 4, FLAG_H // 2), (0, FLAG_H)], fill=(60, 59, 110))
    # White star
    cx, cy = FLAG_W // 8, FLAG_H // 2
    draw.polygon([(cx, cy - 4), (cx + 2, cy), (cx, cy + 4), (cx - 2, cy)],
                 fill=(255, 255, 255))


def flag_cuba(img, draw):
    sh = FLAG_H / 5
    for i in range(5):
        c = (0, 42, 117) if i % 2 == 0 else (255, 255, 255)
        draw.rectangle([0, int(i * sh), FLAG_W, int((i + 1) * sh)], fill=c)
    # Red triangle
    draw.polygon([(0, 0), (FLAG_W // 3 + 2, FLAG_H // 2), (0, FLAG_H)], fill=(206, 17, 38))
    # White star
    cx, cy = FLAG_W // 8, FLAG_H // 2
    draw.polygon([(cx, cy - 4), (cx + 2, cy), (cx, cy + 4), (cx - 2, cy)],
                 fill=(255, 255, 255))


def flag_dominican_republic(img, draw):
    # Quartered: blue top-left, red top-right, red bottom-left, blue bottom-right
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.rectangle([0, 0, cx, cy], fill=(0, 45, 98))
    draw.rectangle([cx, 0, FLAG_W, cy], fill=(206, 17, 38))
    draw.rectangle([0, cy, cx, FLAG_H], fill=(206, 17, 38))
    draw.rectangle([cx, cy, FLAG_W, FLAG_H], fill=(0, 45, 98))
    # White cross
    draw.rectangle([cx - 2, 0, cx + 2, FLAG_H], fill=(255, 255, 255))
    draw.rectangle([0, cy - 2, FLAG_W, cy + 2], fill=(255, 255, 255))


def flag_haiti(img, draw):
    _bi_h(draw, (0, 38, 100), (210, 16, 52))
    # Small emblem
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.rectangle([cx - 4, cy - 3, cx + 4, cy + 3], fill=(255, 255, 255))


def flag_ireland(img, draw):
    _tri_v(draw, (22, 155, 98), (255, 255, 255), (255, 136, 62))


def flag_belgium(img, draw):
    _tri_v(draw, (0, 0, 0), (255, 224, 0), (239, 51, 64))


def flag_switzerland(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(255, 0, 0))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.rectangle([cx - 2, cy - 7, cx + 2, cy + 7], fill=(255, 255, 255))
    draw.rectangle([cx - 7, cy - 2, cx + 7, cy + 2], fill=(255, 255, 255))


def flag_greece(img, draw):
    sh = FLAG_H / 9
    for i in range(9):
        c = (13, 94, 175) if i % 2 == 0 else (255, 255, 255)
        draw.rectangle([0, int(i * sh), FLAG_W, int((i + 1) * sh)], fill=c)
    # Blue canton with cross
    bw = int(FLAG_W * 0.37)
    bh = int(5 * sh)
    draw.rectangle([0, 0, bw, bh], fill=(13, 94, 175))
    draw.rectangle([bw // 2 - 1, 0, bw // 2 + 1, bh], fill=(255, 255, 255))
    draw.rectangle([0, bh // 2 - 1, bw, bh // 2 + 1], fill=(255, 255, 255))


def flag_ukraine(img, draw):
    _bi_h(draw, (0, 87, 183), (255, 215, 0))


def flag_israel(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(255, 255, 255))
    sh = FLAG_H // 6
    draw.rectangle([0, sh, FLAG_W, sh + 2], fill=(0, 56, 184))
    draw.rectangle([0, FLAG_H - sh - 2, FLAG_W, FLAG_H - sh], fill=(0, 56, 184))
    # Star of David (simplified)
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.polygon([(cx, cy - 5), (cx + 5, cy + 3), (cx - 5, cy + 3)], outline=(0, 56, 184))
    draw.polygon([(cx, cy + 5), (cx + 5, cy - 3), (cx - 5, cy - 3)], outline=(0, 56, 184))


def flag_saudi_arabia(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(0, 110, 57))
    draw.rectangle([8, FLAG_H // 2 - 2, FLAG_W - 8, FLAG_H // 2 + 2], fill=(255, 255, 255))
    # Sword simplified
    draw.line([(FLAG_W // 2 - 8, FLAG_H // 2 + 5), (FLAG_W // 2 + 8, FLAG_H // 2 + 5)],
              fill=(255, 255, 255), width=1)


def flag_morocco(img, draw):
    draw.rectangle([0, 0, FLAG_W, FLAG_H], fill=(193, 39, 45))
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.polygon([(cx, cy - 6), (cx + 2, cy - 2), (cx + 6, cy - 2), (cx + 3, cy + 1),
                  (cx + 4, cy + 6), (cx, cy + 3), (cx - 4, cy + 6), (cx - 3, cy + 1),
                  (cx - 6, cy - 2), (cx - 2, cy - 2)], outline=(0, 100, 0), width=1)


def flag_panama(img, draw):
    cx, cy = FLAG_W // 2, FLAG_H // 2
    draw.rectangle([0, 0, cx, cy], fill=(255, 255, 255))
    draw.rectangle([cx, 0, FLAG_W, cy], fill=(218, 41, 28))
    draw.rectangle([0, cy, cx, FLAG_H], fill=(0, 79, 159))
    draw.rectangle([cx, cy, FLAG_W, FLAG_H], fill=(255, 255, 255))
    # Stars
    draw.polygon([(cx // 2, cy // 2 - 3), (cx // 2 + 2, cy // 2 + 2),
                  (cx // 2 - 2, cy // 2 + 2)], fill=(0, 79, 159))
    draw.polygon([(cx + cx // 2, cy + cy // 2 - 3), (cx + cx // 2 + 2, cy + cy // 2 + 2),
                  (cx + cx // 2 - 2, cy + cy // 2 + 2)], fill=(218, 41, 28))


def flag_costa_rica(img, draw):
    sh = FLAG_H / 5
    draw.rectangle([0, 0, FLAG_W, int(sh)], fill=(0, 56, 168))
    draw.rectangle([0, int(sh), FLAG_W, int(sh * 2)], fill=(255, 255, 255))
    draw.rectangle([0, int(sh * 2), FLAG_W, int(sh * 3)], fill=(218, 41, 28))
    draw.rectangle([0, int(sh * 3), FLAG_W, int(sh * 4)], fill=(255, 255, 255))
    draw.rectangle([0, int(sh * 4), FLAG_W, FLAG_H], fill=(0, 56, 168))


def flag_honduras(img, draw):
    _tri_h(draw, (0, 101, 189), (255, 255, 255), (0, 101, 189))
    cx = FLAG_W // 2
    cy = FLAG_H // 2
    for dx in [-6, -3, 0, 3, 6]:
        draw.rectangle([cx + dx - 1, cy - 1, cx + dx + 1, cy + 1], fill=(0, 101, 189))


# ============================================================
# Country registry
# ============================================================
COUNTRIES = [
    ("USA", "United States", flag_usa),
    ("GBR", "United Kingdom", flag_uk),
    ("CAN", "Canada", flag_canada),
    ("MEX", "Mexico", flag_mexico),
    ("BRA", "Brazil", flag_brazil),
    ("ARG", "Argentina", flag_argentina),
    ("COL", "Colombia", flag_colombia),
    ("VEN", "Venezuela", flag_venezuela),
    ("PER", "Peru", flag_peru),
    ("CHL", "Chile", flag_chile),
    ("ECU", "Ecuador", flag_ecuador),
    ("PRI", "Puerto Rico", flag_puerto_rico),
    ("CUB", "Cuba", flag_cuba),
    ("DOM", "Dominican Rep.", flag_dominican_republic),
    ("HTI", "Haiti", flag_haiti),
    ("JAM", "Jamaica", flag_jamaica),
    ("PAN", "Panama", flag_panama),
    ("CRI", "Costa Rica", flag_costa_rica),
    ("HND", "Honduras", flag_honduras),
    ("FRA", "France", flag_france),
    ("DEU", "Germany", flag_germany),
    ("ITA", "Italy", flag_italy),
    ("ESP", "Spain", flag_spain),
    ("PRT", "Portugal", flag_portugal),
    ("NLD", "Netherlands", flag_netherlands),
    ("BEL", "Belgium", flag_belgium),
    ("CHE", "Switzerland", flag_switzerland),
    ("GRC", "Greece", flag_greece),
    ("IRL", "Ireland", flag_ireland),
    ("POL", "Poland", flag_poland),
    ("SWE", "Sweden", flag_sweden),
    ("NOR", "Norway", flag_norway),
    ("UKR", "Ukraine", flag_ukraine),
    ("RUS", "Russia", flag_russia),
    ("TUR", "Turkey", flag_turkey),
    ("ISR", "Israel", flag_israel),
    ("SAU", "Saudi Arabia", flag_saudi_arabia),
    ("MAR", "Morocco", flag_morocco),
    ("EGY", "Egypt", flag_egypt),
    ("NGA", "Nigeria", flag_nigeria),
    ("ZAF", "South Africa", flag_south_africa),
    ("IND", "India", flag_india),
    ("CHN", "China", flag_china),
    ("JPN", "Japan", flag_japan),
    ("KOR", "South Korea", flag_south_korea),
    ("THA", "Thailand", flag_thailand),
    ("PHL", "Philippines", flag_philippines),
    ("AUS", "Australia", flag_australia),
]


# ============================================================
# SFF v2 file writer
# ============================================================
def image_to_png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def create_sff(sprites, output_path):
    """
    sprites: list of (group, index, png_bytes, width, height)
    Writes SFF v2 file matching IkemenGO's expected format.
    """
    HEADER_SIZE = 512
    SPRITE_NODE_SIZE = 28
    PALETTE_NODE_SIZE = 16

    num_sprites = len(sprites)
    num_palettes = 0

    # Palette nodes come first after header, then sprite nodes
    pal_list_offset = HEADER_SIZE
    sprite_list_offset = pal_list_offset + num_palettes * PALETTE_NODE_SIZE
    ldata_offset = sprite_list_offset + num_sprites * SPRITE_NODE_SIZE

    # Build ldata: each sprite = [4-byte uncompressed size] + [PNG data]
    ldata = bytearray()
    sprite_entries = []
    for group, index, png_data, w, h in sprites:
        data_off = len(ldata)
        uncomp_size = w * h * 4  # RGBA
        ldata.extend(struct.pack('<I', uncomp_size))
        ldata.extend(png_data)
        total_len = 4 + len(png_data)
        sprite_entries.append((group, index, w, h, data_off, total_len))

    ldata_length = len(ldata)
    tdata_offset = ldata_offset + ldata_length
    tdata_length = 0

    # Build file
    out = bytearray()

    # -- Header (512 bytes) --
    header = bytearray(HEADER_SIZE)
    header[0:12] = b'ElecbyteSpr\x00'
    # Version: v2.01 (matching artworks.sff: bytes 00 01 00 02)
    header[12] = 0   # verlo3
    header[13] = 1   # verhi
    header[14] = 0   # verlo2
    header[15] = 2   # verlo1
    # Reserved (16-23): 0
    # Compat version (24-27): same as main version
    header[24] = 0
    header[25] = 1
    header[26] = 0
    header[27] = 2
    # Reserved (28-31, 32-35): 0
    # Sprite list offset and count
    struct.pack_into('<I', header, 36, sprite_list_offset)
    struct.pack_into('<I', header, 40, num_sprites)
    # Palette list offset and count
    struct.pack_into('<I', header, 44, pal_list_offset)
    struct.pack_into('<I', header, 48, num_palettes)
    # ldata
    struct.pack_into('<I', header, 52, ldata_offset)
    struct.pack_into('<I', header, 56, ldata_length)
    # tdata
    struct.pack_into('<I', header, 60, tdata_offset)
    struct.pack_into('<I', header, 64, tdata_length)

    out.extend(header)

    # -- Sprite nodes --
    for group, index, w, h, data_off, data_len in sprite_entries:
        node = bytearray(SPRITE_NODE_SIZE)
        struct.pack_into('<H', node, 0, group)     # group
        struct.pack_into('<H', node, 2, index)     # index
        struct.pack_into('<H', node, 4, w)         # width
        struct.pack_into('<H', node, 6, h)         # height
        struct.pack_into('<h', node, 8, w // 2)    # axis x (center)
        struct.pack_into('<h', node, 10, h // 2)   # axis y (center)
        struct.pack_into('<H', node, 12, 0)        # linked index
        node[14] = 12                               # format: PNG32
        node[15] = 32                               # color depth
        struct.pack_into('<I', node, 16, data_off)  # data offset in ldata
        struct.pack_into('<I', node, 20, data_len)  # data length
        struct.pack_into('<H', node, 24, 0)         # palette index
        struct.pack_into('<H', node, 26, 0)         # flags: 0 = ldata
        out.extend(node)

    # -- ldata block --
    out.extend(ldata)

    with open(output_path, 'wb') as f:
        f.write(out)

    return len(out)


# ============================================================
# Main
# ============================================================
CIRCLE_SIZE = 100  # diameter for circular flag sprites


def make_circular_flag(draw_func, size):
    """Create a circular version of a flag, cropped to a circle with transparent BG."""
    # Draw the flag at a larger size, then crop to circle
    flag_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Draw flag stretched to square
    temp = Image.new("RGBA", (FLAG_W, FLAG_H), (0, 0, 0, 255))
    temp_draw = ImageDraw.Draw(temp)
    draw_func(temp, temp_draw)
    # Resize to square
    flag_square = temp.resize((size, size), Image.LANCZOS)
    # Create circular mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.ellipse([0, 0, size - 1, size - 1], fill=255)
    # Apply mask
    flag_img.paste(flag_square, (0, 0))
    flag_img.putalpha(mask)
    # Add circular border
    border_draw = ImageDraw.Draw(flag_img)
    border_draw.ellipse([0, 0, size - 1, size - 1], outline=(60, 60, 60), width=2)
    return flag_img


def main():
    import os
    output = os.path.join(os.path.dirname(os.path.abspath(__file__)), "external", "mods", "flags.sff")
    index_output = os.path.join(os.path.dirname(os.path.abspath(__file__)), "external", "mods", "flags_index.lua")

    print("=" * 50)
    print("  FLAG SFF GENERATOR")
    print("=" * 50)
    print(f"  Generating {len(COUNTRIES)} country flags...")
    print(f"  Rectangular: {FLAG_W}x{FLAG_H}  |  Circular: {CIRCLE_SIZE}x{CIRCLE_SIZE}")
    print()

    sprites = []

    # Group 0: rectangular flags (original)
    for i, (code, name, draw_func) in enumerate(COUNTRIES):
        img = Image.new("RGBA", (FLAG_W, FLAG_H), (0, 0, 0, 255))
        draw = ImageDraw.Draw(img)
        draw_func(img, draw)
        # Add 1px dark border for visibility
        draw.rectangle([0, 0, FLAG_W - 1, FLAG_H - 1], outline=(40, 40, 40), width=1)
        png_data = image_to_png_bytes(img)
        sprites.append((0, i, png_data, FLAG_W, FLAG_H))
        print(f"  [{i:2d}] {code} - {name} (rect)")

    # Group 1: circular flags (for orb overlay)
    for i, (code, name, draw_func) in enumerate(COUNTRIES):
        circ_img = make_circular_flag(draw_func, CIRCLE_SIZE)
        png_data = image_to_png_bytes(circ_img)
        sprites.append((1, i, png_data, CIRCLE_SIZE, CIRCLE_SIZE))
        print(f"  [{i:2d}] {code} - {name} (circle)")

    print()
    file_size = create_sff(sprites, output)
    print(f"  Wrote: {output}")
    print(f"  Size: {file_size:,} bytes")

    # Write Lua index file for the mod to require
    with open(index_output, "w") as f:
        f.write("-- Auto-generated by create_flags_sff.py\n")
        f.write("-- Maps sprite index to country code and name\n")
        f.write("local flags_index = {\n")
        for i, (code, name, _) in enumerate(COUNTRIES):
            f.write(f'  [{i}] = {{code = "{code}", name = "{name}"}},\n')
        f.write("}\n")
        f.write(f"local flags_count = {len(COUNTRIES)}\n")
        f.write("return {index = flags_index, count = flags_count}\n")

    print(f"  Wrote: {index_output}")
    print()
    print("  Done! Now run IkemenGO to test the flags.")


if __name__ == "__main__":
    main()
