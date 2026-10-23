"""Prepare one console's classified artwork pack for R-Shop's normal Drive lane.

References remain on the desktop. Only normalized, selected-edition resources
enter the pack. Never writes ROMs, ratings, credentials or Google Drive directly.
Requires Pillow, requests, py7zr and PyMuPDF for available PDF manuals.
"""
import argparse
from contextlib import closing
import math
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import sqlite3
import time
import unicodedata
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

import requests
from PIL import Image, ImageOps, ImageChops, ImageFilter, ImageStat
from artwork_colour_cast import match_colour_cast

PLATFORMS = {
    'nes': ('Nintendo Entertainment System', 'NES'),
    'snes': ('Super Nintendo Entertainment System', 'Super Nintendo'),
    'n64': ('Nintendo 64', 'Nintendo 64'),
    'gb': ('Nintendo Game Boy', 'Game Boy'),
    'gbc': ('Nintendo Game Boy Color', 'Game Boy Color'),
    'gba': ('Nintendo Game Boy Advance', 'Game Boy Advance'),
    'nds': ('Nintendo DS', 'Nintendo DS'),
    'dsi': ('Nintendo DS', 'Nintendo DSi'),
    'n3ds': ('Nintendo 3DS', 'Nintendo 3DS'),
    'gc': ('Nintendo GameCube', 'GameCube'),
    'wii': ('Nintendo Wii', 'Wii'),
    'wiiu': ('Nintendo Wii U', 'Wii U'),
    'switch': ('Nintendo Switch', 'Nintendo Switch'),
    'virtualboy': ('Nintendo Virtual Boy', 'Virtual Boy'),
    'gameandwatch': ('Nintendo Game & Watch', 'Game & Watch'),
}
ROLES = {'Box - Front': 'box-2D', 'Box - Back': 'box-2D-back',
         'Box - Spine': 'box-2D-side'}
REGIONS = {'North America': 'us', 'United States': 'us', 'Europe': 'eu',
           'Japan': 'jp', 'World': 'wor', '': None}
HTTP_CACHE = None
BOX_FACES = ('front', 'back', 'left', 'right', 'top', 'bottom')


def language_priority(languages):
    languages = set(languages)
    return 0 if languages == {'en'} else 1 if 'en' in languages else 2 if len(languages) > 1 or 'mul' in languages else 99


def compose_english_faces(game, english_resources, *, bodies=None, read=None):
    """Keep a donor's geometry/panels, substitute only its non-English faces.

    The English resources are already matched and selected per role by the
    collector. Do not reintroduce provider precedence during composition.
    No title inference, ROM identity change or unbound image search.
    """
    for face, role in [('front', 'box-2D'), ('back', 'box-2D-back')]:
        donor = next((r for r in game['resources'] if r['type'] == 'outer-box-' + face), None)
        if donor is None:
            continue
        languages = donor['importReference'].get('sourceLanguages', [])
        if 'en' in languages or 'mul' in languages:
            continue
        candidates = [r for r in english_resources if r['type'] == role and
            (r['importReference'].get('sourceLanguages') == ['en'] or r.get('region') == 'us')]
        if len({r['importReference']['sha256'] for r in candidates}) > 1:
            raise ValueError('Select one English face by quality before composition')
        if candidates:
            english = candidates[0]
            reference = {**english['importReference'], 'sourceLanguages': ['en'],
                         'sourceRegion': english['importReference'].get('sourceRegion') or english['region'],
                         'reconstruction': 'composite'}
            if bodies is not None:
                def body(resource):
                    digest = resource['importReference']['sha256']
                    return bodies[digest] if digest in bodies else read('images/' + digest + '.png')
                with Image.open(io.BytesIO(body(donor))) as panel, Image.open(io.BytesIO(body(english))) as art:
                    fitted = fit_panel(art, panel.width / panel.height)
                    colour_reference = donor['importReference'].get('colourReference')
                    if colour_reference:
                        reference_body = bodies[colour_reference['sha256']]
                        with Image.open(io.BytesIO(reference_body)) as original:
                            fitted, correction = match_colour_cast(fitted, original)
                    else:
                        colour_reference = {'sha256': donor['importReference']['sha256'],
                            'sourceId': donor['importReference']['sourceId']}
                        fitted, correction = match_colour_cast(fitted, panel)
                    if correction['applied']:
                        reference['colourCorrection'] = {
                            **{k: v for k, v in correction.items() if k != 'applied'},
                            'referenceSha256': colour_reference['sha256'],
                            'referenceSourceId': colour_reference['sourceId']}
                    game.setdefault('colourReviews', []).append({'face': face, **correction})
                    output = io.BytesIO()
                    fitted.save(output, format='PNG')
                data = png(output.getvalue())
                reference.setdefault('sourceSha256', reference['sha256'])
                reference['sha256'] = hashlib.sha256(data).hexdigest()
                bodies[reference['sha256']] = data
                # The flat/preparation front and the carton must bind the same
                # derived image, rather than returning to the original scan.
                game['resources'] = [r for r in game['resources'] if r['type'] != role]
                game['resources'].append({**english, 'importReference': reference})
            # Retain the reviewed panel until a real replacement is prepared.
            # An absent English face must not turn a complete donor into a gap.
            game['resources'].remove(donor)
            game['resources'].append({**english, 'type': 'outer-box-' + face,
                                      'region': donor.get('region'), 'importReference': reference})
            for resource in game['resources']:
                if resource['type'].startswith('outer-box-'):
                    resource['importReference'] = {**resource['importReference'],
                                                   'reconstruction': 'composite'}


