"""Worn-plastic albedo for the 'dendy-yellow' shell (private models only).

The wear comes from the cartridge textures of "Dendy Junior" by otztava
(Sketchfab c05cb0fb636c4384a854e171b5f66e10, CC BY 4.0). Those textures are
photo-derived, so the output belongs in the private model store, never in the
repository or the APK.

Only the wear is taken, not the colour: on a clean flat panel of each source
atlas, every channel is divided by its own heavy blur (the local mean). That
leaves the scratches, scuffs and grime as a per-channel ratio around 1, which
is multiplied into the shell's own yellow. The front face uses one source
cartridge and the back face the other, at the source's scale (no stretching).

Usage: python -I make_dendy_shell_wear.py SRC_DIR OUT_DIR
SRC_DIR holds K_2.png and K_3.png, the base-colour images of the model's
cartridge materials K_2 and K_3 (1024 px atlases). Writes
dendy-shell-wear-front.png and dendy-shell-wear-back.png.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SHELL_LINEAR = np.array((.76, .30, .01))  # build_nes_cartridge_models.py dendy-yellow
SHELL_MM = (106, 68)                       # the projected front/back rectangle
# Clean lower panel of each atlas (no label, sticker or moulded text), with a
# margin so the blur never sees the panel border. The source face is ~340 px
# across a ~106 mm cartridge, about 3.2 px/mm, so a 320 x 205 px crop is the
# shell's 106 x 68 mm at the source scale.
PANEL = (395, 610, 725, 1000)
CROP = (400, 700, 720, 905)
BLUR_PX = 24
OUT_PX_PER_MM = 8


def to_linear(c):
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= .0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - .055)


def blur(image, sigma):
    """Separable Gaussian with edge padding, per channel."""
    r = int(3 * sigma)
    k = np.exp(-.5 * (np.arange(-r, r + 1) / sigma) ** 2); k /= k.sum()
    pad = np.pad(image, ((r, r), (r, r), (0, 0)), mode='edge')
    rows = sum(k[i] * pad[:, i:i + image.shape[1]] for i in range(2 * r + 1))
    return sum(k[i] * rows[i:i + image.shape[0]] for i in range(2 * r + 1))


def wear(atlas_path):
    panel = Image.open(atlas_path).convert('RGB').crop(PANEL)
    lin = to_linear(np.asarray(panel, dtype=np.float64) / 255)
    mean = blur(lin, BLUR_PX)
    ratio = np.clip(lin / np.maximum(mean, 1e-4), .45, 1.3)
    x0, y0 = CROP[0] - PANEL[0], CROP[1] - PANEL[1]
    ratio = ratio[y0:y0 + CROP[3] - CROP[1], x0:x0 + CROP[2] - CROP[0]]
    albedo = to_srgb(SHELL_LINEAR * ratio)
    image = Image.fromarray((albedo * 255 + .5).astype(np.uint8), 'RGB')
    return image.resize((SHELL_MM[0] * OUT_PX_PER_MM, SHELL_MM[1] * OUT_PX_PER_MM), Image.LANCZOS)


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for face, name in (('front', 'K_2.png'), ('back', 'K_3.png')):
        image = wear(src / name)
        image.save(out / f'dendy-shell-wear-{face}.png', optimize=True)
        print('WEAR', face, image.size)


if __name__ == '__main__':
    main()
