import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.retro.rshop/save_capture');
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
