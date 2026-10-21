import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/features/settings/metadata_settings_screen.dart';
import 'package:g_shop/features/settings/metadata_progress_feedback.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/widgets/media_cover_fallback.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/storage_service.dart';
import '../metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;

void main() {
  MetadataRefreshReport report(String title,
          {int id = 1,
          String provider = 'screenscraper',
          String state = 'running',
          List<MetadataText> descriptions = const [],
          MetadataQuotaObservation? quota,
          bool image = false}) =>
      MetadataRefreshReport(
          id: id,
          generation: id,
          collectionGeneration: 'fixture',
          state: state,
          requested: 1,
          rated: 0,
          counts: const {'needsReview': 1},
          providerId: provider,
          quotaObservation: quota,
          lastProcessed: MetadataProcessedGame(
              jobId: id,
              providerId: provider,
              editionId: 'edition-$id',
              title: title,
              platformId: 'n64',
              status: MetadataLookupStatus.needsReview,
              previewDescriptions: descriptions,
              coverBytes: image
                  ? base64Decode(
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==')
                  : null));

  Widget panel(MetadataRefreshReport report) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Scaffold(body: MetadataProgressFeedback(report: report)));

  testWidgets(
      'preview coalesces on three-second display cadence and clears across jobs/providers',
      (tester) async {
    await tester.pumpWidget(panel(report('First')));
    await tester.pumpWidget(panel(report('Skipped')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(panel(report('Latest', image: true)));
    expect(find.text('First'), findsNWidgets(2));
    expect(find.text('Skipped'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Latest'), findsOneWidget);
    expect(find.byType(MediaCoverFallback), findsNothing);
    await tester
        .pumpWidget(panel(report('Other provider', id: 2, provider: 'igdb')));
    expect(find.text('Latest'), findsNothing);
    expect(find.text('Other provider'), findsNWidgets(2));
    expect(find.textContaining('Daily API quota'), findsNothing);
    expect(find.byType(MediaCoverFallback), findsOneWidget);
    await tester.pumpWidget(panel(
        report('Completed', id: 2, provider: 'igdb', state: 'completed')));
    expect(find.text('Completed'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing daily counters are unknown; exhausted and old reports stay explicit',
      (tester) async {
    await tester.pumpWidget(panel(report('Unknown', state: 'completed')));
    expect(find.textContaining('Unknown / Unknown'), findsOneWidget);
    expect(find.textContaining('unlimited'), findsNothing);
    await tester.pumpWidget(panel(report('Exhausted',
        state: 'completed',
        quota: MetadataQuotaObservation(
            const MetadataQuota(maxRequestsPerDay: 10000, requestsToday: 10000),
            DateTime.utc(2026, 10, 1),
            reservedRemaining: 0))));
    expect(find.textContaining('0 / 10000'), findsOneWidget);
    expect(find.textContaining('October 1, 2026'), findsOneWidget);
    expect(find.textContaining('Lookups available after queued requests: 0'),
        findsOneWidget);
    await tester.pumpWidget(panel(report('Partial',
        state: 'completed',
        quota: MetadataQuotaObservation(
            const MetadataQuota(maxRequestsPerDay: 10000),
            DateTime.utc(2026, 10, 6)))));
    expect(find.textContaining('Unknown / 10000'), findsOneWidget);
    expect(
        find.textContaining('Reported attempts used: Unknown'), findsOneWidget);
  });
  testWidgets(
      'normal scrape feedback shows latest candidate and reported quota',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final db = (await tester.runAsync(controlsDatabase))!;
    final provider = ControlsProvider();
    provider.reply = (request, _) async => MetadataLookupResult(
            status: MetadataLookupStatus.needsReview,
            message: 'Candidate only',
            quota: const MetadataQuota(
                maxRequestsPerDay: 10000,
                requestsToday: 75,
                maxUnmatchedPerDay: 1000,
                unmatchedToday: 4),
            candidates: [
              MetadataLookupCandidate(
                  providerGameId: '42',
                  platformId: request.platformId,
                  titles: const [MetadataText(text: 'Candidate title')],
                  titleMatched: true,
                  evidence: 'platformAndTitle',
                  previewDescriptions: const [
                    MetadataText(text: 'Description francaise', language: 'fr'),
                    MetadataText(
                        text: 'Already fetched synopsis', language: 'en'),
                  ])
            ]);
    final secrets = MemorySecrets();
    final controls = (await tester.runAsync(() async {
      final controller = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: secrets),
          igdbCredentials: IgdbCredentialStore(storage: secrets),
          catalogueChanged: () {});
      await controller.load();
      await controller.refresh(cacheRowId: 1);
      return controller;
    }))!;
    final storage = StorageService();
    await storage.init();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    addTearDown(() async {
      container.dispose();
      await controls.close();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: const MetadataSettingsScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-open-scraping')));
    await tester.pumpAndSettle();
    final feedback = find.byKey(const ValueKey('metadata-progress-feedback'));
    expect(feedback, findsOneWidget);
    await tester.ensureVisible(feedback);
    await tester.pumpAndSettle();
    expect(find.text('Game 1'), findsOneWidget);
    expect(find.text('Candidate title'), findsOneWidget);
    expect(find.text('Already fetched synopsis'), findsOneWidget);
    expect(find.text('Description francaise'), findsNothing);
    expect(find.text('Possible match · needs confirmation'), findsOneWidget);
    expect(find.textContaining('9925 / 10000'), findsOneWidget);
    expect(find.textContaining('996 / 1000'), findsOneWidget);
    expect(controls.state.report!.rated, 0);
    expect(provider.calls, hasLength(1),
        reason: 'display makes no game lookups');
    expect(await db.query('library_metadata'), isEmpty,
        reason: 'candidate descriptions are preview-only, not publication');
    await tester.runAsync(() => controls.refresh(cacheRowId: 2));
    await tester.pumpAndSettle();
    expect(find.text('Game 2'), findsOneWidget);
    expect(find.text('Game 1'), findsNothing);
    expect(find.text('Already fetched synopsis'), findsOneWidget);
    expect(provider.calls, hasLength(2));
    expect(controls.state.report!.rated, 0);
    provider.reply = (request, _) async => MetadataLookupResult(
            status: MetadataLookupStatus.ambiguous,
            message: 'Do not select among candidates',
            candidates: [
              for (final id in ['42', '43'])
                MetadataLookupCandidate(
                    providerGameId: id,
                    platformId: request.platformId,
                    titles: const [MetadataText(text: 'Candidate title')],
                    titleMatched: true,
                    evidence: 'platformAndTitle',
                    previewDescriptions: const [
                      MetadataText(text: 'Ambiguous synopsis')
                    ])
            ]);
    await tester.runAsync(() => controls.refresh(cacheRowId: 1));
    await tester.pumpAndSettle();
    expect(find.text('Already fetched synopsis'), findsNothing);
    expect(find.text('Ambiguous synopsis'), findsNothing);
    expect(provider.calls, hasLength(3));
    provider.reply = (request, _) async => MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Matched fixture',
        record: MetadataRecord(
            gameId: request.gameId,
            editionId: request.editionId,
            platformId: request.platformId,
            providerId: provider.providerId,
            providerGameId: '42',
            retrievedAt: DateTime.utc(2026, 10, 6),
            refreshGeneration: request.refreshGeneration,
            matchMethod: 'verifiedProviderId',
            titles: [MetadataText(text: request.title)],
            descriptions: const [MetadataText(text: 'Accepted synopsis')]));
    await tester.runAsync(() => controls.refresh(cacheRowId: 2));
    await tester.pumpAndSettle();
    expect(find.text('Accepted synopsis'), findsOneWidget);
    expect(find.text('Possible match · needs confirmation'), findsNothing);
    expect(provider.calls, hasLength(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  test('candidate description payload is bounded and immutable', () {
    final candidate = MetadataLookupCandidate(
        providerGameId: '1',
        platformId: 'psx',
        titles: const [],
        titleMatched: false,
        evidence: 'providerTitleCandidate',
        previewDescriptions: [
          for (var i = 0; i < 20; i++)
            MetadataText(text: 'x' * 10000, language: 'en')
        ]);
    expect(candidate.previewDescriptions, hasLength(8));
    expect(candidate.previewDescriptions.every((v) => v.text.length == 4096),
        isTrue);
    expect(() => candidate.previewDescriptions.clear(), throwsUnsupportedError);
  });

  testWidgets('preview decodes provider entities once as plain text',
      (tester) async {
    await tester.pumpWidget(
        panel(report('Encoded', state: 'completed', descriptions: const [
      MetadataText(
          text: 'Pilot &quot;UPEO&quot; &amp; <literal> &#233; &amp;quot;',
          language: 'en')
    ])));
    expect(find.text('Pilot "UPEO" & <literal> é &quot;'), findsOneWidget);
  });
}
