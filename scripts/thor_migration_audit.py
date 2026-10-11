"""Read-only S7 SD/cloud-cache audit. This command cannot remove or adopt files.

Writes a PRIVATE exclusive-create JSONL observation journal, outside the repo.
Cached Drive checksums are comparison evidence, never current recovery authority.
An interrupted journal lacks its terminal summary and must not be called complete.
Use --inventory-only to record local paths/stats without reading the catalogue or
ROM bodies. It supplies no cloud/recovery evidence and still preserves every file.
An optional --retention-helper joins exact artifact identities to the normal
canonical Top-25 query. This is a private review, not removal authorization.
"""
import argparse
import collections
import datetime
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import subprocess

GATES = ["canonical_identity_review", "defensible_retention",
         "live_cloud_revalidation", "tested_restore", "save_sync_safety",
         "execution_time_local_revalidation"]
MAX_RETAINED_ARTIFACT_BYTES = 16 * 1048576
MAX_RETENTION_MEMBERS = 100000  # Same supported catalogue bound as cloud_snapshot.
MAX_RETENTION_IDENTITY_BYTES = 16 * 1048576
MAX_RETAINED_RETENTION_BYTES = 16 * 1048576


def checked_relative_path(path, root):
    if not path.startswith('/') or not root.startswith('/'):
        raise ValueError('Absolute device paths required')
    if any(part in ('.', '..') for part in path.split('/') + root.split('/')):
        raise ValueError('Unnormalized path')
    relative = PurePosixPath(path).relative_to(PurePosixPath(root))
    if str(relative) == '.':
        raise ValueError('Root is not a file')
    return str(relative)


def compare_observation(local, candidates):
    result = {"disposition": "preserve", "removalAuthorized": False,
              "remainingGates": list(GATES)}
    candidates = [c for c in candidates if c['displayName'] == local['name']]
    if not local['stable']:
        reason = 'local_changed'
    elif not candidates:
        reason = 'no_cloud_candidate'
    elif len(candidates) != 1:
        reason = 'ambiguous_cloud_candidates'
    else:
        cloud = candidates[0]
        md5 = cloud.get('providerChecksums', {}).get('md5')
        identity = cloud.get('id') or {}
        has_identity = all(isinstance(identity.get(k), str) and identity[k]
                           for k in ('providerId', 'sourceId', 'accountId', 'providerFileId'))
        if (not has_identity or not cloud.get('version') or not cloud.get('canDownload') or
                type(cloud.get('sizeBytes')) is not int or cloud['sizeBytes'] < 0 or
                not isinstance(md5, str) or not re.fullmatch(r'[0-9a-fA-F]{32}', md5)):
            reason = 'cloud_evidence_incomplete'
        elif local['sizeBytes'] != cloud['sizeBytes']:
            reason = 'size_mismatch'
        elif local.get('md5') != md5.lower():
            reason = 'digest_mismatch'
        else:
            reason = 'cached_digest_match'
    result['comparison'] = reason
    return result


def review_retention(local, candidates, snapshot):
    """Join only identical cached bytes to exact ranked artifact bindings.

    Rankings are observations, not a grant to adopt/delete files. All existing
    current-cloud, restore, save/sync and execution-time checks remain required.
    """
    candidates = [c for c in candidates if c['displayName'] == local['name']]
    result = compare_observation(local, candidates)
    provisional = (snapshot['ranked_games'] < snapshot['collection_games'] or
                   snapshot['unbound_artifacts'] > 0 or
                   snapshot['dirty_editions'] > 0 or snapshot['dirty_artifacts'] > 0)
    retention = {'disposition': 'preserve', 'provisional': provisional,
                 'reason': 'cloud_binding_unverified'}
    result['retention'] = retention
    if result['comparison'] != 'cached_digest_match':
        return result
    identity = candidates[0]['id']
    key = json.dumps([identity['providerId'], identity['sourceId'],
                      identity['accountId'], identity['providerFileId']],
                     separators=(',', ':'), ensure_ascii=False)
    members = [m for m in snapshot['members'] if m.get('artifact_key') == key]
    if not members:
        retention['reason'] = 'canonical_binding_missing'
        return result
    groups = {m['group_key'] for m in members}
    games = {m['game_id'] for m in members}
    ranks = {m['canonical_rank'] for m in members}
    if len(groups) != 1 or len(games) != 1 or len(ranks) != 1:
        retention['reason'] = 'canonical_binding_conflict'
        return result
    rank = next(iter(ranks))
    retention.update(groupKey=next(iter(groups)), gameId=next(iter(games)),
                     editionIds=sorted({m['edition_id'] for m in members}),
                     canonicalRank=rank)
    if any(snapshot[f] > 0 for f in ('dirty_editions', 'dirty_artifacts')):
        retention['reason'] = 'projection_incomplete'
    elif rank is not None and rank <= 25:
        retention.update(disposition='keep', reason='observed_top25_member')
        result['disposition'] = 'keep'
    else:
        # Revision 19 permits exact unrated members to be cloud-only. Coverage
        # remains provisional; it is not a per-file recovery/removal permission.
        retention.update(disposition='outside_sample', reason=(
            'observed_unrated_member' if rank is None else 'observed_outside_top25'))
    return result


