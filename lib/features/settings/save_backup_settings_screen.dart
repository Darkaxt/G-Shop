import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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
import '../../models/game_item.dart';
import '../../models/system_model.dart';
import '../../models/save_emulator_coverage.dart';
import '../../models/retroarch_battery_route.dart';
import '../../services/owned_emulator_launcher.dart';
import '../../providers/app_providers.dart';
import '../../providers/save_backup_providers.dart';
import '../../services/drive/drive_runtime.dart';
import '../../services/saves/drive_save_backup_area.dart';
import '../../services/saves/save_backup_setup.dart';
import '../../services/saves/save_backup_game_job.dart';
import '../../services/saves/automatic_save_backups.dart';
import '../../services/saves/save_capture.dart';
import '../../services/saves/drive_save_backup_generation.dart';
import '../../services/database_service.dart';

enum SaveBackupSection {
  area('Backup area', Icons.cloud_outlined),
  backup('Back up save', Icons.backup_outlined),
  restore('Restore & conflicts', Icons.restore),
  status('Status', Icons.info_outline),
  emulators('Emulators', Icons.sports_esports_outlined);

  final String label;
  final IconData icon;
  const SaveBackupSection(this.label, this.icon);
}

/// Normal explicit setup. It neither changes ROM sources nor enables unmapped
/// folder scanning. Save-group mapping and backup execution follow this gate.
class SaveBackupSettingsScreen extends ConsumerStatefulWidget {
  final String? editionId, gameTitle;
  final GameItem? game;
  final SystemModel? system;
  final String? targetFolder;
  const SaveBackupSettingsScreen(
      {super.key,
      this.editionId,
      this.gameTitle,
      this.game,
      this.system,
      this.targetFolder});
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
  SaveBackupGameJob? _gameJob;
  AutomaticSaveBackups? _automatic;
  Future<SaveBackupGameJob>? _gameLoading;
  String? _gameBinding;
  int _gameGeneration = 0;
  SaveBackupSection _section = SaveBackupSection.area;
  Future<List<SaveEmulatorCoverage>?>? _coverage;
  final _contentScroll = ScrollController();
  final _sectionFocus = {
    for (final section in SaveBackupSection.values)
      section: FocusNode(debugLabel: 'save-section-${section.name}'),
  };
  @override
  void initState() {
    super.initState();
    if (widget.editionId != null) _section = SaveBackupSection.backup;
  }

  Widget _navigationItem(SaveBackupSection section) {
    final selected = _section == section;
    void select() {
      _sectionFocus[section]!.requestFocus();
      if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
      setState(() {
        _section = section;
        if (section == SaveBackupSection.emulators) {
          _coverage ??= _readCoverage();
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        child: ConsoleFocusable(
          focusNode: _sectionFocus[section],
          focusScale: 1,
          onSelect: select,
          child: ExcludeFocus(
            child: TextButton.icon(
              key: ValueKey('save-nav-${section.name}'),
              onPressed: select,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(56),
                padding: const EdgeInsets.all(12),
                foregroundColor: selected ? Colors.white : Colors.white70,
                backgroundColor: selected
                    ? AppTheme.primaryColor.withValues(alpha: .18)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(section.icon, size: 22),
              label: Text(
                  section == SaveBackupSection.status && _gameJob?.issue != null
                      ? '${section.label} · attention'
                      : section == SaveBackupSection.restore &&
                              _gameJob?.conflicts.isNotEmpty == true
                          ? '${section.label} (${_gameJob!.conflicts.length})'
                          : section.label),
            ),
          ),
        ),
      ),
    );
  }

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
    await _gameJob?.cancelAndJoin();
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
    _closeGame();
    _setup?.removeListener(_setupChanged);
    _setup?.dispose();
    _setup = null;
  }

  Future<SaveBackupGameJob> _openGame(
      DriveSourceConfig config, String areaId) async {
    final generation = ++_gameGeneration;
    _automatic = await ref.read(automaticSaveBackupsProvider.future);
    String? ppssppDirectory, ppssppSlot;
    if (widget.system?.id == 'psp') {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_ppssppMappingKey(config));
      if (raw == null) throw StateError('PPSSPP mapping required');
      final mapping = jsonDecode(raw) as Map<String, dynamic>;
      ppssppDirectory = mapping['directory'] as String;
      ppssppSlot = mapping['slot'] as String;
      if (!SaveCapture.validPpssppDirectory(ppssppDirectory) ||
          !SaveCapture.validPpssppName(ppssppSlot)) {
        throw const FormatException('Invalid PPSSPP mapping');
      }
    }
    final authorization =
        DriveRuntime.instance.authorizationFor(config.serverClientId);
    final areas = DriveSaveBackupAreaApi(
        authorization: authorization, accountId: config.accountId);
    final api = DriveSaveBackupGenerationApi(
        authorization: authorization, accountId: config.accountId);
    final job = SaveBackupGameJob(
        database: DatabaseService().database,
        capture: SaveCapture(),
        areas: areas,
        generations: api,
        clientId: config.serverClientId,
        accountId: config.accountId,
        areaId: areaId,
        editionId: widget.editionId!,
        artifactId: widget.game!.remoteArtifact!.id,
        ppssppDirectory: ppssppDirectory,
        ppssppSlot: ppssppSlot,
        retroArchRoute: widget.system?.id == 'gamegear'
            ? RetroArchBatteryRoute.gameGear
            : RetroArchBatteryRoute.mgba,
        resolveSaveName: ppssppSlot == null
            ? () => widget.system?.id == 'gamegear'
                ? OwnedEmulatorLauncher().reviewRetroArchGameGearSave(
                    widget.game!, widget.system!, widget.targetFolder!)
                : OwnedEmulatorLauncher().reviewRetroArchGbaSave(
                    widget.game!, widget.system!, widget.targetFolder!)
            : () async {
                final preferences = await SharedPreferences.getInstance();
                final mapping = jsonDecode(
                    preferences.getString(_ppssppMappingKey(config)) ??
                        '{}') as Map<String, dynamic>;
                if (mapping['directory'] != ppssppDirectory ||
                    mapping['slot'] != ppssppSlot) {
                  throw StateError('PPSSPP mapping changed');
                }
                return ppssppSlot!;
              });
    try {
      await job.load();
      if (!mounted || generation != _gameGeneration) {
        throw StateError('Closed save workflow');
      }
      _gameJob = job;
      job.addListener(_setupChanged);
      return job;
    } catch (_) {
      job.dispose();
      areas.close();
      api.close();
      rethrow;
    }
  }

