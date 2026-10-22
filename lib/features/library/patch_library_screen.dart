import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../models/config/provider_config.dart';
import '../../models/game_item.dart';
import '../../models/patch_catalogue.dart';
import '../../models/patch_chain.dart';
import '../../models/portable_patch_recipe.dart';
import '../../models/system_model.dart';
import '../../services/drive/drive_catalogue.dart';
import '../../services/drive/drive_authorization.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_media.dart';
import '../../services/drive/drive_patch_catalogue.dart';
import '../../services/drive/drive_runtime.dart';
import '../../providers/installed_files_provider.dart';
import '../../providers/library_providers.dart';
import '../../providers/app_providers.dart';
import '../../services/verified_file_publication.dart';
import '../../services/patch_build_service.dart';
import '../../services/patch_build_store.dart';
import '../../services/database_service.dart';
import '../../widgets/base_game_card.dart';
import '../game_detail/game_detail_screen.dart';

Future<PortablePatchRecipe?> _pickRecipe() async {
  final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: false);
  final path = selected?.files.single.path;
  if (path == null) return null;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (bytes.length + chunk.length > PortablePatchRecipe.maxBytes) {
      throw const FormatException('portable_patch_too_large');
    }
    bytes.add(chunk);
  }
  return PortablePatchRecipe.decode(utf8.decode(bytes.takeBytes()));
}

String _recipeMessage(Object error) => switch (error) {
      FormatException(message: 'patch_recipe_output_conflict') =>
        'This recipe conflicts with an existing result. Nothing was replaced.',
      StateError() ||
      FileSystemException() =>
        'Shared recipes are unavailable. Choose or reconnect metadata storage in Settings.',
      _ => 'That file is not a supported G-Shop patch recipe.',
    };

Future<void> _shareRecipe(PortablePatchRecipe recipe) async {
  final json = PortablePatchRecipe.decode(recipe.encode()).encode();
  final scratch =
      await (await getTemporaryDirectory()).createTemp('rshop_recipe_');
  final file = File(p.join(
      scratch.path, 'rshop-recipe-${recipe.recipe.id.substring(0, 12)}.json'));
  try {
    await file.writeAsString(json, flush: true);
    // Android's pinned share_plus copies this file into its own grant cache
    // before opening the chooser; it owns that copy's recipient lifecycle.
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
        subject: recipe.title);
  } finally {
    if (await file.exists()) await file.delete();
    await scratch.delete();
  }
}

String patchCatalogueFailureMessage(Object error) => switch (error) {
      DriveAuthorizationException(issue: DriveAuthorizationIssue.unavailable) ||
      DriveApiException(issue: DriveApiIssue.unavailable) ||
      DriveTransferException(issue: DriveTransferIssue.unavailable) =>
        'Could not connect to Google Drive. Check your connection, then retry.',
      DriveAuthorizationException() =>
        'Check your Google Drive connection in Settings, then retry.',
      DriveTransferException(issue: DriveTransferIssue.sourceChanged) =>
        'This patch catalogue changed in Drive. Sync the console, then retry.',
      FormatException() => 'This patch index is not supported.',
      _ => 'Could not read this patch catalogue. Try again.',
    };

class PatchGameData {
  final DrivePatchCatalogue? catalogue;
  final IndexedPatchGame game;
  final List<IndexedRomPatch> patches;
  final Map<String, GameItem> bases;
  final String sourceId;
  final bool portableOnly;
  const PatchGameData(this.catalogue, this.game, this.patches, this.bases,
      {required this.sourceId, this.portableOnly = false});
  String get key => '$sourceId:${game.sourceGameId}';
}

class PatchLibraryScreen extends ConsumerStatefulWidget {
  final SystemModel system;
  final String targetFolder;
  final List<ProviderConfig> providers;
  final List<GameItem> collection;
  final DriveRuntime? runtime;
  final PatchBuildStore? buildStore;
  const PatchLibraryScreen(
      {super.key,
      required this.system,
      required this.targetFolder,
      required this.providers,
      required this.collection,
      this.runtime,
      this.buildStore});
  @override
  ConsumerState<PatchLibraryScreen> createState() => _PatchLibraryState();
}

