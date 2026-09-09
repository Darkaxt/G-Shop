import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/download_item.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/download_providers.dart';
import 'package:retro_eshop/services/download_queue_manager.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/widgets/download/action_button.dart';
import 'package:retro_eshop/widgets/download/download_item_card.dart';
import 'package:retro_eshop/widgets/download_overlay.dart';

import '../helpers/pump_helpers.dart';

const _system = SystemModel(
    id: 'fixture',
    name: 'Fixture',
    manufacturer: 'Fixture',
    releaseYear: 2000,
    romExtensions: ['.chd']);

DownloadItem _item(String id, DownloadStatus status, {double progress = 0}) =>
    DownloadItem(
        id: id,
        game: GameItem(
            filename: '$id.chd',
            displayName: id,
            url: '',
            providerConfig:
                const ProviderConfig(type: ProviderType.drive, priority: 0)),
        system: _system,
        targetFolder: '/roms',
        status: status,
        progress: progress);

// A controlled queue boundary: these tests exercise the real overlay and action
// dispatch. Queue execution, persistence and native IO have separate fixtures.
class _OverlayQueue extends ChangeNotifier implements DownloadQueueManager {
  DownloadQueueState _state;
  final pauses = <String>[];
  final resumes = <String>[];
  final removals = <String>[];
  final moves = <(String, int)>[];
  void Function(String id, int index)? onMove;

  _OverlayQueue(List<DownloadItem> items)
      : _state = DownloadQueueState(queue: items);

  @override
  DownloadQueueState get state => _state;

  void show(List<DownloadItem> items) {
    _state = _state.copyWith(queue: items);
    notifyListeners();
  }

  @override
  Future<void> cancelDownload(String id) async {
    pauses.add(id);
  }

  @override
  void retryDownload(String id) {
    resumes.add(id);
  }

  @override
  Future<void> removeDownload(String id) async {
    removals.add(id);
  }

  @override
  void moveQueued(String id, int queuedIndex) {
    moves.add((id, queuedIndex));
    onMove?.call(id, queuedIndex);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OverlayStorage extends StorageService {
  @override
  ControllerLayout getControllerLayout() => ControllerLayout.nintendo;
}

Future<void> _pumpOverlay(WidgetTester tester, _OverlayQueue queue,
    {bool expanded = false}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(createTestAppWithProviders(
    const Stack(children: [DownloadOverlay()]),
    overrides: [
      downloadQueueManagerProvider.overrideWith((ref) => queue),
      storageServiceProvider.overrideWithValue(_OverlayStorage()),
      storageInfoProvider('/roms').overrideWith((ref) async => null),
      downloadOverlayExpandedProvider.overrideWith((ref) => expanded),
    ],
  ));
  await _finishEntryAnimation(tester);
}

Future<void> _finishEntryAnimation(WidgetTester tester) async {
  // Advance the existing 150 ms stagger start and bounded entry animations.
  // Active progress indicators intentionally keep animating afterward.
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(seconds: 1));
}

Finder _row(String id) => find.byWidgetPredicate(
    (widget) => widget is DownloadItemCard && widget.item.id == id);

void _overlayTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      // Close the overlay while its provider owner is still alive, then drain
      // OverlayFocusScope's existing event-queued priority release. This is
      // fixture teardown, not a timed production cancellation workaround.
      final overlay = find.byType(DownloadOverlay);
      if (overlay.evaluate().isNotEmpty) {
        final container = ProviderScope.containerOf(tester.element(overlay));
        container.read(downloadOverlayExpandedProvider.notifier).state = false;
        await tester.pump();
        await tester.pump(Duration.zero);
      }
    }
  });
}

