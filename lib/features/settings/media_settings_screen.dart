import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

class MediaSettingsScreen extends ConsumerStatefulWidget {
  const MediaSettingsScreen({super.key});
  @override
  ConsumerState<MediaSettingsScreen> createState() => _MediaSettingsState();
}

class _MediaSettingsState extends ConsumerState<MediaSettingsScreen>
    with ConsoleScreenMixin {
  int _section = 0;
  bool _picking = false;
  String? _notice;
  @override
  String get routeId => 'media-settings';
  @override
  void initState() {
    super.initState();
    ref.read(socketMediaImportProvider).initialize();
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          Navigator.maybePop(context);
          return null;
        }),
        ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
          final target = FocusManager.instance.primaryFocus?.context;
          if (target != null) {
            Actions.maybeInvoke(target, const ActivateIntent());
          }
          return null;
        }),
        NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
          final focus = FocusManager.instance.primaryFocus;
          if (focus == null || focus == screenFocusNode) {
            screenFocusNode.nextFocus();
            return null;
          }
          focus.focusInDirection(switch (intent.direction) {
            GridDirection.up => TraversalDirection.up,
            GridDirection.down => TraversalDirection.down,
            GridDirection.left => TraversalDirection.left,
            GridDirection.right => TraversalDirection.right,
          });
          return null;
        }),
      };

  Future<void> _pickApk() async {
    if (_picking || ref.read(socketMediaImportProvider).importing) return;
    setState(() {
      _picking = true;
      _notice = null;
    });
    File? picked;
    FileStat? pickedStat;
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['apk'],
          allowMultiple: false,
          withData: false);
      final path = result?.files.single.path;
      if (path != null) {
        picked = File(path);
        pickedStat = await picked.stat();
        await ref.read(socketMediaImportProvider).importApk(picked);
      }
    } catch (_) {
      if (mounted && ref.read(socketMediaImportProvider).message.isEmpty) {
        setState(
            () => _notice = 'Could not open that APK. Please choose it again.');
      }
    } finally {
      // Android FilePicker copies documents into its own app-cache namespace.
      // Retire only that unchanged consumed copy, never the user's original.
      if (picked != null && pickedStat != null) {
        try {
          final cache = await getTemporaryDirectory();
          final prefix =
              '${cache.path}${Platform.pathSeparator}file_picker${Platform.pathSeparator}';
          if (await picked.exists()) {
            final path = await picked.resolveSymbolicLinks();
            final current = await picked.stat();
            if (path.startsWith(prefix) &&
                current.size == pickedStat.size &&
                current.modified == pickedStat.modified &&
                current.changed == pickedStat.changed) {
              await picked.delete();
              if (await picked.parent.list().isEmpty) {
                await picked.parent.delete();
              }
            }
          }
        } catch (_) {
          if (mounted) {
            _notice = 'The temporary APK copy remains in the app cache.';
          }
        }
      }
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _toggle(bool media) async {
    try {
      final preferences = ref.read(mediaPresentationProvider.notifier);
      if (media) {
        await preferences.toggleMedia();
      } else {
        await preferences.toggleMotion();
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save that setting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final importer = ref.watch(socketMediaImportProvider);
    final preferences = ref.watch(mediaPresentationProvider);
    return buildWithActions(
        Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(title: const Text('Media previews')),
          body: LayoutBuilder(
              builder: (context, bounds) => Row(children: [
                    NavigationRail(
                      key: const ValueKey('media-settings-sections'),
                      extended: bounds.maxWidth >= 680,
                      selectedIndex: _section,
                      onDestinationSelected: (index) =>
                          setState(() => _section = index),
                      destinations: const [
                        NavigationRailDestination(
                            icon: Icon(Icons.inventory_2_outlined),
                            label: Text('Resources')),
                        NavigationRailDestination(
                            icon: Icon(Icons.view_in_ar_outlined),
                            label: Text('Presentation')),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                        child: SingleChildScrollView(
                      key: ValueKey('media-settings-section-$_section'),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_section == 0) ...[
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(importer.available
                                    ? Icons.check_circle_outline
                                    : Icons.photo_outlined),
                                title: Text(importer.available
                                    ? 'Socket 0.7 imported'
                                    : 'Flat previews are ready'),
                                subtitle: Text(importer.available
                                    ? '16 media formats available for 3D'
                                    : 'Import your original Socket APK to unlock 3D.'),
                              ),
                              if (importer.importing) ...[
                                Text(importer.phase,
                                    key: const ValueKey('media-import-phase')),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                    value: importer.progress == 0
                                        ? null
                                        : importer.progress),
                                const SizedBox(height: 12),
                              ],
                              Wrap(spacing: 12, runSpacing: 12, children: [
                                FilledButton.icon(
                                    key: const ValueKey('media-import-apk'),
                                    style: AppTheme.primaryButtonStyle,
                                    onPressed: _picking || importer.importing
                                        ? null
                                        : _pickApk,
                                    icon: const Icon(Icons.file_open_outlined),
                                    label: const Text('Import APK')),
                                if (importer.importing)
                                  OutlinedButton.icon(
                                      key:
                                          const ValueKey('media-import-cancel'),
                                      onPressed: importer.committing
                                          ? null
                                          : importer.cancel,
                                      icon: const Icon(Icons.close),
                                      label: const Text('Cancel')),
                              ]),
                              const SizedBox(height: 20),
                              const Text(
                                  'Resources stay on this device. Your original APK is unchanged.'),
                            ] else ...[
                              SwitchListTile(
                                  key: const ValueKey('media-enable-3d'),
                                  secondary:
                                      const Icon(Icons.view_in_ar_outlined),
                                  title: const Text('3D media'),
                                  subtitle: Text(importer.available
                                      ? 'Use imported cartridge and disc models'
                                      : 'Import the APK first'),
                                  value: preferences.enabled,
                                  onChanged:
                                      importer.available && !importer.importing
                                          ? (_) => _toggle(true)
                                          : null),
                              SwitchListTile(
                                  key: const ValueKey('media-reduced-motion'),
                                  secondary: const Icon(
                                      Icons.motion_photos_off_outlined),
                                  title: const Text('Reduced motion'),
                                  subtitle: const Text(
                                      'Skip cover reveals and insertion animations'),
                                  value: preferences.reducedMotion,
                                  onChanged: (_) => _toggle(false)),
                            ],
                            if ((_notice ?? importer.message).isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(_notice ?? importer.message,
                                  key: const ValueKey('media-import-message')),
                            ],
                          ]),
                    )),
                  ])),
        ),
        localFocusScope: true);
  }
}
