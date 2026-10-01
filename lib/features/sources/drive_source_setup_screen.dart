import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/theme/app_theme.dart';
import '../../models/config/drive_source_config.dart';
import '../../models/config/source.dart';
import '../../providers/app_providers.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_authorization.dart';
import '../../services/drive/drive_catalogue.dart';
import '../../services/drive/drive_runtime.dart';

class DriveSourceConnection {
  final String accountId;
  final DriveCatalogueApi api;

  const DriveSourceConnection({required this.accountId, required this.api});
}

abstract interface class DriveSourceSetupConnector {
  Future<DriveSourceConnection> connect(String serverClientId);
}

class RuntimeDriveSourceSetupConnector implements DriveSourceSetupConnector {
  final DriveRuntime runtime;

  RuntimeDriveSourceSetupConnector({DriveRuntime? runtime})
      : runtime = runtime ?? DriveRuntime.instance;

  @override
  Future<DriveSourceConnection> connect(String serverClientId) async {
    final authorization = runtime.authorizationFor(serverClientId);
    final grant = await authorization.acquire(interactive: true);
    final temporary = DriveSourceConfig(
      accountId: grant.accountId,
      rootFolderId: 'root',
      serverClientId: serverClientId,
    );
    return DriveSourceConnection(
      accountId: grant.accountId,
      api: runtime.apiFor(temporary),
    );
  }
}

typedef DriveSourceSave = Future<void> Function(Source source);

/// Adds a Drive source through the normal Sources workflow.
///
/// The connector is injectable so widget tests never open native account UI.
/// Production supplies the process-wide Drive runtime connector. Folder
/// navigation is restricted to IDs returned below the observed root and never
/// accepts free-form IDs or paths.
class DriveSourceSetupScreen extends ConsumerStatefulWidget {
  const DriveSourceSetupScreen({
    super.key,
    this.connector,
    this.onSave,
    this.initialSource,
  });

  final DriveSourceSetupConnector? connector;
  final DriveSourceSave? onSave;
  final Source? initialSource;

  @override
  ConsumerState<DriveSourceSetupScreen> createState() =>
      _DriveSourceSetupScreenState();
}

