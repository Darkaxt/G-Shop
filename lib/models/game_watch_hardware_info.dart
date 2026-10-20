/// Compact public reference facts, checked 2026-10-20 against the collection
/// and series pages at NintendoGameAndWatch.com. These explicit hardware keys
/// describe a visual edition; they never establish or change ROM identity.
/// Known conflicting model-number fields and unverified dates are omitted.
class GameWatchHardwareInfo {
  final String title, path;
  final String? released;
  const GameWatchHardwareInfo(this.title, this.path, this.released);
  String get sourceUrl => 'https://nintendogameandwatch.com/$path';
  String get family => path.split('/').first;
  String get series => _series[family]!.$1;
  String get summary => _series[family]!.$2;
  static GameWatchHardwareInfo? forHardware(String id) => entries[id];
  static const _series = <String, (String, String)>{
    'silver': (
      'Silver',
      'The original compact Game & Watch design combines an LCD game with a clock.'
    ),
    'gold': (
      'Gold',
      'A gold-coloured successor to the original Silver handheld design.'
    ),
    'wide-screen': (
      'Wide Screen',
      'A landscape LCD gives the game a wider playing area. Later editions keep this horizontal format.'
    ),
    'multi-screen': (
      'Multi Screen',
      'A folding body presents the game across two LCD panels.'
    ),
    'tabletop': (
      'Table Top',
      'A self-standing, arcade-style unit with a colour display.'
    ),
    'panorama': (
      'Panorama Screen',
      'An angled reflective optical system gives the LCD scene a sense of depth.'
    ),
    'super-color': (
      'Super Color',
      'A vertical handheld design uses coloured LCD sections.'
    ),
    'micro-vs-system': (
      'Micro VS System',
      'Two separate wired controllers allow head-to-head play on one unit.'
    ),
    'crystal-screen': (
      'Crystal Screen',
      'The transparent LCD window allows a view through the handheld.'
    ),
    'other': (
      'Special edition',
      'A commemorative Super Mario Bros. design outside the main named series.'
    ),
  };
  static const entries = <String, GameWatchHardwareInfo>{
    'gnw_ball': GameWatchHardwareInfo('Ball', 'silver/ball', '1980'),
    'gnw_fires': GameWatchHardwareInfo('Fire', 'silver/fire', '1980'),
    'gnw_flagman': GameWatchHardwareInfo('Flagman', 'silver/flagman', '1980'),
    'gnw_vermin': GameWatchHardwareInfo('Vermin', 'silver/vermin', '1980'),
    'gnw_judge': GameWatchHardwareInfo('Judge', 'silver/judge', '1980'),
    'gnw_judgeo': GameWatchHardwareInfo('Judge', 'silver/judge', '1980'),
    'gnw_helmeto': GameWatchHardwareInfo('Helmet', 'gold/helmet', '1981'),
    'gnw_lion': GameWatchHardwareInfo('Lion', 'gold/', '1981'),
    'gnw_manholeg': GameWatchHardwareInfo('Manhole', 'gold/manhole', '1981'),
    'gnw_pchute':
        GameWatchHardwareInfo('Parachute', 'wide-screen/parachute', '1981'),
    'gnw_octopus':
        GameWatchHardwareInfo('Octopus', 'wide-screen/octopus', '1981'),
    'gnw_popeye': GameWatchHardwareInfo('Popeye', 'wide-screen/popeye', '1981'),
    'gnw_chef': GameWatchHardwareInfo('Chef', 'wide-screen/chef', '1981'),
    'gnw_mmouse': GameWatchHardwareInfo(
        'Mickey Mouse', 'wide-screen/mickey-mouse', '1981'),
    'gnw_egg': GameWatchHardwareInfo('Egg', 'wide-screen/egg', '1981'),
    'gnw_fire': GameWatchHardwareInfo('Fire', 'wide-screen/fire', '1981'),
    'gnw_tbridge': GameWatchHardwareInfo(
        'Turtle Bridge', 'wide-screen/turtle-bridge', '1982'),
    'gnw_fireatk':
        GameWatchHardwareInfo('Fire Attack', 'wide-screen/fire-attack', '1982'),
    'gnw_stennis': GameWatchHardwareInfo(
        'Snoopy Tennis', 'wide-screen/snoopy-tennis', '1982'),
    'gnw_dkjr': GameWatchHardwareInfo(
        'Donkey Kong Jr.', 'wide-screen/donkey-kong-jr', '1982'),
    'gnw_mariocm': GameWatchHardwareInfo(
        'Mario\'s Cement Factory', 'wide-screen/marios-cement-factory', '1983'),
    'gnw_manhole':
        GameWatchHardwareInfo('Manhole', 'wide-screen/manhole', null),
    'gnw_tfish': GameWatchHardwareInfo(
        'Tropical Fish', 'wide-screen/tropical-fish', '1985'),
    'gnw_smbn': GameWatchHardwareInfo(
        'Super Mario Bros.', 'wide-screen/super-mario-bros', '1988'),
    'gnw_climbern':
        GameWatchHardwareInfo('Climber', 'wide-screen/climber', '1988'),
    'gnw_mariotj': GameWatchHardwareInfo(
        'Mario the Juggler', 'wide-screen/mario-the-juggler', '1991'),
    'gnw_opanic':
        GameWatchHardwareInfo('Oil Panic', 'multi-screen/oil-panic', '1982'),
    'gnw_dkong': GameWatchHardwareInfo(
        'Donkey Kong', 'multi-screen/donkey-kong', '1982'),
    'gnw_mickdon': GameWatchHardwareInfo(
        'Mickey & Donald', 'multi-screen/mickey-donald', '1982'),
    'gnw_ghouse': GameWatchHardwareInfo(
        'Green House', 'multi-screen/green-house', '1982'),
    'gnw_dkong2': GameWatchHardwareInfo(
        'Donkey Kong II', 'multi-screen/donkey-kong-ii', '1983'),
    'gnw_mario':
        GameWatchHardwareInfo('Mario Bros.', 'multi-screen/mario-bros', '1983'),
    'gnw_rshower': GameWatchHardwareInfo(
        'Rain Shower', 'multi-screen/rain-shower', '1983'),
    'gnw_lboat':
        GameWatchHardwareInfo('Lifeboat', 'multi-screen/lifeboat', '1983'),
    'gnw_pinball':
        GameWatchHardwareInfo('Pinball', 'multi-screen/pinball', '1983'),
    'gnw_bjack':
        GameWatchHardwareInfo('Black Jack', 'multi-screen/black-jack', '1985'),
    'gnw_squish':
        GameWatchHardwareInfo('Squish', 'multi-screen/squish', '1986'),
    'gnw_bsweep': GameWatchHardwareInfo(
        'Bomb Sweeper', 'multi-screen/bomb-sweeper', '1987'),
    'gnw_sbuster':
        GameWatchHardwareInfo('Safebuster', 'multi-screen/safebuster', '1988'),
    'gnw_gcliff':
        GameWatchHardwareInfo('Gold Cliff', 'multi-screen/gold-cliff', '1988'),
    'gnw_zelda': GameWatchHardwareInfo('Zelda', 'multi-screen/zelda', '1989'),
    'dkjr-tabletop': GameWatchHardwareInfo(
        'Donkey Kong Jr.', 'tabletop/donkey-kong-jr', '1983'),
    'gnw_mariocmt': GameWatchHardwareInfo(
        'Mario\'s Cement Factory', 'tabletop/marios-cement-factory', '1983'),
    'snoopy-tabletop':
        GameWatchHardwareInfo('Snoopy', 'tabletop/snoopy', '1983'),
    'popeye-tabletop':
        GameWatchHardwareInfo('Popeye', 'tabletop/popeye', '1983'),
    'gnw_snoopyp': GameWatchHardwareInfo('Snoopy', 'panorama/snoopy', '1983'),
    'gnw_popeyep': GameWatchHardwareInfo('Popeye', 'panorama/popeye', '1983'),
    'gnw_dkjrp': GameWatchHardwareInfo(
        'Donkey Kong Jr.', 'panorama/donkey-kong-jr', '1983'),
    'gnw_mbaway': GameWatchHardwareInfo(
        'Mario\'s Bombs Away', 'panorama/marios-bombs-away', '1983'),
    'gnw_mmousep':
        GameWatchHardwareInfo('Mickey Mouse', 'panorama/mickey-mouse', '1984'),
    'gnw_dkcirc': GameWatchHardwareInfo(
        'Donkey Kong Circus', 'panorama/', '1984'),
    'gnw_ssparky': GameWatchHardwareInfo(
        'Spitball Sparky', 'super-color/spitball-sparky', '1984'),
    'gnw_cgrab':
        GameWatchHardwareInfo('Crab Grab', 'super-color/crab-grab', '1984'),
    'gnw_boxing':
        GameWatchHardwareInfo('Boxing', 'micro-vs-system/boxing', '1984'),
    'gnw_dkong3': GameWatchHardwareInfo(
        'Donkey Kong 3', 'micro-vs-system/donkey-kong-3', '1984'),
    'gnw_dkhockey': GameWatchHardwareInfo(
        'Donkey Kong Hockey', 'micro-vs-system/donkey-kong-hockey', '1984'),
    'gnw_smb': GameWatchHardwareInfo(
        'Super Mario Bros.', 'crystal-screen/super-mario-bros', '1986'),
    'gnw_climber':
        GameWatchHardwareInfo('Climber', 'crystal-screen/climber', '1986'),
    'gnw_bfight': GameWatchHardwareInfo(
        'Balloon Fight', 'crystal-screen/balloon-fight', '1986'),
    'super-mario-bros-special': GameWatchHardwareInfo(
        'Super Mario Bros.', 'other/super-mario-bros-special', null),
  };
}
