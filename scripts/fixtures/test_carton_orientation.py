"""Orientation is checked after UV mapping, never from texture/name alone."""
import hashlib
import io
import struct
from pathlib import Path
import sys
import tempfile
import unittest

from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
import verify_carton_orientation as orientation


class CartonOrientationTest(unittest.TestCase):
    def fixture(self, root, *, compensate=False):
        image=Image.new('RGB',(64,64),'red')
        image.paste('green',(32,0,64,32))
        image.paste('blue',(0,32,32,64))
        image.paste('yellow',(32,32,64,64))
        raw=image.transpose(Image.Transpose.ROTATE_90) if compensate else image
        body=io.BytesIO(); raw.save(body,format='PNG')
        (root/'front.png').write_bytes(body.getvalue())
        mesh=bytearray()
        vertices=[(-1,-1),(1,-1),(1,1),(-1,-1),(1,1),(-1,1)]
        for x,y in vertices:
            u,v=(x+1)/2,(1-y)/2
            if compensate:u,v=v,1-u
            mesh.extend(struct.pack('<8f',x,y,.1,0,0,1,u,v))
        index=len(mesh)
        mesh.extend(struct.pack('<6I',*range(6)))
        model={'geometrySha256':hashlib.sha256(mesh).hexdigest(),
            'textureFiles':{'front.png':hashlib.sha256(body.getvalue()).hexdigest()},
            'surfaces':[{'name':'Scanned back', 'vertexOffset':0,'vertexCount':6,
                'indexOffset':index,'indexCount':6,
                'material':{'color':[1,1,1,1],'textures':{'albedo':'front.png'}}}]}
        return model,bytes(mesh),image

    def test_compensating_texture_and_uv_rotation_is_not_a_model_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            model,mesh,original=self.fixture(root,compensate=True)
            panel=orientation.visible_panel(model,mesh,side='front')
            rendered=orientation.assembled_panel(root,model,mesh,panel,maximum=64)
            for point in [(16,16),(48,16),(16,48),(48,48)]:
                self.assertEqual(rendered.getpixel(point),original.getpixel(point))
            self.assertEqual(panel['surfaceIndex'],0)
            self.assertEqual(panel['surfaceName'],'Scanned back')

    def test_rotated_ocr_and_ambiguous_ocr_cannot_pass(self):
        upright='Nintendo Entertainment System Super Adventure'
        records={angle:{'text':upright if angle==90 else 'xq 1'} for angle in [0,90,180,270]}
        result=orientation.orientation_evidence(records,title='Super Adventure')
        self.assertEqual(result['status'],'rotated')
        self.assertEqual(result['clockwiseCorrectionDegrees'],90)
        records={angle:{'text':upright} for angle in records}
        self.assertEqual(orientation.orientation_evidence(records,title='Super Adventure')['status'],'uncertain')
        records={angle:{'text':''} for angle in records}
        self.assertEqual(orientation.orientation_evidence(records,title='Super Adventure')['status'],'uncertain')

    def test_expected_and_brand_anchors_establish_upright_evidence(self):
        records={angle:{'text':'Super Adventure Nintendo' if angle==0 else ''} for angle in [0,90,180,270]}
        result=orientation.orientation_evidence(records,title='Super Adventure')
        self.assertEqual(result['status'],'upright')
        self.assertEqual(result['clockwiseCorrectionDegrees'],0)
        self.assertIn('nintendo',result['candidates'][0]['anchors'])

    def test_changed_mesh_or_texture_cannot_be_validated(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            model,mesh,_=self.fixture(root)
            panel=orientation.visible_panel(model,mesh,side='front')
            (root/'front.png').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'texture.*digest'):
                orientation.assembled_panel(root,model,mesh,panel)
            with self.assertRaisesRegex(ValueError,'geometry.*digest'):
                orientation.visible_panel(model,mesh+b'changed',side='front')


if __name__=='__main__':unittest.main()
