import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/core/widgets/console_focusable.dart';
import 'package:g_shop/features/settings/widgets/general_tab.dart';
import 'package:g_shop/features/settings/widgets/advanced_tab.dart';
import 'package:g_shop/features/settings/metadata_settings_screen.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/providers/library_providers.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/library_query.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/storage_service.dart';
import 'package:g_shop/services/cover_preload_service.dart';
import 'package:g_shop/widgets/media_cover_fallback.dart';
import '../metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;
import '../helpers/pump_helpers.dart';

class _SavedPageControls extends MetadataControlsController {
  Future<List<MetadataRefreshReport>>? lastPage;
  _SavedPageControls(
      {required super.database,
      required super.providers,
      required super.screenScraperCredentials,
      required super.igdbCredentials,
      required super.catalogueChanged});
  @override
  Future<List<MetadataRefreshReport>> savedJobs({int? beforeId}) =>
      lastPage = super.savedJobs(beforeId: beforeId);
}

void main() {
  testWidgets(
      'Advanced cover entry opens ScreenScraper collector without starting',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(controlsDatabase))!;
    await tester.runAsync(() => LibraryQuery.install(db));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final provider = ControlsProvider();
    final igdb = ControlsProvider('igdb');
    final controls = (await tester.runAsync(() async {
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider, 'igdb': igdb},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          catalogueChanged: () {});
      await controls.load();
      await controls.selectProvider('igdb');
      return controls;
    }))!;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
      coverPreloadServiceProvider.overrideWith(
          (_) => throw StateError('Legacy cover preloading must not be used')),
    ]);
    final focus = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await controls.close();
        await db.close();
      });
      container.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(SettingsAdvancedTab(firstFocusNode: focus))));
    await tester.pumpAndSettle();
    final entry = find.text('Get metadata & covers');
    expect(entry, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(entry);
      await controls.load();
    });
    await tester.pumpAndSettle();
    expect(find.byType(MetadataSettingsScreen), findsOneWidget);
    expect(controls.state.providerId, 'screenscraper');
    expect(find.byKey(const ValueKey('metadata-scope')), findsOneWidget);
    expect(find.byKey(const ValueKey('metadata-refresh')), findsOneWidget);
    expect(provider.calls, isEmpty);
    expect(igdb.calls, isEmpty);
    expect(controls.state.report, isNull);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
      await controls.load();
    });
    await tester.pumpAndSettle();
    expect(controls.state.providerId, 'igdb');
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
      await controls.load();
    });
    await tester.pumpAndSettle();
    expect(controls.state.providerId, 'screenscraper');
    expect(provider.calls, isEmpty);
    expect(igdb.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('metadata-open-scraping')));
    await tester.pumpAndSettle();
    // Start explicitly from the collector and prove it uses the same owner.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('metadata-refresh')));
      await controls.pause();
      if (controls.state.report!.state != 'completed') await controls.resume();
    });
    await tester.pumpAndSettle();
    expect(provider.calls, hasLength(2));
    expect(igdb.calls, isEmpty);
    expect(controls.state.report!.providerId, 'screenscraper');
    expect(controls.state.report!.state, 'completed');
    final top = find.text('Top 25 per console');
    await tester.ensureVisible(top);
    Focus.of(tester.element(top)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SegmentedButton<bool>>(
                find.byKey(const ValueKey('metadata-top25')))
            .selected,
        {true});
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('metadata-refresh')));
      await controls.pause();
      if (controls.state.report!.state != 'completed') await controls.resume();
    });
    await tester.pumpAndSettle();
    expect(controls.state.report!.top25PerSystem, isTrue);
    expect(controls.state.report!.selectionCoverage.keys,
        containsAll(['psx', 'psp']));
    expect(provider.calls, hasLength(2),
        reason: 'No unranked alphabetical fill requests');
    expect(find.text('Top 25 selection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved jobs page selects older work by touch and controller',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(controlsDatabase))!;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final provider = ControlsProvider();
    final ids = <int>[];
    final controls = (await tester.runAsync(() async {
      final controls = _SavedPageControls(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          catalogueChanged: () {});
      final jobs = MetadataRefreshJobs(Future.value(db));
      for (var i = 0; i < 12; i++) {
        ids.add((await jobs.createFromCatalogue(
                providerId: 'screenscraper', systemSlug: 'psp'))
            .id);
      }
      await controls.load();
      return controls;
    }))!;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    addTearDown(() async {
      await tester.runAsync(() async {
        await controls.close();
        await db.close();
      });
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(const MetadataSettingsScreen())));
    await tester.pumpAndSettle();
    // Provider overview is not a giant credentials/scraping/storage form.
    final navigation = find.byKey(const ValueKey('metadata-navigation'));
    expect(navigation, findsOneWidget);
    final firstSection = find
        .ancestor(
            of: find.byKey(const ValueKey('metadata-nav-screenscraper')),
            matching: find.byType(ConsoleFocusable))
        .first;
    expect(
        tester
            .widget<Focus>(find
                .descendant(of: firstSection, matching: find.byType(Focus))
                .first)
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
        reason:
            'Controller entry must focus a section, not the full-screen node');
    expect(find.byKey(const ValueKey('metadata-username')), findsNothing);
    expect(find.byKey(const ValueKey('metadata-saved-jobs')), findsNothing);
    final scraping = find.byKey(const ValueKey('metadata-open-scraping'));
    expect(tester.getRect(navigation).right,
        lessThan(tester.getRect(scraping).left));
    await tester.tap(scraping);
    await tester.pumpAndSettle();
    final transport = {
      'metadata-refresh': (
        Icons.play_circle_outline,
        'Get fresh game information'
      ),
      'metadata-pause': (Icons.pause_rounded, 'Pause'),
      'metadata-resume': (Icons.play_arrow_rounded, 'Resume saved job'),
      'metadata-retry': (Icons.replay_rounded, 'Retry failed / unmatched'),
    };
    final semantics = tester.ensureSemantics();
    for (final action in transport.entries) {
      final button = find.byKey(ValueKey(action.key));
      expect(tester.widget(button), isA<IconButton>(),
          reason: 'Scraping transport must not use long text buttons');
      expect(tester.widget<IconButton>(button).tooltip, action.value.$2);
      expect(tester.getSemantics(button).tooltip, action.value.$2);
      expect(
          find.descendant(of: button, matching: find.byIcon(action.value.$1)),
          findsOneWidget);
      expect(find.descendant(of: button, matching: find.byType(Text)),
          findsNothing);
      expect(tester.getSize(button).width, inInclusiveRange(48, 64));
      expect(tester.getSize(button).height, inInclusiveRange(48, 64));
    }
    semantics.dispose();
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('metadata-pause')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('metadata-resume')))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('metadata-retry')))
            .onPressed,
        isNull);
    final open = find.byKey(const ValueKey('metadata-saved-jobs'));
    await tester.ensureVisible(open);
    await tester.runAsync(() async {
      await tester.tap(open);
      await tester.pump();
      await controls.lastPage;
    });
    await tester.pumpAndSettle();
    expect(
        find.byKey(ValueKey('metadata-saved-job-${ids.first}')), findsNothing);
    final older = find.byKey(const ValueKey('metadata-older-jobs'));
    await tester.scrollUntilVisible(older, 250,
        scrollable: find
            .descendant(
                of: find.byType(AlertDialog), matching: find.byType(Scrollable))
            .first);
    await tester.runAsync(() async {
      await tester.tap(older);
      await tester.pump();
      await controls.lastPage;
    });
    await tester.pumpAndSettle();
    final first = find.byKey(ValueKey('metadata-saved-job-${ids.first}'));
    Future<void> select(Future<void> Function() activate) async {
      final joined = Completer<void>();
      var started = false;
      final remove = controls.addListener((state) {
        started |= state.busy;
        if (started && !state.busy && !joined.isCompleted) joined.complete();
      }, fireImmediately: false);
      try {
        await activate();
        await joined.future;
      } finally {
        remove();
      }
    }

    await tester.runAsync(() async {
      await select(() => tester.tap(first));
    });
    await tester.pumpAndSettle();
    expect(controls.state.report!.id, ids.first);
    expect(provider.calls, isEmpty);
    expect(
        (await tester.runAsync(() => db.query('metadata_refresh_jobs')))!
            .length,
        12);
    await tester.ensureVisible(open);
    await tester.runAsync(() async {
      await tester.tap(open);
      await tester.pump();
      await controls.lastPage;
    });
    await tester.pumpAndSettle();
    final newest = find.byKey(ValueKey('metadata-saved-job-${ids.last}'));
    final wrapper = find
        .ancestor(of: newest, matching: find.byType(ConsoleFocusable))
        .first;
    final focus =
        find.descendant(of: wrapper, matching: find.byType(Focus)).first;
    tester.widget<Focus>(focus).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await select(() => tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA));
    });
    await tester.pumpAndSettle();
    expect(controls.state.report!.id, ids.last);
    expect(provider.calls, isEmpty);
    await tester.runAsync(() async {
      await tester.tap(open);
      await tester.pump();
      await controls.lastPage;
    });
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(open, findsOneWidget,
        reason: 'Back closes the job picker before its scraping workspace');
    await tester.tap(find.byKey(const ValueKey('metadata-nav-storage')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('metadata-shared-storage')), findsOneWidget);
    expect(find.byKey(const ValueKey('metadata-saved-jobs')), findsNothing);
    expect(find.text('Media cache · 2 GB'), findsOneWidget);
    final larger = find.byKey(const ValueKey('metadata-cloud-larger'));
    await tester.ensureVisible(larger);
    await tester.pumpAndSettle();
    final cacheControl = find
        .ancestor(of: larger, matching: find.byType(ConsoleFocusable))
        .first;
    tester
        .widget<Focus>(find
            .descendant(of: cacheControl, matching: find.byType(Focus))
            .first)
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    });
    await tester.pumpAndSettle();
    expect(find.text('Media cache · 4 GB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('metadata-nav-screenscraper')));
    await tester.pumpAndSettle();
    await tester.tap(scraping);
    await tester.pumpAndSettle();
    expect(controls.state.report!.id, ids.last);
    expect(provider.calls, isEmpty,
        reason: 'Section navigation cannot recreate or run a saved job');
    final signals = (await tester.runAsync(() async => (
          Completer<void>(),
          Completer<MetadataLookupResult>(),
          Completer<void>(),
        )))!;
    final entered = signals.$1;
    final release = signals.$2;
    provider.reply = (_, __) {
      if (!entered.isCompleted) entered.complete();
      return release.future;
    };
    final finished = signals.$3;
    final removeRunListener = controls.addListener((state) {
      if (entered.isCompleted && !state.busy && !finished.isCompleted) {
        finished.complete();
      }
    }, fireImmediately: false);
    addTearDown(removeRunListener);
    final resumeWrapper = find
        .ancestor(
            of: find.byKey(const ValueKey('metadata-resume')),
            matching: find.byType(ConsoleFocusable))
        .first;
    tester
        .widget<Focus>(find
            .descendant(of: resumeWrapper, matching: find.byType(Focus))
            .first)
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await entered.future;
    });
    await tester.pump();
    final runningId = controls.state.report!.id;
    await tester.tap(find.byKey(const ValueKey('metadata-nav-storage')));
    await tester.pump();
    expect(controls.state.busy, isTrue);
    expect(provider.calls.length, 1);
    await tester.tap(find.byKey(const ValueKey('metadata-nav-screenscraper')));
    await tester.pump();
    await tester.tap(scraping);
    await tester.pump();
    expect(find.byKey(const ValueKey('metadata-pause')), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('metadata-pause')))
            .onPressed,
        isNotNull);
    for (final key in [
      'metadata-refresh',
      'metadata-resume',
      'metadata-retry'
    ]) {
      expect(tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
          reason: 'Running work must keep other transport actions disabled');
    }
    expect(controls.state.report!.id, runningId);
    expect(controls.state.busy, isTrue);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('metadata-nav-igdb')))
            .onPressed,
        isNull);
    release.complete(MetadataLookupResult(
        status: MetadataLookupStatus.unmatched, message: 'Fixture'));
    await tester.runAsync(() => finished.future);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unavailable shared storage has an actionable reconnect message',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(controlsDatabase))!;
    SharedPreferences.setMockInitialValues({
      sharedMetadataDirectoryKey: '/storage/fixture/RShopMetadata',
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final provider = ControlsProvider();
    final secrets = MemorySecrets();
    final controls = (await tester.runAsync(() async {
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: secrets),
          igdbCredentials: IgdbCredentialStore(storage: secrets),
          sharedStore: () async {
            throw const FileSystemException('Selected storage is unavailable');
          }(),
          catalogueChanged: () {});
      await controls.load();
      return controls;
    }))!;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    addTearDown(() async {
      await tester.runAsync(() async {
        await controls.close();
        await db.close();
      });
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: const MetadataSettingsScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-nav-storage')));
    await tester.pumpAndSettle();
    final message = find.textContaining(
        'Your shared game-information folder could not be opened');
    await tester.ensureVisible(message);
    await tester.pumpAndSettle();
    expect(message, findsOneWidget);
    expect(find.textContaining('Saved information is still usable'),
        findsOneWidget);
    final choose = find.byKey(const ValueKey('metadata-shared-storage'));
    await tester.ensureVisible(choose);
    await tester.pumpAndSettle();
    expect(choose.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(choose).onPressed, isNotNull);
    expect(provider.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('primary button labels retain contrast in enabled interaction states',
      () {
    final style = AppTheme.primaryButtonStyle;
    for (final states in <Set<WidgetState>>[
      {},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ]) {
      final foreground = style.foregroundColor!.resolve(states)!;
      final background = style.backgroundColor!.resolve(states)!;
      final overlay = style.overlayColor!.resolve(states) ?? Colors.transparent;
      final painted = Color.alphaBlend(overlay, background);
      expect(foreground, Colors.white);
      expect(
          (foreground.computeLuminance() + 0.05) /
              (painted.computeLuminance() + 0.05),
          greaterThanOrEqualTo(4.5));
    }
    // Null disabled overrides preserve each screen's existing theme defaults.
    expect(style.foregroundColor!.resolve({WidgetState.disabled}), isNull);
    expect(style.backgroundColor!.resolve({WidgetState.disabled}), isNull);
    expect(AppTheme.primaryColor, Colors.redAccent);
  });

  testWidgets(
      'General settings opens metadata setup and fresh local-catalogue refresh',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = await controlsDatabase();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final secrets = MemorySecrets();
    final ss = ScreenScraperCredentialStore(storage: secrets);
    final provider = ControlsProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {
          'screenscraper': provider,
          'igdb': ControlsProvider('igdb')
        },
        screenScraperCredentials: ss,
        igdbCredentials: IgdbCredentialStore(storage: secrets),
        catalogueChanged: () {});
    await controls.load();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    final focus = FocusNode();
    addTearDown(() async {
      await controls.close();
      container.dispose();
      focus.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(SettingsGeneralTab(firstFocusNode: focus))));
    await tester.pumpAndSettle();
    expect(find.text('Game metadata'), findsOneWidget);
    // ROM cache precedes metadata now; activate the metadata tile, not whichever
    // setting happens to occupy the first row.
    tester
        .widget<ConsoleFocusable>(find.ancestor(
            of: find.text('Game metadata'),
            matching: find.byType(ConsoleFocusable)))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(provider.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('metadata-credentials')));
    await tester.pumpAndSettle();
    final enabledSave = find.byKey(const ValueKey('metadata-save'));
    final saveMaterial = tester.widget<Material>(
        find.descendant(of: enabledSave, matching: find.byType(Material)));
    final saveLabel = tester
        .element(find.descendant(of: enabledSave, matching: find.byType(Text)));
    expect(saveMaterial.color, const Color(0xFFC62828));
    expect(DefaultTextStyle.of(saveLabel).style.color, Colors.white);
    final contrast = (Colors.white.computeLuminance() + 0.05) /
        (saveMaterial.color!.computeLuminance() + 0.05);
    expect(contrast, greaterThanOrEqualTo(4.5));
    final forget = find.byKey(const ValueKey('metadata-forget'));
    expect(tester.widget<FilledButton>(forget).onPressed, isNull);
    final forgetLabel = tester
        .element(find.descendant(of: forget, matching: find.byType(Text)));
    expect(
        DefaultTextStyle.of(forgetLabel).style.color!.toARGB32(),
        Theme.of(forgetLabel)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.38)
            .toARGB32());
    await tester.ensureVisible(find.byKey(const ValueKey('metadata-save')));
    await tester.tap(find.byKey(const ValueKey('metadata-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Complete all required fields'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('metadata-username')), 'fixture-user');
    await tester.enterText(
        find.byKey(const ValueKey('metadata-password')), 'fixture-secret');
    final save = find.byKey(const ValueKey('metadata-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await ss.readUser())!.username, 'fixture-user');
    expect(find.text('fixture-secret'), findsNothing);
    expect(provider.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    // Secrets are never displayed when reopening the editor; cancel discards
    // replacement input rather than changing the saved pair.
    await tester.tap(find.byKey(const ValueKey('metadata-credentials')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('metadata-password')))
            .controller!
            .text,
        '');
    await tester.enterText(
        find.byKey(const ValueKey('metadata-password')), 'discard-this');
    await tester.tap(find.byKey(const ValueKey('metadata-credentials-cancel')));
    await tester.pumpAndSettle();
    expect((await ss.readUser())!.password, 'fixture-secret');
    await tester.tap(find.byKey(const ValueKey('metadata-open-scraping')));
    await tester.pumpAndSettle();
    final refresh = find.byKey(const ValueKey('metadata-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await controls.pause();
    await tester.pumpAndSettle();
    // If pause won the lookup boundary, resume the same job to completion.
    if (controls.state.report!.state != 'completed') {
      await controls.resume();
      await tester.pumpAndSettle();
    }
    expect(controls.state.report!.state, 'completed');
    expect(controls.state.report!.counts, {'unmatched': 2});
    expect(find.textContaining('does not mean every game'), findsOneWidget);
    expect(tester.takeException(), isNull);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('metadata-credentials')), findsOneWidget);
    expect(find.byKey(const ValueKey('metadata-refresh')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MetadataSettingsScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'metadata form and committed coverage preserve dark layout geometry',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // SQLite's asynchronous lock/future ownership must stay in the real zone
    // when its complete operation is awaited through runAsync below.
    final db = (await tester.runAsync(controlsDatabase))!;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final secrets = MemorySecrets();
    final controls = (await tester.runAsync(() async {
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {
            'screenscraper': ControlsProvider(),
            'igdb': ControlsProvider('igdb'),
          },
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: secrets),
          igdbCredentials: IgdbCredentialStore(storage: secrets),
          catalogueChanged: () {});
      await controls.load();
      return controls;
    }))!;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: const MetadataSettingsScreen())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MetadataSettingsScreen),
        matchesGoldenFile('goldens/metadata_settings_setup.png'));
    await tester.tap(find.byKey(const ValueKey('metadata-open-scraping')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => controls.refresh());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('does not mean every game'));
    await tester.runAsync(() => precacheImage(
        ResizeImage(AssetImage(mediaFallbackAsset('psp')), width: 256),
        tester.element(find.byType(MetadataSettingsScreen))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MetadataSettingsScreen),
        matchesGoldenFile('goldens/metadata_settings_progress.png'));
    await tester.tap(find.byKey(const ValueKey('metadata-nav-storage')));
    await tester.pumpAndSettle();
    expect(find.text('No folder selected — saved inside G-Shop only'),
        findsOneWidget);
    final choose = find.byKey(const ValueKey('metadata-shared-storage'));
    await tester.ensureVisible(choose);
    await tester.pumpAndSettle();
    expect(choose.hitTestable(), findsOneWidget);
    expect(
        find.textContaining(
            'Account details and downloaded-game records are not backed up'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('metadata-nav-esde')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Close ES-DE and keep it closed'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('metadata-esde-map')))
            .onPressed,
        isNull,
        reason: 'Global settings cannot guess an edition association');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('metadata-esde-review-artwork')))
            .onPressed,
        isNull,
        reason: 'Artwork review requires the exact open edition');
    final closed = find.byKey(const ValueKey('metadata-esde-closed'));
    await tester.ensureVisible(closed);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(closed).value, false);
    final publish = find.byKey(const ValueKey('metadata-esde-publish'));
    expect(tester.widget<FilledButton>(publish).onPressed, isNull);
    // A narrow/portrait layout keeps the left navigation and lets content
    // scroll independently, including long translated labels and text scaling.
    tester.view.physicalSize = const Size(480, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-nav-screenscraper')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('metadata-navigation')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('metadata-credentials')).hitTestable(),
        findsOneWidget);
    await expectLater(find.byType(MetadataSettingsScreen),
        matchesGoldenFile('goldens/metadata_settings_compact.png'));
    await tester.runAsync(() async {
      final loaded = Completer<void>();
      final remove = controls.addListener((state) {
        if (state.providerId == 'igdb' && !state.loading) loaded.complete();
      }, fireImmediately: false);
      try {
        final current = find
            .ancestor(
                of: find.byKey(const ValueKey('metadata-nav-screenscraper')),
                matching: find.byType(ConsoleFocusable))
            .first;
        tester
            .widget<Focus>(find
                .descendant(of: current, matching: find.byType(Focus))
                .first)
            .focusNode!
            .requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        expect(controls.state.providerId, 'igdb',
            reason: 'One Down moves to the next section, not an inner button');
        await loaded.future;
      } finally {
        remove();
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-credentials')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('metadata-username')), findsNothing);
    expect(
        find.byKey(const ValueKey('metadata-client-secret')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('metadata-navigation')), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final esDeNavigation = find.byKey(const ValueKey('metadata-nav-esde'));
    await tester.ensureVisible(esDeNavigation);
    await tester.tap(esDeNavigation);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('metadata-esde-section')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await controls.close();
    container.dispose();
    await db.close();
  });
}
