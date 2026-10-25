"""Bind audited artwork candidates to captured collection editions.

The private JSON is not ROM-match evidence and never changes game information,
ratings or physical-edition classification. The normal packaging importer still
rechecks the current owner identity before accepting any acquired artwork.
"""
import argparse
import csv
import json
from pathlib import Path

SYSTEM_FOLDERS = {
    'gameandwatch': 'Nintendo - Game & Watch',
    'nes': 'Nintendo - Nintendo Entertainment System',
    'gba': 'Nintendo - Game Boy Advance',
}
def _screenscraper_systems():
    from prepare_collection_catalogue import registry
    return {key: value['screenscraperId'] for key, value in registry().items()}


SCREENSCRAPER_SYSTEMS = _screenscraper_systems()


def artifact_key(identity):
    return json.dumps(identity, sort_keys=True)


def corroborate_providers(providers, lb_games, lb_names, ss_names):
    """Fill a missing artwork provider from an exact, scoped declared name.

    Keys retain word boundaries, operators and non-Latin text. This does not
    create a match when neither provider already has an independent candidate.
    """
    from prepare_packaging_resources import normalized
    providers = dict(providers)
    if 'launchbox' not in providers and 'screenscraper' in providers:
        anchor = providers['screenscraper']
        key = normalized(anchor['title'], word_boundaries=True)
        candidates = lb_names.get(key, set())
        canonical = {i for i in candidates if
                     normalized(lb_games[i]['title'], word_boundaries=True) == key}
        selected = canonical or candidates
        if len(selected) == 1:
            identity = next(iter(selected))
            providers['launchbox'] = {'id': identity, 'title': lb_games[identity]['title'],
                'method': 'corroborated-exact-canonical' if canonical else 'corroborated-declared-alias',
                'corroboratedBy': {'provider': 'screenscraper', **anchor}}
    if 'screenscraper' not in providers and 'launchbox' in providers:
        anchor = providers['launchbox']
        candidates = ss_names.get(normalized(anchor['title'], word_boundaries=True), {})
        if len(candidates) == 1:
            identity, title = next(iter(candidates.items()))
            providers['screenscraper'] = {'id': identity, 'title': title,
                'method': 'corroborated-exact-canonical',
                'corroboratedBy': {'provider': 'launchbox', **anchor}}
    return providers


def census_selection(path, system):
    """Use the app's captured clean query rows without copying its live SQLite file."""
    from prepare_desktop_crawl_import import load_census
    games, editions, _ = load_census(path)
    metadata, selected = {}, []
    with path.open(encoding='utf8') as stream:
        for line in stream:
            row = json.loads(line)
            record = row.get('record')
            if row['kind'] == 'metadata' and record.get('providerId') == 'screenscraper':
                key = record['editionId']
                if key in metadata:
                    raise ValueError('Duplicate census metadata owner')
                metadata[key] = record
            if (row['kind'] == 'projection' and record.get('member') == 1 and
                    record.get('platform_id') == system):
                selected.append(record)
    result, seen = [], set()
    for row in selected:
        game, edition = games.get(row['game_id']), editions.get(row['edition_id'])
        record = metadata.get(row['edition_id'])
        if (not game or not edition or game.get('platformId') != system or
                edition.get('gameId') != game['id'] or row['edition_id'] in seen or
                (record and (record.get('gameId') != game['id'] or
                             record.get('platformId') != system))):
            raise ValueError('Inconsistent census collection identity')
        seen.add(row['edition_id'])
        result.append({**row, 'rank': None, 'score': None,
                       'game': game, 'edition': edition, 'metadata': record})
    return sorted(result, key=lambda r: r['edition_id'])


def retained_preparation(path, selection, system):
    """Keep complete, already reviewed packs in the delivery queue without reacquiring them."""
    from prepare_packaging_resources import file_sha256, owner_key, BOX_FACES
    document = json.loads(path.read_text(encoding='utf8'))
    for receipt in document['packs']:
        source = path.parent / receipt['file']
        if (source.name != receipt['file'] or source.stat().st_size != receipt['bytes'] or
                file_sha256(source) != receipt['sha256']):
            raise ValueError('Retained reviewed preparation pack changed')
    selected = {(r['game']['id'], r['edition']['id']): r for r in selection}
    result = {}
    required = {'box-2D', 'box-2D-back', 'box-2D-side', *('outer-box-'+f for f in BOX_FACES)}
    for game in document['games']:
        row = selected.get((game['gameId'], game['editionId']))
        if row is None:
            continue
        roles = [r['type'] for r in game['resources']]
        if (game['identityKey'] != owner_key(row['game'], row['edition']) or
                row['game']['platformId'] != system or len(roles) != len(set(roles)) or
                not required <= set(roles) or game['editionId'] in result):
            raise ValueError('Retained reviewed preparation identity or roles changed')
        result[game['editionId']] = game
    return result


