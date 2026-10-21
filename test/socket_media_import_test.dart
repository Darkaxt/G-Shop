import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/services/socket_media_import.dart';
import 'package:g_shop/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.darkaxt.gshop/socket_import');
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'startupCleanup'
              ? false
              : throw StateError('Unexpected native action')));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('missing import gates old 3D preferences and importing cannot enable it',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    expect(storage.getPhysicalMediaEnabled(), isFalse);
    await storage.setPhysicalMediaEnabled(true);
    final settings = MediaPresentationNotifier(storage);
    addTearDown(settings.dispose);
    expect(settings.state.enabled, isFalse);
    await expectLater(settings.toggleMedia(), throwsStateError);
    settings.resourcesChanged(true);
    expect(settings.state.enabled, isFalse);
    await settings.toggleMedia();
    expect(settings.state.enabled, isTrue);
    expect(storage.getPhysicalMediaEnabled(), isTrue);
  });

  test(
      'wrong APK removes only its stage and preserves original and active pointer',
      () async {
    const selectedRoot = String.fromEnvironment('RSHOP_IMPORT_TEST_ROOT');
    final parent = selectedRoot.isEmpty
        ? Directory.systemTemp
        : await Directory(selectedRoot).create(recursive: true);
    final root = await parent.createTemp('rshop-import-contract-');
    final original =
        await File('${root.path}/original.apk').writeAsBytes([1, 2, 3]);
    final resources = await Directory('${root.path}/resources').create();
    final pointer = await File('${resources.path}/active.json')
        .writeAsString('prior pointer');
    final importer = SocketMediaImport(directory: resources);
    addTearDown(importer.dispose);
    try {
      await expectLater(importer.importApk(original), throwsFormatException);
      expect(await original.readAsBytes(), [1, 2, 3]);
      expect(await pointer.readAsString(), 'prior pointer');
      expect(
          await resources
              .list()
              .map((entry) => entry.path.split(Platform.pathSeparator).last)
              .toList(),
          ['active.json']);
      expect(importer.importing, isFalse);
      expect(importer.available, isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('procedural import keeps source RGB ramp and L8 normalization', () {
    final texture = <String, dynamic>{
      'width': 2,
      'height': 1,
      'sourceTree': {
        'type': 'NoiseTexture2D',
        'properties': {
          'color_ramp': {
            'properties': {
              'colors': {
                'values': [0, 0, 1, 1, 1, 0, 0, 1]
              }
            }
          },
        }
      },
    };
    expect(socketProceduralPixels(texture, Float32List.fromList([-.4, .8])),
        [0, 0, 255, 255, 255, 0, 0, 255]);
    expect(() => SocketMediaDirectoryBundle.checkName('../outside'),
        throwsFormatException);
  });

  test('texture PNG preserves a platform-channel byte view offset', () {
    final buffer = Uint8List.fromList([99, 98, 97, 96, 12, 34, 56, 255]);
    final rgba = Uint8List.sublistView(buffer, 4);
    final decoded = img.decodePng(encodeSocketTexture((1, 1, rgba)))!;
    final pixel = decoded.getPixel(0, 0);
    expect([pixel.r, pixel.g, pixel.b, pixel.a], [12, 34, 56, 255]);
  });
}
