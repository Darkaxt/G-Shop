"""Read an explicitly stopped R-Shop projection into an in-memory SQL snapshot.

No device files or database values are written. Output is private review evidence,
not a public repository fixture. Use the app's query SQL for ranked selection.
"""
import argparse
import json
import gzip
from pathlib import Path
import sqlite3
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--query', required=True)
    parser.add_argument('--snapshot', type=Path,
        help='Exact task-owned gzip snapshot, captured once and reused read-only')
    args = parser.parse_args()
    if not args.query.lstrip().upper().startswith(('SELECT ', 'PRAGMA ', 'WITH ')):
        parser.error('Only snapshot reads are accepted')
    endpoint = ['adb', '-s', args.serial]
    if subprocess.check_output(endpoint + ['shell', 'getprop', 'ro.serialno'], text=True).strip() != args.serial:
        raise RuntimeError('Device identity differs')
    pid = subprocess.run(endpoint + ['shell', 'pidof', 'com.darkaxt.rshop'], capture_output=True, text=True)
    if pid.stdout.strip():
        raise RuntimeError('Stop the production app before reading its database')
    if args.snapshot and args.snapshot.exists():
        packed = args.snapshot.read_bytes()
    else:
        packed = subprocess.check_output(endpoint + ['exec-out',
            "su -c 'gzip -c /data/user/0/com.darkaxt.rshop/databases/rshop.db'"])
        if args.snapshot:
            with args.snapshot.open('xb') as target:
                target.write(packed)
    data = gzip.decompress(packed)
    db = sqlite3.connect(':memory:')
    try:
        db.deserialize(data)
        db.execute('PRAGMA query_only=ON')
        db.row_factory = sqlite3.Row
        print(json.dumps([dict(row) for row in db.execute(args.query)], ensure_ascii=True))
    finally:
        db.close()


if __name__ == '__main__':
    main()