  String _ppssppMappingKey(DriveSourceConfig config) =>
      AutomaticSaveMapping.ppssppMappingKey(config.serverClientId,
          config.accountId, widget.editionId!, widget.game!.remoteArtifact!.id);

  Future<void> _mapPpsspp(
      DriveSourceConfig config, String directory, String slot) async {
    if (!SaveCapture.validPpssppDirectory(directory) ||
        !SaveCapture.validPpssppName(slot)) {
      throw const FormatException('Invalid PPSSPP mapping');
    }
    final binding = _binding;
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || binding != _binding || _gameJob?.busy == true) return;
    if (!await preferences.setString(_ppssppMappingKey(config),
        jsonEncode({'directory': directory, 'slot': slot}))) {
      throw StateError('Mapping could not be saved');
    }
    if (!mounted || binding != _binding) return;
    setState(_closeGame);
  }

  Widget _mappingIssue(DriveSourceConfig config) {
    if (_section == SaveBackupSection.area) return const SizedBox.shrink();
    if (widget.system?.id == 'psp' && _section == SaveBackupSection.backup) {
      return PpssppSaveMappingPanel(
          title: widget.gameTitle ?? 'Selected PSP edition',
          capture: SaveCapture(),
          chooseDirectory: () => FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Choose PPSSPP_STATE in your configured PSP folder'),
          onMapped: (directory, slot) => _mapPpsspp(config, directory, slot));
    }
    return const Text(
        'Save mapping unavailable. No save was uploaded. Review the mapping in Back up save.');
  }

  void _closeGame() {
    _gameGeneration++;
    _gameBinding = null;
    _gameLoading = null;
    final job = _gameJob;
    _gameJob = null;
    if (job == null) return;
    job.removeListener(_setupChanged);
    job.cancelAndJoin().whenComplete(() {
      job.dispose();
      job.areas.close();
      job.generations.close();
    });
  }

  @override
  void dispose() {
    _generation++;
    _closeSetup();
    _contentScroll.dispose();
    for (final node in _sectionFocus.values) {
      node.dispose();
    }
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
    return buildWithActions(
        ScreenLayout(
            body: Padding(
                padding: const EdgeInsets.all(16),
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
                          child: LayoutBuilder(builder: (context, constraints) {
                        final compact = constraints.maxWidth < 700;
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: compact ? 144 : 244,
                                child: FocusTraversalGroup(
                                  child: ListView(
                                    key: const ValueKey(
                                        'save-backup-navigation'),
                                    children: [
                                      for (final section
                                          in SaveBackupSection.values)
                                        _navigationItem(section),
                                    ],
                                  ),
                                ),
                              ),
                              const VerticalDivider(width: 24),
                              Expanded(
                                  child: FocusTraversalGroup(
                                      child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(_section.label,
                                      key: ValueKey(
                                          'save-content-${_section.name}'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 16),
                                  Expanded(
                                      child: SingleChildScrollView(
                                    key: const ValueKey('save-backup-content'),
                                    controller: _contentScroll,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          ExcludeFocus(
                                            excluding: _section !=
                                                SaveBackupSection.emulators,
                                            child: Visibility(
                                              visible: _section ==
                                                  SaveBackupSection.emulators,
                                              maintainState: true,
                                              child: _coveragePanel(),
                                            ),
                                          ),
                                          // Keep the exact workspace subtree mounted,
                                          // including selection/confirmation and pending
                                          // work. Hidden controls cannot take focus.
                                          ExcludeFocus(
                                            key: const ValueKey(
                                                'save-workspace-focus'),
                                            excluding: _section ==
                                                SaveBackupSection.emulators,
                                            child: Visibility(
                                              visible: _section !=
                                                  SaveBackupSection.emulators,
                                              maintainState: true,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  if (selected == null)
                                                    Text(l.saveBackup_noDrive)
                                                  else ...[
                                                    if (_section ==
                                                        SaveBackupSection
                                                            .area) ...[
                                                      DropdownButtonFormField<
                                                              String>(
                                                          key: ValueKey(
                                                              'save-backup-account-$_sourceId'),
                                                          initialValue:
                                                              _sourceId,
                                                          isExpanded: true,
                                                          decoration:
                                                              InputDecoration(
                                                                  labelText: l
                                                                      .settings_mySources),
                                                          items: sources
                                                              .map((source) =>
                                                                  DropdownMenuItem(
                                                                      value:
                                                                          source
                                                                              .id,
                                                                      child: Text(
                                                                          source
                                                                              .name)))
                                                              .toList(),
                                                          onChanged: _setup
                                                                          ?.busy ==
                                                                      true ||
                                                                  _gameJob?.busy ==
                                                                      true
                                                              ? null
                                                              : (id) {
                                                                  if (id ==
                                                                          null ||
                                                                      id ==
                                                                          _sourceId) {
                                                                    return;
                                                                  }
                                                                  setState(() {
                                                                    _sourceId =
                                                                        id;
                                                                  });
                                                                }),
                                                      const SizedBox(
                                                          height: 20),
                                                    ],
                                                    FutureBuilder<
                                                            SaveBackupSetup>(
                                                        key: ValueKey(_binding),
                                                        future: _loading,
                                                        builder: (context,
                                                            snapshot) {
                                                          if (snapshot
                                                              .hasError) {
                                                            return Text(l
                                                                .saveBackup_problem(
                                                                    'setupUnavailable'));
                                                          }
                                                          final setup =
                                                              snapshot.data;
                                                          if (setup == null) {
                                                            return const LinearProgressIndicator();
                                                          }
                                                          final area =
                                                              setup.ready
                                                                  ? setup.areaId
                                                                  : null;
                                                          final gameBinding =
                                                              widget.editionId ==
                                                                          null ||
                                                                      area ==
                                                                          null
                                                                  ? null
                                                                  : jsonEncode([
                                                                      binding,
                                                                      area,
                                                                      widget
                                                                          .editionId
                                                                    ]);
                                                          if (gameBinding !=
                                                              _gameBinding) {
                                                            _closeGame();
                                                            _gameBinding =
                                                                gameBinding;
                                                            if (gameBinding !=
                                                                null) {
                                                              _gameLoading =
                                                                  _openGame(
                                                                      selected
                                                                          .drive!,
                                                                      area!);
                                                            }
                                                          }
                                                          return Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .stretch,
                                                              children: [
                                                                if (_section ==
                                                                    SaveBackupSection
                                                                        .area)
                                                                  SaveBackupSetupPanel(
                                                                      setup:
                                                                          setup,
                                                                      showUnmapped:
                                                                          _gameLoading ==
                                                                              null),
                                                                if (_gameLoading !=
                                                                    null)
                                                                  FutureBuilder<
                                                                          SaveBackupGameJob>(
                                                                      key: const ValueKey(
                                                                          'save-game-workspace'),
                                                                      future:
                                                                          _gameLoading,
                                                                      builder: (context, game) => game
                                                                              .hasError
                                                                          ? _mappingIssue(
                                                                              selected.drive!)
                                                                          : game.data == null
                                                                              ? const LinearProgressIndicator()
                                                                              : SaveBackupGamePanel(section: _section, job: game.data!, automatic: _automatic, title: widget.gameTitle ?? 'Selected game')),
                                                                if (_gameLoading ==
                                                                        null &&
                                                                    _section !=
                                                                        SaveBackupSection
                                                                            .area)
                                                                  Text(widget.editionId ==
                                                                          null
                                                                      ? 'No game selected. Open a game’s Save backups menu to review its backup, restore and status.'
                                                                      : 'Prepare the backup area first, then return to this section.'),
                                                              ]);
                                                        }),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ]),
                                  )),
                                ],
                              ))),
                            ]);
                      })),
                      if (_gameJob != null &&
                          _gameJob?.busy != true &&
                          _section != SaveBackupSection.status)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const ValueKey('save-operation-status'),
                            onPressed: () {
                              if (_contentScroll.hasClients) {
                                _contentScroll.jumpTo(0);
                              }
                              setState(
                                  () => _section = SaveBackupSection.status);
                            },
                            icon: Icon(_gameJob!.issue == null
                                ? Icons.info_outline
                                : Icons.warning_amber),
                            label: Text(_gameJob!.issue != null
                                ? 'Save operation needs attention · Status'
                                : _gameJob!.lastVerified != null
                                    ? 'Verified backup available · Status'
                                    : 'No verified backup yet · Status'),
                          ),
                        ),
                      if (_setup?.busy == true || _gameJob?.busy == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(children: [
                            const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(_gameJob?.busy == true
                                    ? 'Save operation running · ${_gameJob!.phase}'
                                    : l.saveBackup_preparing)),
                            TextButton(
                                key: const ValueKey('save-operation-cancel'),
                                onPressed: () async {
                                  await _gameJob?.cancelAndJoin();
                                  await _setup?.cancelAndJoin();
                                },
                                child: Text(l.common_cancel)),
                          ]),
                        ),
                    ]))),
        localFocusScope: true);
  }

  Future<List<SaveEmulatorCoverage>?> _readCoverage() async {
    try {
      return await SaveCapture().installedEmulators();
    } catch (_) {
      // Observe channel failures immediately, before the next frame attaches
      // FutureBuilder. Null means failed inventory, never a successful empty one.
      return null;
    }
  }

  Widget _coveragePanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Known installed emulators, embedded runtimes and launchers. '
              'Save and state coverage are separate. Verified applies only to '
              'the route shown, not every game or format. No folders are scanned.'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('save-emulators-refresh'),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh installed apps'),
              onPressed: () => setState(() {
                _coverage = _readCoverage();
              }),
            ),
          ),
          FutureBuilder<List<SaveEmulatorCoverage>?>(
            future: _coverage,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError || snapshot.data == null) {
                return const Text('Installed-emulator inventory unavailable. '
                    'Coverage has not been confirmed; refresh to try again.');
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) {
                return const Text(
                    'No known emulator packages visible to R-Shop. '
                    'This does not prove that no other emulators are installed.');
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in entries)
                      Card(
                        key: ValueKey('save-emulator-${entry.packageName}'),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(
                                    '${entry.versionName} · ${entry.packageName}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 8),
                                Text('Saves: ${entry.saves}'),
                                Text('States: ${entry.states}'),
                                const SizedBox(height: 8),
                                Text(entry.storage),
                              ]),
                        ),
                      ),
                  ]);
            },
          ),
        ],
      );
}

