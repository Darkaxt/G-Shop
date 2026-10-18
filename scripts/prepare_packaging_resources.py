"""Prepare one console's classified artwork pack for R-Shop's normal Drive lane.

References remain on the desktop. Only normalized, selected-edition resources
enter the pack. Never writes ROMs, ratings, credentials or Google Drive directly.
Requires Pillow, requests, py7zr and PyMuPDF for available PDF manuals.
"""
import argparse
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
from PIL import Image, ImageOps

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
    aliases = {normalized(t) for t in [row['title'], *[t['text'] for t in row['metadata']['titles']]]}
    if heading is None or normalized(heading.get_text()) not in aliases:
        return []
    text = soup.get_text(' ', strip=True).lower()
    languages = ['mul'] if 'multi idioma' in text or 'multiidioma' in text else ['en'] if 'inglés' in text or 'ingles' in text else []
    if language_priority(languages) == 99:
        return []
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
        if language_priority(recipe.get('languages', ['en'])) == 99:
            continue
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
            if recipe.get('languages'):
                reference['sourceLanguages'] = recipe['languages']
            if reconstruction:
                reference['reconstruction'] = reconstruction
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


def owner_key(game, edition):
    game = dict(game)
    edition = dict(edition)
    game.pop('title', None)
    edition.pop('collectionCategory', None)
    for entity in [game, edition]:
        entity['providerIds'] = {k: v for k, v in entity.get('providerIds', {}).items() if k == 'packaging'}
        kept = []
        for evidence in entity.get('evidence', []):
            if evidence.get('source') == 'manual' and evidence.get('kind') == 'providerId':
                try:
                    pair = json.loads(evidence['value'])
                    if isinstance(pair, list) and len(pair) == 2 and pair[0] != 'packaging':
                        continue
                except (ValueError, TypeError):
                    pass
            kept.append(evidence)
        entity['evidence'] = kept
    return hashlib.sha256(json.dumps(['metadata-owner-v1', 'packaging', game, edition],
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


def launchbox_index(source, wanted_names, system='gba'):
    games, images = {}, {}
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
                if node.tag == 'Game' and node.findtext('Platform') == PLATFORMS[system][0]:
                    name = node.findtext('Name', '')
                    if normalized(name) in wanted_names:
                        games[node.findtext('DatabaseID')] = name
                elif node.tag == 'GameImage' and node.findtext('DatabaseID') in games:
                    item = {child.tag: child.text or '' for child in node}
                    if item.get('Type') in ROLES:
                        images.setdefault(item['DatabaseID'], []).append(item)
                root.remove(node)
                node.clear()
            depth -= 1
    return games, images


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


def read_env(path):
    result = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            name, value = line.split('=', 1)
            result[name] = value.strip().strip('\"\'')
    return result


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
                raise RuntimeError('ScreenScraper quota is exhausted; collection stopped')
            # Include the access probe conservatively; never guess a reset time.
            self.remaining = max(0, limits['maxrequestsperday'] - limits['requeststoday'] - 1)
            self.interval = 60 / rate
            self.next_allowed = started + self.interval
        if self.remaining < 1:
            raise RuntimeError('ScreenScraper quota is exhausted; collection stopped')
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
            raise RuntimeError('ScreenScraper requires a rate-controlled request budget')
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
    HTTP_CACHE = args.launchbox.parent / 'resource-bodies'
    selection = ranked_selection(args.projection, args.system)
    wanted = {normalized(name) for row in selection for name in
        [row['title'], *(x['text'] for x in row['metadata']['titles'])]}
    games, images = launchbox_index(args.launchbox, wanted, args.system)
    by_name = {}
    for key, title in games.items():
        by_name.setdefault(normalized(title), set()).add(key)
    session = requests.Session()
    manifest = {'version': 1, 'platform': args.system, 'games': []}
    bodies, report = {}, []
    credentials = read_env(args.env) if args.env else {}
    auth = {target: credentials.get(source, '') for target, source in {
        'devid': 'SCREENSCRAPER_DEVID', 'devpassword': 'SCREENSCRAPER_DEVPASSWORD',
        'softname': 'SCREENSCRAPER_SOFTNAME', 'ssid': 'SCREENSCRAPER_USERNAME',
        'sspassword': 'SCREENSCRAPER_PASSWORD'}.items()}
    provider_budget = ScreenScraperBudget(auth) if all(auth.values()) else None
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
    for row in selection:
        resources = []
        edition = row['edition']
        regions = set(edition['regions'])
        # Local reviewed complete boxes win before any remote artwork request.
        local = {'platform': args.system, 'games': [{'gameId': row['game']['id'],
            'regions': list(regions), 'resources': resources}]}
        if args.panel_layouts:
            apply_panel_layouts(local, bodies, args.panel_layouts)
            resources = local['games'][0]['resources']
        full_box = all(any(r['type'] == 'outer-box-' + face for r in resources) for face in BOX_FACES)
        if not full_box:
            web = website_box(row, args.system, session)
            if web:
                resources = [r for r in resources if not r['type'].startswith('outer-box-')]
                for resource in web:
                    bodies[resource['importReference']['sha256']] = resource.pop('_body')
                    resources.append(resource)
                full_box = True
        if full_box:
            for face, role in [('front', 'box-2D'), ('back', 'box-2D-back'), ('right', 'box-2D-side')]:
                panel = next(r for r in resources if r['type'] == 'outer-box-' + face)
                resources.append({**panel, 'type': role})
        ids = set().union(*(by_name.get(normalized(name), set()) for name in
            [row['title'], *(x['text'] for x in row['metadata']['titles'])]))
        if not full_box and len(ids) == 1:
            game_id = next(iter(ids))
            for type_name, role in ROLES.items():
                candidates = [x for x in images.get(game_id, []) if x['Type'] == type_name
                    and REGIONS.get(x.get('Region', ''), 'unsupported') in regions]
                # Deterministic source alternative, not an assertion of extra faces.
                candidates.sort(key=lambda x: x['FileName'])
                if not candidates:
                    continue
                image = candidates[0]
                filename = image['FileName']
                if not re.fullmatch(r'(?:r[0-9]+_)?[a-fA-F0-9-]+\.(jpg|png)', filename):
                    raise ValueError('Unexpected LaunchBox image identity')
                url = 'https://images.launchbox-app.com/' + filename
                body = fetch(session, url)
                if body:
                    add(resources, role, REGIONS[image['Region']], body,
                        source='launchbox', asset=game_id + '/' + filename, url=url)
        # Existing ScreenScraper facts supply the matched game identity. Only
        # extra same-edition faces/documents are requested; facts/scores stay intact.
        provider_id = row['metadata']['providerGameId']
        extra_media = list(row['metadata']['media'])
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
            if region not in regions or role not in {'box-2D-back', 'box-2D-side', 'manuel'}:
                continue
            if role != 'manuel' and any(x['type'] == role for x in resources):
                continue
            if not all(auth.values()):
                continue
            reference = media.get('providerReference')
            if not reference:
                continue
            endpoint = 'mediaManuelJeu.php' if role == 'manuel' else 'mediaJeu.php'
            params = {**auth, 'systemeid': reference['providerPlatformId'], 'jeuid': provider_id,
                'media': f'{role}({region})',
                **({} if role == 'manuel' else {'outputformat': 'png', 'maxwidth': 1024, 'maxheight': 1024})}
            body = fetch(session, 'https://api.screenscraper.fr/api2/' + endpoint,
                params=params, provider_budget=provider_budget)
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
                add(resources, role, region, body, source='screenscraper',
                    asset=f'{provider_id}/{role}({region})', url=source_url)
        report.append({'rank': row['rank'], 'title': row['title'],
            'regions': sorted(regions), 'launchboxIds': sorted(ids),
            'roles': {role: sum(x['type'] == role for x in resources)
                for role in sorted({x['type'] for x in resources})}})
        if resources:
            manifest['games'].append({'gameId': row['game']['id'], 'editionId': edition['id'],
                'identityKey': owner_key(row['game'], edition), 'resources': resources})
        print(json.dumps(report[-1]), flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.panel_layouts:
        apply_panel_layouts(manifest, bodies, args.panel_layouts)
    with zipfile.ZipFile(args.output, 'x', compression=zipfile.ZIP_STORED) as archive:
        archive.writestr('packaging.json', json.dumps(manifest, separators=(',', ':')))
        for digest, data in bodies.items():
            archive.writestr('images/' + digest + '.png', data)
    args.output.with_suffix('.report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'pack': str(args.output), 'ranked': len(selection),
        'prepared': len(manifest['games']), 'images': len(bodies)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--system', choices=PLATFORMS)
    parser.add_argument('--projection', type=Path)
    parser.add_argument('--launchbox', type=Path)
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
