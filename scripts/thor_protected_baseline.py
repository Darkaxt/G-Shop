"""Read-only S7 shared-file evidence, not a backup or deletion authority.

Hashes stay on-device; only paths, stats and digests cross ADB. This is not an
atomic emulator snapshot, nor proof of coverage of private/custom save locations.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path, PurePosixPath
import re
import shlex

from thor_migration_audit import Device, checked_relative_path, inventory_observations


SHARED = '/storage/emulated/0'
SCOPES = [
    (f'retroarch-{name}', f'{SHARED}/RetroArch/{name}', 'directory')
    for name in ('saves', 'states', 'system', 'config')
] + [
    ('retroarch-shared-cfg', f'{SHARED}/RetroArch/retroarch.cfg', 'file'),
    ('retroarch-app-cfg', f'{SHARED}/Android/data/com.retroarch.aarch64/files/retroarch.cfg', 'file'),
] + [
    (f'dolphin-{name}', f'{SHARED}/Android/data/org.dolphinemu.dolphinemu/files/{name}', 'directory')
    for name in ('GC', 'StateSaves', 'Config', 'GameSettings')
] + [
    (f'nethersx2-{name}', f'{SHARED}/Android/data/xyz.aethersx2.android/files/{name}', 'directory')
    for name in ('bios', 'sstates', 'memcards', 'gamesettings', 'inputprofiles')
] + [('ppsspp-shared', f'{SHARED}/PSP', 'directory')]
MAX_FILES = 20000


def parse_hash_observation(data, path, root):
    checked_relative_path(path, root)
    lines = data.decode('utf-8').splitlines()
    if len(lines) != 4 or lines[0] != path:
        raise ValueError('Noncanonical or incomplete hash observation')
    checked_relative_path(lines[0], root)
    if any(not re.fullmatch(r'[0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+', lines[i])
           for i in (1, 3)) or not re.fullmatch(r'[0-9a-fA-F]{64}  -', lines[2]):
        raise ValueError('Invalid hash/stat framing')
    before, after = ([int(value) for value in lines[i].split()] for i in (1, 3))
    return {'path': path, 'sizeBytes': before[2], 'sha256': lines[2][:64].lower(),
            'beforeStat': before, 'afterStat': after, 'stable': before == after}


def hash_file(device, path, root):
    leaf = shlex.quote(path)
    command = (f'test ! -L {leaf} && test -f {leaf} && realpath {leaf}'
               f' && stat -c "%d %i %s %Y %Z" {leaf}'
               f' && sha256sum < {leaf} && stat -c "%d %i %s %Y %Z" {leaf}')
    return parse_hash_observation(device.shell(command), path, root)


def _inventory(device, root):
    result = {}
    for item in inventory_observations(device, root):
        if len(result) >= MAX_FILES:
            raise ValueError('Protected scope exceeds bounded file inventory')
        result[item['path']] = item
    return result


def _same_inventory(before, after):
    return (before.keys() == after.keys() and all(
        before[path]['stable'] and after[path]['stable'] and
        before[path]['beforeStat'] == after[path]['afterStat'] for path in before))


def capture_scope(device, name, path, kind, emit):
    quoted = shlex.quote(path)
    expected = '-d' if kind == 'directory' else '-f'
    probe = device.shell(f'if test ! -L {quoted} && test {expected} {quoted}; '
                         f'then realpath {quoted}; else printf unavailable; fi')
    record = {'type': 'scope', 'scope': name, 'path': path, 'kind': kind,
              'state': 'absent_or_unreadable', 'stableMembership': False,
              'removalAuthorized': False}
    if probe.decode('utf-8').rstrip('\n') != path:
        emit(record)
        return [], record
    root = path if kind == 'directory' else str(PurePosixPath(path).parent)
    before = _inventory(device, root) if kind == 'directory' else {path: None}
    files = []
    for leaf, observation in before.items():
        if observation is not None and not observation['stable']:
            row = {'path': leaf, 'sizeBytes': observation['sizeBytes'],
                   'stable': False, 'sha256': None, 'issue': 'unstable_or_link'}
        else:
            row = hash_file(device, leaf, root)
            if observation is not None:
                row['stable'] = row['stable'] and row['beforeStat'] == observation['beforeStat']
        row.update(type='file', scope=name, removalAuthorized=False)
        emit(row)
        files.append(row)
    after = _inventory(device, root) if kind == 'directory' else None
    membership = _same_inventory(before, after) if after is not None else True
    # No mutation/removal is performed between observations. A changing active
    # emulator is recorded as uncertainty, not stopped or retried on a timer.
    record.update(state='observed', stableMembership=membership,
                  files=len(files), bytes=sum(row['sizeBytes'] for row in files))
    emit(record)
    return files, record


def load_baseline(path, serial):
    files, scopes = {}, {}
    header = summary = None
    with path.open(encoding='utf-8') as stream:
        for index, line in enumerate(iter(lambda: stream.readline(32769), '')):
            if index > MAX_FILES + 100 or len(line) > 32768:
                raise ValueError('Baseline exceeds bounded journal contract')
            row = json.loads(line)
            if not isinstance(row, dict) or summary is not None:
                raise ValueError('Invalid journal ordering')
            kind = row.get('type')
            if index == 0 and kind == 'header' and row.get('serial') == serial:
                header = row
            elif header is not None and kind == 'file':
                key = row.get('path')
                if (not isinstance(key, str) or key in files or
                        row.get('removalAuthorized') is not False or
                        type(row.get('sizeBytes')) is not int or row['sizeBytes'] < 0):
                    raise ValueError('Invalid file record')
                files[key] = row
            elif header is not None and kind == 'scope':
                key = row.get('scope')
                if not isinstance(key, str) or key in scopes:
                    raise ValueError('Invalid scope record')
                scopes[key] = row
            elif header is not None and kind == 'summary':
                summary = row
            else:
                raise ValueError('Invalid journal record')
    if (summary is None or summary.get('complete') is not True or
            summary.get('files') != len(files) or
            summary.get('bytes') != sum(row['sizeBytes'] for row in files.values()) or
            any(row.get('scope') not in scopes for row in files.values())):
        raise ValueError('Incomplete or inconsistent baseline')
    return {'files': files, 'scopes': scopes}


def compare_baseline(baseline, files, scopes):
    def valid(row):
        return row.get('stable') is True and isinstance(row.get('sha256'), str) and bool(
            re.fullmatch(r'[0-9a-f]{64}', row['sha256']))
    equal = (baseline['files'].keys() == files.keys() and
             baseline['scopes'].keys() == scopes.keys())
    equal = equal and all(valid(row) and valid(files[path]) and
                         row['sha256'] == files[path]['sha256'] and
                         row['sizeBytes'] == files[path]['sizeBytes']
                         for path, row in baseline['files'].items())
    equal = equal and all(row.get('path') == current.get('path') and
                         row.get('state') == current.get('state') == 'observed' and
                         row.get('stableMembership') is current.get('stableMembership') is True
                         for key, row in baseline['scopes'].items()
                         for current in [scopes[key]])
    return {'equal': equal, 'removalAuthorized': False,
            'scope': 'explicit_shared_paths_only', 'atomicSnapshot': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-against', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if not args.output.is_absolute() or output.is_relative_to(Path(__file__).resolve().parent.parent):
        raise ValueError('Private journal must be absolute and outside the repository')
    previous = load_baseline(args.verify_against, args.serial) if args.verify_against else None
    device = Device(args.adb, args.serial, 'com.darkaxt.rshop.debug')
    files, scopes = {}, {}
    # Exclusive creation preserves previous evidence; interruption leaves a
    # visibly incomplete journal that cannot pass load_baseline/verification.
    with args.output.open('x', encoding='utf-8', newline='\n') as stream:
        def emit(row):
            stream.write(json.dumps(row, ensure_ascii=False, separators=(',', ':')) + '\n')
            stream.flush()
        emit({'type': 'header', 'serial': args.serial, 'schema': 'rshop.s7.protected.v1',
              'capturedAt': datetime.now(timezone.utc).isoformat(), 'readOnly': True,
              'removalAuthorized': False, 'atomicSnapshot': False,
              'privateAndCustomPathsVerified': False})
        for name, path, kind in SCOPES:
            rows, scope = capture_scope(device, name, path, kind, emit)
            files.update((row['path'], row) for row in rows)
            scopes[name] = scope
            print(json.dumps({'scope': name, 'state': scope['state'], 'files': len(rows),
                              'stableMembership': scope['stableMembership']}), flush=True)
        summary = {'type': 'summary', 'complete': True, 'files': len(files),
                   'bytes': sum(row['sizeBytes'] for row in files.values()),
                   'unverifiedScopes': sum(row['state'] != 'observed' for row in scopes.values()),
                   'unstableFiles': sum(not row['stable'] for row in files.values()),
                   'removalAuthorized': False}
        if previous is not None:
            summary['comparison'] = compare_baseline(previous, files, scopes)
        emit(summary)
        print(json.dumps(summary), flush=True)
    return 1 if previous is not None and not summary['comparison']['equal'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
