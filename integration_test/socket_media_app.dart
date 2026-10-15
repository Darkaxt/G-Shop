// Isolated renderer proof. Never bootstraps the owner's library or credentials.
// VM service extensions are authenticated by the debug VM's session URL and
// reachable only through an explicitly selected ADB forward during this check.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/features/settings/media_settings_screen.dart';
import 'package:retro_eshop/features/game_detail/widgets/cover_section.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/socket_media_import.dart';
import 'package:retro_eshop/utils/game_metadata.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installGamepadKeyFix();
  final info = await PackageInfo.fromPlatform();
  if (!kDebugMode ||
      !Platform.isAndroid ||
      info.packageName != 'com.darkaxt.rshop.sharedproof') {
    throw StateError(
        'Renderer proof requires its isolated Android debug package');
  }
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft]);
  final storage = StorageService();
  await storage.init();
  final importer = SocketMediaImport();
  await importer.initialize();
  final fixture =
      File('${(await getTemporaryDirectory()).path}/media-proof-box.png');
  final icon = await rootBundle.load('assets/icon.png');
  await fixture.writeAsBytes(
      icon.buffer.asUint8List(icon.offsetInBytes, icon.lengthInBytes));
  runApp(ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        socketMediaImportProvider.overrideWith((ref) => importer),
      ],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: _MediaProof(box: fixture))));
}

class _MediaProof extends ConsumerStatefulWidget {
  final File box;
  const _MediaProof({required this.box});
  @override
  ConsumerState<_MediaProof> createState() => _MediaProofState();
}

class _MediaProofState extends ConsumerState<_MediaProof> {
  final _media = GlobalKey<PhysicalMediaViewState>();
  final _next = GlobalKey(), _previous = GlobalKey(), _insert = GlobalKey();
  final _artwork = GlobalKey();
  final _settings = GlobalKey();
  int _index = 0, _revision = 0;
  bool _resolved = false, _busy = false;
  Future<void> _action = Future.value();

  PhysicalMediaFormat get _format => PhysicalMediaFormat.values[_index];

