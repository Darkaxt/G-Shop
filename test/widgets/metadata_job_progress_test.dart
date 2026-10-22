import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/settings/metadata_job_progress.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';

void main() {
  MetadataRefreshReport report(Map<String, int> counts,
          {String state = 'running', String kind = 'metadata'}) =>
      MetadataRefreshReport(
          id: 109,
          generation: 109,
          collectionGeneration: 'fixture',
          state: state,
          kind: kind,
          requested:
              9000, // API calls are deliberately unrelated to item totals.
          rated: 0,
          counts: counts);

  Widget screen(MetadataRefreshReport report,
          {Locale locale = const Locale('en')}) =>
      MaterialApp(
          locale: locale,
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: Scaffold(body: MetadataJobProgress(report: report)));

  testWidgets(
      'committed outcomes determine progress, including review and failure',
      (tester) async {
    await tester.pumpWidget(screen(report(const {
      'pending': 70,
      'matched': 10,
      'needsReview': 10,
      'unmatched': 5,
      'ambiguous': 3,
      'invalidResponse': 2,
    })));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .3);
    expect(find.textContaining('30 / 100 processed · 30% · 70 pending'),
        findsOneWidget);
    expect(find.textContaining('9000'), findsNothing);
    await tester
        .pumpWidget(screen(report(const {'matched': 40, 'pending': 60})));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .4);
    expect(find.textContaining('40 / 100 processed · 40% · 60 pending'),
        findsOneWidget);
  });

  testWidgets('paused and completed reports retain measured remaining work',
      (tester) async {
    for (final state in ['queued', 'running', 'paused', 'completed']) {
      await tester.pumpWidget(
          screen(report(const {'matched': 9998, 'pending': 1}, state: state)));
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(9998 / 9999, .000001));
      expect(bar.semanticsLabel, contains('99.9%'));
      expect(bar.semanticsLabel, contains('1 pending'));
      expect(find.textContaining('100%'), findsNothing);
    }
    await tester.pumpWidget(
        screen(report(const {'unmatched': 100}, state: 'completed')));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        1);
    expect(find.textContaining('100 / 100 processed · 100% · 0 pending'),
        findsOneWidget);
  });

  testWidgets('artwork uses its own snapshot and empty work is explicit',
      (tester) async {
    await tester.pumpWidget(
        screen(report(const {'matched': 3, 'pending': 9}, kind: 'artwork')));
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, .25);
    expect(bar.semanticsLabel, startsWith('Artwork ·'));
    expect(find.textContaining('3 / 12 processed · 25% · 9 pending'),
        findsOneWidget);
    await tester.pumpWidget(screen(report(const {}, state: 'completed')));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0);
    expect(find.textContaining('No items in this job'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
  });

  testWidgets('localized progress wraps in a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen(report(const {'matched': 1, 'pending': 7}),
        locale: const Locale('de')));
    await tester.pumpAndSettle();
    expect(find.textContaining('12,5%'), findsOneWidget);
    expect(find.textContaining('7 ausstehend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
