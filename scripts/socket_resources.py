"""Read the owner's hash-bound Socket 0.7 Godot resources for media integration.

No APK, resource key or account data is embedded in the repository. The embedded
key is read from the exact supplied engine and every envelope is checked before
use. This is a format reader, not a launcher or a Godot runtime dependency.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import re
import struct
import zipfile
from compression import zstd

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
from cryptography.hazmat.decrepit.ciphers.modes import CFB

APK_SHA256 = 'bccf6bf5beccf5155645638e52a20f6e6e6deed902bd23b6b69ae7060c04bd70'


def decrypt_resource(envelope, key):
    if len(envelope) < 40:
        raise ValueError('Truncated encrypted resource')
    size = struct.unpack_from('<Q', envelope, 16)[0]
    if size > len(envelope) - 40 or len(envelope[40:]) % 16:
        raise ValueError('Invalid encrypted resource size')
    data = Cipher(algorithms.AES(key), CFB(envelope[24:40])).decryptor().update(envelope[40:])[:size]
    if hashlib.md5(data).digest() != envelope[:16]:
        raise ValueError('Encrypted resource checksum mismatch')
    return data


class Reader:
    def __init__(self, data, offset=0):
        self.data, self.pos = data, offset
        self.strings = []

    def read(self, count):
        if count < 0 or count > len(self.data) - self.pos:
            raise ValueError(f'Truncated resource at {self.pos}, requested {count}')
        data = self.data[self.pos:self.pos + count]
        self.pos += count
        return data

    def number(self, fmt='I'):
        return struct.unpack('<' + fmt, self.read(struct.calcsize(fmt)))[0]

    def string(self):
        return self.read(self.number()).rstrip(b'\0').decode('utf-8')

    def variant(self):
        kind = self.number()
        if kind == 1:
            return None
        if kind in (2, 3, 40, 4, 41):
            return self.number({2: 'I', 3: 'i', 40: 'q', 4: 'f', 41: 'd'}[kind])
        if kind in (5, 44):
            return self.string()
        if kind in (45, 46, 47, 51):
            count = {45: 2, 46: 4, 47: 3, 51: 4}[kind]
            return {'variant': kind, 'values': [self.number('i') for _ in range(count)]}
        if kind in (10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 50, 52):
            count = {10: 2, 11: 4, 12: 3, 13: 4, 14: 4, 15: 6, 16: 9, 17: 12, 18: 6, 20: 4, 50: 4, 52: 16}[kind]
            return {'variant': kind, 'values': [self.number('f') for _ in range(count)]}
        if kind == 24:
            subtype = self.number()
            if subtype == 0:
                return None
            if subtype in (2, 3):
                return {'resource_reference': subtype, 'index': self.number()}
            raise ValueError(f'Unsupported resource reference {subtype}')
        if kind == 22:
            names, subs = self.number('H'), self.number('H')
            absolute = bool(subs & 0x8000)
            values = []
            for _ in range(names + (subs & 0x7fff)):
                index = self.number()
                values.append(self.read(index & 0x7fffffff).rstrip(b'\0').decode() if index & 0x80000000 else self.strings[index])
            return {'node_path': values, 'absolute': absolute}
        if kind == 26:
            return {str(self.variant()): self.variant() for _ in range(self.number() & 0x7fffffff)}
        if kind == 30:
            return [self.variant() for _ in range(self.number() & 0x7fffffff)]
        if kind == 31:
            count = self.number()
            data = self.read(count)
            self.read((-count) % 4)
            return data
        if kind in (32, 33, 35, 36, 37, 48, 49, 53):
            count = self.number()
            fmt, width = {32: ('i', 1), 33: ('f', 1), 35: ('f', 3), 36: ('f', 4), 37: ('f', 2), 48: ('q', 1), 49: ('d', 1), 53: ('f', 4)}[kind]
            return {'packed_kind': kind, 'count': count, 'values': [self.number(fmt) for _ in range(count * width)]}
        if kind == 34:
            return [self.string() for _ in range(self.number())]
        raise ValueError(f'Unsupported resource variant {kind} at {self.pos}')

    def script_variant(self):
        header = self.number()
        kind, wide = header & 0xffff, bool(header & 0x10000)
        if kind == 0:
            return None
        if kind in (1, 2, 3):
            return self.number('q' if kind == 2 and wide else 'd' if kind == 3 and wide else 'f' if kind == 3 else 'i')
        if kind in (4, 21):
            count = self.number()
            value = self.read(count).decode()
            self.read((-count) % 4)
            return value
        raise ValueError(f'Unsupported script constant {kind} at {self.pos}')


def decode_script(data, tokenizer_header):
    if data[:4] != b'GDSC' or struct.unpack_from('<I', data, 4)[0] != 101:
        raise ValueError('Expected tokenizer version 101')
    enum = re.sub(r'//[^\n]*', '', tokenizer_header.split('enum Type {')[1].split('};')[0])
    enum = [token.strip() for token in enum.split(',') if token.strip()]
    expected = struct.unpack_from('<I', data, 8)[0]
    content = zstd.decompress(data[12:]) if expected else data[12:]
    if expected and len(content) != expected:
        raise ValueError('Script decompression size mismatch')
    reader = Reader(content)
    identifiers, constants, lines, tokens = [reader.number() for _ in range(4)]
    ids = [bytes(b ^ 0xb6 for b in reader.read(reader.number() * 4)).decode('utf-32-le') for _ in range(identifiers)]
    consts = [reader.script_variant() for _ in range(constants)]
    reader.read(lines * 16)
    result = {}
    for _ in range(tokens):
        token = reader.number() if content[reader.pos] & 0x80 else reader.number('B')
        line = reader.number()
        kind, index = token & 0x7f, token >> 8
        value = ids[index] if kind in (1, 2) else repr(consts[index]) if kind == 3 else enum[kind]
        result.setdefault(line, []).append(value)
    if reader.pos != len(content):
        raise ValueError('Unconsumed script bytes')
    return {line: ' '.join(values) for line, values in result.items()}


def scene_nodes(scene):
    packed = next(r for r in scene['resources'] if r['type'] == 'PackedScene')
    bundle = packed['properties']['_bundled']
    names, variants = bundle['names'], bundle['variants']
    values = bundle['nodes']['values']
    nodes, cursor = [], 0
    for _ in range(bundle['node_count']):
        parent, owner, typename, name, instance, count = values[cursor:cursor + 6]
        cursor += 6
        properties = {}
        for _ in range(count):
            prop, variant = values[cursor:cursor + 2]
            cursor += 2
            properties[names[prop & 0x3fffffff]] = variants[variant]
        groups = values[cursor]
        cursor += 1 + groups
        nodes.append({'name': names[name & ((1 << 18) - 1)], 'parent': parent,
                      'type': None if typename == 0x7fffffff else names[typename],
                      'instance': None if instance < 0 else variants[instance],
                      'properties': properties})
    if cursor != len(values):
        raise ValueError('Unconsumed scene nodes')
    return nodes


def decompress_resource(data):
    if data[:4] == b'RSRC':
        return data, 4
    if data[:4] != b'RSCC':
        raise ValueError('Not a Godot binary resource')
    reader = Reader(data, 4)
    mode, block_size, total = [reader.number() for _ in range(3)]
    if mode != 2 or not block_size:
        raise ValueError('Unsupported resource compression')
    sizes = [reader.number() for _ in range(total // block_size + 1)]
    result = b''.join(zstd.decompress(reader.read(size)) for size in sizes)
    if len(result) != total:
        raise ValueError('Decompressed resource size mismatch')
    return result, 0


def resource(data):
    data, offset = decompress_resource(data)
    reader = Reader(data, offset)
    endian, real64, major, minor, version = [reader.number() for _ in range(5)]
    if endian or real64:
        raise ValueError('Unsupported resource byte order/precision')
    typename, metadata, flags, uid = reader.string(), reader.number('Q'), reader.number(), reader.number('Q')
    if flags & 8:
        reader.string()
    reader.read(44)
    reader.strings = [reader.string() for _ in range(reader.number())]
    external = [(reader.string(), reader.string(), reader.number('Q') if flags & 2 else None) for _ in range(reader.number())]
    internal = [(reader.string(), reader.number('Q')) for _ in range(reader.number())]
    results = []
    for path, position in internal:
        reader.pos = position
        cls = reader.string()
        props = {reader.strings[reader.number()]: reader.variant() for _ in range(reader.number())}
        results.append({'path': path, 'type': cls, 'properties': props})
    return {'type': typename, 'engine': [major, minor], 'format': version, 'external': external, 'resources': results}


def json_value(value):
    if isinstance(value, bytes):
        return {'bytes': base64.b64encode(value).decode(), 'length': len(value), 'sha256': hashlib.sha256(value).hexdigest()}
    raise TypeError(type(value).__name__)


class SocketArchive:
    def __init__(self, apk):
        with open(apk, 'rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != APK_SHA256:
                raise ValueError('This extractor requires the supplied Socket 0.7 APK')
        self.zip = zipfile.ZipFile(apk)
        native = self.zip.read('lib/arm64-v8a/libgodot_android.so')
        # Offset belongs to this exact hash, not a guessed key for other builds.
        self._key = native[0x43cb858:0x43cb858 + 32]
        self._resources = {}

    def resolve(self, path):
        member = 'assets/' + path.removeprefix('res://')
        for suffix in ('.remap', '.import'):
            if member + suffix in self.zip.namelist():
                config = self.plain(member + suffix).decode().rstrip('\0')
                match = re.search(r'^path(?:\.[a-z0-9_]+)?="([^"]+)"', config, re.M)
                if not match:
                    raise ValueError(f'Missing remap path: {path}')
                return 'assets/' + match.group(1).removeprefix('res://')
        if member not in self.zip.namelist():
            raise FileNotFoundError(path)
        return member

    def load(self, path):
        member = self.resolve(path)
        if member not in self._resources:
            parsed = resource(self.plain(member))
            parsed['member'] = member
            self._resources[member] = parsed
        return self._resources[member]

    def reference(self, value, scene):
        if value is None:
            return None
        kind, index = value['resource_reference'], value['index']
        if kind == 2:
            return scene['resources'][index], scene
        if kind == 3:
            loaded = self.load(scene['external'][index][1])
            return loaded['resources'][-1], loaded
        raise ValueError('Unknown reference type')

    def plain(self, member):
        return decrypt_resource(self.zip.read(member), self._key)

    def scene(self, member):
        return resource(self.plain(member))

    def close(self):
        self.zip.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--tokenizer-header')
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    archive = SocketArchive(args.apk)
    try:
        names = archive.zip.namelist()
        selected = [n for n in names if n.endswith('.scn') and ('/imported/' in n or '/exported/' in n and '-cart_' in n)]
        manifest = []
        for name in selected:
            scene = archive.scene(name)
            scene['nodes'] = scene_nodes(scene)
            filename = name.rsplit('/', 1)[1] + '.json'
            (output / filename).write_text(json.dumps(scene, default=json_value, separators=(',', ':')), encoding='utf-8')
            manifest.append({'source': name, 'sha256': hashlib.sha256(archive.plain(name)).hexdigest(), 'file': filename, 'resources': [r['type'] for r in scene['resources']]})
        (output / 'manifest.json').write_text(json.dumps({'apkSha256': APK_SHA256, 'scenes': manifest}, indent=2), encoding='utf-8')
        if args.tokenizer_header:
            header = pathlib.Path(args.tokenizer_header).read_text(encoding='utf-8')
            scripts = [n for n in names if n.endswith('.gdc') and
                       (n.startswith('assets/scripts/models/platforms/') or
                        'cartridge' in n or '/selectables/cart_' in n or '/transition.' in n)]
            for name in scripts:
                decoded = decode_script(archive.plain(name), header)
                filename = name.removeprefix('assets/').replace('/', '__') + '.json'
                (output / filename).write_text(json.dumps(decoded, indent=2), encoding='utf-8')
            print(json.dumps({'decodedScripts': len(scripts)}))
        print(json.dumps({'extractedScenes': len(manifest), 'output': str(output.resolve())}))
    finally:
        archive.close()


if __name__ == '__main__':
    main()
