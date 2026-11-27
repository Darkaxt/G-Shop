"""The Dendy cartridge board: one layout shared by its textures and its geometry.

Modelled on the DIP board in "Dendy cartridge PCBs.jpg" by Nzeemin (Wikimedia
Commons, CC BY-SA 3.0, https://commons.wikimedia.org/wiki/File:Dendy_cartridge_PCBs.jpg).
Positions were measured on that photograph at its 2.54 mm edge-finger pitch
(17.62 px/mm). Outline, finger count, packages, pin counts, chip markings,
discretes, vias, wide supply bands and silkscreen follow the photo; the fine
trace routing and the whole back side are interpreted, not traced. No photo
pixels are used: everything is drawn from this vector layout, so the artwork can
be rendered at any resolution (G-Shop uses 20 px/mm; a close-up museum scene can
ask for more).

Units are millimetres. x runs across the board (0 at its centre, seen from the
component side), z up from the bottom of the edge fingers.

As a script it renders the textures:
  python -I dendy_pcb.py OUTDIR [--px-per-mm 20]
writing dendy-pcb-front.png, dendy-pcb-back.png and dendy-pcb-layout.json.
Blender imports the module only for the layout (no PIL needed there).
"""
import json
import math

PX_PER_MM = 17.62                    # measured photograph scale
WIDTH, HEIGHT, THICKNESS = 98.2, 52.2, 1.2
TAB_WIDTH, TAB_HEIGHT = 78.0, 11.1
NOTCH = (18.0, 20.6, 2.4)            # z from, z to, depth on both sides
FINGERS, PITCH, FINGER_W, FINGER_Z = 30, 2.54, 1.75, (0.4, 8.8)


def photo(x, y):
    """Photograph pixel (left edge x=105, board bottom y=1000) to board mm."""
    return round((x - 105) / PX_PER_MM - WIDTH / 2, 2), round((1000 - y) / PX_PER_MM, 2)


def outline():
    w, t, (n0, n1, d) = WIDTH / 2, TAB_WIDTH / 2, NOTCH
    right = [(t, 0), (t, TAB_HEIGHT), (w, TAB_HEIGHT), (w, n0), (w - d, n0),
             (w - d, n1), (w, n1), (w, HEIGHT - .8), (w - .8, HEIGHT)]
    return right + [(-x, z) for x, z in reversed(right)]


def finger_x(i):
    return (i - (FINGERS - 1) / 2) * PITCH


# name, markings, pins, centre x/z, body length/width, row spacing, pin 1 at left.
CHIPS = [
    dict(ref='U1', part='HD74LS74AP', lines=['9G5 4', 'HD74LS74AP'], logo='hitachi',
         pins=14, at=photo(430, 185), size=(19.1, 6.2), rows=7.62, pin1_left=True),
    dict(ref='U2', part='AX5904', lines=['AX5904'], pins=24, at=photo(947, 186),
         size=(31.2, 6.2), rows=7.62, pin1_left=True, big=True),
    dict(ref='U3', part='DM74S133N', lines=['P8818', 'DM74S133N'], logo='ns',
         pins=16, at=photo(447, 352), size=(19.0, 6.0), rows=7.62, pin1_left=True,
         band=True),
    dict(ref='U4', part='unmarked DIP-16', lines=[], pins=16, at=photo(835, 357),
         size=(18.7, 6.0), rows=7.62, pin1_left=False),
    dict(ref='U5', part='unmarked DIP-16', lines=[], pins=16, at=photo(1435, 366),
         size=(18.7, 6.0), rows=7.62, pin1_left=False),
    dict(ref='U6', part='B020A', lines=['B020A'], pins=32, at=photo(577, 600),
         size=(41.7, 13.6), rows=15.24, pin1_left=True, rom=True),
    dict(ref='U7', part='B020B', lines=['B020B'], pins=32, at=photo(1360, 600),
         size=(41.4, 13.6), rows=15.24, pin1_left=True, rom=True),
]

