"""Draw the textures and key layout of the Subor SB-225B keyboard computer.

The SB-225B ("Сюбор: обучение в игре", 2 in 1) is a Famicom clone built into a
101-key keyboard: a light grey case with cream alphanumeric keys, olive-grey
modifier keys, black Cyrillic and red Latin legends, a raised rear ledge with the
red Subor mascot and wordmark, a top cartridge slot behind a white flap and the
"RUSSIAN-ENGLISH COMPUTER LEARNING SET SB225-B" print, plus a Num/Caps/Power
indicator panel above the keypad. Everything here is redrawn from photographs of
a museum unit (Soviet Digital Electronics Museum, Sergei Frolov 2008,
http://www.leningrad.su/museum/show_calc.php?n=227); no photo pixels are used. Surfaces carry mild grime and speckle, like a used unit.

Writes keys.png, deck.png, ledge.png, cart-label.png, pad.png and layout.json
(key positions in key units plus atlas UV rectangles) for build_subor_sb225b.py.

Usage: python -I make_subor_sb225b_textures.py OUTDIR
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONTS = Path('C:/Windows/Fonts')
CREAM = (226, 223, 207)
OLIVE = (132, 134, 106)
CASE = (203, 201, 189)
PANEL = (96, 98, 90)
INK = (22, 22, 24)
RED = (206, 30, 34)
LOGO_RED = (214, 34, 38)
U = 44  # atlas pixels per key unit

CYR = dict(zip('QWERTYUIOP[]ASDFGHJKL;\'ZXCVBNM,./',
               'ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ'))


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), max(6, round(size)))


def fit_text(d, xy, max_width, size, text, face, fill, anchor):
    """Draw text at the largest size up to `size` that fits `max_width` pixels."""
    while size > 6 and d.textlength(text, font=font(face, size)) > max_width:
        size *= .95
    d.text(xy, text, font=font(face, size), fill=fill, anchor=anchor)


def layout():
    """(id, x, y, w, h, colour, legends) in key units; y grows towards the user."""
    keys = []

    def key(kid, x, y, w=1, h=1, colour='cream', legends=None):
        keys.append({'id': kid, 'x': x, 'y': y, 'w': w, 'h': h, 'colour': colour,
                     'legends': legends or {}})

    key('Esc', 0, 0, colour='olive', legends={'c': 'Esc'})
    for i in range(12):
        x = 2 + i + (i // 4) * .5
        key(f'F{i + 1}', x, 0, colour='olive' if 4 <= i < 8 else 'cream', legends={'c': f'F{i + 1}'})
    for i, name in enumerate(('Pause', 'Break', 'Reset')):
        key(name, 15.5 + i, 0, colour='olive', legends={'c': name})
    row1 = [('~', '`', 'Ё'), ('!', '1', ''), ('@', '2', '"'), ('#', '3', '№'), ('$', '4', ';'),
            ('%', '5', '%'), ('^', '6', ':'), ('&', '7', '?'), ('*', '8', '*'), ('(', '9', '('),
            (')', '0', ')'), ('_', '-', '_'), ('+', '=', '+')]
    for i, (shift, base, red) in enumerate(row1):
        key(f'R1-{i}', i, 1.5, legends={'tl': shift, 'bl': base, 'br': red})
    key('Backspace', 13, 1.5, 2, colour='olive', legends={'c': '←'})
    key('Tab', 0, 2.5, 1.5, colour='olive', legends={'tl': 'Tab'})
    for i, ch in enumerate('QWERTYUIOP[]'):
        key(f'K-{ch}', 1.5 + i, 2.5, legends={'cyr': CYR[ch], 'lat': ch.lower() if ch.isalpha() else ch})
    key('Enter-top', 13.5, 2.5, 1.5, colour='olive')
    key('Caps', 0, 3.5, 1.75, colour='olive', legends={'tl': 'Caps'})
    for i, ch in enumerate('ASDFGHJKL;\''):
        key(f'K-{ch}', 1.75 + i, 3.5, legends={'cyr': CYR[ch], 'lat': ch.lower() if ch.isalpha() else ch})
    key('Enter', 12.75, 3.5, 2.25, colour='olive', legends={'c': 'Enter'})
    key('LShift', 0, 4.5, 2.25, colour='olive', legends={'tl': 'Shift'})
    for i, ch in enumerate('ZXCVBNM,./'):
        key(f'K-{ch}', 2.25 + i, 4.5, legends={'cyr': CYR[ch], 'lat': ch.lower() if ch.isalpha() else ch})
    key('RShift', 12.25, 4.5, 2.75, colour='olive', legends={'c': 'Shift'})
    key('LCtrl', 0, 5.5, 1.5, colour='olive', legends={'tl': 'Ctrl'})
    key('LAlt', 1.5, 5.5, 1.5, colour='olive', legends={'tl': 'Alt'})
    key('Space', 3, 5.5, 7)
    key('RAlt', 10, 5.5, 1.5, colour='olive', legends={'tl': 'Alt'})
    key('RCtrl', 13.5, 5.5, 1.5, colour='olive', legends={'tl': 'Ctrl'})
    for i, name in enumerate(('Insert', 'Home', 'Page Up')):
        key(name, 15.5 + i, 1.5, colour='olive', legends={'c': name})
    for i, name in enumerate(('Delete', 'End', 'Page Down')):
        key(name, 15.5 + i, 2.5, colour='olive', legends={'c': name})
    key('Up', 16.5, 4.5, colour='olive', legends={'c': '↑'})
    for i, name in enumerate('←↓→'):
        key(f'Arrow{i}', 15.5 + i, 5.5, colour='olive', legends={'c': name})
    for i, name in enumerate(('Num Lock', '/', '*', '−')):
        key(f'Pad{name}', 19 + i, 1.5, colour='olive', legends={'c': name})
    pad = [('7', 'Home'), ('8', '↑'), ('9', 'PgUp'), ('4', '←'), ('5', ''), ('6', '→'),
           ('1', 'End'), ('2', '↓'), ('3', 'PgDn')]
    for i, (num, alt) in enumerate(pad):
        key(f'Pad{num}', 19 + i % 3, 2.5 + i // 3, legends={'tl': num, 'bl': alt})
    key('Pad+', 22, 2.5, 1, 2, colour='olive', legends={'c': '+'})
    key('Pad0', 19, 5.5, 2, legends={'tl': '0', 'bl': 'Ins'})
    key('Pad.', 21, 5.5, legends={'tl': '.', 'bl': 'Del'})
    key('PadEnter', 22, 4.5, 1, 2, colour='olive', legends={'c': 'Enter'})
    return keys


def grime(size, seed, depth=.07, speckle=.004):
    """Multiplicative wear: low-frequency blotches plus sparse dark specks."""
    rng = np.random.default_rng(seed)
    w, h = size
    low = rng.random((max(2, h // 64), max(2, w // 64))).astype(np.float32)
    low = np.asarray(Image.fromarray((low * 255).astype(np.uint8)).resize(
        (w, h), Image.Resampling.BICUBIC), dtype=np.float32) / 255
    fine = rng.random((h, w)).astype(np.float32)
    out = 1 - depth * low - .025 * fine
    out[rng.random((h, w)) < speckle] *= .78
    return out[..., None]


def worn(img, seed, **kw):
    arr = np.asarray(img.convert('RGB'), dtype=np.float32) * grime(img.size, seed, **kw)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def draw_key(cell, k):
    d = ImageDraw.Draw(cell)
    w, h = cell.size
    lg = k['legends']
    small = font('arial.ttf', U * .22)
    if 'cyr' in lg:
        d.text((w * .16, h * .14), lg['cyr'], font=font('arialbd.ttf', U * .40), fill=INK)
        d.text((w * .80, h * .78), lg['lat'], font=font('arial.ttf', U * .28), fill=RED, anchor='mm')
    if 'tl' in lg:
        d.text((w * .14, h * .12), lg['tl'], font=small, fill=INK)
    if 'bl' in lg:
        d.text((w * .14, h * .54), lg['bl'], font=small, fill=INK)
    if 'br' in lg:
        d.text((w * .80, h * .76), lg['br'], font=small, fill=RED, anchor='mm')
    if 'c' in lg:
        lines = lg['c'].split(' ') if len(lg['c']) > 6 and k['w'] <= 1 else [lg['c']]
        f = font('arial.ttf', U * (.18 if len(lines) > 1 else .22))
        for i, line in enumerate(lines):
            d.text((w / 2, h * (.5 + (i - (len(lines) - 1) / 2) * .26)), line, font=f,
                   fill=INK if k['colour'] == 'cream' else (30, 32, 26), anchor='mm')


def key_atlas(keys, size=1024):
    atlas = Image.new('RGB', (size, size), CASE)
    x = y = 4
    shelf = 0
    for k in sorted(keys, key=lambda k: -k['h']):
        w, h = round(k['w'] * U), round(k['h'] * U)
        if x + w > size - 4:
            x, y, shelf = 4, y + shelf + 4, 0
        cell = Image.new('RGB', (w, h), CREAM if k['colour'] == 'cream' else OLIVE)
        draw_key(cell, k)
        atlas.paste(cell, (x, y))
        k['uv'] = [x / size, 1 - (y + h) / size, (x + w) / size, 1 - y / size]
        x += w + 4
        shelf = max(shelf, h)
    swatches = {}
    for i, (name, colour) in enumerate((('cream', CREAM), ('olive', OLIVE))):
        sx, sy = 4 + i * 40, size - 40
        atlas.paste(Image.new('RGB', (32, 32), tuple(round(c * .9) for c in colour)), (sx, sy))
        swatches[name] = [(sx + 16) / size, 1 - (sy + 16) / size]
    return worn(atlas, 1, depth=.05, speckle=.002), swatches


def mascot(size, colour=LOGO_RED):
    """Subor's mascot reduced to its silhouette: a curly red head with a white face."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size
    for cx, cy, r in ((.30, .34, .20), (.70, .34, .20), (.50, .24, .20), (.20, .55, .17),
                      (.80, .55, .17), (.50, .62, .30)):
        d.ellipse((s * (cx - r), s * (cy - r), s * (cx + r), s * (cy + r)), fill=colour)
    d.ellipse((s * .32, s * .40, s * .68, s * .78), fill=(250, 246, 236))
    for ex in (.43, .57):
        d.ellipse((s * (ex - .025), s * .52, s * (ex + .025), s * .57), fill=INK)
    d.arc((s * .42, s * .58, s * .58, s * .70), 20, 160, fill=colour, width=max(1, s // 40))
    d.rounded_rectangle((s * .18, s * .80, s * .82, s * .96), s * .05, fill=colour)
    d.text((s * .5, s * .88), 'СЮБОР', font=font('arialbd.ttf', s * .12), fill=(255, 255, 255), anchor='mm')
    return img


def ledge(width_m, depth_m, slot):
    """Top of the raised rear ledge: mascot and wordmark, slot frame, product print."""
    w = 1024
    h = round(w * depth_m / width_m)  # square pixels: print keeps its proportions
    img = Image.new('RGB', (w, h), CASE)
    d = ImageDraw.Draw(img)
    px = lambda xm: round((xm / width_m + .5) * w)
    logo = mascot(round(h * .58))
    img.paste(logo, (px(-.226), round(h * .18)), logo)
    # Wordmark and product print fill the ledge either side of the slot, as on the unit.
    word_left = px(-.226) + logo.width + h * .04
    fit_text(d, (word_left, h * .50), px(slot[0]) - h * .14 - word_left, h * .50, 'СЮБОР',
             'timesbi.ttf', LOGO_RED, 'lm')
    d.text((px(-.226) + logo.width * .92, h * .10), '®', font=font('arial.ttf', h * .12), fill=LOGO_RED)
    tx, span = px((slot[1] + width_m / 2) / 2), (px(width_m / 2) - px(slot[1])) * .90
    fit_text(d, (tx, h * .36), span, h * .22, 'RUSSIAN-ENGLISH COMPUTER LEARNING SET',
             'ARIALNB.TTF', INK, 'mm')
    d.text((tx, h * .68), 'SB225 - B', font=font('timesbd.ttf', h * .21), fill=INK, anchor='mm')
    return worn(img, 2)


def deck(width_m, depth_m, keys_front, keys_back, unit):
    """Sloped key deck: the italic SUBOR mark and the indicator panel."""
    w = 1024
    h = round(w * depth_m / width_m)
    img = Image.new('RGB', (w, h), CASE)
    d = ImageDraw.Draw(img)
    px = lambda xm: round((xm / width_m + .5) * w)
    py = lambda ym: round((1 - (ym - keys_front) / depth_m) * h)  # image top = back of deck
    left = -23 * unit / 2
    d.text((px(left + 8.5 * unit), py(keys_back + .012)), 'SUBOR', font=font('timesbi.ttf', h * .09),
           fill=(40, 40, 42), anchor='mm')
    # Indicator panel over the keypad: three labelled lamps and the power button seat.
    x0, x1 = px(left + 19 * unit), px(left + 23 * unit)
    y0, y1 = py(keys_back + .001), py(keys_back - unit + .001)
    d.rounded_rectangle((x0, y0, x1, y1), 4, fill=PANEL, outline=(70, 72, 66), width=2)
    cw = (x1 - x0) / 4
    for i, label in enumerate(('Num\nLock', 'Caps', 'Power')):
        cx = x0 + cw * (i + .5)
        d.rectangle((cx - cw * .44, y0 + 4, cx + cw * .44, y1 - 4), outline=(122, 124, 114), width=1)
        d.multiline_text((cx, y0 + (y1 - y0) * .38), label, font=font('arial.ttf', (y1 - y0) * .16),
                         fill=(196, 196, 184), anchor='mm', align='center')
        lamp = (236, 120, 40) if label == 'Power' else (120, 60, 30)
        d.rectangle((cx - cw * .16, y0 + (y1 - y0) * .70, cx + cw * .16, y0 + (y1 - y0) * .80), fill=lamp)
    d.ellipse((x0 + cw * 3.15, y0 + (y1 - y0) * .15, x0 + cw * 3.85, y1 - (y1 - y0) * .15), fill=(60, 62, 56))
    return worn(img, 3, depth=.09)


def cart_label():
    """Second-issue 'Обучающий картридж V1.0' label: blue band, mascot, contents, red band."""
    w, h = 512, 300
    img = Image.new('RGB', (w, h), (224, 230, 168))
    d = ImageDraw.Draw(img)
    for y in range(36, h - 30, 10):
        d.line((0, y, w, y), fill=(206, 218, 150), width=2)
    d.rectangle((0, 0, w, 34), fill=(40, 140, 196))
    d.rectangle((0, h - 30, w, h), fill=(222, 40, 44))
    logo = mascot(86)
    img.paste(logo, (12, 28), logo)
    d.text((300, 66), 'ОБУЧАЮЩИЙ  КАРТРИДЖ', font=font('timesbd.ttf', 30), fill=(30, 40, 110), anchor='mm')
    d.text((300, 102), '( V 1.0 )', font=font('arialbd.ttf', 22), fill=(30, 40, 110), anchor='mm')
    items = ['1. Управление с клавиатурой', '2. Занимательное печатание', '3. Музыка и песни',
             '4. Редактирование']
    for i, t in enumerate(items):
        d.text((40, 136 + i * 28), t, font=font('times.ttf', 21), fill=INK)
    for i, t in enumerate(('5. Вычисления', '6. G-BASIC', '7. F-BASIC')):
        d.text((340, 136 + i * 28), t, font=font('times.ttf', 21), fill=INK)
    return worn(img, 4, depth=.06)


def pad_face():
    """Both joystick face plates side by side (each half matches the 118 x 52 mm pad top):
    I has Select/Start, II has none. Buttons and D-pad are geometry over this print."""
    w, h = 1024, 224
    img = Image.new('RGB', (w, h), (198, 196, 186))
    d = ImageDraw.Draw(img)
    light = (236, 234, 224)
    for i in range(2):
        ox = i * w // 2
        d.rounded_rectangle((ox + 12, 12, ox + 500, 212), 18, fill=(92, 96, 112))
        for y in (188, 196):
            d.line((ox + 24, y, ox + 488, y), fill=(160, 164, 176), width=2)
        d.rectangle((ox + 24, 20, ox + 24 + 22 + 8 * i, 46), fill=light)
        d.text((ox + 35 + 4 * i, 33), 'I' * (i + 1), font=font('timesbd.ttf', 22), fill=INK, anchor='mm')
        logo = mascot(58, light)
        img.paste(logo, (ox + 227, 12), logo)
        d.text((ox + 256, 92), 'JOYSTICK', font=font('arialbd.ttf', 20), fill=light, anchor='mm')
        d.text((ox + 413, 24), 'TURBO', font=font('arialbd.ttf', 15), fill=light, anchor='mm')
        d.text((ox + 376, 108), 'B', font=font('arialbd.ttf', 13), fill=light, anchor='mm')
        d.text((ox + 450, 108), 'A', font=font('arialbd.ttf', 13), fill=light, anchor='mm')
        if i == 0:
            d.text((ox + 256, 122), 'SELECT   START', font=font('arialbd.ttf', 11), fill=light, anchor='mm')
            d.rounded_rectangle((ox + 206, 134, ox + 306, 162), 13, fill=light)
            for sx in (232, 280):
                d.rounded_rectangle((ox + sx - 14, 142, ox + sx + 14, 154), 6, fill=(70, 72, 80))
    return worn(img, 5, depth=.08)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    unit = .019
    body = {'width': .476, 'depth': .200, 'unit': unit, 'keysFront': -.093,
            'keysBack': -.093 + 6.5 * unit, 'ledgeFront': .059, 'ledgeBack': .099,
            'slot': [-.062, .062]}
    keys = layout()
    atlas, swatches = key_atlas(keys)
    atlas.save(args.output / 'keys.png', optimize=True)
    ledge(body['width'], body['ledgeBack'] - body['ledgeFront'], body['slot']).save(
        args.output / 'ledge.png', optimize=True)
    deck(body['width'], body['ledgeFront'] - body['keysFront'] + .004, body['keysFront'] - .004,
         body['keysBack'], unit).save(args.output / 'deck.png', optimize=True)
    cart_label().save(args.output / 'cart-label.png', optimize=True)
    pad_face().save(args.output / 'pad.png', optimize=True)
    (args.output / 'layout.json').write_text(json.dumps(
        {'body': body, 'keys': keys, 'sideSwatches': swatches}, ensure_ascii=False, indent=1),
        encoding='utf-8')
    print(args.output, len(keys), 'keys')


if __name__ == '__main__':
    main()
