import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/core/input/console_screen_mixin.dart';
import 'package:retro_eshop/core/input/searchable_screen_mixin.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/feedback_service.dart';
import 'package:retro_eshop/widgets/quick_menu.dart';

class _SilentFeedback implements FeedbackService {
  @override
  void tick() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchScreen extends ConsumerStatefulWidget {
  const _SearchScreen({super.key});
  @override
  ConsumerState<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<_SearchScreen>
    with ConsoleScreenMixin, SearchableScreenMixin {
  @override
  String get routeId => 'synthetic-search';
  @override
  Color get searchAccentColor => Colors.cyan;
  @override
  String get searchHintText => 'Search';
  @override
  void onSearchQueryChanged(String query) {}
  @override
  void onSearchReset() {}
  @override
  void onSearchSelectionReset() {}
  Future<void> openDetail() async {
    searchFieldNode.unfocus();
    suspendSearchOverlay();
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const _DetailScreen()));
    if (mounted) resumeSearchOverlay();
  }

  @override
  void initState() {
    super.initState();
    initSearch();
  }

  @override
  void dispose() {
    disposeSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildWithActions(Scaffold(
        body: Stack(children: [
          const Text('Collection'),
          if (isSearchActive) buildSearchWidget(searchQuery: ''),
        ]),
      ));
}

class _DetailScreen extends ConsumerStatefulWidget {
  const _DetailScreen();
  @override
  ConsumerState<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<_DetailScreen>
    with ConsoleScreenMixin {
  @override
  String get routeId => 'synthetic-detail';
  @override
  Widget build(BuildContext context) => buildWithActions(Scaffold(
        body: Stack(children: [
          TextButton(onPressed: toggleQuickMenu, child: const Text('Menu')),
          if (showQuickMenu)
            QuickMenuOverlay(items: [
              QuickMenuItem(
                  label: 'Open owned ROM',
                  icon: Icons.play_arrow,
                  onSelect: () {}),
            ], onClose: closeQuickMenu),
        ]),
      ));
}

void main() {
  Future<({ProviderContainer container, _SearchScreenState screen})> open(
      WidgetTester tester) async {
    final key = GlobalKey<_SearchScreenState>();
    final container = ProviderContainer(overrides: [
      feedbackServiceProvider.overrideWithValue(_SilentFeedback()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: _SearchScreen(key: key))));
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      container.dispose();
    });
    return (container: container, screen: key.currentState!);
  }

  testWidgets('settled search suspends for detail and releases after return',
      (tester) async {
    final fixture = await open(tester);
    final screen = fixture.screen;
    screen.openSearch();
    await tester.pump();
    expect(fixture.container.read(overlayPriorityProvider),
        OverlayPriority.search);
    screen.suspendSearchOverlay();
    await tester.pump();
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    screen.resumeSearchOverlay();
    await tester.pump();
    expect(fixture.container.read(overlayPriorityProvider),
        OverlayPriority.search);
    screen.closeSearch();
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    screen.toggleQuickMenu();
    expect(screen.showQuickMenu, isTrue);
  });

  testWidgets('pending search widget cannot reclaim priority after suspension',
      (tester) async {
    final fixture = await open(tester);
    fixture.screen.openSearch();
    // Navigation can suspend before the widget's next-frame claim exists.
    // The real mixin and widget must agree that the hidden search owns no input.
    fixture.screen.suspendSearchOverlay();
    await tester.pump();
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    expect(fixture.screen.searchFieldNode.hasFocus, isFalse);
    fixture.screen.resumeSearchOverlay();
    await tester.pump();
    fixture.screen.closeSearch();
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    fixture.screen.toggleQuickMenu();
    expect(fixture.screen.showQuickMenu, isTrue);
  });

  testWidgets('search-to-detail route opens the real quick menu and returns',
      (tester) async {
    final fixture = await open(tester);
    fixture.screen.openSearch();
    final navigation = fixture.screen.openDetail();
    await tester.pumpAndSettle();
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Open owned ROM'), findsOneWidget);
    // Close via the actual overlay's backdrop outside its menu panel.
    await tester.tapAt(const Offset(10, 150));
    await tester.pumpAndSettle();
    expect(find.byType(QuickMenuOverlay), findsNothing);
    Navigator.of(tester.element(find.text('Menu'))).pop();
    await tester.pumpAndSettle();
    await navigation;
    expect(fixture.container.read(overlayPriorityProvider),
        OverlayPriority.search);
    fixture.screen.closeSearch();
    await tester.pumpAndSettle();
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
  });

  testWidgets('nested suspension waits for the final matching resume',
      (tester) async {
    final fixture = await open(tester);
    fixture.screen.openSearch();
    await tester.pump();
    fixture.screen.suspendSearchOverlay();
    fixture.screen.suspendSearchOverlay();
    fixture.screen.resumeSearchOverlay();
    await tester.pump();
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    fixture.screen.resumeSearchOverlay();
    await tester.pump();
    expect(fixture.container.read(overlayPriorityProvider),
        OverlayPriority.search);
    fixture.screen.closeSearch();
    await tester.pump();
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
  });

  testWidgets('hidden collection refresh cannot steal the visible route focus',
      (tester) async {
    final fixture = await open(tester);
    fixture.screen.openSearch();
    final navigation = fixture.screen.openDetail();
    await tester.pumpAndSettle();
    final detail = tester.state<_DetailScreenState>(find.byType(_DetailScreen));
    expect(detail.screenFocusNode.hasFocus, isTrue);
    // A late catalogue/install refresh calls this on the still-mounted Library.
    fixture.screen.requestScreenFocus();
    await tester.pump();
    expect(detail.screenFocusNode.hasFocus, isTrue);
    expect(fixture.screen.screenFocusNode.hasFocus, isFalse);
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
    Navigator.of(tester.element(find.text('Menu'))).pop();
    await tester.pumpAndSettle();
    await navigation;
    fixture.screen.closeSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('closing a suspended search never releases another claim',
      (tester) async {
    final fixture = await open(tester);
    fixture.screen.openSearch();
    await tester.pump();
    fixture.screen.suspendSearchOverlay();
    final manager = fixture.container.read(overlayPriorityProvider.notifier);
    final otherSearch = manager.claim(OverlayPriority.search);
    fixture.screen.closeSearch();
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(fixture.container.read(overlayPriorityProvider),
        OverlayPriority.search);
    expect(manager.release(otherSearch), isTrue);
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
  });

  testWidgets('disposing an open search releases only its own exact claim',
      (tester) async {
    final fixture = await open(tester);
    fixture.screen.openSearch();
    await tester.pump();
    final manager = fixture.container.read(overlayPriorityProvider.notifier);
    final dialog = manager.claim(OverlayPriority.dialog);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(fixture.container.read(overlayPriorityProvider),
        OverlayPriority.dialog);
    expect(manager.release(dialog), isTrue);
    expect(
        fixture.container.read(overlayPriorityProvider), OverlayPriority.none);
  });
}
