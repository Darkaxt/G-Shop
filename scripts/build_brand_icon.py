"""Render the authored G-Shop vector geometry; no source bitmap is edited."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


def build(root: Path) -> None:
    scale = 4
    size = 1024 * scale
    background = Image.new('RGB', (size, size), '#15171a')
    ink = Image.new('RGBA', background.size)
    draw = ImageDraw.Draw(ink)
    def box(values):
        return tuple(round(value * scale) for value in values)
    draw.rounded_rectangle(box((136, 136, 888, 888)), radius=174*scale,
                           outline='#f4444c', width=14*scale)
    draw.arc(box((253, 253, 771, 771)), 45, 315,
             fill='#ff565c', width=38*scale)
    points = [(681.706, 681.706), (752, 512), (542, 512)]
    draw.line([box(point) for point in points], fill='#ff565c',
              width=38*scale, joint='curve')
    for x, y in [(681.706, 342.294), *points]:
        draw.ellipse(box((x-19, y-19, x+19, y+19)), fill='#ff565c')
    background = Image.alpha_composite(background.convert('RGBA'),
                                      ink.filter(ImageFilter.GaussianBlur(26*scale)))
    background = Image.alpha_composite(background, ink)
    background.convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS).save(root / 'assets/icon.png')
    (root / 'assets/icon.svg').write_text('''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#15171a"/>
  <rect x="136" y="136" width="752" height="752" rx="174" fill="none" stroke="#f4444c" stroke-width="14"/>
  <path d="M681.706 342.294 A240 240 0 1 0 681.706 681.706 L752 512 H542" fill="none" stroke="#ff565c" stroke-width="38" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''', encoding='utf-8')


if __name__ == '__main__':
    build(Path(__file__).resolve().parents[1])
