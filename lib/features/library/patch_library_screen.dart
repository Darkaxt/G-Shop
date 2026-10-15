import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../models/config/provider_config.dart';
import '../../models/game_item.dart';
import '../../models/patch_catalogue.dart';
import '../../models/system_model.dart';
import '../../services/drive/drive_catalogue.dart';
import '../../services/drive/drive_authorization.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_media.dart';
import '../../services/drive/drive_patch_catalogue.dart';
import '../../services/drive/drive_runtime.dart';
import '../../providers/installed_files_provider.dart';
import '../../services/patch_build_publication.dart';
import '../../services/patch_build_service.dart';
import '../../services/patch_build_store.dart';
import '../../services/database_service.dart';
import '../../widgets/base_game_card.dart';
import '../game_detail/game_detail_screen.dart';

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
  const PatchGameData(this.catalogue, this.game, this.patches, this.bases,
      {required this.sourceId});
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
  @override
  String get routeId => 'patch-library-${widget.system.id}';
  @override
  void initState() {
    super.initState();
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
        final saved = await (widget.buildStore ??
                PatchBuildStore(DatabaseService().database))
            .forPlatform(widget.system.id);
        for (final row in saved) {
          final sourceId = row['providerSourceId'] as String?;
          final indexPath = row['gameIndexPath'] as String?;
          if (sourceId == null || indexPath == null) continue;
          final data = PatchGameData(
              null,
              IndexedPatchGame(row['sourceGameId'] as String,
                  row['gameTitle'] as String, PatchRelativePath(indexPath)),
              const [],
              const {},
              sourceId: sourceId);
          if (!_rows.any((other) => other.key == data.key)) _rows.add(data);
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
            _rows.removeWhere((other) => other.key == data.key);
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

  Future<void> _open(PatchGameData row) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => PatchGameScreen(
                system: widget.system,
                targetFolder: widget.targetFolder,
                row: row)));
  }

  @override
  Widget build(BuildContext context) => buildWithActions(
      Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(title: Text('${widget.system.name} · Patches')),
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
  final SystemModel system;
  final String targetFolder;
  final PatchGameData row;
  final PatchBuildService? service;
  const PatchGameScreen(
      {super.key,
      required this.system,
      required this.targetFolder,
      required this.row,
      this.service});
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
  @override
  String get routeId =>
      'patch-game-${widget.system.id}-${widget.row.game.sourceGameId}';
  IndexedRomPatch? get _selected =>
      widget.row.patches.isEmpty ? null : widget.row.patches[_patch];
  List<IndexedPatchBase> get _bases =>
      _selected?.bases
          .where(
              (base) => widget.row.bases.containsKey(base.relativePath.value))
          .toList() ??
      [];
  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        PatchBuildService(runtime: widget.row.catalogue?.runtime);
    if (widget.row.catalogue == null) _tab = 1;
    unawaited(_reloadBuilds());
  }

  Future<void> _reloadBuilds() async {
    final builds = await _service.store
        .forGame(widget.system.id, widget.row.game.sourceGameId);
    if (mounted) setState(() => _builds = builds);
  }

  void _tabTo(int value) {
    if (_busy) return;
    setState(() => _tab = value);
  }

  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    if (_busy) await _service.cancel();
    if (mounted) {
      setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
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
    if (payload.format == PatchFormat.ebp && !_prepareEarthBound) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await _service.build(
          catalogue: widget.row.catalogue!,
          indexedGame: widget.row.game,
          patch: patch,
          payload: payload,
          base: _bases[_base],
          system: widget.system,
          targetFolder: widget.targetFolder,
          retryBuildId: retryBuildId,
          preprocessing:
              payload.format == PatchFormat.ebp ? ['ebp-canonical-base'] : [],
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
        final bases = patch.bases
            .where((b) => widget.row.bases.containsKey(b.relativePath.value))
            .toList();
        for (var j = 0; j < patch.payloads.length; j++) {
          for (var k = 0; k < bases.length; k++) {
            final candidate = PatchRecipe(
                platformId: widget.system.id,
                base: bases[k],
                steps: [PatchRecipeStep.fromPatch(patch, patch.payloads[j])],
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

  Future<void> _details(Map<String, dynamic> row) => showDialog<void>(
      context: context,
      builder: (context) {
        final recipe = PatchRecipe.fromJson(
            (row['recipe'] as Map).cast<String, dynamic>());
        return AlertDialog(
            title: const Text('Build details'),
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
                      subtitle: Text(row['scratchCleanup'] == 'pending'
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
                appBar: AppBar(title: Text(widget.row.game.title)),
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
                                    return ListTile(
                                        leading: Icon(ready
                                            ? Icons.sd_card_outlined
                                            : Icons.info_outline),
                                        title: Text(row['title'] as String),
                                        subtitle: Text(ready
                                            ? 'Ready to play'
                                            : 'Build not available'),
                                        trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
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
                                                      if (selected.payloads
                                                              .isNotEmpty &&
                                                          selected
                                                                  .payloads[
                                                                      _payload]
                                                                  .format ==
                                                              PatchFormat.ebp)
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
                              onPressed: _service.cancel,
                              icon: const Icon(Icons.stop),
                              label: const Text('Cancel')),
                        ] else if (_tab == 0) ...[
                          const Spacer(),
                          FilledButton.icon(
                              onPressed: selected == null ||
                                      selected.payloads.isEmpty ||
                                      bases.isEmpty ||
                                      (selected.payloads[_payload].format ==
                                              PatchFormat.ebp &&
                                          !_prepareEarthBound)
                                  ? null
                                  : _build,
                              icon: const Icon(Icons.build_outlined),
                              label: const Text('Build')),
                        ],
                      ])),
                ]))),
        localFocusScope: true,
        materialControls: true);
  }
}
