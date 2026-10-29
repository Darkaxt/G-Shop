"""Filename mapping keeps exact names, platform ownership and source membership."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from prepare_collection_catalogue import (filename_title, source_kind, inventory, lookup, match, registry,
    source_games, screenscraper_csv, regional_alias, load_title_aliases, resolve_source, title_key)


class CollectionCatalogueTest(unittest.TestCase):
    def test_reviewed_gb_gbc_namespace_requires_exact_source_and_keeps_native_priority(self):
        source={'system':'gb','family':'root','sourceKind':'program','title':'The Machine',
                'filename':'The Machine (World).7z','sourcePath':'Game Boy/The Machine (World).7z'}
        game={'id':'7','title':'The Machine','aliases':[],'platformName':'Nintendo Game Boy Color'}
        index={'platforms':{'gb':{},'gbc':{'7':game}},'screenscraper':{'gb':{},'gbc':{}}}
        rule={'system':'gb','sourceTitle':'The Machine','sourcePaths':[source['sourcePath']],
              'providers':{'launchbox':{'id':'7','title':'The Machine','catalogueNamespace':'gbc'}},
              'reason':'Author publishes the Game Boy programme; catalogue puts it in GBC.'}
        reviews={('gb','the machine'):[rule]}
        self.assertNotIn('launchbox',resolve_source(source,index,{},matcher_version=7)[1])
        with self.assertRaisesRegex(ValueError,'reviewed programme namespace'):
            resolve_source(source,index,{},reviews,matcher_version=6)
        matches,providers=resolve_source(source,index,{},reviews,matcher_version=7)
        self.assertEqual((providers['launchbox']['id'],providers['launchbox']['catalogueNamespace']),('7','gbc'))
        self.assertEqual(matches['launchbox']['catalogueNamespace'],'gbc')
        rule.pop('sourcePaths')
        with self.assertRaisesRegex(ValueError,'reviewed programme namespace'):
            resolve_source(source,index,{},reviews,matcher_version=7)
        rule['sourcePaths']=[source['sourcePath']]
        index['platforms']['gb']['native']={'id':'native','title':'The Machine','aliases':[]}
        with self.assertRaisesRegex(ValueError,'native provider'):
            resolve_source(source,index,{},reviews,matcher_version=7)

    def test_reviewed_namespace_cannot_cross_generations_or_restore_exclusions(self):
        source={'system':'gb','family':'root','sourceKind':'program','title':'Game',
                'filename':'Game.zip','sourcePath':'GB/Game.zip'}
        index={'platforms':{'gb':{},'gbc':{'7':{'id':'7','title':'Game','aliases':[]}}},
               'screenscraper':{'gb':{},'gbc':{}}}
        rule={'system':'gb','sourceTitle':'Game','sourcePaths':[source['sourcePath']],
              'providers':{'launchbox':{'id':'7','title':'Game','catalogueNamespace':'nes'}},'reason':'Invalid platform'}
        reviews={('gb','game'):[rule]}
        with self.assertRaisesRegex(ValueError,'reviewed programme namespace'):
            resolve_source(source,index,{},reviews,matcher_version=7)
        rule['providers']['launchbox']['catalogueNamespace']='gbc';rule['blockedProviders']=['launchbox']
        with self.assertRaisesRegex(ValueError,'reviewed programme namespace'):
            resolve_source(source,index,{},reviews,matcher_version=7)
        rule.pop('blockedProviders');source['sourceKind']='firmware'
        with self.assertRaisesRegex(ValueError,'reviewed programme namespace'):
            resolve_source(source,index,{},reviews,matcher_version=7)

    def test_exact_source_correction_names_rejected_canonical_id(self):
        source={'system':'nes','family':'root','sourceKind':'program','title':'Parody World',
                'filename':'Parody World (Japan) (Proto).7z','sourcePath':'Public/Parody World (Japan) (Proto).7z'}
        index={'platforms':{'nes':{
            'hack':{'id':'hack','title':'Parody World','aliases':[]},
            'original':{'id':'original','title':'Monster Party','aliases':['Parody World']}}},
            'screenscraper':{'nes':{}}}
        rule={'system':'nes','sourceTitle':'Parody World','sourcePaths':[source['sourcePath']],
              'providers':{'launchbox':{'id':'original','title':'Monster Party'}},
              'replacesProviderIds':{'launchbox':['hack']},'reason':'Full record identifies the canonical entry as a restoration hack.'}
        reviews={('nes','parody world'):[rule]}
        with self.assertRaisesRegex(ValueError,'correction'):
            resolve_source(source,index,{},reviews,matcher_version=5)
        matches,providers=resolve_source(source,index,{},reviews,matcher_version=6)
        self.assertEqual(providers['launchbox']['id'],'original')
        self.assertEqual(matches['launchbox']['rejectedProviderIds'],['hack'])
        rule['replacesProviderIds']['launchbox']=['other']
        with self.assertRaisesRegex(ValueError,'correction'):
            resolve_source(source,index,{},reviews,matcher_version=6)
        rule['replacesProviderIds']['launchbox']=['hack'];rule.pop('sourcePaths')
        with self.assertRaisesRegex(ValueError,'correction'):
            resolve_source(source,index,{},reviews,matcher_version=6)

    def test_canonical_conflict_still_rejects_an_ordinary_review(self):
        source={'system':'nes','family':'root','sourceKind':'program','title':'Original','filename':'Original.zip'}
        index={'platforms':{'nes':{'a':{'id':'a','title':'Original','aliases':[]},
                                'b':{'id':'b','title':'Other','aliases':[]}}},'screenscraper':{'nes':{}}}
        rule={'providers':{'launchbox':{'id':'b','title':'Other'}},'reason':'Insufficient ordinary alias'}
        with self.assertRaisesRegex(ValueError,'unique exact title'):
            resolve_source(source,index,{}, {('nes','original'):[rule]},matcher_version=6)

    def test_exact_source_correction_requires_hashed_evidence_and_single_old_id(self):
        from prepare_collection_catalogue import sha
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);evidence=root/'proof.json';evidence.write_text('full provider records')
            rule={'system':'nes','sourceTitle':'Parody World','sourcePaths':['Public/Proto.zip'],
                  'providers':{'launchbox':{'id':'original','title':'Monster Party'}},
                  'replacesProviderIds':{'launchbox':['hack']},'reason':'Specific source correction'}
            document={'version':1,'rules':[rule]};path=root/'rules.json'
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError,'requires evidence'):
                load_title_aliases(path)
            document['evidence']=[{'path':str(evidence),'sha256':sha(evidence)}]
            path.write_text(json.dumps(document));self.assertTrue(load_title_aliases(path))
            rule['replacesProviderIds']['launchbox']=['hack','another']
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError,'one rejected ID'):
                load_title_aliases(path)

    def test_explicit_gb_compatible_source_can_use_actual_game_boy_records(self):
        source={'system':'gbc','family':'root','sourceKind':'program','title':'Airaki!',
                'filename':'Airaki! (World) (GB Compatible) (Aftermarket) (Unl).7z'}
        game={'id':'7','title':'Airaki!','aliases':[],'platformName':'Nintendo Game Boy'}
        index={'platforms':{'gbc':{},'gb':{'7':game}},'screenscraper':{'gbc':{},'gb':{}}}
        self.assertNotIn('launchbox',resolve_source(source,index,{},matcher_version=4)[1])
        result=resolve_source(source,index,{},matcher_version=5)[1]['launchbox']
        self.assertEqual((result['id'],result['platformName'],result['catalogueNamespace']),
                         ('7','Nintendo Game Boy','gb'))
        self.assertEqual(source['system'],'gbc')
        for updates in ({'filename':'Airaki! (World).7z'}, {'sourceKind':'card-data'}, {'system':'gba'}):
            altered={**source,**updates}
            index['platforms'].setdefault(altered['system'],{})
            index['screenscraper'].setdefault(altered['system'],{})
            self.assertNotIn('launchbox',resolve_source(altered,index,{},matcher_version=5)[1])

    def test_gb_compatible_lookup_keeps_native_platform_precedence_and_exclusions(self):
        source={'system':'gbc','family':'root','sourceKind':'program','title':'Game',
                'sourcePath':'gbc/Game.7z','filename':'Game (World) (GB Compatible).7z'}
        primary={'id':'color','title':'Game','aliases':[],'platformId':10}
        older={'id':'mono','title':'Game','aliases':[],'platformId':9}
        index={'platforms':{'gbc':{},'gb':{}},'screenscraper':{'gbc':{'color':primary},'gb':{'mono':older}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=5)[1]['screenscraper']['id'],'color')
        index['screenscraper']['gbc']={}
        index['platforms']['gbc']={'lb':{'id':'lb','title':'Game','aliases':[]}}
        rule={'system':'gbc','sourceTitle':'Game','providers':{'launchbox':{'id':'lb','title':'Game'}},
              'blockedProviders':['screenscraper'],'reason':'A proven different programme.'}
        reviews={('gbc',title_key('Game')):[rule]}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},reviews,matcher_version=5)[1])
        index['screenscraper']['gbc']={'a':{**primary,'id':'a'},'b':{**primary,'id':'b'}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=5)[1])

    def test_explicit_publisher_qualifier_resolves_screenscraper_as_well_as_launchbox(self):
        source={'system':'nes','family':'Translations','sourceKind':'program','title':'Star Wars',
                'filename':'Translations/Star Wars (Japan) (Namco) [T-En v2.0].7z'}
        games={'namco':{'id':'namco','title':'Star Wars (namco)','aliases':['Star Wars']},
               'beam':{'id':'beam','title':'Star Wars (beam)','aliases':['Star Wars']}}
        index={'platforms':{'nes':{}},'screenscraper':{'nes':games}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=4)[1]['screenscraper']['id'],'namco')
        source['filename']='Star Wars (USA) (Limited Run Games).7z'
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=4)[1])

    def test_numeric_release_annotations_do_not_become_part_of_the_game_lookup(self):
        source={'system':'gba','family':'Hacks','sourceKind':'program',
                'title':'Pokemon Emerald Ex (1.0.4)','filename':'Hacks/Pokemon Emerald Ex (1.0.4).7z'}
        index={'platforms':{'gba':{}},'screenscraper':{'gba':{
            'hack':{'id':'hack','title':'Pokemon Emerald Ex','aliases':[]},
            'base':{'id':'base','title':'Pokemon Emerald','aliases':[]}}}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=4)[1]['screenscraper']['id'],'hack')
        for title in ['Pokemon Emerald Ex (2026-01-25)','Pokemon Emerald Ex (20-9-26)',
                      'Pokemon Emerald Ex (22.08.26)']:
            source['title']=title
            self.assertEqual(resolve_source(source,index,{},matcher_version=4)[1]['screenscraper']['id'],'hack')
        source['title']='Pokemon Emerald Ex (Gen 2 GFX)'
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=4)[1])
        source.update(title='Pokemon Emerald Ex (1.0.4)',family='Multiboot')
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=4)[1])

    def test_exact_version_record_and_ambiguous_parent_keep_their_precedence(self):
        source={'system':'gba','family':'root','sourceKind':'program','title':'Game (1.2.3)',
                'filename':'Game (1.2.3).7z'}
        games={'exact':{'id':'exact','title':'Game (1.2.3)','aliases':[]},
               'parent':{'id':'parent','title':'Game','aliases':[]}}
        index={'platforms':{'gba':{}},'screenscraper':{'gba':games}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=4)[1]['screenscraper']['id'],'exact')
        del games['exact'];games['duplicate']={**games['parent'],'id':'duplicate'}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=4)[1])

    def test_number_spellings_match_the_same_sequel_without_global_fuzzy_matching(self):
        source={'system':'snes','family':'root','sourceKind':'program',
                'title':'Super Castlevania IV','filename':'Super Castlevania IV (USA).7z'}
        games={'4':{'id':'4','title':'Super Castlevania 4','aliases':[]},
               '3':{'id':'3','title':'Super Castlevania 3','aliases':[]}}
        index={'platforms':{'snes':{}},'screenscraper':{'snes':games}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['screenscraper']['id'],'4')
        games['duplicate']={**games['4'],'id':'duplicate'}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])

    def test_numeral_matching_preserves_single_letters_abbreviations_and_subtitles(self):
        cases=[('Mega Man X','Mega Man 10'),('VIP','6P'),('DS','500S'),
               ('Super Fire Pro Wrestling III - Easy Type','Super Fire Pro Wrestling 3 - Final Bout')]
        for source_title,provider_title in cases:
            source={'system':'snes','family':'root','sourceKind':'program',
                    'title':source_title,'filename':source_title+' (USA).7z'}
            index={'platforms':{'snes':{}},'screenscraper':{'snes':{
                '1':{'id':'1','title':provider_title,'aliases':[]}}}}
            self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])

    def test_numerals_do_not_link_download_play_to_a_retail_owner(self):
        source={'system':'nds','family':'Download Play','sourceKind':'program',
                'title':'Game II','filename':'Download Play/Game II (USA).7z'}
        index={'platforms':{'nds':{}},'screenscraper':{'nds':{
            '1':{'id':'1','title':'Game 2','aliases':[]}}}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])

    def test_hash_suffix_is_an_edition_marker_and_survives_number_spelling(self):
        games={'base':{'id':'base','title':'Project DIVA 2nd','aliases':[]},
               'sharp':{'id':'sharp','title':'Project DIVA 2nd#','aliases':[]}}
        source={'system':'psp','family':'root','sourceKind':'program',
                'title':'Project DIVA 2nd','filename':'Project DIVA 2nd (Japan).zip'}
        index={'platforms':{'psp':{}},'screenscraper':{'psp':games}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['screenscraper']['id'],'base')
        source['title']='Project DIVA 2nd#'
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['screenscraper']['id'],'sharp')
        source.update(system='snes',title='Game II',filename='Game II (USA).7z')
        index={'platforms':{'snes':{}},'screenscraper':{'snes':{
            'sharp':{'id':'sharp','title':'Game 2#','aliases':[]}}}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])
        source['title']='Game#'
        index['screenscraper']['snes']['sharp'].update(title='Game',aliases=[])
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])
        index['screenscraper']['snes']['sharp']['aliases']=['Game#']
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['screenscraper']['id'],'sharp')

    def test_provider_html_entities_are_decoded_without_removing_title_words(self):
        source={'system':'gb','family':'root','sourceKind':'program',
                'title':'Learn and Play - Blackjack & Solitaire',
                'filename':'Learn and Play - Blackjack & Solitaire (USA).7z'}
        index={'platforms':{'gb':{}},'screenscraper':{'gb':{
            '1':{'id':'1','title':'Learn and Play - Blackjack &amp; Solitaire','aliases':[]}}}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['screenscraper']['id'],'1')
        source['title']='Learn and Play - Blackjack & Poker'
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])

    def test_provider_corroboration_uses_the_same_sequel_spelling_as_direct_lookup(self):
        source={'system':'gb','family':'root','sourceKind':'program',
                'title':'Rockman World 2','filename':'Rockman World 2 (Japan).7z'}
        index={'platforms':{'gb':{'lb':{'id':'lb','title':'Mega Man II','aliases':['Rockman World 2']}}},
               'screenscraper':{'gb':{'ss':{'id':'ss','title':'Mega Man 2','aliases':[]}}}}
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['screenscraper']['id'],'ss')
        # A provider alias can be overbroad; corroboration still anchors on its
        # selected canonical identity and cannot drop a sequel or DX modifier.
        index['platforms']['gb']['lb'].update(title='Taz-Mania 2',aliases=['Taz-Mania'])
        index['screenscraper']['gb']['ss']['title']='Taz-Mania'
        source.update(title='Taz-Mania 2',filename='Taz-Mania 2 (USA).7z')
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=3)[1])

    def test_expanded_corroboration_cannot_displace_an_exact_canonical_binding(self):
        source={'system':'gb','family':'root','sourceKind':'program',
                'title':'Regional Name','filename':'Regional Name (Japan).7z'}
        index={'platforms':{'gb':{
            'exact':{'id':'exact','title':'Game 4','aliases':[]},
            'other':{'id':'other','title':'Game IV','aliases':[]}}},
            'screenscraper':{'gb':{'ss':{'id':'ss','title':'Game 4','aliases':['Regional Name']}}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['launchbox']['id'],'exact')
        self.assertEqual(resolve_source(source,index,{},matcher_version=3)[1]['launchbox']['id'],'exact')

    def test_provider_rom_filenames_repair_names_without_borrowing_another_revision(self):
        source={'system':'nds','family':'root','title':'Older Local Title',
                'filename':'0123 - Older Local Title (USA) (Rev 1).7z'}
        game={'id':'7','title':'New Canonical Title','aliases':[],
              'romNames':['Older Local Title (USA) (Rev 1).nds']}
        index={'platforms':{'nds':{}},'screenscraper':{'nds':{'7':game}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['screenscraper']['id'],'7')
        source['filename']='0123 - Older Local Title (USA) (Rev 2).7z'
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])

    def test_card_filename_keys_retain_card_codes_series_and_region(self):
        source={'system':'gba','family':'e-Reader','sourceKind':'card-data',
                'title':'Animal Crossing-e - Series 1 - A-001 - K.K. Slider',
                'filename':'e-Reader/Animal Crossing-e - Series 1 - A-001 - K.K. Slider (USA).7z'}
        game={'id':'7','title':'Animal Crossing Card-e','aliases':[], 'platformId':119,
              'romNames':['Animal Crossing-e - Series 1 - A-001 (U).e']}
        index={'platforms':{'ereader':{}},'screenscraper':{'ereader':{'7':game}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['screenscraper']['id'],'7')
        for filename in ['Animal Crossing-e - Series 1 - A-002 (USA).7z',
                         'Animal Crossing-e - Series 2 - A-001 (USA).7z',
                         'Animal Crossing-e - Series 1 - A-001 (Japan).7z']:
            source['filename']='e-Reader/'+filename
            self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])

    def test_global_card_identifier_survives_provider_omitted_card_e_plus(self):
        source={'system':'gba','family':'e-Reader','sourceKind':'card-data',
                'title':'F-Zero - Falcon Densetsu Card-e+ - Carddas Ban - 14-A001',
                'filename':'e-Reader/F-Zero - Falcon Densetsu Card-e+ - Carddas Ban - 14-A001 (Japan).7z'}
        game={'id':'7','title':'F-Zero - Falcon Densetsu Card-e+','aliases':[], 'platformId':119,
              'romNames':['F-Zero - Falcon Densetsu Card-e - Carddas Ban - 14-A001 (Japan).zip']}
        index={'platforms':{'ereader':{}},'screenscraper':{'ereader':{'7':game}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['screenscraper']['id'],'7')

    def test_card_name_variant_retains_collection_series_when_provider_omits_code(self):
        source={'system':'gba','family':'e-Reader','sourceKind':'card-data',
                'title':'Animal Crossing-e - Series 1 - A-003 - Porter',
                'filename':'e-Reader/Animal Crossing-e - Series 1 - A-003 - Porter (USA).7z'}
        game={'id':'7','title':'Animal Crossing Card-e','aliases':[], 'platformId':119,
              'romNames':['Animal Crossing-e - Series 1 - Porter (USA).zip']}
        index={'platforms':{'ereader':{}},'screenscraper':{'ereader':{'7':game}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['screenscraper']['id'],'7')
        source['filename']='e-Reader/Animal Crossing-e - Series 2 - A-003 - Porter (USA).7z'
        self.assertNotIn('screenscraper',resolve_source(source,index,{},matcher_version=2)[1])

    def test_qualified_game_names_use_explicit_source_author_or_publisher(self):
        games={'1':{'id':'1','title':'Felix the Cat (Dragon)','aliases':['Felix the Cat']},
               '2':{'id':'2','title':'Felix the Cat (Hudson)','aliases':['Felix the Cat']}}
        source={'system':'nes','family':'Public (iNES2)','title':'Felix the Cat',
                'filename':'Public (iNES2)/Felix the Cat (China) (En) (Dragon Co.) (Unl).7z'}
        index={'platforms':{'nes':games},'screenscraper':{'nes':{}}}
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['launchbox']['id'],'1')
        source['filename']='Felix the Cat (World).7z'
        self.assertNotIn('launchbox',resolve_source(source,index,{},matcher_version=2)[1])

    def test_ereader_cards_use_their_own_catalogue_and_remain_card_data(self):
        from prepare_collection_catalogue import catalogue_namespace
        source={'system':'gba','family':'e-Reader','sourceKind':'card-data',
                'title':'Air Hockey-e','filename':'e-Reader/Air Hockey-e - 00-B000 (USA).7z'}
        self.assertEqual(source_kind(source['filename'],'gba'),'card-data')
        self.assertEqual(catalogue_namespace(source),'ereader')
        game={'id':'7','title':'Air Hockey-e','aliases':[], 'platformId':119}
        index={'platforms':{'gba':{},'ereader':{}},'screenscraper':{'gba':{},'ereader':{'7':game}}}
        self.assertEqual(resolve_source(source,index,{})[1]['screenscraper']['platformId'],119)
        # Old immutable inventories retain their pre-namespace interpretation.
        source['sourceKind']='program'
        self.assertEqual(catalogue_namespace(source),'gba')

    def test_sg1000_collision_prefers_sg1000_without_discarding_sc3000_exclusives(self):
        games={'1':{'id':'1','title':'Bank Panic','aliases':[], 'platformName':'Sega SG-1000'},
               '2':{'id':'2','title':'Bank Panic','aliases':[], 'platformName':'Sega SC-3000'},
               '3':{'id':'3','title':'SC Only','aliases':[], 'platformName':'Sega SC-3000'}}
        source={'system':'sg1000','family':'root','title':'Bank Panic','filename':'Bank Panic (Japan).zip'}
        index={'platforms':{'sg1000':games},'screenscraper':{'sg1000':{}}}
        self.assertNotIn('launchbox',resolve_source(source,index,{})[1])
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['launchbox']['id'],'1')
        source.update(title='SC Only',filename='SC Only (Japan).zip')
        self.assertEqual(resolve_source(source,index,{},matcher_version=2)[1]['launchbox']['id'],'3')
        games['4']={**games['1'],'id':'4'}
        source.update(title='Bank Panic',filename='Bank Panic (Japan).zip')
        self.assertNotIn('launchbox',resolve_source(source,index,{},matcher_version=2)[1])

    def test_source_role_preserves_firmware_and_addon_boundaries(self):
        cases = [
            ('SNES/SuFami Turbo (Japan).7z', 'snes', 'firmware'),
            ('SNES/SuFami Turbo Adventures (Japan).7z', 'snes', 'program'),
            ('Nintendo - DS/[BIOS] Nintendo DS.7z', 'nds', 'firmware'),
            ('Firmware/Boot ROM.bin', 'gba', 'firmware'),
            ('Texture Packs/Game.zip', 'n64', 'auxiliary-resource'),
            ('0004008C0007AE00 Game (DLC).zcia', 'n3ds', 'dlc'),
            ('0004000E0007AE00 Game (Update).zcia', 'n3ds', 'update'),
            ('Game (USA).7z', 'snes', 'program'),
        ]
        for filename, system, expected in cases:
            with self.subTest(filename=filename):
                self.assertEqual(source_kind(filename, system), expected)

    def test_regional_alias_resolves_same_name_without_merging_different_games(self):
        games={'1':{'title':'Castle','aliases':['Mickey Mouse'], 'aliasRegions':{'Mickey Mouse':['Japan']}},
               '2':{'title':'Castle 2','aliases':['Mickey Mouse'], 'aliasRegions':{'Mickey Mouse':['Europe']}}}
        finding=match('Mickey Mouse',lookup(games))
        self.assertEqual(finding['status'],'ambiguous')
        self.assertEqual(regional_alias({'title':'Mickey Mouse','filename':'Mickey Mouse (Japan).7z'},finding,games)['ids'],['1'])
        self.assertEqual(regional_alias({'title':'Mickey Mouse','filename':'Mickey Mouse (Europe).7z'},finding,games)['ids'],['2'])
        self.assertEqual(regional_alias({'title':'Mickey Mouse','filename':'Mickey Mouse (World).7z'},finding,games)['status'],'ambiguous')

    def test_reviewed_title_order_alias_is_scoped_and_rejects_foreign_ids(self):
        source={'system':'n3ds','family':'root','title':'Metal Gear Solid 3D - Snake Eater',
                'filename':'Metal Gear Solid 3D - Snake Eater (USA).zcci'}
        game={'id':'7','title':'Metal Gear Solid: Snake Eater 3D','aliases':[], 'platformName':'Nintendo 3DS'}
        index={'platforms':{'n3ds':{'7':game}},'screenscraper':{'n3ds':{}}}
        rule={'system':'n3ds','sourceTitle':source['title'],'reason':'Reviewed 3D marker relocation',
              'providers':{'launchbox':{'id':'7','title':game['title']}}}
        reviews={('n3ds',title_key(source['title'])):[rule]}
        self.assertEqual(resolve_source(source,index,{})[1],{})
        matches,providers=resolve_source(source,index,{},reviews)
        self.assertEqual(providers['launchbox']['id'],'7')
        self.assertEqual(matches['launchbox']['method'],'reviewed-scoped-alias')
        rule['providers']['launchbox']['id']='8'
        with self.assertRaisesRegex(ValueError,'foreign'):
            resolve_source(source,index,{},reviews)

    def test_reviewed_alias_retains_region_and_revision_selectors(self):
        from prepare_collection_catalogue import reviewed_alias
        rule={'system':'gbc','sourceTitle':'Chromanoids','regions':['World'],'tags':['v1.0'],
              'providers':{'screenscraper':{'id':'1','title':'Chromanoids'}},'reason':'Exact revision proof'}
        reviews={('gbc','chromanoids'):[rule]}
        source={'system':'gbc','title':'Chromanoids','filename':'Chromanoids (World) (v1.0).7z'}
        self.assertIs(reviewed_alias(source,reviews),rule)
        source['filename']='Chromanoids (World) (v1.1).7z'
        self.assertIsNone(reviewed_alias(source,reviews))

    def test_excluded_provider_is_not_restored_by_corroboration(self):
        source={'system':'gb','family':'root','title':'Mickey Mouse',
                'filename':'Mickey Mouse (Japan).7z'}
        game={'id':'1','title':'Correct Game','aliases':['Mickey Mouse']}
        index={'platforms':{'gb':{'1':game}},'screenscraper':{'gb':{
            '2':{'id':'2','title':'Correct Game','aliases':[]}}}}
        rule={'system':'gb','sourceTitle':'Mickey Mouse','regions':['Japan'],
              'reason':'Provider groups a different regional game',
              'providers':{'launchbox':{'id':'1','title':'Correct Game'}},
              'blockedProviders':['screenscraper']}
        self.assertIn('screenscraper',resolve_source(source,index,{})[1])
        matches,providers=resolve_source(source,index,{}, {('gb','mickey mouse'):[rule]})
        self.assertEqual(set(providers),{'launchbox'})
        self.assertEqual(matches['screenscraper']['status'],'reviewed-provider-conflict')

    def test_reviewed_alias_evidence_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            from prepare_collection_catalogue import sha
            evidence=Path(folder)/'evidence.json'
            evidence.write_text('original')
            rules=Path(folder)/'rules.json'
            rules.write_text(json.dumps({'version':1,'evidence':[{'path':str(evidence),'sha256':sha(evidence)}],'rules':[]}))
            self.assertEqual(load_title_aliases(rules),{})
            evidence.write_text('changed')
            with self.assertRaisesRegex(ValueError,'evidence changed'):
                load_title_aliases(rules)

    def test_exact_source_rule_does_not_capture_same_title_download_play(self):
        from prepare_collection_catalogue import reviewed_alias
        source={'system':'nds','title':'Cooking Mama 2','filename':'Cooking Mama 2 (Japan).7z',
                'sourcePath':'Nintendo - DS/6000 - Cooking Mama 2 (Japan).7z'}
        rule={'sourcePaths':[source['sourcePath']]}
        rules={('nds',title_key(source['title'])):[rule]}
        self.assertIs(reviewed_alias(source,rules),rule)
        source['sourcePath']='Nintendo - DS/Download Play/Cooking Mama 2 (Japan).7z'
        self.assertIsNone(reviewed_alias(source,rules))

    def test_registry_covers_actual_supported_app_systems(self):
        systems = registry()
        self.assertEqual(systems['ps2']['screenscraperId'], 58)
        self.assertIn('Sega - Mega Drive', systems['megadrive']['folders'])
        self.assertIn('.rvz', systems['gc']['extensions'])

    def test_blank_provider_row_is_retained_without_discarding_the_platform_index(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'gameslist.csv'
            path.write_text('Game ID;Game Name\n8420;\n1;Known Game\n', encoding='utf-8')
            games, invalid = screenscraper_csv(path, 15)
            self.assertEqual(set(games), {'1'})
            self.assertEqual(invalid, [{'Game ID': '8420', 'Game Name': ''}])
            path.write_text('Game ID;Game Name\n1;Game\n1;Other\n', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                screenscraper_csv(path, 15)

    def test_title_keeps_subtitles_operators_and_non_latin(self):
        self.assertEqual(filename_title('Name (The Movie) (USA) (Rev 1).7z'), 'Name (The Movie)')
        self.assertEqual(filename_title('Final Fantasy ++ (Japan).zip'), 'Final Fantasy ++')
        self.assertEqual(filename_title('游戏 (China).7z'), '游戏')
        self.assertEqual(filename_title('0001 - Electroplankton (Japan).7z', 'nds'), 'Electroplankton')
        self.assertEqual(filename_title('x001 - Known (Japan) (Demo).7z', 'nds'), 'Known')
        self.assertEqual(filename_title('z1234 - Known (Europe).7z', 'nds'), 'Known')
        self.assertEqual(filename_title('x001 - Known (Japan).7z', 'gb'), 'x001 - Known')
        self.assertEqual(filename_title('Pyoro 64 (Unknown) (PAL) (Aftermarket).7z','n64'), 'Pyoro 64')
        self.assertEqual(filename_title('ViviD Dolls (JP, Rev 2).7z','n64'), 'ViviD Dolls')
        self.assertEqual(filename_title('STELLA GLOW (Undub).zcci','n3ds'), 'STELLA GLOW')
        self.assertEqual(title_key('Fantasy Life™'),title_key('Fantasy Life'))
        self.assertNotEqual(title_key('Final Fantasy ++'),title_key('Final Fantasy'))
        self.assertEqual(filename_title('1942 - Game (USA).zip', 'snes'), '1942 - Game')
        self.assertEqual(filename_title('0004000000030800 Mario Kart 7 (CTR-P-AMKE) (v2.4.0) (U).legit.zcci', 'n3ds'), 'Mario Kart 7')
        self.assertEqual(filename_title('0004008C0007AE00 New Super Mario Bros. 2 (CTR-M-ABEE-00) (v0.3.0) (W).piratelegit.zcia', 'n3ds'), 'New Super Mario Bros. 2')
        self.assertEqual(filename_title('000400000F700100 Xenoblade Chronicles 3D (KTR-P-CAFE) (v2.2.0) (U).piratelegit.zcci', 'n3ds'), 'Xenoblade Chronicles 3D')
        self.assertEqual(match('102 Dalmatiens a la Rescousse, Les', lookup({
            '1': {'title': 'Les 102 Dalmatiens a la Rescousse', 'aliases': []}}))['ids'], ['1'])

    def test_canonical_wins_over_another_games_bad_alias_and_collisions_are_held(self):
        names = lookup({'1': {'title': 'Quest', 'aliases': []},
            '2': {'title': 'Quest II', 'aliases': ['Quest']},
            '3': {'title': 'Different', 'aliases': ['Same']},
            '4': {'title': 'Other', 'aliases': ['Same']}})
        self.assertEqual(match('Quest', names)['ids'], ['1'])
        self.assertEqual(match('Same', names)['status'], 'ambiguous')
        self.assertEqual(match('Quest III', names)['status'], 'unmatched')

    def test_word_boundaries_and_numeric_operators_are_not_silently_folded(self):
        names = lookup({'1': {'title': 'Castlequest', 'aliases': []},
            '2': {'title': 'Game 2', 'aliases': []},
            '3': {'title': 'Final Fantasy', 'aliases': []}})
        self.assertEqual(match('Castle Quest', names)['status'], 'loose-candidate')
        self.assertEqual(match('Game -2', names)['status'], 'unmatched')
        self.assertEqual(match('Final Fantasy ++', names)['status'], 'unmatched')
        names = lookup({'1': {'title': "Dewy's Adventure", 'aliases': []}})
        self.assertEqual(match('Dewys Adventure', names)['ids'], ['1'])

    def test_minis_uses_its_provider_namespace_without_changing_app_system(self):
        games = {'1': {'platformName': 'Sony PSP', 'title': 'Game', 'aliases': []},
                 '2': {'platformName': 'Sony PSP Minis', 'title': 'Game', 'aliases': []}}
        scoped = source_games({'system': 'psp', 'family': 'Minis'}, 'launchbox', games)
        self.assertEqual(set(scoped), {'2'})
        self.assertEqual(match('Game', lookup(scoped))['ids'], ['2'])

    def test_translated_64dd_tag_preserves_namespace_and_cache_scope(self):
        games={'1':{'id':'1','platformName':'Nintendo 64','title':'Game','aliases':[]},
               '2':{'id':'2','platformName':'Nintendo 64DD','title':'Game','aliases':[]}}
        index={'platforms':{'n64':games},'screenscraper':{'n64':{}}}
        source={'system':'n64','family':'Translations','title':'Game',
                'filename':'Translations/Game (Japan) (64DD) [T-En].7z'}
        cache={}
        self.assertEqual(resolve_source(source,index,cache)[1]['launchbox']['id'],'2')
        source['filename']='Translations/Game (Japan) [T-En].7z'
        self.assertEqual(resolve_source(source,index,cache)[1]['launchbox']['id'],'1')

    def test_satellaview_namespace_recovers_missing_titles_preserving_existing_ids(self):
        games={'1':{'id':'1','platformName':'Super Nintendo Entertainment System','title':'Known','aliases':[]},
               '2':{'id':'2','platformName':'Nintendo Satellaview','title':'Known','aliases':[]},
               '3':{'id':'3','platformName':'Nintendo Satellaview','title':'Broadcast','aliases':[]}}
        index={'platforms':{'snes':games},'screenscraper':{'snes':{}}}
        source={'system':'snes','family':'Satellaview','title':'Known','filename':'Satellaview/Known (Japan).7z'}
        cache={}
        self.assertEqual(resolve_source(source,index,cache)[1]['launchbox']['id'],'1')
        source.update(title='Broadcast',filename='Satellaview/Broadcast (Japan).7z')
        self.assertEqual(resolve_source(source,index,cache)[1]['launchbox']['id'],'3')
        source.update(family='root',filename='Broadcast (Japan).7z')
        self.assertNotIn('launchbox',resolve_source(source,index,cache)[1])

    def test_satellaview_corroboration_does_not_escape_broadcast_source_scope(self):
        game={'id':'3','platformName':'Nintendo Satellaview','title':'Broadcast','aliases':[]}
        index={'platforms':{'snes':{'3':game}},'screenscraper':{'snes':{
            '4':{'id':'4','platformId':4,'title':'Broadcast','aliases':[]}}}}
        source={'system':'snes','family':'root','title':'Broadcast',
                'filename':'Broadcast (Japan).7z'}
        cache={}
        self.assertNotIn('launchbox',resolve_source(source,index,cache)[1])
        source.update(family='Satellaview',filename='Satellaview/Broadcast (Japan).7z')
        self.assertEqual(resolve_source(source,index,cache)[1]['launchbox']['id'],'3')

    def test_embedded_disk_system_uses_its_own_namespace_and_cache(self):
        source={'system':'nes','family':'Disk System','title':'Same Name',
                'filename':'Disk System/Same Name (Japan).7z'}
        nes={'id':'1','title':'Same Name','aliases':[], 'platformName':'Nintendo Entertainment System'}
        fds={'id':'2','title':'Same Name','aliases':[], 'platformName':'Nintendo Famicom Disk System'}
        index={'platforms':{'nes':{'1':nes},'fds':{'2':fds}},
               'screenscraper':{'nes':{},'fds':{
                   '3':{'id':'3','title':'Same Name','aliases':[], 'platformId':106}}}}
        cache={}
        matches,providers=resolve_source(source,index,cache)
        self.assertEqual(providers['launchbox']['id'],'2')
        self.assertEqual(providers['screenscraper']['platformId'],106)
        source.update(family='root',filename='Same Name (Japan).7z')
        self.assertEqual(resolve_source(source,index,cache)[1]['launchbox']['id'],'1')

    def test_indexes_include_embedded_fds_without_separate_fds_folder(self):
        from prepare_collection_catalogue import indexes
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            census=root/'inventory.json'
            settings={'nes':{'launchbox':['Nintendo Entertainment System'],'screenscraperId':3},
                      'fds':{'launchbox':['Nintendo Famicom Disk System'],'screenscraperId':106}}
            census.write_text(json.dumps({'supportedSystems':settings,
                'systems':{'nes':{'sources':1},'fds':{'sources':0}},
                'rows':[{'system':'nes','family':'Disk System'}]}))
            records=[('Game',{'DatabaseID':'1','Name':'Cart','Platform':'Nintendo Entertainment System'}),
                     ('Game',{'DatabaseID':'2','Name':'Disk','Platform':'Nintendo Famicom Disk System'})]
            for platform in [3,106]:
                (root/f'screenscraper-{platform}-gameslist.csv').write_text('Game ID;Game Name\n7;Disk\n')
            with patch('prepare_collection_catalogue.launchbox_records',return_value=iter(records)), \
                 patch('prepare_collection_catalogue.download',return_value={}), \
                 patch('prepare_collection_catalogue.sha',return_value='fixture'):
                result=indexes(census,root/'Metadata.zip',root,root/'index.json')
            self.assertEqual(result['platforms']['fds']['2']['title'],'Disk')
            self.assertEqual(result['screenscraper']['fds']['7']['title'],'Disk')

    def test_filename_map_reaches_normal_collector_and_rejects_changed_source(self):
        self.check_filename_map_collector('snes','snes','root','Super Nintendo Entertainment System')

    def test_embedded_fds_filename_map_promotes_to_nes_owner_and_fds_packaging(self):
        self.check_filename_map_collector('nes','fds','Disk System','Nintendo Famicom Disk System')

    def test_gb_compatible_map_keeps_gbc_owner_and_actual_provider_namespace(self):
        self.check_filename_map_collector('gbc','gb','root','Nintendo Game Boy',compatible=True)

    def test_reviewed_gbc_catalogue_reference_keeps_actual_gb_owner(self):
        self.check_filename_map_collector('gb','gbc','root','Nintendo Game Boy Color',reviewed_namespace=True)

    def check_filename_map_collector(self,system,namespace,family,platform_name,compatible=False,reviewed_namespace=False):
        import zipfile
        from prepare_catalogue_bindings import promote_filename_mapping
        from prepare_collection_catalogue import mapping, load_mapping, sha
        import test_catalogue_bindings as fixture

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row, args, _, body = fixture.CatalogueBindingsTest().fixture(root)
            row['game']['platformId'] = system
            filename=('Disk System/' if family=='Disk System' else '')+'Known Canonical Name (USA).7z'
            if compatible:filename=filename.replace('(USA)','(USA) (GB Compatible)')
            source_path=system+'/'+filename
            records = [json.loads(line) for line in args.binding_census.read_text().splitlines()]
            for envelope in records:
                if envelope['kind'] == 'game':
                    envelope['record']['platformId'] = system
                if envelope['kind'] == 'artifact':
                    envelope['record']['displayPath'] = source_path
                    identity = envelope['record']['id']
            records.insert(-1, {'kind': 'cache', 'record': {'artifact_key': json.dumps([
                identity[k] for k in ['providerId', 'sourceId', 'accountId', 'providerFileId']])}})
            records[-1]['rows'] = len(records)-1
            args.binding_census.write_text(''.join(json.dumps(r)+'\n' for r in records))
            with zipfile.ZipFile(args.launchbox, 'w') as archive:
                archive.writestr('Metadata.xml', '''<LaunchBox><Game><DatabaseID>7</DatabaseID>
                    <Name>Known Canonical Name</Name><Platform>{platform_name}</Platform></Game>
                    <GameImage><DatabaseID>7</DatabaseID><Type>Box - Front</Type><Region>North America</Region>
                    <FileName>00000007-0000-0000-0000-000000000000.png</FileName></GameImage></LaunchBox>'''.format(platform_name=platform_name))
            source = {'system': system, 'sourcePath': source_path,
                'filename': filename, 'folder': system,
                'title': 'Known Canonical Name', 'family': family, 'modifiedContext': False,
                'sourceKind':'program'}
            inventory_path, index_path, map_path = (root/name for name in ['inventory.json', 'index.json', 'map.json'])
            inventory_path.write_text(json.dumps({'version': 1, 'registrySha256': sha(Path(__file__).parents[1]/'catalogue_platforms.json'),
                'supportedSystems': registry(), 'systems': {system: {'sources': 1}}, 'rows': [source]}))
            game = {'id': '7', 'title': 'Known Canonical Name', 'aliases': [],
                    'platformName': platform_name}
            indexed_games={namespace:{'7':game}};indexed_ss={namespace:{}}
            if compatible or reviewed_namespace:indexed_games[system]={};indexed_ss[system]={}
            index_path.write_text(json.dumps({'inventorySha256': sha(inventory_path),
                'launchbox': {'path': str(args.launchbox), 'sha256': sha(args.launchbox)},
                'screenscraperSources': {}, 'platforms': indexed_games, 'screenscraper': indexed_ss}))
            aliases=None
            if reviewed_namespace:
                aliases=root/'reviews.json'
                aliases.write_text(json.dumps({'version':1,'evidence':[{'path':str(args.launchbox),'sha256':sha(args.launchbox)}],
                    'rules':[{'system':system,'sourceTitle':source['title'],'sourcePaths':[source_path],
                        'reason':'Specific source programme is filed in the other GB catalogue namespace.',
                        'providers':{'launchbox':{'id':'7','title':game['title'],'catalogueNamespace':namespace}}}]}))
            mapping(inventory_path, index_path, map_path,aliases)
            args.catalogue_bindings = root/'promoted.json'
            promoted = promote_filename_mapping(map_path, args.binding_census, args.launchbox, args.catalogue_bindings)
            self.assertEqual(len(promoted['bindings']), 1)
            self.assertEqual(promoted['unpromotedSources'], [])
            self.assertEqual(promoted['bindings'][0]['cataloguePlatform'],system if compatible or reviewed_namespace else namespace)
            self.assertEqual(promoted['bindings'][0]['platform'],system)
            if reviewed_namespace:
                binding=promoted['bindings'][0]['providers']['launchbox']
                self.assertEqual((binding['catalogueNamespace'],binding['platformName']),('gbc','Nintendo Game Boy Color'))
                document=json.loads(map_path.read_text());document['rows'][0]['providers']['launchbox']['catalogueNamespace']='nes'
                map_path.write_text(json.dumps(document))
                with self.assertRaisesRegex(ValueError,'unsupported compatible namespace'):
                    load_mapping(map_path)
                return
            if compatible:
                binding=promoted['bindings'][0]['providers']['launchbox']
                self.assertEqual((binding['catalogueNamespace'],binding['platformName']),('gb','Nintendo Game Boy'))
                # A candidate cannot admit arbitrary other platforms through a
                # forged namespace, even when its ID exists in another index.
                document=json.loads(map_path.read_text())
                document['rows'][0]['providers']['launchbox']['catalogueNamespace']='nes'
                map_path.write_text(json.dumps(document))
                with self.assertRaisesRegex(ValueError,'unsupported compatible namespace'):
                    load_mapping(map_path)
                return
            args.system = system
            fixture.CatalogueBindingsTest().collect(row, args, body)
            with zipfile.ZipFile(args.output) as archive:
                actual = json.loads(archive.read('packaging.json'))['games'][0]
            self.assertEqual(actual['gameId'], 'game')
            self.assertEqual(actual['resources'][0]['importReference']['assetId'].split('/')[0], '7')
            document = json.loads(map_path.read_text())
            document['rows'][0]['sourcePath'] = 'SNES/Other Game.7z'
            map_path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError, 'source changed'):
                load_mapping(map_path)

    def test_inventory_reads_names_without_opening_roms_and_retains_duplicate_leaf_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            roms = root/'roms'
            for name in ['Hacks/Game (USA).zip', 'Retail/Game (USA).zip', 'saves/ignored.zip']:
                path = roms/'Test'/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'do not read this payload')
            settings = {'test': {'folders': ['Test'], 'extensions': ['.bin']}}
            with patch('prepare_collection_catalogue.registry', return_value=settings), \
                    patch.object(Path, 'open', side_effect=AssertionError('ROM contents opened')):
                # Output/hash IO is deliberately separate from the mounted tree.
                with patch('prepare_collection_catalogue.write') as write, patch('prepare_collection_catalogue.sha', return_value='registry'):
                    result = inventory(roms, root/'inventory.json')
            self.assertEqual(len(result['rows']), 2)
            self.assertEqual(len({r['sourcePath'] for r in result['rows']}), 2)
            self.assertEqual(result['romBodiesRead'], 0)
            self.assertTrue(next(r for r in result['rows'] if r['family'] == 'Hacks')['modifiedContext'])
            write.assert_called_once()


if __name__ == '__main__':
    unittest.main()
