"""Prepare bounded import packs from completed Windows archive-crawl receipts.

Uses an immutable read-only catalogue census. The app rechecks current identities,
artifacts and provider matches before normal Drive publication. This script never
writes Drive, edits app databases, imports classifications or counts acceptance.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile
from PIL import Image
from prepare_packaging_resources import owner_key, artwork_quality


def digest(body):
    return hashlib.sha256(body).hexdigest()


def load_census(path):
    games, editions, artifacts = {}, {}, {}
    count, end = 0, None
    with path.open(encoding='utf8') as stream:
        for line in stream:
            if end is not None:
                raise ValueError('Census has data after end')
            row = json.loads(line)
            kind, value = row['kind'], row.get('record')
            if count == 0 and (kind != 'snapshot' or value !=
                    {'editionDirty': 0, 'cacheDirty': 0, 'readOnly': True}):
                raise ValueError('A clean read-only catalogue census is required')
            if kind == 'game': games[value['id']] = value
            if kind == 'edition': editions[value['id']] = value
            if kind == 'artifact': artifacts[json.dumps(value['id'], sort_keys=True)] = value
            if kind == 'end': end = row
            else: count += 1
    if not end or end.get('rows') != count:
        raise ValueError('Incomplete catalogue census')
    return games, editions, artifacts


def prepare(census, manifest_path, crawl, output, *, reuse_lookup=False,
            review_holds=None, edition_ids=None):
    games, editions, artifacts = load_census(census)
    manifest_bytes = manifest_path.read_bytes()
    manifest_hash = digest(manifest_bytes)
    manifest = json.loads(manifest_bytes)
    if manifest.get('version') != 1:
        raise ValueError('Unsupported crawl manifest')
    selection = None
    if edition_ids is not None:
        selection = set(edition_ids)
        known = {item['request']['editionId'] for item in manifest['items']}
        if (not selection or len(selection) != len(edition_ids) or
                not selection <= known or not selection <= editions.keys()):
            raise ValueError('Invalid current manifest edition selection')
    all_item_keys = {digest(json.dumps(item, ensure_ascii=False, separators=(',', ':')).encode())
                     for item in manifest['items']}
    selected_items = [item for item in manifest['items']
                      if selection is None or item['request']['editionId'] in selection]
    selected_keys = {digest(json.dumps(item, ensure_ascii=False, separators=(',', ':')).encode())
                     for item in selected_items}
    checkpoint = json.loads((crawl/'checkpoint.json').read_text(encoding='utf8'))
    if checkpoint.get('version') != 2 or checkpoint.get('manifestSha256') != manifest_hash:
        raise ValueError('Crawl checkpoint does not own this manifest')
    held_sources = {}
    if review_holds is not None:
        reviewed = json.loads(review_holds.read_text(encoding='utf8'))
        if reviewed.get('version') != 1 or not isinstance(reviewed.get('holds'), list):
            raise ValueError('Invalid provider identity reviews')
        for hold in reviewed['holds']:
            key, source_hash, reason = (hold.get(field) for field in
                                          ['key', 'sourceSha256', 'reason'])
            if (not isinstance(key, str) or not isinstance(source_hash, str) or
                    any(len(value) != 64 or any(c not in '0123456789abcdef'
                        for c in value) for value in [key, source_hash]) or
                    not isinstance(reason, str) or not reason.strip() or
                    key in held_sources or checkpoint['items'].get(key) != 'matched'):
                raise ValueError('Invalid or unowned provider identity review')
            held_sources[key] = hold
    if not held_sources.keys() <= all_item_keys:
        raise ValueError('Provider identity review is outside the manifest')
    consumed_holds = set()
    candidates = []
    quality_holds = []
    for item in selected_items:
        # Match crawlItemKey: the complete ordered item, including its artifact.
        key = digest(json.dumps(item, ensure_ascii=False, separators=(',', ':')).encode())
        if key not in checkpoint['items']:
            continue
        if checkpoint['items'][key] != 'matched': continue
        source = crawl/(key+'.json')
        source_body = source.read_bytes()
        row = json.loads(source_body)
        if key in held_sources:
            hold = held_sources[key]
            if digest(source_body) != hold['sourceSha256']:
                raise ValueError('Reviewed source changed')
            quality_holds.append({'key': key, 'editionId': item['request']['editionId'],
                                 'kind': 'providerIdentityReview', **hold})
            consumed_holds.add(key)
            continue
        request = row['request']
        edition = editions.get(request['editionId'])
        game = games.get(request['gameId'])
        artifact = item.get('archive', {}).get('artifact')
        if (row.get('version') != 2 or row.get('manifestSha256') != manifest_hash or
                row.get('key') != key or row.get('status') != 'matched' or
                row.get('archiveReadStatus') != 'validated' or not edition or not game or
                edition['gameId'] != game['id'] or game.get('platformId') != request['platformId'] or
                request['platformId'] not in {'nes', 'gba'} or not item.get('allowRawBinding') or
                not artifact or artifacts.get(json.dumps(artifact['id'], sort_keys=True)) != artifact or
                len(edition['members']) != 1 or edition['members'][0]['artifactId'] != artifact['id']):
            raise ValueError('Completed result no longer owns the captured source')
        observation = row['archiveObservation']
        if observation['raw'] != request['romIdentifier'] or observation['container']['sizeBytes'] != artifact['sizeBytes']:
            raise ValueError('Raw/archive proof changed')
        for algorithm, value in artifact['providerChecksums'].items():
            if algorithm in {'md5','sha1','sha256'} and observation['container'].get(algorithm) != value:
                raise ValueError('Archive checksum differs from captured Drive artifact')
        artwork, bodies, outcomes = [], {}, []
        for resource in row.get('artwork', []):
            outcome={k:resource[k] for k in ['media','status']}
            if resource.get('status') != 'matched':
                outcomes.append(outcome)
                continue
            sha = resource['sha256']
            if len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha) or resource['file'] != sha+'.png':
                raise ValueError('Invalid content-addressed artwork path')
            body = (crawl/resource['file']).read_bytes()
            if len(body) != resource['bytes'] or len(body) > 4*1024*1024 or digest(body) != sha:
                raise ValueError('Completed artwork body changed')
            with Image.open(io.BytesIO(body)) as image:
                if image.format != 'PNG' or max(image.size) > 1024 or getattr(image,'n_frames',1) != 1:
                    raise ValueError('Artwork is not normalized static PNG')
                image.verify()
            quality=artwork_quality(body)
            if quality['contentStatus'] != 'nonuniform':
                outcome.update(status='needsReview',providerStatus='matched',
                    sha256=sha,bytes=len(body),reason=quality['contentStatus'])
                outcomes.append(outcome)
                quality_holds.append({'key':key,**outcome})
                continue
            outcomes.append(outcome)
            artwork.append({k:resource[k] for k in ['media','sha256','bytes']})
            bodies[sha] = crawl/resource['file']  # re-read at pack time; bounds memory
        lookup = None
        if reuse_lookup:
            record = row.get('record')
            if (not isinstance(record,dict) or record.get('gameId') != game['id'] or
                    record.get('editionId') != edition['id'] or
                    record.get('platformId') != request['platformId'] or
                    record.get('providerId') != 'screenscraper' or
                    record.get('matchMethod') != 'rawRomHashAndSize'):
                raise ValueError('Captured exact provider response is unavailable')
            lookup = {'request':request,'record':{**record,'ratings':[]},
                      'officialRomEvidence':row.get('officialRomEvidence'),
                      'artworkOutcomes':outcomes}
            if len(json.dumps(lookup,ensure_ascii=False).encode()) > 60*1024:
                raise ValueError('Captured provider response exceeds evidence budget')
        candidates.append(({'gameId':game['id'], 'editionId':edition['id'], 'platformId':request['platformId'],
            'identityKey':owner_key(game, edition, 'screenscraper'), 'artifact':artifact,
            'observation':observation, 'artwork':artwork,
            **({'lookup':lookup} if lookup is not None else {})}, bodies))
    if not candidates:
        raise ValueError('No completed archive-bound results are available')
    if consumed_holds != held_sources.keys() & selected_keys:
        raise ValueError('Provider identity review is outside the manifest')
    output.mkdir(parents=True, exist_ok=True)
    for offset in range(0,len(candidates),25):
        target=output/f'desktop-resources-{offset//25+1:04}.zip'
        if target.exists(): raise FileExistsError(target)
    packs = []
    for offset in range(0,len(candidates),25):
        group = candidates[offset:offset+25]
        target = output/f'desktop-resources-{offset//25+1:04}.zip'
        with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_STORED) as archive:
            archive.writestr('packaging.json',json.dumps({'version':1,'kind':'desktopArchiveEvidence',
                **({'reuseProviderResponse':True} if reuse_lookup else {}),
                'games':[g for g,_ in group]},ensure_ascii=False,separators=(',',':')))
            bodies = {sha:path for _, images in group for sha,path in images.items()}
            for sha,path in sorted(bodies.items()):
                body = path.read_bytes()
                if digest(body) != sha: raise ValueError('Completed artwork body changed')
                archive.writestr('images/'+sha+'.png',body)
        packs.append({'file':target.name,'games':len(group),'sha256':digest(target.read_bytes())})
    receipt={'manifestSha256':manifest_hash,'censusSha256':digest(census.read_bytes()),
        'capturedCheckpoint':checkpoint,'preparedGames':len(candidates),'published':False,'nativeAccepted':False,
        'qualityHolds':quality_holds,'packs':packs}
    if selection is not None:
        receipt.update(selectionScope='selected-editions', editionFilter=sorted(selection),
            manifestItems=len(manifest['items']), selectedManifestItems=len(selected_items),
            unselectedProviderIdentityHolds=[held_sources[key] for key in sorted(held_sources.keys()-selected_keys)])
    (output/'preparation.json').write_text(json.dumps(receipt,indent=2),encoding='utf8')
    return {'preparedGames':len(candidates),'packs':len(packs),'published':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--census',type=Path,required=True)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--crawl',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--reuse-lookup',action='store_true',
        help='Retain exact completed Windows provider responses; import without another API lookup')
    parser.add_argument('--review-holds', type=Path,
        help='Exclude source-hash-bound provider identity conflicts from import')
    parser.add_argument('--edition-id', dest='edition_ids', action='append',
        help='Prepare an explicit current-manifest delta while retaining the full checkpoint')
    args=parser.parse_args()
    print(json.dumps(prepare(args.census,args.manifest,args.crawl,args.output,
        reuse_lookup=args.reuse_lookup, review_holds=args.review_holds,
        edition_ids=args.edition_ids)))


if __name__=='__main__': main()
