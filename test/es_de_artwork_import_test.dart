import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reviewed PNG JPG and WebP normalize to bounded immutable cache images',
      () async {
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    final root =
        await Directory.systemTemp.createTemp('rshop-reviewed-formats-');
    try {
      final cache = MetadataArtworkCache(
          Future.value(db), Directory(p.join(root.path, 'cache')));
      final media =
          MetadataMedia(type: 'cover', url: 'https://example.com/cover.png');
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
      final samples = {
        '.png': png,
        '.jpg': img.encodeJpg(img.decodePng(png)!),
        '.webp': base64Decode(
            'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA'),
      };
      for (final sample in samples.entries) {
        final source = File(p.join(root.path, 'cover${sample.key}'));
        await source.writeAsBytes(sample.value);
        final imported = await cache.importReviewedImage(source, media);
        expect(imported.sourceLength, sample.value.length);
        final normalized =
            await File(p.join(cache.root.path, imported.blob.filename))
                .readAsBytes();
        expect(img.decodePng(normalized), isNotNull,
            reason: 'Actual ${sample.key} native decoding');
        expect(await source.readAsBytes(), sample.value);
      }
      final hugeHeader = Uint8List.fromList(png);
      final header = ByteData.sublistView(hugeHeader);
      header.setUint32(16, 2049);
      header.setUint32(20, 2049);
      header.setUint32(29, getCrc32(hugeHeader.sublist(12, 29)));
      final oversized = File(p.join(root.path, 'oversized.png'));
      await oversized.writeAsBytes(hugeHeader);
      await expectLater(cache.importReviewedImage(oversized, media),
          throwsA(isA<FormatException>()));
      final oversizedBody = File(p.join(root.path, 'oversized.jpg'));
      await oversizedBody
          .writeAsBytes(Uint8List(MetadataArtworkCache.maxBytes + 1));
      await expectLater(cache.importReviewedImage(oversizedBody, media),
          throwsA(isA<FormatException>()));
      expect(await cache.root.list().where((e) => e is Directory).toList(),
          isEmpty,
          reason:
              'Joined import cleanup leaves no disposable staging directories');
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