def website_box(row, system, session):
    """Use the public low-resolution unfolded preview, never paid originals."""
    from bs4 import BeautifulSoup
    from nintandbox_preview import split_preview
    categories = {'gba': 'gameboy-advance', 'gb': 'gameboy', 'gbc': 'gameboy-color',
        'n64': 'nintendo-64', 'nes': 'nes-8-bit', 'snes': 'super-nintendo',
        'gameandwatch': 'game-watch'}
    if system not in categories:
        return []
    slug = re.sub(r'[^a-z0-9]+', '-', unicodedata.normalize('NFKD', row['title'])
        .encode('ascii', 'ignore').decode().lower()).strip('-')
    page_url = f'https://www.nintandbox.es/{categories[system]}/{slug}'
    page = fetch(session, page_url, limit=2 * 1024 * 1024)
    if page is None:
        return []
    soup = BeautifulSoup(page, 'html.parser')
    heading = soup.find('h1')
    aliases = {normalized(t) for t in [row['title'],
        *[t['text'] for t in (row['metadata'] or {}).get('titles', [])]]}
    if heading is None or normalized(heading.get_text()) not in aliases:
        return []
    text = soup.get_text(' ', strip=True).lower()
    languages = ['mul'] if 'multi idioma' in text or 'multiidioma' in text else ['en'] if 'inglés' in text or 'ingles' in text else ['es']
    urls = {urllib.parse.urljoin(page_url, a['href']) for a in soup.select('a[href]')
        if '/styles/ficha_open/public/' in a['href']}
    if len(urls) != 1:
        return []
    url = urls.pop()
    if urllib.parse.urlsplit(url).hostname != 'www.nintandbox.es':
        raise ValueError('Untrusted preview resource host')
    body = fetch(session, url, limit=4 * 1024 * 1024)
    if body is None:
        return []
    parts = split_preview(body)
    resources = []
    region = next((r for r in ['eu', 'us', 'jp'] if r in row['edition']['regions']), None)
    if region is None:
        return []
    for role, data, crop, rotation in parts:
        resources.append({'type': 'outer-box-' + role, 'region': region,
            '_body': data, 'importReference': {'sourceId': 'nintandbox',
                'assetId': hashlib.sha256(body).hexdigest() + '/' + role,
                'sourceUrl': url, 'sourceSha256': hashlib.sha256(body).hexdigest(),
                'sha256': hashlib.sha256(data).hexdigest(), 'panel': crop,
                'rotationDegrees': rotation, 'sourceRegion': 'eu',
                'sourceLanguages': languages, 'reconstruction': 'regionalPackaging'}})
    return resources


def fit_panel(image, aspect, tolerance=.08):
    """Small ratio deviations may fit; larger gaps extend the actual edge colour.

    No synthesis, labels, borders or background gray is added. The central scan
    remains intact rather than stretching a folded sheet onto a rectangular face.
    """
    image = image.convert('RGBA')
    maximum = min(1024, max(image.size))
    target = (max(1, round(maximum * min(aspect, 1))), max(1, round(maximum / max(aspect, 1))))
    ratio = image.width / image.height
    if abs(ratio / aspect - 1) <= tolerance:
        return image.resize(target, Image.Resampling.LANCZOS)
    fitted = ImageOps.contain(image, target, Image.Resampling.LANCZOS)
    x, y = (target[0] - fitted.width) // 2, (target[1] - fitted.height) // 2
    canvas = Image.new('RGBA', target)
    # Stretch only the edge pixel rows/columns into uncovered mesh areas.
    canvas.paste(fitted.resize(target, Image.Resampling.NEAREST))
    if x:
        canvas.paste(fitted.crop((0, 0, 1, fitted.height)).resize((x, target[1])), (0, 0))
        canvas.paste(fitted.crop((fitted.width - 1, 0, fitted.width, fitted.height))
            .resize((target[0] - x - fitted.width, target[1])), (x + fitted.width, 0))
    if y:
        canvas.paste(fitted.crop((0, 0, fitted.width, 1)).resize((target[0], y)), (0, 0))
        canvas.paste(fitted.crop((0, fitted.height - 1, fitted.width, fitted.height))
            .resize((target[0], target[1] - y - fitted.height)), (0, y + fitted.height))
    canvas.paste(fitted, (x, y))
    return canvas


def apply_panel_layouts(manifest, bodies, recipe_file):
    """Classify reviewed local scans for any bound game/console. No network IO.

    Recipes are reviewed evidence, not image heuristics. Donor-region packaging
    is explicitly marked as such and never changes ROM or cover identity.
    """
    recipe_file = Path(recipe_file)
    recipes = json.loads(recipe_file.read_text(encoding='utf-8-sig'))
    if recipes.get('version') != 1 or not isinstance(recipes.get('layouts'), list):
        raise ValueError('Invalid panel layout manifest')
    prepared = []
    for game in manifest['games']:
        candidates = [r for r in recipes['layouts']
            if r['platform'] == manifest['platform'] and r['gameId'] == game['gameId']]
        if len(candidates) > 1:
            raise ValueError('Ambiguous panel layout for game')
        if not candidates:
            continue
        recipe = candidates[0]
        regions = set(game.get('regions', [])) or ({r.get('region') for r in game['resources']} - {None})
        targets = set(recipe['targetRegions']) & regions
        if len(targets) != 1:
            raise ValueError('Panel layout must bind one selected edition region')
        region = next(iter(targets))
        donor = recipe['sourceRegion']
        reconstruction = recipe.get('reconstruction')
        if donor != region and reconstruction not in {'regionalPackaging', 'composite'}:
            raise ValueError('Different-region panels require reconstruction provenance')
        panels = recipe['panels']
        if not panels or not set(panels).issubset(BOX_FACES):
            raise ValueError('Invalid box panel role')
        resources = []
        for role, panel in panels.items():
            source = recipe_file.parent / panel['file']
            if not source.is_file():
                resources = []
                break
            raw = source.read_bytes()
            digest = hashlib.sha256(raw).hexdigest()
            if digest != panel['sha256']:
                raise ValueError('Reviewed panel source digest changed')
            rect = panel['rect']
            rotation = panel.get('rotationDegrees', 0)
            if (len(rect) != 4 or any(type(v) is not int or v < 0 for v in rect)
                    or not rect[2] or not rect[3] or rotation not in {0, 90, 180, 270}):
                raise ValueError('Invalid reviewed panel crop')
            x, y, width, height = rect
            with Image.open(io.BytesIO(raw)) as image:
                if (image.width * image.height > 64_000_000
                        or x + width > image.width or y + height > image.height):
                    raise ValueError('Reviewed panel crop exceeds source')
                cropped = image.crop((x, y, x + width, y + height))
                if rotation:
                    cropped = cropped.rotate(-rotation, expand=True)
                if 'aspect' in panel:
                    cropped = fit_panel(cropped, float(panel['aspect']))
                output = io.BytesIO()
                cropped.save(output, format='PNG')
            data = png(output.getvalue())
            target_digest = hashlib.sha256(data).hexdigest()
            bodies[target_digest] = data
            reference = {'sourceId': 'nintandbox', 'assetId': digest + '/' + role,
                'sourceUrl': panel['sourceUrl'], 'sourceSha256': digest,
                'sha256': target_digest, 'panel': rect,
                'rotationDegrees': rotation, 'sourceRegion': donor}
            languages = panel.get('languages', recipe.get('languages'))
            if languages:
                reference['sourceLanguages'] = languages
            if reconstruction:
                reference['reconstruction'] = reconstruction
            colour = panel.get('colourReference')
            if colour is not None:
                colour_file = recipe_file.parent / colour['file']
                if (colour_file.stat().st_size > 4 * 1024 * 1024 or
                        colour['sourceId'] not in {'screenscraper', 'nintandbox', 'launchbox'}):
                    raise ValueError('Invalid colour reference')
                colour_body = colour_file.read_bytes()
                if hashlib.sha256(colour_body).hexdigest() != colour['sha256']:
                    raise ValueError('Colour reference digest changed')
                bodies[colour['sha256']] = colour_body
                reference['colourReference'] = {k: colour[k] for k in ['sha256', 'sourceId']}
            resources.append({'type': 'outer-box-' + role, 'region': region,
                'importReference': reference})
        if resources:
            prepared.append((game, resources))
    # Publish only after every bound layout passed its content and crop checks.
    for game, resources in prepared:
        roles = {r['type'] for r in resources}
        game['resources'] = [r for r in game['resources'] if r['type'] not in roles] + resources
    return len(prepared)


