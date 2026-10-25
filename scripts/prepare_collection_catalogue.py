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
        stem = re.sub(r'^\d{4,5}\s+-\s+', '', stem)
    if system == 'n3ds':
        # Preserve the title ID in sourcePath, not as part of the game title.
        stem = re.sub(r'^0004[0-9a-fA-F]{12}\s+', '', stem)
        stem = re.sub(r'\.(?:piratelegit|legit|standard)$', '', stem, flags=re.I)
        stem = re.sub(r'\s*\((?:(?:CTR|KTR)-[A-Z]-[A-Z0-9]{4}(?:-\d{2})?|v\d[^)]*|[JUEKWT]+|DLC|Update)\)', '', stem)
    for group in re.finditer(r'\(([^)]*)\)', stem):
        if all(r.strip().casefold() in REGIONS for r in group[1].split(',')):
            return re.sub(r'\s+', ' ', stem[:group.start()]).strip()
    # Tags without a recognised region: remove only release annotations. A
    # parenthesised subtitle can be part of the title and must survive.
    stem = re.sub(r'\s*\[(?:!|n|b\d*|h[^]]*|t[^]]*|BIOS)\]', '', stem, flags=re.I)
    stem = re.sub(r'\s*\((?:Rev [^)]*|v\d[^)]*|Beta[^)]*|Proto[^)]*|Demo[^)]*|Unl|En(?:,[A-Z][a-z])+|Disc \d[^)]*)\)', '', stem)
    return re.sub(r'\s+', ' ', stem).strip()


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
                        'sourceKind': ('auxiliary-resource' if {'texture packs', 'textures'} & {p.casefold() for p in Path(relative).parts[:-1]} else
                            'firmware' if 'firmware' in {p.casefold() for p in Path(relative).parts[:-1]} or '[BIOS]' in name else
                            'dlc' if re.search(r'(?i)(?:^0004008c|\(DLC\))', name) else
                            'update' if re.search(r'(?i)(?:^0004000e|\(Update\))', name) else 'program'),
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
    settings = census['supportedSystems']
    active = {key: value for key, value in settings.items()
              if census['systems'][key]['sources']}
    platforms = collections.defaultdict(list)
    for system, config in active.items():
        for platform in config['launchbox']:
            platforms[platform].append(system)
    games = {key: {} for key in active}
    aliases = collections.defaultdict(set)
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
    for system in games:
        missing = set(active[system]['launchbox'])-observed
        if missing and not active[system].get('allowMissingLaunchbox'):
            raise ValueError('Unrecognised LaunchBox platform '+str(missing))
        for identity, game in games[system].items():
            game['aliases'] = sorted(aliases[identity]-{game['title'], ''})
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
    title = re.sub(r"(?<=\w)['’](?=\w)", '', title)
    article = re.match(r'^(.+?),\s*(le|la|les|der|die|das|el|los|las|il|lo|gli|un|une|des)(?=\s*(?:-|:|$))(.*)$', title, re.I)
    if article:
        title = article[2]+' '+article[1]+article[3]
    return normalized(title, word_boundaries=word_boundaries)


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


def source_games(source, provider, games):
    # Minis is an explicit source family and a separate LaunchBox namespace.
    # The parent app system remains PSP. Avoid duplicate-title cross-family IDs.
    if source['system'] == 'psp' and provider == 'launchbox':
        platform = 'Sony PSP Minis' if source['family'].casefold() == 'minis' else 'Sony PSP'
        return {key: game for key, game in games.items() if game['platformName'] == platform}
    if source['system'] == 'n64' and provider == 'launchbox':
        platform = 'Nintendo 64DD' if source['family'].casefold() == '64dd' else 'Nintendo 64'
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


def resolve_source(source, index, cache):
    """One cached resolver per platform/family, shared by producer and consumer."""
    from prepare_catalogue_bindings import corroborate_providers
    system = source['system']
    family = source['family'].casefold() if system in {'psp', 'n64'} else ''
    key = system, family
    if key not in cache:
        games = {provider: source_games(source, provider, systems[system]) for provider, systems in
                 [('launchbox', index['platforms']), ('screenscraper', index['screenscraper'])]}
        lookups = {provider: lookup(values) for provider, values in games.items()}
        lb_names, ss_names = {}, {}
        for identity, game in games['launchbox'].items():
            for title in [game['title'], *game['aliases']]:
                lb_names.setdefault(normalized(title, word_boundaries=True), set()).add(identity)
        for identity, game in games['screenscraper'].items():
            ss_names.setdefault(normalized(game['title'], word_boundaries=True), {})[identity] = game['title']
        cache[key] = games, lookups, lb_names, ss_names
    games, lookups, lb_names, ss_names = cache[key]
    matches, providers = {}, {}
    for provider in games:
        found = match(source['title'], lookups[provider])
        found['names'] = [games[provider][i]['title'] for i in found['ids']]
        matches[provider] = found
        if found['status'] == 'unique':
            game = games[provider][found['ids'][0]]
            providers[provider] = {**game, 'method': 'exact-'+found['method']}
            providers[provider].pop('aliases')
    providers = corroborate_providers(providers, games['launchbox'], lb_names, ss_names)
    for provider, candidate in providers.items():
        game = games[provider][candidate['id']]
        providers[provider] = {**{k: v for k, v in game.items() if k != 'aliases'}, **candidate}
    return matches, providers


def mapping(inventory_path, index_path, output):
    inventory_data, index = read(inventory_path), read(index_path)
    if index['inventorySha256'] != sha(inventory_path):
        raise ValueError('Indexes belong to another source census')
    rows, summaries, cache = [], {}, {}
    for source in inventory_data['rows']:
        system = source['system']
        matches, providers = resolve_source(source, index, cache)
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
    document = {'version': 1, 'scope': 'filename-catalogue-candidates',
        'inventoryPath': str(inventory_path), 'inventorySha256': sha(inventory_path),
        'indexPath': str(index_path), 'indexSha256': sha(index_path),
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
    inventory_path, index_path = Path(document['inventoryPath']), Path(document['indexPath'])
    if sha(inventory_path) != document['inventorySha256'] or sha(index_path) != document['indexSha256']:
        raise ValueError('Catalogue mapping input changed')
    inventory_data, index = read(inventory_path), read(index_path)
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
            game = games.get(row['system'], {}).get(candidate['id']) if games else None
            if not game or any(candidate.get(k) != game.get(k) for k in ['id', 'title', 'platformId', 'platformName']):
                raise ValueError('Filename binding has a foreign provider ID')
        matches, providers = resolve_source(original, index, cache)
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
        mapping(args.inventory, args.index, args.output)
    else:
        rows = load_mapping(args.mapping)
        if args.system or args.source_path:
            print(json.dumps(rows[(args.system, args.source_path)], ensure_ascii=False))
        else:
            print(json.dumps({'verifiedSources': len(rows), 'bound': sum(bool(r['providers']) for r in rows.values())}))


if __name__ == '__main__':
    main()
