import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../utils/game_metadata.dart';
import 'socket_media_model.dart';

/// Reusable photographed shell families. Candidate references do not assert a
/// cartridge's manufacturing revision or colour from its ROM program alone.
class NesCartridgeModel {
  static const labels = {
    'nintendo-3-gray': 'Nintendo · grey · 3 screws',
    'nintendo-5-gray': 'Nintendo · grey · 5 screws',
    'nintendo-3-gold': 'Nintendo · gold · 3 screws',
    'nintendo-5-gold': 'Nintendo · gold · 5 screws',
    'tengen': 'Tengen · black',
    'camerica-gold': 'Camerica · gold',
    'camerica-silver': 'Camerica · silver',
    'dreams-blue': 'Color Dreams family · blue',
    'dreams-black': 'Color Dreams family · black',
    'ave-square': 'AVE · square',
    'ave-angle': 'AVE · clipped corner',
    'active-clear': 'Active Enterprises · clear',
    'aladdin': 'Aladdin · adapter and compact cartridge',
  };

  static List<String> referencesFor(String filename) {
    if (filename.contains(RegExp(r'[/\\\[]')) ||
        RegExp(r'\((?:Aftermarket|Pirate|Proto[^)]*|Beta[^)]*|Virtual Console|Demo[^)]*)\)',
                caseSensitive: false)
            .hasMatch(filename)) return const [];
    final region = GameMetadata.extractRegion(filename).name;
    if (!region
        .split(' / ')
        .any({'USA', 'Europe', 'Australia', 'Canada'}.contains)) {
      return const []; // Famicom/bootleg shapes are not the 72-pin NES shell.
    }
    final title = GameMetadata.cleanTitle(filename)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .replaceFirst(RegExp(r'^the'), '')
        .replaceFirst(RegExp(r'the$'), '');
    final unl = filename.contains('(Unl)');
    if (!unl) {
      if (title.startsWith('zeldaii') ||
          title.startsWith('zelda2') ||
          title.startsWith('adventureoflink')) {
        return const ['nintendo-3-gold', 'nintendo-3-gray'];
      }
      if (title == 'legendofzelda') {
        return const ['nintendo-3-gold', 'nintendo-5-gold', 'nintendo-3-gray'];
      }
      const fiveOnly = {
        'chubbycherub',
        'clucluland',
        'donkeykongjrmath',
        'gumshoe',
        'muscle',
        'soccer',
        'sqoon',
        'stackup',
        'devilworld',
        'mahjong'
      };
      if (fiveOnly.contains(title)) return const ['nintendo-5-gray'];
      // Photographed 1985-87 factory list; later releases never gain invented
      // five-screw editions merely because the mesh is available.
      const fiveScrew = {
        '10yardfight',
        '1942',
        '3dworldrunner',
        'alphamission',
        'arkanoid',
        'athena',
        'athleticworld',
        'balloonfight',
        'baseball',
        'breakthru',
        'burgertime',
        'castlevania',
        'commando',
        'deadlytowers',
        'donkeykong',
        'donkeykong3',
        'donkeykongjr',
        'doubledribble',
        'duckhunt',
        'elevatoraction',
        'excitebike',
        'ghostsngoblins',
        'golf',
        'gooniesii',
        'gotchathesport',
        'gradius',
        'gyromite',
        'hogansalley',
        'iceclimber',
        'ikariwarriors',
        'jaws',
        'karatechamp',
        'kidicarus',
        'kidnikiradicalninja',
        'kungfu',
        'legendofkage',
        'loderunner',
        'lunarpool',
        'machrider',
        'mariobros',
        'megaman',
        'metroid',
        'mightybombjack',
        'miketysonspunchout',
        'ninjakid',
        'pinball',
        'popeye',
        'prowrestling',
        'radracer',
        'raidonbungelingbay',
        'ringking',
        'rushnattack',
        'rygar',
        'sectionz',
        'skykid',
        'slalom',
        'solomonskey',
        'spelunker',
        'spyhunter',
        'starforce',
        'starvoyager',
        'stinger',
        'supermariobros',
        'superpitfall',
        'tagteamwrestling',
        'tennis',
        'tigerheli',
        'topgun',
        'trackfield',
        'trojan',
        'urbanchampion',
        'volleyball',
        'wildgunman',
        'wintergames',
        'wizardswarriors',
        'wreckingcrew',
        'zanac'
      };
      return fiveScrew.contains(title)
          ? const ['nintendo-3-gray', 'nintendo-5-gray']
          : const ['nintendo-3-gray'];
    }
    if (filename.contains('(Aladdin Deck Enhancer)') ||
        title == 'dizzytheadventurer') return const ['aladdin'];
    if (title == 'action52' || title == 'cheetahmenii')
      return const ['active-clear'];
    if (const {
      'afterburner',
      'aliensyndrome',
      'fantasyzone',
      'gauntlet',
      'indianajonesandthetempleofdoom',
      'klax',
      'mspacman',
      'pacman',
      'pacmania',
      'rbibaseball',
      'rbibaseball2',
      'rbibaseball3',
      'roadrunner',
      'rollingthunder',
      'shinobi',
      'skullcrossbones',
      'supersprint',
      'tetris',
      'toobin',
      'vindicators'
    }.contains(title)) return const ['tengen'];
    if (const {
      'bee52',
      'bignosefreaksout',
      'bignosethecaveman',
      'fantasticadventuresofdizzythe',
      'thefantasticadventuresofdizzy',
      'fantasticadventuresofdizzy',
      'linusspaceheadscosmiccrusade',
      'micromachines',
      'quattroadventure',
      'quattroarcade',
      'quattrosports',
      'firehawk',
      'mig29sovietfighter',
      'stuntkids',
      'ultimatestuntmanthe',
      'theultimatestuntman',
      'ultimatestuntman'
    }.contains(title)) {
      // Photographed commercial releases use one finish per title; this does
      // not establish an owned copy's printing or a different program revision.
      return const {'bee52', 'firehawk', 'mig29sovietfighter', 'stuntkids'}
              .contains(title)
          ? const ['camerica-silver']
          : const ['camerica-gold'];
    }
    if (const {
      'blackjack',
      'deathbots',
      'doublestrike',
      'dudeswithattitude',
      'f15citywar',
      'impossiblemissionii',
      'krazykreatures',
      'mermaidsofatlantistheriddleofthemagicbubble',
      'puzzle',
      'pyramid',
      'solitaire',
      'tilesoffate',
      'trollsontreasureisland',
      'ultimateleaguesoccer',
      'wallybearandthenogang',
      'maxi15',
      'radracketdeluxetennisii',
      'venicebeachvolleyball'
    }.contains(title)) {
      if (title == 'maxi15') return const ['ave-square'];
      if (const {'radracketdeluxetennisii', 'venicebeachvolleyball'}
          .contains(title)) {
        return const ['ave-angle'];
      }
      return const ['ave-square', 'ave-angle'];
    }
    if (const {
      'bibleadventures',
      'biblebuffet',
      'spiritualwarfare',
      'sundayfundaytheride',
      'exodusjourneytothepromisedland',
      'joshuathebattleofjericho',
      'menacebeach',
      'crystalmines',
      'babyboomer',
      'captaincomic',
      'adventuresofcaptaincomic',
      'operationsecretstorm',
      'raid2020',
      'roborobots',
      'roborobodemond',
      'robodemons',
      'silentassault',
      'tagindragon',
      'kingneptunesadventure',
      'challengeofthedragon',
      'chiller',
      'freefall',
      'moonranger'
    }.contains(title)) {
      return const ['dreams-blue', 'dreams-black'];
    }
    return const [];
  }

  static Future<SocketMediaModel?> load(String style,
      {Directory? modelsDirectory}) async {
    if (!labels.containsKey(style))
      throw const FormatException('Unknown NES shell');
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/cartridges/nes/$style');
    final manifest = File('${dir.path}/model.json');
    if (!await manifest.exists()) return null;
    final mesh = File('${dir.path}/model.mesh');
    if (await manifest.length() > 1024 * 1024 ||
        await mesh.length() > 20 * 1024 * 1024) {
      throw const FormatException('NES shell exceeds import size');
    }
    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    if (data['system'] != 'nes' ||
        data['cartridgeStyle'] != style ||
        data['motionKind'] != 'pushClick' ||
        data['textureFiles'] is! Map ||
        (data['textureFiles'] as Map).isNotEmpty) {
      throw const FormatException('NES shell identity differs from selection');
    }
    final bytes = ByteData.sublistView(await mesh.readAsBytes());
    return SocketMediaModel.privateCartridge(data, bytes);
  }
}
