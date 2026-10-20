import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/console_model.dart';

void main() {
  test(
      'coverage aliases preserve MAME revision and physical edition identities',
      () {
    const aliases = {
      "Ball (World).7z": "gnw_ball",
      "Balloon Fight (World).7z": "gnw_bfight",
      "Climber (World).7z": "gnw_climber",
      "Crab Grab (World).7z": "gnw_cgrab",
      "Donkey Kong 3 (World).7z": "gnw_dkong3",
      "Donkey Kong Hockey (World).7z": "gnw_dkhockey",
      "Donkey Kong Jr. (World) (Panorama Screen).7z": "gnw_dkjrp",
      "Fire (World) (Silver).7z": "gnw_fires",
      "Fire Attack (World).7z": "gnw_fireatk",
      "Flagman (World).7z": "gnw_flagman",
      "Helmet (World).7z": "gnw_helmeto",
      "Helmet (World) (Rev 1).7z": "gnw_helmet",
      "Judge (World).7z": "gnw_judgeo",
      "Judge (World) (Rev 1).7z": "gnw_judge",
      "Lion (World).7z": "gnw_lion",
      "Manhole (World) (Gold).7z": "gnw_manholeg",
      "Manhole (World) (New Wide Screen).7z": "gnw_manhole",
      "Mario the Juggler (World).7z": "gnw_mariotj",
      "Mario's Bombs Away (World).7z": "gnw_mbaway",
      "Mario's Cement Factory (World) (Table Top).7z": "gnw_mariocmt",
      "Mickey Mouse ~ Donkey Kong Circus (World) (Panorama Screen).7z":
          "gnw_mmousep",
      "Popeye (World) (Panorama Screen).7z": "gnw_popeyep",
      "Popeye (World) (Wide Screen).7z": "gnw_popeye",
      "Snoopy Tennis (World).7z": "gnw_stennis",
      "Tropical Fish (World).7z": "gnw_tfish",
      "Turtle Bridge (World).7z": "gnw_tbridge",
      "Vermin (World).7z": "gnw_vermin",
    };
    for (final entry in aliases.entries) {
      expect(ConsoleModel.gameWatchSet(entry.key), entry.value,
          reason: entry.key);
      expect(ConsoleModel.gameWatchSet('${entry.value}.zip'), entry.value);
    }
    expect(ConsoleModel.gameWatchSet('Ball (USA).7z'), isNull);
    expect(ConsoleModel.gameWatchSet('gnw_ball.zip.exe'), isNull);
    expect(ConsoleModel.gameWatchSet('gnw_helmet.zip'), 'gnw_helmet');
    expect(
        ConsoleModel.gameWatchSet('Super Mario Bros. (World).7z'), 'gnw_smbn');
  });
}