def load_bindings(path, census, launchbox, selection, system):
    """Reject stale input before opening an acquisition session."""
    from prepare_desktop_crawl_import import load_census
    from prepare_packaging_resources import file_sha256, owner_key
    document = json.loads(path.read_text(encoding='utf8'))
    if document.get('version') != 1 or document.get('scope') != 'artwork-candidates':
        raise ValueError('Unsupported catalogue binding document')
    if not census or document.get('censusSha256') != file_sha256(census):
        raise ValueError('Catalogue binding census changed')
    if document.get('launchboxIndexSha256') != file_sha256(launchbox):
        raise ValueError('Catalogue binding LaunchBox index changed')
    games, editions, artifacts = load_census(census)
    result = {}
    for binding in document['bindings']:
        platform, game_id, edition_id = (binding.get(k) for k in
                                        ['platform', 'gameId', 'editionId'])
        game, edition = games.get(game_id), editions.get(edition_id)
        source = binding.get('artifact')
        if (not game or not edition or game.get('platformId') != platform or
                edition.get('gameId') != game_id or
                binding.get('identityKey') != owner_key(game, edition) or
                not source or artifacts.get(artifact_key(source['id'])) != source or
                source['id'] not in [m['artifactId'] for m in edition.get('members', [])]):
            raise ValueError('Catalogue binding identity or source changed')
        namespace = binding.get('cataloguePlatform')
        if namespace != platform and (platform, namespace) != ('nes', 'fds'):
            raise ValueError('Catalogue binding platform mismatch')
        for provider, candidate in binding.get('providers', {}).items():
            if (provider not in {'launchbox', 'screenscraper'} or
                    not str(candidate.get('id', '')).isdigit() or
                    not candidate.get('title') or not candidate.get('method')):
                raise ValueError('Invalid catalogue binding provider')
            if (provider == 'screenscraper' and candidate.get('platformId') !=
                    SCREENSCRAPER_SYSTEMS.get(namespace)):
                raise ValueError('ScreenScraper catalogue binding platform mismatch')
        if platform != system:
            continue
        key = (game_id, edition_id)
        if key in result:
            previous = result[key]
            # Several source members may share one edition, but must agree.
            if any(previous[k] != binding[k] for k in ['providers', 'cataloguePlatform', 'identityKey']):
                raise ValueError('Conflicting catalogue bindings for one edition')
        result[key] = binding
    for row in selection:
        binding = result.get((row['game']['id'], row['edition']['id']))
        if binding and binding['identityKey'] != owner_key(row['game'], row['edition']):
            raise ValueError('Selected edition differs from catalogue binding identity')
    return result


