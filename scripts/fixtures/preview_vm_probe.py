"""One authenticated, isolated S22 diagnostic action; never echo credentials/VM URI."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import urllib.parse
from websockets.sync.client import connect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--command', default='status')
    parser.add_argument('--env-file', type=Path)
    parser.add_argument('--host-vm-url')
    parser.add_argument('--source-rom', help='Existing on-device GoldenEye fixture ROM; read-only')
    args = parser.parse_args()
    if args.command == 'prepare-launch' and not args.source_rom:
        parser.error('--source-rom is required for prepare-launch')
    package = 'com.darkaxt.rshop.sharedproof'

    def adb(*words):
        return subprocess.check_output([args.adb, '-s', args.serial, *words], text=True)

    pid = adb('shell', 'pidof', package).strip()
    if not re.fullmatch(r'\d+', pid):
        raise RuntimeError('Expected exactly one isolated proof process')
    port = None
    if args.host_vm_url:
        uri = urllib.parse.urlsplit(args.host_vm_url)
        if uri.scheme != 'http' or uri.hostname != '127.0.0.1' or not uri.port:
            raise RuntimeError('Isolated VM service is not ready')
        host_port = str(uri.port)
    else:
        log = adb('logcat', '-d', '--pid', pid, '-s', 'flutter:I')
        urls = re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)', log)
        if not urls:
            raise RuntimeError('Isolated VM service is not ready')
        uri = urllib.parse.urlsplit(urls[-1])
        port = adb('forward', 'tcp:0', 'tcp:' + str(uri.port)).strip()
        host_port = port
    client = None
    try:
        client = connect(f'ws://127.0.0.1:{host_port}{uri.path}ws',
                         open_timeout=None, close_timeout=None, ping_interval=None, proxy=None)
        sequence = 0

        def rpc(method, params=None):
            nonlocal sequence
            sequence += 1
            request = str(sequence)
            client.send(json.dumps({'jsonrpc': '2.0', 'id': request, 'method': method, 'params': params or {}}))
            while True:
                response = json.loads(client.recv())
                if response.get('id') == request:
                    if 'error' in response:
                        raise RuntimeError('VM action rejected: ' + method + ':' + str(response['error'].get('code')))
                    return response['result']

        vm = rpc('getVM')
        candidates = []
        extension = 'ext.rshop.previewProof'
        for isolate in vm['isolates']:
            details = rpc('getIsolate', {'isolateId': isolate['id']})
            if 'ext.rshop.previewProof' in details.get('extensionRPCs', []):
                candidates.append(isolate['id'])
                if 'ext.rshop.previewReload' in details.get('extensionRPCs', []):
                    extension = 'ext.rshop.previewReload'
        if len(candidates) != 1:
            raise RuntimeError('Isolated proof entrypoint is not ready')
        params = {'isolateId': candidates[0], 'command': args.command}
        if args.command == 'prepare-launch':
            params['romSource'] = args.source_rom
        if args.command == 'media':
            if args.env_file is None:
                raise RuntimeError('Private credential file is required')
            values = {}
            for line in args.env_file.read_text('utf-8-sig').splitlines():
                if '=' in line and not line.lstrip().startswith('#'):
                    key, value = line.split('=', 1)
                    if key.strip().startswith('SCREENSCRAPER_'):
                        values[key.strip()] = value.strip().strip('\"\'')
            params['credentials'] = json.dumps(values)
        result = rpc(extension, params)
        print(json.dumps(result, ensure_ascii=True))
    finally:
        if client is not None:
            client.close()
        if port is not None:
            adb('forward', '--remove', 'tcp:' + port)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        detail = str(error)
        allowed = {'Expected exactly one isolated proof process',
                   'Isolated VM service is not ready',
                   'Isolated proof entrypoint is not ready',
                   'Private credential file is required'}
        print(json.dumps({'ok': False, 'failure_type': type(error).__name__,
                          'failure_detail': detail if detail in allowed or detail.startswith('VM action rejected: ') else None}))
        raise SystemExit(1)
