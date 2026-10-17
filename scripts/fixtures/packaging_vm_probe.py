"""PID-bound persistent transport for the isolated S25 renderer, not production."""
import argparse
import json
import re
import subprocess
import urllib.parse
from websockets.sync.client import connect


class InspectionSession:
    def __init__(self, serial):
        self.serial = serial
        self.client = None
        self.port = None
        self.sequence = 0

    def adb(self, *parts):
        return subprocess.check_output(['adb', '-s', self.serial, *parts], text=True)

    def __enter__(self):
        try:
            self.pid = self.adb('shell', 'pidof', 'com.darkaxt.rshop.sharedproof').strip()
            if not re.fullmatch(r'\d+', self.pid):
                raise RuntimeError('Isolated inspection process unavailable')
            # Subscribe to the real startup announcement, including already
            # buffered lines. No sleep/retry or per-action log rediscovery.
            log = subprocess.Popen(['adb','-s',self.serial,'logcat','--pid',self.pid,
                                    '-s','flutter:I','AndroidRuntime:E'],
                                   stdout=subprocess.PIPE,text=True)
            try:
                for line in log.stdout:
                    match = re.search(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)',line)
                    if match:
                        uri = urllib.parse.urlsplit(match.group(1))
                        break
                    if 'Unhandled Exception' in line or 'FATAL EXCEPTION' in line:
                        raise RuntimeError('Isolated proof startup failed')
                else:
                    raise RuntimeError('VM announcement stream ended')
            finally:
                log.terminate()
                log.wait()
            self.port = self.adb('forward', 'tcp:0', f'tcp:{uri.port}').strip()
            self.client = connect(f'ws://127.0.0.1:{self.port}{uri.path}ws',
                                  open_timeout=None, close_timeout=None,
                                  ping_interval=None, proxy=None)
            self.rpc('streamListen', {'streamId': 'Isolate'})
            candidates = []
            for isolate in self.rpc('getVM')['isolates']:
                details = self.rpc('getIsolate', {'isolateId': isolate['id']})
                if 'ext.rshop.packaging' in details.get('extensionRPCs', []):
                    candidates.append(isolate['id'])
            if len(candidates) > 1:
                raise RuntimeError('Ambiguous isolated inspection extension')
            if candidates:
                self.isolate = candidates[0]
            else:
                while True:
                    event = json.loads(self.client.recv()).get('params', {}).get('event', {})
                    if (event.get('kind') == 'ServiceExtensionAdded' and
                            event.get('extensionRPC') == 'ext.rshop.packaging'):
                        self.isolate = event['isolate']['id']
                        break
            return self
        except BaseException:
            self.close()
            raise

    def rpc(self, method, params=None):
        self.sequence += 1
        token = str(self.sequence)
        self.client.send(json.dumps({'jsonrpc': '2.0', 'id': token,
                                     'method': method, 'params': params or {}}))
        while True:
            reply = json.loads(self.client.recv())
            if reply.get('id') == token:
                if 'error' in reply:
                    raise RuntimeError('Inspection action failed: ' +
                                       str(reply['error'].get('message')))
                return reply['result']

    def action(self, command, **options):
        return self.rpc('ext.rshop.packaging',
                        {'isolateId': self.isolate, 'command': command, **options})

    def close(self):
        if self.client is not None:
            self.client.close()
            self.client = None
        if self.port is not None:
            self.adb('forward', '--remove', 'tcp:' + self.port)
            self.port = None

    def __exit__(self, *_):
        self.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--command', default='status',
                        choices=['status', 'ready', 'next', 'view', 'button'])
    parser.add_argument('--view', choices=['box', 'cover', 'cartridge', 'manual', 'gallery'])
    parser.add_argument('--tooltip')
    args = parser.parse_args()
    with InspectionSession(args.serial) as session:
        options = {key: value for key, value in
                   [('view', args.view), ('tooltip', args.tooltip)] if value is not None}
        print(json.dumps(session.action(args.command, **options)))


if __name__ == '__main__':
    main()
