"""Labels and carton faces from ScreenScraper for one release class's gaps.

Input is a coverage census (scripts/coverage_census.py --json) and a copy of the
master store. For every bound, label-missing gap of the requested release class,
the store's ScreenScraper record supplies the matched game and its advertised
support-2D regions. The photo of the same printing region is fetched through the
paced, quota-checked ScreenScraper budget of prepare_packaging_resources, the
label is cut with prepare_launchbox_pack.cut_label, and the cut is written as a
'support-texture' packaging resource. Carton gaps get their missing box-2D,
box-2D-back and box-2D-side faces the same way, uncut, with ScreenScraper provenance (public
gameinfos page; credentials never enter the pack, the cache key or the log).

Region choice follows the archive's No-Intro regions. A Western edition with no
photo of its own printing may use another Western printing of the same game,
marked reconstruction=regionalPackaging; the photo region is always recorded as
sourceRegion. GBA photos use ScreenScraper's fixed template label window. Rejected cuts are reported, never
guessed. Review the --preview cuts before importing the pack.

Usage: python -I prepare_screenscraper_label_pack.py --platform gba \
  --census census.json --store-db metadata-copy.sqlite --projection projection.db \
  --env .env.local --cache CACHE_DIR --output pack.zip [--preview DIR] [--class official]
"""
import argparse
import collections
import hashlib
import io
import json
import re
import sqlite3
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_census as census_lib  # noqa: E402
import prepare_packaging_resources as resources_lib  # noqa: E402
from prepare_launchbox_pack import cut_label  # noqa: E402
from prepare_packaging_resources import (  # noqa: E402
    ScreenScraperBudget, ScreenScraperUnavailable, artwork_quality, fetch, normalize_role_image,
    owner_key, read_env, write_packaging_batches)

LABEL = 'support-texture'
FACES = ('box-2D', 'box-2D-back', 'box-2D-side')
SOURCES = {'support-2D', *FACES}
MIN_EDGE = 400  # smaller scans upscale into unreadable smears
RERELEASE = re.compile(r'\((?:Evercade|[^)]*Virtual Console|[^)]*Switch Online|Early Days Collection)\)', re.I)
# No-Intro region -> ScreenScraper media regions of the same printing, in order.
FITS = {
    'USA': ['us', 'wor'], 'Canada': ['ca', 'us'], 'World': ['wor', 'us', 'eu'],
    'Europe': ['eu', 'wor', 'uk'], 'United Kingdom': ['uk', 'eu'], 'Germany': ['de'],
    'France': ['fr'], 'Spain': ['sp'], 'Italy': ['it'], 'Netherlands': ['nl'],
    'Sweden': ['se'], 'Scandinavia': ['se', 'dk', 'no'], 'Denmark': ['dk'], 'Norway': ['no'],
    'Finland': ['fi'], 'Australia': ['au'], 'Japan': ['jp'], 'Korea': ['kr'], 'China': ['cn'],
    'Taiwan': ['tw'], 'Hong Kong': ['hk'], 'Asia': ['asi'], 'Brazil': ['br'], 'Russia': ['ru'],
}
# A Western edition without its own photo may show another Western printing of the
# same game, marked reconstruction=regionalPackaging. Asian printings differ too
# much in title and layout to stand in for one another or for Western editions.
WESTERN = {'USA', 'Canada', 'World', 'Europe', 'United Kingdom', 'Germany', 'France', 'Spain',
           'Italy', 'Netherlands', 'Sweden', 'Scandinavia', 'Denmark', 'Norway', 'Finland',
           'Australia', 'Brazil'}
STAND_INS = ['eu', 'uk', 'wor', 'us', 'au', 'ca', 'de', 'fr', 'sp', 'it', 'nl', 'se']
# ScreenScraper composes every GBA support-2D onto one 600x355 cartridge template;
# its label window is fixed (measured on accepted colour cuts, identical in all).
GBA_TEMPLATE = {'size': (600, 355), 'cart': (3, 1, 594, 348), 'label': (86, 83, 431, 221)}


def region_names(archive):
    tag = next(iter(re.findall(r'\(([^)]*)\)', archive.split('/')[-1])), '')
    return [w.strip() for w in tag.split(',')]


def fitting_regions(archive):
    """(exact, stand-in) ScreenScraper regions for the archive's region tag."""
    exact = [r for name in region_names(archive) for r in FITS.get(name, [])]
    western = all(name in WESTERN for name in region_names(archive))
    stand_ins = [r for r in STAND_INS if western and r not in exact]
    if RERELEASE.search(archive):
        # A re-release has its own (or no) packaging: the original's is only a stand-in.
        return [], list(dict.fromkeys(exact + stand_ins))
    return list(dict.fromkeys(exact)), stand_ins


