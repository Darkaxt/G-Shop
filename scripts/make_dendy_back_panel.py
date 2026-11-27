"""Draw the back panel texture of the 'dendy-yellow' cartridge shell.

Real Dendy cartridges carry moulded bulleted care text on the back panel with Steepler's
yellow warranty sticker pasted over it: a blue line-art elephant, the blue
"Dendy" wordmark, the Russian compatibility notice and Steepler's phone line.
The thin sticker paper lets the relief beneath show faintly. By default the
sticker is a flat redraw of the real layout (wordmark top left, notice below it,
elephant on the right). --sticker pastes a supplied sticker image instead, such
as a crop of a reference model's photographic texture; that output belongs with
the private model, not in this repository.

The panel spans PANEL_SIZE metres of the shell's back (see
build_nes_cartridge_models.py); the PNG keeps that aspect.

Usage: python -I make_dendy_back_panel.py OUT.png [--sticker STICKER.png]
"""
import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ASSETS = Path(__file__).resolve().parent / 'assets'
FONTS = Path('C:/Windows/Fonts')
PANEL_SIZE = (.088, .048)
# sRGB of the shell's linear base colour (.76, .30, .01) in the builder.
SHELL = (225, 149, 25)
YELLOW = (236, 236, 40)
BLUE = (24, 92, 176)
INK = (20, 20, 24)
CARE = ['•  Avoid exposing cartridge to extreme temperature',
        '•  Be careful not to immerse cartridge in water',
        '•  For protection, when cartridge is not in use, place',
        '    cartridge inside protective plastic case']
NOTICE = ['Торговая марка Dendy на игровом картридже,',
          'световом пистолете и других дополнениях',
          'гарантирует совместимость этих устройств',
          'с игровыми приставками Dendy.',
          '™Стиплер (Россия),                .Телефон (095) 921-2618']


def elephant_lineart(height):
    """The mascot from the Dendy logo, reduced to a blue outline like the sticker print."""
    with Image.open(ASSETS / 'dendy-logo.png') as logo:
        logo = logo.convert('RGBA')
    figure = logo.crop((0, 0, logo.width, round(logo.height * 0.70)))
    # The cartoon's own dark outlines plus its silhouette edge are the line art.
    lum = figure.convert('L')
    alpha = figure.getchannel('A').point(lambda v: 255 if v > 128 else 0)
    lines = ImageChops.multiply(lum.point(lambda v: 255 if v < 45 else 0), alpha)
    lines = ImageChops.lighter(lines, alpha.filter(ImageFilter.FIND_EDGES))
    size = (round(figure.width * height / figure.height), height)
    mask = lines.resize(size, Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(1.5))
    mask = mask.point(lambda v: 255 if v > 70 else 0)
    art = Image.new('RGBA', size, (*BLUE, 0))
    art.putalpha(mask)
    return art


def sticker(w, h):
    img = Image.new('RGB', (w, h), YELLOW)
    d = ImageDraw.Draw(img)
    art = elephant_lineart(round(h * 0.80))
    img.paste(art, (w - art.width - round(w * .025), round(h * 0.10)), art)
    word = ImageFont.truetype(str(FONTS / 'georgiab.ttf'), round(h * .30))
    d.text((w * .045, h * .035), 'Dendy', font=word, fill=BLUE)
    body = ImageFont.truetype(str(FONTS / 'arialbd.ttf'), round(h * .066))
    for i, line in enumerate(NOTICE):
        d.text((w * .045, h * (.46 + i * .095)), line, font=body, fill=INK)
    return img


def relief(size):
    """Moulded care text as a height map: 255 raised, 0 flat."""
    height = Image.new('L', size, 0)
    d = ImageDraw.Draw(height)
    w, h = size
    f = ImageFont.truetype(str(FONTS / 'arialbd.ttf'), round(h * .055))
    for i, line in enumerate(CARE):
        d.text((w * .07, h * (.08 + i * .075)), line, font=f, fill=255)
    return height.filter(ImageFilter.GaussianBlur(1.2))


def emboss(base, height, strength):
    """Light from the top left: raised edges brighten above-left and darken below-right."""
    shift = 3
    up = ImageChops.offset(height, -shift, -shift)
    down = ImageChops.offset(height, shift, shift)
    light = ImageChops.subtract(height, down)
    shade = ImageChops.subtract(height, up)
    white = Image.new('RGB', base.size, (255, 255, 255))
    black = Image.new('RGB', base.size, (0, 0, 0))
    base = Image.composite(white, base, light.point(lambda v: round(v * strength)))
    return Image.composite(black, base, shade.point(lambda v: round(v * strength)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--sticker', type=Path)
    args = parser.parse_args()
    w = 1600
    h = round(w * PANEL_SIZE[1] / PANEL_SIZE[0])
    height = relief((w, h))
    panel = emboss(Image.new('RGB', (w, h), SHELL), height, .30)
    # An 84 x 30 mm sticker over the lower care lines; the first lines stay visible.
    sw = round(w * .084 / PANEL_SIZE[0])
    sh = round(sw * 30 / 84)
    sx, sy = (w - sw) // 2, round(h * .27)
    if args.sticker:
        with Image.open(args.sticker) as supplied:
            paper = supplied.convert('RGB').resize((sw, sh), Image.Resampling.LANCZOS)
    else:
        # A photograph already shows the relief through the paper; a redraw adds it.
        paper = emboss(sticker(sw, sh), height.crop((sx, sy, sx + sw, sy + sh)), .05)
        ImageDraw.Draw(paper).rectangle((0, 0, sw - 1, sh - 1), outline=(200, 198, 30), width=2)
    panel.paste(paper, (sx, sy))
    panel.save(args.output, optimize=True)
    print(args.output, panel.size)


if __name__ == '__main__':
    main()
