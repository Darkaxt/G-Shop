"""Prepare carton and cartridge-label packs from LaunchBox for uncovered NES/GBA editions.

Input rows come from the private gap ledger: archives the census still counts as
uncovered whose title has a unique LaunchBox match (canonical title or LaunchBox's
own declared alias; matching is never loosened here). The edition is the ledger's
store binding or, for unbound archives, the single member catalogue edition of the
Drive file (importing the pack creates the store binding).

Faces never mix printings: front, back and spine all come from the first LaunchBox
region that fits the archive's region and has a front. The cartridge label is cut
from a "Cart - Front" scan of a fitting region: the largest area that differs from
the plastic colour (sampled at the bottom of the cartridge). A cut whose size or
shape is implausible is skipped and reported, never guessed. Roles the store
already has for the edition are left alone. Fan translations get the original's
box with the translation sticker on the front (TRANSLATION-STICKER-01).

Inputs (desktop copies only):
  --ledger      gap-ledger JSON         --images  LaunchBox GameImage TSV
  --projection  projection copy         --store-db store metadata.sqlite copy
  --cache       image cache directory   --output  DIR/launchbox-<platform>.zip
Usage: python -I prepare_launchbox_pack.py --platform nes --ledger L --images I
       --projection P --store-db S --cache C --output O [--limit N] [--preview DIR]
"""
import argparse
import collections
import hashlib
import io
import json
from pathlib import Path
import re
import sqlite3
import sys
import time

import numpy as np
import requests
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_census as census_lib  # noqa: E402
from prepare_packaging_resources import (  # noqa: E402
    REGIONS, normalize_role_image, owner_key, write_packaging_batches)
from prepare_translation_pack import language, sticker  # noqa: E402

CDN = 'https://images.launchbox-app.com/'
FOLDERS = {'nes': 'Nintendo - Nintendo Entertainment System',
           'gba': 'Nintendo - Game Boy Advance'}
TRANSLATION_GROUPS = {'Translations', 'T-En'}
SKIP_VERDICTS = {'excluded-short-term', 'no-physical-release'}
FACES = {'Box - Front': 'box-2D', 'Box - Back': 'box-2D-back', 'Box - Spine': 'box-2D-side'}
LABEL = 'support-texture'
# LaunchBox region name -> provenance code (two or three lower-case letters).
CODES = {**{k: v for k, v in REGIONS.items() if v}, 'Taiwan': 'tw', 'Sweden': 'se',
         'Scandinavia': 'sca'}
EUROPE = ['Europe', 'United Kingdom', 'World']
# Archive region (No-Intro name) -> LaunchBox regions of the same printing, in order.
FITS = {
    'USA': ['North America', 'United States', 'Canada', 'World'],
    'Canada': ['Canada', 'North America', 'United States'],
    'World': ['World', 'North America', 'United States', 'Europe'],
    'Europe': EUROPE, 'United Kingdom': ['United Kingdom', 'Europe'],
    'Germany': ['Germany', 'Europe'], 'France': ['France', 'Europe'],
    'Spain': ['Spain', 'Europe'], 'Italy': ['Italy', 'Europe'],
    'Netherlands': ['The Netherlands', 'Netherlands', 'Europe'],
    'Sweden': ['Sweden', 'Scandinavia', 'Europe'], 'Scandinavia': ['Scandinavia', 'Europe'],
    'Australia': ['Australia', 'Europe'], 'Japan': ['Japan'],
    'Asia': ['Asia', 'China', 'Taiwan', 'Hong Kong'],  # one pirate market
    'Taiwan': ['Taiwan', 'Asia'], 'China': ['China', 'Asia'], 'Hong Kong': ['Hong Kong', 'Asia'],
    'Korea': ['Korea'], 'Russia': ['Russia'], 'Brazil': ['Brazil'],
}


def fitting_regions(archive):
    """Regions of the first parenthesised group naming a known region."""
    for group in re.findall(r'\(([^()]+)\)', archive):
        names = [part.strip() for part in group.split(',')]
        if names[0] in FITS:
            out = []
            for name in names:
                out += [r for r in FITS.get(name, []) if r not in out]
            return [r for r in out if r in CODES]
    return []