# Discretes: kind, body centre, lead holes, size (mm).
DISCRETES = [
    dict(ref='C1', kind='disc', marking='104Z', at=photo(165, 310), d=5.0, t=2.2,
         holes=[photo(235, 295), photo(230, 385)], angle=-72),
    dict(ref='D1', kind='diode', at=photo(182, 552), length=3.6, d=1.8,
         holes=[photo(185, 465), photo(180, 640)]),
    dict(ref='D2', kind='diode', at=photo(1137, 380), length=4.0, d=1.8,
         holes=[photo(1047, 380), photo(1222, 380)]),
    dict(ref='R1', kind='resistor', at=photo(1135, 428), length=5.6, d=2.2,
         holes=[photo(1047, 428), photo(1222, 428)],
         bands=['brown', 'black', 'red', 'gold']),
]

VIAS = [photo(*p) for p in [
    (238, 125), (235, 212), (188, 252), (185, 422), (115, 470), (115, 555),
    (185, 762), (633, 125), (633, 215), (1410, 135), (1518, 162), (1300, 262),
    (1390, 265), (1780, 485), (1785, 575), (380, 800), (442, 800), (1085, 790),
    (1270, 800), (1460, 795)]]

SILK = [  # text, centre, height, rotation in degrees
    ('74', photo(165, 125), 1.3, 0), ('830733C', photo(1650, 155), 1.5, 0),
    ('0017', photo(1640, 186), 1.5, 0), ('1', photo(125, 765), 1.2, 0),
    ('30', photo(1815, 785), 1.2, 0)]
CAP_SYMBOLS = [photo(215, 172), photo(236, 342), photo(115, 510), photo(1790, 530),
               photo(1355, 268)]

# Wide supply bands (copper under the mask, much lighter than the board).
BANDS = [
    [photo(*p) for p in [(1215, 218), (1765, 218), (1795, 248), (1795, 735),
                         (1765, 765), (1640, 770), (1615, 795), (1615, 830)]],
    [photo(*p) for p in [(1240, 258), (1560, 258), (1590, 288), (1590, 300)]],
    [photo(*p) for p in [(235, 212), (178, 240), (160, 262), (160, 500), (115, 555)]],
    [photo(*p) for p in [(185, 762), (255, 762), (300, 800), (300, 830)]],
]
BAND_WIDTH = 1.5


def pin_positions(chip):
    """Through-hole centres, numbered anticlockwise from pin 1 (seen from above)."""
    (cx, cz), n = chip['at'], chip['pins'] // 2
    out = []
    for i in range(n):          # pin 1 row runs along the bottom when pin 1 is left
        out.append((cx + (i - (n - 1) / 2) * PITCH, cz - chip['rows'] / 2))
    for i in range(n):
        out.append((cx + ((n - 1) / 2 - i) * PITCH, cz + chip['rows'] / 2))
    if not chip['pin1_left']:
        out = [(2 * cx - x, 2 * cz - z) for x, z in out]
    return out


