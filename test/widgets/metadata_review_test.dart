import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/settings/metadata_settings_screen.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import '../metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[], popped = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }
}

void main() {
  for (final size in [
    const Size(1280, 720),
    const Size(480, 900),
    const Size(720, 1280)
  ]) {
    testWidgets('normal cached candidate review and independent tags at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = await controlsDatabase();
      final artifact = RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'fixture',
              providerFileId: 'disc2'),
          displayName: 'Game 1 (Japan) (Disc 2) [T-En].chd',
          displayPath: 'Translations/Game 1 (Japan) (Disc 2) [T-En].chd');
      await db.update(
          'games',
          {
            'artifact_key': artifact.id.key,
            'remote_artifact': jsonEncode(artifact.toJson()),
            'filename': artifact.displayName,
          },
          where: 'id = ?',
          whereArgs: [1]);
      final provider = ControlsProvider();
      provider.reply = (request, _) async => MetadataLookupResult(
              status: MetadataLookupStatus.needsReview,
              message: 'Review required',
              candidates: [
                MetadataLookupCandidate(
                    providerGameId: '42',
                    platformId: request.platformId,
                    titles: [MetadataText(text: 'Candidate ${request.title}')],
                    titleMatched: true,
                    evidence: 'platformAndTitle'),
                MetadataLookupCandidate(
                    providerGameId: 'wrong',
                    platformId: 'wrong-platform',
                    titles: const [MetadataText(text: 'Wrong platform')],
                    titleMatched: true,
                    evidence: 'titleOnly')
              ]);
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          catalogueChanged: () {});
      await controls.load();
      await controls.refresh();
      final reviews = await controls.reviewQueue();
      final selected = reviews.singleWhere((r) => r.request!.title == 'Game 1');
      final exactScope = size.width == 720;
      final container = ProviderContainer(overrides: [
        metadataControlsProvider.overrideWith((_) => controls),
      ]);
      addTearDown(() async {
        await controls.close();
        container.dispose();
        await db.close();
      });
      final routes = _Routes();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              localizationsDelegates: L.localizationsDelegates,
              supportedLocales: L.supportedLocales,
              navigatorObservers: [routes],
              home: Scaffold(
                  body: MetadataSettingsScreen(
                      cacheRowId: exactScope ? 1 : null,
                      gameTitle: exactScope ? 'Game 1' : null)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('metadata-open-scraping')));
      await tester.pumpAndSettle();
      final open = find.byKey(const ValueKey('metadata-open-review'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('Review possible matches'), findsOneWidget);
      expect(find.text(artifact.displayPath), findsOneWidget,
          reason: 'Review must expose the actual folder, disc and patch label, '
              'not just the cleaned title.');
      expect(
          find.text('Game 2.chd'), exactScope ? findsNothing : findsOneWidget);
      expect(provider.calls, hasLength(2));
      expect(find.text('Game 2'), exactScope ? findsNothing : findsOneWidget);
      expect(routes.pushed, hasLength(2),
          reason: 'Home plus one review route.');
      final approve =
          find.byKey(ValueKey('review-accept-${selected.editionId}'));
      await tester.ensureVisible(approve);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      final candidate =
          find.byKey(ValueKey('review-candidate-${selected.editionId}'));
      await tester.ensureVisible(candidate);
      await tester.pumpAndSettle();
      await tester.tap(candidate);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<DropdownMenuItem<int>>(find.ancestor(
                  of: find
                      .text('Wrong platform · wrong-platform · #wrong')
                      .last,
                  matching: find.byType(DropdownMenuItem<int>)))
              .enabled,
          isFalse);
      await tester.tap(find.text('Candidate Game 1 · psx · #42').last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(approve).onPressed, isNull,
          reason: 'Selecting an ID must not guess that a release is official.');
      final region =
          find.byKey(ValueKey('review-region-${selected.editionId}'));
      await tester.ensureVisible(region);
      await tester.pumpAndSettle();
      await tester.enterText(region, 'Japan');
      await tester.pumpAndSettle();
      for (final tag in ['T-Eng', 'Undub', 'Uncensor']) {
        final chip =
            find.byKey(ValueKey('review-tag-${selected.editionId}-$tag'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      provider.reply = (request, _) async => MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          message: 'Verified',
          record: MetadataRecord(
              gameId: request.gameId,
              editionId: request.editionId,
              platformId: request.platformId,
              providerId: 'screenscraper',
              providerGameId: request.verifiedProviderGameId!,
              retrievedAt: DateTime.now().toUtc(),
              refreshGeneration: request.refreshGeneration,
              matchMethod: 'verifiedProviderId',
              titles: [MetadataText(text: request.title)]));
      await tester.ensureVisible(approve);
      await tester.pumpAndSettle();
      if (size.width > 1000) {
        tester
            .widget<Focus>(
                find.ancestor(of: approve, matching: find.byType(Focus)).first)
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      } else {
        await tester.tap(approve);
      }
      await controls
          .pause(); // Join the button's owning operation without sleeps.
      if (controls.state.report!.state != 'completed') await controls.resume();
      await tester.pumpAndSettle();
      expect(controls.state.report!.counts, {'matched': 1});
      expect(find.byKey(ValueKey('review-candidate-${selected.editionId}')),
          findsNothing);
      expect(find.text('Game 2'), exactScope ? findsNothing : findsOneWidget,
          reason:
              'The exact-game scope must not broaden after a one-game retry.');
      expect(await controls.reviewQueue(), hasLength(1),
          reason: 'Other unresolved games remain cached outside exact scope.');
      final edition =
          await LibraryStore(Future.value(db)).edition(selected.editionId);
      expect(edition!.tags, {'T-Eng', 'Undub', 'Uncensor'});
      expect(edition.regions, ['Japan']);
      expect(provider.calls.last.region, 'Japan');
      expect(
          edition.evidence.any((e) =>
              e.source == 'manual' &&
              e.kind == 'releaseRegion' &&
              e.value == 'Japan'),
          isTrue);
      expect(tester.takeException(), isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      final poppedScreens =
          routes.popped.whereType<MaterialPageRoute<dynamic>>();
      expect(poppedScreens, hasLength(1),
          reason: 'Back must pop exactly one review screen.');
      expect(poppedScreens.single, same(routes.pushed[1]));
      expect(find.byType(MetadataSettingsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
