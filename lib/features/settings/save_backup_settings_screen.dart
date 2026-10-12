import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _pspSavedata = true;
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
    String? ppssppDirectory,
        ppssppSlot,
        ppssppSavedataDirectory,
        melonDirectory,
        melonName;
    final melon = widget.system?.id == 'nds';
    final savedata = widget.system?.id == 'psp' && _pspSavedata;
    final mappingKey = melon
        ? _melonMappingKey(config)
        : _ppssppMappingKey(config, savedata: savedata);
    if (widget.system?.id == 'psp' || melon) {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(mappingKey);
      if (raw == null) throw StateError('Save mapping required');
      final mapping = jsonDecode(raw) as Map<String, dynamic>;
      if (melon) {
        melonDirectory = mapping['directory'] as String;
        melonName = mapping['name'] as String;
        if (!SaveCapture.validMelonDirectory(melonDirectory) ||
            !SaveCapture.validMelonName(melonName)) {
          throw const FormatException('Invalid MelonDualDS mapping');
        }
      } else if (savedata) {
        ppssppSavedataDirectory = mapping['directory'] as String;
        if (!SaveCapture.validPpssppSavedataDirectory(
                ppssppSavedataDirectory) ||
            mapping['name'] != ppssppSavedataDirectory.split('/').last) {
          throw const FormatException('Invalid PPSSPP in-game save mapping');
        }
      } else {
        ppssppDirectory = mapping['directory'] as String;
        ppssppSlot = mapping['slot'] as String;
        if (!SaveCapture.validPpssppDirectory(ppssppDirectory) ||
            !SaveCapture.validPpssppName(ppssppSlot)) {
          throw const FormatException('Invalid PPSSPP mapping');
        }
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
        ppssppSavedataDirectory: ppssppSavedataDirectory,
        melonDirectory: melonDirectory,
        melonName: melonName,
        retroArchRoute: RetroArchBatteryRoute.forPlatform(widget.system?.id) ??
            RetroArchBatteryRoute.mgba,
        resolveSaveName: !savedata && ppssppSlot == null && melonName == null
            ? () => OwnedEmulatorLauncher().reviewRetroArchBatterySave(
                widget.game!,
                widget.system!,
                widget.targetFolder!,
                RetroArchBatteryRoute.forPlatform(widget.system?.id)!)
            : () async {
                final preferences = await SharedPreferences.getInstance();
                final mapping =
                    jsonDecode(preferences.getString(mappingKey) ?? '{}')
                        as Map<String, dynamic>;
                final name = savedata
                    ? ppssppSavedataDirectory!.split('/').last
                    : (melonName ?? ppssppSlot)!;
                if (mapping['directory'] !=
                        (melonDirectory ??
                            ppssppSavedataDirectory ??
                            ppssppDirectory) ||
                    mapping[melon || savedata ? 'name' : 'slot'] != name) {
                  throw StateError('Save mapping changed');
                }
                return name;
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

  String _ppssppMappingKey(DriveSourceConfig config, {bool? savedata}) =>
      (savedata ?? _pspSavedata
              ? AutomaticSaveMapping.ppssppSavedataMappingKey
              : AutomaticSaveMapping.ppssppMappingKey)(config.serverClientId,
          config.accountId, widget.editionId!, widget.game!.remoteArtifact!.id);

  String _melonMappingKey(DriveSourceConfig config) =>
      'save_melon_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
            config.serverClientId,
            config.accountId,
            widget.editionId!,
            widget.game!.remoteArtifact!.id.key
          ])))}';

  Future<void> _mapMelon(
      DriveSourceConfig config, String directory, String name) async {
    if (!SaveCapture.validMelonDirectory(directory) ||
        !SaveCapture.validMelonName(name)) {
      throw const FormatException('Invalid MelonDualDS mapping');
    }
    final binding = _binding;
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || binding != _binding || _gameJob?.busy == true) return;
    if (!await preferences.setString(_melonMappingKey(config),
        jsonEncode({'directory': directory, 'name': name}))) {
      throw StateError('Mapping could not be saved');
    }
    if (!mounted || binding != _binding) return;
    setState(_closeGame);
  }

  Future<void> _mapPpsspp(
      DriveSourceConfig config, String directory, String slot) async {
    final savedata = _pspSavedata;
    if (savedata
        ? !SaveCapture.validPpssppSavedataDirectory(directory) ||
            directory.split('/').last != slot
        : !SaveCapture.validPpssppDirectory(directory) ||
            !SaveCapture.validPpssppName(slot)) {
      throw const FormatException('Invalid PPSSPP mapping');
    }
    final binding = _binding;
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || binding != _binding || _gameJob?.busy == true) return;
    if (!await preferences.setString(
        _ppssppMappingKey(config, savedata: savedata),
        jsonEncode(
            {'directory': directory, savedata ? 'name' : 'slot': slot}))) {
      throw StateError('Mapping could not be saved');
    }
    if (!mounted || binding != _binding) return;
    setState(_closeGame);
  }

  Widget _mappingIssue(DriveSourceConfig config) {
    if (_section == SaveBackupSection.area) return const SizedBox.shrink();
    if (widget.system?.id == 'nds' && _section == SaveBackupSection.backup) {
      return StandaloneSaveMappingPanel(
          melon: true,
          title: widget.gameTitle ?? 'Selected DS edition',
          capture: SaveCapture(),
          resolveMelonSave: widget.game != null &&
                  OwnedEmulatorLauncher.supports(widget.game!, widget.system!)
              ? () => OwnedEmulatorLauncher().reviewMelonSave(
                  widget.game!, widget.system!, widget.targetFolder!)
              : null,
          chooseDirectory: () => FilePicker.platform.getDirectoryPath(
              dialogTitle:
                  'Choose the shared save folder configured in MelonDualDS'),
          onMapped: (directory, name) => _mapMelon(config, directory, name));
    }
    if (widget.system?.id == 'psp' &&
        (_section == SaveBackupSection.backup ||
            _pspSavedata && _section == SaveBackupSection.restore)) {
      return StandaloneSaveMappingPanel(
          key: ValueKey('psp-map-$_pspSavedata'),
          pspSavedata: _pspSavedata,
          title: widget.gameTitle ?? 'Selected PSP edition',
          capture: SaveCapture(),
          cloudSavedataFolders: _pspSavedata && _setup?.areaId != null
              ? (cancellation) async {
                  final api = DriveSaveBackupGenerationApi(
                      authorization: DriveRuntime.instance
                          .authorizationFor(config.serverClientId),
                      accountId: config.accountId);
                  try {
                    return await SaveBackupGameJob
                        .discoverPpssppSavedataFolders(
                            database: DatabaseService().database,
                            generations: api,
                            areaId: _setup!.areaId!,
                            editionId: widget.editionId!,
                            artifactId: widget.game!.remoteArtifact!.id,
                            cancellation: cancellation);
                  } finally {
                    api.close();
                  }
                }
              : null,
          chooseDirectory: () => FilePicker.platform.getDirectoryPath(
              dialogTitle:
                  'Choose ${_pspSavedata ? 'SAVEDATA' : 'PPSSPP_STATE'} in your configured PSP folder'),
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
                                                                          .editionId,
                                                                      if (widget
                                                                              .system
                                                                              ?.id ==
                                                                          'psp')
                                                                        _pspSavedata,
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
                                                                if (widget.system
                                                                            ?.id ==
                                                                        'psp' &&
                                                                    _section !=
                                                                        SaveBackupSection
                                                                            .area &&
                                                                    _section !=
                                                                        SaveBackupSection
                                                                            .emulators)
                                                                  Padding(
                                                                      padding: const EdgeInsets
                                                                          .only(
                                                                          bottom:
                                                                              16),
                                                                      child: DropdownButtonFormField<
                                                                          bool>(
                                                                        key: const ValueKey(
                                                                            'psp-backup-kind'),
                                                                        initialValue:
                                                                            _pspSavedata,
                                                                        decoration:
                                                                            const InputDecoration(labelText: 'Backup type'),
                                                                        items: const [
                                                                          DropdownMenuItem(
                                                                              value: true,
                                                                              child: Text('In-game saves')),
                                                                          DropdownMenuItem(
                                                                              value: false,
                                                                              child: Text('Save states'))
                                                                        ],
                                                                        onChanged: _gameJob?.busy ==
                                                                                true
                                                                            ? null
                                                                            : (value) {
                                                                                if (value != null && value != _pspSavedata) {
                                                                                  setState(() {
                                                                                    _pspSavedata = value;
                                                                                    _closeGame();
                                                                                  });
                                                                                }
                                                                              },
                                                                      )),
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
                                                                      key: ValueKey(
                                                                          'save-game-workspace-$gameBinding'),
                                                                      future:
                                                                          _gameLoading,
                                                                      builder: (context, game) => game
                                                                              .hasError
                                                                          ? _mappingIssue(
                                                                              selected.drive!)
                                                                          : game.data == null
                                                                              ? const LinearProgressIndicator()
                                                                              : SaveBackupGamePanel(key: ObjectKey(game.data!), section: _section, job: game.data!, automatic: _automatic, title: widget.gameTitle ?? 'Selected game')),
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
              'Backup support for the emulators R-Shop recognizes on this device. '
              'In-game saves and save states are listed separately. Support may '
              'depend on the game and storage folder. This list does not scan your files.'),
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
                return const Text(
                    'The installed emulator list could not be loaded. '
                    'Choose Refresh installed apps to try again.');
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) {
                return const Text(
                    'R-Shop could not find any emulators it recognizes. '
                    'Other emulators may still be installed.');
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
  @override
  void initState() {
    super.initState();
    widget.automatic?.addListener(_automaticChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _automaticChanged());
  }

  @override
  void didUpdateWidget(SaveBackupGamePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.automatic != widget.automatic) {
      oldWidget.automatic?.removeListener(_automaticChanged);
      widget.automatic?.addListener(_automaticChanged);
    }
  }

  void _automaticChanged() {
    if (mounted &&
        widget.automatic != null &&
        widget.automatic!.activeMappingKey == null &&
        !widget.job.busy) {
      widget.job.refresh();
    }
  }

  @override
  void dispose() {
    widget.automatic?.removeListener(_automaticChanged);
    super.dispose();
  }

  Widget _appInfoButton(SaveBackupGameJob job) => ConsoleFocusable(
      focusScale: 1,
      onSelect: job.busy ? null : job.openAppInfo,
      child: OutlinedButton.icon(
          key: ValueKey(
              job.isMelon ? 'save-melon-app-info' : 'save-ppsspp-app-info'),
          onPressed: job.busy ? null : job.openAppInfo,
          icon: const Icon(Icons.settings_applications_outlined),
          label: Text('${job.emulatorLabel} App info')));
  Future<void> _resolveConflict({String? cloudId}) async {
    final job = widget.job;
    if (job.busy) return;
    final reviewed = job.conflicts.map((h) => h.generationId).toSet();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(cloudId == null
                  ? 'Use this device’s saved copy?'
                  : 'Use this cloud version?'),
              content: Text(cloudId == null
                  ? 'Upload the saved copy from this device as the version to use. '
                      'Older cloud backups are kept. The current local save is not replaced.'
                  : 'Restore the selected cloud version to this game’s configured save location. '
                      '${job.localCopyAvailable ? 'Copies of your local saves are kept so you can undo the restore. ' : 'There is no device copy to replace. '}'
                      'No cloud version is overwritten or deleted. '
                      '${job.isStandalone ? 'Exit ${job.emulatorLabel} safely and keep it closed during restore. R-Shop checks that it has exited before replacing a save.' : 'Close the game in RetroArch first.'}'),
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
                        ? 'Use device copy'
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
    final writerInstruction = widget.job.isStandalone
        ? 'Exit ${widget.job.emulatorLabel} safely and keep it closed during restore. '
            'R-Shop checks that it has exited before replacing a save; it never stops the emulator automatically.'
        : 'Close the game in RetroArch before continuing.';
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(rollback
                  ? 'Undo the last restore?'
                  : widget.job.localCopyAvailable
                      ? 'Replace local save with cloud backup?'
                      : 'Restore the cloud save?'),
              content: Text(rollback
                  ? 'Restore the copy of ${widget.title}’s save kept before the last cloud restore. '
                      'A copy of the current save will also be kept. '
                      '$writerInstruction ROMs and settings are untouched.'
                  : '${widget.job.restorePending ? 'Resume the cloud copy already selected for this restore. It may not be the newest copy; other cloud copies are kept. ' : ''}'
                      '${widget.job.localCopyAvailable ? 'Replace ${widget.title}’s selected save with its last checked cloud backup, even if the local save is different. A copy of the current save is kept so you can undo this. ' : 'Restore ${widget.title}’s selected cloud save to its configured location. There is no device copy to replace. '}'
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
                    child: Text(rollback ? 'Undo restore' : 'Use cloud save')),
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
                  job.isMelon
                      ? 'MelonDualDS · in-game save · 0.8.0.rc2'
                      : job.isPpssppSavedata
                          ? 'PPSSPP · in-game save folder · v1.20.4'
                          : job.isPpsspp
                              ? 'PPSSPP · published state slot · v1.20.4'
                              : !job.retroArchRoute.includesRtc
                                  ? 'RetroArch · Genesis Plus GX · ${job.retroArchRoute.label} battery saves'
                                  : 'RetroArch · mGBA · battery saves only',
                  style: TextStyle(fontSize: 18)),
              if (widget.section == SaveBackupSection.backup) ...[
                const SizedBox(height: 12),
                Text(
                    job.isMelon
                        ? 'Backs up only this game’s selected .sav or .srm file in its configured save folder. ROMs, settings and save states are not included.'
                        : job.isPpssppSavedata
                            ? 'Backs up this game’s complete in-game save folder, including its companion files. ROMs, emulator settings and save states are not included.'
                            : job.isPpsspp
                                ? 'Backs up only the save-state slot you selected for this game. In-game saves, thumbnails, ROMs and settings are not included.'
                                : !job.retroArchRoute.includesRtc
                                    ? 'Backs up this ${job.retroArchRoute.label} game’s in-game save from RetroArch. CD saves, ROMs, settings and save states are not included.'
                                    : 'Backs up this game’s in-game save from RetroArch, including its clock data if present. ROMs, settings and save states are not included.',
                    style: TextStyle(fontSize: 18, height: 1.4)),
                const SizedBox(height: 16),
                FutureBuilder<List<String>>(
                    future: _names,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Text(
                            'R-Shop could not find this game’s save folder. Check that the game is downloaded and storage access is allowed.');
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
                              labelText: 'Save file for this game'),
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
                    job.isMelon
                        ? 'MelonDualDS can stay open. R-Shop only backs up a completed save and keeps your previous backup if the save is still changing.'
                        : job.isPpssppSavedata
                            ? 'Exit PPSSPP normally after saving. R-Shop then backs up the complete folder together, keeping your last verified backup if saving has not finished.'
                            : job.isPpsspp
                                ? 'Finish saving in PPSSPP before backing up. R-Shop will not upload a save that changes while it is being copied.'
                                : 'Close the game in RetroArch first. If it is still running, use Open RetroArch below, close the game, then return here. You can cancel while R-Shop waits.',
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
                            ? 'Back up selected save'
                            : 'Resume this backup'))),
                if (conflicts.isNotEmpty)
                  const Text('Conflict needs review in Restore & conflicts.'),
                if (job.isStandalone && widget.automatic != null)
                  AutomaticSaveBackupPanel(
                      service: widget.automatic!,
                      mapping: AutomaticSaveMapping.fromJob(job,
                          title: widget.title),
                      allowEnable: !job.busy &&
                          _confirmed &&
                          (job.pendingName ?? _name) != null),
              ],
              if (widget.section == SaveBackupSection.restore) ...[
                if (job.isStandalone) ...[
                  Text(
                      'Exit ${job.emulatorLabel} safely and keep it closed during restore. '
                      'R-Shop checks that it has exited before replacing a save; '
                      'it never stops the emulator automatically.'),
                  _appInfoButton(job),
                ],
                const SizedBox(height: 16),
                const Text(
                    'Close the game before restoring. Copies of your current saves and older cloud backups are kept.'),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          job.localCopyAvailable
                              ? 'Save conflict: local and cloud versions differ. Both are preserved. '
                                  'Choose which one to use; R-Shop will not choose based on the date.'
                              : 'More than one cloud save is available. Choose which one to restore. '
                                  'All cloud copies are kept.',
                          style: TextStyle(fontSize: 18, height: 1.4))),
                  if (job.localCopyAvailable)
                    ConsoleFocusable(
                        focusScale: 1,
                        onSelect: job.busy ? null : _resolveConflict,
                        child: FilledButton(
                            key: const ValueKey('save-conflict-local'),
                            style: AppTheme.primaryButtonStyle,
                            onPressed: job.busy ? null : _resolveConflict,
                            child: const Text('Use device copy'))),
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
                if (job.lastVerified != null || job.restorePending)
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
                            ? 'Resume undo'
                            : 'Undo last restore'),
                      )),
                if (job.lastVerified == null &&
                    !job.restorePending &&
                    conflicts.isEmpty &&
                    !job.rollbackAvailable)
                  const Text(
                      'There is no checked cloud backup or saved local copy to restore yet.'),
              ],
              if (widget.section != SaveBackupSection.status || job.busy)
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect:
                        job.isStandalone && job.busy ? null : job.openEmulator,
                    child: TextButton(
                        onPressed: job.isStandalone && job.busy
                            ? null
                            : job.openEmulator,
                        child: Text('Open ${job.emulatorLabel}'))),
              if (job.busy) ...[
                const LinearProgressIndicator(),
                Text(
                    switch (job.phase) {
                      'capture' =>
                        'Waiting for the game to close, then copying its save…',
                      'cloud_review' =>
                        'Checking cloud versions for conflicts…',
                      'rollback_capture' =>
                        'Waiting for the game to close, then keeping a copy of its current save…',
                      'restore_download' =>
                        'Downloading and verifying cloud save…',
                      'restore_publish' =>
                        'Waiting for the game to close, then restoring its save…',
                      'rollback_verify' => 'Checking the previous local save…',
                      _ => 'Uploading and checking the backup…',
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
                if (job.phase == 'no_save')
                  const Text(
                      'No device save or compatible cloud backup yet. '
                      'You can start the game to create one.',
                      style: TextStyle(fontSize: 18)),
                if (job.isStandalone && widget.automatic != null)
                  AutomaticSaveBackupPanel(
                      service: widget.automatic!,
                      mapping: AutomaticSaveMapping.fromJob(job,
                          title: widget.title),
                      statusOnly: true),
                if (job.phase == 'restored')
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          job.rollbackAvailable
                              ? 'Cloud save restored. Your previous local save is kept in case you want to undo this.'
                              : 'Cloud save restored and ready to use.',
                          style: const TextStyle(fontSize: 18))),
                if (job.phase == 'rolled_back')
                  Semantics(
                      liveRegion: true,
                      child: const Text(
                          'The previous local save was restored. A copy of the replaced save is also kept.',
                          style: TextStyle(fontSize: 18))),
                if (job.issue != null) ...[
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          switch (job.issue) {
                            'conflict_changed' => job.restorePending
                                ? 'The cloud save changed while it was being checked. Automatic restore stopped. You can review and explicitly resume the previously selected copy in Restore & conflicts; other cloud copies are kept.'
                                : 'The cloud saves changed while you were choosing. Review the current choices in Restore & conflicts. No copy was replaced.',
                            'stop_melon_required' ||
                            'stop_ppsspp_required' =>
                              'Exit ${job.emulatorLabel} safely, then return here and resume without reopening it. Your existing saves and cloud backups are kept.',
                            'root_unavailable' =>
                              'Allow R-Shop root access in your root manager, then resume the restore. Your cloud backup and staged save are kept.',
                            'related_group_changed' =>
                              'This backup and the local save contain different files. Nothing was replaced; both copies are kept.',
                            'pending_restore' ||
                            'save_restore_pending' =>
                              'Finish the pending restore in Restore & conflicts before backing up or opening this game.',
                            _ =>
                              'The save operation could not finish. Your previous cloud backups and saved local copies are kept. Check your connection and save-folder access, then try again.',
                          },
                          style: const TextStyle(fontSize: 18))),
                  ExpansionTile(
                      title: const Text('Technical details'),
                      children: [SelectableText('Error code: ${job.issue}')]),
                ],
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
            'Automatic backup setting could not be saved. Review the source, backup area and selected save.');
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
                      title: const Text('Automatically back up this save',
                          style: TextStyle(fontSize: 18)),
                      subtitle: const Text(
                          'Only for this version of the game. Watches this save while R-Shop is running, including while you play. Also checks when you return and in the background about every 6 hours when online. Unchanged saves are not uploaded again. If saves conflict, you choose which to use.'),
                    ))),
              if (widget.statusOnly) ...[
                Text(
                    'Automatic save checks: ${status.enabled ? 'enabled' : 'disabled'}',
                    style: const TextStyle(fontSize: 18)),
                if (widget.service.activeMappingKey == widget.mapping.key)
                  const Text('Checking the selected save…'),
                if (status.outcome == 'verified')
                  const Text('Last automatic check: backup verified.'),
                if (status.outcome == 'unchanged')
                  const Text(
                      'Last automatic check: unchanged; verified backup retained.'),
                if (status.issue != null)
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          'Automatic backup could not finish. Existing backups are kept. Check your connection and save-folder access.')),
                if (status.issue != null)
                  ExpansionTile(
                      title: const Text('Technical details'),
                      children: [
                        SelectableText('Error code: ${status.issue}')
                      ]),
                if (status.enabled && widget.service.backgroundIssue != null)
                  const Text(
                      'Android could not schedule background backups. Backups can still run when you return to R-Shop or start one yourself.'),
                if (status.enabled && widget.service.watchIssue != null)
                  const Text(
                      'Live save monitoring is unavailable. Check the selected folder. Backups can still run when you return to R-Shop or start one yourself.'),
              ],
              if (_issue != null) Text(_issue!),
            ]);
      });
}