def routes():
    """Fine signal traces, front and back: edge fingers into the ROM pins and vias."""
    front, back = [], []
    rom_a = pin_positions(CHIPS[5])[:16]
    rom_b = pin_positions(CHIPS[6])[:16]
    pins = sorted(rom_a + rom_b)
    used = -1
    for i in range(1, FINGERS - 1):      # fingers 1 and 30 are the supply bands
        x, top = finger_x(i), FINGER_Z[1]
        if i % 5 == 3:                   # some leave through a via to the back
            vx, vz = x + 2.2, 12.4 + (i % 3) * .55
            front.append([(x, top), (x, top + .8), (vx, top + 3), (vx, vz)])
            back.append([(vx, vz), (vx, vz + .9)])
            continue
        # The photo's fan: a short rise, a 45 degree run up and right, then
        # straight into the nearest free ROM pin.
        want = x + 3.0 + (i % 3) * .6
        k = min((k for k in range(used + 1, len(pins))), key=lambda k: abs(pins[k][0] - want))
        used = k
        tx, tz = pins[k]
        rise = top + .7 + (i % 2) * .5
        run = max(0.0, min(tx - x, tz - 1.3 - rise))
        front.append([(x, top), (x, rise), (x + run, rise + run), (tx, rise + run), (tx, tz)])
    free = [p for p in sorted(rom_a + rom_b) if p not in [f[-1] for f in front]]
    for j, (px, pz) in enumerate(free[::2]):   # the rest reach the fingers on the back
        i = min(range(1, FINGERS - 1), key=lambda i: abs(finger_x(i) - px))
        x = finger_x(i)
        back.append([(x, FINGER_Z[1]), (x, FINGER_Z[1] + 1 + (j % 3) * .5),
                     (px, FINGER_Z[1] + 1 + (j % 3) * .5 + abs(px - x)), (px, pz)])
    # Shared ROM address/data lines: nested U-shaped runs under both ROMs.
    top_a = pin_positions(CHIPS[5])[16:]   # right to left along the top row
    top_b = pin_positions(CHIPS[6])[16:][::-1]
    for k in range(14):
        a, b = top_a[k], top_b[k]
        z = 28.6 - k * .82
        back.append([a, (a[0], z), (b[0], z), b])
    # Address/data buses between the logic chips and the ROM top rows.
    u = [pin_positions(c) for c in CHIPS]
    for k in range(8):
        z = 31.2 + k * .62
        a, b = u[5][16 + k], u[6][16 + k]
        front.append([(a[0], a[1]), (a[0], z), (b[0] - 1.2 - k * .3, z), (b[0], b[1])])
    for k in range(7):
        z = 41.5 - k * .6
        p, q = u[0][k], u[1][k]
        back.append([(p[0], p[1]), (p[0] + 1.27, z), (q[0] - 1.27, z), (q[0], q[1])])
    for k in range(6):
        p, q = u[2][8 + k], u[3][8 + k]
        front.append([(p[0], p[1]), (p[0], p[1] + 1.1 + k * .45), (q[0], q[1] + 1.1 + k * .45), q])
    for k in range(8):
        p, q = u[4][k], u[6][31 - k]
        back.append([p, (p[0], p[1] - 1.6 - k * .35), (q[0], p[1] - 1.6 - k * .35), q])
    for k in range(6):                   # logic outputs down to the ROM enables
        p, q = u[1][k], u[5][31 - k]
        back.append([p, (p[0], 33.4 - k * .5), (q[0], 33.4 - k * .5), q])
    return front, back


def holes():
    """Every plated hole: (x, z, pad diameter)."""
    out = [(x, z, 1.75) for c in CHIPS for x, z in pin_positions(c)]
    out += [(x, z, 1.6) for d in DISCRETES for x, z in d['holes']]
    out += [(x, z, 1.25) for x, z in VIAS]
    f, b = routes()
    for path in b:
        if len(path) == 2:               # via where a front trace crosses over
            out.append((*path[0], .95))
    return out


def layout():
    front, back = routes()
    return dict(source='Dendy cartridge PCBs.jpg, Nzeemin, Wikimedia Commons, CC BY-SA 3.0',
                units='mm', width=WIDTH, height=HEIGHT, thickness=THICKNESS,
                outline=outline(), fingers=[finger_x(i) for i in range(FINGERS)],
                fingerWidth=FINGER_W, fingerZ=FINGER_Z, chips=CHIPS,
                pins={c['ref']: pin_positions(c) for c in CHIPS}, discretes=DISCRETES,
                vias=VIAS, holes=holes(), silkscreen=SILK, bands=BANDS,
                frontTraces=front, backTraces=back)


# --- texture rendering (PIL; not used inside Blender) -------------------------

