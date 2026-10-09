import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/input/app_intents.dart';
import '../../core/input/console_screen_mixin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../l10n/app_localizations.dart';
import '../../models/config/drive_source_config.dart';
import '../../models/config/source.dart';
import '../../providers/app_providers.dart';
import '../../services/drive/drive_runtime.dart';
import '../../services/saves/drive_save_backup_area.dart';
import '../../services/saves/save_backup_setup.dart';

/// Normal explicit setup. It neither changes ROM sources nor enables unmapped
/// folder scanning. Save-group mapping and backup execution follow this gate.
class SaveBackupSettingsScreen extends ConsumerStatefulWidget {
  const SaveBackupSettingsScreen({super.key});
  @override
  ConsumerState<SaveBackupSettingsScreen> createState() =>
      _SaveBackupSettingsScreenState();
}

class _SaveBackupSettingsScreenState
    extends ConsumerState<SaveBackupSettingsScreen> with ConsoleScreenMixin {
  String? _sourceId;
  String? _binding;
  Future<SaveBackupSetup>? _loading;
  SaveBackupSetup? _setup;
  int _generation = 0;
  bool _leaving = false;
  @override
  String get routeId => 'save_backup_settings';
  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          _back();
          return null;
        }),
        ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
          final context = FocusManager.instance.primaryFocus?.context;
          if (context != null) {
            Actions.maybeInvoke(context, const ActivateIntent());
          }
          return null;
        }),
        NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
          FocusManager.instance.primaryFocus
              ?.focusInDirection(switch (intent.direction) {
            GridDirection.up => TraversalDirection.up,
            GridDirection.down => TraversalDirection.down,
            GridDirection.left => TraversalDirection.left,
            GridDirection.right => TraversalDirection.right,
          });
          return null;
        }),
      };

  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    await _setup?.cancelAndJoin();
    if (mounted) Navigator.maybePop(context);
  }

  Future<SaveBackupSetup> _open(DriveSourceConfig config) async {
    final generation = ++_generation;
    final preferences = await SharedPreferences.getInstance();
    final authorization =
        DriveRuntime.instance.authorizationFor(config.serverClientId);
    final setup = SaveBackupSetup(
        accountId: config.accountId,
        clientId: config.serverClientId,
        preferences: preferences,
        authorization: authorization,
        api: DriveSaveBackupAreaApi(
            authorization: authorization, accountId: config.accountId));
    await setup.load();
    if (!mounted || generation != _generation) {
      setup.dispose();
      throw StateError('Backup settings closed');
    }
    _setup = setup;
    setup.addListener(_setupChanged);
    return setup;
  }

  void _setupChanged() {
    if (mounted) setState(() {});
  }

  void _closeSetup() {
    _setup?.removeListener(_setupChanged);
    _setup?.dispose();
    _setup = null;
  }

  @override
  void dispose() {
    _generation++;
    _closeSetup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final bindings = <String>{};
    final sources = ref
        .watch(sourcesProvider)
        .sources
        .where((source) =>
            source.enabled &&
            source.type == SourceType.drive &&
            source.drive?.isConfigured == true &&
            bindings.add(jsonEncode(
                [source.drive!.serverClientId, source.drive!.accountId])))
        .toList();
    final selected = sources.where((s) => s.id == _sourceId).firstOrNull ??
        sources.firstOrNull;
    final binding = selected == null
        ? null
        : jsonEncode([
            selected.id,
            selected.drive!.serverClientId,
            selected.drive!.accountId,
          ]);
    if (binding != _binding) {
      _binding = binding;
      _sourceId = selected?.id;
      _generation++;
      _closeSetup();
      _loading = selected == null ? null : _open(selected.drive!);
    }
    return buildWithActions(ScreenLayout(
        body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    IconButton(
                        key: const ValueKey('save-backup-back'),
                        tooltip: l.common_back,
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(l.saveBackup_title,
                            style: AppTheme.headlineMedium)),
                  ]),
                  const SizedBox(height: 20),
                  Expanded(
                      child: ListView(children: [
                    if (selected == null)
                      Text(l.saveBackup_noDrive)
                    else ...[
                      DropdownButtonFormField<String>(
                          key: ValueKey('save-backup-account-$_sourceId'),
                          initialValue: _sourceId,
                          decoration:
                              InputDecoration(labelText: l.settings_mySources),
                          items: sources
                              .map((source) => DropdownMenuItem(
                                  value: source.id, child: Text(source.name)))
                              .toList(),
                          onChanged: _setup?.busy == true
                              ? null
                              : (id) {
                                  if (id == null || id == _sourceId) {
                                    return;
                                  }
                                  setState(() {
                                    _sourceId = id;
                                  });
                                }),
                      const SizedBox(height: 20),
                      FutureBuilder<SaveBackupSetup>(
                          key: ValueKey(_binding),
                          future: _loading,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Text(
                                  l.saveBackup_problem('setupUnavailable'));
                            }
                            final setup = snapshot.data;
                            if (setup == null) {
                              return const LinearProgressIndicator();
                            }
                            return SaveBackupSetupPanel(setup: setup);
                          }),
                    ],
                  ])),
                ]))));
  }
}

class SaveBackupSetupPanel extends StatelessWidget {
  final SaveBackupSetup setup;
  const SaveBackupSetupPanel({super.key, required this.setup});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: setup,
      builder: (context, _) {
        final l = L.of(context);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.saveBackup_help,
                  style: const TextStyle(fontSize: 18, height: 1.5)),
              const SizedBox(height: 16),
              if (setup.ready) ...[
                Row(children: [
                  const Icon(Icons.verified_user_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l.saveBackup_ready))
                ]),
                const SizedBox(height: 12),
              ],
              Text(l.saveBackup_notMapped),
              const SizedBox(height: 20),
              ConsoleFocusable(
                  autofocus: true,
                  focusScale: 1,
                  onSelect: setup.busy ? null : setup.prepare,
                  child: FilledButton(
                      key: const ValueKey('save-backup-authorize'),
                      style: AppTheme.primaryButtonStyle,
                      onPressed: setup.busy ? null : setup.prepare,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(setup.ready
                              ? l.saveBackup_verify
                              : l.saveBackup_authorize)))),
              if (setup.busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(l.saveBackup_preparing),
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: setup.cancel,
                    child: TextButton(
                        key: const ValueKey('save-backup-cancel'),
                        onPressed: setup.cancel,
                        child: Text(l.common_cancel))),
              ],
              if (setup.issue case final issue?) ...[
                const SizedBox(height: 16),
                Semantics(
                    liveRegion: true, child: Text(l.saveBackup_problem(issue))),
              ],
            ]);
      });
}
