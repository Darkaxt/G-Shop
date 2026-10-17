import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/responsive/responsive.dart';
import '../core/util/color_contrast.dart';
import '../l10n/app_localizations.dart';
import '../models/config/app_config.dart';
import '../providers/app_providers.dart';
import '../providers/game_providers.dart';
import '../providers/library_providers.dart';
import '../providers/ra_providers.dart';
import '../services/library_sync_service.dart';
import '../services/ra_sync_service.dart';

/// Progress area showing collection freshness, ROM library and RA sync pills.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = context.rs;

    return Positioned(
      top: rs.safeAreaTop + (rs.isSmall ? 8 : 12),
      right: rs.isSmall ? 12 : 16,
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            _CollectionRefreshNotice(),
            _LibrarySyncPill(),
            _ConsoleGameProgress(),
            _RaSyncPill(),
          ],
        ),
      ),
    );
  }
}

/// Read saved freshness once; startup is not a request to refresh the catalogue.
/// The five-second timer only dismisses this informational presentation.
class _CollectionRefreshNotice extends ConsumerStatefulWidget {
  const _CollectionRefreshNotice();
  @override
  ConsumerState<_CollectionRefreshNotice> createState() =>
      _CollectionRefreshNoticeState();
}

class _CollectionRefreshNoticeState
    extends ConsumerState<_CollectionRefreshNotice> {
  ProviderSubscription<AsyncValue<AppConfig>>? _config;
  ProviderSubscription<AsyncValue<bool>>? _changes;
  Timer? _dismiss;
  bool _shown = false;
  String? _message;
  String? _age;
  void _show(String message) {
    _dismiss?.cancel();
    setState(() => _message = message);
    _dismiss = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  void initState() {
    super.initState();
    _config = ref.listenManual<AsyncValue<AppConfig>>(
        bootstrappedConfigProvider, (_, next) {
      final config = next.valueOrNull;
      if (_shown || config == null || config.systems.isEmpty) return;
      _shown = true;
      final oldest = ref
          .read(storageServiceProvider)
          .getOldestCollectionSync(config.systems.map((system) => system.id));
      _age = oldest == null
          ? 'Some consoles have not been refreshed yet'
          : 'Collection last refreshed: ${DateFormat.yMMMd().add_Hm().format(oldest.toLocal())}';
      _show(_age!);
    }, fireImmediately: true);
    _changes = ref.listenManual<AsyncValue<bool>>(
        collectionDriveChangesProvider, (_, next) {
      if (next.valueOrNull == true && mounted) {
        _show(
            'Drive folder updated · ${_age ?? 'Saved collection'}. Sync when ready.');
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _config?.close();
    _changes?.close();
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null || ref.watch(librarySyncServiceProvider).isSyncing) {
      return const SizedBox.shrink();
    }
    return _SyncPillContent(
        key: const ValueKey('collection-refresh-notice'),
        accentColor: Colors.white70,
        leadingIcon: Icon(Icons.history_rounded,
            size: context.rs.isSmall ? 14 : 16, color: Colors.white70),
        label: message);
  }
}

/// A separate current-console card; discovery has no invented denominator.
class _ConsoleGameProgress extends ConsumerWidget {
  const _ConsoleGameProgress();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(librarySyncServiceProvider);
    if (!state.isSyncing || state.currentSystem == null) {
      return const SizedBox.shrink();
    }
    final rs = context.rs;
    final label = switch (state.phase) {
      LibrarySyncPhase.checkingSource => state.sourceFilesRead == 0
          ? 'Checking Drive folders…'
          : 'Checking Drive · ${state.sourceFilesRead} files read',
      LibrarySyncPhase.readingGames => 'Reading game list…',
      LibrarySyncPhase.scanningLocal => 'Scanning local games…',
      LibrarySyncPhase.updatingGames =>
        'Updating games · ${state.processedGames}/${state.currentGamesTotal ?? 0}',
    };
    final total = state.currentGamesTotal;
    final value = state.phase == LibrarySyncPhase.updatingGames &&
            total != null &&
            total > 0
        ? (state.processedGames / total).clamp(0.0, 1.0)
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        key: const ValueKey('console-game-progress'),
        width:
            (rs.screenWidth - 24).clamp(0, rs.isSmall ? 280 : 350).toDouble(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: .3)),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  state.phase == LibrarySyncPhase.checkingSource
                      ? 'Drive catalogue'
                      : state.currentSystem!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white, fontSize: rs.isSmall ? 11 : 13)),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.cyanAccent.forText,
                      fontSize: rs.isSmall ? 11 : 12)),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  color: Colors.cyanAccent,
                  backgroundColor: Colors.white12),
            ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library sync pill (cyan) — existing behavior preserved
// ---------------------------------------------------------------------------

class _LibrarySyncPill extends ConsumerStatefulWidget {
  const _LibrarySyncPill();

  @override
  ConsumerState<_LibrarySyncPill> createState() => _LibrarySyncPillState();
}

