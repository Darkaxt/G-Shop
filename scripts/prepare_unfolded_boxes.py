"""Classify the selected console's existing unfolded scans without game branches.

Existing validated cover art supplies the expected face proportions.
Paired scan fold geometry locates the sections; review output before import.
Requires OpenCV, Pillow and Windows English OCR for language evidence.
"""
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import zipfile

import cv2
import numpy as np
from PIL import Image

from prepare_packaging_resources import normalized, ranked_selection, language_priority

FOLDERS = {'gba': 'Game Boy Advance', 'gb': 'Game Boy', 'gbc': 'Game Boy Color',
    'nes': 'NES - Famicom', 'snes': 'SuperNES - SuperFamicom', 'n64': 'Nintendo64',
    'virtualboy': 'Virtual Boy', 'gameandwatch': 'Game And Watch'}


def language_evidence(text):
    words = re.findall(r'[a-z]+', text.lower())
    markers = {
        'en': {'the', 'with', 'this', 'your', 'you', 'from', 'and', 'that', 'into', 'new', 'for'},
        'fr': {'les', 'des', 'pour', 'avec', 'une', 'vous', 'est', 'dans', 'sur', 'jeu'},
        'de': {'die', 'und', 'nicht', 'ein', 'das', 'mit', 'auf', 'dem', 'der', 'sie'},
        'es': {'los', 'las', 'para', 'con', 'una', 'juego', 'del', 'por', 'una'},
        'nl': {'het', 'van', 'een', 'met', 'deze', 'zijn', 'voor', 'worden'},
        'it': {'gli', 'che', 'una', 'per', 'della', 'dei', 'nel', 'suo', 'sono'},
    }
    counts = {language: len(set(words) & values) for language, values in markers.items()}
    return [language for language, count in counts.items() if count >= (5 if language == 'en' else 3)], counts


def locate_fold_panel(image, aspect, *, joined=False):
    """Locate the body's actual cut edge, not an inset logo/artwork match.

    Two-half print layouts have a narrow flap above a broad front/back body.
    The largest foreground width transition identifies that fold. A different
    layout is rejected for reviewed classification rather than stretched to fit.
    """
    pixels = np.array(image.convert('RGB'))
    mask = cv2.inRange(pixels, (0, 0, 0), (244, 244, 244))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    filled = np.zeros(mask.shape, np.uint8)
    cv2.drawContours(filled, [max(contours, key=cv2.contourArea)], -1, 255, -1)
    widths = (filled > 0).sum(axis=1)
    changes = np.diff(widths)
    for offset in np.argsort(changes)[::-1]:
        if changes[offset] < image.width * .2:
            break
        y = int(offset) + 1
        added = np.flatnonzero((filled[y] > 0) & (filled[y - 1] == 0))
        if not len(added):
            continue
        # A white logo touching the fold interrupts dark pixels, not the panel.
        # Use the complete cut-edge span; taking its longest dark run crops art.
        x, w = int(added.min()), int(added.max() - added.min() + 1)
        if joined:
            bands = Counter()
            # Artwork may bleed into the fold's top boundary. Use the stable
            # narrow-flap / wide-back alignment above it, not one noisy row.
            for previous in range(y):
                before = np.flatnonzero(filled[previous] > 0)
                spans = np.split(before, np.flatnonzero(np.diff(before) > 1) + 1)
                spans = [r for r in spans if len(r) > image.width * .03]
                if len(spans) == 2 and len(spans[0]) < len(spans[1]) * .4:
                    bands[(int(spans[0][-1]) + 1, int(spans[1][0]))] += 1
            if not bands:
                continue
            (x, end), _ = bands.most_common(1)[0]
            w = end - x
        h = round(w / aspect)
        if joined:
            column_widths = (filled[y:, x:x+w] > 0).sum(axis=1)
            drops = np.diff(column_widths)
            candidates = [int(i) + 1 for i in np.argsort(drops)
                if i > w * .4 and drops[i] < -w * .7]
            if candidates:
                h = candidates[0]
        if (w < image.width * (.25 if joined else .5) or not .06 * image.width < x < .3 * image.width
                or y < x or y + h > image.height or h < image.height * .3):
            continue
        coverage = float((filled[y:y+h, x:x+w] > 0).mean())
        if coverage < .96:
            continue
        return [x, y, w, h], {'method': 'paired-fold-body-boundary', 'bodyCoverage': round(coverage, 4)}
    return None


def trim_closure(file, rect):
    """Discard white cutout margins, retaining the continuous printed flap band."""
    x, y, w, h = rect
    with Image.open(file) as image:
        pixels = np.array(image.crop((x, y, x + w, y + h)).convert('RGB'))
    mask = cv2.inRange(pixels, (0, 0, 0), (244, 244, 244))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return rect
    filled = np.zeros(mask.shape, np.uint8)
    cv2.drawContours(filled, [max(contours, key=cv2.contourArea)], -1, 255, -1)
    # Fill internal white print (text/barcodes), not just dark pixel rows.
    rows = np.flatnonzero((filled > 0).mean(axis=1) >= .95)
    if not len(rows) or rows[-1] - rows[0] + 1 < h * .2:
        return rect
    return [x, y + int(rows[0]), w, int(rows[-1] - rows[0] + 1)]


def closure_has_print(file, rect):
    x, y, w, h = rect
    with Image.open(file) as image:
        if x < 0 or y < 0 or x + w > image.width or y + h > image.height:
            return False
        pixels = np.array(image.crop((x, y, x + w, y + h)).convert('RGB'))
    return float((np.min(pixels, axis=2) < 244).mean()) > .03


