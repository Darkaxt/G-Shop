import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../models/config/source.dart';
import '../../providers/app_providers.dart';
import '../../providers/game_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/source_health_providers.dart';
import '../../services/drive/drive_runtime.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_authorization.dart';
import '../../services/drive/drive_catalogue.dart';
import '../../widgets/console_hud.dart';
import '../sources/drive_source_setup_screen.dart';
import '../sources/drive_source_mappings_screen.dart';

class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});
  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen>
    with ConsoleScreenMixin {
  @override
  String get routeId => 'sources_screen';
  final _addFocus = FocusNode();
  final _cards = <String, FocusNode>{};
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _addFocus.dispose();
    for (final n in _cards.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: BackAction(context, ref),
        SearchIntent: SearchAction(ref, onSearch: _addSource),
      };
  void _changed() {
    ref.invalidate(bootstrappedConfigProvider);
    ref.invalidate(gamesProvider);
    ref.read(gameDbChangedProvider.notifier).state++;
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      if (mounted) _changed();
    } catch (error) {
      if (mounted)
        setState(() => _error = error is DriveApiException ||
                error is DriveAuthorizationException ||
                error is DriveCatalogueException
            ? error.toString()
            : 'Google Drive operation could not finish. Your files are unchanged.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSource() async {
    if (_busy) return;
    final source = await Navigator.of(context).push<Source>(
        MaterialPageRoute(builder: (_) => const DriveSourceSetupScreen()));
    if (!mounted || source == null) return;
    _changed(); // Setup committed even if the following remote refresh fails.
    await _run(() async {
      await DriveRuntime.instance.refreshSource(source);
      ref.read(sourceHealthProvider.notifier).markValid(source.id);
    });
  }

  Future<void> _configure(Source source) async {
    final updated = await Navigator.of(context).push<Source>(MaterialPageRoute(
        builder: (_) => DriveSourceSetupScreen(
            initialSource: source,
            onSave: (value) =>
                ref.read(sourcesProvider.notifier).updateSource(value))));
    if (!mounted || updated == null) return;
    _changed(); // Publish the saved binding before attempting remote refresh.
    await _run(() => DriveRuntime.instance.refreshSource(updated));
  }

  Future<void> _mappings(Source source) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => DriveSourceMappingsScreen(source: source)));
    if (mounted && saved == true) _changed();
  }

  Future<void> _actions(Source source) async {
    if (_busy) return;
    final l = L.of(context);
    final action = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
            backgroundColor: AppTheme.backgroundColor,
            title: Text(source.name),
            content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final entry in {
                'refresh': l.sources_refreshCatalogue,
                'map': l.sources_editMappings,
                'configure': l.sources_configureDrive,
                'toggle': source.enabled ? l.sources_disable : l.sources_enable,
                'disconnect': l.sources_disconnectDrive,
                'revoke': l.sources_revokeDrive,
                'remove': l.common_remove,
              }.entries)
                ConsoleFocusable(
                    autofocus: entry.key == 'refresh',
                    onSelect: () => Navigator.pop(dialog, entry.key),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        child: SizedBox(
                            width: 320,
                            child: Text(entry.value,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 18))))),
            ]))));
    if (!mounted || action == null) return;
    switch (action) {
      case 'map':
        await _mappings(source);
      case 'configure':
        await _configure(source);
      case 'refresh':
        await _run(() async {
          await DriveRuntime.instance.refreshSource(source);
          ref.read(sourceHealthProvider.notifier).markValid(source.id);
        });
      case 'toggle':
        await _run(() => ref
            .read(sourcesProvider.notifier)
            .setEnabled(source.id, !source.enabled));
      case 'remove':
        await _run(
            () => ref.read(sourcesProvider.notifier).removeSource(source.id));
      case 'disconnect':
      case 'revoke':
        await _run(() async {
          await DriveRuntime.instance.disconnect(revoke: action == 'revoke');
          ref
              .read(sourceHealthProvider.notifier)
              .markUnknown(ref.read(sourcesProvider).sources.map((s) => s.id));
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sourcesProvider);
    final config = ref.watch(bootstrappedConfigProvider).valueOrNull;
    return buildWithActions(ScreenLayout(
        body: Stack(children: [
      Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 80),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GOOGLE DRIVE',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 28,
                                letterSpacing: 4)),
                        const SizedBox(height: 8),
                        const Text(
                            'Your private collection · Download when you want to play',
                            style: TextStyle(color: Colors.white60)),
                        const SizedBox(height: 24),
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null || state.error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                  _error ?? 'Could not load source settings',
                                  style: const TextStyle(
                                      color: Colors.redAccent))),
                        Expanded(
                            child: state.loading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : state.sources.isEmpty
                                    ? Center(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                            const Icon(Icons.cloud_outlined,
                                                color: Colors.white38,
                                                size: 64),
                                            const SizedBox(height: 16),
                                            const Text(
                                                'Connect Google Drive to browse your collection',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 20)),
                                            const SizedBox(height: 24),
                                            ConsoleFocusable(
                                                focusNode: _addFocus,
                                                autofocus: true,
                                                onSelect: _addSource,
                                                child: const Padding(
                                                    padding: EdgeInsets.all(20),
                                                    child: Text(
                                                        'Connect Google Drive',
                                                        style: TextStyle(
                                                            color: AppTheme
                                                                .primaryColor,
                                                            fontSize: 18)))),
                                          ]))
                                    : ListView.separated(
                                        itemCount: state.sources.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 16),
                                        itemBuilder: (context, index) {
                                          final source = state.sources[index];
                                          final count = config?.systems
                                                  .where((s) => s.manualMappings
                                                      .any((m) =>
                                                          m.sourceId ==
                                                          source.id))
                                                  .length ??
                                              0;
                                          return ConsoleFocusable(
                                              key: ValueKey(
                                                  'source_card_${source.id}'),
                                              focusNode: _cards.putIfAbsent(
                                                  source.id, () => FocusNode()),
                                              autofocus: index == 0,
                                              onSelect: () => _actions(source),
                                              child: Container(
                                                  padding:
                                                      const EdgeInsets.all(24),
                                                  decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: .04),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      border: Border.all(
                                                          color: source.enabled
                                                              ? AppTheme
                                                                  .primaryColor
                                                              : Colors
                                                                  .white24)),
                                                  child: Row(children: [
                                                    const Icon(
                                                        Icons.cloud_outlined,
                                                        color: AppTheme
                                                            .primaryColor),
                                                    const SizedBox(width: 16),
                                                    Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          Text(source.name,
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize:
                                                                      20)),
                                                          const SizedBox(
                                                              height: 8),
                                                          Text(
                                                              '${source.enabled ? 'Enabled' : 'Disabled'} · $count console folders',
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white60))
                                                        ])),
                                                    const Icon(
                                                        Icons.chevron_right,
                                                        color: Colors.white54)
                                                  ])));
                                        })),
                      ])))),
      ConsoleHud(
          b: HudAction('Back', onTap: () => Navigator.maybePop(context)),
          y: HudAction('Connect Drive', onTap: _addSource)),
    ])));
  }
}