class _LibrarySyncPillState extends ConsumerState<_LibrarySyncPill> {
  Map<String, String> _failedSystems = const {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(librarySyncServiceProvider);

    ref.listen<LibrarySyncState>(librarySyncServiceProvider, (prev, next) {
      if (next.isSyncing) {
        // New sync starting — clear stale failure state
        if (_failedSystems.isNotEmpty) {
          setState(() => _failedSystems = const {});
        }
        return;
      }

      if (prev != null &&
          prev.isSyncing &&
          !next.isSyncing &&
          next.hadFailures) {
        ref.read(feedbackServiceProvider).warning();
        setState(() => _failedSystems = next.failedSystems);
      }
    });

    final showSyncing = state.isSyncing;
    if (!showSyncing && _failedSystems.isEmpty) return const SizedBox.shrink();

    final rs = context.rs;
    final iconSize = rs.isSmall ? 14.0 : 16.0;

    if (showSyncing) {
      return _SyncPillContent(
        key: const ValueKey('library-syncing'),
        accentColor: Colors.cyanAccent,
        leadingIcon: _SpinningIcon(
          size: iconSize,
          icon: Icons.sync,
          color: Colors.cyanAccent,
        ),
        label: L
            .of(context)
            .sync_progress(state.completedSystems, state.totalSystems),
        systemName: state.currentSystem,
      );
    }

    final l = L.of(context);
    final label = _failedSystems.length == 1
        ? l.sync_singleSystemFailed(_failedSystems.keys.first)
        : l.sync_multipleSystemsFailed(_failedSystems.length);

    return _PulsingPill(
      key: const ValueKey('library-error'),
      child: _SyncPillContent(
        accentColor: Colors.redAccent,
        leadingIcon:
            Icon(Icons.error_outline, size: iconSize, color: Colors.redAccent),
        label: label,
      ),
    );
  }
}

/// Slow pulse animation to draw attention to error pills.
class _PulsingPill extends StatefulWidget {
  final Widget child;
  const _PulsingPill({super.key, required this.child});

  @override
  State<_PulsingPill> createState() => _PulsingPillState();
}

class _PulsingPillState extends State<_PulsingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// RetroAchievements sync pill (golden)
// ---------------------------------------------------------------------------

const _raColor = Color(0xFFFFD54F);

class _RaSyncPill extends ConsumerStatefulWidget {
  const _RaSyncPill();

  @override
  ConsumerState<_RaSyncPill> createState() => _RaSyncPillState();
}

class _RaSyncPillState extends ConsumerState<_RaSyncPill> {
  bool _showError = false;
  String? _lastError;
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raEnabled = ref.watch(raEnabledProvider);
    if (!raEnabled) return const SizedBox.shrink();

    final state = ref.watch(raSyncServiceProvider);

    ref.listen<RaSyncState>(raSyncServiceProvider, (prev, next) {
      if (next.isSyncing) {
        _dismissTimer?.cancel();
        if (_showError) setState(() => _showError = false);
        return;
      }

      if (prev != null &&
          prev.isSyncing &&
          !next.isSyncing &&
          next.error != null) {
        ref.read(feedbackServiceProvider).warning();
        setState(() {
          _showError = true;
          _lastError = next.error;
        });
        _dismissTimer?.cancel();
        _dismissTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _showError = false);
        });
      }
    });

    final showSyncing = state.isSyncing;
    if (!showSyncing && !_showError) return const SizedBox.shrink();

    final rs = context.rs;
    final iconSize = rs.isSmall ? 14.0 : 16.0;

    final Widget pill;
    if (showSyncing) {
      pill = _SyncPillContent(
        key: const ValueKey('ra-syncing'),
        accentColor: _raColor,
        leadingIcon: _SpinningIcon(
          size: iconSize,
          icon: Icons.emoji_events,
          color: _raColor,
        ),
        label: L
            .of(context)
            .sync_raProgress(state.completedSystems, state.totalSystems),
        systemName: state.currentSystem,
      );
    } else {
      pill = _SyncPillContent(
        key: const ValueKey('ra-error'),
        accentColor: Colors.redAccent,
        leadingIcon:
            Icon(Icons.error_outline, size: iconSize, color: Colors.redAccent),
        label: _lastError ?? L.of(context).sync_raFailed,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: pill,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pill decoration
// ---------------------------------------------------------------------------

class _SyncPillContent extends StatelessWidget {
  final Color accentColor;
  final Widget leadingIcon;
  final String label;
  final String? systemName;

  const _SyncPillContent({
    super.key,
    required this.accentColor,
    required this.leadingIcon,
    required this.label,
    this.systemName,
  });

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final fontSize = rs.isSmall ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: rs.isSmall ? 10 : 12,
        vertical: rs.isSmall ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leadingIcon,
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: rs.isSmall ? 200 : 300),
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: accentColor.forText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (systemName != null) ...[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: rs.isSmall ? 100 : 150),
              child: Text(
                systemName!,
                style: TextStyle(
                  fontSize: fontSize - 1,
                  color: Colors.grey[400],
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spinning icon (generalized)
// ---------------------------------------------------------------------------

class _SpinningIcon extends StatefulWidget {
  final double size;
  final IconData icon;
  final Color color;

  const _SpinningIcon({
    required this.size,
    required this.icon,
    required this.color,
  });

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(
        widget.icon,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}
