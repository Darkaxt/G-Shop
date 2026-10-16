import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/preview_settings.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/providers/preview_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/metadata/preview_video_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'metadata_controls_test.dart' show ControlsArtworkProvider;

Uint8List movie(int value) {
  Uint8List box(String type, List<int> body) {
    final result = Uint8List(8 + body.length);
    ByteData.sublistView(result).setUint32(0, result.length);
    result.setRange(4, 8, ascii.encode(type));
    result.setRange(8, result.length, body);
    return result;
  }

  return Uint8List.fromList([
    ...box('ftyp', [0, 0, 0, value]),
    ...box('moov', [0]),
    ...box('mdat', [value, value])
  ]);
}

class _MovieProvider extends ControlsArtworkProvider {
  Uint8List bytes = movie(1);
  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    await write(bytes);
    return MetadataLookupResult(
        status: MetadataLookupStatus.matched, message: 'Fixture clip');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'preview preferences survive restart with bounded settings and no secrets',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final preferences = PreviewSettingsNotifier(storage);
    expect(preferences.state.sound, isTrue);
    expect(preferences.state.downloads, PreviewDownloadPolicy.wifi);
    await preferences.change('background', 'slideshow');
    await preferences.change('cacheMiB', 256);
    await preferences.change('blur', 1000);
    final reopened = StorageService();
    await reopened.init();
    expect(reopened.getPreviewSettings().toJson(), preferences.state.toJson());
    expect(reopened.getPreviewSettings().blur, 20);
    expect(
        PreviewSettings.fromJson(
            {'background': 'unknown', 'brightness': double.nan}).brightness,
        .45);
    preferences.dispose();
  });
  test(
      'clip publication validates structure and decoder before offline readiness; eviction is owned',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('rshop-preview-cache-');
    final store =
        await SharedMetadataStore.open(root, factory: databaseFactoryFfi);
    addTearDown(() async {
      await store.close();
      await root.delete(recursive: true);
    });
    var decoded = 0;
    final cache = PreviewVideoCache(store, validateDecoder: (file) async {
      decoded++;
      expect(await file.length(), movie(1).length);
    });
    MetadataMedia media(String game) => MetadataMedia(
        type: 'video',
        providerReference: ScreenScraperMediaReference(
            providerGameId: game, providerPlatformId: 4, mediaType: 'video'));
    final provider = _MovieProvider();
    final path = await cache.acquire(media('42'), provider, CancelToken(),
        budgetBytes: 1024);
    expect(decoded, 1);
    expect(await cache.find(media('42')), path);
    final unrelated = File('${cache.root.path}/user-video.mp4');
    await unrelated.writeAsBytes(movie(9));
    await cache.trim(0, protectedPaths: {path});
    expect(await File(path).exists(), isTrue);
    await cache.trim(0);
    expect(await cache.find(media('42')), isNull);
    expect(await unrelated.exists(), isTrue);
    provider.bytes = Uint8List.fromList([...movie(1), 0]);
    await expectLater(
        cache.acquire(media('43'), provider, CancelToken(), budgetBytes: 1024),
        throwsFormatException);
    expect(decoded, 1,
        reason: 'Truncated structure must not reach native decoding');
    expect(await cache.find(media('43')), isNull);
  });
}