def prepare(audit_path, census_path, launchbox, title_index, manual_path, output):
    """Account for every audited filename without reading any ROM bodies."""
    from prepare_desktop_crawl_import import load_census
    from prepare_packaging_resources import file_sha256, owner_key, normalized
    games, editions, artifacts = load_census(census_path)
    index = json.loads(title_index.read_text(encoding='utf8'))
    index_hash = file_sha256(launchbox)
    if index.get('source', {}).get('sha256') != index_hash:
        raise ValueError('Audited title index does not own the LaunchBox ZIP')
    ss_indexes, ss_hashes, ss_names, lb_names = {}, {}, {}, {}
    for namespace, entries in index['platforms'].items():
        lb_names[namespace] = {}
        for identity, game in entries.items():
            for name in [game['title'], *game['aliases']]:
                lb_names[namespace].setdefault(normalized(name, word_boundaries=True), set()).add(identity)
    for namespace in SCREENSCRAPER_SYSTEMS:
        source = title_index.parent / f'screenscraper-{namespace}-gameslist.csv'
        if source.exists():
            with source.open(encoding='utf-8-sig', newline='') as stream:
                entries = list(csv.DictReader(stream, delimiter=';', quotechar='"'))
            ss_indexes[namespace] = {r['Game ID']: r['Game Name'] for r in entries}
            if len(ss_indexes[namespace]) != len(entries):
                raise ValueError('Duplicate ScreenScraper public index ID')
            ss_hashes[namespace] = file_sha256(source)
            ss_names[namespace] = {}
            for identity, title in ss_indexes[namespace].items():
                ss_names[namespace].setdefault(normalized(title, word_boundaries=True), {})[identity] = title
    manual = json.loads(manual_path.read_text(encoding='utf8')) if manual_path else {'overrides': []}
    if manual.get('version', 1) != 1:
        raise ValueError('Unsupported manual binding review')
    overrides = {}
    for review in manual['overrides']:
        key = (review['platform'], review['archive'])
        if key in overrides or not review.get('reason') or not review.get('sourceSha256'):
            raise ValueError('Duplicate or incomplete manual review')
        proof = Path(review['evidencePath'])
        if file_sha256(proof) != review['evidenceSha256']:
            raise ValueError('Manual binding evidence changed')
        overrides[key] = review
    by_path, by_member = {}, {}
    for artifact in artifacts.values():
        by_path.setdefault(artifact['displayPath'], []).append(artifact)
    for edition in editions.values():
        for member in edition.get('members', []):
            by_member.setdefault(artifact_key(member['artifactId']), []).append(edition)
    active = set()
    with census_path.open(encoding='utf8') as stream:
        for line in stream:
            row = json.loads(line)
            if row['kind'] == 'cache' and row['record'].get('artifact_key'):
                active.add(tuple(json.loads(row['record']['artifact_key'])))
    def is_active(artifact):
        identity = artifact['id']
        return tuple(identity[k] for k in ['providerId', 'sourceId', 'accountId', 'providerFileId']) in active
    bindings, unresolved, consumed = [], [], set()
    audited = json.loads(audit_path.read_text(encoding='utf8'))
    seen = set()
    for row in audited:
        platform, archive = row['system'], row['filename']
        key = (platform, archive)
        if key in seen:
            raise ValueError('Duplicate audited source')
        seen.add(key)
        candidates = [a for a in by_path.get(SYSTEM_FOLDERS[platform]+'/'+archive, []) if is_active(a)]
        if len(candidates) != 1:
            raise ValueError('Audited source lacks a unique current artifact: '+str(key))
        artifact = candidates[0]
        owners = by_member.get(artifact_key(artifact['id']), [])
        if len(owners) != 1:
            raise ValueError('Audited source lacks a unique current edition: '+str(key))
        edition = owners[0]
        game = games[edition['gameId']]
        if game['platformId'] != platform:
            raise ValueError('Audited source platform differs from current edition')
        namespace = row.get('catalogueSystem', platform)
        providers = {}
        for provider, audit_provider in [('launchbox', 'launchbox'),
                ('screenscraper', 'screenscraper-with-retained-aliases')]:
            match = row['matches'][audit_provider]
            if match['status'] == 'unique' and len(match['ids']) == 1:
                providers[provider] = {'id': str(match['ids'][0]),
                    'title': match['names'][0], 'method': 'audited-'+match['method']}
        if key in overrides:
            review = overrides[key]
            if artifact.get('providerChecksums', {}).get('sha256') != review['sourceSha256']:
                raise ValueError('Manual binding archive checksum changed: '+archive)
            providers.update(review['providers'])
            consumed.add(key)
        providers = corroborate_providers(providers, index['platforms'][namespace],
            lb_names[namespace], ss_names.get(namespace, {}))
        if 'launchbox' in providers:
            candidate = providers['launchbox']
            actual = index['platforms'][namespace].get(candidate['id'])
            if not actual or candidate['title'].strip() != actual['title'].strip():
                raise ValueError('LaunchBox binding ID/title is not in the audited platform')
        if 'screenscraper' in providers:
            candidate = providers['screenscraper']
            actual = ss_indexes.get(namespace, {}).get(candidate['id'])
            if not actual or candidate['title'].strip().casefold() != actual.strip().casefold():
                raise ValueError('ScreenScraper binding ID/title is not in the audited platform')
            candidate['platformId'] = SCREENSCRAPER_SYSTEMS[namespace]
        record = {'platform': platform, 'gameId': game['id'], 'editionId': edition['id'],
            'identityKey': owner_key(game, edition), 'archive': archive, 'artifact': artifact,
            'cataloguePlatform': namespace, 'family': row.get('family'),
            'modifiedContext': row.get('modifiedContext', False), 'providers': providers}
        if key in overrides:
            record['review'] = overrides[key]
        if providers:
            bindings.append(record)
        else:
            unresolved.append({**record, 'matches': row['matches'], 'reason': 'no-unique-reviewed-candidate'})
    if consumed != set(overrides):
        raise ValueError('Manual review references a source absent from the audit')
    document = {'version': 1, 'scope': 'artwork-candidates', 'launchboxIndexSha256': index_hash,
        'censusSha256': file_sha256(census_path), 'auditSha256': file_sha256(audit_path),
        'titleIndexSha256': file_sha256(title_index),
        'screenscraperIndexSha256': ss_hashes,
        'manualSha256': file_sha256(manual_path) if manual_path else None,
        'sourceCount': len(audited), 'bindings': bindings, 'unresolved': unresolved}
    with output.open('x', encoding='utf8') as stream:
        json.dump(document, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'sources': len(audited), 'bindings': len(bindings),
        'unresolved': len(unresolved), 'manual': len(consumed), 'resourceAcceptance': False}))