class Device:
    def __init__(self, adb, serial, package, cache_helper=None, retention_helper=None):
        self.prefix = [adb, '-s', serial]
        self.package = package
        for helper in (cache_helper, retention_helper):
            if helper is not None and not re.fullmatch(
                    r'/data/local/tmp/[A-Za-z0-9_.-]+\.jar', helper):
                raise ValueError('An exact prepared native helper path is required')
        self.cache_helper = cache_helper
        self.retention_helper = retention_helper

    def shell(self, command):
        return self._read(self.prefix + ['exec-out', 'sh', '-c', command], 8 * 1048576)

    def private(self, path, limit):
        return self._read(self.prefix + ['exec-out', 'run-as', self.package, 'cat', path], limit)

    def cache_snapshot(self, platform, after=0):
        if (not self.cache_helper or not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,63}', platform)
                or type(after) is not int or not 0 <= after < 1 << 63):
            raise ValueError('Prepared native cache helper, platform and row cursor required')
        command = ('CLASSPATH=' + self.cache_helper +
                   ' app_process -Xmx128m /system/bin RShopMigrationCacheSnapshot ' + platform + ' ' + str(after))
        return self._read(self.prefix + ['exec-out', 'run-as', self.package,
                                        'sh', '-c', command], 1048576)

    def retention_page(self, platform, offset):
        if (not self.retention_helper or
                not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,63}', platform) or
                type(offset) is not int or not 0 <= offset <= MAX_RETENTION_MEMBERS):
            raise ValueError('Prepared native retention helper and bounded page required')
        command = ('CLASSPATH=' + self.retention_helper +
                   ' app_process -Xmx128m /system/bin RShopRetentionSnapshot ' + platform + ' ' + str(offset))
        return self._read(self.prefix + ['exec-out', 'run-as', self.package,
                                        'sh', '-c', command], 1048576)

    def _read(self, command, limit):
        # Bound the reader itself; neither ROM bytes nor unbounded fixture output
        # enters this process. Only private config/catalogue metadata is read.
        process = subprocess.Popen(command, stdout=subprocess.PIPE)
        data = bytearray()
        try:
            while chunk := process.stdout.read(65536):
                data.extend(chunk)
                if len(data) > limit:
                    raise ValueError('Device observation exceeds audit buffer limit')
            if process.wait() != 0:
                raise ValueError('Private metadata read failed')
            return bytes(data)
        except BaseException:
            # Only this command's read-only adb client, never the app or other work.
            if process.poll() is None:
                process.terminate()
            process.wait()
            raise
        finally:
            process.stdout.close()


