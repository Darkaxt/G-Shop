import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../providers/migration_providers.dart';
import '../../services/migration/migration_maintenance.dart';
import '../../services/migration/migration_service.dart';

class MigrationSettingsScreen extends ConsumerStatefulWidget {
  const MigrationSettingsScreen({super.key});
  @override
  ConsumerState<MigrationSettingsScreen> createState() =>
      _MigrationSettingsState();
}

class _MigrationSettingsState extends ConsumerState<MigrationSettingsScreen>
    with ConsoleScreenMixin {
  int section = 0;
  bool picking = false, dialogOpen = false;
  final first = FocusNode();
  @override
  String get routeId => 'migration-settings';
  bool get busy => ref.read(migrationServiceProvider).valueOrNull?.busy == true;
  void _section(int index) {
    if (busy || picking || dialogOpen) return;
    setState(() => section = (index + 3) % 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) first.requestFocus();
    });
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        TabLeftIntent: CallbackAction<TabLeftIntent>(onInvoke: (_) {
          _section(section - 1);
          return null;
        }),
        TabRightIntent: CallbackAction<TabRightIntent>(onInvoke: (_) {
          _section(section + 1);
          return null;
        }),
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          if (dialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
          } else if (!busy && !picking) {
            Navigator.maybePop(context);
          }
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
          final focused = FocusManager.instance.primaryFocus;
          if (focused == null || focused == screenFocusNode) {
            first.requestFocus();
          } else {
            focused.focusInDirection(switch (intent.direction) {
              GridDirection.up => TraversalDirection.up,
              GridDirection.down => TraversalDirection.down,
              GridDirection.left => TraversalDirection.left,
              GridDirection.right => TraversalDirection.right,
            });
          }
          return null;
        }),
      };
  @override
  void dispose() {
    first.dispose();
    super.dispose();
  }

  Future<String?> _password(bool backup) async {
    dialogOpen = true;
    try {
      return await showConsoleDialog<String>(
          context: context,
          builder: (_) => _MigrationPasswordDialog(backup: backup));
    } finally {
      dialogOpen = false;
    }
  }

  Future<void> _share(File file) async {
    await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'G-Shop encrypted backup');
  }

  Future<void> _backup(MigrationService service) async {
    if (picking || service.busy) return;
    setState(() => picking = true);
    try {
      final password = await _password(true);
      if (password == null) return;
      final file = await service.backup(password);
      await _share(file);
    } catch (_) {
      /* The service exposes a fixed, credential-free issue code. */
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _restore(MigrationService service) async {
    if (picking || service.busy) return;
    setState(() => picking = true);
    File? consumed;
    FileStat? original;
    try {
      final selected = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false, withData: false);
      final path = selected?.files.single.path;
      if (path == null) return;
      consumed = File(path);
      original = await consumed.stat();
      final password = await _password(false);
      if (password == null) return;
      if (Platform.isAndroid &&
          !(await Permission.manageExternalStorage.request()).isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Allow file access in Android to restore your games.')));
        }
        return;
      }
      await service.restore(consumed, password);
      await MigrationMaintenance.restart();
    } catch (_) {
      /* No raw error, path, credentials or archive payload is logged. */
    } finally {
      if (consumed != null && original != null) {
        // Only the unchanged copy created by Android's document picker; never
        // the user's original archive or another picker request's directory.
        final cache = await getTemporaryDirectory();
        final root = p.join(await cache.resolveSymbolicLinks(), 'file_picker');
        if (await consumed.exists()) {
          final path = await consumed.resolveSymbolicLinks();
          final current = await consumed.stat();
          if (p.isWithin(root, path) &&
              current.size == original.size &&
              current.modified == original.modified &&
              current.changed == original.changed) {
            await consumed.delete();
            if (await consumed.parent.list().isEmpty) {
              await consumed.parent.delete();
            }
          }
        }
      }
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _previous(MigrationService service) async {
    try {
      await service.recoverPrevious();
      await MigrationMaintenance.restart();
    } catch (_) {
      /* Recovery stays journaled and the UI offers a normal restart. */
    }
  }

  Future<void> _resume(MigrationService service) async {
    try {
      await service.resume();
      await MigrationMaintenance.restart();
    } catch (_) {/* The original resumable transaction remains available. */}
  }

  Widget _action(String label, IconData icon, String key, VoidCallback? action,
          {bool initial = false}) =>
      ConsoleFocusable(
          key: ValueKey('$key-focus'),
          focusNode: initial ? first : null,
          autofocus: initial,
          focusScale: 1,
          onSelect: action,
          child: FilledButton.icon(
              key: ValueKey(key),
              onPressed: action,
              style: AppTheme.primaryButtonStyle,
              icon: Icon(icon),
              label: Text(label)));

  @override
  Widget build(BuildContext context) => ref
      .watch(migrationServiceProvider)
      .when(
        loading: () => buildWithActions(
            const Scaffold(body: Center(child: CircularProgressIndicator()))),
        error: (_, __) => buildWithActions(Scaffold(
            appBar: AppBar(title: const Text('Device migration')),
            body: const Center(
                child: Text(
                    'Could not open migration settings. Please reopen G-Shop.')))),
        data: (service) => AnimatedBuilder(
            animation: service,
            builder: (context, _) => buildWithActions(
                PopScope(
                    canPop: !service.busy && !picking,
                    child: Scaffold(
                      backgroundColor: AppTheme.backgroundColor,
                      appBar: AppBar(title: const Text('Device migration')),
                      body: LayoutBuilder(
                          builder: (context, bounds) => Row(children: [
                                NavigationRail(
                                    key: const ValueKey('migration-sections'),
                                    extended: bounds.maxWidth >= 680,
                                    selectedIndex: section,
                                    onDestinationSelected:
                                        service.busy || picking
                                            ? null
                                            : _section,
                                    destinations: const [
                                      NavigationRailDestination(
                                          icon: Icon(Icons.backup_outlined),
                                          label: Text('Backup')),
                                      NavigationRailDestination(
                                          icon: Icon(Icons.restore_outlined),
                                          label: Text('Restore')),
                                      NavigationRailDestination(
                                          icon: Icon(Icons.history_outlined),
                                          label: Text('Recovery')),
                                    ]),
                                const VerticalDivider(width: 1),
                                Expanded(
                                    child: Center(
                                        child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 720),
                                            child: SingleChildScrollView(
                                              key: ValueKey(
                                                  'migration-section-$section'),
                                              padding: const EdgeInsets.all(28),
                                              child: FocusTraversalGroup(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    if (section == 0) ...[
                                                      const ListTile(
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                          leading: Icon(Icons
                                                              .lock_outline),
                                                          title: Text(
                                                              'Take your complete G-Shop setup with you'),
                                                          subtitle: Text(
                                                              'Settings, API keys, metadata, installed games and their data in one encrypted file.')),
                                                      const SizedBox(
                                                          height: 16),
                                                      const Text(
                                                          'Keep the backup password somewhere safe. G-Shop cannot recover it.'),
                                                      const SizedBox(
                                                          height: 24),
                                                      _action(
                                                          'Backup',
                                                          Icons.backup_outlined,
                                                          'migration-backup',
                                                          service.busy ||
                                                                  picking ||
                                                                  service
                                                                      .restartRequired
                                                              ? null
                                                              : () => _backup(
                                                                  service),
                                                          initial: true),
                                                      if (service.lastBackup !=
                                                          null) ...[
                                                        const SizedBox(
                                                            height: 16),
                                                        _action(
                                                            'Share backup',
                                                            Icons
                                                                .share_outlined,
                                                            'migration-share',
                                                            service.busy ||
                                                                    picking
                                                                ? null
                                                                : () => _share(
                                                                    service
                                                                        .lastBackup!)),
                                                      ],
                                                    ],
                                                    if (section == 1) ...[
                                                      const ListTile(
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                          leading: Icon(Icons
                                                              .move_to_inbox_outlined),
                                                          title: Text(
                                                              'Restore a complete setup'),
                                                          subtitle: Text(
                                                              'Choose your backup and unlock it once. No API keys to enter again.')),
                                                      const SizedBox(
                                                          height: 16),
                                                      const Text(
                                                          'Your current setup is kept for recovery. Google sign-in, storage or root permission may still need Android’s approval.'),
                                                      const SizedBox(
                                                          height: 24),
                                                      if (service
                                                          .canResume) ...[
                                                        _action(
                                                            'Resume',
                                                            Icons.play_arrow,
                                                            'migration-resume',
                                                            service.busy ||
                                                                    picking ||
                                                                    service
                                                                        .restartRequired
                                                                ? null
                                                                : () => _resume(
                                                                    service)),
                                                        const SizedBox(
                                                            height: 16),
                                                      ],
                                                      _action(
                                                          'Restore',
                                                          Icons
                                                              .restore_outlined,
                                                          'migration-restore',
                                                          service.busy ||
                                                                  picking ||
                                                                  service
                                                                      .restartRequired ||
                                                                  service
                                                                      .canResume
                                                              ? null
                                                              : () => _restore(
                                                                  service),
                                                          initial: true),
                                                    ],
                                                    if (section == 2) ...[
                                                      const ListTile(
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                          leading: Icon(Icons
                                                              .history_outlined),
                                                          title: Text(
                                                              'Previous setup'),
                                                          subtitle: Text(
                                                              'An interrupted restore is rolled back when G-Shop opens. A successful restore keeps the previous setup on this device.')),
                                                      const SizedBox(
                                                          height: 24),
                                                      _action(
                                                          'Restore previous',
                                                          Icons.undo_outlined,
                                                          'migration-previous',
                                                          service.busy ||
                                                                  picking ||
                                                                  !service
                                                                      .canRecoverPrevious ||
                                                                  service
                                                                      .restartRequired
                                                              ? null
                                                              : () => _previous(
                                                                  service),
                                                          initial: true),
                                                    ],
                                                    if (service.busy ||
                                                        service.issue != null ||
                                                        service.phase ==
                                                            'Complete') ...[
                                                      const SizedBox(
                                                          height: 28),
                                                      Text(service.phase,
                                                          key: const ValueKey(
                                                              'migration-phase')),
                                                      if (service.busy) ...[
                                                        const SizedBox(
                                                            height: 12),
                                                        LinearProgressIndicator(
                                                            value: service
                                                                        .total >
                                                                    0
                                                                ? service
                                                                        .completed /
                                                                    service
                                                                        .total
                                                                : null),
                                                        if (service.total > 0)
                                                          Text(
                                                              '${service.completed} / ${service.total}'),
                                                      ],
                                                      if (service.issue != null)
                                                        Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 12),
                                                            child: Text(switch (
                                                                service.issue) {
                                                              'invalid_archive_or_password' =>
                                                                'Check the password and choose a complete, unchanged backup.',
                                                              'short_password' =>
                                                                'Use a backup password with at least 12 characters.',
                                                              'cancelled' =>
                                                                'Stopped. Your current setup has been kept.',
                                                              'root_unavailable' =>
                                                                'Allow G-Shop root access to include your protected game data.',
                                                              'storage_permission' =>
                                                                'Allow file access in Android, then try again.',
                                                              _ =>
                                                                'Could not finish. Your previous setup is kept for recovery.',
                                                            })),
                                                    ],
                                                    if (service
                                                        .restartRequired) ...[
                                                      const SizedBox(
                                                          height: 20),
                                                      _action(
                                                          'Restart',
                                                          Icons.restart_alt,
                                                          'migration-restart',
                                                          service.busy
                                                              ? null
                                                              : MigrationMaintenance
                                                                  .restart),
                                                    ],
                                                  ])),
                                            )))),
                              ])),
                    )),
                materialControls: true)),
      );
}

