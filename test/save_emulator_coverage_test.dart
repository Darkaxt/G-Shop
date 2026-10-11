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
        'In-game saves · GBA, Game Gear, Master System and Mega Drive. Clock-data restore is not yet supported.');
    expect(rows.singleWhere((r) => r.label == 'RetroArch').storage,
        contains('Genesis Plus GX'));
    expect(rows.singleWhere((r) => r.label == 'RetroArch').states,
        startsWith('Unfinished'));
    expect(rows.singleWhere((r) => r.label == 'PPSSPP').states,
        startsWith('Verified'));
    expect(rows.singleWhere((r) => r.label == 'PPSSPP').saves,
        startsWith('Unfinished'));
    for (final row in SaveEmulatorCoverage.decode([
      _row('com.retroarch.aarch64', '1.23.0'),
      _row('org.ppsspp.ppsspp', '1.21.0'),
    ])) {
      expect('${row.saves} ${row.states}', isNot(contains('Verified')));
      expect('${row.saves} ${row.states}', contains('Needs review'));
    }
  });

  test('advertised provider is neither a grant nor implemented restore support',
      () {
    final row = SaveEmulatorCoverage.decode([
      _row('org.dolphinemu.dolphinemu', '2606',
          ['org.dolphinemu.dolphinemu.user'])
    ]).single;
    expect(row.storage, contains('user grant'));
    expect(row.storage, contains('read/write review'));
    expect(row.saves, startsWith('Unfinished'));
    expect(row.states, startsWith('Unfinished'));
    expect(row.storage, isNot(contains('unsupported')));
  });

  test('launchers and unreviewed emulators are not falsely unsupported', () {
    final rows = SaveEmulatorCoverage.decode([
      _row('org.es_de.frontend', '3.4.1'),
      _row('com.flycast.emulator', 'v2.6'),
    ]);
    expect(rows.first.saves, startsWith('Not applicable'));
    expect(rows.last.saves, startsWith('Unfinished'));
    expect(rows.last.storage, contains('not a claim'));
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