  @override
  void initState() {
    super.initState();
    ref.read(socketMediaImportProvider).addListener(_importChanged);
    ref.listenManual(mediaPresentationProvider, (_, __) => _revision++);
    developer.registerExtension('ext.rshop.media', (_, args) async {
      try {
        final command = args['command'] ?? 'status';
        final before = _revision;
        if (command == 'settings-action') {
          if (WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed) {
            throw StateError('R-Shop is not foreground');
          }
          final target = _settingControl(args['target'] ?? '');
          final widget = target?.widget;
          if (widget is FilledButton && widget.onPressed != null) {
            widget.onPressed!();
          } else if (widget is OutlinedButton && widget.onPressed != null) {
            widget.onPressed!();
          } else if (widget is SwitchListTile && widget.onChanged != null) {
            widget.onChanged!(!widget.value);
          } else if (widget is NavigationRail) {
            final section = int.parse(args['section'] ?? '-1');
            if (section < 0 || section > 1) {
              throw ArgumentError('Unknown settings section');
            }
            widget.onDestinationSelected!(section);
          } else {
            throw StateError('Visible control unavailable');
          }
          _revision++;
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'action': command,
            'status': 'accepted',
            'beforeRevision': before,
            'afterRevision': _revision,
            'completionLimit':
                'Picker/import/preference completion is observed separately in import state',
            ..._snapshot(),
          }));
        } else if (command == 'ready') {
          await _media.currentState?.renderReady;
        } else if (command != 'status') {
          final key = switch (command) {
            'next' => _next,
            'previous' => _previous,
            'insert' => _insert,
            'artwork' => _artwork,
            'settings' => _settings,
            _ => throw ArgumentError('Unknown proof action'),
          };
          final control = key.currentWidget as FilledButton;
          if (control.onPressed == null) throw StateError('Control disabled');
          control.onPressed!(); // The same callback as an actual UI press.
          await _action;
          await WidgetsBinding.instance.endOfFrame;
        }
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'action': command,
          'beforeRevision': before,
          'afterRevision': _revision,
          ..._snapshot(),
        }));
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError, '$error');
      }
    });
  }

  void _importChanged() {
    _revision++;
  }

  @override
  void dispose() {
    ref.read(socketMediaImportProvider).removeListener(_importChanged);
    super.dispose();
  }

  static const _settingIds = {
    'media-settings-sections',
    'media-import-apk',
    'media-import-cancel',
    'media-enable-3d',
    'media-reduced-motion'
  };
  Element? _settingControl(String id) {
    if (!_settingIds.contains(id)) return null;
    Element? found;
    var visited = 0;
    void visit(Element element) {
      if (++visited > 2048 || found != null) return;
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget.key == ValueKey(id)) {
        found = element;
        return;
      }
      element.visitChildElements(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }

  List<Map<String, Object?>> _settingsSnapshot() => [
        for (final id in _settingIds)
          if (_settingControl(id) case final element?)
            (() {
              final box = element.findRenderObject() as RenderBox?;
              final offset =
                  box?.hasSize == true ? box!.localToGlobal(Offset.zero) : null;
              final widget = element.widget;
              return <String, Object?>{
                'id': id,
                'role': widget.runtimeType.toString(),
                'visible': offset != null,
                'boundsLogicalPixels': offset == null
                    ? null
                    : [offset.dx, offset.dy, box!.size.width, box.size.height],
                'enabled': switch (widget) {
                  FilledButton w => w.onPressed != null,
                  OutlinedButton w => w.onPressed != null,
                  SwitchListTile w => w.onChanged != null,
                  _ => true
                },
                'selected': widget is SwitchListTile
                    ? widget.value
                    : widget is NavigationRail
                        ? widget.selectedIndex
                        : null,
              };
            })()
      ];

  Map<String, Object?> _snapshot() {
    Map<String, Object?> node(String id, GlobalKey key, String role) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      final origin = box?.localToGlobal(Offset.zero);
      final button = key.currentWidget;
      return {
        'id': id,
        'role': role,
        'parent': 'proof',
        'boundsLogicalPixels': box?.hasSize == true
            ? [origin!.dx, origin.dy, box!.size.width, box.size.height]
            : null,
        'enabled': button is FilledButton ? button.onPressed != null : true,
      };
    }

    return {
      'package': 'com.darkaxt.rshop.sharedproof',
      'debug': kDebugMode,
      'appLifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'productionBootstrap': false,
      'romRequests': 0,
      'import': {
        'available': ref.read(socketMediaImportProvider).available,
        'importing': ref.read(socketMediaImportProvider).importing,
        'phase': ref.read(socketMediaImportProvider).phase,
        'progress': ref.read(socketMediaImportProvider).progress,
        'message': ref.read(socketMediaImportProvider).message,
        'generation': ref.read(socketMediaImportProvider).generation,
        'threeD': ref.read(mediaPresentationProvider).enabled,
        'reducedMotion': ref.read(mediaPresentationProvider).reducedMotion,
      },
      'format': _format.assetName,
      'settingsNodes': _settingsSnapshot(),
      'resolvedFixtureBoxArt': _resolved,
      'renderer': _media.currentState?.renderSnapshot,
      'viewportLogicalPixels': [
        MediaQuery.sizeOf(context).width,
        MediaQuery.sizeOf(context).height
      ],
      'nodes': [
        node('media', _media, 'physical-media'),
        node('previous', _previous, 'button'),
        node('next', _next, 'button'),
        node('insert', _insert, 'button'),
        node('artwork', _artwork, 'button'),
        node('settings', _settings, 'button')
      ],
      'coverageLimit':
          'Isolated real renderer; not owner-library data or launch proof',
    };
  }

  void _move(int delta) {
    _media.currentState?.resetInsertion();
    setState(() {
      _index = (_index + delta) % PhysicalMediaFormat.values.length;
      _revision++;
    });
    _action = Future.value();
  }

  void _play() {
    setState(() => _busy = true);
    _action = () async {
      final completed = await _media.currentState?.playInsertion() ?? true;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _revision++;
      });
      if (!completed) throw StateError('Insertion cancelled');
    }();
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(mediaPresentationProvider);
    const systems = [
      'gb',
      'gbc',
      'gbc',
      'gba',
      'n64',
      'nes',
      'snes',
      'snes',
      'nds',
      'n3ds',
      'switch',
      'megadrive',
      'megadrive',
      'psp',
      'psvita',
      'psx'
    ];
    final system = SystemModel.supportedSystems
        .singleWhere((s) => s.id == systems[_index]);
    final region = {PhysicalMediaFormat.snesPal, PhysicalMediaFormat.megadrive}
            .contains(_format)
        ? 'Europe'
        : 'USA';
    final game = GameItem(
        filename: 'Renderer sample ($region).rom',
        displayName: 'Renderer sample',
        url: '');
    return Scaffold(
        backgroundColor: const Color(0xff39070d),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Socket media: ${_format.description}',
                  style: const TextStyle(color: Colors.white, fontSize: 24))),
          Expanded(
              child: CoverSection(
                  key: ValueKey('fixture-${_format.assetName}'),
                  physicalMediaKey: _media,
                  game: game,
                  system: system,
                  metadata: GameMetadata.parse(game.filename),
                  gbcDualMode: _format == PhysicalMediaFormat.gameBoyColorDual
                      ? 'no'
                      : 'yes',
                  coverUrls: const [],
                  cachedUrl: _resolved ? widget.box.uri.toString() : null,
                  physicalMediaEnabled: media.enabled,
                  reducedMotion: media.reducedMotion,
                  showPresentationControls: false)),
          Padding(
              padding: const EdgeInsets.all(12),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FilledButton(
                    key: _previous,
                    onPressed: _busy ? null : () => _move(-1),
                    child: const Icon(Icons.arrow_back)),
                const SizedBox(width: 12),
                FilledButton(
                    key: _next,
                    onPressed: _busy ? null : () => _move(1),
                    child: const Icon(Icons.arrow_forward)),
                const SizedBox(width: 12),
                FilledButton(
                    key: _insert,
                    onPressed: _busy ? null : _play,
                    child: const Icon(Icons.play_arrow)),
                const SizedBox(width: 12),
                FilledButton(
                    key: _artwork,
                    onPressed: _busy
                        ? null
                        : () {
                            _media.currentState?.resetInsertion();
                            _action = () async {
                              await precacheImage(
                                  FileImage(widget.box), context);
                              if (!mounted) return;
                              setState(() {
                                _resolved = !_resolved;
                                _revision++;
                              });
                            }();
                          },
                    child: const Icon(Icons.image)),
                const SizedBox(width: 12),
                FilledButton(
                    key: _settings,
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MediaSettingsScreen()));
                      _action = Future.value();
                    },
                    child: const Icon(Icons.settings)),
              ])),
        ])));
  }
}