class _MigrationPasswordDialog extends StatefulWidget {
  final bool backup;
  const _MigrationPasswordDialog({required this.backup});
  @override
  State<_MigrationPasswordDialog> createState() => _MigrationPasswordState();
}

class _MigrationPasswordState extends State<_MigrationPasswordDialog> {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  String? error;
  void _submit() {
    if (widget.backup && password.text.length < 12) {
      setState(() => error = 'Use at least 12 characters.');
      return;
    }
    if (widget.backup && password.text != confirmation.text) {
      setState(() => error = 'The passwords do not match.');
      return;
    }
    if (password.text.isEmpty) return;
    Navigator.pop(context, password.text);
  }

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label, String key) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
              key: ValueKey(key),
              controller: controller,
              autofocus: key == 'migration-password',
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              onSubmitted: (_) => widget.backup && controller == password
                  ? FocusScope.of(context).nextFocus()
                  : _submit(),
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder())));
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.backup ? 'Protect your backup' : 'Unlock backup'),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(password, 'Backup password', 'migration-password'),
              if (widget.backup)
                _field(confirmation, 'Repeat password',
                    'migration-password-confirm'),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!)),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _submit,
              style: AppTheme.primaryButtonStyle,
              child: Text(widget.backup ? 'Backup' : 'Unlock'))
        ],
      );
}
