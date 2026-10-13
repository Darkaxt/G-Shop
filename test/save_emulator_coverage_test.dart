import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/save_emulator_coverage.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';

Map<String, Object> _row(String name, String version,
        [List<String> authorities = const []]) =>
    {
      'packageName': name,
      'versionName': version,
      'documentAuthorities': authorities,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PC runtimes are excluded from ROM-emulator save coverage', () {
    for (final package in [
      'app.gamenative',
      'com.winnative.cmod',
      'org.force9.starboard',
    ]) {
      expect(SaveEmulatorCoverage.knownPackages, isNot(contains(package)));
    }
    for (final package in [
      'com.retroarch.aarch64',
      'org.ppsspp.ppsspp',
      'org.dolphinemu.dolphinemu',
      'xyz.aethersx2.android',
      'me.magnum.melondualds',
      'dev.eden.eden_emulator',
    ]) {
      expect(SaveEmulatorCoverage.knownPackages, contains(package));
    }
  });

  test(
      'coverage requests bounded package metadata without paths or credentials',
      () async {
    const channel = MethodChannel('com.retro.rshop/save_capture');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return [_row('org.ppsspp.ppsspp', 'v1.20.4')];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect((await SaveCapture().installedEmulators()).single.label, 'PPSSPP');
    expect(calls.single.method, 'installedSaveEmulators');
    expect(calls.single.arguments, {
      'packages': SaveEmulatorCoverage.knownPackages.keys.toList(),
    });
  });

  test('installed version cannot inherit verification from an older runtime',
      () {
    final rows = SaveEmulatorCoverage.decode([
      _row('com.retroarch.aarch64', '1.22.2_GIT'),
      _row('org.ppsspp.ppsspp', '1.20.4'),
    ]);
    expect(rows.singleWhere((r) => r.label == 'RetroArch').saves,
        'In-game saves · GB, GBC, NES, SNES and GBA (including paired clock data), Game Gear, Master System, Mega Drive and Nintendo 64 (including Controller Paks).');
    expect(rows.singleWhere((r) => r.label == 'RetroArch').storage,
        contains('FCEUmm'));
    expect(rows.singleWhere((r) => r.label == 'RetroArch').storage,
        contains('Snes9x'));
    expect(rows.singleWhere((r) => r.label == 'RetroArch').storage,
        contains('Genesis Plus GX'));
    expect(rows.singleWhere((r) => r.label == 'RetroArch').states,
        startsWith('Custom mapping'));
    expect(rows.singleWhere((r) => r.label == 'PPSSPP').states,
        startsWith('Verified'));
    expect(rows.singleWhere((r) => r.label == 'PPSSPP').saves,
        'In-game saves · complete PPSSPP SAVEDATA folders.');
    for (final row in SaveEmulatorCoverage.decode([
      _row('com.retroarch.aarch64', '1.23.0'),
      _row('org.ppsspp.ppsspp', '1.21.0'),
    ])) {
      expect('${row.saves} ${row.states}', isNot(contains('Verified')));
      expect('${row.saves} ${row.states}', contains('Needs review'));
    }
  });

  test('PPSSPP coverage describes the verified folder and normal-exit routes',
      () {
    for (final version in ['1.20.4', 'v1.20.4']) {
      final row = SaveEmulatorCoverage.decode([
        _row('org.ppsspp.ppsspp', version),
      ]).single;
      expect(row.saves, contains('SAVEDATA'));
      expect(row.saves, isNot(contains('Unfinished')));
      expect(row.storage, contains('SAVEDATA'));
      expect(row.storage, contains('PPSSPP_STATE'));
      expect(row.storage, contains('root'));
      expect(row.storage, contains('Exit'));
      expect(row.storage, isNot(contains('App info')));
    }
    final changed = SaveEmulatorCoverage.decode([
      _row('org.ppsspp.ppsspp', '1.21.0'),
    ]).single;
    expect(changed.saves, startsWith('Needs review'));
    expect(changed.states, startsWith('Needs review'));
    expect(changed.storage, startsWith('Needs review'));
  });

  test('advertised provider is neither a grant nor implemented restore support',
      () {
    final row = SaveEmulatorCoverage.decode([
      _row('io.github.lime3ds.android', '2606',
          ['io.github.lime3ds.android.user'])
    ]).single;
    expect(row.storage, contains('does not select'));
    expect(row.saves, startsWith('Automatic mapping pending'));
    expect(row.states, startsWith('Custom mapping'));
    expect(row.storage, isNot(contains('unsupported')));
  });

  test(
      'Melon coverage describes automatic root discovery and coherent live capture',
      () {
    final current = SaveEmulatorCoverage.decode(
        [_row('me.magnum.melondualds', '0.8.0.rc2')]).single;
    expect(current.saves, contains('shared'));
    expect(current.saves, contains('completed'));
    expect(current.saves, isNot(contains('must be closed')));
    expect(current.storage, contains('Android/data'));
    expect(current.storage, contains('Root'));
    expect(current.storage, contains('automatically'));
    expect(current.storage, contains('Restore'));
    expect(current.storage, isNot(contains('before capture')));
    expect(current.storage, isNot(contains('still being integrated')));
    expect(current.storage, isNot(contains('not accessible')));
    expect(current.states, startsWith('Custom mapping'));
    final changed =
        SaveEmulatorCoverage.decode([_row('me.magnum.melondualds', '0.9.0')])
            .single;
    expect(changed.saves, startsWith('Needs review'));
  });

  test('launchers and unreviewed emulators are not falsely unsupported', () {
    final rows = SaveEmulatorCoverage.decode([
      _row('org.es_de.frontend', '3.4.1'),
      _row('com.flycast.emulator', 'v2.6'),
    ]);
    expect(rows.first.saves, startsWith('Not applicable'));
    expect(rows.last.saves, contains('shared virtual VMU cards'));
    expect(rows.last.storage, contains('not BIOS'));
  });

  test('Dolphin card coverage does not claim Wii NAND or raw-card discovery',
      () {
    final row =
        SaveEmulatorCoverage.decode([_row('org.dolphinemu.dolphinemu', '2606')])
            .single;
    expect(row.saves, contains('shared GCI memory-card folders'));
    expect(row.storage, contains('Wii NAND'));
    expect(row.storage, contains('Raw cards'));
  });
  test('malformed or substituted inventory fails as a whole', () {
    final good = _row('org.ppsspp.ppsspp', 'v1.20.4');
    for (final rows in <List<dynamic>?>[
      null,
      [good, good],
      [_row('unrequested.app', '1')],
      [_row('org.ppsspp.ppsspp', '')],
      [_row('org.ppsspp.ppsspp', 'bad\nversion')],
      [
        _row('org.ppsspp.ppsspp', '1', ['content://other'])
      ],
      [
        _row('org.ppsspp.ppsspp', '1', ['same.authority', 'same.authority'])
      ],
      [42],
      [
        {'packageName': 'org.ppsspp.ppsspp'}
      ],
    ]) {
      expect(() => SaveEmulatorCoverage.decode(rows), throwsFormatException);
    }
    expect(SaveEmulatorCoverage.decode([]), isEmpty);
  });
}
