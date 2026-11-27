"""Give Russian (Dendy-era) NES releases the official game's carton with a Dendy sticker.

Owner ruling 2026-11-27: an unlicensed Russian port or pirate cartridge with no
box of its own shows the official reference release's box, marked with a sticker
derived from the Dendy logo (the elephant mascot), just as fan translations show
the original box with a "translated" sticker. The owner also accepts the official
cartridge label for a Dendy game, so the label is copied unchanged.

A target is a `(Russia)` archive outside Translations/Hacks whose edition has no
front in the local store. Its donor is the licensed NES archive whose title (the
name before the first parenthesis) is identical, or the curated alias below; the
donor must have a local carton. Japan is preferred (Dendy cartridges are Famicom
format), then USA, World, Europe. A title with no NES release may name a curated
LaunchBox scan of the official release on its original platform. Nothing else is
guessed. Provenance stays the donor's; the front adds `overlay: dendySticker`.

Inputs are copies, never live files being written (see prepare_translation_pack).

Usage: python -I prepare_dendy_pack.py --projection P --store-db S --artwork A
       --lb-cache DIR --output DIR/dendy-nes.zip
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

import requests
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_packaging_resources import (  # noqa: E402
    normalize_role_image, owner_key, write_packaging_batches)
from prepare_translation_pack import donor_resources, store_cartons  # noqa: E402

FOLDER = 'Nintendo - Nintendo Entertainment System/'
LOGO = Path(__file__).resolve().parent / 'assets' / 'dendy-logo.png'
RED = (228, 0, 18)
ROLES = ('box-2D', 'box-2D-back', 'box-2D-side', 'support-texture')
SKIP_FOLDERS = ('Translations/', 'Hacks/', 'Patches/')
# Donors are original licensed releases: no unlicensed, unreleased or later
# re-release builds (the markers the cartridge reference rules also exclude).
UNOFFICIAL = re.compile(r'\((?:[^()]*\b(?:Unl|Pirate|Aftermarket|Beta|Proto|Demo|Sample|Hack|Kiosk|'
                        r'Virtual Console|Switch|Collection|Archives|Retro-Bit|Evercade|Capcom Town|'
                        r'Classic Mini|Classics Mini Mix|Disney Classic Games|QUByte Classics|'
                        r'Limited Run Games|Animal Crossing|FamicomBox)\b[^()]*)\)')
REGION_ORDER = ('Japan', 'USA', 'World', 'Europe')
# Russian titles of official games (the same game, retitled by the cartridge maker).
ALIASES = {'Prince Persii': 'Prince of Persia',
           "Malen'kaya Rusalochka": 'Little Mermaid, The'}
# Ports of games never released on the NES: the official release's front on its
# original platform (LaunchBox database id, image file, LaunchBox region).
CROSS = {'Cvetnie Linii': ('30346', '58c73d4a-114b-48af-b9a5-ddc9c051dd12.jpg', 'se')}
LAUNCHBOX_IMAGES = 'https://images.launchbox-app.com/'


def title(path):
    return re.split(r'\s+[(\[]', path.rsplit('/', 1)[-1], maxsplit=1)[0].strip()


def region_rank(path):
    for i, region in enumerate(REGION_ORDER):
        if re.search(r'\((?:[^()]*, )?' + region + r'(?:,[^()]*)?\)', path):
            return i
    return len(REGION_ORDER)


def sticker(front):
    """Composite the Dendy logo on a white badge, bottom-left as on Dendy boxes."""
    image = front.convert('RGBA')
    with Image.open(LOGO) as logo:
        logo = logo.convert('RGBA')
        w = round(min(image.width, image.height * 0.9) * 0.24)
        pad = max(3, round(w * 0.08))
        inner = w - 2 * pad
        logo = logo.resize((inner, round(logo.height * inner / logo.width)),
                           Image.Resampling.LANCZOS)
    h = logo.height + 2 * pad
    badge = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(badge)
    ring = max(2, round(w * 0.03))
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=round(w * 0.14),
                           fill=(255, 255, 255, 255), outline=RED, width=ring)
    badge.alpha_composite(logo, (pad, pad))
    shadow = Image.new('RGBA', badge.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), mask=badge.getchannel('A'))
    margin = round(image.width * 0.04)
    x, y = margin, image.height - h - margin
    offset = max(2, round(h * 0.03))
    image.alpha_composite(shadow, (x + offset, y + offset))
    image.alpha_composite(badge, (x, y))
    out = io.BytesIO()
    image.convert('RGB').save(out, format='PNG')
    return out.getvalue()


def cross_front(name, cache, payload):
    database_id, filename, region = CROSS[name]
    cached = cache / filename
    if not cached.exists():
        response = requests.get(LAUNCHBOX_IMAGES + filename, timeout=60,
                                headers={'User-Agent': 'G-Shop catalogue preparation'})
        response.raise_for_status()
        cached.write_bytes(response.content)
    raw = cached.read_bytes()
    with Image.open(io.BytesIO(raw)) as front:
        data, rotation = normalize_role_image('box-2D', sticker(front))
    digest = hashlib.sha256(data).hexdigest()
    payload[digest] = data
    reference = {'sourceId': 'launchbox', 'assetId': f'dendy/launchbox/{database_id}/box-2D',
                 'sourceUrl': LAUNCHBOX_IMAGES + filename,
                 'sourceSha256': hashlib.sha256(raw).hexdigest(), 'sha256': digest,
                 'sourceRegion': region, 'overlay': 'dendySticker'}
    if rotation:
        reference['rotationDegrees'] = rotation
    return [{'type': 'box-2D', 'importReference': reference}]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('projection', 'store_db', 'artwork', 'lb_cache', 'output'):
        parser.add_argument('--' + name.replace('_', '-'), dest=name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f'{args.output} exists')
    projection = sqlite3.connect(f'file:{args.projection.as_posix()}?mode=ro', uri=True)
    store = sqlite3.connect(f'file:{args.store_db.as_posix()}?mode=ro', uri=True)
    paths = {fid: p.replace(chr(92), '/') for fid, p in projection.execute(
        'SELECT file_id, display_path FROM drive_catalogue_entries WHERE is_folder=0 '
        'AND display_path LIKE ?', (FOLDER + '%',))}
    paths = {fid: p for fid, p in paths.items() if p.lower().endswith('.7z')
             and not p[len(FOLDER):].startswith(SKIP_FOLDERS)}
    edition_of_path, carton = store_cartons(store, args.artwork)
    query = {}
    for edition, game, key in projection.execute(
            "SELECT edition_id, game_id, catalogue_key FROM library_query_editions "
            "WHERE platform_id='nes' AND member=1"):
        if key:
            query[json.loads(key)[-1]] = edition
    official = collections.defaultdict(list)
    for p in paths.values():
        if '(Russia)' not in p and not UNOFFICIAL.search(p) and p in edition_of_path:
            official[title(p)].append(p)

    report = collections.Counter()
    games, payload, rows = [], {}, []
    for fid, path in sorted(paths.items(), key=lambda item: item[1]):
        if '(Russia)' not in path:
            continue
        edition_id = edition_of_path.get(path) or query.get(fid)
        if edition_id is None:
            report['noEdition'] += 1
            continue
        if carton(edition_id):
            report['hasFront'] += 1
            continue
        name = title(path)
        wanted = ALIASES.get(name, name)
        donors = sorted(official.get(wanted, []), key=lambda p: (region_rank(p), p))
        donor = next(((p, c) for p in donors for c in [carton(edition_of_path[p])] if c), None)
        if donor is None and name not in CROSS:
            report['noOfficialCarton' if donors else 'noOfficialRelease'] += 1
            rows.append({'archive': path[len(FOLDER):], 'donor': None,
                         'reason': 'official release has no local carton' if donors
                         else 'no licensed NES release with this title'})
            continue
        found = projection.execute('''SELECT g.record_json, e.record_json FROM library_editions e
            JOIN library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
            (edition_id,)).fetchone()
        if found is None:
            report['noEdition'] += 1
            continue
        game, edition = (json.loads(v) for v in found)
        if game.get('platformId') != 'nes':
            report['noEdition'] += 1
            continue
        if donor is None:
            resources = cross_front(name, args.lb_cache, payload)
            source = 'launchbox:' + CROSS[name][0]
        else:
            resources = donor_resources(edition_of_path[donor[0]], donor[1], ROLES, 'dendy',
                                        sticker, 'dendySticker', payload)
            source = donor[0][len(FOLDER):]
        rows.append({'archive': path[len(FOLDER):], 'donor': source,
                     'roles': [r['type'] for r in resources]})
        games.append({'editionId': edition_id, 'gameId': game['id'],
                      'identityKey': owner_key(game, edition), 'resources': resources})
        report['selected'] += 1
    print(json.dumps(rows, ensure_ascii=False, indent=1), file=sys.stderr)
    if not games:
        raise SystemExit(json.dumps(report))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    packs = write_packaging_batches(args.output, {'version': 1, 'platform': 'nes',
                                                  'games': games}, payload)
    print(json.dumps({**report, 'packs': packs}))


if __name__ == '__main__':
    main()
