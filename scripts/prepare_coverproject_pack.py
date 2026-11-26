"""Prepare NES carton packs from The Cover Project wraps (fan-made covers).

The owner prefers a fan reconstruction to an empty game (2026-11-26), with its
provenance kept distinct: every resource is `sourceId: thecoverproject` and
`reconstruction: fanCover`, and an original scan always wins where one exists
(only gap editions without a carton are selected).

Inputs come from the desktop, never from the device:
  --projection  a read-only COPY of the catalogue projection (never the live file)
  --matches     tcp-match JSON: gap rows with exact normalized-title hits
  --covers      TSV: game_id, cover_id, kind, format, country, image URL
A Universal Game Case wrap is back | spine | front; a Disk System sleeve gives its
upright front only. Panels are cropped at the
template's proportions; anything else is skipped and reported, not guessed.
Region is never mixed: USA/World editions take NTSC covers, Europe-family PAL,
Japan NTSC-J. Retail-labelled covers win over Custom ones.

Usage: python -I prepare_coverproject_pack.py --projection P --matches M
       --covers C --cache DIR --output DIR/coverproject-nes.zip
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import sqlite3
import sys
import time

import requests
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_packaging_resources import (  # noqa: E402
    normalize_role_image, owner_key, write_packaging_batches)

FOLDER = 'Nintendo - Nintendo Entertainment System'
CDN = 'https://coverproject.sfo2.cdn.digitaloceanspaces.com/'
# Universal Game Case template, 3366 x 2100: back 0-1537, spine 1537-1829,
# front 1829-3366 (measured on the Abadox US wrap; checked by aspect below).
TEMPLATE = (3366, 2100)
PANELS = {'box-2D-back': (0, 1537), 'box-2D-side': (1537, 1829),
          'box-2D': (1829, 3366)}
FDS_FOLD = 0.45
PAL = {'Europe', 'Germany', 'France', 'Spain', 'Italy', 'Sweden', 'Australia',
       'United Kingdom', 'Netherlands', 'Scandinavia'}
WANT = {'USA': {'NTSC'}, 'World': {'NTSC'}, 'Canada': {'NTSC'},
        'Japan': {'NTSC-J'}, **{r: {'PAL'} for r in PAL}}


def edition_region(archive):
    for group in re.findall(r'\(([^()]+)\)', archive):
        first = group.split(',')[0].strip()
        if first in WANT:
            return first
    return None


def choose(covers, region, disk_system):
    """Labels are cartridge stickers, not wraps; a Disk System edition takes
    only Disk System wraps (a Famicom cart wrap is a different product)."""
    formats = WANT.get(region)
    if not formats:
        return None
    prefix = CDN + 'famicom_disk_system/'
    usable = [c for c in covers if c['format'] in formats and c['kind'] != 'Label'
              and c['url'].startswith(prefix) == disk_system]
    usable.sort(key=lambda c: (c['kind'] != 'Retail', c['cover_id']))
    return usable[0] if usable else None


def wrap_panels(body):
    with Image.open(io.BytesIO(body)) as image:
        width, height = image.size
        image = image.convert('RGB')
        if 0.54 <= width / height <= 0.57:
            # Disk System sleeve (~945x1700): upright front below the fold at
            # 45% of the height, the back flap above it printed upside down.
            # Only the front is taken (measured on Metroid, Zanac, Eggerland).
            rects = {'box-2D': (0, round(height * FDS_FOLD), width, height)}
        elif 1.58 <= width / height <= 1.68:
            # Variants with other bleed (3338, 3431 and 3470 wide) keep the same
            # proportions to within ~10 px, so panels scale with the width.
            scale = width / TEMPLATE[0]
            rects = {role: (round(left * scale), 0, round(right * scale), height)
                     for role, (left, right) in PANELS.items()}
        else:
            raise ValueError(f'unknown wrap template ({width}x{height})')
        for role, (x, y, right, bottom) in rects.items():
            w, h = right - x, bottom - y
            panel = image.crop((x, y, right, bottom))
            out = io.BytesIO()
            panel.save(out, format='PNG')
            yield role, [x, y, w, h], out.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('projection', 'matches', 'covers', 'cache', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f'{args.output} exists')
    covers = {}
    for line in args.covers.read_text(encoding='utf-8').splitlines():
        game_id, cover_id, kind, fmt, country, url = line.split('\t')
        if not url.startswith(CDN):
            continue
        covers.setdefault(int(game_id), []).append({'cover_id': int(cover_id),
            'kind': kind, 'format': fmt, 'country': country, 'url': url})
    db = sqlite3.connect(f'file:{args.projection.as_posix()}?mode=ro', uri=True)
    # Ledger rows without a store binding still have a catalogue edition: the
    # Drive file id is the last element of its catalogue key. Importing a pack
    # creates the store binding.
    file_ids = {p.replace(chr(92), '/'): f for f, p in db.execute(
        'SELECT file_id, display_path FROM drive_catalogue_entries WHERE is_folder=0 '
        'AND display_path LIKE ?', (FOLDER + '/%',))}
    catalogue = {}
    for edition_id, key in db.execute("SELECT edition_id, catalogue_key FROM "
            "library_query_editions WHERE platform_id='nes' AND member=1"):
        if key:
            catalogue.setdefault(json.loads(key)[-1], []).append(edition_id)

    def resolve(row):
        if row.get('editionId'):
            return row['editionId']
        path = FOLDER + '/' + row['archive'].replace(chr(92), '/')
        editions = catalogue.get(file_ids.get(path), [])
        return editions[0] if len(editions) == 1 else None

    session = requests.Session()
    session.headers['User-Agent'] = 'G-Shop catalogue preparation'
    args.cache.mkdir(parents=True, exist_ok=True)
    games, bodies, report = [], {}, {'selected': 0, 'noRegionCover': 0,
        'noEdition': 0, 'badTemplate': 0, 'multiTitle': 0}
    seen = set()
    for row in json.loads(args.matches.read_text(encoding='utf-8')):
        edition_id = resolve(row)
        if not edition_id:
            report['noEdition'] += 1
            continue
        if edition_id in seen:
            continue
        hits = row['tcp']
        if len(hits) != 1:
            report['multiTitle'] += 1
            continue
        region = edition_region(row['archive'])
        disk_system = row['archive'].replace(chr(92), '/').startswith('Disk System/')
        cover = choose(covers.get(hits[0][1], []), region, disk_system)
        if cover is None:
            report['noRegionCover'] += 1
            continue
        found = db.execute('''SELECT g.record_json, e.record_json FROM library_editions e
            JOIN library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
            (edition_id,)).fetchone()
        if found is None:
            report['noEdition'] += 1
            continue
        game, edition = (json.loads(v) for v in found)
        if game.get('platformId') != 'nes':
            report['noEdition'] += 1
            continue
        cached = args.cache / f"{cover['cover_id']}.jpg"
        if not cached.exists():
            response = session.get(cover['url'], timeout=60)
            response.raise_for_status()
            if len(response.content) > 32 * 1024 * 1024:
                raise ValueError('wrap too large')
            cached.write_bytes(response.content)
            time.sleep(0.5)
        raw = cached.read_bytes()
        source_digest = hashlib.sha256(raw).hexdigest()
        try:
            panels = list(wrap_panels(raw))
        except ValueError:
            report['badTemplate'] += 1
            continue
        resources = []
        for role, rect, body in panels:
            data, rotation = normalize_role_image(role, body)
            digest = hashlib.sha256(data).hexdigest()
            bodies[digest] = data
            reference = {'sourceId': 'thecoverproject',
                'assetId': f"cover/{cover['cover_id']}/{role}",
                'sourceUrl': cover['url'], 'sourceSha256': source_digest,
                'sha256': digest, 'panel': rect, 'reconstruction': 'fanCover'}
            if rotation:
                reference['rotationDegrees'] = rotation
            resources.append({'type': role, 'importReference': reference})
        seen.add(edition_id)
        games.append({'editionId': edition_id, 'gameId': game['id'],
            'identityKey': owner_key(game, edition), 'resources': resources})
        report['selected'] += 1
    if not games:
        raise SystemExit(json.dumps(report))
    manifest = {'version': 1, 'platform': 'nes', 'games': games}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report['packs'] = write_packaging_batches(args.output, manifest, bodies)
    print(json.dumps(report))


if __name__ == '__main__':
    main()
