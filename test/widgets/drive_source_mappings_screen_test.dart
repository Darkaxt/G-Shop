import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/sources/drive_source_mappings_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';

class _Runtime extends DriveRuntime {
  final bool duplicate;
  _Runtime(this.duplicate);
  @override
  Future<List<DriveFile>> folders(Source source) async => [
        DriveFile(
            id: 'first',
            name: 'SNES',
            mimeType: DriveFile.folderMime,
            parents: ['root-id']),
        if (duplicate)
          DriveFile(
              id: 'second',
              name: 'Super Famicom',
              mimeType: DriveFile.folderMime,
              parents: ['root-id']),
      ];
}

void main() {
  for (final duplicate in [false, true]) {
    testWidgets(
        'empty configuration offers consoles, ambiguous alias=$duplicate',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
          ],
          child: MaterialApp(
              home: DriveSourceMappingsScreen(
            source: const Source(
                id: 'source', name: 'Drive', type: SourceType.drive),
            runtime: _Runtime(duplicate),
          ))));
      await tester.pump();
      expect(find.text('Nintendo Entertainment System'), findsWidgets);
      expect(find.text('Super Nintendo'), findsWidgets);
      final rows = tester
          .widgetList<DropdownButtonFormField<String?>>(
              find.byType(DropdownButtonFormField<String?>))
          .toList();
      expect(rows.length, greaterThanOrEqualTo(2));
      expect(rows[0].initialValue, isNull);
      expect(rows[1].initialValue, duplicate ? isNull : 'first');
      expect(tester.takeException(), isNull);
    });
  }
}
