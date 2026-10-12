import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.retro.rshop/save_capture');
  const directory = '/storage/emulated/0/Emulator saves/MelonDualDS';
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendRestore') {
        return (call.arguments['offset'] as int) +
            (call.arguments['bytes'] as Uint8List).length;
      }
      if (call.method == 'melonNames') return ['Game.sav', 'Other.srm'];
      if (call.method != 'captureMelon') return null;
      return {
        'captureId': 'a' * 32,
        'deviceId': 'device',
        'emulatorVersion': '0.8.0.rc2',
        'files': [
          {
            'name': call.arguments['name'],
            'path': '/private/save-captures/${'a' * 32}/member-0',
            'size': 4,
            'sha256': 'b' * 64,
          }
        ]
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test(
      'discovers current emulator save settings without a caller supplied path',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'mode': 'custom',
        'directory': directory,
        'extension': 'srm',
      };
    });
    final settings = await SaveCapture().melonSaveSettings();
    expect(settings.directory, directory);
    expect(settings.extension, 'srm');
    expect(settings.savesBesideRom, isFalse);
    expect(calls.single.method, 'melonSaveSettings');
    expect(calls.single.arguments, isNull);
  });

  test('ROM-relative settings do not pretend the fallback is the chosen folder',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => {
                  'mode': 'rom',
                  'directory': null,
                  'extension': 'sav',
                });
    final settings = await SaveCapture().melonSaveSettings();
    expect(settings.savesBesideRom, isTrue);
    expect(settings.directory, isNull);
  });

  test('settings discovery rejects an invalid or contradictory native location',
      () async {
    for (final row in [
      {'mode': 'custom', 'directory': '/data/user/0/other', 'extension': 'sav'},
      {'mode': 'custom', 'directory': null, 'extension': 'sav'},
      {'mode': 'rom', 'directory': directory, 'extension': 'sav'},
      {'mode': 'custom', 'directory': directory, 'extension': 'state'},
      {'mode': 'unknown', 'directory': directory, 'extension': 'sav'},
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => row);
      await expectLater(
          SaveCapture().melonSaveSettings(), throwsFormatException);
    }
  });

  test('Melon save mapping admits its standard protected save directory only',
      () {
    expect(SaveCapture.validMelonDirectory(directory), isTrue);
    expect(
        SaveCapture.validMelonDirectory('/storage/75D7-DC5F/Saves/DS'), isTrue);
    expect(
        SaveCapture.validMelonDirectory(
            '/storage/emulated/0/Android/data/me.magnum.melondualds/files/saves'),
        isTrue);
    for (final path in [
      '/storage/emulated/0',
      '$directory/..',
      '/storage/emulated/0/Android/data/me.magnum.melondualds/files',
      '/storage/emulated/0/Android/data/another.emulator/files/saves',
      '/data/user/0/me.magnum.melondualds',
      '$directory//child'
    ]) {
      expect(SaveCapture.validMelonDirectory(path), isFalse, reason: path);
    }
    for (final name in ['Game.sav', 'Game.srm']) {
      expect(SaveCapture.validMelonName(name), isTrue);
    }
    for (final name in [
      '../Game.sav',
      '.sav',
      'Game.sav.tmp',
      'Game.ml1',
      'Game.nds',
      'Game.rtc',
      'Game\\save.sav'
    ]) {
      expect(SaveCapture.validMelonName(name), isFalse, reason: name);
    }
  });

  test('one mapped DS save uses its own native capture and restore route',
      () async {
    final capture = SaveCapture();
    expect(await capture.melonNames(directory), ['Game.sav', 'Other.srm']);
    final group = await capture.captureMelon(
        captureId: 'a' * 32, directory: directory, name: 'Game.sav');
    expect(group.files.single.name, 'Game.sav');
    expect(group.emulatorVersion, '0.8.0.rc2');
    await capture.stageRestore(
        restoreId: 'c' * 32,
        name: 'Game.sav',
        size: 4,
        sha256: 'b' * 64,
        melonDirectory: directory,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3, 4])));
    final begin = calls.singleWhere((c) => c.method == 'beginRestore');
    expect(begin.arguments['melonDirectory'], directory);
    expect(begin.arguments.containsKey('ppssppDirectory'), isFalse);
    expect(calls.last.method, 'sealRestore');
    await capture.openMelonAppInfo();
    expect(calls.last.method, 'openMelonAppInfo');
  });

  test('mixed emulator restore bindings are rejected before native IO',
      () async {
    await expectLater(
        SaveCapture().stageRestore(
            restoreId: 'c' * 32,
            name: 'Game.sav',
            size: 4,
            sha256: 'b' * 64,
            melonDirectory: directory,
            ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
            bytes: const Stream.empty()),
        throwsFormatException);
    expect(calls, isEmpty);
  });

  test('only an explicit restore baseline accepts a sealed absent local save',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => {
                  'captureId': 'a' * 32,
                  'deviceId': 'device',
                  'emulatorVersion': '0.8.0.rc2',
                  'localWasAbsent': true,
                  'files': [],
                });
    final capture = SaveCapture();
    await expectLater(
        capture.captureMelon(
            captureId: 'a' * 32, directory: directory, name: 'Game.sav'),
        throwsFormatException);
    final baseline = await capture.captureMelon(
        captureId: 'a' * 32,
        directory: directory,
        name: 'Game.sav',
        restoreBaseline: true);
    expect(baseline.localWasAbsent, isTrue);
    expect(baseline.files, isEmpty);
  });
}
