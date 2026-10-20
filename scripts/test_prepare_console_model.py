"""Real Blender adapter regression; scratch stays in the caller's task directory."""
import base64
import json
import os
from pathlib import Path
import struct
import subprocess
import unittest

class ConsoleAdapterTest(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('RSHOP_BLENDER') and os.environ.get('RSHOP_ADAPTER_TEST_DIR'), 'Explicit Blender and task scratch required')
    def test_untextured_uv_absence_and_textured_rejection(self):
        root = Path(os.environ['RSHOP_ADAPTER_TEST_DIR']);root.mkdir(parents=True, exist_ok=False)
        binary = struct.pack('<18f', -1, -1, 0, 1, -1, 0, 0, 1, 0, *([0,0,1]*3))
        image = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ZkAAAAASUVORK5CYII=')
        for name, textured, glass in [('solid', False, False), ('glass', False, True), ('textured', True, False)]:
            payload = binary + (image if textured else b'')
            gltf = {'asset':{'version':'2.0'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0}],
                'meshes':[{'name':'part','primitives':[{'attributes':{'POSITION':0,'NORMAL':1},'material':0}]}],
                'materials':[{'name':'part-material','pbrMetallicRoughness':{'baseColorFactor':[.3,.2,.1,1], **({'baseColorTexture':{'index':0}} if textured else {})}}],
                'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3','min':[-1,-1,0],'max':[1,1,0]},
                             {'bufferView':1,'componentType':5126,'count':3,'type':'VEC3'}],
                'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':36},{'buffer':0,'byteOffset':36,'byteLength':36}],
                'buffers':[{'byteLength':len(payload)}],'images':[],'textures':[]}
            if glass:
                gltf['materials'][0]['extensions'] = {'KHR_materials_transmission': {'transmissionFactor': .92}, 'KHR_materials_ior': {'ior': 1.46}}
                gltf['extensionsUsed'] = ['KHR_materials_transmission', 'KHR_materials_ior']
            if textured:
                gltf['bufferViews'].append({'buffer':0,'byteOffset':72,'byteLength':len(image)})
                gltf['images']=[{'bufferView':2,'mimeType':'image/png'}];gltf['textures']=[{'source':0}]
            header=json.dumps(gltf).encode();header+=b' '*((-len(header))%4);payload+=b'\0'*((-len(payload))%4)
            src=root/(name+'.glb');src.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(header)+len(payload))+struct.pack('<I4s',len(header),b'JSON')+header+struct.pack('<I4s',len(payload),b'BIN\0')+payload)
            out=root/(name+'-output')
            result=subprocess.run([os.environ['RSHOP_BLENDER'],'--background','--factory-startup','--python-exit-code','1','--python',str(Path(__file__).with_name('prepare_console_model.py')),'--','--source',str(src),'--output',str(out),'--system','gameandwatch','--rom-set','gnw_ball','--author','Fixture','--source-url','local:fixture'],capture_output=True,text=True,encoding='utf8')
            (root/(name+'.log')).write_text(result.stdout+result.stderr,encoding='utf8')
            if textured:
                self.assertNotEqual(result.returncode,0)
                self.assertIn('Textured mesh part has no UV coordinates',result.stdout+result.stderr)
                self.assertFalse(out.exists())
            else:
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                model=json.loads((out/'model.json').read_text())
                self.assertEqual(model['textureFiles'],{})
                self.assertEqual(model['surfaces'][0]['material']['color'],[.3,.2,.1,1])
                self.assertEqual(model['surfaces'][0]['vertexCount'],3)
                if glass:
                    props=model['surfaces'][0]['material']['sourceProperties']
                    self.assertAlmostEqual(props.get('transmission',0),.92)
                    self.assertAlmostEqual(props.get('ior',1.5),1.46)

if __name__ == '__main__':unittest.main()