def retention_snapshot(device, platform, artifact_keys=None):
    """Bounded observational pages; execution must revalidate actual membership.

    Summary changes abort this review. Unchanged counts alone do NOT prove an
    atomic snapshot across pages; the journal records this limit explicitly.
    """
    fields = ('collection_games', 'ranked_games', 'total_members',
              'unbound_artifacts', 'dirty_editions', 'dirty_artifacts')
    if artifact_keys is not None:
        artifact_keys = set(artifact_keys)
        if (any(not isinstance(key, str) or not key or
                len(key.encode('utf-8')) > 4096 for key in artifact_keys) or
                sum(len(key.encode('utf-8')) for key in artifact_keys) >
                MAX_RETAINED_RETENTION_BYTES):
            raise ValueError('Retention requested identity bound exceeded')
    result = None
    offset = 0
    identity_bytes = retained_bytes = 0
    editions = set()
    while True:
        payload = device.retention_page(platform, offset)
        if len(payload) > 1048576:
            raise ValueError('Retention page exceeds buffer limit')
        page = json.loads(payload)
        if (not isinstance(page, dict) or page.get('schema') != 'rshop.s7.retention.v2' or
                page.get('platform') != platform or page.get('offset') != offset or
                page.get('readOnly') is not True or page.get('removalAuthorized') is not False or
                any(type(page.get(f)) is not int or page[f] < 0 for f in fields) or
                page['total_members'] > MAX_RETENTION_MEMBERS or
                page['collection_games'] > page['total_members'] or
                page['ranked_games'] > page['collection_games'] or
                not isinstance(page.get('members'), list) or len(page['members']) > 128):
            raise ValueError('Invalid bounded retention observation')
        if result is None:
            result = {f: page[f] for f in fields}
            result.update(platform=platform, members=[])
        elif any(page[f] != result[f] for f in fields):
            raise ValueError('Retention summary changed during review')
        for member in page['members']:
            if (not isinstance(member, dict) or
                    any(not isinstance(member.get(f), str) or not member[f] or
                        len(member[f].encode('utf-8')) > 4096
                        for f in ('edition_id', 'game_id', 'group_key')) or
                    member['edition_id'] in editions or
                    'artifact_key' not in member or
                    (member['artifact_key'] is not None and
                     (not isinstance(member['artifact_key'], str) or
                      len(member['artifact_key'].encode('utf-8')) > 4096)) or
                    'canonical_rank' not in member or
                    (member['canonical_rank'] is not None and
                     (type(member['canonical_rank']) is not int or
                      not 1 <= member['canonical_rank'] <= page['ranked_games']))):
                raise ValueError('Invalid or repeated retention binding')
            editions.add(member['edition_id'])
            identity_bytes += len(member['edition_id'].encode('utf-8'))
            if identity_bytes > MAX_RETENTION_IDENTITY_BYTES:
                raise ValueError('Retention observed identity bound exceeded')
            if artifact_keys is None or member['artifact_key'] in artifact_keys:
                retained_bytes += len(json.dumps(member, ensure_ascii=False).encode('utf-8'))
                if retained_bytes > MAX_RETAINED_RETENTION_BYTES:
                    raise ValueError('Retention retained member bound exceeded')
                result['members'].append(member)
        offset += len(page['members'])
        if offset == result['total_members']:
            return result
        if not page['members'] or offset > result['total_members']:
            raise ValueError('Incomplete retention observation')