/// A focused mapping view within Back up save, not another settings scroll.
/// Selecting a directory never changes the application's ROM destination.
class StandaloneSaveMappingPanel extends StatefulWidget {
  final String title;
  final bool melon, pspSavedata;
  final SaveCapture capture;
  final Future<({String directory, String name})> Function()? resolveMelonSave;
  final Future<List<String>> Function(CancelToken)? cloudSavedataFolders;
  final Future<String?> Function() chooseDirectory;
  final Future<void> Function(String directory, String slot) onMapped;
  const StandaloneSaveMappingPanel(
      {super.key,
      this.melon = false,
      this.pspSavedata = false,
      this.resolveMelonSave,
      this.cloudSavedataFolders,
      required this.title,
      required this.capture,
      required this.chooseDirectory,
      required this.onMapped});
  @override
  State<StandaloneSaveMappingPanel> createState() =>
      _StandaloneSaveMappingPanelState();
}

class _StandaloneSaveMappingPanelState
    extends State<StandaloneSaveMappingPanel> {
  String? _directory, _slot, _issue, _locationInfo;
  List<String> _names = const [];
  bool _confirmed = false, _busy = false;
  CancelToken? _cloudCancellation;
  List<String> _localNames = const [];
  String? _cloudInfo;

  @override
  void dispose() {
    _cloudCancellation?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _issue = null;
    });
    try {
      if (!widget.melon) {
        final directory = widget.pspSavedata
            ? await widget.capture.ppssppSavedataParent()
            : await widget.capture.ppssppSaveDirectory();
        final names = widget.pspSavedata
            ? await widget.capture.ppssppSavedataFolders(directory)
            : await widget.capture.ppssppNames(directory);
        if (!mounted) return;
        setState(() {
          _directory = directory;
          _names = names;
          _localNames = names;
          _cloudInfo = null;
          _slot = null;
          _confirmed = false;
          _locationInfo = widget.pspSavedata
              ? 'Found PPSSPP’s in-game saves. Choose this game’s folder below; all its companion files are backed up together.'
              : 'Found the save-state folder configured in PPSSPP. Choose this game’s slot below.';
        });
        return;
      }
      final resolve = widget.resolveMelonSave;
      if (resolve != null) {
        final mapping = await resolve();
        if (!SaveCapture.validMelonDirectory(mapping.directory) ||
            !SaveCapture.validMelonName(mapping.name)) {
          throw const FormatException('Invalid DS save destination');
        }
        final names = await widget.capture.melonNames(mapping.directory);
        if (!mounted) return;
        setState(() {
          _directory = mapping.directory;
          _names = {...names, mapping.name}.toList()..sort();
          _slot = mapping.name;
          _confirmed = false;
          _locationInfo = names.contains(mapping.name)
              ? 'Found the save used by this game’s R-Shop launch. Review it below.'
              : 'Found where this game’s R-Shop launch will save. No local save exists yet; a compatible cloud save can be restored here.';
        });
        return;
      }
      final settings = await widget.capture.melonSaveSettings();
      if (!mounted) return;
      if (settings.directory == null) {
        setState(() => _locationInfo =
            'MelonDualDS saves beside each game when its folder is available. Otherwise it uses the standard save folder. Choose the folder used for this game below.');
      } else {
        final names = await widget.capture.melonNames(settings.directory!);
        if (!mounted) return;
        setState(() {
          _directory = settings.directory;
          _names = names;
          _slot = null;
          _confirmed = false;
          _locationInfo =
              'Found the save folder selected in MelonDualDS. New saves use .${settings.extension}.';
        });
      }
    } catch (error) {
      if (mounted) {
        final emulator = widget.melon ? 'MelonDualDS' : 'PPSSPP';
        setState(() => _issue = error is PlatformException &&
                error.code == 'root_unavailable'
            ? 'Allow R-Shop root access in Magisk to find $emulator’s save folder, or choose the folder yourself.'
            : '$emulator’s save location could not be resolved. Choose the folder configured in the emulator. Your saves and mapping are unchanged.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose([String? standardDirectory]) async {
    setState(() {
      _busy = true;
      _issue = null;
    });
    try {
      final directory = standardDirectory ?? await widget.chooseDirectory();
      if (directory == null || !mounted) return;
      if (!(widget.melon
          ? SaveCapture.validMelonDirectory(directory)
          : widget.pspSavedata
              ? SaveCapture.validPpssppSavedataParent(directory)
              : SaveCapture.validPpssppDirectory(directory))) {
        throw const FormatException(
            'Choose the configured PPSSPP_STATE folder');
      }
      final names = widget.melon
          ? await widget.capture.melonNames(directory)
          : widget.pspSavedata
              ? await widget.capture.ppssppSavedataFolders(directory)
              : await widget.capture.ppssppNames(directory);
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _names = names;
        _localNames = names;
        _cloudInfo = null;
        _slot = null;
        _confirmed = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _issue = widget.melon
            ? error is PlatformException && error.code == 'root_unavailable'
                ? 'Root access was not available. Allow R-Shop in Magisk, then try again. Your saves and mapping are unchanged.'
                : 'The save folder could not be opened. Check root access for the standard folder, or choose the custom folder configured in MelonDualDS. Your mapping is unchanged.'
            : 'Choose ${widget.pspSavedata ? 'SAVEDATA' : 'PPSSPP_STATE'} inside PPSSPP’s configured PSP folder. Protected app folders require R-Shop root access. No mapping was changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findCloud() async {
    final discover = widget.cloudSavedataFolders;
    if (_busy ||
        !widget.pspSavedata ||
        discover == null ||
        _directory == null) {
      return;
    }
    final cancellation = CancelToken();
    _cloudCancellation = cancellation;
    setState(() {
      _busy = true;
      _issue = null;
    });
    try {
      final names = await discover(cancellation);
      if (!mounted || cancellation.isCancelled) return;
      if (!names.every(SaveCapture.validPpssppSavedataMember)) {
        throw const FormatException('Invalid cloud save folder');
      }
      setState(() {
        // Remove previous cloud-only candidates on refresh; local names remain.
        _names = {..._localNames, ...names}.toList()..sort();
        _slot = null;
        _confirmed = false;
        _cloudInfo = names.isEmpty
            ? 'No compatible cloud saves were found for this edition.'
            : 'Cloud saves found. Choose a folder below. Restore will create it in PPSSPP’s save location if it is missing.';
      });
    } catch (_) {
      if (mounted && !cancellation.isCancelled) {
        setState(() => _issue =
            'Cloud saves could not be checked. Check your connection and Drive access, then try again. Your saves are unchanged.');
      }
    } finally {
      if (identical(_cloudCancellation, cancellation)) {
        _cloudCancellation = null;
      }
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
      await widget.onMapped(
          widget.pspSavedata ? '$_directory/$_slot' : _directory!, _slot!);
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
        Text(
            widget.melon
                ? 'Choose a MelonDualDS save'
                : widget.pspSavedata
                    ? 'Choose a PPSSPP in-game save'
                    : 'Choose a PPSSPP save state',
            style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        Text(
            widget.melon
                ? 'R-Shop checks MelonDualDS’s save settings using root. Select this game’s .sav or .srm file from the detected folder, or choose another folder below. Emulator settings and existing saves are not changed.'
                : widget.pspSavedata
                    ? 'R-Shop finds PPSSPP’s Memory Stick using root. Choose the in-game save folder for this edition. Its complete contents stay together; save states are managed separately.'
                    : 'R-Shop checks PPSSPP’s Memory Stick setting using root. Choose this game’s save-state slot from the detected folder, or choose another folder below. Emulator settings and existing saves are not changed.',
            style: TextStyle(fontSize: 18, height: 1.4)),
        const SizedBox(height: 16),
        if (_locationInfo != null)
          Text(_locationInfo!, style: const TextStyle(fontSize: 18)),
        if (_cloudInfo != null)
          Text(_cloudInfo!, style: const TextStyle(fontSize: 18)),
        ConsoleFocusable(
            focusScale: 1,
            onSelect: _busy ? null : _discover,
            child: OutlinedButton.icon(
                key: ValueKey(widget.melon
                    ? 'melon-map-discover'
                    : 'ppsspp-map-discover'),
                onPressed: _busy ? null : _discover,
                icon: const Icon(Icons.refresh),
                label: const Text('Find configured save folder'))),
        if (widget.pspSavedata && widget.cloudSavedataFolders != null)
          ConsoleFocusable(
              focusScale: 1,
              onSelect: _busy || _directory == null ? null : _findCloud,
              child: OutlinedButton.icon(
                  key: const ValueKey('ppsspp-map-cloud'),
                  onPressed: _busy || _directory == null ? null : _findCloud,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Find cloud saves'))),
        if (widget.melon)
          ConsoleFocusable(
              focusScale: 1,
              onSelect: _busy
                  ? null
                  : () => _choose(SaveCapture.melonStandardDirectory),
              child: OutlinedButton.icon(
                  key: const ValueKey('melon-map-standard'),
                  onPressed: _busy
                      ? null
                      : () => _choose(SaveCapture.melonStandardDirectory),
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Check standard save folder'))),
        ConsoleFocusable(
            focusScale: 1,
            onSelect: _busy ? null : _choose,
            child: OutlinedButton.icon(
                key: ValueKey(
                    widget.melon ? 'melon-map-folder' : 'ppsspp-map-folder'),
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.folder_open),
                label: Text(widget.melon
                    ? 'Choose shared save folder'
                    : widget.pspSavedata
                        ? 'Choose SAVEDATA folder'
                        : 'Choose PPSSPP_STATE folder'))),
        if (_directory != null) ...[
          Text(_directory!, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          if (_names.isEmpty)
            Text(widget.melon
                ? 'No in-game saves were found. Save in MelonDualDS, then choose this folder again.'
                : widget.pspSavedata
                    ? 'No local in-game saves were found. Check cloud saves, or save in PPSSPP and refresh.'
                    : 'No finished save states were found. Save a state in PPSSPP, then choose this folder again.'),
          DropdownButtonFormField<String>(
              key:
                  ValueKey(widget.melon ? 'melon-map-slot' : 'ppsspp-map-slot'),
              initialValue: _slot,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: widget.melon
                      ? 'In-game save for this game'
                      : widget.pspSavedata
                          ? 'In-game save folder for this game'
                          : 'Save-state slot for this game'),
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
              key: ValueKey(
                  widget.melon ? 'melon-map-confirm' : 'ppsspp-map-confirm'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              title: Text(
                  'I confirm this ${widget.melon || widget.pspSavedata ? 'save' : 'slot'} belongs to ${widget.title}',
                  style: const TextStyle(fontSize: 18)),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _confirmed = value ?? false)),
        ],
        ConsoleFocusable(
            focusScale: 1,
            onSelect: !_busy && _confirmed && _slot != null ? _save : null,
            child: FilledButton(
                key: ValueKey(
                    widget.melon ? 'melon-map-save' : 'ppsspp-map-save'),
                style: AppTheme.primaryButtonStyle,
                onPressed: !_busy && _confirmed && _slot != null ? _save : null,
                child: Text(widget.melon || widget.pspSavedata
                    ? 'Use this save'
                    : 'Use this save state'))),
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
                    liveRegion: true,
                    child: Text(l.saveBackup_problem(switch (issue) {
                      'authorization_interactionRequired' ||
                      'authorization_accountMismatch' =>
                        'Reconnect your Google account in Sources, then try again.',
                      'cancelled' ||
                      'authorization_cancelled' =>
                        'Setup was cancelled. You can start it again when ready.',
                      'ambiguousAreas' =>
                        'More than one backup folder was found. Check the selected Drive account before continuing.',
                      _ =>
                        'Check your Google account and internet connection, then try again.',
                    }))),
                ExpansionTile(
                    title: const Text('Technical details'),
                    children: [SelectableText('Error code: $issue')]),
              ],
            ]);
      });
}