def classify(args):
    rows = ranked_selection(args.projection, args.system)
    bound = {r['game']['id']: r for r in rows}
    root = args.dump / FOLDERS[args.system]
    folders = {}
    for folder in root.iterdir():
        if folder.is_dir():
            folders.setdefault(normalized(folder.name), []).append(folder)
    layouts, report = [], []
    with zipfile.ZipFile(args.pack) as archive:
        manifest = json.loads(archive.read('packaging.json'))
        if manifest['platform'] != args.system:
            raise ValueError('Projection and source pack console differ')
        for game in manifest['games']:
            row = bound.get(game['gameId'])
            if row is None or row['edition']['id'] != game['editionId']:
                raise ValueError('Collection no longer matches source pack')
            aliases = {normalized(t) for t in [row['title'], *[t['text'] for t in row['metadata']['titles']]]}
            matched = {p for name in aliases for p in folders.get(name, [])}
            candidates = []
            template = next((r for r in game['resources'] if r['type'] == 'box-2D'), None)
            if template is None:
                continue
            front_art = Image.open(io.BytesIO(archive.read('images/' + template['importReference']['sha256'] + '.png')))
            for folder in matched:
                for front in sorted(folder.rglob('*')):
                    if 'Box(Front)' not in front.name or front.suffix.lower() not in {'.png', '.jpg', '.jpeg'}:
                        continue
                    back = front.with_name(front.name.replace('Box(Front)', 'Box(Back)'))
                    if not back.is_file():
                        # Face scans may have different scan/restoration dates;
                        # their common edition folder, not that date, binds them.
                        backs = sorted(p for p in front.parent.iterdir()
                            if 'Box(Back)' in p.name and p.suffix.lower() in {'.png', '.jpg', '.jpeg'})
                        if not backs:
                            continue
                        back = backs[-1]
                    with Image.open(front) as image:
                        located = locate_fold_panel(image, front_art.width / front_art.height)
                        size = image.size
                    if located is None:
                        continue
                    rect, confidence = located
                    raw_text = subprocess.check_output(['powershell.exe', '-NoProfile', '-File',
                        str(Path(__file__).with_name('read_packaging_text.ps1')),
                        '-ImagePath', str(back)], encoding='utf-8')
                    languages, counts = language_evidence(json.loads(raw_text)['text'])
                    candidates.append((language_priority(languages), str(front),
                        front, back, rect, confidence, size, languages, counts))
            if not candidates:
                report.append({'gameId': game['gameId'], 'status': 'no-compatible-folded-scan'})
                print(json.dumps({'rank': row['rank'], 'classified': False}), flush=True)
                continue
            _, _, front, back, rect, confidence, size, languages, counts = min(candidates)
            x, y, w, h = rect
            with Image.open(back) as image:
                if image.width != size[0] or rect[1] + rect[3] > image.height:
                    report.append({'gameId': game['gameId'], 'status': 'paired-layout-dimensions-differ'})
                    continue
            # The left strip on the paired sheets is the two opposite narrow
            # faces. Closure flaps above/back and below/front are distinct faces.
            depth = min(x, round(h * .25))
            if depth < h * .07 or y < depth or y + h + depth > size[1]:
                report.append({'gameId': game['gameId'], 'status': 'fold-layout-needs-review'})
                continue
            region = 'us' if '_AME' in front.name else 'jp' if '_ASI' in front.name else 'eu'
            target = row['edition']['regions'][0]
            definitions = {
                'front': (front, rect, 0, w / h),
                'back': (back, rect, 0, w / h),
                'left': (front, [x - depth, y, depth, h], 0, depth / h),
                'right': (back, [x - depth, y, depth, h], 0, depth / h),
                'top': (back, [x, y - depth, w, depth], 180, w / depth),
                'bottom': (front, [x, y + h, w, depth], 0, w / depth),
            }
            panels = {}
            for role, (file, crop, rotation, aspect) in definitions.items():
                if role in {'top', 'bottom'}:
                    if not closure_has_print(file, crop):
                        other = front if file == back else back
                        if closure_has_print(other, crop):
                            file = other
                        else:
                            continue  # Honest missing face; viewer's fallback remains available.
                    crop = trim_closure(file, crop)
                panels[role] = {'file': str(file.resolve()),
                    'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
                    'rect': crop, 'rotationDegrees': rotation, 'aspect': aspect,
                    'sourceUrl': 'https://archive.org/details/nintandbox-2026'}
            layouts.append({'platform': args.system, 'gameId': game['gameId'],
                'targetRegions': [target], 'sourceRegion': region, 'languages': languages,
                'reconstruction': 'regionalPackaging', 'panels': panels,
                'classificationEvidence': {
                    **confidence, 'ocr': 'Windows.Media.Ocr/en-US', 'languageMarkers': counts}})
            report.append({'gameId': game['gameId'], 'status': 'classified',
                'languages': languages, 'confidence': confidence})
            print(json.dumps({'rank': row['rank'], 'classified': True, 'languages': languages}), flush=True)
    args.output.write_text(json.dumps({'version': 1, 'layouts': layouts}, indent=2))
    args.output.with_suffix('.report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'classifiedGames': len(layouts), 'examined': len(manifest['games'])}), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--system', choices=FOLDERS, required=True)
    parser.add_argument('--pack', type=Path, required=True)
    parser.add_argument('--projection', type=Path, required=True)
    parser.add_argument('--dump', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Preserve the existing classified index; use a new generation')
    classify(args)


if __name__ == '__main__':
    main()