/// Explicit per-edition mapping. No basename matching or recursive folder scan.
/// The selected source plus optional related RTC is reviewed before capture.
class SaveBackupGamePanel extends StatefulWidget {
  final SaveBackupGameJob job;
  final AutomaticSaveBackups? automatic;
  final String title;
  final SaveBackupSection section;
  const SaveBackupGamePanel(
      {super.key,
      required this.job,
      required this.title,
      this.automatic,
      this.section = SaveBackupSection.backup});
  @override
  State<SaveBackupGamePanel> createState() => _SaveBackupGamePanelState();
}

class _SaveBackupGamePanelState extends State<SaveBackupGamePanel> {
  late final Future<List<String>> _names = widget.job.reviewedNames();
  String? _name;
  bool _confirmed = false;
  Future<void> _resolveConflict({String? cloudId}) async {
    final job = widget.job;
    if (job.busy) return;
    final reviewed = job.conflicts.map((h) => h.generationId).toSet();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(cloudId == null
                  ? 'Use captured local save?'
                  : 'Use this cloud version?'),
              content: Text(cloudId == null
                  ? 'Publish the retained local capture as a new version resolving the reviewed branches. '
                      'Every existing cloud version stays intact. This does not replace the current local file.'
                  : 'Restore the selected cloud version to this game’s configured save location. '
                      'The captured and current local saves are preserved for recovery. '
                      'No cloud version is overwritten or deleted. '
                      '${job.isPpsspp ? 'Exit the game, then use Force stop in PPSSPP App info. Keep PPSSPP closed during restore.' : 'Close the game content first.'}'),
              actions: [
                TextButton(
                    key: const ValueKey('save-conflict-cancel'),
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    key: const ValueKey('save-conflict-confirm'),
                    style: AppTheme.primaryButtonStyle,
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(cloudId == null
                        ? 'Use captured local save'
                        : 'Use cloud save')),
              ],
            ));
    if (accepted != true || !mounted) return;
    if (cloudId == null) {
      await job.keepLocalConflict(reviewed);
    } else {
      await job.restoreConflict(cloudId, reviewed);
    }
  }

  Future<void> _restore({bool rollback = false}) async {
    if (widget.job.busy) return;
    final writerInstruction = widget.job.isPpsspp
        ? 'Exit the game, then use Force stop in PPSSPP App info. '
            'Keep PPSSPP closed during restore. R-Shop never stops it automatically.'
        : 'Close the game content in RetroArch before continuing.';
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(rollback
                  ? 'Restore the retained local save?'
                  : 'Replace local save with cloud backup?'),
              content: Text(rollback
                  ? 'This restores the local save retained before the last cloud restore for ${widget.title}. '
                      'The current save is preserved separately before replacement. '
                      '$writerInstruction ROMs and settings are untouched.'
                  : 'This replaces the reviewed save for ${widget.title} '
                      'with its last verified cloud generation, even if the local save differs. '
                      'The current local save is retained as a rollback capture first. '
                      '$writerInstruction '
                      'No other save, ROM or emulator setting is selected.'),
              actions: [
                TextButton(
                    key: const ValueKey('save-restore-cancel'),
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    key: const ValueKey('save-restore-confirm'),
                    style: AppTheme.primaryButtonStyle,
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(rollback
                        ? 'Use retained local save'
                        : 'Use cloud save')),
              ],
            ));
    if (accepted == true && mounted) {
      if (rollback) {
        await widget.job.rollbackLast();
      } else {
        await widget.job.restoreLatest();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.job,
      builder: (context, _) {
        final job = widget.job;
        final conflicts = job.conflicts;
        if (widget.section == SaveBackupSection.area) {
          return const SizedBox.shrink();
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: AppTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                  job.isPpsspp
                      ? 'PPSSPP · published state slot · v1.20.4'
                      : job.retroArchRoute == RetroArchBatteryRoute.gameGear
                          ? 'RetroArch · Genesis Plus GX · Game Gear battery saves'
                          : 'RetroArch · mGBA · battery saves only',
                  style: TextStyle(fontSize: 18)),
              if (widget.section == SaveBackupSection.backup) ...[
                const SizedBox(height: 12),
                Text(
                    job.isPpsspp
                        ? 'Only the explicitly mapped state slot is captured. Its game association is your reviewed mapping, not a title guess. Battery saves, thumbnails, temporary files, ROMs and settings are excluded.'
                        : job.retroArchRoute == RetroArchBatteryRoute.gameGear
                            ? 'Only cartridge SRAM from this exact installation’s validated Game Gear launch is captured. CD backup RAM, ROMs, settings and save states are excluded.'
                            : 'The save target comes from this exact installation’s validated RetroArch launch. A related RTC file is included when present. ROMs, settings and save states are excluded.',
                    style: TextStyle(fontSize: 18, height: 1.4)),
                const SizedBox(height: 16),
                FutureBuilder<List<String>>(
                    future: _names,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Text(
                            'This installation’s save target could not be verified. Check the local game and storage permission.');
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      final names = {...snapshot.data!}.toList()..sort();
                      final selected = names.contains(job.pendingName ?? _name)
                          ? job.pendingName ?? _name
                          : null;
                      return DropdownButtonFormField<String>(
                          key: ValueKey('save-file-$selected'),
                          initialValue: selected,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Reviewed save file'),
                          items: names
                              .map((name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: job.busy || job.pendingName != null
                              ? null
                              : (value) => setState(() {
                                    _name = value;
                                    _confirmed = false;
                                  }));
                    }),
                CheckboxListTile(
                    value: _confirmed,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        'I confirm this save belongs to ${widget.title}',
                        style: const TextStyle(fontSize: 18)),
                    onChanged: job.busy
                        ? null
                        : (value) =>
                            setState(() => _confirmed = value ?? false)),
                Text(
                    job.isPpsspp
                        ? 'PPSSPP publishes a completed slot after closing its temporary writer. Capture rejects a slot that changes while being copied.'
                        : 'Close the game content in RetroArch first. Capture waits for RetroArch’s confirmation; if it is in the background, switch to it using the button below, then return here. You can cancel the wait.',
                    style: TextStyle(fontSize: 18, height: 1.4)),
                const SizedBox(height: 16),
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: !job.busy &&
                            !job.restorePending &&
                            conflicts.isEmpty &&
                            _confirmed &&
                            (job.pendingName ?? _name) != null
                        ? () => job.backup((job.pendingName ?? _name)!)
                        : null,
                    child: FilledButton(
                        key: const ValueKey('save-backup-game-run'),
                        style: AppTheme.primaryButtonStyle,
                        onPressed: !job.busy &&
                                !job.restorePending &&
                                conflicts.isEmpty &&
                                _confirmed &&
                                (job.pendingName ?? _name) != null
                            ? () => job.backup((job.pendingName ?? _name)!)
                            : null,
                        child: Text(job.pendingName == null
                            ? 'Back up reviewed save'
                            : 'Resume this backup'))),
                if (conflicts.isNotEmpty)
                  const Text('Conflict needs review in Restore & conflicts.'),
                if (job.isPpsspp && widget.automatic != null)
                  AutomaticSaveBackupPanel(
                      service: widget.automatic!,
                      mapping: AutomaticSaveMapping.fromJob(job,
                          title: widget.title),
                      allowEnable: !job.busy &&
                          _confirmed &&
                          (job.pendingName ?? _name) != null),
              ],
              if (widget.section == SaveBackupSection.restore) ...[
                if (job.isPpsspp) ...[
                  const Text(
                      'Exit the game safely, then use Force stop in PPSSPP App info. '
                      'Return here without reopening PPSSPP. R-Shop checks Android’s stopped state '
                      'before replacing the selected slot; it never stops the emulator automatically.'),
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: job.busy ? null : job.capture.openPpssppAppInfo,
                      child: OutlinedButton.icon(
                          key: const ValueKey('save-ppsspp-app-info'),
                          onPressed:
                              job.busy ? null : job.capture.openPpssppAppInfo,
                          icon:
                              const Icon(Icons.settings_applications_outlined),
                          label: const Text('PPSSPP App info'))),
                ],
                const SizedBox(height: 16),
                const Text(
                    'Close the game content before restoring. Current local saves and existing cloud versions are preserved.'),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Semantics(
                      liveRegion: true,
                      child: const Text(
                          'Save conflict: local and cloud versions differ. Both are preserved. '
                          'Choose a version explicitly; dates do not decide the winner.',
                          style: TextStyle(fontSize: 18, height: 1.4))),
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: job.busy ? null : _resolveConflict,
                      child: FilledButton(
                          key: const ValueKey('save-conflict-local'),
                          style: AppTheme.primaryButtonStyle,
                          onPressed: job.busy ? null : _resolveConflict,
                          child: const Text('Use captured local save'))),
                  for (final cloud in conflicts)
                    ConsoleFocusable(
                        focusScale: 1,
                        onSelect: job.busy
                            ? null
                            : () =>
                                _resolveConflict(cloudId: cloud.generationId),
                        child: OutlinedButton.icon(
                          key: ValueKey(
                              'save-conflict-cloud-${cloud.generationId}'),
                          onPressed: job.busy
                              ? null
                              : () =>
                                  _resolveConflict(cloudId: cloud.generationId),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: Text(
                              'Use cloud save · ${cloud.binding.deviceId} · '
                              '${cloud.createdAt.toLocal()} · ${cloud.generationId}'),
                        )),
                ],
                if (job.lastVerified != null)
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: !job.busy &&
                              job.pendingName == null &&
                              !job.rollbackPending
                          ? _restore
                          : null,
                      child: OutlinedButton.icon(
                        key: const ValueKey('save-backup-game-restore'),
                        onPressed: !job.busy &&
                                job.pendingName == null &&
                                !job.rollbackPending
                            ? _restore
                            : null,
                        icon: const Icon(Icons.restore),
                        label: Text(job.restorePending
                            ? 'Resume this restore'
                            : 'Restore verified cloud backup'),
                      )),
                if (job.rollbackAvailable)
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: !job.busy && job.pendingName == null
                          ? () => _restore(rollback: true)
                          : null,
                      child: OutlinedButton.icon(
                        key: const ValueKey('save-backup-game-rollback'),
                        onPressed: !job.busy && job.pendingName == null
                            ? () => _restore(rollback: true)
                            : null,
                        icon: const Icon(Icons.undo),
                        label: Text(job.rollbackPending
                            ? 'Resume local rollback'
                            : 'Restore retained local save'),
                      )),
                if (job.lastVerified == null &&
                    conflicts.isEmpty &&
                    !job.rollbackAvailable)
                  const Text(
                      'No verified backup or retained local save is available yet.'),
              ],
              if (widget.section != SaveBackupSection.status || job.busy)
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: job.isPpsspp && job.busy
                        ? null
                        : job.isPpsspp
                            ? job.capture.openPpsspp
                            : job.capture.openRetroArch,
                    child: TextButton(
                        onPressed: job.isPpsspp && job.busy
                            ? null
                            : job.isPpsspp
                                ? job.capture.openPpsspp
                                : job.capture.openRetroArch,
                        child: Text(
                            job.isPpsspp ? 'Open PPSSPP' : 'Open RetroArch'))),
              if (job.busy) ...[
                const LinearProgressIndicator(),
                Text(
                    switch (job.phase) {
                      'capture' => 'Waiting for closed content / capturing…',
                      'cloud_review' =>
                        'Checking cloud versions for conflicts…',
                      'rollback_capture' =>
                        'Waiting for closed content / preserving local rollback…',
                      'restore_download' =>
                        'Downloading and verifying cloud save…',
                      'restore_publish' =>
                        'Waiting for closed content / restoring verified save…',
                      'rollback_verify' => 'Verifying retained local save…',
                      _ => 'Uploading and verifying complete generation…',
                    },
                    style: const TextStyle(fontSize: 18)),
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: job.cancelAndJoin,
                    child: TextButton(
                        onPressed: job.cancelAndJoin,
                        child: const Text('Cancel'))),
              ],
              if (widget.section == SaveBackupSection.status) ...[
                if (job.lastVerified == null)
                  const Text('No verified backup yet.'),
                if (conflicts.isNotEmpty)
                  Text(
                      '${conflicts.length} cloud version(s) need review in Restore & conflicts. No version was overwritten.'),
                if (job.lastVerified != null)
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          'Verified backup: ${job.lastVerified!.createdAt.toLocal()} · ${job.lastVerified!.members.length} save file(s)',
                          style: const TextStyle(fontSize: 18))),
                if (job.phase == 'unchanged')
                  const Text(
                      'Save unchanged. The existing verified cloud backup was retained.',
                      style: TextStyle(fontSize: 18)),
                if (job.isPpsspp && widget.automatic != null)
                  AutomaticSaveBackupPanel(
                      service: widget.automatic!,
                      mapping: AutomaticSaveMapping.fromJob(job,
                          title: widget.title),
                      statusOnly: true),
                if (job.phase == 'restored')
                  Semantics(
                      liveRegion: true,
                      child: const Text(
                          'Cloud save restored. The previous local save is retained for rollback.',
                          style: TextStyle(fontSize: 18))),
                if (job.phase == 'rolled_back')
                  Semantics(
                      liveRegion: true,
                      child: const Text(
                          'Retained local save restored. The replaced save is preserved separately.',
                          style: TextStyle(fontSize: 18))),
                if (job.issue != null)
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          'Save operation not completed: ${job.issue}. The previous verified cloud generation and retained captures are preserved.',
                          style: const TextStyle(fontSize: 18))),
              ],
            ]);
      });
}

