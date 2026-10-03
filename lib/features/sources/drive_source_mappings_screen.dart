import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/config/app_config.dart';
import '../../models/config/source.dart';
import '../../models/system_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/game_providers.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_runtime.dart';
import '../../services/library_platform_mapping.dart';

/// Maps systems to folder IDs already observed in the source's successfully
/// published catalogue. IDs cannot be typed or invented here.
class DriveSourceMappingsScreen extends ConsumerStatefulWidget {
  const DriveSourceMappingsScreen({
    super.key,
    required this.source,
    this.runtime,
  });

  final Source source;
  final DriveRuntime? runtime;

  @override
  ConsumerState<DriveSourceMappingsScreen> createState() =>
      _DriveSourceMappingsScreenState();
}

class _DriveSourceMappingsScreenState
    extends ConsumerState<DriveSourceMappingsScreen> {
  List<DriveFile>? _folders;
  final Map<String, String?> _selectedBySystem = {};
  final Map<String, String> _persistedBySystem = {};
  bool _busy = false;
  String? _error;

  DriveRuntime get _runtime => widget.runtime ?? DriveRuntime.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config =
        ref.read(bootstrappedConfigProvider).valueOrNull ?? AppConfig.empty;
    for (final system in config.systems) {
      _selectedBySystem[system.id] = system.manualMappings
          .where((mapping) => mapping.sourceId == widget.source.id)
          .firstOrNull
          ?.remotePath;
      final persisted = _selectedBySystem[system.id];
      if (persisted != null) _persistedBySystem[system.id] = persisted;
    }
    try {
      final folders = await _runtime.folders(widget.source);
      folders
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final suggestions = <String, List<DriveFile>>{};
      for (final folder in folders) {
        final mapped = LibraryPlatformMapping.resolve(folder.name);
        final systemId = mapped.activePlatformId;
        if (systemId != null) {
          suggestions.putIfAbsent(systemId, () => []).add(folder);
        }
      }
      for (final entry in suggestions.entries) {
        if (entry.value.length == 1 && _selectedBySystem[entry.key] == null) {
          _selectedBySystem[entry.key] = entry.value.single.id;
        }
      }
      if (!mounted) return;
      setState(() => _folders = folders);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Refresh this Drive source before mapping console folders.');
    }
  }

  Future<void> _save() async {
    final folders = _folders;
    if (folders == null) return;
    final observedIds = folders.map((folder) => folder.id).toSet();
    final mappings = <String, String>{};
    for (final entry in _selectedBySystem.entries) {
      final folderId = entry.value;
      if (folderId != null &&
          (observedIds.contains(folderId) ||
              _persistedBySystem[entry.key] == folderId)) {
        mappings[entry.key] = folderId;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final basePath = ref.read(storageServiceProvider).getRomPath() ??
          '/storage/emulated/0/ROMs';
      await ref.read(sourcesProvider.notifier).setMappingsForSource(
            widget.source.id,
            mappings,
            targetBasePath: basePath,
          );
      ref.invalidate(bootstrappedConfigProvider);
      ref.invalidate(gamesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed to save Drive folder mappings';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config =
        ref.watch(bootstrappedConfigProvider).valueOrNull ?? AppConfig.empty;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        foregroundColor: Colors.white,
        title: const Text('Map Drive folders'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _folders == null && _error == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'Choose only folders observed in the last successful Drive refresh. Empty selections disable this source for that system.',
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 18),
                      for (final system in SystemModel.supportedSystems)
                        _mappingRow(system.id, system.name),
                      for (final system in config.systems)
                        if (!SystemModel.supportedSystems
                            .any((known) => known.id == system.id))
                          _unsupportedExistingRow(system.id, system.name),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        style: AppTheme.primaryButtonStyle,
                        onPressed: _busy || _folders == null ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save mappings'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _mappingRow(String systemId, String fallbackName) {
    final folders = _folders ?? const <DriveFile>[];
    final supported = SystemModel.supportedSystems
        .where((system) => system.id == systemId)
        .firstOrNull;
    final selected = _selectedBySystem[systemId];
    final selectedIsObserved = folders.any((folder) => folder.id == selected);
    final selectedIsPersisted =
        selected != null && _persistedBySystem[systemId] == selected;
    final validSelected =
        selectedIsObserved || selectedIsPersisted ? selected : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: validSelected,
        dropdownColor: const Color(0xFF252525),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: supported?.name ?? fallbackName,
          labelStyle: const TextStyle(color: Colors.white70),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Not mapped'),
          ),
          if (selectedIsPersisted && !selectedIsObserved)
            DropdownMenuItem<String?>(
              value: selected,
              child: Text('Previously mapped · ${_shortId(selected)}'),
            ),
          for (final folder in folders)
            DropdownMenuItem<String?>(
              value: folder.id,
              child: Text('${folder.name} · ${_shortId(folder.id)}'),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() => _selectedBySystem[systemId] = value),
      ),
    );
  }

  Widget _unsupportedExistingRow(String systemId, String name) {
    final mapping = _persistedBySystem[systemId];
    if (mapping == null) return const SizedBox.shrink();
    return ListTile(
      enabled: false,
      leading: const Icon(Icons.info_outline, color: Colors.orangeAccent),
      title: Text(
        '$name ($systemId) — unsupported by this app',
        style: const TextStyle(color: Colors.white60),
      ),
      subtitle: Text(
        'Existing mapping preserved · ${_shortId(mapping)}',
        style: const TextStyle(color: Colors.white38),
      ),
    );
  }

  String _shortId(String id) => id.length <= 8 ? id : '${id.substring(0, 8)}…';
}
