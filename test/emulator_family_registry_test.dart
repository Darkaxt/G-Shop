import 'dart:convert';
import 'dart:io';
import 'package:retro_eshop/services/saves/emulator_family_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/models/emulator_family_registry.dart';
import 'package:retro_eshop/models/save_emulator_coverage.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late File shared;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final root = Directory('D:/Temp/rshop-s10-family-settings-20261014');
    root.createSync(recursive: true);
    final directory = root.createTempSync('registry-');
    shared = File('${directory.path}/emulator_families.json');
  });
  const alias = {
    'package': 'org.example.switchfork',
    'family': 'eden',
    'name': 'My Switch fork'
  };
  String file(List<Object> entries) =>
      jsonEncode({'schema': 1, 'packages': entries});
  test(
      'the bundled file registers existing apps and Eden Duo as the Eden family',
      () async {
    final registry = await EmulatorFamilyRegistry.load();
    expect(registry.packages['dev.igawa6.edenduo']!.family, 'eden');
    expect(registry.packages['org.dolphinemu.dolphinemu']!.family, 'dolphin');
    expect(() => registry.packages.clear(), throwsUnsupportedError);
    expect(EmulatorFamilyRegistry.decode(registry.encode()).encode(),
        registry.encode());
  });
  test(
      'shared file seeds defaults, reloads external edits and recovers after restart',
      () async {
    final settings = await EmulatorFamilySettings.open(file: shared);
    expect(shared.existsSync(), isTrue);
    expect(settings.registry.packages, contains('dev.igawa6.edenduo'));
    shared.writeAsStringSync(file([alias]), flush: true);
    await settings.reload();
    expect(settings.registry.packages.keys, ['org.example.switchfork']);
    expect(settings.issue, isNull);
    shared.writeAsStringSync('{unfinished', flush: true);
    await settings.reload();
    expect(settings.registry.packages.keys, ['org.example.switchfork']);
    expect(settings.issue, isNotNull);
    final reopened = await EmulatorFamilySettings.open(file: shared);
    expect(reopened.registry.encode(), settings.registry.encode());
    expect(shared.readAsStringSync(), '{unfinished');
    shared.writeAsStringSync(file([alias]), flush: true);
    await reopened.reload();
    expect(reopened.issue, isNull);
  });
  test(
      'in-app changes persist to the same file and stale edits preserve external changes',
      () async {
    SharedPreferences.setMockInitialValues(
        {'existing-save-mapping': 'keep', 'backup-state': 'keep'});
    final settings = await EmulatorFamilySettings.open(file: shared);
    final replacement = EmulatorFamilyRegistry.decode(file([alias]));
    File('${shared.path}.pending').writeAsStringSync('interrupted app write');
    await settings.save(replacement, expectedSource: settings.source);
    expect(EmulatorFamilyRegistry.decode(shared.readAsStringSync()).encode(),
        replacement.encode());
    final original = settings.source;
    final external = file([
      {...alias, 'name': 'External edit'}
    ]);
    shared.writeAsStringSync(external, flush: true);
    await expectLater(
        settings.save(replacement, expectedSource: original), throwsStateError);
    expect(shared.readAsStringSync(), external);
    final reopened = await EmulatorFamilySettings.open(file: shared);
    expect(reopened.registry.packages[alias['package']]!.name, 'External edit');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('existing-save-mapping'), 'keep');
    expect(prefs.getString('backup-state'), 'keep');
    expect(File('${shared.path}.pending').existsSync(), isFalse);
  });
  test('file notifications reload external saves without a polling timer',
      () async {
    final settings = await EmulatorFamilySettings.open(file: shared);
    final changed = settings.watch().first.then((_) => settings.reload());
    shared.writeAsStringSync(file([alias]), flush: true);
    await changed;
    expect(settings.registry.packages.keys, ['org.example.switchfork']);
    expect(settings.issue, isNull);
  });
  test(
      'invalid schemas, unsafe packages, duplicate IDs and oversized files are rejected',
      () {
    for (final invalid in [
      jsonEncode({
        'schema': 2,
        'packages': [alias]
      }),
      file([]),
      file([
        {...alias, 'package': '../other'}
      ]),
      file([
        {...alias, 'package': 'a.12bad'}
      ]),
      file([
        {...alias, 'name': 'bad\nname'}
      ]),
      file([
        {...alias, 'token': 'not-allowed'}
      ]),
      file(List.filled(65, alias)),
      ' ' * (EmulatorFamilyRegistry.maxBytes + 1),
    ]) {
      expect(
          () => EmulatorFamilyRegistry.decode(invalid), throwsFormatException);
    }
  });
  test('a file-added package crosses discovery and receives family guidance',
      () async {
    final settings = await EmulatorFamilySettings.open(file: shared);
    shared.writeAsStringSync(file([alias]));
    await settings.reload();
    const channel = MethodChannel('com.retro.rshop/save_capture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, {
        'packages': ['org.example.switchfork']
      });
      return [
        {
          'packageName': 'org.example.switchfork',
          'versionName': '1',
          'documentAuthorities': <String>[]
        }
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final entry =
        (await SaveCapture().installedEmulators(registry: settings.registry))
            .single;
    expect(entry.family, 'eden');
    expect(entry.label, 'My Switch fork');
    expect(entry.storage, contains('title and user/profile'));
    expect(entry.packageName, 'org.example.switchfork');
  });
  test(
      'family membership cannot impersonate a reviewed runtime or admit an unrequested package',
      () {
    final registry = EmulatorFamilyRegistry.decode(file([
      {...alias, 'family': 'ppsspp'}
    ]));
    final row = {
      'packageName': 'org.example.switchfork',
      'versionName': 'v1.20.4',
      'documentAuthorities': <String>[]
    };
    final entry = SaveEmulatorCoverage.decode([row], registry: registry).single;
    expect(entry.family, 'ppsspp');
    expect(entry.states, isNot(startsWith('Verified')));
    expect(entry.saves, contains('not verified'));
    expect(
        () => SaveEmulatorCoverage.decode([
              {...row, 'packageName': 'org.ppsspp.ppsspp'}
            ], registry: registry),
        throwsFormatException);
  });
}