/// Compact opt-in inside the selected game section. No additional settings roll.
class AutomaticSaveBackupPanel extends StatefulWidget {
  final AutomaticSaveBackups service;
  final AutomaticSaveMapping mapping;
  final bool allowEnable, statusOnly;
  const AutomaticSaveBackupPanel(
      {super.key,
      required this.service,
      required this.mapping,
      this.allowEnable = false,
      this.statusOnly = false});
  @override
  State<AutomaticSaveBackupPanel> createState() =>
      _AutomaticSaveBackupPanelState();
}

class _AutomaticSaveBackupPanelState extends State<AutomaticSaveBackupPanel> {
  late Future<AutomaticSaveStatus> _status;
  bool _changing = false;
  String? _issue;
  @override
  void initState() {
    super.initState();
    _status = widget.service.status(widget.mapping);
    widget.service.addListener(_changed);
  }

  @override
  void didUpdateWidget(AutomaticSaveBackupPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.mapping.key != widget.mapping.key) {
      oldWidget.service.removeListener(_changed);
      widget.service.addListener(_changed);
      _status = widget.service.status(widget.mapping);
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _status = widget.service.status(widget.mapping);
      });
    }
  }

  Future<void> _set(bool enabled) async {
    if (_changing) return;
    setState(() {
      _changing = true;
      _issue = null;
    });
    try {
      await widget.service.setEnabled(widget.mapping, enabled);
    } catch (_) {
      if (mounted) {
        setState(() => _issue =
            'Automatic backup setting could not be saved. Review the source, backup area and slot mapping.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _changing = false;
          _status = widget.service.status(widget.mapping);
        });
      }
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AutomaticSaveStatus>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
              'Automatic save status unavailable. No backup was enabled.');
        }
        final status = snapshot.data;
        if (status == null) return const LinearProgressIndicator();
        final canChange = !_changing && (status.enabled || widget.allowEnable);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.statusOnly)
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: canChange ? () => _set(!status.enabled) : null,
                    child: ExcludeFocus(
                        child: CheckboxListTile(
                      key: const ValueKey('automatic-save-enable'),
                      contentPadding: EdgeInsets.zero,
                      value: status.enabled,
                      onChanged:
                          canChange ? (value) => _set(value ?? false) : null,
                      title: const Text('Check this slot on app return',
                          style: TextStyle(fontSize: 18)),
                      subtitle: const Text(
                          'Opt-in for this reviewed edition only. Checks on R-Shop startup or return; unchanged bytes are not uploaded again. Conflicts require your choice.'),
                    ))),
              if (widget.statusOnly) ...[
                Text(
                    'Automatic return checks: ${status.enabled ? 'enabled' : 'disabled'}',
                    style: const TextStyle(fontSize: 18)),
                if (widget.service.activeMappingKey == widget.mapping.key)
                  const Text('Checking the mapped save…'),
                if (status.outcome == 'verified')
                  const Text('Last automatic check: backup verified.'),
                if (status.outcome == 'unchanged')
                  const Text(
                      'Last automatic check: unchanged; verified backup retained.'),
                if (status.issue != null)
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          'Automatic check needs attention: ${status.issue}. Existing backups are preserved.')),
              ],
              if (_issue != null) Text(_issue!),
            ]);
      });
}

