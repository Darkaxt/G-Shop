import 'dart:convert';
import 'dart:async';
import '../../models/save_root_configuration.dart';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/input/app_intents.dart';
import '../../core/input/console_screen_mixin.dart';
import '../../core/input/global_input_wrapper.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../core/widgets/scroll_edge_fade.dart';
import '../../l10n/app_localizations.dart';
import '../../models/config/drive_source_config.dart';
import '../../models/config/source.dart';
import '../../models/game_item.dart';
import '../../models/system_model.dart';
import '../../models/save_emulator_coverage.dart';
import '../../models/emulator_family_registry.dart';
import '../../models/retroarch_battery_route.dart';
import '../../models/pcsx_save_layout.dart';
import '../../models/save_backup_manifest.dart';
import '../../services/owned_emulator_launcher.dart';
import '../../services/owned_storage.dart';
import '../../providers/app_providers.dart';
import '../../providers/save_backup_providers.dart';
import '../../services/drive/drive_runtime.dart';
import '../../services/saves/drive_save_backup_area.dart';
import '../../services/saves/save_backup_setup.dart';
import '../../services/saves/save_backup_game_job.dart';
import '../../services/saves/automatic_save_backups.dart';
import '../../services/saves/save_capture.dart';
import '../../services/saves/emulator_family_settings.dart';
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

enum _DeviceImportSection { source, files }

/// Normal explicit setup. It neither changes ROM sources nor enables unmapped
/// folder scanning. Save-group mapping and backup execution follow this gate.
class SaveBackupSettingsScreen extends ConsumerStatefulWidget {
  final String? editionId, gameTitle;
  final GameItem? game;
  final SystemModel? system;
  final String? targetFolder;
  final EmulatorFamilySettings? emulatorSettings;
  final OwnedEmulatorLauncher? emulatorLauncher;
  const SaveBackupSettingsScreen(
      {super.key,
      this.editionId,
      this.gameTitle,
      this.game,
      this.system,
      this.targetFolder,
      this.emulatorSettings,
      this.emulatorLauncher});
  @override
  ConsumerState<SaveBackupSettingsScreen> createState() =>
      _SaveBackupSettingsScreenState();
}

