"""Filename-only catalogue preparation for the app's supported collection.

Reads directory metadata on the mounted ROM volume, never ROM contents. Public
provider indexes and private, reusable mappings stay in the chosen cache folder.
Exact title candidates are not raw-ROM matches or physical-edition acceptance.
"""
import argparse
import collections
import csv
import datetime
import hashlib
import html
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys

import requests

from prepare_packaging_resources import launchbox_records, normalized

REPO = Path(__file__).resolve().parents[1]
REGISTRY = Path(__file__).with_name('catalogue_platforms.json')
PROVIDER_NAMESPACES = {'ereader': {'launchbox': [], 'screenscraperId': 119}}
# Single letters I/V/X can be names or words; only unambiguous multi-letter
# sequel numerals participate. Word boundaries preserve VIP and other acronyms.
SEQUEL_NUMERALS = dict(zip(
    ('II', 'III', 'IV', 'VI', 'VII', 'VIII', 'IX', 'XI', 'XII', 'XIII',
     'XIV', 'XV', 'XVI', 'XVII', 'XVIII', 'XIX', 'XX'),
    ('2', '3', '4', '6', '7', '8', '9', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20')))
EXCLUDED = {'saves', 'patches', '_meta', '$recycle.bin', '.trash'}
REGIONS = {'world', 'usa', 'europe', 'japan', 'china', 'korea', 'taiwan',
    'hong kong', 'brazil', 'russia', 'australia', 'asia', 'uk', 'united kingdom',
    'germany', 'france', 'netherlands', 'spain', 'italy', 'sweden', 'denmark',
    'finland', 'norway', 'canada', 'argentina', 'portugal', 'new zealand',
    'south africa', 'latin america', 'mexico', 'belgium', 'poland', 'greece',
    'ireland', 'scandinavia', 'austria', 'india', 'peru', 'chile', 'turkey',
    'israel', 'indonesia', 'singapore', 'thailand', 'czech', 'slovakia', 'hungary'}


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def write(path, document):
    with Path(path).open('x', encoding='utf-8') as stream:
        json.dump(document, stream, ensure_ascii=False, indent=2)


def registry():
    """Explicit provider names; app-owned IDs/extensions, checked for full parity."""
    config = read(REGISTRY)['platforms']
    text = (REPO/'lib/models/system_model.dart').read_text(encoding='utf-8')
    systems = {}
    for block in text.split('    SystemModel(')[1:]:
        identity = re.search(r"id: '([^']+)'", block)[1]
        libretro = re.search(r"libretroId: '([^']*)'", block)[1]
        extensions = re.search(r'romExtensions: \[([^]]*)\]', block)[1]
        systems[identity] = {**config.get(identity, {}),
            'extensions': re.findall(r"'([^']+)'", extensions),
            'folders': config.get(identity, {}).get('folders', [libretro.replace('_', ' ')])}
    if set(systems) != set(config):
        raise ValueError('Catalogue registry differs from supported app systems')
    ss = (REPO/'lib/services/metadata/screenscraper_provider.dart').read_text(encoding='utf-8')
    block = ss.split('static const platformIds = <String, int>{', 1)[1].split('};', 1)[0]
    ids = {key: int(value) for key, value in re.findall(r"'([^']+)': (\d+)", block)}
    if set(systems) != set(ids):
        raise ValueError('ScreenScraper registry differs from supported app systems')
    for key in systems:
        systems[key]['screenscraperId'] = ids[key]
    return systems


def filename_title(filename, system=None):
    stem = PurePosixPath(filename).stem.replace('_', ' ')
    if system == 'nds':
        # Scene release numbers are catalogue decoration, unlike game sequels.
        stem = re.sub(r'^(?:\d{4,5}|[xz]\d{3,5})\s+-\s+', '', stem, flags=re.I)
    if system == 'n3ds':
        # Preserve the title ID in sourcePath, not as part of the game title.
        stem = re.sub(r'^0004[0-9a-fA-F]{12}\s+', '', stem)
        stem = re.sub(r'\.(?:piratelegit|legit|standard)$', '', stem, flags=re.I)
        stem = re.sub(r'\s*\((?:(?:CTR|KTR)-[A-Z]-[A-Z0-9]{4}(?:-\d{2})?|v\d[^)]*|[JUEKWT]+|DLC|Update)\)', '', stem)
    country_codes = {'us', 'eu', 'jp', 'au', 'unknown'}
    for group in re.finditer(r'\(([^)]*)\)', stem):
        parts = [r.strip().casefold() for r in group[1].split(',')]
        if (any(r in REGIONS | country_codes for r in parts) and
                all(r in REGIONS | country_codes or re.fullmatch(r'rev\s+[^,]+', r) for r in parts)):
            return re.sub(r'\s+', ' ', stem[:group.start()]).strip()
    # Tags without a recognised region: remove only release annotations. A
    # parenthesised subtitle can be part of the title and must survive.
    stem = re.sub(r'\s*\[(?:!|n|b\d*|h[^]]*|t[^]]*|BIOS)\]', '', stem, flags=re.I)
    stem = re.sub(r'\s*\((?:Rev [^)]*|v\d[^)]*|Beta[^)]*|Proto[^)]*|Demo[^)]*|Unl|En(?:,[A-Z][a-z])+|Disc \d[^)]*|Undub|Uncensored|Orchestrated|English Translation)\)', '', stem, flags=re.I)
    if system == 'n3ds' and re.search(r'\((?:Undub|Uncensored|Orchestrated|English Translation)\)', filename, re.I):
        stem = re.sub(r'\s*\((?:homuhomu|code)\)', '', stem, flags=re.I)
    return re.sub(r'\s+', ' ', stem).strip()


def source_kind(filename, system):
    folders = {p.casefold() for p in Path(filename).parts[:-1]}
    name = Path(filename).name
    if {'texture packs', 'textures'} & folders:
        return 'auxiliary-resource'
    if ('firmware' in folders or '[bios]' in name.casefold() or
            (system == 'snes' and title_key(filename_title(name, system)) == 'sufami turbo')):
        return 'firmware'
    if system == 'gba' and 'e-reader' in folders:
        return 'card-data'
    if re.search(r'(?i)(?:^0004008c|\(DLC\))', name):
        return 'dlc'
    if re.search(r'(?i)(?:^0004000e|\(Update\))', name):
        return 'update'
    return 'program'


def inventory(root, output, exclude_systems=()):
    systems = registry()
    if not set(exclude_systems) <= set(systems):
        raise ValueError('Unknown excluded system')
    top = {p.name: p for p in root.iterdir() if p.is_dir()}
    # Windows aliases can differ only in case; do not visit the same folder twice.
    names = {name.casefold(): name for name in top}
    owners, rows, summaries = {}, [], {}
    for system, settings in systems.items():
        folders = sorted({names[f.casefold()] for f in settings['folders'] if f.casefold() in names})
        if system in exclude_systems:
            for folder in folders:
                owners[folder] = system
            summaries[system] = {'folders': folders, 'sources': None, 'retainedExistingMapping': True}
            continue
        extensions = set(settings['extensions']) | set(settings.get('inventoryExtensions', [])) | {'.zip', '.7z'}
        count = 0
        others = collections.Counter()
        for folder in folders:
            if folder in owners:
                raise ValueError('Folder belongs to multiple systems: '+folder)
            owners[folder] = system
            def onerror(error):
                raise error
            for base, dirs, files in os.walk(top[folder], onerror=onerror):
                dirs[:] = sorted(d for d in dirs if d.casefold() not in EXCLUDED)
                for name in sorted(files):
                    suffix = Path(name).suffix.casefold()
                    if suffix not in extensions:
                        others[suffix] += 1
                        continue
                    path = Path(base)/name
                    relative = path.relative_to(top[folder]).as_posix()
                    rows.append({'system': system, 'filename': relative,
                        'sourcePath': folder+'/'+relative, 'folder': folder,
                        'appContainerSupported': suffix in set(settings['extensions']) | {'.zip', '.7z'},
                        'title': filename_title(relative, system),
                        'sourceKind': source_kind(relative, system),
                        'family': relative.split('/')[0] if '/' in relative else 'root',
                        'modifiedContext': bool(re.search(r'(?i)(?:^|/)(?:hacks|color hacks|t-en|translations)(?:/|$)|\((?:hack|patched|translation|english translation|undub|uncensored|orchestrated)|\[Scarlet Study English', relative))})
                    count += 1
        summaries[system] = {'folders': folders, 'sources': count, 'excludedExtensions': dict(others)}
        print(json.dumps({'inventory': system, 'sources': count, 'folders': folders}), flush=True)
    document = {'version': 1, 'root': str(root), 'romBodiesRead': 0,
        'registrySha256': sha(REGISTRY), 'supportedSystems': systems,
        'systems': summaries, 'unassignedFolders': sorted(set(top)-set(owners)),
        'rows': sorted(rows, key=lambda r: (r['system'], r['sourcePath']))}
    write(output, document)
    return document


def download(session, url, path):
    receipt_path = path.with_suffix(path.suffix+'.receipt.json')
    if path.exists():
        receipt = read(receipt_path)
        if receipt['url'] != url or receipt['sha256'] != sha(path):
            raise ValueError('Changed cached public index: '+str(path))
        return receipt
    partial = path.with_suffix(path.suffix+'.part')
    with session.get(url, stream=True) as response:
        response.raise_for_status()
        with partial.open('xb') as stream:
            for chunk in response.iter_content(1024*1024):
                stream.write(chunk)
        receipt = {'url': url, 'finalUrl': response.url,
            'fetchedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'contentType': response.headers.get('Content-Type'),
            'bytes': partial.stat().st_size, 'sha256': sha(partial)}
    partial.rename(path)
    write(receipt_path, receipt)
    return receipt


def screenscraper_csv(source, identity):
    body = source.read_text(encoding='utf-8-sig')
    records = list(csv.DictReader(io.StringIO(body), delimiter=';', quotechar='"'))
    if not records or set(records[0]) != {'Game ID', 'Game Name'}:
        raise ValueError('Public CSV is empty or invalid')
    entries, invalid = {}, []
    for record in records:
        key, title = record['Game ID'], record['Game Name']
        if not key.isdigit() or not title.strip():
            invalid.append(record)
            continue
        if key in entries:
            raise ValueError('Duplicate ScreenScraper record')
        entries[key] = {'id': key, 'title': title, 'aliases': [], 'platformId': identity}
    if not entries:
        raise ValueError('Public CSV contains no usable title records')
    return entries, invalid


def indexes(inventory_path, launchbox, cache, output, existing_cache=None):
    census = read(inventory_path)
    settings = {**census['supportedSystems'], **PROVIDER_NAMESPACES}
    namespaces = {catalogue_namespace(row) for row in census.get('rows', [])}
    active = {key: value for key, value in settings.items()
              if census['systems'].get(key, {}).get('sources') or key in namespaces}
    platforms = collections.defaultdict(list)
    for system, config in active.items():
        for platform in config['launchbox']:
            platforms[platform].append(system)
    games = {key: {} for key in active}
    aliases = collections.defaultdict(set)
    alias_regions = collections.defaultdict(lambda: collections.defaultdict(set))
    observed, arcade_fields = set(), None
    for kind, record in launchbox_records(launchbox):
        if kind == 'Game':
            observed.add(record.get('Platform'))
            if record.get('Platform') == 'Arcade' and arcade_fields is None:
                arcade_fields = sorted(record)
            for system in platforms.get(record.get('Platform'), []):
                games[system][record['DatabaseID']] = {'id': record['DatabaseID'],
                    'title': record['Name'], 'platformName': record['Platform'], 'aliases': []}
        elif kind == 'GameAlternateName':
            aliases[record['DatabaseID']].add(record.get('AlternateName', ''))
            if record.get('Region'):
                alias_regions[record['DatabaseID']][record.get('AlternateName', '')].add(record['Region'])
    for system in games:
        missing = set(active[system]['launchbox'])-observed
        if missing and not active[system].get('allowMissingLaunchbox'):
            raise ValueError('Unrecognised LaunchBox platform '+str(missing))
        for identity, game in games[system].items():
            game['aliases'] = sorted(aliases[identity]-{game['title'], ''})
            game['aliasRegions'] = {name: sorted(regions) for name, regions in alias_regions[identity].items()}
    ss, sources, issues = {}, {}, {}
    with requests.Session() as session:
        for system, config in active.items():
            identity = config['screenscraperId']
            name = f'screenscraper-{identity}-gameslist.csv'
            source = cache/name
            old = existing_cache/f'screenscraper-{system}-gameslist.csv' if existing_cache else None
            if old and old.exists():
                source = old
            url = f'https://www.screenscraper.fr/medias/{identity}/gameslist.csv'
            try:
                receipt = download(session, url, source)
                entries, invalid = screenscraper_csv(source, identity)
                ss[system] = entries
                sources[system] = {**receipt, 'path': str(source), 'invalidRows': invalid}
            except (requests.RequestException, ValueError) as error:
                # An unavailable public index is a reported gap, not an empty
                # successful catalogue or a reason to spend per-ROM API calls.
                ss[system] = {}
                issues[system] = str(error)
            print(json.dumps({'index': system, 'launchbox': len(games[system]),
                'screenscraper': len(ss[system]), 'issue': issues.get(system)}), flush=True)
    document = {'version': 1, 'inventorySha256': sha(inventory_path),
        'launchbox': {'path': str(launchbox), 'sha256': sha(launchbox)},
        'screenscraperSources': sources, 'issues': issues,
        'arcadeGameFields': arcade_fields,
        'platforms': games, 'screenscraper': ss}
    write(output, document)
    return document


def title_key(title, *, word_boundaries=True):
    # A missing typographic apostrophe does not create a word boundary. Keep
    # actual spaces and numeric operators, so Castle Quest is not Castlequest.
    title = re.sub(r"(?<=\w)['’](?=\w)", '', title.replace('™', '').replace('®', ''))
    article = re.match(r'^(.+?),\s*(le|la|les|der|die|das|el|los|las|il|lo|gli|un|une|des)(?=\s*(?:-|:|$))(.*)$', title, re.I)
    if article:
        title = article[2]+' '+article[1]+article[3]
    return normalized(title, word_boundaries=word_boundaries)


def sequel_number_key(title):
    title = html.unescape(title)
    key = title_key(re.sub(r'\b(?:' + '|'.join(SEQUEL_NUMERALS) + r')\b',
                           lambda m: SEQUEL_NUMERALS[m[0]], title))
    return key + ('|edition:#' if title.rstrip().endswith('#') else '')


def release_lookup_title(title):
    """Ignore only trailing numeric three-part versions/dates, never named mods."""
    return re.sub(r'(?:\s+\(\d{1,4}(?:[.-]\d{1,4}){2}\))+$', '', title)


def lookup(games):
    result = {'canonical': collections.defaultdict(set), 'declared-alias': collections.defaultdict(set),
              'loose': collections.defaultdict(set)}
    for identity, game in games.items():
        result['canonical'][title_key(game['title'])].add(identity)
        for title in game['aliases']:
            result['declared-alias'][title_key(title)].add(identity)
        for title in [game['title'], *game['aliases']]:
            result['loose'][normalized(title)].add(identity)
    return result


def provider_filename_keys(filename, system, *, card_data=False):
    """Compare declared filenames without reading archives or discarding revisions."""
    name = PurePosixPath(filename.replace('\\', '/')).name
    stem = PurePosixPath(name).stem
    if PurePosixPath(name).suffix.casefold() in {'.zip', '.7z'} and PurePosixPath(stem).suffix.casefold() in {
            '.nes', '.nds', '.ds', '.gba', '.gb', '.gbc', '.bin', '.md', '.3ds', '.cia', '.raw', '.sav'}:
        stem = PurePosixPath(stem).stem
    if system == 'nds':
        stem = re.sub(r'^(?:\d{4,5}|[xz]\d{3,5})\s+-\s+', '', stem, flags=re.I)
    countries = {'u': 'USA', 'us': 'USA', 'e': 'Europe', 'eu': 'Europe', 'j': 'Japan', 'jp': 'Japan'}
    stem = re.sub(r'\((U|US|E|EU|J|JP)\)', lambda m: '(' + countries[m[1].casefold()] + ')', stem, flags=re.I)
    keys = {'filename:' + title_key(stem)}
    if card_data:
        core = filename_title(stem + '.raw', 'gba')
        tags = re.findall(r'\(([^)]*)\)', stem)
        regions = sorted({part.strip().casefold() for tag in tags for part in tag.split(',')
                          if part.strip().casefold() in REGIONS})
        revisions = sorted(tag.casefold() for tag in tags if re.match(r'(?:Rev\b|v\d|Proto\b|Beta\b|Demo\b)', tag, re.I))
        suffix = '|' + ','.join(regions) + '|' + ','.join(revisions)
        code = re.search(r'(?<!\w)(?:\d{2,3}-[A-Z]\d{3}|[A-Z]-\d{2,3}(?:-[#a-z])?)(?!\w)', core, re.I)
        if code:
            keys.add('card-code:' + title_key(core[:code.start()]) + '|' + code[0].upper()
                     + suffix)
            if re.fullmatch(r'\d{2,3}-[A-Z]\d{3}', code[0], re.I):
                keys.add('card-id:' + code[0].upper() + suffix)
        parts = core.split(' - ')
        if code:
            printed_name = core[code.end():].strip(' -')
            if printed_name and '...' not in printed_name:
                keys.add('card-name:' + title_key(core[:code.start()].strip(' -'))
                         + '|' + title_key(printed_name) + suffix)
        elif len(parts) >= 3 and '...' not in core:
            keys.add('card-name:' + title_key(' - '.join(parts[:-1]))
                     + '|' + title_key(parts[-1]) + suffix)
        if len(parts) >= 3 and normalized(parts[0]) == 'pokemonetcg' and '...' not in core:
            offset = 3 if re.fullmatch(r'[A-Z]-\d{2,3}-[#a-z]', parts[2], re.I) else 2
            if len(parts) > offset:
                keys.add('card-name:' + title_key(' - '.join(parts[:2])) + '|'
                         + title_key(' - '.join(parts[offset:])) + suffix)
    return keys


def catalogue_family(source):
    if source['system'] == 'n64' and re.search(r'\(64DD\)', source['filename'], re.I):
        return '64dd'
    return source['family'].casefold()


def catalogue_namespace(source):
    """Keep embedded FDS media in its provider namespace and NES library."""
    if source['system'] == 'nes' and source['family'].casefold() == 'disk system':
        return 'fds'
    if source['system'] == 'gba' and source.get('sourceKind') == 'card-data':
        return 'ereader'
    return source['system']


def source_games(source, provider, games):
    # Minis is an explicit source family and a separate LaunchBox namespace.
    # The parent app system remains PSP. Avoid duplicate-title cross-family IDs.
    if source['system'] == 'psp' and provider == 'launchbox':
        platform = 'Sony PSP Minis' if source['family'].casefold() == 'minis' else 'Sony PSP'
        return {key: game for key, game in games.items() if game['platformName'] == platform}
    if source['system'] == 'n64' and provider == 'launchbox':
        platform = 'Nintendo 64DD' if catalogue_family(source) == '64dd' else 'Nintendo 64'
        return {key: game for key, game in games.items() if game['platformName'] == platform}
    return games


def match(title, names):
    key = title_key(title)
    for method in ['canonical', 'declared-alias']:
        ids = names[method].get(key, set())
        if ids:
            return {'status': 'unique' if len(ids) == 1 else 'ambiguous',
                    'method': method, 'ids': sorted(ids)}
    ids = names['loose'].get(normalized(title), set())
    return {'status': 'loose-candidate' if ids else 'unmatched',
            'method': 'spacing-candidate' if ids else 'none', 'ids': sorted(ids)}


def regional_alias(source, finding, games):
    if finding['status'] != 'ambiguous' or finding['method'] != 'declared-alias':
        return finding
    source_regions = {part.strip().casefold() for tag in re.findall(r'\(([^)]*)\)', source['filename'])
                      for part in tag.split(',') if part.strip().casefold() in REGIONS}
    region_names = {'north america': {'usa', 'canada'}, 'oceania': {'australia', 'new zealand'},
                    'the netherlands': {'netherlands'}, 'united states': {'usa'}}
    selected = []
    for identity in finding['ids']:
        game = games[identity]
        for alias, regions in game.get('aliasRegions', {}).items():
            actual_regions = {country for region in regions for country in
                              region_names.get(region.casefold(), {region.casefold()})}
            if title_key(alias) == title_key(source['title']) and source_regions & actual_regions:
                selected.append(identity)
                break
    if len(selected) == 1:
        return {'status': 'unique', 'method': 'regional-declared-alias',
                'ids': selected, 'originalCandidateIds': finding['ids']}
    return finding


def qualified_alias(source, finding, games):
    """Use an explicit author/publisher tag, never an inferred title substring."""
    if finding['status'] != 'ambiguous':
        return finding
    def company_key(value):
        value = re.sub(r'\b(?:co|company|inc|ltd|corp)\.?\s*$', '', value, flags=re.I).strip()
        return title_key(value)
    tags = {company_key(tag) for tag in re.findall(r'\(([^)]*)\)', source['filename'])}
    selected = []
    for identity in finding['ids']:
        qualifier = re.search(r'\(([^)]+)\)\s*$', games[identity]['title'])
        if qualifier and company_key(qualifier[1]) in tags:
            selected.append(identity)
    if len(selected) == 1:
        return {'status': 'unique', 'method': 'explicit-source-qualifier',
                'ids': selected, 'originalCandidateIds': finding['ids']}
    return finding


def load_title_aliases(path):
    if path is None:
        return {}
    document = read(path)
    if document.get('version') != 1:
        raise ValueError('Unsupported reviewed title-alias format')
    for evidence in document.get('evidence', []):
        if sha(evidence['path']) != evidence['sha256']:
            raise ValueError('Reviewed title-alias evidence changed')
    result = {}
    selectors = set()
    for rule in document['rules']:
        if not rule.get('reason') or not rule.get('providers'):
            raise ValueError('Title-alias review requires providers and a reason')
        key = rule['system'], title_key(rule['sourceTitle'])
        selector = (key, tuple(sorted(rule.get('regions', []))), tuple(sorted(rule.get('tags', []))),
                    tuple(sorted(rule.get('sourcePaths', []))))
        if selector in selectors:
            raise ValueError('Duplicate reviewed title-alias selector')
        selectors.add(selector)
        result.setdefault(key, []).append(rule)
    return result


def reviewed_alias(source, rules):
    tags = {tag.casefold().strip() for tag in re.findall(r'\(([^)]*)\)', source['filename'])}
    regions = {part.strip() for tag in tags for part in tag.split(',') if part.strip() in REGIONS}
    applicable = [rule for rule in rules.get((source['system'], title_key(source['title'])), [])
        if set(r.casefold() for r in rule.get('regions', [])) <= regions
        and set(t.casefold() for t in rule.get('tags', [])) <= tags
        and (not rule.get('sourcePaths') or source.get('sourcePath') in rule['sourcePaths'])]
    if len(applicable) > 1:
        raise ValueError('Conflicting applicable title-alias reviews')
    return applicable[0] if applicable else None


def resolve_source(source, index, cache, reviews=None, *, matcher_version=1):
    """One cached resolver per platform/family, shared by producer and consumer."""
    from prepare_catalogue_bindings import corroborate_providers
    system = catalogue_namespace(source)
    family = catalogue_family(source) if system in {'psp', 'n64'} else ''
    broadcast_source = system == 'snes' and (
        source['family'].casefold() == 'satellaview' or
        bool(re.match(r'^BS\s', source['title'], re.I)))
    key = system, family, broadcast_source, matcher_version
    if key not in cache:
        games = {provider: source_games(source, provider, systems[system]) for provider, systems in
                 [('launchbox', index['platforms']), ('screenscraper', index['screenscraper'])]}
        lookups = {provider: lookup({identity: game for identity, game in values.items()
            if not (system == 'snes' and provider == 'launchbox' and
                    game.get('platformName') == 'Nintendo Satellaview')})
            for provider, values in games.items()}
        if system == 'snes':
            lookups['satellaview'] = lookup({identity: game for identity, game in games['launchbox'].items()
                if game.get('platformName') == 'Nintendo Satellaview'})
        if matcher_version >= 2:
            lookups['rom-filenames'] = {}
            for provider, values in games.items():
                filenames = collections.defaultdict(set)
                for identity, game in values.items():
                    for name in game.get('romNames', []):
                        for filename_key in provider_filename_keys(name, source['system'], card_data=system == 'ereader'):
                            filenames[filename_key].add(identity)
                lookups['rom-filenames'][provider] = filenames
        if matcher_version >= 3:
            lookups['sequel-numbers'] = {}
            for provider, values in games.items():
                numbers = collections.defaultdict(set)
                for identity, game in values.items():
                    for name in [game['title'], *game.get('aliases', [])]:
                        numbers[sequel_number_key(name)].add(identity)
                lookups['sequel-numbers'][provider] = numbers
        lb_names, ss_names = {}, {}
        spelling_lb_names, spelling_ss_names = {}, {}
        for identity, game in games['launchbox'].items():
            if (system == 'snes' and not broadcast_source and
                    game.get('platformName') == 'Nintendo Satellaview'):
                continue
            for title in [game['title'], *game['aliases']]:
                lb_names.setdefault(normalized(title, word_boundaries=True), set()).add(identity)
                if matcher_version >= 3:
                    spelling_lb_names.setdefault(sequel_number_key(title), set()).add(identity)
        for identity, game in games['screenscraper'].items():
            ss_names.setdefault(normalized(game['title'], word_boundaries=True), {})[identity] = game['title']
            if matcher_version >= 3:
                spelling_ss_names.setdefault(sequel_number_key(game['title']), {})[identity] = game['title']
        if matcher_version >= 3:
            lookups['spelling-lb-names'] = spelling_lb_names
            lookups['spelling-ss-names'] = spelling_ss_names
        cache[key] = games, lookups, lb_names, ss_names
    games, lookups, lb_names, ss_names = cache[key]
    review = reviewed_alias(source, reviews or {})
    matches, providers = {}, {}
    for provider in games:
        found = match(source['title'], lookups[provider])
        if (provider == 'launchbox' and system == 'snes' and
                found['status'] in {'unmatched', 'loose-candidate'} and
                broadcast_source):
            broadcast = match(source['title'], lookups['satellaview'])
            if broadcast['status'] in {'unique', 'ambiguous'}:
                found = broadcast
        if provider == 'launchbox':
            found = regional_alias(source, found, games[provider])
            if matcher_version >= 2:
                found = qualified_alias(source, found, games[provider])
            if matcher_version >= 2 and system == 'sg1000' and found['status'] == 'ambiguous':
                candidate_platforms = {games[provider][i]['platformName'] for i in found['ids']}
                if candidate_platforms == {'Sega SG-1000', 'Sega SC-3000'}:
                    preferred = ('Sega SC-3000' if source['family'].casefold() == 'sc-3000' or
                                 re.search(r'\(SC-3000\)', source['filename'], re.I) else 'Sega SG-1000')
                    selected = [i for i in found['ids'] if games[provider][i]['platformName'] == preferred]
                    if len(selected) == 1:
                        found = {'status': 'unique', 'method': 'library-platform',
                                 'ids': selected, 'originalCandidateIds': found['ids']}
        if matcher_version >= 3 and found['status'] in {'unique', 'ambiguous'}:
            # Project DIVA 2nd and 2nd# are separately catalogued releases.
            # Preserve that explicit marker instead of treating it as punctuation.
            marked = lambda name: html.unescape(name).rstrip().endswith('#')
            names = {i: [games[provider][i]['title'], *games[provider][i].get('aliases', [])]
                     for i in found['ids']}
            if marked(source['title']) or any(marked(name) for values in names.values() for name in values):
                selected = [i for i, values in names.items() if any(
                    marked(name) == marked(source['title']) and title_key(name) == title_key(source['title'])
                    for name in values)]
                if set(selected) != set(found['ids']):
                    found = {'status': 'unique' if len(selected) == 1 else 'ambiguous' if selected else 'unmatched',
                             'method': 'literal-edition-marker', 'ids': sorted(selected),
                             'originalCandidateIds': found['ids']}
        if (matcher_version >= 3 and found['status'] != 'unique' and
                source.get('sourceKind') == 'program' and
                source['family'].casefold() not in {'download play', 'multiboot'}):
            identities = lookups['sequel-numbers'][provider].get(sequel_number_key(source['title']), set())
            if len(identities) == 1:
                found = {'status': 'unique', 'method': 'catalogue-title-spelling', 'ids': sorted(identities)}
        if matcher_version >= 2 and found['status'] != 'unique':
            keys = provider_filename_keys(source['filename'], source['system'], card_data=system == 'ereader')
            identities = set().union(*(lookups['rom-filenames'][provider].get(k, set()) for k in keys if k.startswith('filename:')))
            method = 'provider-rom-filename'
            if not identities:
                identities = set().union(*(lookups['rom-filenames'][provider].get(k, set()) for k in keys if not k.startswith('filename:')))
                method = 'provider-card-identifier'
            if len(identities) == 1:
                found = {'status': 'unique', 'method': method, 'ids': sorted(identities)}
        if (matcher_version >= 4 and found['status'] in {'unmatched', 'loose-candidate'} and
                source.get('sourceKind') == 'program' and
                source['family'].casefold() not in {'download play', 'multiboot'}):
            query = release_lookup_title(source['title'])
            if query != source['title']:
                candidate = match(query, lookups[provider])
                if candidate['status'] in {'unmatched', 'loose-candidate'}:
                    identities = lookups['sequel-numbers'][provider].get(sequel_number_key(query), set())
                    if identities:
                        candidate = {'status': 'unique' if len(identities) == 1 else 'ambiguous',
                                     'method': 'catalogue-title-spelling', 'ids': sorted(identities)}
                if candidate['status'] in {'unique', 'ambiguous'}:
                    found = {**candidate, 'method': 'release-annotation-' + candidate['method'], 'lookupTitle': query}
        if matcher_version >= 4:
            found = qualified_alias(source, found, games[provider])
        if review and provider in review['providers']:
            candidate = review['providers'][provider]
            actual = games[provider].get(candidate['id'])
            if not actual or candidate['title'] != actual['title']:
                raise ValueError('Reviewed title alias has a foreign ID/title/platform')
            if (found['status'] == 'unique' and found['method'] in {'canonical','declared-alias'}
                    and found['ids'] != [candidate['id']]):
                raise ValueError('Reviewed alias conflicts with a unique exact title')
            found = {'status': 'unique', 'method': 'reviewed-scoped-alias',
                     'ids': [candidate['id']], 'reviewReason': review['reason']}
        if review and provider in review.get('blockedProviders', []):
            found = {'status': 'reviewed-provider-conflict', 'method': 'reviewed-provider-exclusion',
                     'ids': [], 'reviewReason': review['reason']}
        found['names'] = [games[provider][i]['title'] for i in found['ids']]
        matches[provider] = found
        if found['status'] == 'unique':
            game = games[provider][found['ids'][0]]
            providers[provider] = {**{k:v for k,v in game.items() if k not in {'aliases','aliasRegions','romNames'}},
                                   'method': 'exact-'+found['method']}
    blocked = set(review.get('blockedProviders', [])) if review else set()
    providers = corroborate_providers(providers, games['launchbox'],
        {} if 'launchbox' in blocked else lb_names,
        {} if 'screenscraper' in blocked else ss_names)
    if (matcher_version >= 3 and source.get('sourceKind') == 'program' and
            source['family'].casefold() not in {'download play', 'multiboot'}):
        # Preserve exact canonical corroboration first. Expanded spelling can
        # introduce another candidate; it must not invalidate an earlier proof.
        providers = corroborate_providers(providers, games['launchbox'],
            {} if 'launchbox' in blocked else lookups['spelling-lb-names'],
            {} if 'screenscraper' in blocked else lookups['spelling-ss-names'],
            title_normalizer=sequel_number_key)
    for provider, candidate in providers.items():
        game = games[provider][candidate['id']]
        providers[provider] = {**{k: v for k, v in game.items() if k not in {'aliases','aliasRegions','romNames'}}, **candidate}
    return matches, providers


def mapping(inventory_path, index_path, output, title_aliases=None):
    inventory_data, index = read(inventory_path), read(index_path)
    if index['inventorySha256'] != sha(inventory_path):
        raise ValueError('Indexes belong to another source census')
    rows, summaries, cache = [], {}, {}
    reviews = load_title_aliases(title_aliases)
    for source in inventory_data['rows']:
        system = source['system']
        matches, providers = resolve_source(source, index, cache, reviews, matcher_version=4)
        rows.append({**source, 'providers': providers, 'matches': matches,
            'status': 'bound-candidate' if providers else 'unresolved',
            'identityLevel': 'filename-title-candidate', 'physicalEditionVerified': False})
    for system, census in inventory_data['systems'].items():
        subset = [r for r in rows if r['system'] == system]
        count = len(subset)
        bound = sum(bool(r['providers']) for r in subset)
        summaries[system] = {**census, 'bound': bound, 'unresolved': count-bound,
            'percent': round(100*bound/count, 2) if count else None,
            'launchbox': sum('launchbox' in r['providers'] for r in subset),
            'screenscraper': sum('screenscraper' in r['providers'] for r in subset),
            'sourceKinds': dict(collections.Counter(r.get('sourceKind', 'program') for r in subset)),
            'modifiedSources': sum(r['modifiedContext'] for r in subset),
            'appUnsupportedContainers': sum(not r.get('appContainerSupported', True) for r in subset),
            'unresolvedReasons': dict(collections.Counter(
                'ambiguous' if any(m['status'] == 'ambiguous' for m in r['matches'].values()) else
                'spacing-review' if any(m['status'] == 'loose-candidate' for m in r['matches'].values()) else
                'no-exact-index-title' for r in subset if not r['providers']))}
    document = {'version': 1, 'matcherVersion': 4, 'scope': 'filename-catalogue-candidates',
        'inventoryPath': str(inventory_path), 'inventorySha256': sha(inventory_path),
        'indexPath': str(index_path), 'indexSha256': sha(index_path),
        **({'titleAliasesPath': str(title_aliases), 'titleAliasesSha256': sha(title_aliases)} if title_aliases else {}),
        'sourceCount': len(rows), 'bound': sum(bool(r['providers']) for r in rows),
        'romBodiesRead': 0, 'artworkDownloads': 0, 'screenScraperApiRequests': 0,
        'systems': summaries, 'rows': rows}
    write(output, document)
    print(json.dumps({'sources': len(rows), 'bound': document['bound'],
        'unresolved': len(rows)-document['bound'],
        'systems': {s: {k: v for k, v in d.items() if k in {'sources', 'bound', 'unresolved', 'percent'}}
                    for s, d in summaries.items() if d['sources']}}), flush=True)
    return document


def load_mapping(path):
    """Normal source lookup, verifying ownership and rejecting stale/foreign IDs."""
    document = read(path)
    if document.get('version') != 1 or document.get('scope') != 'filename-catalogue-candidates':
        raise ValueError('Unsupported filename binding format')
    matcher_version = document.get('matcherVersion', 1)
    if matcher_version not in {1, 2, 3, 4}:
        raise ValueError('Unsupported catalogue matcher version')
    inventory_path, index_path = Path(document['inventoryPath']), Path(document['indexPath'])
    if sha(inventory_path) != document['inventorySha256'] or sha(index_path) != document['indexSha256']:
        raise ValueError('Catalogue mapping input changed')
    inventory_data, index = read(inventory_path), read(index_path)
    alias_path = Path(document['titleAliasesPath']) if document.get('titleAliasesPath') else None
    if alias_path and sha(alias_path) != document.get('titleAliasesSha256'):
        raise ValueError('Reviewed title-alias input changed')
    reviews = load_title_aliases(alias_path)
    if (inventory_data['registrySha256'] != sha(REGISTRY) or
            inventory_data['supportedSystems'] != registry() or
            index['inventorySha256'] != sha(inventory_path)):
        raise ValueError('Catalogue mapping registry/census changed')
    if sha(index['launchbox']['path']) != index['launchbox']['sha256']:
        raise ValueError('LaunchBox source index changed')
    for source in index['screenscraperSources'].values():
        if sha(source['path']) != source['sha256']:
            raise ValueError('ScreenScraper source index changed')
    expected = {(r['system'], r['sourcePath']): r for r in inventory_data['rows']}
    if len(expected) != len(inventory_data['rows']):
        raise ValueError('Duplicate inventory source')
    result = {}
    cache = {}
    for row in document['rows']:
        key = row['system'], row['sourcePath']
        original = expected.get(key)
        if not original or key in result or any(row.get(k) != v for k, v in original.items()):
            raise ValueError('Filename binding source changed/duplicated')
        for provider, candidate in row['providers'].items():
            games = index['platforms'] if provider == 'launchbox' else index['screenscraper'] if provider == 'screenscraper' else None
            game = games.get(catalogue_namespace(row), {}).get(candidate['id']) if games else None
            if not game or any(candidate.get(k) != game.get(k) for k in ['id', 'title', 'platformId', 'platformName']):
                raise ValueError('Filename binding has a foreign provider ID')
        matches, providers = resolve_source(original, index, cache, reviews, matcher_version=matcher_version)
        if row['providers'] != providers or row['matches'] != matches:
            raise ValueError('Filename binding differs from exact index evidence')
        result[key] = row
    if set(result) != set(expected) or document['sourceCount'] != len(result):
        raise ValueError('Filename binding census incomplete')
    return result


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('inventory')
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--exclude-system', action='append', default=[])
    p = sub.add_parser('indexes')
    for key in ['inventory', 'launchbox', 'cache', 'output']:
        p.add_argument('--'+key, type=Path, required=True)
    p.add_argument('--existing-cache', type=Path)
    p = sub.add_parser('match')
    for key in ['inventory', 'index', 'output']:
        p.add_argument('--'+key, type=Path, required=True)
    p.add_argument('--title-aliases', type=Path)
    p = sub.add_parser('verify')
    p.add_argument('--mapping', type=Path, required=True)
    p.add_argument('--system')
    p.add_argument('--source-path')
    args = parser.parse_args()
    if args.command == 'inventory':
        inventory(args.root, args.output, args.exclude_system)
    elif args.command == 'indexes':
        indexes(args.inventory, args.launchbox, args.cache, args.output, args.existing_cache)
    elif args.command == 'match':
        mapping(args.inventory, args.index, args.output, args.title_aliases)
    else:
        rows = load_mapping(args.mapping)
        if args.system or args.source_path:
            print(json.dumps(rows[(args.system, args.source_path)], ensure_ascii=False))
        else:
            print(json.dumps({'verifiedSources': len(rows), 'bound': sum(bool(r['providers']) for r in rows.values())}))


if __name__ == '__main__':
    main()