MASK = (6, 104, 84)
COPPER = (14, 168, 146)
TRACE = (10, 138, 112)
SILK_INK = (96, 196, 172)
TIN = (196, 196, 188)
CHIP_BODY = (30, 33, 38)
CHIP_INK = (112, 120, 128)
ROM_INK = (88, 128, 178)
DISC = (196, 140, 92)


def render(px_per_mm=20, supersample=2):
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    s = px_per_mm * supersample
    size = (round(WIDTH * s), round(HEIGHT * s))

    def P(x, z):
        return ((x + WIDTH / 2) * s, (HEIGHT - z) * s)

    fonts = 'C:/Windows/Fonts/'

    def font(name, mm):
        return ImageFont.truetype(fonts + name, max(4, round(mm * s)))

    def polyline(d, path, width, fill):
        pts = [P(*p) for p in path]
        d.line(pts, fill=fill, width=max(1, round(width * s)), joint='curve')
        r = width * s / 2
        for x, y in pts:
            d.ellipse((x - r, y - r, x + r, y + r), fill=fill)

    def disc(d, x, z, dia, fill):
        cx, cy = P(x, z)
        r = dia * s / 2
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)

    def text(img, msg, x, z, mm, fill, fname='arial.ttf', angle=0):
        f = font(fname, mm)
        box = f.getbbox(msg)
        w, h = box[2] - box[0] + 4, box[3] - box[1] + 4
        layer = Image.new('L', (w, h), 0)
        ImageDraw.Draw(layer).text((2 - box[0], 2 - box[1]), msg, font=f, fill=255)
        if angle:
            layer = layer.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)
        cx, cy = P(x, z)
        img.paste(Image.new('RGB', layer.size, fill),
                  (round(cx - layer.width / 2), round(cy - layer.height / 2)), layer)

    def base():
        img = Image.new('RGB', size, MASK)
        d = ImageDraw.Draw(img)
        for i in range(FINGERS):    # tin fingers, drawn too (the geometry sits on them)
            x = finger_x(i)
            x0, y0 = P(x - FINGER_W / 2, FINGER_Z[1])
            x1, y1 = P(x + FINGER_W / 2, FINGER_Z[0])
            d.rectangle((x0, y0, x1, y1), fill=TIN)
        return img, d

    def pads(d):
        for x, z, dia in holes():
            disc(d, x, z, dia, TIN)
            disc(d, x, z, dia * .42, (60, 62, 60))

    # Front: component side.
    img, d = base()
    for band in BANDS:
        polyline(d, band, BAND_WIDTH, COPPER)
    front, back = routes()
    for path in front:
        polyline(d, path, .32, TRACE)
    for i in (0, FINGERS - 1):
        polyline(d, [(finger_x(i), FINGER_Z[1]), (finger_x(i), FINGER_Z[1] + 1.6)], 1.5, COPPER)
    pads(d)
    for msg, (x, z), h, a in SILK:
        text(img, msg, x, z, h, SILK_INK, 'lucon.ttf', a)
    for x, z in CAP_SYMBOLS:
        for dx in (-.25, .25):
            polyline(d, [(x + dx, z - .55), (x + dx, z + .55)], .16, SILK_INK)
        polyline(d, [(x - .9, z), (x - .25, z)], .16, SILK_INK)
        polyline(d, [(x + .25, z), (x + .9, z)], .16, SILK_INK)
    # Chip tops: the chip bodies share this atlas through the same projection.
    for c in CHIPS:
        (cx, cz), (L, W) = c['at'], c['size']
        # A small margin keeps the projected package sides out of the mask colour.
        m = .25
        d.rectangle((*P(cx - L / 2 - m, cz + W / 2 + m), *P(cx + L / 2 + m, cz - W / 2 - m)),
                    fill=CHIP_BODY)
        x0, y0 = P(cx - L / 2, cz + W / 2)
        x1, y1 = P(cx + L / 2, cz - W / 2)
        end = -1 if c['pin1_left'] else 1
        nx = cx + end * L / 2
        disc(d, nx, cz, W * .22, (14, 15, 17))          # moulded end notch
        if c.get('band'):
            bx0, _ = P(cx - L / 2, 0)
            bx1, _ = P(cx - L / 2 + 1.6, 0)
            d.rectangle((bx0, y0, bx1, y1), fill=(52, 56, 62))
        if c.get('rom'):
            for dx, dz, dd in ((-L * .38, 0, 2.6), (L * .38, 0, 2.6), (-L * .45, -W * .3, 1.3)):
                disc(d, cx + dx, cz + dz, dd, (40, 44, 50))
            text(img, c['lines'][0], cx, cz, W * .5, ROM_INK, 'ARIALNB.TTF')
        elif c.get('big'):
            disc(d, cx - L * .43, cz, 1.0, (20, 21, 24))
            text(img, c['lines'][0], cx + 1, cz, W * .42, CHIP_INK, 'arial.ttf')
        elif c['lines']:
            disc(d, cx - L * .42, cz - W * .05, .9, (20, 21, 24))
            text(img, c['lines'][0], cx + 1.2, cz + W * .17, W * .26, CHIP_INK, 'arial.ttf')
            text(img, c['lines'][1], cx + .4, cz - W * .2, W * .26, CHIP_INK, 'arial.ttf')
            lx, lz = cx - L * .3, cz + W * .17
            if c.get('logo') == 'hitachi':
                disc(d, lx, lz, 1.5, CHIP_INK)
                disc(d, lx, lz, 1.0, CHIP_BODY)
                polyline(d, [(lx - .75, lz), (lx + .75, lz)], .2, CHIP_INK)
                polyline(d, [(lx, lz - .75), (lx, lz + .75)], .2, CHIP_INK)
            else:                                        # National Semiconductor mark
                polyline(d, [(lx - .7, lz - .6), (lx - .7, lz + .6), (lx + .7, lz - .6),
                             (lx + .7, lz + .6)], .28, CHIP_INK)
        else:
            disc(d, nx - end * 1.6, cz, .9, (20, 21, 24))
    for part in DISCRETES:
        if part['kind'] == 'disc':
            x, z = part['at']
            disc(d, x, z, part['d'] + .4, DISC)
            text(img, part['marking'], x, z, 1.1, (120, 70, 40), 'arial.ttf', part['angle'])
    front_img = img.filter(ImageFilter.GaussianBlur(supersample * .35))

    # Back: solder side, drawn in board coordinates, then mirrored as seen from behind.
    img, d = base()
    for band in BANDS[:2]:
        polyline(d, [(x, z) for x, z in band], BAND_WIDTH * .8, COPPER)
    for path in back:
        polyline(d, path, .32, TRACE)
    for i in range(1, FINGERS - 1):
        if i % 5 != 3:
            x = finger_x(i)
            polyline(d, [(x, FINGER_Z[1]), (x, FINGER_Z[1] + 1.4 + (i % 3) * .4)], .32, TRACE)
    polyline(d, [(-WIDTH / 2 + 2, HEIGHT - 2), (WIDTH / 2 - 2, HEIGHT - 2)], 1.2, COPPER)
    pads(d)
    for x, z, dia in holes():      # solder fillets read brighter on this side
        disc(d, x, z, dia * .7, (214, 214, 206))
    back_img = img.filter(ImageFilter.GaussianBlur(supersample * .35))
    back_img = back_img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)

    out = []
    for im in (front_img, back_img):
        out.append(im.resize((size[0] // supersample, size[1] // supersample),
                             Image.Resampling.LANCZOS))
    return out


def main():
    import argparse
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--px-per-mm', type=float, default=20)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    front, back = render(args.px_per_mm)
    front.save(args.output / 'dendy-pcb-front.png', optimize=True)
    back.save(args.output / 'dendy-pcb-back.png', optimize=True)
    (args.output / 'dendy-pcb-layout.json').write_text(json.dumps(layout(), indent=1), encoding='utf-8')
    print(args.output, front.size)


if __name__ == '__main__':
    main()
