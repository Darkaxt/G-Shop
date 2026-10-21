import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/features/settings/sources_screen.dart';
import 'package:g_shop/features/sources/manual_source_add_screen.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/game_providers.dart';
import 'package:g_shop/services/config_storage_service.dart';
import 'package:g_shop/services/sources_notifier.dart';
import 'package:g_shop/services/storage_service.dart';

class _MemoryConfig extends ConfigStorageService {
  AppConfig config;
  _MemoryConfig(this.config);
  @override
  Future<AppConfig?> loadConfig() async => config;
  @override
  Future<File> saveConfig(String text) async {
    config = AppConfig.fromJson(jsonDecode(text));
    return File('synthetic-config-not-written');
  }
}

const _drive = Source(
  id: 'synthetic-drive',
  name: 'Synthetic private library',
  type: SourceType.drive,
  enabled: false,
  drive: DriveSourceConfig(
      accountId: 'synthetic-account',
      rootFolderId: 'synthetic-root',
      serverClientId: 'synthetic-client'),
);

void main() => defineSourceMenuNavigationChecks();

/// Real screen, focus scopes, routes and notifier; only persistent config and
/// platform preferences are synthetic. No account/bootstrap/ROM access.
void defineSourceMenuNavigationChecks({
  bool native = false,
  Future<void> Function(String name, WidgetTester tester)? checkpoint,
  void Function(String check)? verified,
}) {
  Future<({_MemoryConfig config, ProviderContainer container})> open(
      WidgetTester tester,
      {Size? size,
      Locale locale = const Locale('en'),
      double textScale = 1}) async {
    if (!native) {
      tester.view.physicalSize = size ?? const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final config =
        _MemoryConfig(AppConfig(systems: const [], sources: [_drive]));
    final notifier = SourcesNotifier(config);
    await notifier.ready;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      sourcesProvider.overrideWith((ref) => notifier),
      bootstrappedConfigProvider.overrideWith((ref) async => config.config),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            locale: locale,
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!),
            home: const SourcesScreen())));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    return (config: config, container: container);
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.tap(find.text(_drive.name));
    await tester.pumpAndSettle();
  }

  testWidgets('Drive actions activate by touch through the normal notifier',
      (tester) async {
    final fixture = await open(tester);
    await openActions(tester);
    await tester.ensureVisible(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(find.text('Enable').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(fixture.config.config.sources.single.enabled, isTrue);
    expect(
        fixture.container.read(sourcesProvider).sources.single.enabled, isTrue);
    expect(find.text('Cancel'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    verified?.call('touch_enable_persists');
  });

  testWidgets(
      'landscape Drive actions scroll controller selection and wrap labels',
      (tester) async {
    await open(tester, size: const Size(800, 360));
    await openActions(tester);
    expect(tester.takeException(), isNull);
    // Wrap up from the first action to the last, visibly, then cancel by A.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final cancel = find.byKey(const ValueKey('source-action-7'));
    expect(cancel.hitTestable(), findsOneWidget);
    await checkpoint?.call('sources-controller-cancel', tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    // Focus returns to the original card, so A opens it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.text('Edit mappings'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    verified?.call('controller_wrap_cancel_focus_restore');
  });

  testWidgets('Drive action labels are localized and safe at large text scale',
      (tester) async {
    await open(tester,
        size: const Size(640, 360), locale: const Locale('es'), textScale: 1.4);
    await openActions(tester);
    expect(find.text('Actualizar catálogo'), findsOneWidget);
    expect(find.text('Conectar / configurar'), findsOneWidget);
    expect(find.text('Refresh catalogue'), findsNothing);
    expect(tester.takeException(), isNull);
    await checkpoint?.call('sources-localized-actions', tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    verified?.call('localized_large_text_labels');
  });

  testWidgets('source type picker supports touch and controller scrolling',
      (tester) async {
    await open(tester, size: const Size(800, 360));
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final web = find.byKey(const ValueKey('source-type-5'));
    expect(web.hitTestable(), findsOneWidget);
    await checkpoint?.call('sources-type-web', tester);
    await tester.tap(web);
    await tester.pumpAndSettle();
    expect(find.byType(ManualSourceAddScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    verified?.call('type_picker_scroll_touch_route');
  });
}
