"""Contact sheets of the actual classified pack, not replacement product art."""
import argparse
import io
import json
from pathlib import Path
import zipfile
from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pack', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.pack.with_suffix('.report.json').read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.pack) as archive:
        games = json.loads(archive.read('packaging.json'))['games']
        for start in range(0, len(games), 8):
            sheet = Image.new('RGB', (1360, 8 * 240), '#181818')
            draw = ImageDraw.Draw(sheet)
            for index, game in enumerate(games[start:start + 8]):
                top = index * 240
                title = report[start + index]['title']
                draw.text((12, top + 4), f'{start + index + 1}. {title}', fill='white')
                for col, role in enumerate(['box-2D', 'box-2D-back', 'box-2D-side', 'manual-page']):
                    draw.text((col * 340 + 12, top + 22), role, fill='#aaaaaa')
                    item = next((m for m in game['resources'] if m['type'] == role), None)
                    if item:
                        image = Image.open(io.BytesIO(archive.read('images/' + item['importReference']['sha256'] + '.png'))).convert('RGB')
                        image.thumbnail((320, 190))
                        sheet.paste(image, (col * 340 + 12 + (320 - image.width) // 2, top + 43))
            target = args.output / f'resources-{start // 8 + 1}.jpg'
            sheet.save(target, quality=92)
            print(target)


if __name__ == '__main__':
    main()