def cloud_snapshot(device, platform, names=None):
    """Bounded keyset pages, retaining only names present in the inspected SD set.

    Reject row/count/generation/config drift. This is still a per-page cache
    observation, never a collection-wide transaction or live recovery proof.
    """
    config_bytes = device.private('app_flutter/config.json', 1048576)
    config = json.loads(config_bytes)
    after = seen = retained_bytes = 0
    artifacts, states, total = [], None, None
    while True:
        payload = device.cache_snapshot(platform, after)
        if len(payload) > 1048576:
            raise ValueError('Native catalogue projection exceeds buffer limit')
        page = json.loads(payload)
        if (not isinstance(page, dict) or page.get('error') or
                page.get('schema') != 'rshop.s7.cache.v2' or page.get('platform') != platform or
                type(page.get('after')) is not int or page['after'] != after or
                type(page.get('totalArtifacts')) is not int or not 0 <= page['totalArtifacts'] <= 100000 or
                not isinstance(page.get('artifacts'), list) or len(page['artifacts']) > 128 or
                not isinstance(page.get('rowIds'), list) or len(page['rowIds']) != len(page['artifacts']) or
                not isinstance(page.get('states'), list) or len(page['states']) > 256):
            raise ValueError('Invalid native catalogue page')
        ids = page['rowIds']
        cursor = after
        for row_id in ids:
            if type(row_id) is not int or not cursor < row_id < 1 << 63:
                raise ValueError('Invalid repeated or unordered row cursor')
            cursor = row_id
        if type(page.get('next')) is not int or page['next'] != cursor:
            raise ValueError('Invalid next row cursor')
        if states is None:
            states, total = page['states'], page['totalArtifacts']
        elif states != page['states'] or total != page['totalArtifacts']:
            raise ValueError('Catalogue state changed during observation')
        for artifact in page['artifacts']:
            if (not isinstance(artifact, dict) or not isinstance(artifact.get('displayName'), str)
                    or not artifact['displayName']):
                raise ValueError('Invalid native artifact record')
            if names is None or artifact['displayName'] in names:
                retained_bytes += len(json.dumps(artifact, ensure_ascii=False).encode('utf-8'))
                if retained_bytes > MAX_RETAINED_ARTIFACT_BYTES:
                    raise ValueError('Catalogue retained artifact bound exceeded')
                artifacts.append(artifact)
        seen += len(ids)
        if seen > total:
            raise ValueError('Catalogue count changed during observation')
        if len(ids) < 128:
            if seen != total:
                raise ValueError('Incomplete catalogue observation')
            break
        after = cursor
    by_scope = {}
    for state in states:
        if not isinstance(state, dict):
            raise ValueError('Invalid native catalogue state')
        scope_parts = state.get('scope')
        if (not isinstance(scope_parts, list) or len(scope_parts) != 3 or
                any(not isinstance(part, str) or not part for part in scope_parts) or
                tuple(scope_parts) in by_scope or
                not {'active', 'pending'}.issubset(state) or
                any(state.get(k) is not None and
                    (type(state[k]) is not int or state[k] < 1) for k in ('active', 'pending'))):
            raise ValueError('Invalid native catalogue state identity')
        by_scope[tuple(scope_parts)] = state
    scopes = []
    for source in config['sources']:
        drive = source.get('drive')
        if not drive:
            continue
        scope = (source['id'], drive['account_id'], drive['root_folder_id'])
        state = by_scope.get(scope)
        scopes.append({'sourceId': source['id'], 'accountId': drive['account_id'],
                       'rootFolderId': drive['root_folder_id'],
                       'activeGeneration': state['active'] if state else None,
                       'pendingGeneration': state['pending'] if state else None})
    if config_bytes != device.private('app_flutter/config.json', 1048576):
        raise ValueError('Configuration changed during observation')
    return artifacts, scopes


def local_observation(device, path, root, hash_required):
    relative = checked_relative_path(path, root)
    quoted = shlex.quote(path)
    if device.shell(f'test -L {quoted} && printf link || printf regular') == b'link':
        return {'path': path, 'relativePath': relative, 'name': PurePosixPath(path).name,
                'sizeBytes': 0, 'stable': False, 'issue': 'symbolic_link_preserved'}
    # Capture both file identities around streaming device-side hashing. Only the
    # digest crosses adb; no ROM body is buffered or copied to this Windows host.
    command = (f'realpath {quoted} && stat -c "%d %i %s %Y %Z" {quoted}' +
               (f' && md5sum {quoted}' if hash_required else '') +
               f' && stat -c "%d %i %s %Y %Z" {quoted}')
    lines = device.shell(command).decode('utf-8').splitlines()
    if len(lines) != (4 if hash_required else 3):
        raise ValueError('Unexpected local observation response')
    resolved = lines[0]
    checked_relative_path(resolved, root)
    before = [int(v) for v in lines[1].split()]
    after = [int(v) for v in lines[-1].split()]
    md5 = lines[2].split()[0].lower() if hash_required else None
    if hash_required and not re.fullmatch(r'[0-9a-f]{32}', md5):
        raise ValueError('Invalid device hash response')
    return {'path': path, 'relativePath': relative, 'resolvedPath': resolved,
            'name': PurePosixPath(path).name, 'sizeBytes': before[2], 'md5': md5,
            'beforeStat': before, 'afterStat': after,
            'stable': before == after and resolved == path}


