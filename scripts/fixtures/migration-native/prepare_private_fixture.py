"""One read-only real-ROM fixture; private outputs must never be committed.

Streams binary ADB output directly to disk, verifies source hashes before/after,
and queries the private SQLite copy. No production process stop or device write.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import secrets
import shlex
import shutil
import tarfile
import xml.etree.ElementTree as ET


def main():
    cli = argparse.ArgumentParser()
    cli.add_argument('--adb', required=True)
    cli.add_argument('--serial', required=True)
    cli.add_argument('--repo', type=Path, required=True)
    cli.add_argument('--output', type=Path, required=True)
    cli.add_argument('--host-rom-root', type=Path)
    cli.add_argument('--stage-package', choices=['com.darkaxt.rshop.sharedproof'])
    cli.add_argument('--password-only', action='store_true',
                     help='Fresh destination receives only the unlock password, never source setup')
    cli.add_argument('--verify-encrypted-archive', action='store_true')
    args = cli.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.verify_encrypted_archive:
        private = json.loads((args.output / 'proof-input.json').read_text(encoding='utf-8'))
        needles = [value.encode() for value in private['credentials'].values() if value]
        needles.append((args.output / 'proof-password').read_bytes())
        overlap = max(map(len, needles)) - 1
        digest = hashlib.sha256()
        count, previous = 0, b''
        process = subprocess.Popen([args.adb, '-s', args.serial, 'exec-out',
            'cat /storage/emulated/0/RShopMigrationProof-20261016/portable.rshop'],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        found = False
        while chunk := process.stdout.read(65536):
            digest.update(chunk)
            count += len(chunk)
            joined = previous + chunk
            found |= any(value in joined for value in needles)
            previous = joined[-overlap:] if overlap else b''
        _, _ = process.communicate()
        if process.returncode or count < 40 or found:
            raise RuntimeError('Encrypted archive privacy check failed')
        print(json.dumps({'archive_bytes': count, 'sha256': digest.hexdigest(),
            'plaintext_credentials_found': False, 'plaintext_password_found': False,
            'stream_chunk_bytes': 65536}))
        return
    if args.stage_package:
        members = [('proof-password', args.output / 'proof-password')]
        if not args.password_only:
            members.extend([('proof-input.json', args.output / 'proof-input.json'),
                            ('proof-rom', args.output / 'proof-rom')])
            members.extend(('proof-art/' + file.name, file)
                for file in sorted((args.output / 'proof-art').iterdir()))
        expected = {}
        for name, file in members:
            if not file.is_file() or file.is_symlink() or '..' in name.split('/'):
                raise RuntimeError('Unsafe private fixture member')
            with file.open('rb') as stream:
                expected[name] = hashlib.file_digest(stream, 'sha256').hexdigest()
        command = 'run-as ' + args.stage_package + ' sh -c ' + shlex.quote(
            'mkdir -p files && tar -xf - -C files')
        process = subprocess.Popen([args.adb, '-s', args.serial, 'exec-in', command],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with tarfile.open(fileobj=process.stdin, mode='w|') as archive:
            for name, file in members:
                archive.add(file, arcname=name, recursive=False)
        process.stdin.close()
        process.stdin = None
        _, _ = process.communicate()
        if process.returncode:
            raise RuntimeError('Private fixture transport failed')
        for name, file in members:
            result = subprocess.run([args.adb, '-s', args.serial, 'shell', '-n',
                'run-as', args.stage_package, 'sha256sum', 'files/' + name],
                stdin=subprocess.DEVNULL, capture_output=True, check=True)
            if result.stdout.decode().split()[0] != expected[name]:
                raise RuntimeError('Private fixture transport mismatch')
        print(json.dumps({'staged': True, 'verified': True, 'private_files': len(members),
            'shared_plaintext_files': 0, 'compression': 'none'}))
        return
    prefix = [args.adb, '-s', args.serial, 'exec-out']

    def command(operation, path):
        return [*prefix, 'su -c ' + shlex.quote(operation + ' ' + shlex.quote(path))]

    def remote_hash(path):
        value = subprocess.run(command('sha256sum', path), check=True,
                               stdin=subprocess.DEVNULL, capture_output=True).stdout.decode().split()[0]
        if len(value) != 64:
            raise RuntimeError('Invalid remote hash')
        return value

    def digest(path):
        with path.open('rb') as stream:
            return hashlib.file_digest(stream, 'sha256').hexdigest()

    def copy(path, target):
        before = remote_hash(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            if digest(target) != before:
                raise RuntimeError('Retained fixture no longer matches source')
            return
        with target.open('xb') as stream:
            subprocess.run(command('cat', path), stdout=stream, stdin=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, check=True)
        if digest(target) != before or remote_hash(path) != before:
            raise RuntimeError('Source changed or binary copy mismatch')

    app = '/data/user/0/com.darkaxt.rshop'
    database = args.output / 'source.db'
    before_db = remote_hash(app + '/databases/rshop.db')
    before_journal = remote_hash(app + '/databases/rshop.db-journal')
    copy(app + '/databases/rshop.db', database)
    copy(app + '/databases/rshop.db-journal', args.output / 'source.db-journal')
    if (before_db != remote_hash(app + '/databases/rshop.db') or
            before_journal != remote_hash(app + '/databases/rshop.db-journal')):
        raise RuntimeError('SQLite fixture changed during snapshot')
    copy(app + '/app_flutter/config.json', args.output / 'config.json')
    copy(app + '/shared_prefs/FlutterSharedPreferences.xml', args.output / 'preferences.xml')
    with sqlite3.connect(database) as db:
        db.row_factory = sqlite3.Row
        installed = [json.loads(row[0]) for row in db.execute(
            'SELECT record_json FROM installed_artifacts')]
        cache = {row['media_key']: dict(row) for row in db.execute('SELECT * FROM metadata_artwork_cache')}
        selected = None
        for row in db.execute('SELECT e.record_json AS edition,g.record_json AS game,'
                'm.record_json AS metadata FROM library_editions e '
                'JOIN library_game_identities g ON e.game_id=g.game_id '
                'JOIN library_metadata m ON e.edition_id=m.edition_id '
                "WHERE g.platform_id='gba' ORDER BY CASE WHEN g.title='Advance Wars' THEN 0 ELSE 1 END,g.title"):
            edition = json.loads(row['edition'])
            metadata = json.loads(row['metadata'])
            if not any(hashlib.sha256(json.dumps([media, 'png-1024-v1'],
                    ensure_ascii=False, separators=(',', ':')).encode()).hexdigest() in cache
                    for media in metadata['media']):
                continue
            ids = [member['artifactId'] for member in edition['members']]
            owned = next((value for value in installed
                if value['artifact']['id'] in ids and value['sizeBytes'] <= 20*1024*1024), None)
            host_file = None
            if not owned and args.host_rom_root:
                for identity in ids:
                    key = json.dumps([identity['providerId'], identity['sourceId'],
                        identity.get('accountId'), identity['providerFileId']], separators=(',', ':'))
                    artifact_row = db.execute('SELECT record_json FROM library_artifacts WHERE artifact_id=?', (key,)).fetchone()
                    if not artifact_row:
                        continue
                    artifact = json.loads(artifact_row[0])
                    candidate = args.host_rom_root / artifact['displayName']
                    if (candidate.parent == args.host_rom_root and candidate.is_file() and
                            candidate.stat().st_size == artifact.get('sizeBytes') and
                            candidate.stat().st_size <= 20*1024*1024 and artifact.get('providerChecksums')):
                        valid = True
                        for name, expected in artifact['providerChecksums'].items():
                            if name not in ('md5', 'sha1', 'sha256'):
                                continue
                            with candidate.open('rb') as stream:
                                if hashlib.file_digest(stream, name).hexdigest() != expected:
                                    valid = False
                        if valid:
                            owned = {'artifact': artifact, 'sizeBytes': candidate.stat().st_size}
                            host_file = candidate
                            break
            if owned:
                selected = {'edition': edition, 'game': json.loads(row['game']),
                    'metadata': metadata, 'installed': owned}
                break
        if not selected:
            raise RuntimeError('No actual owned GBA fixture')
    selected['configuration'] = json.loads((args.output / 'config.json').read_text('utf-8'))
    prefs = ET.parse(args.output / 'preferences.xml').getroot()
    shared = next((node.text for node in prefs if node.attrib['name'] ==
                   'flutter.metadata_shared_directory_v1'), None)
    art_root = shared + '/artwork' if shared else app + '/files/metadata-artwork'
    art = []
    for media in selected['metadata']['media']:
        encoded = json.dumps([media, 'png-1024-v1'], ensure_ascii=False, separators=(',', ':'))
        key = hashlib.sha256(encoded.encode()).hexdigest()
        if key in cache:
            row = cache[key]
            copy(art_root + '/' + row['filename'], args.output / 'proof-art' / row['filename'])
            art.append(row)
    if not art:
        raise RuntimeError('No selected actual artwork')
    selected['selectedArtwork'] = art
    source = selected['installed']
    if host_file:
        shutil.copyfile(host_file, args.output / 'proof-rom')
        if digest(host_file) != digest(args.output / 'proof-rom'):
            raise RuntimeError('Host ROM changed')
    else:
        copy(source['destinationRoot'] + '/' + source['relativePath'], args.output / 'proof-rom')
    env = {}
    for line in (args.repo / '.env.local').read_text('utf-8-sig').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            env[key.strip()] = value.strip().strip('\"\'')
    names = {'SCREENSCRAPER_USERNAME': 'rshop.metadata.screenscraper.user.name',
        'SCREENSCRAPER_PASSWORD': 'rshop.metadata.screenscraper.user.password',
        'SCREENSCRAPER_DEVID': 'rshop.metadata.screenscraper.developer.id',
        'SCREENSCRAPER_DEVPASSWORD': 'rshop.metadata.screenscraper.developer.password',
        'SCREENSCRAPER_SOFTNAME': 'rshop.metadata.screenscraper.developer.software',
        'IGDB_CLIENT_ID': 'rshop.metadata.igdb.client.id',
        'IGDB_CLIENT_SECRET': 'rshop.metadata.igdb.client.secret'}
    selected['credentials'] = {target: env[source] for source, target in names.items()}
    with (args.output / 'proof-input.json').open('x', encoding='utf-8') as stream:
        json.dump(selected, stream, ensure_ascii=False)
    with (args.output / 'proof-password').open('x', encoding='utf-8') as stream:
        stream.write(secrets.token_urlsafe(32))
    print(json.dumps({'verified': True, 'title': selected['game']['title'],
        'rom_bytes': source['sizeBytes'], 'artwork_files': len(art),
        'credential_fields': len(selected['credentials']), 'source_mutations': 0}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Never log captured command output, configuration or credential values.
        print(json.dumps({'failed': True, 'type': type(error).__name__,
            'code': str(error) if isinstance(error, RuntimeError) else 'fixture_io_failed'}))
        raise SystemExit(1)
