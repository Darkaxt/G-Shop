import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/services/feedback_service.dart';
import 'package:g_shop/widgets/quick_menu.dart';
import 'package:g_shop/l10n/app_localizations.dart';

class _Feedback implements FeedbackService {
  @override
  void tick() {}
  @override
  void confirm() {}
  @override
  void cancel() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Sync and Scrape submenus support controller back and touch',
      (tester) async {
    final selected = <String>[];
    var closed = false;
    final container = ProviderContainer(overrides: [
      feedbackServiceProvider.overrideWithValue(_Feedback()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: Scaffold(
                body: Stack(children: [
              QuickMenuOverlay(items: [
                QuickMenuItem(label: 'Sync', icon: Icons.sync, children: [
                  QuickMenuItem(
                      label: 'Sync all',
                      icon: Icons.sync,
                      onSelect: () => selected.add('sync')),
                ]),
                QuickMenuItem(
                    label: 'Scrape',
                    icon: Icons.auto_stories,
                    children: [
                      QuickMenuItem(
                          label: 'Scrape all',
                          icon: Icons.auto_stories,
                          onSelect: () => selected.add('scrape')),
                    ]),
              ], onClose: () => closed = true),
            ])))));
    await tester.pumpAndSettle();
    expect(find.text('Scrape all'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Sync all'), findsOneWidget);
    expect(selected, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Scrape'), findsOneWidget);
    expect(closed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Scrape all'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrape all'));
    await tester.pumpAndSettle();
    expect(selected, ['scrape']);
    expect(closed, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
  for (final size in [
    const Size(960, 540),
    const Size(640, 360),
    const Size(540, 960)
  ]) {
    testWidgets('save menu remains reachable by touch and controller at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = <int>[];
      final container = ProviderContainer(overrides: [
        feedbackServiceProvider.overrideWithValue(_Feedback()),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(Duration.zero);
        container.dispose();
      });
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: Stack(children: [
          QuickMenuOverlay(items: [
            for (var i = 0; i < 12; i++) ...[
              if (i == 5) null,
              QuickMenuItem(
                  label: i == 0 ? 'Save backups' : 'Action $i',
                  subtitle: i == 1 ? 'A longer game action description' : null,
                  icon: Icons.backup_outlined,
                  onSelect: () => selected.add(i)),
            ]
          ], onClose: () {}),
        ]))),
      ));
      await tester.pumpAndSettle();
      final first = tester.getRect(find.text('Save backups'));
      expect(first.top, greaterThanOrEqualTo(0));
      expect(first.bottom, lessThan(size.height - 60));
      await tester.tap(find.text('Save backups'));
      await tester.pumpAndSettle();
      expect(selected, [0]);

      // Rebuild a fresh overlay after the selection closes its animation.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: Stack(children: [
          QuickMenuOverlay(items: [
            for (var i = 0; i < 12; i++) ...[
              if (i == 5) null,
              QuickMenuItem(
                  label: 'Action $i',
                  icon: Icons.backup_outlined,
                  onSelect: () => selected.add(i)),
            ]
          ], onClose: () {}),
        ]))),
      ));
      await tester.pumpAndSettle();
      for (var i = 0; i < 11; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      final last = tester.getRect(find.text('Action 11'));
      expect(last.top, greaterThanOrEqualTo(0));
      expect(last.bottom, lessThan(size.height - 60));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, [0, 11]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  }
}
