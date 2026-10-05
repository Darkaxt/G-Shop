"""Read-only S7 SD/cloud-cache audit. This command cannot remove or adopt files.

Writes a PRIVATE exclusive-create JSONL observation journal, outside the repo.
Cached Drive checksums are comparison evidence, never current recovery authority.
An interrupted journal lacks its terminal summary and must not be called complete.
"""
import argparse
import collections
import datetime
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import sqlite3
import subprocess

GATES = ["canonical_identity_review", "defensible_retention",
         "live_cloud_revalidation", "tested_restore", "save_sync_safety",
         "execution_time_local_revalidation"]


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


class Device:
    def __init__(self, adb, serial, package):
        self.prefix = [adb, '-s', serial]
        self.package = package

    def shell(self, command):
        return self._read(self.prefix + ['exec-out', 'sh', '-c', command], 8 * 1048576)

    def private(self, path, limit):
        return self._read(self.prefix + ['exec-out', 'run-as', self.package, 'cat', path], limit)

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


def cloud_snapshot(device, platform):
    config_bytes = device.private('app_flutter/config.json', 1048576)
    config = json.loads(config_bytes)
    db = sqlite3.connect(':memory:')
    try:
        db.deserialize(device.private('databases/rshop.db', 64 * 1048576))
        if db.execute('pragma quick_check').fetchone() != ('ok',):
            raise ValueError('Not a consistent catalogue observation; no journal written')
        artifacts = [json.loads(row[0]) for row in db.execute(
            'select remote_artifact from games where systemSlug=? and remote_artifact is not null',
            (platform,))]
        scopes = []
        for source in config['sources']:
            drive = source.get('drive')
            if not drive:
                continue
            scope = json.dumps([source['id'], drive['account_id'], drive['root_folder_id']],
                               separators=(',', ':'))
            state = db.execute('select active,pending from drive_catalogue_state where scope=?',
                               (scope,)).fetchone()
            scopes.append({'sourceId': source['id'], 'accountId': drive['account_id'],
                           'rootFolderId': drive['root_folder_id'],
                           'activeGeneration': state[0] if state else None,
                           'pendingGeneration': state[1] if state else None})
        if config_bytes != device.private('app_flutter/config.json', 1048576):
            raise ValueError('Configuration changed during observation')
        return artifacts, scopes
    finally:
        db.close()


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--package', default='com.darkaxt.rshop.debug')
    parser.add_argument('--platform', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--extension', action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    if not args.output.is_absolute() or output.is_relative_to(repo):
        raise ValueError('Private audit output must be absolute and outside the repository')
    if not args.root.startswith('/storage/') or '/Roms/' not in args.root:
        raise ValueError('An explicit SD console directory is required')
    device = Device(args.adb, args.serial, args.package)
    if device.shell('realpath ' + shlex.quote(args.root)).decode().strip() != args.root:
        raise ValueError('Root is redirected or not normalized')
    artifacts, scopes = cloud_snapshot(device, args.platform)
    by_name = collections.defaultdict(list)
    for artifact in artifacts:
        by_name[artifact['displayName']].append(artifact)
    output.parent.mkdir(parents=True, exist_ok=True)
    counts = collections.Counter()
    byte_counts = collections.Counter()
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
                'cloudEvidence': 'published_app_cache_not_live_revalidation',
                'scopes': scopes, 'removalAuthorized': False})
        paths = device.shell('find ' + shlex.quote(args.root) +
                             ' \\( -type f -o -type l \\) -print0').split(b'\0')
        for raw in paths:
            if not raw:
                continue
            path = raw.decode('utf-8')
            checked_relative_path(path, args.root)
            name = PurePosixPath(path).name
            candidates = by_name.get(name, [])
            is_game_artifact = PurePosixPath(name).suffix.lower() in extensions
            local = local_observation(device, path, args.root,
                                      is_game_artifact and len(candidates) == 1)
            comparison = compare_observation(local, candidates) if is_game_artifact else {
                'comparison': 'non_rom_preserved', 'disposition': 'preserve',
                'removalAuthorized': False, 'remainingGates': []}
            record({'kind': 'file', 'local': local, 'cloudCandidates': candidates,
                    **comparison})
            counts[comparison['comparison']] += 1
            byte_counts[comparison['comparison']] += local['sizeBytes']
        summary = {'kind': 'completed', 'files': sum(counts.values()),
                   'comparisons': dict(counts), 'bytesByComparison': dict(byte_counts),
                   'removalAuthorized': False}
        record(summary)
    # Sanitized aggregate only; paths/accounts/cloud identifiers stay private.
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
