"""Inspection captions must follow the packed edition, including held rows."""
import io,json,sys,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch,MagicMock
from PIL import Image
sys.path.insert(0,str(Path(__file__).parent))
import packaging_resource_sheet as sheets


class ResourceSheetTest(unittest.TestCase):
    def test_filtered_pack_titles_use_edition_identity_instead_of_report_position(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);pack=root/'pack.zip'
            image=io.BytesIO();Image.new('RGB',(8,8),'navy').save(image,format='PNG')
            with zipfile.ZipFile(pack,'w') as archive:
                archive.writestr('packaging.json',json.dumps({'games':[{'gameId':'game',
                    'editionId':'present','resources':[{'type':'box-2D','importReference':{'sha256':'body'}}]}]}))
                archive.writestr('images/body.png',image.getvalue())
            pack.with_suffix('.report.json').write_text(json.dumps([
                {'editionId':'held','title':'Held entry'}, {'editionId':'present','title':'Actual packed game'}]))
            draw=MagicMock()
            with patch.object(sys,'argv',['sheet','--pack',str(pack),'--output',str(root/'sheets')]), \
                    patch.object(sheets.ImageDraw,'Draw',return_value=draw):
                sheets.main()
            labels=[call.args[1] for call in draw.text.call_args_list]
            self.assertIn('1. Actual packed game',labels)
            self.assertNotIn('1. Held entry',labels)


if __name__=='__main__':unittest.main()