def augment_panels(source, target, recipes, *, panels_only=False, website_fallback=False, projection=None):
    global HTTP_CACHE
    HTTP_CACHE = source.parent / 'resource-bodies'
    with zipfile.ZipFile(source) as original:
        manifest = json.loads(original.read('packaging.json'))
        english_resources = {g['gameId']: list(g['resources']) for g in manifest['games']}
        bodies = {}
        count = apply_panel_layouts(manifest, bodies, recipes)
        if website_fallback:
            rows = {r['game']['id']: r for r in ranked_selection(projection, manifest['platform'])}
            session = requests.Session()
            for game in manifest['games']:
                if all(any(r['type'] == 'outer-box-' + face for r in game['resources']) for face in BOX_FACES):
                    continue
                row = rows.get(game['gameId'])
                if row is None or row['edition']['id'] != game['editionId']:
                    raise ValueError('Collection changed before website fallback')
                resources = website_box(row, manifest['platform'], session)
                for resource in resources:
                    bodies[resource['importReference']['sha256']] = resource.pop('_body')
                game['resources'] += resources
                print(json.dumps({'rank': row['rank'], 'websitePanels': len(resources)}), flush=True)
        for game in manifest['games']:
            compose_english_faces(game, english_resources[game['gameId']], bodies=bodies, read=original.read)
        if panels_only:
            for game in manifest['games']:
                game['resources'] = [r for r in game['resources'] if r['type'].startswith('outer-box-')]
                if all(any(r['type'] == 'outer-box-' + face for r in game['resources']) for face in BOX_FACES):
                    for face, role in [('front', 'box-2D'), ('back', 'box-2D-back'), ('right', 'box-2D-side')]:
                        panel = next(r for r in game['resources'] if r['type'] == 'outer-box-' + face)
                        game['resources'].append({**panel, 'type': role})
            manifest['games'] = [g for g in manifest['games'] if g['resources']]
        if not manifest['games']:
            raise ValueError('No reviewed panels match this collection pack')
        needed = {r['importReference']['sha256'] for g in manifest['games'] for r in g['resources']}
        with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_STORED) as archive:
            archive.writestr('packaging.json', json.dumps(manifest, separators=(',', ':')))
            for digest in sorted(needed):
                archive.writestr('images/' + digest + '.png', bodies[digest]
                    if digest in bodies else original.read('images/' + digest + '.png'))
    print(json.dumps({'classifiedGames': count, 'pack': str(target)}))


def normalized(value):
    text = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode().lower()
    return re.sub('[^a-z0-9]', '', text.replace('&', 'and'))


