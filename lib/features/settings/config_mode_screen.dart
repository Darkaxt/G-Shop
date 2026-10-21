import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../models/config/system_config.dart';
import '../../providers/app_providers.dart';
import '../../providers/game_providers.dart';
import '../../providers/library_providers.dart';
import '../../widgets/console_hud.dart';

/// Drive console options; never adds a standalone filesystem collection.
class ConfigModeScreen extends ConsumerStatefulWidget {
  const ConfigModeScreen({super.key});
  @override
  ConsumerState<ConfigModeScreen> createState() => _ConfigModeScreenState();
}

class _ConfigModeScreenState extends ConsumerState<ConfigModeScreen>
    with ConsoleScreenMixin {
  @override
  String get routeId => 'config_mode';
  String? _error;
  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: BackAction(context, ref),
        FavoriteIntent: CallbackAction<FavoriteIntent>(onInvoke: (_) {
          _importConfig();
          return null;
        }),
        ToggleOverlayIntent: CallbackAction<ToggleOverlayIntent>(onInvoke: (_) {
          _exportConfig();
          return null;
        }),
      };

  Future<void> _exportConfig() async {
    try {
      final storage = ref.read(configStorageServiceProvider);
      final config = await storage.loadConfig();
      if (config == null) throw StateError('Configuration unavailable');
      await storage.exportConfig(config);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not export configuration');
    }
  }

  Future<void> _importConfig() async {
    try {
      final result = await importConfigFile(ref);
      if (!mounted || result.cancelled) return;
      if (result.error != null) {
        setState(() => _error = result.error);
        return;
      }
      await ref
          .read(sourcesProvider.notifier)
          .replaceAll(result.config!.sources);
      if (!mounted) return;
      ref.invalidate(bootstrappedConfigProvider);
      ref.invalidate(gamesProvider);
      ref.read(gameDbChangedProvider.notifier).state++;
      setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not import configuration');
    }
  }

  Future<void> _save(SystemConfig edited) async {
    try {
      final storage = ref.read(configStorageServiceProvider);
      final raw = await storage.loadConfig();
      if (raw == null) return;
      // Preserve original source bindings and retired recovery data verbatim.
      final original = raw.systemById(edited.id);
      if (original == null) return;
      final next = original.copyWith(
          targetFolder: edited.targetFolder,
          autoExtract: edited.autoExtract,
          autoSync: edited.autoSync);
      await storage.saveConfig(jsonEncode(raw.copyWith(systems: [
        for (final s in raw.systems) s.id == edited.id ? next : s
      ]).toJson()));
      ref.invalidate(bootstrappedConfigProvider);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not save console options. Previous settings are retained.');
    }
  }

  Future<void> _edit(SystemConfig system) async {
    final action = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
            backgroundColor: AppTheme.backgroundColor,
            title: Text(system.name),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final entry in {
                'folder': 'Download destination',
                'extract': 'Auto-extract: ${system.autoExtract ? 'On' : 'Off'}',
                'sync': 'Auto-sync: ${system.autoSync ? 'On' : 'Off'}'
              }.entries)
                ConsoleFocusable(
                    autofocus: entry.key == 'folder',
                    onSelect: () => Navigator.pop(dialog, entry.key),
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SizedBox(
                            width: 320,
                            child: Text(entry.value,
                                style: const TextStyle(color: Colors.white))))),
            ])));
    if (!mounted || action == null) return;
    if (action == 'folder') {
      final folder = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose ${system.name} download destination');
      if (mounted && folder != null)
        await _save(system.copyWith(targetFolder: folder));
    } else {
      await _save(system.copyWith(
          autoExtract: action == 'extract' ? !system.autoExtract : null,
          autoSync: action == 'sync' ? !system.autoSync : null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(bootstrappedConfigProvider);
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
                        const Text('CONSOLE OPTIONS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3)),
                        const SizedBox(height: 24),
                        if (_error != null)
                          Text(_error!,
                              style: const TextStyle(color: Colors.redAccent)),
                        Expanded(
                            child: config.when(
                                loading: () => const Center(
                                    child: CircularProgressIndicator()),
                                error: (_, __) => const Text(
                                    'Could not load console settings'),
                                data: (value) => value.systems.isEmpty
                                    ? const Center(
                                        child: Text(
                                            'Connect Google Drive and map its console folders in My Sources.',
                                            style: TextStyle(
                                                color: Colors.white70)))
                                    : ListView.builder(
                                        itemCount: value.systems.length,
                                        itemBuilder: (context, index) {
                                          final s = value.systems[index];
                                          return ConsoleFocusable(
                                              autofocus: index == 0,
                                              onSelect: () => _edit(s),
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 20,
                                                      horizontal: 16),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(s.name,
                                                            style:
                                                                const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        20)),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(s.targetFolder,
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: const TextStyle(
                                                                color: Colors
                                                                    .white60))
                                                      ])));
                                        }))),
                      ])))),
      ConsoleHud(
          select: HudAction(L.of(context).onboarding_importConfig,
              onTap: _importConfig),
          start: HudAction(L.of(context).onboarding_exportConfig,
              onTap: _exportConfig),
          b: HudAction(L.of(context).common_back,
              onTap: () => Navigator.maybePop(context))),
    ])));
  }
}