void main() {
  for (final entry in {
    DownloadStatus.queued: Icons.schedule_rounded,
    DownloadStatus.paused: Icons.pause_rounded,
    DownloadStatus.awaitingAuthorization: Icons.lock_outline_rounded,
    DownloadStatus.error: Icons.error_outline_rounded,
    DownloadStatus.cancelled: Icons.cancel_outlined,
  }.entries) {
    _overlayTest('${entry.key.name} badge never claims completion',
        (tester) async {
      final queue = _OverlayQueue([_item('first', entry.key)]);
      await _pumpOverlay(tester, queue);
      expect(find.byIcon(entry.value), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });
  }

  _overlayTest(
      'badge counts paused, auth and failed rows alongside queued work',
      (tester) async {
    final queue = _OverlayQueue([
      _item('queued', DownloadStatus.queued),
      _item('paused', DownloadStatus.paused),
      _item('auth', DownloadStatus.awaitingAuthorization),
      _item('failed', DownloadStatus.error),
      _item('done', DownloadStatus.completed),
    ]);
    await _pumpOverlay(tester, queue);
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.download_done_rounded), findsNothing);
  });

  _overlayTest('completed badge requires every remaining row to be completed',
      (tester) async {
    final queue = _OverlayQueue([_item('done', DownloadStatus.completed)]);
    await _pumpOverlay(tester, queue);
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    queue.show([
      _item('done', DownloadStatus.completed),
      _item('paused', DownloadStatus.paused)
    ]);
    await tester.pump();
    expect(find.byIcon(Icons.download_done_rounded), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  for (final status in [DownloadStatus.verifying, DownloadStatus.publishing]) {
    _overlayTest(
        '${status.name} badge stays indeterminate at full byte progress',
        (tester) async {
      final queue = _OverlayQueue([_item('processing', status, progress: 1)]);
      await _pumpOverlay(tester, queue);
      expect(
          tester
              .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator))
              .value,
          isNull);
      expect(find.byIcon(Icons.download_done_rounded), findsNothing);
    });
  }

  _overlayTest('opening badge reveals paused and auth rows with working Resume',
      (tester) async {
    final queue = _OverlayQueue([
      _item('paused', DownloadStatus.paused),
      _item('auth', DownloadStatus.awaitingAuthorization)
    ]);
    await _pumpOverlay(tester, queue);
    await tester.tap(find.byKey(const ValueKey('download-queue-badge')));
    await tester.pump();
    await _finishEntryAnimation(tester);
    expect(_row('paused'), findsOneWidget);
    expect(_row('auth'), findsOneWidget);
    expect(find.text('Reconnect in Sources'), findsOneWidget);
    for (final id in ['paused', 'auth']) {
      await tester.tap(find.descendant(
          of: _row(id), matching: find.byType(DownloadActionButton)));
    }
    expect(queue.resumes, ['paused', 'auth']);
    expect(queue.pauses, isEmpty);
  });

  _overlayTest('controller confirms Resume on a focused paused row',
      (tester) async {
    final queue = _OverlayQueue([_item('paused', DownloadStatus.paused)]);
    await _pumpOverlay(tester, queue, expanded: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    expect(queue.resumes, ['paused']);
  });

  _overlayTest('active Drive row dispatches Pause through cancelDownload',
      (tester) async {
    final queue = _OverlayQueue([_item('active', DownloadStatus.downloading)]);
    await _pumpOverlay(tester, queue, expanded: true);
    await tester.tap(
        find.descendant(of: _row('active'), matching: find.byTooltip('Pause')));
    expect(queue.pauses, ['active']);
    expect(queue.resumes, isEmpty);
  });

  _overlayTest('touch reorder sends queued index and reflects queue order',
      (tester) async {
    final first = _item('first', DownloadStatus.queued);
    final second = _item('second', DownloadStatus.queued);
    final paused = _item('paused', DownloadStatus.paused);
    final queue = _OverlayQueue([first, paused, second]);
    queue.onMove = (_, __) => queue.show([second, paused, first]);
    await _pumpOverlay(tester, queue, expanded: true);
    final disabledUp = find.descendant(
        of: _row('first'),
        matching:
            find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up_rounded));
    expect(tester.widget<IconButton>(disabledUp).onPressed, isNull);
    await tester.tap(disabledUp);
    expect(queue.removals, isEmpty);
    expect(queue.moves, isEmpty);
    expect(
        find.descendant(
            of: _row('paused'), matching: find.byTooltip('Move down')),
        findsNothing);
    await tester.tap(find.descendant(
        of: _row('first'), matching: find.byTooltip('Move down')));
    await tester.pump();
    expect(queue.moves, [('first', 1)]);
    expect(tester.getTopLeft(_row('second')).dy,
        lessThan(tester.getTopLeft(_row('first')).dy));
    expect(tester.widget<DownloadItemCard>(_row('first')).isFocused, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
  });

  _overlayTest(
      'shoulder reorder targets focused queued row and keeps its focus',
      (tester) async {
    final first = _item('first', DownloadStatus.queued);
    final second = _item('second', DownloadStatus.queued);
    final queue = _OverlayQueue([first, second]);
    queue.onMove = (_, __) => queue.show([second, first]);
    await _pumpOverlay(tester, queue, expanded: true);
    expect(find.text('Move down'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pump();
    expect(queue.moves, [('first', 1)]);
    expect(tester.widget<DownloadItemCard>(_row('first')).isFocused, isTrue);
    expect(tester.getTopLeft(_row('second')).dy,
        lessThan(tester.getTopLeft(_row('first')).dy));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
