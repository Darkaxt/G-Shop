import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/core/input/global_input_wrapper.dart';
import 'package:retro_eshop/features/settings/migration_settings_screen.dart';
import 'package:retro_eshop/providers/migration_providers.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/migration/migration_service.dart';
import '../migration_activation_test.dart' show MemorySettings;
import '../helpers/pump_helpers.dart';

void main() {
  for (final size in [const Size(1920, 1080), const Size(800, 450)]) {
    testWidgets(
        'migration sections and password dialog support controllers at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = MigrationService(
          locations: MigrationLocations(
              documents: Directory('/unused/documents'),
              support: Directory('/unused/support'),
              configuration: Directory('/unused/config'),
              roms: Directory('/unused/roms'),
              database: File('/unused/database')),
          database: Completer<Database>().future,
          configuration: ConfigStorageService(),
          settings: MemorySettings(),
          sharedMetadata: Future.value(null),
          captureAssociated: () async => [],
          joinOwners: () async => (_) async {},
          closeDatabase: () async {});
      await tester.pumpWidget(ProviderScope(
          overrides: [
            migrationServiceProvider.overrideWith((ref) async => service)
          ],
          child: GlobalInputWrapper(
              child: createTestApp(const MigrationSettingsScreen()))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('migration-backup')), findsOneWidget);
      expect(find.byKey(const ValueKey('migration-restore')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('migration-restore')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('migration-backup')));
      await tester.tap(find.byKey(const ValueKey('migration-backup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('migration-password')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('migration-backup')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      service.dispose();
    });
  }
}