class _PatchLibraryState extends ConsumerState<PatchLibraryScreen>
    with ConsoleScreenMixin {
  final _cancellation = CancelToken();
  final _rows = <PatchGameData>[];
  final _pending = <(DrivePatchCatalogue, IndexedPatchGame)>[];
  final _focus = <String, FocusNode>{};
  var _cursor = 0;
  bool _loading = true;
  bool _initialized = false;
  String? _notice;
  String? _focused;
  late final PatchBuildStore _store;
  bool _importing = false;
  @override
  String get routeId => 'patch-library-${widget.system.id}';
  @override
  void initState() {
    super.initState();
    _store = widget.buildStore ??
        PatchBuildStore(DatabaseService().database,
            sharedStore: ref.read(sharedMetadataStoreProvider));
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _cancellation.cancel();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (!_loading && mounted) {
      setState(() {
        _loading = true;
        _notice = null;
      });
    }
    try {
      if (!_initialized) {
        _seedSaved(await _store.forPlatform(widget.system.id));
        if (_store.sharedIssue != null) {
          _notice = _recipeMessage(StateError('shared'));
        }
        if (mounted) setState(() {});
        _pending.clear();
        for (final provider
            in widget.providers.where((p) => p.type == ProviderType.drive)) {
          final catalogue =
              DrivePatchCatalogue(provider, runtime: widget.runtime);
          try {
            _pending.addAll((await catalogue.games(_cancellation))
                .map((game) => (catalogue, game)));
          } on DriveCatalogueException catch (error) {
            if (error.code != 'ambiguousOrMissingDependency') rethrow;
            // No patch index in this source is not an empty successful scan of
            // some other source; existing indexed sources remain in the list.
          }
        }
        _pending.sort((a, b) =>
            a.$2.title.toLowerCase().compareTo(b.$2.title.toLowerCase()));
        _initialized = true;
      }
      final end = (_cursor + 12).clamp(0, _pending.length);
      while (_cursor < end) {
        final (catalogue, game) = _pending[_cursor];
        final patches = await catalogue.patches(game, _cancellation);
        await catalogue.rememberBases(game, patches);
        final bases = <String, GameItem>{};
        for (final patch in patches) {
          for (final base in patch.bases) {
            if (bases.containsKey(base.relativePath.value)) continue;
            try {
              final artifact = await catalogue.resolve(base.relativePath);
              final existing = widget.collection
                  .where((entry) => entry.remoteArtifact?.id == artifact.id);
              if (existing.isNotEmpty) {
                bases[base.relativePath.value] = existing.first;
              }
            } on DriveCatalogueException catch (error) {
              if (error.code != 'ambiguousOrMissingDependency') rethrow;
            }
          }
        }
        _cursor++;
        if (bases.isNotEmpty && mounted) {
          final data = PatchGameData(catalogue, game, patches, bases,
              sourceId: catalogue.config.sourceId!);
          setState(() {
            _rows.removeWhere((other) =>
                other.key == data.key ||
                (other.portableOnly &&
                    other.game.sourceGameId == game.sourceGameId));
            _rows.add(data);
            _rows.sort((a, b) => a.game.title
                .toLowerCase()
                .compareTo(b.game.title.toLowerCase()));
          });
        }
        debugPrint('Patch page progress: checked=$_cursor '
            'total=${_pending.length} games=${_rows.length}');
      }
    } catch (error) {
      if (mounted && !_cancellation.isCancelled) {
        // Report only fixed error codes, never an authenticated URL, account,
        // provider response body or private catalogue paths.
        final code = switch (error) {
          DriveCatalogueException(:final code) => code,
          DriveApiException(:final issue) => issue.name,
          DriveTransferException(:final issue) => issue.name,
          DriveAuthorizationException(:final issue) => issue.name,
          FormatException(:final message)
              when RegExp(r'^[a-z_]{1,64}$').hasMatch(message) =>
            message,
          FormatException() => 'invalid_index',
          _ => 'unexpected',
        };
        debugPrint('Patch catalogue failed: cursor=$_cursor '
            'type=${error.runtimeType} code=$code');
        setState(() => _notice = patchCatalogueFailureMessage(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _seedSaved(List<Map<String, dynamic>> saved) {
    for (final row in saved) {
      final sourceId = row['providerSourceId'] as String?;
      final indexPath = row['gameIndexPath'] as String?;
      if (sourceId == null || indexPath == null) continue;
      final portable = row['state'] == 'recipe';
      final data = PatchGameData(
          null,
          IndexedPatchGame(row['sourceGameId'] as String,
              row['gameTitle'] as String, PatchRelativePath(indexPath)),
          const [],
          const {},
          sourceId: sourceId,
          portableOnly: portable);
      if (!_rows.any((other) =>
          other.key == data.key ||
          (portable && other.game.sourceGameId == data.game.sourceGameId))) {
        _rows.add(data);
      }
    }
  }

  Future<void> _importRecipe() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final portable = await _pickRecipe();
      if (portable == null || !mounted) return;
      if (portable.recipe.platformId != widget.system.id) {
        setState(
            () => _notice = 'Open this recipe in its console’s Patches page.');
        return;
      }
      await _store.importRecipe(portable);
      final saved = await _store.forPlatform(widget.system.id);
      if (mounted) {
        setState(() {
          _seedSaved(saved);
          _notice = 'Recipe imported. Open its game to check requirements.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = _recipeMessage(error));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(PatchGameData row) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => PatchGameScreen(
                    system: widget.system,
                    targetFolder: widget.targetFolder,
                    row: row,
                    collection: widget.collection,
                    catalogues: [
                      for (final provider in widget.providers)
                        if (provider.type == ProviderType.drive)
                          DrivePatchCatalogue(provider, runtime: widget.runtime)
                    ])));
  }

  @override
  Widget build(BuildContext context) => buildWithActions(
      Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar:
              AppBar(title: Text('${widget.system.name} · Patches'), actions: [
            IconButton(
                tooltip: 'Reset launch suggestions',
                onPressed: () async {
                  await ref
                      .read(storageServiceProvider)
                      .resetPatchLaunchChoices(widget.system.id);
                  if (mounted)
                    setState(() => _notice =
                        'Launch suggestions restored for this console.');
                },
                icon: const Icon(Icons.restore)),
            IconButton(
                tooltip: 'Import recipe',
                onPressed: _importing ? null : _importRecipe,
                icon: const Icon(Icons.file_open_outlined))
          ]),
          body: Column(children: [
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.extension_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          '${_rows.length} games · $_cursor/${_pending.length} checked')),
                  if (_loading)
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ])),
            if (_notice != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Expanded(child: Text(_notice!)),
                    IconButton(
                        tooltip: 'Retry',
                        onPressed: _loading ? null : _loadMore,
                        icon: const Icon(Icons.refresh))
                  ])),
            Expanded(
                child: _rows.isEmpty && !_loading
                    ? const Center(
                        child: Text(
                            'No indexed patches match games in this collection.'))
                    : LayoutBuilder(
                        builder: (context, bounds) => GridView.builder(
                            padding: const EdgeInsets.all(24),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: (bounds.maxWidth / 260)
                                        .floor()
                                        .clamp(2, 6),
                                    crossAxisSpacing: 18,
                                    mainAxisSpacing: 18,
                                    childAspectRatio: 0.8),
                            itemCount: _rows.length,
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final key = row.key;
                              final base = row.bases.values.firstOrNull;
                              final focus = _focus.putIfAbsent(
                                  key,
                                  () => FocusNode(
                                      debugLabel: 'Patch ${row.game.title}'));
                              return Focus(
                                  onFocusChange: (value) {
                                    if (value && mounted) {
                                      setState(() => _focused = key);
                                    }
                                  },
                                  child: BaseGameCard(
                                      displayName: row.game.title,
                                      systemId: widget.system.id,
                                      gameIdentity: base?.identityKey ?? key,
                                      coverUrls: const [],
                                      cachedUrl: base?.cachedCoverUrl,
                                      isInstalled: false,
                                      isSelected: _focused == key,
                                      accentColor: widget.system.accentColor,
                                      focusNode: focus,
                                      showRating: false,
                                      providerLabel: 'Patches',
                                      onTap: () => _open(row)));
                            }))),
            if (_cursor < _pending.length && !_loading && _notice == null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more),
                      label: const Text('More games'))),
          ])),
      localFocusScope: true,
      materialControls: true);
}