def inventory_observations(device, root):
    # Paths are arguments, never shell programs. NUL framing preserves names.
    # Android find's {} + may exceed ARG_MAX: bound both count and command bytes.
    # Do not follow links or open/hash ROM bodies. Every failure aborts the run.
    program = r'''set -e
for path do
  printf '%s\0' "$path"
  if test -L "$path"; then printf 'link\0'; continue; fi
  resolved=$(realpath "$path")
  before=$(stat -c '%d %i %s %Y %Z' "$path")
  after=$(stat -c '%d %i %s %Y %Z' "$path")
  printf 'regular\0%s\0%s\0%s\0' "$resolved" "$before" "$after"
done'''
    data = device.shell('find ' + shlex.quote(root) +
                        ' \\( -type f -o -type l \\) -print0')
    if data and not data.endswith(b'\0'):
        raise ValueError('Incomplete inventory framing')
    paths = [value.decode('utf-8') for value in data.split(b'\0')[:-1]] if data else []
    seen = set()
    for path in paths:
        checked_relative_path(path, root)
        if path in seen:
            raise ValueError('Duplicate inventory path')
        seen.add(path)
    prefix = 'sh -c ' + shlex.quote(program) + ' sh'
    batch = []
    command = prefix
    for path in paths:
        argument = ' ' + shlex.quote(path)
        if len((prefix + argument).encode('utf-8')) > 16384:
            raise ValueError('Inventory path exceeds command byte bound')
        if len(batch) == 64 or len((command + argument).encode('utf-8')) > 16384:
            yield from _inventory_records(device.shell(command), root, batch)
            batch, command = [], prefix
        batch.append(path)
        command += argument
    if batch:
        yield from _inventory_records(device.shell(command), root, batch)


