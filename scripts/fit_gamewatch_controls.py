"""Register two supplied reconstructions' raised controls to their faceplates.

Produces a derived private GLB, leaving every texture/binary byte and hinge clip
unchanged. Profiles are pinned to inspected source hashes, not fuzzy model names.
Use the result as --source for prepare_console_model.py. Never edit the original.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


PROFILES = {
    'eacc0ad35e011d3ce72e858dca07b075afbc8c8ac24eb5a640cd9028da076ae7': {
        'imageSize': (1767, 2199), 'controls': [
            ('Printed_face_0', ('D_pad', 'D_pad.001'), (108, 1742, 351, 1985)),
            ('Printed_face_0', ('Jump_key',), (1473, 1799, 1597, 1923)),
            ('Printed_face_0', ('Menu_key.002',), (1477, 1246, 1558, 1295)),
            ('Printed_face_0', ('Menu_key.001',), (1477, 1362, 1558, 1411)),
            ('Printed_face_0', ('Menu_key',), (1477, 1478, 1558, 1527))]},
    '2fe07958903a2deb216044a69c4d7d28bb7d3f1e19f41b29e3fe05e4bad5944d': {
        'imageSize': (2068, 1146), 'controls': [
            ('Printed_face_0', ('Rocker_0',), (218, 809, 290, 981)),
            ('Printed_face_1', ('Rocker_1',), (1670, 809, 1742, 980)),
            ('Printed_face_1', ('Menu_key',), (1239, 772, 1273, 832)),
            ('Printed_face_1', ('Menu_key.001',), (1341, 772, 1376, 832)),
            ('Printed_face_1', ('Menu_key.002',), (1439, 771, 1474, 832))]}}

# The 20 October rear/battery refinement preserves these faceplate images,
# UVs, control vertices and local transforms byte-for-byte. Keep the same
# inspected registration while retaining its newly refined rear geometry.
PROFILES['089e1af86f9b651f7aaee1be754cb80d26abf03d2bba3a881aeceeb1311b4d0f'] = (
    PROFILES['2fe07958903a2deb216044a69c4d7d28bb7d3f1e19f41b29e3fe05e4bad5944d'])


def transform(m, p):
    return tuple(sum(m[c*4+r]*p[c] for c in range(3))+m[12+r] for r in range(3))


def node_matrix(node):
    if 'matrix' in node:
        return node['matrix']
    x, y, z, w = node.get('rotation', (0, 0, 0, 1))
    norm = (x*x+y*y+z*z+w*w)**.5
    x, y, z, w = (v/norm for v in (x, y, z, w))
    sx, sy, sz = node.get('scale', (1, 1, 1))
    return [(1-2*y*y-2*z*z)*sx, (2*x*y+2*w*z)*sx, (2*x*z-2*w*y)*sx, 0,
            (2*x*y-2*w*z)*sy, (1-2*x*x-2*z*z)*sy, (2*y*z+2*w*x)*sy, 0,
            (2*x*z+2*w*y)*sz, (2*y*z-2*w*x)*sz, (1-2*x*x-2*y*y)*sz, 0,
            *node.get('translation', (0, 0, 0)), 1]


def fit_transform(old, target):
    sx = (target[2]-target[0])/(old[2]-old[0])
    sy = (target[3]-target[1])/(old[3]-old[1])
    return [sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, 1, 0,
            target[0]-old[0]*sx, target[1]-old[1]*sy, 0, 1]


def register(gltf, binary, profile):
    nodes = {o['name']: (i, o) for i, o in enumerate(gltf['nodes'])}
    parents = {i: parent for parent, o in enumerate(gltf['nodes']) for i in o.get('children', [])}

    def read(index):
        a = gltf['accessors'][index]; v = gltf['bufferViews'][a['bufferView']]
        width = {'VEC2': 2, 'VEC3': 3}[a['type']]
        if a['componentType'] != 5126 or 'sparse' in a:
            raise ValueError('Expected inspected float geometry')
        off = v.get('byteOffset', 0)+a.get('byteOffset', 0)
        return [struct.unpack_from('<'+'f'*width, binary, off+j*v.get('byteStride', width*4))
                for j in range(a['count'])]

    def points(node):
        return [transform(node_matrix(node), p)
                for prim in gltf['meshes'][node['mesh']]['primitives']
                for p in read(prim['attributes']['POSITION'])]

    receipt = []
    for face_name, names, pixels in profile['controls']:
        face_id, face = nodes[face_name]
        prim = gltf['meshes'][face['mesh']]['primitives'][0]
        pos = points(face); uv = read(prim['attributes']['TEXCOORD_0'])
        # These two inspected faceplates are axis-aligned in their own parent.
        xmin, xmax = min(p[0] for p in pos), max(p[0] for p in pos)
        ymin, ymax = min(p[1] for p in pos), max(p[1] for p in pos)
        umin, umax = min(p[0] for p in uv), max(p[0] for p in uv)
        vmin, vmax = min(p[1] for p in uv), max(p[1] for p in uv)
        w, h = profile['imageSize']
        x0, y0, x1, y1 = pixels
        target = (xmin+(x0/w-umin)/(umax-umin)*(xmax-xmin),
                  ymax-(y1/h-vmin)/(vmax-vmin)*(ymax-ymin),
                  xmin+(x1/w-umin)/(umax-umin)*(xmax-xmin),
                  ymax-(y0/h-vmin)/(vmax-vmin)*(ymax-ymin))
        group = [nodes[name] for name in names]
        if any(parents.get(i) != parents.get(face_id) for i, _ in group):
            raise ValueError('Control/face must share the same hinge parent')
        before = [p for _, node in group for p in points(node)]
        old = (min(p[0] for p in before), min(p[1] for p in before),
               max(p[0] for p in before), max(p[1] for p in before))
        fit = fit_transform(old, target)
        for _, node in group:
            original = node_matrix(node)
            result = [sum(fit[k*4+r]*original[c*4+k] for k in range(4))
                      for c in range(4) for r in range(4)]
            for key in ('translation', 'rotation', 'scale'):
                node.pop(key, None)
            node['matrix'] = result
        after = [p for _, node in group for p in points(node)]
        actual = (min(p[0] for p in after), min(p[1] for p in after),
                  max(p[0] for p in after), max(p[1] for p in after))
        if max(abs(a-b) for a, b in zip(actual, target)) > 1e-8:
            raise ValueError('Control registration failed')
        receipt.append({'nodes': names, 'face': face_name, 'pixels': pixels,
                        'before': old, 'after': actual})
    # The reconstruction used pale grey for controls photographed charcoal.
    # Register the raised surface colour too, not only its footprint.
    menu = next(m for m in gltf['materials'] if m['name'] == 'Menu buttons')
    menu['pbrMetallicRoughness']['baseColorFactor'] = [.012, .015, .016, 1]
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.source.read_bytes(); sha = hashlib.sha256(raw).hexdigest()
    if sha not in PROFILES:
        raise ValueError('No inspected registration profile for this source hash')
    length, tag = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or tag != 0x4e4f534a:
        raise ValueError('Expected GLB')
    gltf = json.loads(raw[20:20+length]); binary = raw[28+length:]
    receipt = register(gltf, binary, PROFILES[sha])
    gltf.setdefault('extras', {})['controlRegistration'] = {
        'sourceSha256': sha, 'method': 'Raised controls fitted to original faceplate pixels',
        'controls': receipt}
    encoded = json.dumps(gltf, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    # Preserve the complete BIN chunk (header included), textures, clips and UVs.
    tail = raw[20+length:]
    output = struct.pack('<4sII', b'glTF', 2, 20+len(encoded)+len(tail))
    output += struct.pack('<II', len(encoded), 0x4e4f534a)+encoded+tail
    with args.output.open('xb') as stream:
        stream.write(output)
    print(json.dumps({'sourceSha256': sha, 'derivedSha256': hashlib.sha256(output).hexdigest(),
                      'controls': receipt}))


if __name__ == '__main__':
    main()
