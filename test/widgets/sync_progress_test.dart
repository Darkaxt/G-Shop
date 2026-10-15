import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/ra_providers.dart';
import 'package:retro_eshop/services/library_sync_service.dart';
import 'package:retro_eshop/widgets/sync_badge.dart';
import '../helpers/pump_helpers.dart';

class _Sync extends LibrarySyncService {
  void publish(LibrarySyncState value) => state = value;
  _Sync() {
    state = const LibrarySyncState(
        isSyncing: true, totalSystems: 40, currentSystem: 'Nintendo GameCube');
  }
}

void main() {
  for (final size in [const Size(320, 568), const Size(832, 468)]) {
    testWidgets('stacked progress fits $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sync = _Sync();
      await tester.pumpWidget(createTestAppWithProviders(
        const Stack(children: [SyncBadge()]),
        overrides: [
          librarySyncServiceProvider.overrideWith((ref) => sync),
          raEnabledProvider.overrideWithValue(false),
        ],
      ));
      sync.publish(sync.state.copyWith(phase: LibrarySyncPhase.updatingGames,
          processedGames: 0, currentGamesTotal: 0));
      await tester.pump();
      expect(find.text('Updating games · 0/0'), findsOneWidget);
      final bounds = tester.getRect(find.byKey(const ValueKey('console-game-progress')));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'game counts reset by console and unknown source totals stay honest',
      (tester) async {
    final sync = _Sync();
    await tester.pumpWidget(createTestAppWithProviders(
      const Stack(children: [SyncBadge()]),
      overrides: [
        librarySyncServiceProvider.overrideWith((ref) => sync),
        raEnabledProvider.overrideWithValue(false),
      ],
    ));
    sync.publish(sync.state.copyWith(
        phase: LibrarySyncPhase.updatingGames,
        processedGames: 100,
        currentGamesTotal: 250));
    await tester.pump();
    expect(find.text('Updating games · 100/250'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .4);
    sync.publish(sync.state.copyWith(
        currentSystem: 'Game Gear',
        resetGameProgress: true,
        phase: LibrarySyncPhase.checkingSource,
        sourceFilesRead: 27));
    await tester.pump();
    expect(find.text('Drive catalogue'), findsOneWidget);
    expect(find.text('Checking Drive · 27 files read'), findsOneWidget);
    expect(find.textContaining('100/250'), findsNothing);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        isNull);
    sync.publish(sync.state.copyWith(isSyncing: false));
    await tester.pump();
    expect(find.byKey(const ValueKey('console-game-progress')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('current console progress appears beneath console completion',
      (tester) async {
    await tester.pumpWidget(createTestAppWithProviders(
      const Stack(children: [SyncBadge()]),
      overrides: [
        librarySyncServiceProvider.overrideWith((ref) => _Sync()),
        raEnabledProvider.overrideWithValue(false),
      ],
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('console-game-progress')), findsOneWidget);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('console-game-progress')))
            .dy,
        greaterThan(tester
            .getBottomLeft(find.byKey(const ValueKey('library-syncing')))
            .dy));
    await tester.pumpWidget(const SizedBox());
  });
}
