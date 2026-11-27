"""Recolour the Dendy Junior albedo atlas into the black Subor SB-225.

The SB-225 is the same top-loader body in black plastic with Subor's own marking
("SUBOR SB-225 ... VIDEO GAME SYSTEM") where the Junior has its Dendy band.
Cream plastic becomes black with its variation inverted, so grime on the cream
reads as light scuffs on black and moulded/printed grey legends turn light.
Saturated colours (inserted cartridge, RCA jacks) are kept. Pass the 4096 px
base colour atlas of otztava's Dendy Junior; the output stays private with the
model, like its source.

Usage: python -I make_subor_sb225_texture.py JUNIOR_BASE.png OUT.png
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONTS = Path('C:/Windows/Fonts')
# The Dendy band in the 4096 px atlas, stored rotated: see marking().
BAND = (212, 445, 306, 1346)
GOLD = (214, 172, 74)
WHITE = (226, 224, 214)


def recolour(rgb):
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    light = np.clip(np.float32(.07) + (np.float32(.86) - lum) * np.float32(.8), .04, .6)
    dark = lum * np.float32(.6)                            # slots/recesses stay darkest
    grey = np.where(lum >= .5, light, dark)  # cream -> black, grime -> scuffs
    tint = np.array([1.0, 1.0, 1.04], dtype=np.float32)   # cold black, not brown
    out = grey[..., None] * tint
    # The cartridge's muted orange (red well above blue) is kept as well; cream is only ~.08 warm.
    keep = ((sat > .18) | (rgb[..., 0] - rgb[..., 2] > .2))[..., None]
    return np.where(keep, rgb, np.clip(out, 0, 1))


def marking(size):
    """The band as read on the console, then turned into the atlas orientation."""
    w, h = size[1], size[0]       # band is stored rotated by 90 degrees
    text = Image.new('RGB', (w, h), (16, 16, 18))
    d = ImageDraw.Draw(text)
    bold = ImageFont.truetype(str(FONTS / 'arialbd.ttf'), round(h * .44))
    serif = ImageFont.truetype(str(FONTS / 'timesbd.ttf'), round(h * .36))
    d.text((w * .03, h * .5), 'SUBOR  SB-225', font=bold, fill=GOLD, anchor='lm')
    d.text((w * .97, h * .5), 'VIDEO GAME SYSTEM', font=serif, fill=WHITE, anchor='rm')
    # The atlas holds the band flipped top to bottom and turned a quarter left.
    return text.transpose(Image.Transpose.FLIP_TOP_BOTTOM).rotate(90, expand=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    with Image.open(args.source) as src:
        if src.size != (4096, 4096):
            raise ValueError('Expected the 4096 px Dendy Junior base colour atlas')
        alpha = src.getchannel('A') if 'A' in src.getbands() else None
        rgb = np.asarray(src.convert('RGB'))
    out = np.empty_like(rgb)
    for y in range(0, rgb.shape[0], 512):      # bounded float32 working set
        part = rgb[y:y + 512].astype(np.float32) / 255
        out[y:y + 512] = (recolour(part) * 255 + .5).astype(np.uint8)
    img = Image.fromarray(out)
    x0, y0, x1, y1 = BAND
    img.paste(marking((x1 - x0, y1 - y0)), (x0, y0))
    if alpha is not None:
        img.putalpha(alpha)
    img.save(args.output, optimize=True)
    print(args.output, img.size)


if __name__ == '__main__':
    main()