class _SaveBackupSettingsScreenState
    extends ConsumerState<SaveBackupSettingsScreen>
    with ConsoleScreenMixin, WidgetsBindingObserver {
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
  bool _pspCompanion = false;
  bool _romCompanions = false;
  SaveRootConfiguration? _saveRootConfiguration;
  String? _standardMappingIssue;
  int _pcsxSlot = 1;
  PcsxSaveLayout? _pcsxLayout;
  bool _editingMapping = false;
  SaveBackupSection _section = SaveBackupSection.area;
  Future<List<SaveEmulatorCoverage>?>? _coverage;
  bool _familyFileBusy = false;
  bool _showRegistrations = false;
  EmulatorFamilySettings? _familySettings;
  Future<EmulatorFamilySettings>? _familyOpening;
  StreamSubscription? _familyWatcher;
  final _contentScroll = ScrollController();
  OwnedEmulatorLauncher get _launcher =>
      widget.emulatorLauncher ?? OwnedEmulatorLauncher();
  final _sectionFocus = {
    for (final section in SaveBackupSection.values)
      section: FocusNode(debugLabel: 'save-section-${section.name}'),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.editionId != null) _section = SaveBackupSection.backup;
  }

  Widget _navigationItem(SaveBackupSection section) {
    final selected = _section == section;
    void select() {
      _selectSection(section);
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
  void _selectSection(SaveBackupSection section) {
    _sectionFocus[section]!.requestFocus();
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    setState(() {
      _section = section;
      if (section == SaveBackupSection.emulators) _coverage = _readCoverage();
    });
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        TabLeftIntent: CallbackAction<TabLeftIntent>(onInvoke: (_) {
          _selectSection(SaveBackupSection
              .values[(_section.index - 1) % SaveBackupSection.values.length]);
          return null;
        }),
        TabRightIntent: CallbackAction<TabRightIntent>(onInvoke: (_) {
          _selectSection(SaveBackupSection
              .values[(_section.index + 1) % SaveBackupSection.values.length]);
          return null;
        }),
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
    final artifactKey = widget.game?.remoteArtifact?.id.key;
    if (artifactKey != null && _saveRootConfiguration == null) {
      final raw =
          preferences.getString(SaveRootConfiguration.storageKey(artifactKey));
      if (raw != null) {
        _saveRootConfiguration = SaveRootConfiguration.decode(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        _romCompanions = true;
      }
      if ({'ps2', 'dreamcast', 'gc', 'n3ds', 'wiiu'}
              .contains(widget.system?.id) &&
          (_saveRootConfiguration == null ||
              _saveRootConfiguration!.profile != null)) {
        SaveRootConfiguration? standard;
        try {
          final grant = const {'n3ds', 'wiiu'}.contains(widget.system!.id)
              ? await _launcher.resolveRomCompanionGrant(
                  widget.game!, widget.system!.id, widget.targetFolder!)
              : null;
          standard = await SaveCapture()
              .standardSaveRoot(platformId: widget.system!.id, grant: grant);
          _standardMappingIssue =
              standard == null ? 'save_settings_unresolved' : null;
        } on PlatformException catch (error) {
          _standardMappingIssue = error.code;
        } on FormatException {
          _standardMappingIssue = 'save_settings_unresolved';
        } on OwnedStorageException {
          _standardMappingIssue = 'save_settings_unresolved';
        }
        _saveRootConfiguration = standard;
        _romCompanions = standard != null;
        if (standard != null) {
          if (!await preferences.setString(
              SaveRootConfiguration.storageKey(artifactKey),
              jsonEncode(standard.toJson()))) {
            throw StateError('Mapping was not saved');
          }
          _romCompanions = true;
        }
      }
    }
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
    if (!_romCompanions &&
        !{'psx', 'psp', 'nds'}.contains(widget.system?.id) &&
        RetroArchBatteryRoute.forPlatform(widget.system?.id) == null) {
      throw PlatformException(code: 'save_settings_unresolved');
    }
    _automatic = await ref.read(automaticSaveBackupsProvider.future);
    PcsxSaveLayout? pcsx;
    PcsxSaveCard? card;
    final launcher = _launcher;
    if (_romCompanions) {
      final configured = _saveRootConfiguration;
      Future<Map<String, Object>> grant() async => {
            ...await launcher.resolveRomCompanionGrant(
                widget.game!, widget.system!.id, widget.targetFolder!),
            if (configured != null) 'saveRoot': configured.toJson(),
          };
      final snapshot =
          await SaveCapture().reviewRomCompanions(grant: await grant());
      final runtime = configured == null
          ? OwnedEmulatorLauncher.romCompanionRuntime(widget.system!.id)
          : (packageName: configured.emulator, coreId: configured.core);
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
          resolveRomCompanionGrant: grant,
          saveRootConfiguration: configured,
          romCompanionDirectory: snapshot.directory,
          romCompanionName: snapshot.romName,
          romCompanionPlatform: widget.system!.id,
          romCompanionEmulator: runtime.packageName,
          romCompanionCore: runtime.coreId,
          resolveSaveName: () async {
            final current =
                await SaveCapture().reviewRomCompanions(grant: await grant());
            if (!snapshot.sameTarget(current)) {
              throw PlatformException(code: 'source_changed');
            }
            return current.romName;
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
    if (widget.system?.id == 'psx') {
      pcsx = await launcher.reviewRetroArchPcsxSaves(
          widget.game!, widget.system!, widget.targetFolder!);
      if (!mounted || generation != _gameGeneration) {
        throw StateError('Closed save workflow');
      }
      _pcsxLayout = pcsx;
      card = pcsx.cards.where((c) => c.slot == _pcsxSlot).firstOrNull;
      if (card == null && pcsx.cards.isNotEmpty) {
        card = pcsx.cards.first;
        _pcsxSlot = card.slot;
      }
      if (card?.name == null) {
        throw StateError('PlayStation card association unresolved');
      }
    }
    String? ppssppDirectory,
        ppssppSlot,
        ppssppSavedataDirectory,
        melonDirectory,
        melonName;
    final melon = widget.system?.id == 'nds';
    final savedata = widget.system?.id == 'psp' && _pspSavedata;
    final companion = widget.system?.id == 'psp' && _pspCompanion;
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
        if (companion) {
          ppssppSlot = SaveCapture.ppssppScreenshotName(ppssppSlot);
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
        ppssppCompanion: companion,
        ppssppSavedataDirectory: ppssppSavedataDirectory,
        melonDirectory: melonDirectory,
        melonName: melonName,
        pcsxLayout: pcsx,
        pcsxCard: card,
        resolvePcsxGrant: pcsx == null
            ? null
            : () => launcher.resolveRetroArchPcsxGrant(
                widget.game!, widget.targetFolder!),
        retroArchRoute: RetroArchBatteryRoute.forPlatform(widget.system?.id) ??
            RetroArchBatteryRoute.mgba,
        resolveSaveName: pcsx != null
            ? () async {
                final current = await launcher.reviewRetroArchPcsxSaves(
                    widget.game!, widget.system!, widget.targetFolder!);
                if (!current.containsSelection(pcsx!, card!)) {
                  throw PlatformException(code: 'source_changed');
                }
                return card.name!;
              }
            : !savedata && ppssppSlot == null && melonName == null
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
                        (companion
                            ? mapping['slot'] is! String ||
                                !SaveCapture.validPpssppName(
                                    mapping['slot'] as String) ||
                                SaveCapture.ppssppScreenshotName(
                                        mapping['slot'] as String) !=
                                    name
                            : mapping[melon || savedata ? 'name' : 'slot'] !=
                                name)) {
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

  Future<void> _importSaveRoot() async {
    if (_gameJob?.busy == true ||
        widget.game?.remoteArtifact == null ||
        widget.system == null ||
        widget.targetFolder == null) {
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          withReadStream: true);
      if (picked == null) return;
      final file = picked.files.single;
      if (file.size > 32768 || file.readStream == null) {
        throw const FormatException();
      }
      final bytes = <int>[];
      await for (final chunk in file.readStream!) {
        if (bytes.length + chunk.length > 32768) throw const FormatException();
        bytes.addAll(chunk);
      }
      final grant = await _launcher.resolveRomCompanionGrant(
          widget.game!, widget.system!.id, widget.targetFolder!);
      final configured = SaveRootConfiguration.decode(
          Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
          romName: (grant['filename'] as String).split('/').last);
      await _applySaveRoot(configured);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not use this mapping. Check the folder and selected files.')));
      }
    }
  }

  Future<void> _chooseSavePreset() async {
    if (_gameJob?.busy == true ||
        widget.game?.remoteArtifact == null ||
        widget.system == null ||
        widget.targetFolder == null) {
      return;
    }
    try {
      final settings =
          widget.emulatorSettings ?? await EmulatorFamilySettings.open();
      await settings.reload();
      if (settings.issue != null) throw StateError(settings.issue!);
      final source = settings.source;
      final installed =
          await SaveCapture().installedEmulators(registry: settings.registry);
      final presets = [
        for (final emulator in installed)
          for (final preset in emulator.registration.saveRoots)
            if (preset.platform == widget.system!.id)
              (emulator: emulator.registration, preset: preset)
      ];
      if (!mounted || _leaving) return;
      final selected = await showConsoleDialog<
              ({EmulatorRegistration emulator, EmulatorSavePreset preset})>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Save location'),
                content: presets.isEmpty
                    ? Text(
                        'No presets for this console. Add saveRoots to ${settings.file.path}, then reopen this dialog.')
                    : SizedBox(
                        width: 480,
                        height: (presets.length * 76.0).clamp(76, 360),
                        child: ListView(children: [
                          for (final choice in presets)
                            ListTile(
                                key: ValueKey(
                                    'save-preset-${choice.emulator.packageName}-${choice.preset.name}'),
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(choice.emulator.name),
                                subtitle: Text(choice.preset.name),
                                onTap: () => Navigator.pop(context, choice))
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))
                ],
              ));
      if (selected == null || !mounted || _leaving) return;
      final grant = await _launcher.resolveRomCompanionGrant(
          widget.game!, widget.system!.id, widget.targetFolder!);
      await settings.reload();
      if (settings.source != source) {
        throw StateError('Save locations changed. Reopen the dialog.');
      }
      final configured = selected.preset.resolve(selected.emulator.packageName,
          (grant['filename'] as String).split('/').last);
      await _applySaveRoot(configured);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not use this save location. Check the settings file and installed game.')));
      }
    }
  }

  Future<void> _applySaveRoot(SaveRootConfiguration configured) async {
    if (!mounted || _leaving || _gameJob?.busy == true) return;
    final preferences = await SharedPreferences.getInstance();
    await _prepareMappingChange();
    if (!await preferences.setString(
        SaveRootConfiguration.storageKey(widget.game!.remoteArtifact!.id.key),
        jsonEncode(configured.toJson()))) {
      throw StateError('Mapping was not saved');
    }
    if (!mounted) return;
    setState(() {
      _closeGame();
      _saveRootConfiguration = configured;
      _standardMappingIssue = null;
      _romCompanions = true;
    });
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
    await _prepareMappingChange();
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
    await _prepareMappingChange();
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

  Future<void> _prepareMappingChange() async {
    final job = _gameJob;
    if (job == null) return;
    void requireIdle() {
      if (!mounted ||
          _gameJob != job ||
          job.busy ||
          job.pendingName != null ||
          job.restorePending ||
          job.conflicts.isNotEmpty) {
        throw StateError(
            'Finish the current save operation before changing its location.');
      }
    }

    requireIdle();
    // Retire only this association's automatic work/watch before publishing a
    // new location. Other games and all retained backup generations are kept.
    await _automatic?.disableForJob(job,
        title: widget.gameTitle ?? 'Selected game',
        romRoot: widget.targetFolder);
    await job.refresh();
    requireIdle();
  }

  Widget _mappingIssue(DriveSourceConfig config) {
    if (widget.system?.id == 'psx') {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pcsxCards(),
        const Text(
            'R-Shop could not link this memory card. Check that the game is downloaded and RetroArch’s card settings use a supported save location.'),
      ]);
    }
    if (_section == SaveBackupSection.area && !_editingMapping) {
      return const SizedBox.shrink();
    }
    if (widget.system?.id == 'nds' &&
        (_section == SaveBackupSection.backup || _editingMapping)) {
      return StandaloneSaveMappingPanel(
          melon: true,
          onCancel: _editingMapping
              ? () => setState(() => _editingMapping = false)
              : null,
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
        (_editingMapping ||
            _section == SaveBackupSection.backup ||
            (_pspSavedata || _editingMapping) &&
                _section == SaveBackupSection.restore)) {
      return StandaloneSaveMappingPanel(
          key: ValueKey('psp-map-$_pspSavedata'),
          onCancel: _editingMapping
              ? () => setState(() => _editingMapping = false)
              : null,
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
    _editingMapping = false;
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

  Widget _pcsxCards() {
    final cards = _pcsxLayout?.cards ?? const <PcsxSaveCard>[];
    if (cards.length < 2 ||
        !{SaveBackupSection.backup, SaveBackupSection.restore}
            .contains(_section)) {
      return const SizedBox.shrink();
    }
    final job = _gameJob;
    final changeable = job?.busy != true &&
        job?.pendingName == null &&
        job?.restorePending != true &&
        job?.conflicts.isNotEmpty != true;
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<int>(
          key: ValueKey('pcsx-card-selection-$_pcsxSlot'),
          initialValue: _pcsxSlot,
          decoration: const InputDecoration(labelText: 'Memory card'),
          items: [
            for (final card in cards)
              DropdownMenuItem(
                  value: card.slot,
                  child: Text(
                      'Card ${card.slot} · ${card.isShared ? 'shared between games' : card.needsDiscSerial ? 'disc-based name' : 'this game'}'))
          ],
          onChanged: !changeable
              ? null
              : (slot) {
                  if (slot != null && slot != _pcsxSlot) {
                    setState(() {
                      _pcsxSlot = slot;
                      _closeGame();
                    });
                  }
                },
        ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _familyWatcher?.cancel();
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
                                      child: ScrollEdgeFade(
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
                                                                      _romCompanions,
                                                                      _saveRootConfiguration
                                                                          ?.identity,
                                                                      if (widget
                                                                              .system
                                                                              ?.id ==
                                                                          'psx')
                                                                        _pcsxSlot,
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
                                                                if (_standardMappingIssue !=
                                                                        null &&
                                                                    _section ==
                                                                        SaveBackupSection
                                                                            .backup)
                                                                  Padding(
                                                                      padding: const EdgeInsets
                                                                          .only(
                                                                          bottom:
                                                                              12),
                                                                      child: Text(_standardMappingIssue ==
                                                                              'root_unavailable'
                                                                          ? 'Root access is needed to read the save folder.'
                                                                          : 'Save folder could not be resolved. Choose a save location or use a custom mapping.')),
                                                                if (widget.game
                                                                            ?.remoteArtifact !=
                                                                        null &&
                                                                    widget.system !=
                                                                        null &&
                                                                    _section ==
                                                                        SaveBackupSection
                                                                            .backup)
                                                                  Align(
                                                                      alignment:
                                                                          Alignment
                                                                              .centerLeft,
                                                                      child: TextButton.icon(
                                                                          key: const ValueKey(
                                                                              'save-import-mapping'),
                                                                          onPressed: _gameJob?.busy == true
                                                                              ? null
                                                                              : _importSaveRoot,
                                                                          icon: const Icon(Icons
                                                                              .file_open_outlined),
                                                                          label:
                                                                              const Text('Import mapping'))),
                                                                if (widget
                                                                            .game
                                                                            ?.remoteArtifact !=
                                                                        null &&
                                                                    _section ==
                                                                        SaveBackupSection
                                                                            .backup)
                                                                  Align(
                                                                      alignment:
                                                                          Alignment
                                                                              .centerLeft,
                                                                      child: TextButton.icon(
                                                                          key: const ValueKey(
                                                                              'save-choose-preset'),
                                                                          onPressed: _gameJob?.busy == true
                                                                              ? null
                                                                              : _chooseSavePreset,
                                                                          icon: const Icon(Icons
                                                                              .folder_outlined),
                                                                          label:
                                                                              const Text('Save location'))),
                                                                if (widget.game != null &&
                                                                    widget.system !=
                                                                        null &&
                                                                    (_saveRootConfiguration !=
                                                                            null ||
                                                                        OwnedEmulatorLauncher.supports(
                                                                            widget
                                                                                .game!,
                                                                            widget
                                                                                .system!)) &&
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
                                                                            'game-backup-scope'),
                                                                        initialValue:
                                                                            _romCompanions,
                                                                        decoration: const InputDecoration(
                                                                            labelText:
                                                                                'Back up',
                                                                            prefixIcon:
                                                                                Icon(Icons.folder_copy_outlined)),
                                                                        items: [
                                                                          const DropdownMenuItem(
                                                                              value: false,
                                                                              child: Text('Save data')),
                                                                          DropdownMenuItem(
                                                                              value: true,
                                                                              child: Text(_saveRootConfiguration == null ? 'Game files' : 'Mapped files')),
                                                                        ],
                                                                        onChanged: _gameJob?.busy ==
                                                                                true
                                                                            ? null
                                                                            : (value) {
                                                                                if (value != null) {
                                                                                  setState(() {
                                                                                    _romCompanions = value;
                                                                                    _closeGame();
                                                                                  });
                                                                                }
                                                                              },
                                                                      )),
                                                                if (widget.system
                                                                            ?.id ==
                                                                        'psp' &&
                                                                    !_romCompanions &&
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
                                                                          String>(
                                                                        key: const ValueKey(
                                                                            'psp-backup-kind'),
                                                                        initialValue: _pspSavedata
                                                                            ? 'save'
                                                                            : _pspCompanion
                                                                                ? 'companion'
                                                                                : 'state',
                                                                        decoration:
                                                                            const InputDecoration(labelText: 'Backup type'),
                                                                        items: const [
                                                                          DropdownMenuItem(
                                                                              value: 'save',
                                                                              child: Text('In-game saves')),
                                                                          DropdownMenuItem(
                                                                              value: 'state',
                                                                              child: Text('Save states')),
                                                                          DropdownMenuItem(
                                                                              value: 'companion',
                                                                              child: Text('Slot screenshot'))
                                                                        ],
                                                                        onChanged: _gameJob?.busy ==
                                                                                true
                                                                            ? null
                                                                            : (value) {
                                                                                if (value != null) {
                                                                                  setState(() {
                                                                                    _pspSavedata = value == 'save';
                                                                                    _pspCompanion = value == 'companion';
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
                                                                              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                                                                  if (_editingMapping)
                                                                                    Offstage(
                                                                                        offstage: _section != SaveBackupSection.backup && _section != SaveBackupSection.restore,
                                                                                        child: ExcludeFocus(
                                                                                            excluding: _section != SaveBackupSection.backup && _section != SaveBackupSection.restore,
                                                                                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                                                                              const Text('Changing the selection turns off automatic backups for the previous save. Your existing cloud backups are kept.'),
                                                                                              _mappingIssue(selected.drive!),
                                                                                            ]))),
                                                                                  if (widget.system?.id == 'psx') _pcsxCards(),
                                                                                  if (!_editingMapping || (_section != SaveBackupSection.backup && _section != SaveBackupSection.restore)) SaveBackupGamePanel(key: ObjectKey(game.data!), section: _section, job: game.data!, automatic: _automatic, romRoot: widget.targetFolder, title: widget.gameTitle ?? 'Selected game', onChangeMapping: () => setState(() => _editingMapping = true)),
                                                                                ])),
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
                                  ))),
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
      final settings = _familySettings ??= await (_familyOpening ??=
          widget.emulatorSettings != null
              ? Future.value(widget.emulatorSettings!)
              : EmulatorFamilySettings.open());
      if (!mounted || _leaving) return null;
      _familyWatcher ??= settings.watch().listen((_) => _refreshFamilies(),
          onError: (Object error) {
        // Resume, section entry and Refresh still read the shared file on
        // storage implementations that cannot deliver directory notifications.
        if (mounted) setState(() {});
      });
      await settings.reload();
      if (mounted) setState(() {});
      return await SaveCapture()
          .installedEmulators(registry: settings.registry);
    } catch (_) {
      // Observe channel failures immediately, before the next frame attaches
      // FutureBuilder. Null means failed inventory, never a successful empty one.
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _familySettings != null) {
      _refreshFamilies();
    }
  }

  void _refreshFamilies() {
    if (mounted && !_leaving) {
      setState(() {
        _coverage = _readCoverage();
      });
    }
  }

  Future<void> _editFamily([EmulatorRegistration? entry]) async {
    if (_familyFileBusy) return;
    final settings = _familySettings;
    if (settings == null) return;
    String source;
    try {
      await settings.reload();
      source = settings.source;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted || _leaving) return;
    final opening = settings.registry;
    setState(() => _familyFileBusy = true);
    final package = TextEditingController(text: entry?.packageName);
    final name = TextEditingController(text: entry?.name);
    var family = entry?.family ?? 'custom';
    String? validation;
    try {
      final route = DialogRoute<EmulatorFamilyRegistry>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(entry == null ? 'Add emulator' : 'Edit emulator'),
                  content: SizedBox(
                      width: 440,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            key: const ValueKey('emulator-package'),
                            controller: package,
                            decoration: const InputDecoration(
                                labelText: 'Package ID',
                                hintText: 'dev.igawa6.edenduo')),
                        TextField(
                            key: const ValueKey('emulator-name'),
                            controller: name,
                            decoration: const InputDecoration(
                                labelText: 'Display name')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('emulator-family'),
                          initialValue: family,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Emulator family'),
                          items: [
                            for (final option
                                in EmulatorFamilyRegistry.familyNames.entries)
                              DropdownMenuItem(
                                  value: option.key, child: Text(option.value))
                          ],
                          onChanged: (value) => update(() => family = value!),
                        ),
                        if (validation != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(validation!,
                                  style: const TextStyle(
                                      color: Colors.redAccent))),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel')),
                    TextButton.icon(
                        key: const ValueKey('emulator-save'),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                        onPressed: () {
                          try {
                            final parsed =
                                EmulatorFamilyRegistry.decode(jsonEncode({
                              'schema': 1,
                              'packages': [
                                for (final current in opening.packages.values)
                                  if (current.packageName != entry?.packageName)
                                    current.toJson(),
                                EmulatorRegistration(package.text.trim(),
                                        family, name.text.trim(),
                                        saveRoots: entry?.saveRoots ?? const [])
                                    .toJson(),
                              ]
                            }));
                            Navigator.pop(dialogContext, parsed);
                          } on FormatException catch (error) {
                            update(() => validation = error.message);
                          }
                        }),
                  ],
                )),
      );
      final replacement = await Navigator.of(context).push(route);
      await route.completed;
      if (replacement == null || !mounted || _leaving) return;
      await settings.save(replacement, expectedSource: source);
      _refreshFamilies();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is StateError
                ? error.message.toString()
                : 'Could not save the emulator settings. Check storage access.')));
      }
    } finally {
      package.dispose();
      name.dispose();
      if (mounted) setState(() => _familyFileBusy = false);
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
          const Text(
              'Add forks here, or edit the shared settings file directly. '
              'Save folders and existing backups are unchanged.'),
          if (_familySettings != null) ...[
            SelectableText(_familySettings!.file.path,
                key: const ValueKey('emulator-config-path'),
                style: Theme.of(context).textTheme.bodySmall),
            if (_familySettings!.issue != null) Text(_familySettings!.issue!),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            TextButton.icon(
              key: const ValueKey('save-emulators-refresh'),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: _refreshFamilies,
            ),
            TextButton.icon(
                key: const ValueKey('save-emulator-families-add'),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: _familyFileBusy ||
                        _familySettings == null ||
                        _familySettings!.issue != null
                    ? null
                    : () => _editFamily()),
            TextButton.icon(
                key: const ValueKey('save-emulator-families-configure'),
                icon: Icon(
                    _showRegistrations ? Icons.list : Icons.settings_outlined),
                label: Text(_showRegistrations ? 'Installed' : 'Registrations'),
                onPressed: _familySettings == null
                    ? null
                    : () => setState(
                        () => _showRegistrations = !_showRegistrations)),
          ]),
          if (_showRegistrations && _familySettings != null)
            for (final entry in _familySettings!.registry.packages.values)
              ListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                      '${EmulatorFamilyRegistry.familyNames[entry.family]} · ${entry.packageName}'),
                  trailing: IconButton(
                      tooltip: 'Edit emulator',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed:
                          _familyFileBusy || _familySettings!.issue != null
                              ? null
                              : () => _editFamily(entry))),
          if (!_showRegistrations)
            FutureBuilder<List<SaveEmulatorCoverage>?>(
              future: _coverage,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return const Text(
                      'The installed emulator list could not be loaded. '
                      'Choose Refresh to try again.');
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
                                      '${entry.familyLabel} · ${entry.versionName} · ${entry.packageName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
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

/// Exact per-edition mapping resolved from installation/emulator evidence.
/// Custom/ambiguous location setup belongs to the mapping editor, not this panel.
class SaveBackupGamePanel extends StatefulWidget {
  final SaveBackupGameJob job;
  final AutomaticSaveBackups? automatic;
  final String title;
  final String? romRoot;
  final SaveBackupSection section;
  final VoidCallback? onChangeMapping;
  const SaveBackupGamePanel(
      {super.key,
      required this.job,
      required this.title,
      this.automatic,
      this.romRoot,
      this.onChangeMapping,
      this.section = SaveBackupSection.backup});
  static Future<void> reviewOtherDevices(
          BuildContext context, SaveBackupGameJob job) =>
      _SaveBackupGamePanelState.reviewOtherDevices(context, job);
  @override
  State<SaveBackupGamePanel> createState() => _SaveBackupGamePanelState();
}

class _SaveBackupGamePanelState extends State<SaveBackupGamePanel> {
  late final Future<List<String>> _names = _resolveName();
  String? _name;
  Future<List<String>> _resolveName() async {
    final names = await widget.job.reviewedNames();
    if (mounted) {
      setState(() => _name = names.length == 1 ? names.single : null);
    }
    return names;
  }

  String? get _selectedName =>
      widget.job.pendingName == null || widget.job.pendingName == _name
          ? _name
          : null;
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

  Widget _automaticPanel(SaveBackupGameJob job, {bool statusOnly = false}) {
    Widget panel(String? name) => AutomaticSaveBackupPanel(
        service: widget.automatic!,
        mapping: AutomaticSaveMapping.fromJob(job,
            title: widget.title, saveName: name, romRoot: widget.romRoot),
        statusOnly: statusOnly,
        allowEnable: !job.busy && _selectedName != null);
    if (job.isStandalone) return panel(null);
    return FutureBuilder<List<String>>(
        future: _names,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Text('Finding this game’s save…');
          }
          if (!snapshot.hasData || snapshot.data!.length != 1) {
            return const Text(
                'R-Shop could not link this game’s save. Check its save location.');
          }
          return panel(snapshot.data!.single);
        });
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
    final accepted = await showConsoleDialog<bool>(
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

  Widget _cloudConflictChoice(SaveBackupManifest cloud, int index) {
    final date = cloud.createdAt.toLocal();
    final labels = MaterialLocalizations.of(context);
    final saved = '${labels.formatMediumDate(date)} · '
        '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    final choose = widget.job.busy
        ? null
        : () => _resolveConflict(cloudId: cloud.generationId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Tooltip(
          message:
              'Device: ${cloud.binding.deviceId}\nBackup: ${cloud.generationId}',
          child: Text('Cloud copy ${index + 1} · $saved',
              key: ValueKey('save-cloud-summary-${cloud.generationId}')),
        ),
        const SizedBox(height: 4),
        ConsoleFocusable(
          focusScale: 1,
          onSelect: choose,
          child: OutlinedButton.icon(
            key: ValueKey('save-conflict-cloud-${cloud.generationId}'),
            onPressed: choose,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Use this copy'),
          ),
        ),
      ]),
    );
  }

  Future<void> _restore({bool rollback = false}) async {
    if (widget.job.busy) return;
    final writerInstruction = widget.job.isStandalone
        ? 'Exit ${widget.job.emulatorLabel} safely and keep it closed during restore. '
            'R-Shop checks that it has exited before replacing a save; it never stops the emulator automatically.'
        : 'Close the game in RetroArch before continuing.';
    final accepted = await showConsoleDialog<bool>(
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

  Future<void> _reviewOtherDevices() => reviewOtherDevices(context, widget.job);

  static Future<void> reviewOtherDevices(
      BuildContext context, SaveBackupGameJob job) async {
    final copies = job.otherDeviceBackups;
    if (job.busy || copies.isEmpty) return;
    final suggested = job.suggestedDeviceBackups;
    var selected = suggested.isEmpty ? copies.first : suggested.first;
    var includeGroup = false;
    Set<String> rememberedFiles(SaveBackupManifest copy) => {
          for (final member in copy.members)
            if (job.deviceBackupMemberSelected(copy, member.relativePath))
              member.relativePath
        };
    var selectedFiles = rememberedFiles(selected);
    var section = _DeviceImportSection.source;
    final choice = await showConsoleDialog<
            ({SaveBackupManifest copy, String action, Set<String> files})>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) {
              final ignored = job.deviceBackupIgnored(selected);
              final device = selected.binding.deviceId;
              final shortDevice =
                  device.length > 12 ? '${device.substring(0, 12)}…' : device;
              return ScreenActionsWrapper(
                  screenActions: {
                    TabLeftIntent: CallbackAction<TabLeftIntent>(onInvoke: (_) {
                      update(() => section =
                          section == _DeviceImportSection.source
                              ? _DeviceImportSection.files
                              : _DeviceImportSection.source);
                      return null;
                    }),
                    TabRightIntent:
                        CallbackAction<TabRightIntent>(onInvoke: (_) {
                      update(() => section =
                          section == _DeviceImportSection.source
                              ? _DeviceImportSection.files
                              : _DeviceImportSection.source);
                      return null;
                    }),
                  },
                  child: AlertDialog(
                    icon: const Icon(Icons.devices_outlined),
                    title: const Text('Import from another device'),
                    content: SizedBox(
                      width: 600,
                      height: MediaQuery.sizeOf(context).height * .48,
                      child: Column(
                        children: [
                          SegmentedButton<_DeviceImportSection>(
                            segments: const [
                              ButtonSegment(
                                  value: _DeviceImportSection.source,
                                  icon: Icon(Icons.devices_outlined),
                                  label: Text('Source',
                                      key: ValueKey(
                                          'save-device-source-section'))),
                              ButtonSegment(
                                  value: _DeviceImportSection.files,
                                  icon: Icon(Icons.folder_open_outlined),
                                  label: Text('Files',
                                      key: ValueKey(
                                          'save-device-files-section'))),
                            ],
                            selected: {section},
                            onSelectionChanged: (value) =>
                                update(() => section = value.single),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                              child: ListView(children: [
                            if (section == _DeviceImportSection.source) ...[
                              DropdownButtonFormField<SaveBackupManifest>(
                                key: const ValueKey('save-device-source'),
                                initialValue: selected,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'Source'),
                                items: [
                                  for (final copy in copies)
                                    DropdownMenuItem(
                                        value: copy,
                                        child: Text(
                                            'Device ${copy.binding.deviceId.length > 12 ? '${copy.binding.deviceId.substring(0, 12)}…' : copy.binding.deviceId} · ${MaterialLocalizations.of(context).formatShortDate(copy.createdAt.toLocal())}',
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: (copy) {
                                  if (copy == null) return;
                                  update(() {
                                    selected = copy;
                                    includeGroup = false;
                                    selectedFiles = rememberedFiles(copy);
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(ignored
                                      ? Icons.block
                                      : Icons.cloud_outlined),
                                  title: Text('Device $shortDevice'),
                                  subtitle: Text(
                                      '${selected.binding.kind.label} · ${selected.members.length} files${ignored ? ' · Ignored' : ''}')),
                              const Text(
                                  'A newer date is only a suggestion. Open Files to choose what to import.'),
                              const SizedBox(height: 12),
                              const Text(
                                  'Close the game first. Your current copy is kept for Undo; cloud copies are kept too.'),
                            ] else ...[
                              if (selected.binding.kind !=
                                  SaveBackupKind.companion)
                                CheckboxListTile(
                                  key: const ValueKey('save-device-group'),
                                  contentPadding: EdgeInsets.zero,
                                  value: includeGroup,
                                  title: const Text('Complete save group'),
                                  subtitle: const Text(
                                      'These files need to stay together.'),
                                  onChanged: (value) => update(
                                      () => includeGroup = value ?? false),
                                ),
                              if (selected.binding.kind ==
                                  SaveBackupKind.companion)
                                const Text(
                                    'Choose the companion files to import.'),
                              for (final member in selected.members)
                                if (selected.binding.kind ==
                                    SaveBackupKind.companion)
                                  CheckboxListTile(
                                      key: ValueKey(
                                          'save-device-file-${member.relativePath}'),
                                      contentPadding: EdgeInsets.zero,
                                      value: selectedFiles
                                          .contains(member.relativePath),
                                      secondary: const Icon(
                                          Icons.insert_drive_file_outlined),
                                      title: Text(member.relativePath),
                                      subtitle:
                                          Text('${member.sizeBytes} bytes'),
                                      onChanged: (value) => update(() {
                                            if (value == true) {
                                              selectedFiles
                                                  .add(member.relativePath);
                                            } else {
                                              selectedFiles
                                                  .remove(member.relativePath);
                                            }
                                          }))
                                else
                                  ListTile(
                                      dense: true,
                                      leading: const Icon(
                                          Icons.insert_drive_file_outlined),
                                      title: Text(member.relativePath),
                                      subtitle:
                                          Text('${member.sizeBytes} bytes')),
                            ],
                          ])),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton.icon(
                          key: const ValueKey('save-device-cancel'),
                          autofocus: true,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel')),
                      TextButton.icon(
                          key: const ValueKey('save-device-ignore'),
                          onPressed: () => Navigator.pop(context, (
                                copy: selected,
                                action: ignored ? 'suggest' : 'ignore',
                                files: <String>{},
                              )),
                          icon: Icon(ignored
                              ? Icons.notifications_outlined
                              : Icons.block),
                          label: Text(ignored ? 'Suggest' : 'Ignore')),
                      FilledButton.icon(
                          key: const ValueKey('save-device-import'),
                          style: AppTheme.primaryButtonStyle,
                          onPressed: (selected.binding.kind ==
                                      SaveBackupKind.companion
                                  ? selectedFiles.isNotEmpty
                                  : includeGroup)
                              ? () => Navigator.pop(context, (
                                    copy: selected,
                                    action: 'import',
                                    files: Set<String>.unmodifiable(
                                        selected.binding.kind ==
                                                SaveBackupKind.companion
                                            ? selectedFiles
                                            : selected.members
                                                .map((m) => m.relativePath)),
                                  ))
                              : null,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Import')),
                    ],
                  ));
            }));
    if (choice == null || !context.mounted || job.busy) return;
    if (choice.action == 'import') {
      await job.importDeviceBackup(choice.copy, memberPaths: choice.files);
    } else {
      await job.setDeviceBackupIgnored(choice.copy, choice.action == 'ignore');
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
              if (widget.section == SaveBackupSection.restore &&
                  job.hasImportedData) ...[
                const SizedBox(height: 12),
                const Text('Imported game data',
                    style: TextStyle(fontSize: 20)),
                const Text(
                    'Different files on this device are kept until you choose which copy to use.'),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: job.busy
                          ? null
                          : () async => job.restoreMigrationBeforeLaunch(
                              _selectedName ?? await job.resolveSaveName(),
                              useImported: true),
                      child: FilledButton.icon(
                          key: const ValueKey('save-use-imported'),
                          onPressed: job.busy
                              ? null
                              : () async => job.restoreMigrationBeforeLaunch(
                                  _selectedName ?? await job.resolveSaveName(),
                                  useImported: true),
                          icon: const Icon(Icons.move_to_inbox_outlined),
                          label: const Text('Use imported'))),
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: job.busy ? null : job.keepCurrentImportedData,
                      child: OutlinedButton.icon(
                          onPressed:
                              job.busy ? null : job.keepCurrentImportedData,
                          key: const ValueKey('save-keep-current'),
                          icon: const Icon(Icons.check),
                          label: const Text('Keep current'))),
                  if (job.hasPreviousImportedData)
                    ConsoleFocusable(
                        focusScale: 1,
                        onSelect: job.busy
                            ? null
                            : () async => job.restoreMigrationBeforeLaunch(
                                _selectedName ?? await job.resolveSaveName(),
                                useImported: true,
                                previous: true),
                        child: OutlinedButton.icon(
                            key: const ValueKey('save-previous-import'),
                            onPressed: job.busy
                                ? null
                                : () async => job.restoreMigrationBeforeLaunch(
                                    _selectedName ??
                                        await job.resolveSaveName(),
                                    useImported: true,
                                    previous: true),
                            icon: const Icon(Icons.undo),
                            label: const Text('Previous copy'))),
                ]),
              ],
              const SizedBox(height: 12),
              Text(
                  job.isRomCompanion
                      ? '${job.emulatorLabel} · Game files'
                      : job.isPcsx
                          ? 'RetroArch · PlayStation · ${job.isSharedPcsx ? 'shared memory card' : 'private memory card'} ${job.pcsxCard!.slot}'
                          : job.isMelon
                              ? 'MelonDualDS · in-game save · 0.8.0.rc2'
                              : job.isPpssppSavedata
                                  ? 'PPSSPP · in-game save folder · v1.20.4'
                                  : job.isPpsspp
                                      ? job.ppssppCompanion
                                          ? 'PPSSPP · slot screenshot · v1.20.4'
                                          : 'PPSSPP · published state slot · v1.20.4'
                                      : !job.retroArchRoute.includesRtc
                                          ? 'RetroArch · ${job.retroArchRoute.coreLabel} · ${job.retroArchRoute.label} in-game saves'
                                          : 'RetroArch · mGBA · battery saves only',
                  style: TextStyle(fontSize: 18)),
              if (job.isStandalone &&
                  (widget.section == SaveBackupSection.backup ||
                      widget.section == SaveBackupSection.restore))
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: !job.busy &&
                            job.pendingName == null &&
                            !job.restorePending &&
                            conflicts.isEmpty
                        ? widget.onChangeMapping
                        : null,
                    child: OutlinedButton.icon(
                        key: const ValueKey('save-change-location'),
                        onPressed: !job.busy &&
                                job.pendingName == null &&
                                !job.restorePending &&
                                conflicts.isEmpty
                            ? widget.onChangeMapping
                            : null,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Change save location'))),
              if (widget.section == SaveBackupSection.backup) ...[
                const SizedBox(height: 12),
                Text(
                    job.isPcsx
                        ? job.isSharedPcsx
                            ? 'Backs up the complete shared memory card. It may contain saves from several games; those games use one backup history. ROMs, settings and save states are not included.'
                            : 'Backs up this game’s complete PlayStation memory card. ROMs, settings and save states are not included.'
                        : job.isMelon
                            ? 'Backs up only this game’s selected .sav or .srm file in its configured save folder. ROMs, settings and save states are not included.'
                            : job.isPpssppSavedata
                                ? 'Backs up this game’s complete in-game save folder, including its companion files. ROMs, emulator settings and save states are not included.'
                                : job.isPpsspp
                                    ? job.ppssppCompanion
                                        ? 'Backs up the screenshot for this game’s selected slot. In-game saves and save states have separate backups.'
                                        : 'Backs up only the save-state slot you selected for this game. In-game saves, thumbnails, ROMs and settings are not included.'
                                    : !job.retroArchRoute.includesRtc
                                        ? 'Backs up this ${job.retroArchRoute.label} game’s complete in-game save from RetroArch. ROMs, settings and save states are not included.'
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
                      if (_selectedName == null) {
                        return const Text(
                            'R-Shop could not link this game’s save. Check its save location.');
                      }
                      return const Text('Save linked automatically',
                          key: ValueKey('save-linked-automatically'),
                          style: TextStyle(fontSize: 18));
                    }),
                Text(
                    job.isMelon
                        ? 'MelonDualDS can stay open. R-Shop only backs up a completed save and keeps your previous backup if the save is still changing.'
                        : job.isPpssppSavedata
                            ? 'Exit PPSSPP normally after saving. R-Shop then backs up the complete folder together, keeping your last verified backup if saving has not finished.'
                            : job.isPpsspp
                                ? 'Finish saving in PPSSPP before backing up. R-Shop will not upload a save that changes while it is being copied.'
                                : 'RetroArch can stay open. R-Shop checks that saving has finished and keeps your previous backup if the file is still changing.',
                    style: TextStyle(fontSize: 18, height: 1.4)),
                const SizedBox(height: 16),
                ConsoleFocusable(
                    focusScale: 1,
                    onSelect: !job.busy &&
                            !job.restorePending &&
                            conflicts.isEmpty &&
                            _selectedName != null
                        ? () => job.backup(_selectedName!)
                        : null,
                    child: FilledButton(
                        key: const ValueKey('save-backup-game-run'),
                        style: AppTheme.primaryButtonStyle,
                        onPressed: !job.busy &&
                                !job.restorePending &&
                                conflicts.isEmpty &&
                                _selectedName != null
                            ? () => job.backup(_selectedName!)
                            : null,
                        child: Text(job.pendingName == null
                            ? 'Back up save'
                            : 'Resume this backup'))),
                if (conflicts.isNotEmpty)
                  const Text('Conflict needs review in Restore & conflicts.'),
                if (widget.automatic != null) _automaticPanel(job),
              ],
              if (widget.section == SaveBackupSection.restore) ...[
                if (job.otherDeviceBackups.isNotEmpty) ...[
                  if (job.suggestedDeviceBackups.isNotEmpty)
                    const Text(
                        'Another device has a backup you may want to use. Nothing will be imported unless you choose it.'),
                  ConsoleFocusable(
                      focusScale: 1,
                      onSelect: job.busy ? null : _reviewOtherDevices,
                      child: OutlinedButton.icon(
                          key: const ValueKey('save-other-devices'),
                          onPressed: job.busy ? null : _reviewOtherDevices,
                          icon: const Icon(Icons.devices_outlined),
                          label: const Text('Other devices'))),
                ],
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
                  for (var i = 0; i < conflicts.length; i++)
                    _cloudConflictChoice(conflicts[i], i),
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
                        label: Text(
                            job.restorePending ? 'Resume restore' : 'Restore'),
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
                if (widget.automatic != null)
                  _automaticPanel(job, statusOnly: true),
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
                            'device_choice_unavailable' =>
                              'That choice could not be saved. Your files are unchanged; try again.',
                            'device_import_changed' =>
                              'That backup changed or is no longer available for this game. Open Other devices and choose again. Your files were not replaced.',
                            'device_import_selection' =>
                              'Choose at least one companion file, or the complete save group. Nothing was replaced.',
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
                            'incompatible_state' =>
                              'The emulator or core changed. This state is still backed up, but needs the matching version to restore it. Nothing was replaced.',
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
    } catch (error) {
      if (mounted) {
        setState(() => _issue = error is PlatformException &&
                error.code == 'pending_save_operation'
            ? 'Finish the previous save backup or restore, and resolve any save conflict before changing its location. Existing saves and cloud copies are kept.'
            : 'Automatic backup setting could not be saved. Review the source, backup area and selected save.');
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
                      subtitle: Text(
                          'Watches this game while you play. Offline changes wait for a connection, then check for cloud conflicts before uploading. Also checks when you return and about every 6 hours when online. Unchanged files are not uploaded again.'),
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
                if (status.issue == 'offline')
                  const Text(
                      'Backup queued. It will continue when a connection is available.'),
                if (status.issue != null && status.issue != 'offline')
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
  final VoidCallback? onCancel;
  const StandaloneSaveMappingPanel(
      {super.key,
      this.melon = false,
      this.pspSavedata = false,
      this.resolveMelonSave,
      this.cloudSavedataFolders,
      this.onCancel,
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
        if (widget.onCancel != null)
          ConsoleFocusable(
              focusScale: 1,
              onSelect: _busy ? null : widget.onCancel,
              child: TextButton(
                  key: const ValueKey('save-change-location-cancel'),
                  onPressed: _busy ? null : widget.onCancel,
                  child: const Text('Keep current location'))),
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