def disk_label_crop(body):
    """Disk System "Cart - Front" scans are close-ups of the disk: the label
    sticker above the embossed NINTENDO plastic, or the bare label. Plastic is
    the bottom band when that band is one colour; with no plastic band the whole
    image is the label. Raise ValueError when neither reading is plausible."""
    with Image.open(io.BytesIO(body)) as image:
        image = image.convert('RGB')
    rgb = np.asarray(image).astype(np.int16)
    height, width = rgb.shape[:2]
    depth = max(2, height // 10)
    band = rgb[height - depth:].reshape(-1, 3)
    plastic = np.median(band, axis=0)
    # Embossing shades the plastic, so "near" is generous; most of the band
    # must still be that one colour for it to count as plastic.
    if (np.abs(band - plastic).max(axis=1) < 90).mean() > .55:
        differs = np.abs(rgb - plastic).max(axis=2) >= 90

        def run(values, threshold):
            best, start = (0, 0), None
            for i, v in enumerate(list(values) + [0]):
                if v > threshold and start is None:
                    start = i
                elif v <= threshold and start is not None:
                    best = max(best, (i - start, start), key=lambda b: b[0])
                    start = None
            return best[1], best[1] + best[0]

        y0, y1 = run(differs[:height - depth].mean(axis=1), .45)
        if y1 - y0 < 2:
            raise ValueError('disk label not found')
        x0, x1 = run(differs[y0:y1].mean(axis=0), .45)
        if differs[y0:y1, x0:x1].mean() < .55:
            raise ValueError('disk label cut is mostly plastic-coloured')
        if y0 < .2 * height:
            # The label's header strip is printed in the disk colour; close-ups
            # start at the label's top edge.
            y0 = 0
    else:
        x0, y0, x1, y1 = 0, 0, width, height
    w, h = x1 - x0, y1 - y0
    if w * h < .2 * width * height or not 1.15 <= w / max(h, 1) <= 4:
        raise ValueError(f'implausible disk label {w}x{h} on {width}x{height}')
    out = io.BytesIO()
    image.crop((x0, y0, x1, y1)).save(out, format='PNG')
    return [x0, y0, w, h], out.getvalue()


def label_crop(body):
    """Return (rect, png) of the label on a cartridge scan, or raise ValueError."""
    with Image.open(io.BytesIO(body)) as image:
        image = image.convert('RGBA')
    pixels = np.asarray(image).astype(np.int16)
    alpha = pixels[..., 3] > 200
    if alpha.all():
        # Opaque scan on a plain backdrop: the backdrop is the corner colour.
        k = max(2, min(alpha.shape) // 40)
        corners = np.concatenate([pixels[:k, :k, :3].reshape(-1, 3), pixels[:k, -k:, :3].reshape(-1, 3),
                                  pixels[-k:, :k, :3].reshape(-1, 3), pixels[-k:, -k:, :3].reshape(-1, 3)])
        if corners.std(axis=0).max() > 20:
            raise ValueError('no plain backdrop')
        alpha = np.abs(pixels[..., :3] - np.median(corners, axis=0)).max(axis=2) > 32
    if alpha.mean() < .2:
        raise ValueError('cartridge not found')
    ys, xs = np.nonzero(alpha)
    top, bottom, left, right = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgb = pixels[..., :3]
    band = alpha.copy()
    band[:bottom - max(2, (bottom - top) // 8)] = False
    plastic = np.median(rgb[band], axis=0)
    distance = np.abs(rgb - plastic).max(axis=2)
    # Textured or translucent plastic varies a lot: the threshold follows the
    # spread measured on the plastic itself.
    threshold = max(48, np.percentile(distance[band], 90) + 16)
    differs = (distance > threshold) & alpha

    def longest_run(values, threshold):
        best, start = (0, 0), None
        for i, v in enumerate(list(np.nan_to_num(values)) + [0]):
            if v > threshold and start is None:
                start = i
            elif v <= threshold and start is not None:
                best = max(best, (i - start, start), key=lambda b: b[0])
                start = None
        return best[1], best[1] + best[0]

    x0, x1 = longest_run(differs[top:bottom].mean(axis=0), .3)
    if x1 - x0 < 2:
        raise ValueError('no label found')
    y0, y1 = longest_run(differs[:, x0:x1].mean(axis=1), .6)
    w, h = x1 - x0, y1 - y0
    cart = (right - left) * (bottom - top)
    if w * h < .12 * cart or w * h > .8 * cart or not .45 <= w / max(h, 1) <= 2.4:
        raise ValueError(f'implausible label cut {w}x{h} on {right - left}x{bottom - top}')
    margin = .03 * (right - left)
    if x0 - left < margin or right - x1 < margin:
        raise ValueError(f'label cut reaches the cartridge sides ({w}x{h})')
    if differs[y0:y1, x0:x1].mean() < .75:
        raise ValueError(f'label cut is mostly plastic-coloured ({w}x{h})')
    inset = round(min(w, h) * .01)
    rect = (x0 + inset, y0 + inset, x1 - inset, y1 - inset)
    out = io.BytesIO()
    image.crop(rect).convert('RGB').save(out, format='PNG')
    return [rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]], out.getvalue()


def cut_label(body, disk):
    """Disk close-ups (opaque) read as disks first; anything else as a cartridge."""
    if disk:
        with Image.open(io.BytesIO(body)) as image:
            opaque = image.convert('RGBA').getchannel('A').getextrema()[0] > 200
        if opaque:
            try:
                return disk_label_crop(body)
            except ValueError:
                pass
    return label_crop(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=sorted(FOLDERS), required=True)
    for name in ('ledger', 'images', 'projection', 'store_db', 'cache', 'output'):
        parser.add_argument('--' + name.replace('_', '-'), dest=name, type=Path, required=True)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--store', type=Path, default=Path('D:/RShopPrivate/CatalogueStore'),
                        help='store root holding the artwork bodies')
    parser.add_argument('--preview', type=Path, help='also write label cuts here for review')
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f'{args.output} exists')
    folder = FOLDERS[args.platform] + '/'

    images = collections.defaultdict(lambda: collections.defaultdict(list))
    for line in args.images.read_text(encoding='utf-8').splitlines():
        game, kind, region, filename, _ = line.split('\t')
        images[game][(kind, region)].append(filename)

    projection = sqlite3.connect(f'file:{args.projection.as_posix()}?mode=ro', uri=True)
    file_ids = {p.replace(chr(92), '/'): f for f, p in projection.execute(
        'SELECT file_id, display_path FROM drive_catalogue_entries WHERE is_folder=0 '
        'AND display_path LIKE ?', (folder + '%',))}
    catalogue = collections.defaultdict(list)
    for edition, key in projection.execute('SELECT edition_id, catalogue_key FROM '
            'library_query_editions WHERE platform_id=? AND member=1', (args.platform,)):
        if key:
            catalogue[json.loads(key)[-1]].append(edition)
    # Roles the edition can show (a local body, as the census counts them); a
    # recorded face whose image was never fetched or does not fit is not present.
    _, usable, _ = census_lib.store_roles(args.store, args.store_db)
    have = {edition: {role.split(':')[-1] for role in roles} for edition, roles in usable.items()}

    session = requests.Session()
    session.headers['User-Agent'] = 'G-Shop catalogue preparation'
    args.cache.mkdir(parents=True, exist_ok=True)
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)

    def fetch(filename):
        cached = args.cache / filename
        if not cached.exists():
            response = session.get(CDN + filename, timeout=60)
            response.raise_for_status()
            if len(response.content) > 32 * 1024 * 1024:
                raise ValueError('image too large')
            cached.write_bytes(response.content)
            time.sleep(.2)
        return cached.read_bytes()

    report = collections.Counter()
    games, bodies, seen = [], {}, set()
    for row in json.load(open(args.ledger, encoding='utf-8'))['rows']:
        lb = row.get('launchbox') or {}
        if (row['system'] != args.platform or row['verdict'] in SKIP_VERDICTS
                or lb.get('status') != 'unique' or len(lb['ids']) != 1
                or (row.get('carton') and row.get('label'))):
            continue
        if args.limit and report['selected'] >= args.limit:
            break
        archive = row['archive'].replace(chr(92), '/')
        edition_id = row.get('editionId')
        if not edition_id:
            editions = catalogue.get(file_ids.get(folder + archive), [])
            edition_id = editions[0] if len(editions) == 1 else None
        if not edition_id or edition_id in seen:
            report['noEdition' if not edition_id else 'duplicate'] += 1
            continue
        found = projection.execute('''SELECT g.record_json, e.record_json FROM library_editions e
            JOIN library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
            (edition_id,)).fetchone()
        if found is None:
            report['noEdition'] += 1
            continue
        game, edition = (json.loads(v) for v in found)
        if game.get('platformId') != args.platform:
            report['noEdition'] += 1
            continue
        lb_game = lb['ids'][0]
        offered = images.get(lb_game, {})
        fits = fitting_regions(archive)
        translated = archive.split('/')[0] in TRANSLATION_GROUPS
        present = have.get(edition_id, set())
        resources = []

        def add(role, filename, region, body, panel=None, original=None):
            data, rotation = normalize_role_image(role, body)
            digest = hashlib.sha256(data).hexdigest()
            bodies[digest] = data
            reference = {'sourceId': 'launchbox', 'assetId': f'{lb_game}/{filename}',
                         'sourceUrl': CDN + filename,
                         'sourceSha256': hashlib.sha256(original or body).hexdigest(),
                         'sha256': digest, 'sourceRegion': CODES[region]}
            if panel:
                reference['panel'] = panel
            if rotation:
                reference['rotationDegrees'] = rotation
            if role == 'box-2D' and translated:
                reference['overlay'] = 'translationSticker'
            resources.append({'type': role, 'importReference': reference})

        box_region = next((r for r in fits if offered.get(('Box - Front', r))), None)
        if box_region and not {'box-2D', 'box-2D-back'} <= present:
            for kind, role in FACES.items():
                names = offered.get((kind, box_region))
                if names and role not in present:
                    body = fetch(names[0])
                    try:
                        if role == 'box-2D' and translated:
                            with Image.open(io.BytesIO(body)) as front:
                                add(role, names[0], box_region,
                                    sticker(front, language(archive)), original=body)
                        else:
                            add(role, names[0], box_region, body)
                    except (OSError, ValueError, Image.DecompressionBombError) as error:
                        report['faceUnreadable'] += 1
                        print('face unreadable', archive, kind, error, file=sys.stderr)
        elif not box_region:
            report['noFittingBox'] += 1
        if LABEL not in present:
            cart_region = next((r for r in fits if offered.get(('Cart - Front', r))), None)
            if cart_region:
                name = offered[('Cart - Front', cart_region)][0]
                raw = fetch(name)
                try:
                    disk = args.platform == 'nes' and archive.startswith('Disk System/')
                    rect, cut = cut_label(raw, disk)
                    add(LABEL, name, cart_region, cut, panel=rect, original=raw)
                    report['labelCut'] += 1
                    if args.preview:
                        (args.preview / f'{lb_game}-{cart_region}.png').write_bytes(cut)
                except (ValueError, OSError, Image.DecompressionBombError) as error:
                    report['labelRejected'] += 1
                    print('label rejected', archive, error, file=sys.stderr)
            else:
                report['noFittingCart'] += 1
        if not resources:
            report['nothingToAdd'] += 1
            continue
        seen.add(edition_id)
        games.append({'editionId': edition_id, 'gameId': game['id'],
                      'identityKey': owner_key(game, edition), 'resources': resources})
        report['selected'] += 1
        report['withCarton'] += any(r['type'] == 'box-2D-back' for r in resources) or \
            ('box-2D-back' in present and any(r['type'] == 'box-2D' for r in resources))
    if not games:
        raise SystemExit(json.dumps(report))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    packs = write_packaging_batches(args.output, {'version': 1, 'platform': args.platform,
                                                  'games': games}, bodies)
    print(json.dumps({**report, 'packs': packs}))


if __name__ == '__main__':
    main()