class PatchGameScreen extends ConsumerStatefulWidget {
  final bool selectForLaunch;
  final List<IndexedPatchBase>? launchBases;
  final SystemModel system;
  final String targetFolder;
  final PatchGameData row;
  final PatchBuildService? service;
  final List<DrivePatchCatalogue> catalogues;
  final List<GameItem> collection;
  const PatchGameScreen(
      {super.key,
      required this.system,
      required this.targetFolder,
      required this.row,
      this.service,
      this.selectForLaunch = false,
      this.launchBases,
      this.catalogues = const [],
      this.collection = const []});
  @override
  ConsumerState<PatchGameScreen> createState() => _PatchGameState();
}

class _PatchGameState extends ConsumerState<PatchGameScreen>
    with ConsoleScreenMixin {
  late final PatchBuildService _service;
  int _tab = 0, _patch = 0, _payload = 0, _base = 0;
  bool _busy = false, _leaving = false, _prepareEarthBound = false;
  String? _notice;
  String _phase = '';
  int _completed = 0, _total = 0;
  List<Map<String, dynamic>> _builds = [];
  CancelToken? _portableCancellation;
  Future<void>? _portableOperation;
  bool _sharing = false, _importing = false;
  @override
  String get routeId =>
      'patch-game-${widget.system.id}-${widget.row.game.sourceGameId}';
  IndexedRomPatch? get _selected =>
      widget.row.patches.isEmpty ? null : widget.row.patches[_patch];
  PatchChain? get _chain {
    final selected = _selected;
    if (selected == null || selected.payloads.isEmpty) return null;
    try {
      return PatchChain.resolve(
          widget.row.patches, selected, selected.payloads[_payload]);
    } on FormatException {
      return null;
    }
  }

  bool get _needsPreparation => _chain?.steps.any((step) => step.payload.format == PatchFormat.ebp) ?? false;
  List<IndexedPatchBase> get _bases =>
      _chain?.bases
          .where(
              (base) => widget.row.bases.containsKey(base.relativePath.value))
          .toList() ??
      [];
  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        PatchBuildService(
            runtime: widget.row.catalogue?.runtime,
            sharedStore: ref.read(sharedMetadataStoreProvider));
    if (widget.row.catalogue == null) _tab = 1;
    unawaited(_reloadBuilds());
  }

  Future<void> _reloadBuilds() async {
    final builds = await _service.store
        .forGame(widget.system.id, widget.row.game.sourceGameId);
    if (mounted) {
      setState(() {
        _builds = widget.launchBases == null
            ? builds
            : builds.where((row) {
                final recipe = PatchRecipe.fromJson(
                    (row['recipe'] as Map).cast<String, dynamic>());
                return widget.launchBases!.any((b) =>
                    b.sizeBytes == recipe.base.sizeBytes &&
                    b.checksums.length == recipe.base.checksums.length &&
                    b.checksums.entries
                        .every((e) => recipe.base.checksums[e.key] == e.value));
              }).toList();
        if (_service.store.sharedIssue != null) {
          _notice = _recipeMessage(StateError('shared'));
        }
      });
    }
  }

  void _tabTo(int value) {
    if (_busy) return;
    setState(() => _tab = value);
  }

  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    _portableCancellation?.cancel();
    if (_busy) await _service.cancel();
    try {
      await _portableOperation;
    } catch (_) {/* Original action owns its result. */}
    if (mounted) {
      setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _cancel() async {
    _portableCancellation?.cancel();
    await _service.cancel();
  }

  Future<void> _share(Map<String, dynamic> row) async {
    if (_busy || _sharing) return;
    setState(() => _sharing = true);
    try {
      final portable = row['portable'] == null
          ? PortablePatchRecipe.fromBuild(row)
          : PortablePatchRecipe.decode(jsonEncode(row['portable']));
      await _shareRecipe(portable);
    } catch (_) {
      if (mounted) {
        setState(() => _notice =
            'Could not share this recipe. No game files were shared.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _importRecipe() async {
    if (_busy || _importing) return;
    setState(() => _importing = true);
    try {
      final portable = await _pickRecipe();
      if (portable == null || !mounted) return;
      if (portable.recipe.platformId != widget.system.id ||
          portable.sourceGameId != widget.row.game.sourceGameId) {
        setState(() => _notice =
            'Use the console’s Patches page to import a recipe for another game.');
        return;
      }
      await _service.store.importRecipe(portable);
      await _reloadBuilds();
      if (mounted) {
        setState(() {
          _tab = 1;
          _notice = 'Recipe imported. Check its requirements before building.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = _recipeMessage(error));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _buildPortable(Map<String, dynamic> row) {
    if (_busy) return Future.value();
    final cancellation = _portableCancellation = CancelToken();
    setState(() {
      _busy = true;
      _notice = null;
      _phase = 'Checking requirements';
      _total = 0;
    });
    final operation = _resolveAndBuildPortable(row, cancellation);
    _portableOperation = operation;
    return operation.whenComplete(() {
      if (identical(_portableOperation, operation)) _portableOperation = null;
      if (mounted && !_leaving) setState(() => _busy = false);
    });
  }

  Future<void> _resolveAndBuildPortable(
      Map<String, dynamic> row, CancelToken cancellation) async {
    try {
      final portable = PortablePatchRecipe.decode(jsonEncode(row['portable']));
      final missing = <String>{};
      DrivePatchCatalogue? selected;
      ResolvedPatchRecipe? resolved;
      final catalogues = [
        if (widget.row.catalogue != null) widget.row.catalogue!,
        ...widget.catalogues.where((item) =>
            item.config.sourceId != widget.row.catalogue?.config.sourceId)
      ];
      for (final catalogue in catalogues) {
        if (cancellation.isCancelled) return;
        try {
          final result = await catalogue.resolveRecipe(portable, cancellation);
          if (result.resolved != null) {
            selected = catalogue;
            resolved = result.resolved;
            missing.clear();
            break;
          }
          missing.addAll(result.missing);
        } on DriveCatalogueException catch (error) {
          if (error.code != 'ambiguousOrMissingDependency') rethrow;
        }
      }
      if (resolved == null) {
        missing.addAll(['Configured original game', 'Exact patch resources']);
      }
      if (selected != null && resolved != null) {
        final artifact = await selected.resolve(resolved.base.relativePath);
        if (!widget.collection
                .any((game) => game.remoteArtifact?.id == artifact.id) &&
            !widget.row.bases.values
                .any((game) => game.remoteArtifact?.id == artifact.id)) {
          missing.add('Original game in this collection');
        }
      }
      final engine = await _service.native.invokeMethod<String>('revision');
      if (engine != portable.recipe.engineRevision) {
        missing.add('Matching patch engine version');
      }
      if (cancellation.isCancelled || !mounted || _leaving) return;
      final confirmed = await showConsoleDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Recipe requirements'),
                content: SizedBox(
                    width: 480,
                    child: ListView(shrinkWrap: true, children: [
                      ListTile(
                          leading: const Icon(Icons.videogame_asset_outlined),
                          title: Text(portable.gameTitle),
                          subtitle: Text(
                              'Expected original · ${portable.recipe.base.sizeBytes} bytes · ${portable.recipe.base.checksums.keys.join(', ')}')),
                      for (final step in portable.recipe.steps)
                        ListTile(
                            leading: const Icon(Icons.extension_outlined),
                            title: Text('${step.source} · ${step.sourceId}'),
                            subtitle: Text(
                                '${step.format.name.toUpperCase()} · ${step.version}')),
                      for (final requirement in missing)
                        ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(requirement),
                            subtitle: const Text('Not available')),
                      if (missing.isEmpty)
                        const ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('Ready to build')),
                    ])),
                actions: [
                  TextButton(
                      autofocus: true,
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Close')),
                  if (missing.isEmpty)
                    FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Build'))
                ],
              ));
      if (confirmed != true ||
          selected == null ||
          resolved == null ||
          !mounted ||
          _leaving ||
          cancellation.isCancelled) {
        return;
      }
      final result = await _service.build(
          catalogue: selected,
          indexedGame: resolved.game,
          patch: resolved.patch,
          availablePatches: resolved.availablePatches,
          payload: resolved.payload,
          base: resolved.base,
          system: widget.system,
          targetFolder: widget.targetFolder,
          preprocessing: portable.recipe.preprocessing,
          importedRecipe: portable,
          onProgress: (phase, completed, total) {
            if (mounted) {
              setState(() {
                _phase = phase;
                _completed = completed;
                _total = total;
              });
            }
          });
      await _reloadBuilds();
      if (mounted) {
        ref.invalidate(installedFilesProvider);
        if (widget.selectForLaunch) {
          Navigator.pop(context, result);
          return;
        }
        setState(() => _notice = result.reused
            ? 'This build is already installed.'
            : 'Patched game is ready to play.');
      }
    } catch (error) {
      if (mounted && !_leaving && !cancellation.isCancelled) {
        setState(() => _notice = error is PatchBuildException
            ? _message(error)
            : patchCatalogueFailureMessage(error));
      }
    }
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        TabLeftIntent: CallbackAction<TabLeftIntent>(onInvoke: (_) {
          _tabTo(1 - _tab);
          return null;
        }),
        TabRightIntent: CallbackAction<TabRightIntent>(onInvoke: (_) {
          _tabTo(1 - _tab);
          return null;
        }),
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          unawaited(_back());
          return null;
        }),
      };
  Future<void> _build({String? retryBuildId}) async {
    final patch = _selected;
    if (_busy ||
        patch == null ||
        patch.payloads.isEmpty ||
        _bases.isEmpty ||
        widget.row.catalogue == null) {
      return;
    }
    final payload = patch.payloads[_payload];
    if (_needsPreparation && !_prepareEarthBound) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await _service.build(
          catalogue: widget.row.catalogue!,
          indexedGame: widget.row.game,
          patch: patch,
          availablePatches: widget.row.patches,
          payload: payload,
          base: _bases[_base],
          system: widget.system,
          targetFolder: widget.targetFolder,
          retryBuildId: retryBuildId,
          preprocessing:
              _needsPreparation ? ['ebp-canonical-base'] : [],
          onProgress: (phase, completed, total) {
            if (mounted) {
              setState(() {
                _phase = phase;
                _completed = completed;
                _total = total;
              });
            }
          });
      await _reloadBuilds();
      if (mounted) ref.invalidate(installedFilesProvider);
      if (mounted) {
        if (widget.selectForLaunch) {
          Navigator.pop(context, result);
          return;
        }
        setState(() {
          _tab = 1;
          _notice = result.reused
              ? 'This build is already installed.'
              : 'Patched game is ready to play.';
        });
      }
    } catch (error) {
      if (mounted && !_leaving) setState(() => _notice = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    final code = error is PatchBuildException ? error.code : '';
    return switch (code) {
      'cancelled' => 'Build cancelled. You can retry from My builds.',
      'busy' => 'Another patch build is running.',
      'recipe_output_conflict' =>
        'The result differs from this recipe. Your existing games were preserved.',
      'recipe_changed' =>
        'The patch or original game changed. Create a new build instead.',
      'input_fingerprint_mismatch' ||
      'input_size_mismatch' =>
        'The original game or patch does not match its index. Sync the console and try again.',
      'scratch_unavailable' ||
      'rebuild_required' =>
        'Build files are missing. Create a new build from Available patches.',
      _ => 'The build could not finish. Your original game was not changed.',
    };
  }

  Future<void> _retry(Map<String, dynamic> row) async {
    if (_busy) return;
    if (row['outputArtifact'] == null) {
      final recipe =
          PatchRecipe.fromJson((row['recipe'] as Map).cast<String, dynamic>());
      for (var i = 0; i < widget.row.patches.length; i++) {
        final patch = widget.row.patches[i];
        if (patch.payloads.isEmpty) continue;
        final PatchChain chain;
        try {
          chain = PatchChain.resolve(
              widget.row.patches, patch, patch.payloads.first);
        } on FormatException {
          continue;
        }
        final bases = chain.bases
            .where((b) => widget.row.bases.containsKey(b.relativePath.value))
            .toList();
        for (var j = 0; j < patch.payloads.length; j++) {
          for (var k = 0; k < bases.length; k++) {
            final candidate = PatchRecipe(
                platformId: widget.system.id,
                base: bases[k],
                steps: PatchChain.resolve(
                        widget.row.patches, patch, patch.payloads[j])
                    .recipeSteps,
                engineRevision: recipe.engineRevision,
                preprocessing: recipe.preprocessing);
            if (candidate.id != recipe.id) continue;
            setState(() {
              _patch = i;
              _payload = j;
              _base = k;
              _prepareEarthBound =
                  recipe.preprocessing.contains('ebp-canonical-base');
            });
            await _build(retryBuildId: row['buildId'] as String);
            return;
          }
        }
      }
      setState(() => _notice =
          'The exact patch is not currently available. Sync the console to check again.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
      _phase = 'Saving patched game';
      _total = 0;
    });
    try {
      await _service.resumePublication(row['buildId'] as String);
      if (mounted) ref.invalidate(installedFilesProvider);
      await _reloadBuilds();
      if (mounted) setState(() => _notice = 'Patched game is ready to play.');
    } catch (error) {
      if (mounted && !_leaving) setState(() => _notice = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _details(Map<String, dynamic> row) => showConsoleDialog<void>(
      context: context,
      builder: (context) {
        final recipe = PatchRecipe.fromJson(
            (row['recipe'] as Map).cast<String, dynamic>());
        return AlertDialog(
            title: Text(
                row['state'] == 'recipe' ? 'Recipe details' : 'Build details'),
            content: SizedBox(
                width: 480,
                child: ListView(shrinkWrap: true, children: [
                  for (final step in recipe.steps)
                    ListTile(
                        leading: const Icon(Icons.extension_outlined),
                        title: Text('${step.source} · ${step.sourceId}'),
                        subtitle: Text(
                            '${step.format.name.toUpperCase()} · ${step.version.isEmpty ? "No version supplied" : step.version}')),
                  ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: const Text('Original game'),
                      subtitle: Text(p.posix.basename(
                          recipe.base.archiveMember?.value ??
                              recipe.base.relativePath.value))),
                  ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(row['state'] as String),
                      subtitle: Text(row['state'] == 'recipe'
                          ? 'Instructions only. No game files were imported.'
                          : row['shareIssue'] == 'patch_recipe_output_conflict'
                              ? 'The shared recipe has a different verified result. Neither copy was replaced.'
                              : row['scratchCleanup'] == 'pending'
                                  ? 'Temporary-file cleanup is pending.'
                                  : 'Original game preserved.')),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ]);
      });

  Future<void> _play(Map<String, dynamic> row) async {
    if (_busy) return;
    try {
      final recipe =
          PatchRecipe.fromJson((row['recipe'] as Map).cast<String, dynamic>());
      final result = await _service.existing(recipe, CancelToken());
      if (!mounted) return;
      if (result == null) {
        setState(() => _notice =
            'This copy is missing or changed. Build a new copy from Available patches.');
        await _reloadBuilds();
        return;
      }
      if (widget.selectForLaunch) {
        Navigator.pop(context, result);
        return;
      }
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => GameDetailScreen(
                  game: result.game,
                  variants: [result.game],
                  system: widget.system,
                  targetFolder: result.targetRoot,
                  isLocalOnly: true)));
    } catch (error) {
      if (mounted) setState(() => _notice = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final bases = _bases;
    return buildWithActions(
        PopScope(
            canPop: !_busy,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) unawaited(_back());
            },
            child: Scaffold(
                backgroundColor: AppTheme.backgroundColor,
                appBar: AppBar(title: Text(widget.row.game.title), actions: [
                  IconButton(
                      tooltip: 'Import recipe',
                      onPressed: _busy || _importing ? null : _importRecipe,
                      icon: const Icon(Icons.file_open_outlined))
                ]),
                body: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(
                                value: 0,
                                icon: Icon(Icons.extension_outlined),
                                label: Text('Available patches')),
                            ButtonSegment(
                                value: 1,
                                icon: Icon(Icons.inventory_2_outlined),
                                label: Text('My builds')),
                          ],
                          selected: {
                            _tab
                          },
                          onSelectionChanged: _busy
                              ? null
                              : (values) => _tabTo(values.single))),
                  if (_notice != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        child: Text(_notice!)),
                  Expanded(
                      child: _tab == 1
                          ? _builds.isEmpty
                              ? const Center(child: Text('No builds yet.'))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(24),
                                  itemCount: _builds.length,
                                  itemBuilder: (context, index) {
                                    final row = _builds[index];
                                    final ready = row['state'] == 'ready';
                                    final portable = row['state'] == 'recipe';
                                    return ListTile(
                                        leading: Icon(ready
                                            ? Icons.sd_card_outlined
                                            : Icons.info_outline),
                                        title: Text(row['title'] as String),
                                        subtitle: Text(ready
                                            ? row['shareIssue'] == null
                                                ? 'Ready to play'
                                                : row['shareIssue'] ==
                                                        'patch_recipe_output_conflict'
                                                    ? 'Ready to play · Recipe conflict'
                                                    : 'Ready to play · Recipe backup pending'
                                            : portable
                                                ? 'Saved recipe · Not installed'
                                                : 'Build not available'),
                                        trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (ready || portable)
                                                IconButton(
                                                    tooltip: 'Share recipe',
                                                    onPressed: _busy || _sharing
                                                        ? null
                                                        : () => _share(row),
                                                    icon: const Icon(
                                                        Icons.share_outlined)),
                                              IconButton(
                                                  tooltip: 'Build details',
                                                  onPressed: _busy
                                                      ? null
                                                      : () => _details(row),
                                                  icon: const Icon(
                                                      Icons.info_outline)),
                                              if (ready)
                                                IconButton(
                                                    tooltip: 'Play',
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _play(row),
                                                    icon: const Icon(
                                                        Icons.play_arrow))
                                              else if (portable)
                                                IconButton(
                                                    tooltip:
                                                        'Check requirements',
                                                    onPressed: _busy
                                                        ? null
                                                        : () =>
                                                            _buildPortable(row),
                                                    icon: const Icon(Icons
                                                        .fact_check_outlined))
                                              else if (row['state'] ==
                                                      'failed' ||
                                                  row['state'] == 'cancelled' ||
                                                  row['state'] == 'building' ||
                                                  row['state'] == 'publishing')
                                                IconButton(
                                                    tooltip: 'Retry',
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _retry(row),
                                                    icon: const Icon(
                                                        Icons.refresh)),
                                            ]),
                                        onTap: _busy
                                            ? null
                                            : ready
                                                ? () => _play(row)
                                                : () => _details(row));
                                  })
                          : LayoutBuilder(
                              builder: (context, bounds) => Row(children: [
                                    SizedBox(
                                        width: (bounds.maxWidth * 0.38)
                                            .clamp(180, 400),
                                        child: ListView.builder(
                                            padding: const EdgeInsets.all(12),
                                            itemCount:
                                                widget.row.patches.length,
                                            itemBuilder: (context, index) {
                                              final patch =
                                                  widget.row.patches[index];
                                              return ListTile(
                                                  selected: _patch == index,
                                                  enabled: !_busy,
                                                  leading: Icon(patch.section ==
                                                          'translations'
                                                      ? Icons.translate
                                                      : Icons.extension),
                                                  title: Text(patch.title,
                                                      maxLines: 2,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                  subtitle: Text(patch
                                                          .version.isEmpty
                                                      ? 'Version not supplied'
                                                      : patch.version),
                                                  onTap: () => setState(() {
                                                        _patch = index;
                                                        _payload = _base = 0;
                                                        _prepareEarthBound =
                                                            false;
                                                      }));
                                            })),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                        child: selected == null
                                            ? const Center(
                                                child:
                                                    Text('No patches listed.'))
                                            : SingleChildScrollView(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(selected.title,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleLarge),
                                                      const SizedBox(
                                                          height: 10),
                                                      Text(selected.description,
                                                          maxLines: 5,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                      if (selected.requires !=
                                                          null)
                                                        if (_chain == null)
                                                          const Text(
                                                              'A required patch version is missing, ambiguous or cyclic. This build is unavailable.')
                                                        else
                                                          Text(
                                                              'Apply in order: ${_chain!.steps.map((s) => '${s.patch.title} ${s.patch.version}').join(' → ')}'),
                                                      const SizedBox(
                                                          height: 14),
                                                      if (selected
                                                          .payloads.isEmpty)
                                                        const Text(
                                                            'No supported patch file in this package.'),
                                                      if (bases.isEmpty)
                                                        const Text(
                                                            'The required original game is not in this collection.'),
                                                      if (selected
                                                          .payloads.isNotEmpty)
                                                        DropdownButtonFormField<
                                                                int>(
                                                            key: ValueKey(
                                                                'payload-$_patch'),
                                                            initialValue:
                                                                _payload,
                                                            decoration:
                                                                const InputDecoration(
                                                                    labelText:
                                                                        'Patch file'),
                                                            isExpanded: true,
                                                            items: [
                                                              for (var i = 0;
                                                                  i <
                                                                      selected
                                                                          .payloads
                                                                          .length;
                                                                  i++)
                                                                DropdownMenuItem(
                                                                    value: i,
                                                                    child: Text(
                                                                        p.posix.basename(selected
                                                                            .payloads[
                                                                                i]
                                                                            .relativePath),
                                                                        overflow:
                                                                            TextOverflow.ellipsis))
                                                            ],
                                                            onChanged: _busy
                                                                ? null
                                                                : (index) =>
                                                                    setState(
                                                                        () {
                                                                      _payload =
                                                                          index!;
                                                                      _prepareEarthBound =
                                                                          false;
                                                                    })),
                                                      if (bases.isNotEmpty)
                                                        DropdownButtonFormField<
                                                                int>(
                                                            key: ValueKey(
                                                                'base-$_patch'),
                                                            initialValue: _base,
                                                            decoration:
                                                                const InputDecoration(
                                                                    labelText:
                                                                        'Original game'),
                                                            isExpanded: true,
                                                            items: [
                                                              for (var i = 0;
                                                                  i <
                                                                      bases
                                                                          .length;
                                                                  i++)
                                                                DropdownMenuItem(
                                                                    value: i,
                                                                    child: Text(
                                                                        p.posix.basename(bases[i]
                                                                            .relativePath
                                                                            .value),
                                                                        overflow:
                                                                            TextOverflow.ellipsis))
                                                            ],
                                                            onChanged: _busy
                                                                ? null
                                                                : (index) =>
                                                                    setState(() =>
                                                                        _base =
                                                                            index!)),
                                                      if (_needsPreparation)
                                                        CheckboxListTile(
                                                            title: const Text(
                                                                'Prepare EarthBound base'),
                                                            subtitle: const Text(
                                                                'Records the format’s header and repair steps in this build.'),
                                                            value:
                                                                _prepareEarthBound,
                                                            onChanged: _busy
                                                                ? null
                                                                : (value) =>
                                                                    setState(() =>
                                                                        _prepareEarthBound =
                                                                            value!)),
                                                      const SizedBox(
                                                          height: 12),
                                                      const Text(
                                                          'The original bytes are checked before patching.'),
                                                    ]))),
                                  ]))),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        if (_busy) ...[
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(_phase),
                                LinearProgressIndicator(
                                    value: _total > 0
                                        ? _completed / _total
                                        : null),
                              ])),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                              onPressed: _cancel,
                              icon: const Icon(Icons.stop),
                              label: const Text('Cancel')),
                        ] else if (_tab == 0) ...[
                          const Spacer(),
                          FilledButton.icon(
                              onPressed: selected == null ||
                                      selected.payloads.isEmpty ||
                                      bases.isEmpty ||
                                      (_needsPreparation &&
                                          !_prepareEarthBound)
                                  ? null
                                  : _build,
                              icon: const Icon(Icons.build_outlined),
                              label: Text(widget.selectForLaunch
                                  ? 'Build and play'
                                  : 'Build')),
                        ],
                      ])),
                ]))),
        localFocusScope: true,
        materialControls: true);
  }
}