def template_label(body):
    """The fixed label window of ScreenScraper's GBA template, or None."""
    with Image.open(io.BytesIO(body)) as image:
        if image.size != GBA_TEMPLATE['size'] or image.mode != 'RGBA':
            return None
        alpha = np.asarray(image.getchannel('A')) > 200
        ys, xs = np.nonzero(alpha)
        if (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) != GBA_TEMPLATE['cart']:
            return None
        x, y, w, h = GBA_TEMPLATE['label']
        out = io.BytesIO()
        image.crop((x, y, x + w, y + h)).convert('RGB').save(out, format='PNG')
        return [x, y, w, h], out.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=sorted(census_lib.FOLDERS), required=True)
    for name in ('census', 'store_db', 'projection', 'env', 'cache', 'output'):
        parser.add_argument('--' + name.replace('_', '-'), dest=name, type=Path, required=True)
    parser.add_argument('--preview', type=Path, help='also write source photos and cuts here')
    parser.add_argument('--class', dest='klass', default='official')
    parser.add_argument('--limit', type=int)
    parser.add_argument('--catalogue', type=Path, help='published catalogue: its bodies count as present')
    parser.add_argument('--store', type=Path, default=Path('D:/RShopPrivate/CatalogueStore'),
                        help='master store (artwork bodies); --store-db is a copy of its database')
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f'{args.output} exists')
    resources_lib.HTTP_CACHE = args.cache
    folder = census_lib.FOLDERS[args.platform]

    gaps = [g for g in json.load(open(args.census, encoding='utf-8'))['systems'][args.platform]['gaps']
            if g.get('class') == args.klass and g.get('bound') and not (g.get('label') and g.get('carton'))]
    # Roles the edition already shows (local or published bodies), as the census counts them.
    published = census_lib.published_keys(args.catalogue, (args.platform,)) if args.catalogue else frozenset()
    shipped = census_lib.shipped_roles(args.catalogue, (args.platform,)) if args.catalogue else None
    edition_of, have, _ = census_lib.store_roles(args.store, args.store_db, published, shipped)

    def have_role(edition, role):
        return role in have.get(edition, set()) or f'packaging:{role}' in have.get(edition, set())

    store = sqlite3.connect(f'file:{args.store_db.as_posix()}?mode=ro', uri=True)
    offered = collections.defaultdict(lambda: collections.defaultdict(dict))  # edition -> type -> region -> ref
    for edition, record in store.execute(
            "SELECT edition_id, record_json FROM records WHERE provider_id='screenscraper'"):
        if not record.startswith('{'):
            continue
        for media in json.loads(record).get('media', []):
            reference = media.get('providerReference') or {}
            if media.get('type') in SOURCES and reference.get('providerGameId'):
                offered[edition][media['type']].setdefault(media.get('region'), reference)
    projection = sqlite3.connect(f'file:{args.projection.as_posix()}?mode=ro&immutable=1', uri=True)

    credentials = read_env(args.env)
    auth = {target: credentials.get(source, '') for target, source in {
        'devid': 'SCREENSCRAPER_DEVID', 'devpassword': 'SCREENSCRAPER_DEVPASSWORD',
        'softname': 'SCREENSCRAPER_SOFTNAME', 'ssid': 'SCREENSCRAPER_USERNAME',
        'sspassword': 'SCREENSCRAPER_PASSWORD'}.items()}
    budget = ScreenScraperBudget(auth) if all(auth.values()) else None
    import requests
    session = requests.Session()
    session.headers['User-Agent'] = 'G-Shop catalogue preparation'
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)

    report = collections.Counter()
    games, bodies, seen, rows = [], {}, set(), []
    stopped = None
    for gap in gaps:
        if stopped or args.limit and len(games) >= args.limit:
            break
        archive = gap['archive']
        edition_id = edition_of.get(f'{folder}/{archive}')
        if not edition_id or edition_id in seen:
            report['noEdition' if not edition_id else 'duplicate'] += 1
            continue
        found = projection.execute('''SELECT g.record_json, e.record_json FROM library_editions e
            JOIN library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
            (edition_id,)).fetchone()
        if found is None:
            report['noProjectionEdition'] += 1
            continue
        game, edition = (json.loads(v) for v in found)
        exact_regions, stand_ins = fitting_regions(archive)
        wanted = ([LABEL] if not gap['label'] else []) + \
            [t for t in FACES if not gap['carton'] and not have_role(edition_id, t)]
        resources = []
        for role in wanted:
            source = 'support-2D' if role == LABEL else role
            choices = offered[edition_id][source]
            regions = [r for r in exact_regions + stand_ins if r in choices]
            if not regions:
                key = 'noFitting' if choices else 'none'
                report[f'{role}:{key}'] += 1
                rows.append({'archive': archive, 'role': role, 'result': key,
                             'offered': sorted(r or '' for r in choices)})
                continue
            raw = None
            for region in regions:
                reference = choices[region]
                game_id, platform_id = reference['providerGameId'], reference['providerPlatformId']
                params = {**auth, 'systemeid': platform_id, 'jeuid': game_id,
                          'media': f'{source}({region})', 'outputformat': 'png',
                          'maxwidth': 1024, 'maxheight': 1024}
                try:
                    raw = fetch(session, 'https://api.screenscraper.fr/api2/mediaJeu.php',
                                params=params, provider_budget=budget)
                except ScreenScraperUnavailable as failure:
                    stopped = failure.reason
                    break
                except requests.RequestException:
                    # The exception text carries the authenticated URL; never log it.
                    stopped = 'network'
                    break
                if not raw:
                    result = 'noMedia'
                else:
                    try:
                        result = None if artwork_quality(raw)['contentStatus'] == 'nonuniform' else 'placeholder'
                        with Image.open(io.BytesIO(raw)) as image:
                            if result is None and max(image.size) < MIN_EDGE:
                                result = 'lowRes'
                    except (ValueError, OSError):
                        result = 'unreadable'
                if result is None:
                    break
                # Some advertised faces are opaque green placeholders; try the next printing.
                report[f'{role}:{result}'] += 1
                rows.append({'archive': archive, 'role': role, 'result': result, 'region': region})
                raw = None
            if stopped:
                break
            if raw is None:
                continue
            rect, fixed, body = None, None, raw
            if role == LABEL:
                try:
                    disk = args.platform == 'nes' and archive.startswith('Disk System/')
                    fixed = template_label(raw) if args.platform == 'gba' else None
                    rect, body = fixed or cut_label(raw, disk)
                except (ValueError, OSError) as error:
                    report[f'{role}:rejected'] += 1
                    rows.append({'archive': archive, 'role': role, 'result': 'rejected',
                                 'region': region, 'reason': str(error)})
                    if args.preview:
                        (args.preview / f'rejected-{game_id}-{region}.png').write_bytes(raw)
                    continue
            try:
                data, rotation = normalize_role_image(role, body)
            except (ValueError, OSError) as error:
                report[f'{role}:unreadable'] += 1
                rows.append({'archive': archive, 'role': role, 'result': 'unreadable', 'reason': str(error)})
                continue
            digest = hashlib.sha256(data).hexdigest()
            bodies[digest] = data
            source_url = f'https://www.screenscraper.fr/gameinfos.php?plateforme={platform_id}&gameid={game_id}'
            importReference = {'sourceId': 'screenscraper', 'assetId': f'{game_id}/{source}({region})',
                               'sourceUrl': source_url, 'sourceSha256': hashlib.sha256(raw).hexdigest(),
                               'sha256': digest, 'sourceRegion': region}
            if rect:
                importReference['panel'] = rect
            if rotation:
                importReference['rotationDegrees'] = rotation
            exact = region in exact_regions
            if not exact:
                importReference['reconstruction'] = 'regionalPackaging'
            resources.append({'type': role, 'importReference': importReference})
            report[f'{role}:{"exact" if exact else "standIn"}'] += 1
            rows.append({'archive': archive, 'role': role, 'result': 'added', 'region': region,
                         'exactRegion': exact, 'template': fixed is not None, 'sha256': digest})
            if args.preview:
                stem = f'{len(games) + 1:03d}-{game_id}-{region}-{role}'
                if role == LABEL:
                    (args.preview / f'{stem}-photo.png').write_bytes(raw)
                (args.preview / f'{stem}.png').write_bytes(data)
        if resources:
            seen.add(edition_id)
            games.append({'editionId': edition_id, 'gameId': game['id'],
                          'identityKey': owner_key(game, edition), 'resources': resources})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix('.report.json').write_text(
        json.dumps({'counts': report, 'stopped': stopped, 'rows': rows}, indent=1, ensure_ascii=False),
        encoding='utf-8')
    packs = write_packaging_batches(args.output, {'version': 1, 'platform': args.platform,
                                                  'games': games}, bodies) if games else []
    print(json.dumps({'gaps': len(gaps), 'games': len(games), **report, 'stopped': stopped, 'packs': packs}))


if __name__ == '__main__':
    main()