def promote_filename_mapping(mapping_path, census_path, launchbox, output):
    """Join the prepared desktop map to real owners when their census is available.

    Missing native owners stay unpromoted, rather than fabricating game/edition
    IDs or requiring a device for the filename-only mapping outcome.
    """
    from prepare_collection_catalogue import load_mapping, read, sha
    from prepare_desktop_crawl_import import load_census
    from prepare_packaging_resources import owner_key
    sources = load_mapping(mapping_path)
    mapping_document = read(mapping_path)
    index = read(mapping_document['indexPath'])
    if sha(launchbox) != index['launchbox']['sha256']:
        raise ValueError('Filename map uses another LaunchBox index')
    games, editions, artifacts = load_census(census_path)
    owners, paths = {}, {}
    for edition in editions.values():
        for member in edition.get('members', []):
            owners.setdefault(artifact_key(member['artifactId']), []).append(edition)
    active = set()
    with census_path.open(encoding='utf-8') as stream:
        for line in stream:
            envelope = json.loads(line)
            if envelope['kind'] == 'cache' and envelope['record'].get('artifact_key'):
                active.add(tuple(json.loads(envelope['record']['artifact_key'])))
    for artifact in artifacts.values():
        identity = artifact['id']
        key = tuple(identity[k] for k in ['providerId', 'sourceId', 'accountId', 'providerFileId'])
        if key in active:
            paths.setdefault(artifact['displayPath'], []).append(artifact)
    bindings, unresolved, unpromoted = [], [], []
    for (system, source_path), source in sources.items():
        if source.get('sourceKind', 'program') != 'program':
            unpromoted.append({'platform': system, 'sourcePath': source_path,
                               'reason': 'not-a-program-artwork-owner:'+source['sourceKind']})
            continue
        candidates = paths.get(source_path, [])
        if not candidates:
            unpromoted.append({'platform': system, 'sourcePath': source_path,
                               'reason': 'no-current-census-artifact'})
            continue
        if len(candidates) != 1:
            raise ValueError('Filename map has multiple current artifacts: '+source_path)
        artifact = candidates[0]
        members = owners.get(artifact_key(artifact['id']), [])
        if len(members) != 1:
            raise ValueError('Filename map lacks a unique edition: '+source_path)
        edition = members[0]
        game = games[edition['gameId']]
        if game['platformId'] != system:
            raise ValueError('Filename map owner platform differs: '+source_path)
        record = {'platform': system, 'gameId': game['id'], 'editionId': edition['id'],
            'identityKey': owner_key(game, edition), 'archive': source['filename'],
            'artifact': artifact, 'cataloguePlatform': system, 'family': source['family'],
            'modifiedContext': source['modifiedContext'], 'providers': source['providers']}
        if source['providers']:
            bindings.append(record)
        else:
            unresolved.append({**record, 'matches': source['matches'], 'reason': 'no-unique-reviewed-candidate'})
    document = {'version': 1, 'scope': 'artwork-candidates',
        'launchboxIndexSha256': sha(launchbox), 'censusSha256': sha(census_path),
        'filenameMappingSha256': sha(mapping_path), 'titleIndexSha256': sha(mapping_document['indexPath']),
        'sourceCount': len(sources), 'bindings': bindings, 'unresolved': unresolved,
        'unpromotedSources': unpromoted}
    with output.open('x', encoding='utf-8') as stream:
        json.dump(document, stream, ensure_ascii=False, indent=2)
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['census', 'launchbox', 'output']:
        parser.add_argument('--'+name, required=True, type=Path)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--audit', type=Path)
    source.add_argument('--filename-mapping', type=Path)
    parser.add_argument('--title-index', type=Path)
    parser.add_argument('--manual', type=Path)
    args = parser.parse_args()
    if args.filename_mapping:
        if args.title_index or args.manual:
            parser.error('--filename-mapping already owns its index and decisions')
        result = promote_filename_mapping(args.filename_mapping, args.census, args.launchbox, args.output)
        print(json.dumps({'sources': result['sourceCount'], 'bindings': len(result['bindings']),
                          'unpromoted': len(result['unpromotedSources'])}))
    else:
        if not args.title_index:
            parser.error('--audit requires --title-index')
        prepare(args.audit, args.census, args.launchbox, args.title_index, args.manual, args.output)


if __name__ == '__main__':
    main()