/// A focused mapping view within Back up save, not another settings scroll.
/// Selecting a directory never changes the application's ROM destination.
class PpssppSaveMappingPanel extends StatefulWidget {
  final String title;
  final SaveCapture capture;
  final Future<String?> Function() chooseDirectory;
  final Future<void> Function(String directory, String slot) onMapped;
  const PpssppSaveMappingPanel(
      {super.key,
      required this.title,
      required this.capture,
      required this.chooseDirectory,
      required this.onMapped});
  @override
  State<PpssppSaveMappingPanel> createState() => _PpssppSaveMappingPanelState();
}

class _PpssppSaveMappingPanelState extends State<PpssppSaveMappingPanel> {
  String? _directory, _slot, _issue;
  List<String> _names = const [];
  bool _confirmed = false, _busy = false;
  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _issue = null;
    });
    try {
      final directory = await widget.chooseDirectory();
      if (directory == null || !mounted) return;
      if (!SaveCapture.validPpssppDirectory(directory)) {
        throw const FormatException(
            'Choose the configured PPSSPP_STATE folder');
      }
      final names = await widget.capture.ppssppNames(directory);
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _names = names;
        _slot = null;
        _confirmed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _issue =
            'Choose an accessible PPSSPP_STATE folder from PPSSPP’s configured shared PSP folder. No mapping was changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_confirmed || _directory == null || _slot == null) return;
    setState(() {
      _busy = true;
      _issue = null;
    });
    try {
      await widget.onMapped(_directory!, _slot!);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _issue = 'Mapping could not be saved. No backup was started.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: AppTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text('Map a PPSSPP state slot', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        const Text(
            'Choose PPSSPP_STATE inside the shared PSP folder configured in PPSSPP. Then explicitly associate one completed slot with this edition. This does not change PPSSPP’s storage settings or start a backup.',
            style: TextStyle(fontSize: 18, height: 1.4)),
        const SizedBox(height: 16),
        ConsoleFocusable(
            focusScale: 1,
            onSelect: _busy ? null : _choose,
            child: OutlinedButton.icon(
                key: const ValueKey('ppsspp-map-folder'),
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose PPSSPP_STATE folder'))),
        if (_directory != null) ...[
          Text(_directory!, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          if (_names.isEmpty)
            const Text(
                'No completed retail state slots were found. Create a state in PPSSPP, then choose this folder again.'),
          DropdownButtonFormField<String>(
              key: const ValueKey('ppsspp-map-slot'),
              initialValue: _slot,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'State slot for this edition'),
              items: _names
                  .map((name) => DropdownMenuItem(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _slot = value;
                        _confirmed = false;
                      })),
          CheckboxListTile(
              key: const ValueKey('ppsspp-map-confirm'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              title: Text('I confirm this slot belongs to ${widget.title}',
                  style: const TextStyle(fontSize: 18)),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _confirmed = value ?? false)),
        ],
        ConsoleFocusable(
            focusScale: 1,
            onSelect: !_busy && _confirmed && _slot != null ? _save : null,
            child: FilledButton(
                key: const ValueKey('ppsspp-map-save'),
                style: AppTheme.primaryButtonStyle,
                onPressed: !_busy && _confirmed && _slot != null ? _save : null,
                child: const Text('Use this state mapping'))),
        if (_busy) const LinearProgressIndicator(),
        if (_issue != null) Text(_issue!, style: const TextStyle(fontSize: 18)),
      ]);
}

class SaveBackupSetupPanel extends StatelessWidget {
  final SaveBackupSetup setup;
  final bool showUnmapped;
  const SaveBackupSetupPanel(
      {super.key, required this.setup, this.showUnmapped = true});
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
              if (showUnmapped) Text(l.saveBackup_notMapped),
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