def _inventory_records(data, root, expected):
    if not data or not data.endswith(b'\0'):
        raise ValueError('Incomplete inventory response')
    fields = data.split(b'\0')[:-1]
    index = 0
    observed = []
    while index < len(fields):
        if index + 2 > len(fields):
            raise ValueError('Incomplete inventory record')
        path, kind = (value.decode('utf-8') for value in fields[index:index + 2])
        index += 2
        relative = checked_relative_path(path, root)
        if len(observed) >= len(expected) or path != expected[len(observed)]:
            raise ValueError('Inventory response path mismatch')
        observed.append(path)
        common = {'path': path, 'relativePath': relative, 'name': PurePosixPath(path).name,
                  'md5': None}
        if kind == 'link':
            yield dict(common, sizeBytes=0, stable=False, issue='symbolic_link_preserved')
            continue
        if kind != 'regular' or index + 3 > len(fields):
            raise ValueError('Invalid inventory record')
        resolved, before, after = (value.decode('utf-8') for value in fields[index:index + 3])
        index += 3
        checked_relative_path(resolved, root)
        before, after = ([int(v) for v in value.split()] for value in (before, after))
        if any(len(stat) != 5 or stat[2] < 0 for stat in (before, after)):
            raise ValueError('Invalid inventory file stats')
        yield dict(common, sizeBytes=before[2], resolvedPath=resolved,
                   beforeStat=before, afterStat=after,
                   stable=before == after and resolved == path)
    if observed != expected:
        raise ValueError('Incomplete inventory response')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--package', default='com.darkaxt.rshop.debug')
    parser.add_argument('--cache-helper', help='Exact prepared native cache-snapshot .jar path')
    parser.add_argument('--retention-helper', help='Exact prepared native retention .jar path')
    parser.add_argument('--platform', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--extension', action='append', required=True)
    parser.add_argument('--inventory-only', action='store_true',
                        help='Local path/stat inventory only; no catalogue read or ROM hashing')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    if not args.output.is_absolute() or output.is_relative_to(repo):
        raise ValueError('Private audit output must be absolute and outside the repository')
    if not args.root.startswith('/storage/') or not (
            '/Roms/' in args.root or (args.inventory_only and args.root.endswith('/Roms'))):
        raise ValueError('An explicit SD console directory is required')
    if not args.inventory_only and not args.cache_helper:
        parser.error('--cache-helper is required for consistent cached comparison')
    if args.inventory_only and args.retention_helper:
        parser.error('--retention-helper requires cached cloud comparison')
    device = Device(args.adb, args.serial, args.package, args.cache_helper, args.retention_helper)
    if device.shell('realpath ' + shlex.quote(args.root)).decode().strip() != args.root:
        raise ValueError('Root is redirected or not normalized')
    paths = None
    if not args.inventory_only:
        data = device.shell('find ' + shlex.quote(args.root) +
                            ' \\( -type f -o -type l \\) -print0')
        if data and not data.endswith(b'\0'):
            raise ValueError('Incomplete local path framing')
        paths = [value.decode('utf-8') for value in data.split(b'\0')[:-1]] if data else []
        if len(set(paths)) != len(paths):
            raise ValueError('Duplicate local path')
        for path in paths:
            checked_relative_path(path, args.root)
    artifacts, scopes = ([], []) if args.inventory_only else cloud_snapshot(
        device, args.platform, {PurePosixPath(path).name for path in paths})
    retention = retention_snapshot(device, args.platform, {
        json.dumps([identity[field] for field in
                    ('providerId', 'sourceId', 'accountId', 'providerFileId')],
                   separators=(',', ':'), ensure_ascii=False)
        for artifact in artifacts
        for identity in [artifact.get('id')]
        if isinstance(identity, dict) and all(
            isinstance(identity.get(field), str) and identity[field]
            for field in ('providerId', 'sourceId', 'accountId', 'providerFileId'))
    }) if args.retention_helper else None
    by_name = collections.defaultdict(list)
    for artifact in artifacts:
        by_name[artifact['displayName']].append(artifact)
    output.parent.mkdir(parents=True, exist_ok=True)
    counts = collections.Counter()
    byte_counts = collections.Counter()
    dispositions = collections.Counter()
    disposition_bytes = collections.Counter()
    disposition_games = collections.defaultdict(set)
    extensions = {e.lower() for e in args.extension}
    # Exclusive create. Never overwrite an earlier completed/interrupted journal.
    with output.open('x', encoding='utf-8', newline='\n') as journal:
        def record(value):
            journal.write(json.dumps(value, separators=(',', ':'), ensure_ascii=True) + '\n')
            journal.flush()
            os.fsync(journal.fileno())
        record({'kind': 'header', 'schema': 'rshop.s7.readonly-audit.v1',
                'observedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'serial': args.serial, 'platform': args.platform, 'root': args.root,
                'cloudEvidence': ('inventory_only_no_cloud_evidence' if args.inventory_only else
                                  'per_page_published_cache_not_live_revalidation'),
                'scopes': scopes, 'removalAuthorized': False,
                'retention': None if retention is None else {
                    k: v for k, v in retention.items() if k != 'members'},
                'retentionCoherence': None if retention is None else
                    'per_page_observation_not_execution_authority'})
        if args.inventory_only:
            observations = inventory_observations(device, args.root)
        else:
            observations = (local_observation(device, path, args.root,
                PurePosixPath(path).suffix.lower() in extensions and
                len(by_name.get(PurePosixPath(path).name, [])) == 1)
                for path in paths)
        for local in observations:
            name = local['name']
            candidates = by_name.get(name, [])
            is_game_artifact = PurePosixPath(name).suffix.lower() in extensions
            if not is_game_artifact:
                comparison = {'comparison': 'non_rom_preserved', 'disposition': 'preserve',
                              'removalAuthorized': False, 'remainingGates': []}
            elif args.inventory_only:
                comparison = {'comparison': 'cloud_not_observed' if local['stable'] else 'local_changed',
                              'disposition': 'preserve', 'removalAuthorized': False,
                              'remainingGates': list(GATES)}
            else:
                comparison = (compare_observation(local, candidates) if retention is None else
                              review_retention(local, candidates, retention))
            record({'kind': 'file', 'local': local, 'cloudCandidates': candidates,
                    **comparison})
            counts[comparison['comparison']] += 1
            byte_counts[comparison['comparison']] += local['sizeBytes']
            disposition = comparison['disposition']
            dispositions[disposition] += 1
            disposition_bytes[disposition] += local['sizeBytes']
            group = comparison.get('retention', {}).get('groupKey')
            if group is not None:
                disposition_games[disposition].add(group)
        summary = {'kind': 'completed', 'files': sum(counts.values()),
                   'comparisons': dict(counts), 'bytesByComparison': dict(byte_counts),
                   'filesByDisposition': dict(dispositions),
                   'bytesByDisposition': dict(disposition_bytes),
                   'boundCanonicalGamesByDisposition': {
                       k: len(v) for k, v in disposition_games.items()},
                   'removalAuthorized': False}
        record(summary)
    # Sanitized aggregate only; paths/accounts/cloud identifiers stay private.
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
