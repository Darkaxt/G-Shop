import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../providers/preview_providers.dart';
import '../../providers/metadata_providers.dart';

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
  final _sliderFocus = <String, FocusNode>{};
  @override
  void dispose() {
    for (final node in _sliderFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  String get routeId => 'media-settings';
  @override
  void initState() {
    super.initState();
    ref.read(socketMediaImportProvider).initialize();
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        TabLeftIntent: CallbackAction<TabLeftIntent>(onInvoke: (_) {
          setState(() => _section = (_section + 5) % 6);
          return null;
        }),
        TabRightIntent: CallbackAction<TabRightIntent>(onInvoke: (_) {
          setState(() => _section = (_section + 1) % 6);
          return null;
        }),
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
          final slider =
              focus?.context?.findAncestorWidgetOfExactType<Slider>();
          if (slider != null &&
              (intent.direction == GridDirection.left ||
                  intent.direction == GridDirection.right)) {
            final step = (slider.max - slider.min) / (slider.divisions ?? 20);
            slider.onChanged?.call((slider.value +
                    (intent.direction == GridDirection.right ? step : -step))
                .clamp(slider.min, slider.max));
            return null;
          }
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
          final canonicalCache = await cache.resolveSymbolicLinks();
          final prefix =
              '$canonicalCache${Platform.pathSeparator}file_picker${Platform.pathSeparator}';
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
    final preview = ref.watch(previewSettingsProvider);
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
                        NavigationRailDestination(
                            icon: Icon(Icons.wallpaper),
                            label: Text('Background')),
                        NavigationRailDestination(
                            icon: Icon(Icons.tune), label: Text('Appearance')),
                        NavigationRailDestination(
                            icon: Icon(Icons.play_circle_outline),
                            label: Text('Playback')),
                        NavigationRailDestination(
                            icon: Icon(Icons.storage), label: Text('Storage')),
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
                            ] else if (_section == 1) ...[
                              _switch(
                                  'Second screen',
                                  Icons.desktop_windows_outlined,
                                  'enabled',
                                  preview.enabled),
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
                            ] else if (_section == 2) ...[
                              _choice('Background', Icons.wallpaper,
                                  'background', preview.background.name, const {
                                'off': 'Off',
                                'screenshot': 'Screenshot',
                                'slideshow': 'Slideshow',
                                'video': 'Video preferred'
                              }),
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                      'Cached media works offline. Missing clips fall back to screenshots.')),
                            ] else if (_section == 3) ...[
                              _switch('Show cartridge', Icons.album_outlined,
                                  'modelVisible', preview.modelVisible),
                              _slider('Blur', Icons.blur_on, 'blur',
                                  preview.blur, 20),
                              _slider('Brightness', Icons.brightness_6_outlined,
                                  'brightness', preview.brightness, 1),
                            ] else if (_section == 4) ...[
                              _switch('Autoplay', Icons.play_arrow, 'autoplay',
                                  preview.autoplay),
                              _switch(
                                  'Loop', Icons.repeat, 'loop', preview.loop),
                              _switch('Trailer sound', Icons.volume_up_outlined,
                                  'sound', preview.sound),
                              const ListTile(
                                  leading: Icon(Icons.volume_down_outlined),
                                  title: Text('Volume follows Audio → Music'),
                                  subtitle: Text(
                                      'Music mutes while a trailer plays.')),
                            ] else ...[
                              _choice('Download', Icons.download_outlined,
                                  'downloads', preview.downloads.name, const {
                                'manual': 'Manual',
                                'wifi': 'Wi-Fi only',
                                'any': 'Any network'
                              }),
                              _switch('Normalized video', Icons.movie_outlined,
                                  'normalized', preview.normalized),
                              _choice(
                                  'Video cache',
                                  Icons.storage,
                                  'cacheMiB',
                                  '${preview.cacheMiB}',
                                  const {
                                    '128': '128 MiB',
                                    '256': '256 MiB',
                                    '512': '512 MiB',
                                    '1024': '1 GiB',
                                    '2048': '2 GiB'
                                  },
                                  numeric: true),
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                      'Open Resources on a game to explore collected media. Use Scrape to collect more. Changing these settings does not start scraping.')),
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

  Future<void> _change(String key, Object value) async {
    try {
      await ref.read(previewSettingsProvider.notifier).change(key, value);
      if (key == 'cacheMiB' && mounted) {
        final storage = ref.read(storageServiceProvider);
        final controls = ref.read(metadataControlsProvider.notifier);
        await controls.load();
        await controls.trimPreviewVideos(
            () => storage.getPreviewSettings().cacheMiB * 1024 * 1024);
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save that setting.');
    }
  }

  Widget _switch(String title, IconData icon, String key, bool value) =>
      SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          value: value,
          onChanged: (value) => _change(key, value));
  Widget _slider(
      String title, IconData icon, String key, double value, double max) {
    final node = _sliderFocus.putIfAbsent(
        key, () => FocusNode(debugLabel: 'preview-$key'));
    return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Slider(
            focusNode: node,
            onChangeStart: (_) => node.requestFocus(),
            value: value,
            max: max,
            divisions: 20,
            onChanged: (value) => _change(key, value)));
  }

  Widget _choice(String title, IconData icon, String key, String value,
          Map<String, String> values,
          {bool numeric = false}) =>
      ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: DropdownButton<String>(
              value: values.containsKey(value) ? value : values.keys.first,
              items: [
                for (final entry in values.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value))
              ],
              onChanged: (value) {
                if (value != null)
                  _change(key, numeric ? int.parse(value) : value);
              }));
}