class _DriveSourceSetupScreenState
    extends ConsumerState<DriveSourceSetupScreen> {
  static const int _maxFolderEntries = 5000;
  late final TextEditingController _name;
  late final TextEditingController _serverClientId;
  DriveSourceConnection? _connection;
  final List<DriveFile> _breadcrumbs = [];
  List<DriveFile> _children = const [];
  DriveFile? _selectedRoot;
  bool _busy = false;
  String? _error;
  final CancelToken _cancellation = CancelToken();

  DriveFile? get _currentFolder =>
      _breadcrumbs.isEmpty ? null : _breadcrumbs.last;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initialSource?.name ?? 'Google Drive',
    );
    _serverClientId = TextEditingController(
      text: widget.initialSource?.drive?.serverClientId ?? '',
    );
  }

  @override
  void dispose() {
    _cancellation.cancel('Drive source setup closed');
    _name.dispose();
    _serverClientId.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final clientId = _serverClientId.text.trim();
    if (clientId.isEmpty) {
      setState(() => _error = 'Public Web OAuth client ID is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final connector = widget.connector ?? RuntimeDriveSourceSetupConnector();
      final connection = await connector.connect(clientId);
      final root = await connection.api.getFile(
        'root',
        cancelToken: _cancellation,
      );
      if (!root.isFolder || root.id == 'root') {
        throw const DriveApiException(DriveApiIssue.invalidResponse);
      }
      final children = await _loadAllFolders(connection.api, root.id);
      if (!mounted) return;
      setState(() {
        _connection = connection;
        _breadcrumbs
          ..clear()
          ..add(root);
        _children = children;
        _selectedRoot = null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _connection = null;
        _breadcrumbs.clear();
        _children = const [];
        _selectedRoot = null;
        _error = _safeError(error);
      });
    }
  }

  Future<List<DriveFile>> _loadAllFolders(
    DriveCatalogueApi api,
    String parentId,
  ) async {
    final result = <DriveFile>[];
    final seenPageTokens = <String>{};
    String? pageToken;
    do {
      final page = await api.listChildren(
        parentId,
        pageToken: pageToken,
        foldersOnly: true,
        cancelToken: _cancellation,
      );
      for (final file in page.files) {
        if (!file.parents.contains(parentId)) {
          throw const DriveApiException(DriveApiIssue.invalidResponse);
        }
        result.add(file);
        if (result.length > _maxFolderEntries) {
          throw const DriveApiException(DriveApiIssue.invalidResponse);
        }
      }
      pageToken = page.nextPageToken;
      if (pageToken != null && !seenPageTokens.add(pageToken)) {
        throw const DriveApiException(DriveApiIssue.invalidPageToken);
      }
    } while (pageToken != null);
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> _openFolder(DriveFile folder) async {
    final connection = _connection;
    final current = _currentFolder;
    if (connection == null || current == null) return;
    if (!folder.isFolder || !folder.parents.contains(current.id)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final children = await _loadAllFolders(connection.api, folder.id);
      if (!mounted) return;
      setState(() {
        _breadcrumbs.add(folder);
        _children = children;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeError(error);
      });
    }
  }

  Future<void> _backTo(int index) async {
    final connection = _connection;
    if (connection == null || index < 0 || index >= _breadcrumbs.length) return;
    final folder = _breadcrumbs[index];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final children = await _loadAllFolders(connection.api, folder.id);
      if (!mounted) return;
      setState(() {
        _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
        _children = children;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeError(error);
      });
    }
  }

  Future<void> _save() async {
    final connection = _connection;
    final root = _selectedRoot;
    final name = _name.text.trim();
    final clientId = _serverClientId.text.trim();
    if (connection == null ||
        root == null ||
        name.isEmpty ||
        clientId.isEmpty) {
      return;
    }
    final source = Source(
      id: widget.initialSource?.id ??
          'src-drive-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: SourceType.drive,
      drive: DriveSourceConfig(
        accountId: connection.accountId,
        rootFolderId: root.id,
        serverClientId: clientId,
      ),
      priority: widget.initialSource?.priority ?? 5,
      enabled: widget.initialSource?.enabled ?? true,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final save = widget.onSave;
      if (save != null) {
        await save(source);
      } else {
        await ref
            .read(sourcesProvider.notifier)
            .addSourceWithMappings(source, const {});
      }
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop<Source?>(source);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed to save source';
      });
    }
  }

  String _safeError(Object error) {
    if (error is DriveApiException) return error.toString();
    if (error is DriveAuthorizationException) return error.toString();
    if (error is DriveCatalogueException) return error.toString();
    return 'Google Drive setup failed';
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentFolder;
    final canSave = !_busy &&
        _connection != null &&
        _selectedRoot != null &&
        _name.text.trim().isNotEmpty &&
        _serverClientId.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        foregroundColor: Colors.white,
        title: const Text('Add Google Drive source'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              key: ValueKey(current?.id),
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Setup required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Create a public Web OAuth client ID for this fork, then connect your account. Google grants read-only access to the entire selected account; the chosen library folder is an app-enforced boundary, not a folder-scoped OAuth permission.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('drive_source_name'),
                  controller: _name,
                  enabled: !_busy,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Source name',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('drive_server_client_id'),
                  controller: _serverClientId,
                  enabled: !_busy && _connection == null,
                  autocorrect: false,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Public Web OAuth client ID',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(Icons.login),
                  label: Text(_connection == null ? 'Connect' : 'Reconnect'),
                ),
                if (current != null) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < _breadcrumbs.length; i++)
                        TextButton(
                          onPressed: _busy ? null : () => _backTo(i),
                          child: Text(_breadcrumbs[i].name),
                        ),
                    ],
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _selectedRoot = current),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Use this folder'),
                  ),
                  if (_selectedRoot != null)
                    Text(
                      'Selected: ${_selectedRoot!.name}',
                      style: const TextStyle(color: Colors.lightGreenAccent),
                    ),
                  const Divider(color: Colors.white24),
                  for (final child in _children)
                    ListTile(
                      enabled: !_busy && child.isFolder,
                      leading: Icon(
                        child.isFolder ? Icons.folder : Icons.block,
                        color:
                            child.isFolder ? Colors.blueAccent : Colors.white38,
                      ),
                      title: Text(
                        child.unsupportedReason == null
                            ? child.name
                            : '${child.name} — unsupported ${child.unsupportedReason}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: child.isFolder ? () => _openFolder(child) : null,
                    ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: canSave ? _save : null,
                  child: const Text('Save source'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
