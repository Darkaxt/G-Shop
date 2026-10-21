import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/features/settings/metadata_settings_screen.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';

import '../metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;

void main() => defineMetadataMatchCorrectionChecks();

void defineMetadataMatchCorrectionChecks({
  DatabaseFactory? factory,
  Future<void> Function(String name, WidgetTester tester)? checkpoint,
}) {
  testWidgets('exact-game correction searches again before replacing old facts',
      (tester) async {
    final db = await controlsDatabase(factory: factory);
    final jobs = MetadataRefreshJobs(Future.value(db));
    await jobs.createFromCatalogue(providerId: 'screenscraper', cacheRowId: 1);
    final store = LibraryStore(Future.value(db));
    final id = (await db.transaction((txn) =>
            LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
        .single;
    final edition = (await store.edition(id))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '99'},
      'matchStatus': 'manuallyMatched'
    }));
    final old = MetadataRecord(
        gameId: game.id,
        editionId: id,
        platformId: 'psx',
        providerId: 'screenscraper',
        providerGameId: '99',
        retrievedAt: DateTime.utc(2026, 10, 4),
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Wrong old match')]);
    await store.putMetadata(old);
    final provider = ControlsProvider();
    provider.reply = (request, _) async =>
        request.verifiedProviderGameId == null
            ? MetadataLookupResult(
                status: MetadataLookupStatus.needsReview,
                message: 'Select explicitly',
                candidates: [
                    MetadataLookupCandidate(
                        providerGameId: '42',
                        platformId: request.platformId,
                        titles: const [MetadataText(text: 'Correct game')],
                        titleMatched: true,
                        evidence: 'platformAndTitle')
                  ])
            : MetadataLookupResult(
                status: MetadataLookupStatus.matched,
                message: 'Verified',
                record: MetadataRecord(
                    gameId: request.gameId,
                    editionId: request.editionId,
                    platformId: request.platformId,
                    providerId: 'screenscraper',
                    providerGameId: request.verifiedProviderGameId!,
                    retrievedAt: DateTime.utc(2026, 10, 4),
                    refreshGeneration: request.refreshGeneration,
                    matchMethod: 'verifiedProviderId',
                    titles: const [MetadataText(text: 'Correct game')]));
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    await controls.load();
    Future<void> completeAction(Future<void> Function() action) async {
      final previousId = controls.state.report?.id;
      final completed = Completer<void>();
      final remove = controls.addListener((state) {
        if (!state.busy &&
            state.report?.id != previousId &&
            state.report?.state == 'completed' &&
            !completed.isCompleted) {
          completed.complete();
        }
      });
      try {
        await action();
        await completed.future;
      } finally {
        remove();
      }
      await tester.pumpAndSettle();
    }

    final container = ProviderContainer(overrides: [
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    addTearDown(() async {
      await controls.close();
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: MetadataSettingsScreen(
                cacheRowId: 1, editionId: id, gameTitle: game.title))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-open-scraping')));
    await tester.pumpAndSettle();
    final discover = find.byKey(const ValueKey('metadata-rediscover'));
    expect(discover, findsOneWidget);
    await tester.ensureVisible(discover);
    await tester.pumpAndSettle();
    // Wait for the real completion event; pausing changes the UI workflow.
    await completeAction(() => tester.tap(discover));
    expect(provider.calls, hasLength(1));
    expect(provider.calls.single.verifiedProviderGameId, isNull);
    expect(provider.calls.single.baseProviderGameId, isNull);
    expect(provider.calls.single.romIdentifier, isNull);
    expect(provider.calls.single.editionId, id);
    expect((await store.game(game.id))!.providerIds['screenscraper'], '99');
    expect((await store.metadata(id, 'screenscraper'))!.toJson(), old.toJson());
    expect(find.text('Review possible matches'), findsOneWidget);
    await checkpoint?.call('match-correction-preserved', tester);
    final candidate = find.byKey(ValueKey('review-candidate-$id'));
    await tester.ensureVisible(candidate);
    await tester.pumpAndSettle();
    await tester.tap(candidate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct game · psx · #42').last);
    await tester.pumpAndSettle();
    final official = find.byKey(ValueKey('review-tag-$id-official'));
    await tester.ensureVisible(official);
    await tester.pumpAndSettle();
    await tester.tap(official);
    await tester.pumpAndSettle();
    final accept = find.byKey(ValueKey('review-accept-$id'));
    await tester.ensureVisible(accept);
    await tester.pumpAndSettle();
    tester
        .widget<Focus>(
            find.ancestor(of: accept, matching: find.byType(Focus)).first)
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    await completeAction(
        () => tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA));
    expect(controls.state.error, isFalse);
    expect((await store.game(game.id))!.providerIds['screenscraper'], '42');
    expect((await store.metadata(id, 'screenscraper'))!.providerGameId, '42');
    expect(await controls.reviewQueue(), isEmpty);
    await checkpoint?.call('match-correction-verified', tester);
    await controls.refresh(cacheRowId: 1);
    expect(provider.calls.last.verifiedProviderGameId, '42');
    expect((await store.metadata(id, 'screenscraper'))!.providerGameId, '42');
    await checkpoint?.call('match-correction-refreshed', tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