def owner_key(game, edition, provider='packaging'):
    game = dict(game)
    edition = dict(edition)
    game.pop('title', None)
    edition.pop('collectionCategory', None)
    for entity in [game, edition]:
        entity['providerIds'] = {k: v for k, v in entity.get('providerIds', {}).items() if k == provider}
        kept = []
        for evidence in entity.get('evidence', []):
            if evidence.get('source') == 'manual' and evidence.get('kind') == 'providerId':
                try:
                    pair = json.loads(evidence['value'])
                    if (isinstance(pair, list) and len(pair) == 2 and
                            all(isinstance(v, str) and v.strip() for v in pair) and pair[0] != provider):
                        continue
                except (ValueError, TypeError):
                    pass
            kept.append(evidence)
        entity['evidence'] = kept
    return hashlib.sha256(json.dumps(['metadata-owner-v1', provider, game, edition],
        ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def ranked_selection(projection, system):
    db = sqlite3.connect(':memory:')
    db.deserialize(gzip.decompress(projection.read_bytes()))
    db.row_factory = sqlite3.Row
    # Same canonical rank/source/conflict contract as LibraryQuery._rankedScope.
    rows = db.execute('''WITH scoped AS (SELECT * FROM library_query_editions
      WHERE member=1 AND platform_id=?), priorities AS (SELECT group_key,
      MIN(source_order) AS source_order FROM scoped WHERE rating_eligible=1 GROUP BY group_key),
      scores AS (SELECT s.group_key,p.source_order,MIN(s.score) AS score FROM scoped s
      JOIN priorities p ON p.group_key=s.group_key AND p.source_order=s.source_order
      WHERE s.rating_eligible=1 GROUP BY s.group_key,p.source_order HAVING MIN(s.score)=MAX(s.score)),
      ranks AS (SELECT group_key,source_order,score,ROW_NUMBER() OVER
      (ORDER BY score DESC,group_key) AS rank FROM scores)
      SELECT r.rank,r.score,s.title,s.group_key,g.record_json AS game_json,
      e.record_json AS edition_json,m.record_json AS metadata_json FROM scoped s
      JOIN ranks r ON r.group_key=s.group_key AND r.source_order=s.source_order AND r.score=s.score
      JOIN library_editions e ON e.edition_id=s.edition_id JOIN library_game_identities g ON g.game_id=s.game_id
      JOIN library_metadata m ON m.edition_id=s.edition_id AND m.provider_id='screenscraper'
      WHERE r.rank<=25 ORDER BY r.rank,s.edition_id''', (system,)).fetchall()
    chosen = {}
    for row in rows:
        item = dict(row)
        for field in ['game', 'edition', 'metadata']:
            item[field] = json.loads(item.pop(field + '_json'))
        regions = item['edition']['regions']
        preference = min((['eu', 'us', 'jp'].index(r) if r in ['eu', 'us', 'jp'] else 99 for r in regions), default=99)
        key = item['group_key']
        if key not in chosen or preference < chosen[key][0]:
            chosen[key] = (preference, item)
    db.close()
    return sorted((v[1] for v in chosen.values()), key=lambda x: x['rank'])


def collection_selection(projection, system):
    """Every current edition, including unrated/modified and metadata gaps.

    Identity and region facts are retained verbatim. Missing prerequisites remain
    census members, rather than disappearing through the ranked/provider joins.
    """
    with closing(sqlite3.connect(':memory:')) as db:
        db.deserialize(gzip.decompress(projection.read_bytes()))
        db.row_factory = sqlite3.Row
        rows = db.execute('''SELECT s.edition_id,s.game_id,s.cache_row_id,
          s.title,s.group_key,g.record_json AS game_json,
          e.record_json AS edition_json,m.record_json AS metadata_json
          FROM library_query_editions s
          LEFT JOIN library_editions e ON e.edition_id=s.edition_id
          LEFT JOIN library_game_identities g ON g.game_id=s.game_id
          LEFT JOIN library_metadata m ON m.edition_id=s.edition_id
            AND m.provider_id='screenscraper'
          WHERE s.member=1 AND s.platform_id=? ORDER BY s.edition_id''', (system,))
        result = []
        seen = set()
        for row in rows:
            if row['edition_id'] in seen:
                raise ValueError('Duplicate collection edition')
            seen.add(row['edition_id'])
            item = dict(row)
            for field in ['game', 'edition', 'metadata']:
                raw = item.pop(field + '_json')
                item[field] = json.loads(raw) if raw is not None else None
            game, edition, metadata = item['game'], item['edition'], item['metadata']
            if (game is None or edition is None or game['id'] != row['game_id'] or
                    game['platformId'] != system or edition['id'] != row['edition_id'] or
                    edition['gameId'] != game['id']):
                raise ValueError('Inconsistent collection identity')
            if metadata is not None and (metadata.get('gameId') != game['id'] or
                    metadata.get('editionId') != edition['id'] or
                    metadata.get('platformId') != system or
                    metadata.get('providerId') != 'screenscraper'):
                raise ValueError('Inconsistent metadata identity')
            item.update(rank=None, score=None)
            result.append(item)
    return result


def write_packaging_batches(target, manifest, bodies):
    """Keep the production import's 25-game and decoded/member budgets intact."""
    games = manifest['games']
    batches = [games[start:start + 25] for start in range(0, len(games), 25)]
    prepared = []
    for index, batch in enumerate(batches, 1):
        path = target if len(batches) == 1 else target.with_name(
            f'{target.stem}.batch-{index:04d}{target.suffix}')
        if path.exists():
            raise FileExistsError(path)
        data = json.dumps({**manifest, 'games': batch}, separators=(',', ':')).encode()
        needed = sorted({r['importReference']['sha256'] for g in batch for r in g['resources']})
        if any(digest not in bodies for digest in needed):
            raise ValueError('Missing resource body')
        sizes = [len(data), *(len(bodies[digest]) for digest in needed)]
        if len(sizes) > 4096 or any(size < 1 or size > 4 * 1024 * 1024 for size in sizes) or sum(sizes) > 1024 ** 3:
            raise ValueError('Artwork batch exceeds production import budget')
        prepared.append((path, data, needed, len(batch)))
    receipts = []
    for path, data, needed, count in prepared:
        with zipfile.ZipFile(path, 'x', compression=zipfile.ZIP_STORED) as archive:
            archive.writestr('packaging.json', data)
            for digest in needed:
                archive.writestr('images/' + digest + '.png', bodies[digest])
        receipts.append({'file': path.name, 'games': count, 'images': len(needed),
            'bytes': path.stat().st_size, 'sha256': file_sha256(path)})
    return receipts


def file_sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def launchbox_records(source):
    """Stream top-level records, releasing each XML element before advancing."""
    with zipfile.ZipFile(source) as archive, archive.open('Metadata.xml') as stream:
        root = None
        depth = 0
        for event, node in ET.iterparse(stream, events=['start', 'end']):
            if event == 'start':
                depth += 1
                if root is None:
                    root = node
                continue
            if depth == 2:
                yield node.tag, {child.tag: child.text or '' for child in node}
                root.remove(node)
                node.clear()
            depth -= 1


def launchbox_index(source, wanted_names, system='gba'):
    """Resolve exact canonical/declared aliases; retain conflicting IDs.

    Aliases identify artwork candidates, never a ROM revision or physical SKU.
    Read images after resolving platform ownership so XML section order cannot
    hide alias-only images or admit another console's same-named release.
    """
    platform_games, matching_names = {}, {}
    for kind, item in launchbox_records(source):
        identity = item.get('DatabaseID')
        if kind == 'Game' and item.get('Platform') == PLATFORMS[system][0]:
            platform_games[identity] = item.get('Name', '')
            name = normalized(item.get('Name', ''))
        elif kind == 'GameAlternateName':
            name = normalized(item.get('AlternateName', ''))
        else:
            continue
        if identity and name in wanted_names:
            matching_names.setdefault(identity, set()).add(name)
    games = {identity: platform_games[identity] for identity in matching_names
             if identity in platform_games}
    names, images = {}, {}
    for identity in games:
        for name in matching_names[identity]:
            names.setdefault(name, set()).add(identity)
    if games:
        for kind, item in launchbox_records(source):
            if (kind == 'GameImage' and item.get('DatabaseID') in games
                    and item.get('Type') in ROLES):
                images.setdefault(item['DatabaseID'], []).append(item)
    return games, images, names


def launchbox_resolution(title, alternate_titles, names):
    """An exact target-title link wins over broader regional alternate names.

    Keep every candidate in the audit; a collision on the target itself remains
    ambiguous. This chooses artwork candidates, never a physical printing/ROM.
    """
    primary = set(names.get(normalized(title), set()))
    candidates = primary.union(*(names.get(normalized(t), set()) for t in alternate_titles))
    return {'selectedIds': sorted(primary if primary else candidates),
            'candidateIds': sorted(candidates),
            'method': 'exact-target-title' if primary else 'provider-alternate-titles'}


def png(body):
    with Image.open(io.BytesIO(body)) as image:
        if image.width * image.height > 64_000_000:
            raise ValueError('Source artwork dimensions exceed import budget')
        image = ImageOps.exif_transpose(image).convert('RGBA')
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        result = io.BytesIO()
        image.save(result, format='PNG')
        value = result.getvalue()
    if len(value) > 4 * 1024 * 1024:
        raise ValueError('Normalized artwork exceeds app budget')
    return value


def artwork_quality(body):
    """Measured nomination, not proof of edition/printing or visual acceptance.

    Resolution alone can reward enlarged blurry scans. Compare available detail
    at a common display size; retain both measurements for the visual review.
    """
    with Image.open(io.BytesIO(body)) as image:
        if image.width * image.height > 64_000_000 or getattr(image, 'n_frames', 1) != 1:
            raise ValueError('Artwork exceeds static image budget')
        image = ImageOps.exif_transpose(image)
        width, height = image.size
        scale = min(1, 1024 / max(width, height))
        sample = image.convert('L').resize((512, 512), Image.Resampling.LANCZOS)
        # Exclude the outer edge from the detail measurement. No source pixels
        # are cropped from the actual imported resource.
        fine = ImageChops.difference(sample, sample.filter(ImageFilter.GaussianBlur(.8))).crop((4,4,508,508))
        coarse = ImageChops.difference(sample, sample.filter(ImageFilter.GaussianBlur(2))).crop((4,4,508,508))
        fine_detail = ImageStat.Stat(fine).mean[0]
        coarse_detail = ImageStat.Stat(coarse).mean[0]
        ratio = fine_detail / coarse_detail if coarse_detail else 0
        pixels = width * height * scale * scale
        return {'width':width, 'height':height, 'usablePixels':round(pixels),
            'detailRatio':round(ratio,6), 'nominationScore':round(pixels * ratio * ratio,3)}


def choose_artwork(candidates, review=None):
    """Keep provenance and use a reviewed hash before a measured nomination."""
    measured, rejected = [], []
    for candidate in candidates:
        source_hash=hashlib.sha256(candidate['body']).hexdigest()
        try:
            quality=artwork_quality(candidate['body'])
        except (OSError,ValueError,Image.DecompressionBombError):
            rejected.append({**{k:v for k,v in candidate.items() if k!='body'},
                'sourceSha256':source_hash,'rejection':'invalid-or-unsupported-image'})
            continue
        measured.append({**candidate, 'sourceSha256':source_hash,'quality':quality})
    if not measured:
        if review: raise ValueError('Reviewed artwork was not acquired')
        return None, {'method':'unavailable', 'candidates':[],'rejected':rejected}
    if review:
        matches = [c for c in measured if c['sourceSha256'] == review.get('sourceSha256')
                   and c['source'] == review.get('sourceId')]
        if not matches or not str(review.get('reason','')).strip():
            raise ValueError('Quality review does not identify one acquired image')
        selected, method = matches[0], 'reviewed-source-hash'
    else:
        selected = max(measured, key=lambda c:(c['quality']['nominationScore'],c['sourceSha256']))
        method = 'measured-nomination-requires-visual-sample'
    audit = {'method':method, 'selectedSourceId':selected['source'],
        'selectedSha256':selected['sourceSha256'],
        'candidates':[{**{k:v for k,v in c.items() if k!='body'},
            'decision':'selected' if c is selected else 'not-selected',
            'decisionReason':review['reason'] if review else 'provisional-measured-detail-and-resolution'} for c in measured],
        'rejected':rejected}
    if review: audit['reviewReason'] = review['reason']
    return selected, audit


def seed_crawl_artwork(source, cache):
    """Reuse validated image bodies acquired by the maintained Windows worker.

    This seeds image transport cache only, never provider facts or acceptance.
    The worker has already removed the API's non-image trailing framing byte.
    Existing response bodies survive; a changed reviewed hash needs a new review.
    """
    seeded, reused, different = 0, 0, 0
    for receipt in source.glob('*.artwork.json'):
        for resource in json.loads(receipt.read_text(encoding='utf8')):
            if resource.get('status') != 'matched': continue
            media = resource['media']
            ref = media.get('providerReference',{})
            if media.get('type') not in ROLES.values() or ref.get('providerId') != 'screenscraper': continue
            sha = resource['sha256']
            if not re.fullmatch('[a-f0-9]{64}',sha) or resource['file'] != sha+'.png':
                raise ValueError('Invalid retained crawl artwork path')
            body = (source/resource['file']).read_bytes()
            if len(body)!=resource['bytes'] or len(body)>4*1024*1024 or hashlib.sha256(body).hexdigest()!=sha:
                raise ValueError('Retained crawl artwork changed')
            with Image.open(io.BytesIO(body)) as image:
                if image.format!='PNG' or max(image.size)>1024:
                    raise ValueError('Invalid retained crawl image')
                image.verify()
            region = ref.get('region')
            selector = ref['mediaType'] if region is None else f"{ref['mediaType']}({region})"
            params={'systemeid':ref['providerPlatformId'],'jeuid':ref['providerGameId'],
                    'media':selector,'outputformat':'png','maxwidth':1024,'maxheight':1024}
            url='https://api.screenscraper.fr/api2/mediaJeu.php'
            key=hashlib.sha256(json.dumps([url,params],sort_keys=True).encode()).hexdigest()
            target=cache/(key+'.bin')
            if target.exists():
                if hashlib.sha256(target.read_bytes()).hexdigest()==sha: reused+=1
                else: different+=1
            else:
                cache.mkdir(parents=True,exist_ok=True)
                with target.open('xb') as output: output.write(body)
                seeded+=1
    return {'seeded':seeded,'reused':reused,'preservedDifferentBodies':different}


def read_env(path):
    result = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            name, value = line.split('=', 1)
            result[name] = value.strip().strip('\"\'')
    return result


class ScreenScraperUnavailable(RuntimeError):
    def __init__(self, reason):
        self.reason=reason
        super().__init__('ScreenScraper quota is exhausted; uncached requests are paused'
            if reason=='quotaExceeded' else 'ScreenScraper requires a rate-controlled request budget'
            if reason=='unconfigured' else 'ScreenScraper artwork unavailable: '+reason)


class ScreenScraperBudget:
    """One serial desktop collection, paced by freshly reported account limits.

    Do not run this collector beside another ScreenScraper collection. Other
    clients consume the same account quota; the provider remains authoritative.
    """

    def __init__(self, auth, *, clock=time.monotonic, wait=time.sleep):
        self.auth = dict(auth)
        self.clock, self.wait = clock, wait
        self.remaining = None
        self.interval = None
        self.next_allowed = 0

    def reserve(self, session):
        if self.remaining is None:
            started = self.clock()
            try:
                with session.get('https://api.screenscraper.fr/api2/ssuserInfos.php',
                        params={**self.auth, 'output': 'json'},
                        stream=True, allow_redirects=False) as response:
                    if response.status_code != 200:
                        raise RuntimeError(f'ScreenScraper account check returned HTTP {response.status_code}')
                    body = bytearray()
                    for chunk in response.iter_content(8192):
                        body.extend(chunk)
                        if len(body) > 65536:
                            raise RuntimeError('ScreenScraper account response exceeds budget')
                    account = json.loads(body)['response']['ssuser']
            except requests.RequestException:
                raise RuntimeError('ScreenScraper account check unavailable') from None
            except (ValueError, KeyError, TypeError):
                raise RuntimeError('ScreenScraper account limits are unavailable') from None
            try:
                fields = ['maxthreads', 'maxrequestsperday', 'requeststoday',
                    'maxrequestskoperday', 'requestskotoday']
                limits = {key: int(account[key]) for key in fields}
                rate = int(account.get('maxrequestsperdmin', account.get('maxrequestspermin')))
                valid = (str(account['id']).lower() == self.auth['ssid'].lower()
                    and all(value >= 0 for value in limits.values()) and rate > 0)
            except (ValueError, KeyError, TypeError):
                valid = False
            if not valid:
                raise RuntimeError('ScreenScraper account limits are unavailable')
            if (limits['maxthreads'] < 1
                    or limits['requestskotoday'] >= limits['maxrequestskoperday']):
                self.remaining = 0
                raise ScreenScraperUnavailable('quotaExceeded')
            # Include the access probe conservatively; never guess a reset time.
            self.remaining = max(0, limits['maxrequestsperday'] - limits['requeststoday'] - 1)
            self.interval = 60 / rate
            self.next_allowed = started + self.interval
        if self.remaining < 1:
            raise ScreenScraperUnavailable('quotaExceeded')
        delay = self.next_allowed - self.clock()
        if delay > 0:
            self.wait(delay)  # External API's advertised rate, not a completion timer.
        self.next_allowed = self.clock() + self.interval
        self.remaining -= 1  # Reserve before dispatch, including failed attempts.


def fetch(session, url, *, params=None, limit=32 * 1024 * 1024, provider_budget=None):
    public = {key: value for key, value in (params or {}).items()
        if key not in {'devid', 'devpassword', 'softname', 'ssid', 'sspassword'}}
    cache_key = hashlib.sha256(json.dumps([url, public], sort_keys=True).encode()).hexdigest()
    target = HTTP_CACHE / (cache_key + '.bin') if HTTP_CACHE else None
    if target and target.exists():
        value = target.read_bytes()
        return None if value.strip() == b'NOMEDIA' else value
    if urllib.parse.urlsplit(url).hostname == 'api.screenscraper.fr':
        if provider_budget is None:
            raise ScreenScraperUnavailable('unconfigured')
        provider_budget.reserve(session)
    with session.get(url, params=params, stream=True, allow_redirects=False) as response:
        # No exception messages include authenticated request URLs.
        if response.status_code == 404:
            return None
        if response.status_code != 200:
            raise RuntimeError(f'Resource provider returned HTTP {response.status_code}')
        body = bytearray()
        for chunk in response.iter_content(128 * 1024):
            body.extend(chunk)
            if len(body) > limit:
                raise ValueError('Resource body exceeds budget')
        if target:
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as cached:
                cached.write(body)
        if body.strip() == b'NOMEDIA':
            return None
        return bytes(body)


def collect(args):
    global HTTP_CACHE
    HTTP_CACHE = getattr(args, 'http_cache', None) or args.launchbox.parent / 'resource-bodies'
    if getattr(args,'crawl_artwork',None):
        print(json.dumps({'crawlArtworkCache':seed_crawl_artwork(args.crawl_artwork,HTTP_CACHE)}),flush=True)
    scope = getattr(args, 'selection', 'top25')
    selection = (collection_selection if scope == 'collection' else ranked_selection)(
        args.projection, args.system)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    batch_count = math.ceil(len(selection) / 25)
    def batch_target(index):
        return args.output if batch_count <= 1 else args.output.with_name(
            f'{args.output.stem}.batch-{index:04d}{args.output.suffix}')
    for index in range(1, batch_count + 1):
        if batch_target(index).exists():
            raise FileExistsError(batch_target(index))
    if scope == 'collection':
        census = {'scope': scope, 'platform': args.system,
            'projectionSha256': file_sha256(args.projection),
            'editions': [{'gameId': r['game']['id'], 'editionId': r['edition']['id'],
                'cacheRowId': r['cache_row_id'], 'identityKey': owner_key(r['game'], r['edition']),
                'metadataAvailable': r['metadata'] is not None} for r in selection]}
        with args.output.with_suffix('.selection.json').open('x', encoding='utf8') as output:
            json.dump(census, output, indent=2)
    if getattr(args, 'inventory_only', False):
        print(json.dumps({'scope': scope, 'selected': len(selection), 'acquisitionStarted': False}))
        return
    wanted = {normalized(name) for row in selection for name in
        [row['title'], *(x['text'] for x in (row['metadata'] or {}).get('titles', []))]}
    games, images, by_name = launchbox_index(args.launchbox, wanted, args.system)
    session = requests.Session()
    manifest = {'version': 1, 'platform': args.system, 'games': []}
    bodies, report, packs = {}, [], []
    credentials = read_env(args.env) if args.env else {}
    auth = {target: credentials.get(source, '') for target, source in {
        'devid': 'SCREENSCRAPER_DEVID', 'devpassword': 'SCREENSCRAPER_DEVPASSWORD',
        'softname': 'SCREENSCRAPER_SOFTNAME', 'ssid': 'SCREENSCRAPER_USERNAME',
        'sspassword': 'SCREENSCRAPER_PASSWORD'}.items()}
    provider_budget = ScreenScraperBudget(auth) if all(auth.values()) else None
    quality_reviews = json.loads(args.quality_review.read_text(encoding='utf8')) if getattr(args,'quality_review',None) else {}
    screenscraper_unavailable = None
    def flush(processed):
        if manifest['games']:
            packs.extend(write_packaging_batches(batch_target(math.ceil(processed / 25)), manifest, bodies))
        args.output.with_suffix('.report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
        if scope == 'collection':
            args.output.with_suffix('.batches.json').write_text(json.dumps({
                'scope': scope, 'selected': len(selection), 'processed': processed,
                'preparationFinished': processed == len(selection),
                'publicationVerified': False, 'packs': packs}, indent=2), encoding='utf8')
        manifest['games'].clear()
        bodies.clear()
    def add(resources, role, region, body, *, source, asset, url, page=None, panel=None, original=None):
        source_body = original or body
        rotation = 0
        if role == 'box-2D-side':
            with Image.open(io.BytesIO(body)) as image:
                if image.width > image.height:
                    output = io.BytesIO()
                    image.transpose(Image.Transpose.ROTATE_270).save(output, format='PNG')
                    body = output.getvalue()
                    rotation = 90
        data = png(body)
        digest = hashlib.sha256(data).hexdigest()
        bodies[digest] = data
        resources.append({'type': role, 'region': region,
            **({'memberIndex': page} if page else {}),
            'importReference': {'sourceId': source, 'assetId': asset,
              'sourceUrl': url, 'sha256': digest,
              'sourceSha256': hashlib.sha256(source_body).hexdigest(),
              **({'rotationDegrees': rotation} if rotation else {}),
              **({'panel': panel} if panel else {})}})
    for position, row in enumerate(selection, 1):
        resources = []
        edition = row['edition']
        regions = set(edition['regions'])
        metadata = row['metadata'] or {}
        # These remain in the full census. A title match alone cannot establish
        # the printing of a hack/translation or an edition with unknown region.
        modified = (row['game'].get('baseGameId') or edition.get('patchId') or
            edition.get('isTranslation') or set(edition.get('tags', [])) &
                {'Hack', 'T-Eng', 'Dub', 'Undub', 'Uncensor'})
        if scope == 'collection' and (not regions or modified):
            report.append({'editionId': edition['id'], 'gameId': row['game']['id'],
                'title': row['title'], 'rank': None, 'regions': sorted(regions), 'roles': {},
                'gap': 'modified-release-artwork-binding' if modified else 'edition-region-unresolved'})
            if position % 25 == 0 or position == len(selection):
                flush(position)
            continue
        # Local reviewed complete boxes win before any remote artwork request.
        local = {'platform': args.system, 'games': [{'gameId': row['game']['id'],
            'regions': list(regions), 'resources': resources}]}
        if args.panel_layouts:
            apply_panel_layouts(local, bodies, args.panel_layouts)
            resources = local['games'][0]['resources']
        complete_layout = all(any(r['type'] == 'outer-box-' + face for r in resources) for face in BOX_FACES)
        if not complete_layout:
            web = website_box(row, args.system, session)
            if web:
                resources = [r for r in resources if not r['type'].startswith('outer-box-')]
                for resource in web:
                    bodies[resource['importReference']['sha256']] = resource.pop('_body')
                    resources.append(resource)
                complete_layout = True
        full_box = complete_layout and all(
            'en' in r['importReference'].get('sourceLanguages', ['en']) or
            'mul' in r['importReference'].get('sourceLanguages', [])
            for r in resources if r['type'] in {'outer-box-front', 'outer-box-back'})
        if full_box:
            for face, role in [('front', 'box-2D'), ('back', 'box-2D-back'), ('right', 'box-2D-side')]:
                panel = next(r for r in resources if r['type'] == 'outer-box-' + face)
                resources.append({**panel, 'type': role})
        resolution = launchbox_resolution(row['title'],
            [x['text'] for x in metadata.get('titles', [])], by_name)
        ids = set(resolution['selectedIds'])
        face_candidates = {role:[] for role in ROLES.values()}
        quality_report = {}
        if not full_box and len(ids) == 1:
            game_id = next(iter(ids))
            for type_name, role in ROLES.items():
                candidates = [x for x in images.get(game_id, []) if x['Type'] == type_name
                    and REGIONS.get(x.get('Region', ''), 'unsupported') in regions]
                candidates.sort(key=lambda x: x['FileName'])
                for image in candidates:
                    filename = image['FileName']
                    if not re.fullmatch(r'(?:r[0-9]+_)?[a-fA-F0-9-]+\.(jpg|png)', filename):
                        raise ValueError('Unexpected LaunchBox image identity')
                    url = 'https://images.launchbox-app.com/' + filename
                    body = fetch(session, url)
                    if body:
                        face_candidates[role].append({'body':body, 'region':REGIONS[image['Region']],
                            'source':'launchbox', 'asset':game_id+'/'+filename, 'url':url})
        # Existing ScreenScraper facts supply the matched game identity. Only
        # extra same-edition faces/documents are requested; facts/scores stay intact.
        provider_id = metadata.get('providerGameId')
        extra_media = list(metadata.get('media', []))
        platform_id = next((m['providerReference']['providerPlatformId'] for m in extra_media
            if m.get('providerReference')), None)
        # Legacy metadata discarded mediaManuelJeu selectors. Probe the documented
        # manual selector against the already-bound game/region; NOMEDIA is not a match.
        if platform_id is not None and not any(m['type'] == 'manuel' and m.get('region') in regions for m in extra_media):
            for region in sorted(regions):
                extra_media.append({'type': 'manuel', 'region': region,
                    'providerReference': {'providerPlatformId': platform_id}})
        for media in extra_media:
            role, region = media['type'], media.get('region')
            if region not in regions or role not in {'box-2D', 'box-2D-back', 'box-2D-side', 'manuel'}:
                continue
            if role != 'manuel' and full_box:
                continue
            if not provider_id:
                continue
            reference = media.get('providerReference')
            if not reference:
                continue
            endpoint = 'mediaManuelJeu.php' if role == 'manuel' else 'mediaJeu.php'
            params = {**auth, 'systemeid': reference['providerPlatformId'], 'jeuid': provider_id,
                'media': f'{role}({region})',
                **({} if role == 'manuel' else {'outputformat': 'png', 'maxwidth': 1024, 'maxheight': 1024})}
            try:
                body = fetch(session, 'https://api.screenscraper.fr/api2/' + endpoint,
                    params=params, provider_budget=provider_budget)
            except ScreenScraperUnavailable as failure:
                # Exhausting this provider is not a stop condition for LaunchBox.
                # Preserve its exact limitation rather than claiming paired review.
                screenscraper_unavailable = failure.reason
                continue
            if not body:
                continue
            source_url = f'https://www.screenscraper.fr/gameinfos.php?plateforme={reference["providerPlatformId"]}&gameid={provider_id}'
            if role == 'manuel':
                if not body.startswith(b'%PDF-'):
                    raise ValueError('Manual endpoint did not return a PDF')
                import pymupdf
                with pymupdf.open(stream=body, filetype='pdf') as document:
                    if document.page_count > 256:
                        raise ValueError('Manual exceeds page budget')
                    for number, page in enumerate(document, 1):
                        scale = 1024 / max(page.rect.width, page.rect.height)
                        picture = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False).tobytes('png')
                        add(resources, 'manual-page', region, picture, source='screenscraper',
                            asset=f'{provider_id}/manuel({region})/{number}', url=source_url,
                            page=number, original=body)
            else:
                face_candidates[role].append({'body':body,'region':region,'source':'screenscraper',
                    'asset':f'{provider_id}/{role}({region})','url':source_url})
        for role, candidates in face_candidates.items():
            if full_box: continue
            selected, quality = choose_artwork(candidates,
                quality_reviews.get(row['game']['id'],{}).get(role))
            available = {c['source'] for c in candidates}
            quality['providers'] = {
                'launchbox':'available' if 'launchbox' in available else
                    'ambiguous-game' if len(ids)>1 else 'no-index-match' if not ids else 'no-image-body',
                'screenscraper':'available' if 'screenscraper' in available else
                    screenscraper_unavailable or ('unconfigured' if not all(auth.values()) else 'no-bound-identity' if not provider_id else 'no-advertised-image-or-body')}
            quality_report[role] = quality
            if selected:
                resources = [r for r in resources if r['type'] != role]
                add(resources, role, selected['region'], selected['body'],
                    source=selected['source'], asset=selected['asset'],url=selected['url'])
        composed = {'resources': resources}
        compose_english_faces(composed, resources.copy(), bodies=bodies)
        resources = composed['resources']
        report.append({'rank': row['rank'], 'title': row['title'],
            'gameId': row['game']['id'], 'editionId': edition['id'],
            'regions': sorted(regions), 'launchboxIds': sorted(ids),
            'launchboxResolution': resolution,
            'artworkQuality':quality_report,
            'roles': {role: sum(x['type'] == role for x in resources)
                for role in sorted({x['type'] for x in resources})}})
        if resources:
            manifest['games'].append({'gameId': row['game']['id'], 'editionId': edition['id'],
                'identityKey': owner_key(row['game'], edition), 'resources': resources})
        print(json.dumps(report[-1]), flush=True)
        if position % 25 == 0 or position == len(selection):
            flush(position)
    print(json.dumps({'scope': scope, 'selected': len(selection), 'packs': packs,
        'prepared': sum(p['games'] for p in packs), 'publicationVerified': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--system', choices=PLATFORMS)
    parser.add_argument('--projection', type=Path)
    parser.add_argument('--selection', choices=['top25', 'collection'], default='top25',
        help='Top 25 testing sample (default), or every current collection edition')
    parser.add_argument('--inventory-only', action='store_true',
        help='Write the complete collection identity census without acquiring resources')
    parser.add_argument('--launchbox', type=Path)
    parser.add_argument('--http-cache', type=Path,
        help='Exact artwork response-cache directory; defaults beside the LaunchBox index')
    parser.add_argument('--quality-review', type=Path,
        help='Private game-ID/role map of reviewed sourceId/sourceSha256/reason selections')
    parser.add_argument('--crawl-artwork',type=Path,
        help='Reuse validated completed Windows crawl image bodies before provider requests')
    parser.add_argument('--env', type=Path)
    parser.add_argument('--normalize-spines', type=Path,
        help='Reclassify a completed local pack without repeating provider requests')
    parser.add_argument('--panel-layouts', type=Path,
        help='Reviewed per-source unfolded panel recipes, usable with any console pack')
    parser.add_argument('--augment-pack', type=Path,
        help='Add reviewed panels to an existing pack without provider requests')
    parser.add_argument('--panels-only', action='store_true',
        help='Write only panel changes, retaining existing imported media on device')
    parser.add_argument('--website-fallback', action='store_true',
        help='For an existing pack, check the public lower-res .es preview only where dump panels are absent')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.inventory_only and (args.selection != 'collection' or args.augment_pack or args.normalize_spines):
        parser.error('--inventory-only requires normal --selection collection')
    if args.augment_pack:
        if not args.panel_layouts:
            parser.error('--augment-pack requires --panel-layouts')
        if args.website_fallback and not args.projection:
            parser.error('--website-fallback requires the bound --projection')
        augment_panels(args.augment_pack, args.output, args.panel_layouts,
            panels_only=args.panels_only, website_fallback=args.website_fallback,
            projection=args.projection)
    elif args.normalize_spines:
        normalize_spines(args.normalize_spines, args.output)
    else:
        if not all([args.system, args.projection, args.launchbox]):
            parser.error('--system, --projection and --launchbox are required for collection')
        collect(args)


def normalize_spines(source, target):
    replacements = {}
    with zipfile.ZipFile(source) as original:
        manifest = json.loads(original.read('packaging.json'))
        for game in manifest['games']:
            for resource in game['resources']:
                if resource['type'] != 'box-2D-side':
                    continue
                reference = resource['importReference']
                data = original.read('images/' + reference['sha256'] + '.png')
                with Image.open(io.BytesIO(data)) as image:
                    if image.width <= image.height:
                        continue
                    output = io.BytesIO()
                    image.transpose(Image.Transpose.ROTATE_270).save(output, format='PNG')
                    rotated = output.getvalue()
                reference['rotationDegrees'] = 90
                reference['sha256'] = hashlib.sha256(rotated).hexdigest()
                replacements[reference['sha256']] = rotated
        needed = {r['importReference']['sha256'] for g in manifest['games'] for r in g['resources']}
        with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_STORED) as archive:
            archive.writestr('packaging.json', json.dumps(manifest, separators=(',', ':')))
            for digest in sorted(needed):
                archive.writestr('images/' + digest + '.png', replacements[digest]
                    if digest in replacements else original.read('images/' + digest + '.png'))
    target.with_suffix('.report.json').write_bytes(source.with_suffix('.report.json').read_bytes())
    print(json.dumps({'normalizedSpines': len(replacements), 'pack': str(target)}))


if __name__ == '__main__':
    main()
