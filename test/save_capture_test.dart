import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';
import 'package:retro_eshop/models/retroarch_battery_route.dart';
import 'package:retro_eshop/models/pcsx_save_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GB and GBC expose separate SameBoy battery routes with clock groups',
      () {
    for (final platform in ['gb', 'gbc']) {
      final route = RetroArchBatteryRoute.forPlatform(platform);
      expect(route, isNotNull);
      expect(route!.coreId, 'sameboy');
      expect(route.directory, '/storage/emulated/0/RetroArch/saves/SameBoy');
      expect(route.journalId, '$platform-battery');
      expect(route.includesRtc, isTrue);
    }
  });
  const channel = MethodChannel('com.retro.rshop/save_capture');
  final calls = <MethodCall>[];
  late Map<String, Object> response;
  setUp(() {
    calls.clear();
    response = {
      'captureId': 'a' * 32,
      'deviceId': 'device',
      'emulatorVersion': '1.22.2_GIT',
      'files': [
        {
          'name': 'Game.srm',
          'path': '/private/save-captures/${'a' * 32}/member-0',
          'size': 4,
          'sha256': 'b' * 64
        }
      ]
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('PS1 capture keeps the owned ROM and private/shared card roles exact',
      () async {
    final layout = PcsxSaveLayout.decode({
      'directory': '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
      'cards': [
        {'slot': 1, 'mode': 'libretro', 'name': 'owned%2FGame.srm'},
        {'slot': 2, 'mode': 'shared', 'name': 'pcsx-card2.mcd'},
      ]
    });
    for (final card in layout.cards) {
      calls.clear();
      (response['files'] as List).single['name'] = card.name;
      (response['files'] as List).single['size'] = 131072;
      final group = await SaveCapture().capturePcsx(
          captureId: 'a' * 32,
          grant: {'installationId': 'owned', 'filename': 'Game.chd'},
          layout: layout,
          card: card);
      expect(group.files.single.name, card.name);
      expect(calls.single.method, 'capturePcsx');
      expect(calls.single.arguments, {
        'captureId': 'a' * 32,
        'installationId': 'owned',
        'filename': 'Game.chd',
        'directory': layout.directory,
        'slot': card.slot,
        'mode': card.mode,
        'name': card.name,
      });
      (response['files'] as List).single['size'] = 131071;
      await expectLater(
          SaveCapture().capturePcsx(
              captureId: 'a' * 32,
              grant: {'installationId': 'owned', 'filename': 'Game.chd'},
              layout: layout,
              card: card),
          throwsFormatException);
    }
    calls.clear();
    await expectLater(
        SaveCapture().capturePcsx(
            captureId: 'a' * 32,
            grant: {
              'installationId': 'owned',
              'filename': 'Game.chd',
              'directory': '/other'
            },
            layout: layout,
            card: layout.cards.first),
        throwsFormatException);
    expect(calls, isEmpty);
    final serial = PcsxSaveLayout.decode({
      'directory': layout.directory,
      'cards': [
        {'slot': 1, 'mode': 'serial', 'name': null}
      ]
    });
    await expectLater(
        SaveCapture().capturePcsx(
            captureId: 'a' * 32,
            grant: {'installationId': 'owned', 'filename': 'Game.chd'},
            layout: serial,
            card: serial.cards.first),
        throwsFormatException);
    expect(calls, isEmpty);
  });

  test('SNES battery route retains its Snes9x SRAM and optional clock contract',
      () {
    final route = RetroArchBatteryRoute.forPlatform('snes');
    expect(route, isNotNull);
    expect(route!.coreId, 'snes9x');
    expect(route.directory, '/storage/emulated/0/RetroArch/saves/Snes9x');
    expect(route.formatId, 'libretro-snes9x-sram-v1');
    expect(route.includesRtc, isTrue);
    expect(route.acceptsSize(131072), isTrue);
    expect(route.acceptsSize(131073), isFalse);
  });

  test('capture requests only an explicitly selected mGBA battery group',
      () async {
    final captured = await SaveCapture()
        .captureRetroArch(captureId: 'a' * 32, name: 'Game.srm');
    expect(calls.single.method, 'captureRetroArch');
    expect(calls.single.arguments, {'captureId': 'a' * 32, 'name': 'Game.srm'});
    expect(captured.files.single.name, 'Game.srm');
    expect(captured.deviceId, 'device');
  });

  for (final platform in ['snes', 'gb', 'gbc']) {
    test(
        '$platform captures and stages SRAM plus RTC with its own native route',
        () async {
      final route = RetroArchBatteryRoute.forPlatform(platform)!;
      (response['files'] as List).add({
        'name': 'Game.rtc',
        'path': '/private/save-captures/${'a' * 32}/member-1',
        'size': 20,
        'sha256': 'c' * 64,
      });
      final group = await SaveCapture().captureRetroArch(
          captureId: 'a' * 32, name: 'Game.srm', route: route);
      expect(group.files.map((f) => f.name), ['Game.srm', 'Game.rtc']);
      expect((calls.single.arguments as Map)['retroArchRoute'], platform);
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'appendRestoreGroup') {
          final args = call.arguments as Map;
          return (args['offset'] as int) + (args['bytes'] as Uint8List).length;
        }
        return null;
      });
      await SaveCapture().stageRetroArchGroupRestore(
          restoreId: 'a' * 32,
          name: 'Game.srm',
          route: route,
          members: [
            RestoreSaveMember(
                'Game.srm', 4, 'b' * 64, Stream.value(Uint8List(4))),
            RestoreSaveMember(
                'Game.rtc', 20, 'c' * 64, Stream.value(Uint8List(20))),
          ]);
      expect((calls.first.arguments as Map)['retroArchRoute'], platform);
      expect(calls.last.method, 'sealRestoreGroup');
      calls.clear();
      await expectLater(
          SaveCapture().stageRetroArchGroupRestore(
              restoreId: 'a' * 32,
              name: 'Game.srm',
              route: RetroArchBatteryRoute.nes,
              members: [
                RestoreSaveMember(
                    'Game.srm', 4, 'b' * 64, const Stream.empty()),
                RestoreSaveMember(
                    'Game.rtc', 20, 'c' * 64, const Stream.empty()),
              ]),
          throwsFormatException);
      expect(calls, isEmpty);
    });
  }

  test('PPSSPP captures one explicitly mapped completed state slot', () async {
    const directory = '/storage/emulated/0/Games/PSP/PPSSPP_STATE';
    const name = 'ULUS10001_1.00_0.ppst';
    response['emulatorVersion'] = 'v1.20.4';
    (response['files'] as List).single['name'] = name;
    // States can exceed the battery-save bound; transport stays streamed.
    (response['files'] as List).single['size'] = 32 * 1024 * 1024;
    final captured = await SaveCapture()
        .capturePpsspp(captureId: 'a' * 32, directory: directory, name: name);
    expect(calls.single.method, 'capturePpsspp');
    expect(calls.single.arguments,
        {'captureId': 'a' * 32, 'directory': directory, 'name': name});
    expect(captured.files.single.name, name);
    expect(captured.emulatorVersion, 'v1.20.4');
  });

  test('PPSSPP settings discovery exposes only a validated state directory',
      () async {
    const directory = '/storage/emulated/0/PSP/PPSSPP_STATE';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'directory': directory};
    });
    expect(await SaveCapture().ppssppSaveDirectory(), directory);
    expect(calls.single.method, 'ppssppSaveSettings');
    expect(calls.single.arguments, isNull);
    for (final raw in [
      null,
      <String, dynamic>{},
      {'directory': 123},
      {'directory': '/data/user/0/other'},
      {'directory': '/storage/emulated/0/PSP/SAVEDATA'},
      {'directory': directory, 'privateConfig': 'not permitted'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => raw);
      await expectLater(
          SaveCapture().ppssppSaveDirectory(), throwsFormatException);
    }
  });

  test('PPSSPP protected state paths stay within its external files root', () {
    for (final path in [
      '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files/PSP/PPSSPP_STATE',
      '/storage/75D7-DC5F/Android/data/org.ppsspp.ppsspp/files/Custom/PSP/PPSSPP_STATE',
    ]) {
      expect(SaveCapture.validPpssppDirectory(path), isTrue, reason: path);
    }
    for (final path in [
      '/storage/emulated/0/Android/data/other/files/PSP/PPSSPP_STATE',
      '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files/../PSP/PPSSPP_STATE',
      '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/cache/PSP/PPSSPP_STATE',
      '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files/PSP/SAVEDATA',
    ]) {
      expect(SaveCapture.validPpssppDirectory(path), isFalse, reason: path);
    }
  });

  test('Game Gear capture binds its route and rejects unrelated RTC members',
      () async {
    final group = await SaveCapture().captureRetroArch(
        captureId: 'a' * 32,
        name: 'Game.srm',
        route: RetroArchBatteryRoute.gameGear);
    expect(group.files.single.name, 'Game.srm');
    expect(calls.single.arguments, {
      'captureId': 'a' * 32,
      'name': 'Game.srm',
      'retroArchRoute': 'gamegear'
    });
    (response['files'] as List).add({
      'name': 'Game.rtc',
      'path': '/private/member-1',
      'size': 4,
      'sha256': 'c' * 64
    });
    await expectLater(
        SaveCapture().captureRetroArch(
            captureId: 'a' * 32,
            name: 'Game.srm',
            route: RetroArchBatteryRoute.gameGear),
        throwsFormatException);
  });

  test(
      'N64 captures the complete Mupen save-memory group and rejects fragments',
      () async {
    final route = RetroArchBatteryRoute.forPlatform('n64');
    expect(route, isNotNull);
    expect(route!.coreId, 'mupen64plus_next_gles3');
    expect(route.formatId, 'libretro-mupen64plus-next-srm-v1');
    expect(route.includesRtc, isFalse);
    (response['files'] as List).single['size'] = 296960;
    final group = await SaveCapture()
        .captureRetroArch(captureId: 'a' * 32, name: 'Game.srm', route: route);
    expect(group.files.single.size, 296960);
    expect((calls.single.arguments as Map)['retroArchRoute'], 'n64');
    for (final size in [1, 65536, 296959, 296961]) {
      (response['files'] as List).single['size'] = size;
      await expectLater(
          SaveCapture().captureRetroArch(
              captureId: 'a' * 32, name: 'Game.srm', route: route),
          throwsFormatException);
    }
    calls.clear();
    for (final size in [1, 296959, 296961]) {
      await expectLater(
          SaveCapture().stageRestore(
              restoreId: 'a' * 32,
              name: 'Game.srm',
              size: size,
              sha256: 'b' * 64,
              retroArchRoute: route,
              bytes: const Stream.empty()),
          throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  for (final platform in ['mastersystem', 'megadrive', 'nes']) {
    test('$platform capture and restore retain the console route', () async {
      final route = RetroArchBatteryRoute.values
          .singleWhere((route) => route.platformId == platform);
      expect(route.coreId, platform == 'nes' ? 'fceumm' : 'genesis_plus_gx');
      expect(route.includesRtc, isFalse);
      await SaveCapture().captureRetroArch(
          captureId: 'a' * 32, name: 'Game.srm', route: route);
      expect((calls.single.arguments as Map)['retroArchRoute'], platform);
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'appendRestore' ? 4 : null;
      });
      await SaveCapture().stageRestore(
          restoreId: 'a' * 32,
          name: 'Game.srm',
          size: 4,
          sha256: 'b' * 64,
          retroArchRoute: route,
          bytes: Stream.value(Uint8List.fromList([1, 2, 3, 4])));
      expect((calls.first.arguments as Map)['retroArchRoute'], platform);
      calls.clear();
      await expectLater(
          SaveCapture().stageRestore(
              restoreId: 'a' * 32,
              name: 'Game.srm',
              size: route.maxBytes + 1,
              sha256: 'b' * 64,
              retroArchRoute: route,
              bytes: const Stream.empty()),
          throwsFormatException);
      expect(calls, isEmpty);
    });
  }

  test('Game Gear restore passes only its reviewed route and SRAM size',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'appendRestore' ? 4 : null;
    });
    await SaveCapture().stageRestore(
        restoreId: 'a' * 32,
        name: 'Game.srm',
        size: 4,
        sha256: 'b' * 64,
        retroArchRoute: RetroArchBatteryRoute.gameGear,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3, 4])));
    expect((calls.first.arguments as Map)['retroArchRoute'], 'gamegear');
    calls.clear();
    await expectLater(
        SaveCapture().stageRestore(
            restoreId: 'a' * 32,
            name: 'Game.srm',
            size: 65537,
            sha256: 'b' * 64,
            retroArchRoute: RetroArchBatteryRoute.gameGear,
            bytes: const Stream.empty()),
        throwsFormatException);
    expect(calls, isEmpty);
  });

  test('PPSSPP lists only the explicitly selected state directory', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return ['ULUS10041_1.00_0.ppst'];
    });
    const directory = '/storage/emulated/0/PSP/PPSSPP_STATE';
    expect(
        await SaveCapture().ppssppNames(directory), ['ULUS10041_1.00_0.ppst']);
    expect(calls.single.method, 'ppssppNames');
    expect(calls.single.arguments, {'directory': directory});
    await expectLater(SaveCapture().ppssppNames('/storage/emulated/0'),
        throwsFormatException);
    expect(calls, hasLength(1));
  });

  test('PPSSPP rejects temporary slots and unmapped roots before native IO',
      () async {
    for (final name in ['Game.ppst', 'ULUS10001_1.00_0.ppst.tmp', 'Game.iso']) {
      await expectLater(
          SaveCapture().capturePpsspp(
              captureId: 'a' * 32,
              directory: '/storage/emulated/0/PSP/PPSSPP_STATE',
              name: name),
          throwsFormatException);
    }
    for (final directory in [
      '/storage/emulated/0',
      '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/PPSSPP_STATE',
      '/storage/emulated/0/PSP/../PPSSPP_STATE'
    ]) {
      await expectLater(
          SaveCapture().capturePpsspp(
              captureId: 'a' * 32,
              directory: directory,
              name: 'ULUS10001_1.00_0.ppst'),
          throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  test('PPSSPP cannot substitute a second slot or battery-save member',
      () async {
    response['emulatorVersion'] = 'v1.20.4';
    (response['files'] as List).single['name'] = 'ULUS10001_1.00_0.ppst';
    (response['files'] as List).add({
      'name': 'Game.srm',
      'path': '/private/other',
      'size': 4,
      'sha256': 'b' * 64
    });
    await expectLater(
        SaveCapture().capturePpsspp(
            captureId: 'a' * 32,
            directory: '/storage/emulated/0/PSP/PPSSPP_STATE',
            name: 'ULUS10001_1.00_0.ppst'),
        throwsFormatException);
  });

  test(
      'rejects escaping names and unsupported state/ROM files before native IO',
      () async {
    for (final name in [
      '../Game.srm',
      'Game.state',
      'Game.gba',
      'Game.srm/other'
    ]) {
      await expectLater(
          SaveCapture().captureRetroArch(captureId: 'a' * 32, name: name),
          throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  test('native response cannot substitute another capture or save group',
      () async {
    response['captureId'] = 'c' * 32;
    await expectLater(
        SaveCapture().captureRetroArch(captureId: 'a' * 32, name: 'Game.srm'),
        throwsFormatException);
    response['captureId'] = 'a' * 32;
    (response['files'] as List).add({
      'name': 'Other.srm',
      'path': '/private/other',
      'size': 4,
      'sha256': 'b' * 64
    });
    await expectLater(
        SaveCapture().captureRetroArch(captureId: 'a' * 32, name: 'Game.srm'),
        throwsFormatException);
  });

  test('restore seals only after normal verified stream completion', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendRestore') {
        final args = call.arguments as Map;
        return (args['offset'] as int) + (args['bytes'] as Uint8List).length;
      }
      return null;
    });
    await SaveCapture().stageRestore(
        restoreId: 'a' * 32,
        name: 'Game.srm',
        size: 4,
        sha256: 'b' * 64,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3, 4])));
    expect(calls.map((c) => c.method),
        ['beginRestore', 'appendRestore', 'sealRestore']);
    expect((calls[1].arguments as Map)['offset'], 0);
  });

  test(
      'related restore seals the whole group only after both verified streams end',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendRestoreGroup') {
        final args = call.arguments as Map;
        return (args['offset'] as int) + (args['bytes'] as Uint8List).length;
      }
      return null;
    });
    await SaveCapture().stageRetroArchGroupRestore(
        restoreId: 'a' * 32,
        name: 'Game.srm',
        members: [
          RestoreSaveMember('Game.srm', 4, 'b' * 64,
              Stream.value(Uint8List.fromList([1, 2, 3, 4]))),
          RestoreSaveMember('Game.rtc', 4, 'c' * 64,
              Stream.value(Uint8List.fromList([5, 6, 7, 8]))),
        ]);
    expect(calls.map((c) => c.method), [
      'beginRestoreGroup',
      'appendRestoreGroup',
      'appendRestoreGroup',
      'sealRestoreGroup'
    ]);
    expect(calls.skip(1).take(2).map((c) => (c.arguments as Map)['member']),
        [0, 1]);
    calls.clear();
    Stream<Uint8List> failed() async* {
      yield Uint8List.fromList([1, 2, 3, 4]);
      throw StateError('changed cloud');
    }

    await expectLater(
        SaveCapture().stageRetroArchGroupRestore(
            restoreId: 'a' * 32,
            name: 'Game.srm',
            members: [
              RestoreSaveMember('Game.rtc', 4, 'c' * 64,
                  Stream.value(Uint8List.fromList([5, 6, 7, 8]))),
              RestoreSaveMember('Game.srm', 4, 'b' * 64, failed()),
            ]),
        throwsStateError);
    expect(calls.any((c) => c.method == 'sealRestoreGroup'), isFalse);
  });

  test(
      'group staging rejects unrelated, duplicate and escaping members before IO',
      () async {
    for (final names in [
      ['Game.srm', 'Other.rtc'],
      ['Game.srm', 'Game.srm'],
      ['Game.srm', '../Game.rtc'],
      ['Game.srm', 'Game.state']
    ]) {
      await expectLater(
          SaveCapture().stageRetroArchGroupRestore(
              restoreId: 'a' * 32,
              name: 'Game.srm',
              members: [
                for (final name in names)
                  RestoreSaveMember(name, 4, 'b' * 64, const Stream.empty()),
              ]),
          throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  test('a full-length download followed by verification failure cannot seal',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'appendRestore' ? 4 : null;
    });
    Stream<Uint8List> rejectedReadback() async* {
      yield Uint8List.fromList([1, 2, 3, 4]);
      throw StateError('cloud verification rejected');
    }

    await expectLater(
        SaveCapture().stageRestore(
            restoreId: 'a' * 32,
            name: 'Game.srm',
            size: 4,
            sha256: 'b' * 64,
            bytes: rejectedReadback()),
        throwsStateError);
    expect(calls.map((c) => c.method), ['beginRestore', 'appendRestore']);
  });

  test('PPSSPP restore seals with the explicit mapped directory and slot',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendRestore') {
        final args = call.arguments as Map;
        return (args['offset'] as int) + (args['bytes'] as Uint8List).length;
      }
      return null;
    });
    const directory = '/storage/emulated/0/PSP/PPSSPP_STATE';
    const name = 'ULUS10001_1.00_0.ppst';
    await SaveCapture().stageRestore(
        restoreId: 'a' * 32,
        name: name,
        ppssppDirectory: directory,
        size: 4,
        sha256: 'b' * 64,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3, 4])));
    expect((calls.first.arguments as Map)['ppssppDirectory'], directory);
    expect((calls.first.arguments as Map)['name'], name);
    expect(calls.last.method, 'sealRestore');
    calls.clear();
    for (final (slot, root) in [
      (name, '/storage/emulated/0/RetroArch/saves/mGBA'),
      ('Game.srm', directory),
      (name, null),
    ]) {
      await expectLater(
          SaveCapture().stageRestore(
              restoreId: 'a' * 32,
              name: slot,
              ppssppDirectory: root,
              size: 4,
              sha256: 'b' * 64,
              bytes: const Stream.empty()),
          throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  test('restore rejects escaping destinations before native staging', () async {
    await expectLater(
        SaveCapture().stageRestore(
            restoreId: 'a' * 32,
            name: '../Game.srm',
            size: 4,
            sha256: 'b' * 64,
            bytes: const Stream.empty()),
        throwsFormatException);
    expect(calls, isEmpty);
  });
}
