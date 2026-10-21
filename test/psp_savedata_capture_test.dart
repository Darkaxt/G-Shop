import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/saves/save_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.darkaxt.gshop/save_capture');
  const parent = '/storage/emulated/0/PSP/SAVEDATA';
  const directory = '$parent/ULUS10001DATA00';
  final calls = <MethodCall>[];
  late Map<String, dynamic> receipt;
  setUp(() {
    calls.clear();
    receipt = {
      'captureId': 'a' * 32,
      'deviceId': 'device',
      'emulatorVersion': 'v1.20.4',
      'files': [
        for (final name in ['CUSTOM.SAV', 'EMPTY', 'ICON0.PNG', 'PARAM.SFO'])
          {
            'name': name,
            'path': '/private/save-captures/${'a' * 32}/member-$name',
            'size': name == 'EMPTY' ? 0 : 17,
            'sha256': 'b' * 64,
          }
      ]
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'ppssppSaveSettings' => {
            'directory': '/storage/emulated/0/PSP/PPSSPP_STATE'
          },
        'ppssppSavedataFolders' => ['ULUS10001DATA00'],
        _ => receipt
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('discovers save folders from the configured Memory Stick', () async {
    final capture = SaveCapture();
    expect(await capture.ppssppSavedataParent(), parent);
    expect(await capture.ppssppSavedataFolders(parent), ['ULUS10001DATA00']);
    expect(calls.last.arguments, {'directory': parent});
  });

  test('captures all payloads and empty companions, separately from states',
      () async {
    final group = await SaveCapture()
        .capturePpssppSavedata(captureId: 'a' * 32, directory: directory);
    expect(calls.single.method, 'capturePpssppSavedata');
    expect(calls.single.arguments,
        {'captureId': 'a' * 32, 'directory': directory});
    expect(group.files.map((member) => member.name),
        ['CUSTOM.SAV', 'EMPTY', 'ICON0.PNG', 'PARAM.SFO']);
    expect(group.files[1].size, 0);
    expect(SaveCapture.validPpssppDirectory(directory), false);
  });

  test('stages a whole save folder, including an empty companion', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendRestoreGroup') {
        final row = call.arguments as Map;
        return (row['offset'] as int) + (row['bytes'] as Uint8List).length;
      }
      return null;
    });
    await SaveCapture().stagePpssppSavedataRestore(
        restoreId: 'c' * 32,
        directory: directory,
        members: [
          RestoreSaveMember(
              'PARAM.SFO', 65537, 'a' * 64, Stream.value(Uint8List(65537))),
          RestoreSaveMember(
              'EMPTY',
              0,
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
              const Stream.empty()),
        ]);
    expect(calls.map((call) => call.method), [
      'beginRestoreGroup',
      'appendRestoreGroup',
      'appendRestoreGroup',
      'sealRestoreGroup',
    ]);
    expect(calls.first.arguments['ppssppSavedataDirectory'], directory);
    expect(calls.first.arguments['name'], 'ULUS10001DATA00');
    expect(calls.first.arguments['members'][0]['name'], 'EMPTY');
    expect(calls[1].arguments['member'], 1);
    expect((calls[1].arguments['bytes'] as Uint8List).length, 65536);
    expect(calls[2].arguments['offset'], 65536);
  });

  test('transport failure at empty-member EOF cannot seal a restore', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await expectLater(
        SaveCapture().stagePpssppSavedataRestore(
            restoreId: 'c' * 32,
            directory: directory,
            members: [
              RestoreSaveMember(
                  'EMPTY',
                  0,
                  'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                  Stream.error(const FormatException('revision changed'))),
            ]),
        throwsFormatException);
    expect(calls.map((call) => call.method), ['beginRestoreGroup']);
  });

  test('rejects partial or unsafe complete-folder receipts', () async {
    for (final bad in [
      [],
      [receipt['files'][0], receipt['files'][0]],
      [
        {...receipt['files'][0], 'name': '../other'}
      ],
      [
        {...receipt['files'][0], 'size': -1}
      ],
      List.generate(
          129, (index) => {...receipt['files'][0], 'name': 'F$index'}),
      [
        {...receipt['files'][0], 'size': 512 * 1024 * 1024 + 1}
      ],
      [
        {...receipt['files'][0], 'size': 300 * 1024 * 1024},
        {...receipt['files'][1], 'size': 300 * 1024 * 1024}
      ],
    ]) {
      receipt['files'] = bad;
      await expectLater(
          SaveCapture()
              .capturePpssppSavedata(captureId: 'a' * 32, directory: directory),
          throwsFormatException);
    }
    for (final bad in [
      '/storage/emulated/0/PSP/PPSSPP_STATE',
      '$parent/../other',
      '/storage/emulated/0/Android/data/other/files/PSP/SAVEDATA/ABC',
      '/data/user/0/org.ppsspp.ppsspp/files',
    ]) {
      expect(SaveCapture.validPpssppSavedataDirectory(bad), false);
    }
  });
}
