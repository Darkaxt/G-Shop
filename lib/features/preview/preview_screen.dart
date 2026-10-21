import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game_item.dart';
import '../../models/console_model.dart';
import '../../models/nes_launch_scene.dart';
import '../../models/scene_launch_presentation.dart';
import '../../models/socket_media_model.dart';
import 'nes_launch_preview.dart';
import 'nes_console_selector.dart';
import '../../models/preview_settings.dart';
import '../../models/system_model.dart';
import '../../services/socket_media_import.dart';
import '../../utils/game_metadata.dart';
import '../game_detail/widgets/cover_section.dart';
import '../game_detail/widgets/game_scene_information.dart';
import '../../widgets/physical_media_view.dart';
import 'resource_gallery.dart';
import 'console_hardware_view.dart';

/// Dedicated rendering isolate. It receives local media and public facts only.
@pragma('vm:entry-point')
Future<void> previewMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const PreviewScreen()));
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with WidgetsBindingObserver {
  static const bridge = MethodChannel('com.darkaxt.gshop/preview_view');
  Map<String, dynamic>? _snapshot;
  VideoPlayerController? _video;
  Future<void> _settled = Future.value();
  int _generation = 0, _slide = 0;
  Timer? _slideshow;
  String? _videoPath;
  bool _paused = false;
  bool? _manualPlayback;
  bool? _reportedPlaying;
  int? _reportedEpoch;
  final _physicalKey = GlobalKey<PhysicalMediaViewState>();
  final _coverKey = GlobalKey<CoverSectionState>();
  final _galleryKey = GlobalKey<ResourceGalleryState>();
  final _consoleKey = GlobalKey<ConsoleHardwareViewState>();
  ConsoleModel? _consoleModel;
  NesLaunchScene? _launchScene;
  SocketMediaPose? _launchInitialPose;
  Widget? _launchLabel;
  Object? _launchLabelIdentity;
  int? _launchPreparingToken;
  PhysicalMediaViewState? _launchHeldMedia;

  void _clearLaunchScene() {
    if (_launchHeldMedia?.mounted == true)
      _launchHeldMedia!.releaseLaunchHold();
    _launchHeldMedia = null;
    _launchScene = null;
    _launchPreparingToken = null;
    _launchInitialPose = null;
    _launchLabel = null;
    _launchLabelIdentity = null;
  }

  bool _sameLaunch(int token) =>
      mounted && (_snapshot?['sceneLaunch'] as Map?)?['token'] == token;

  Future<void> _prepareLaunchScene() async {
    final launch = _snapshot?['sceneLaunch'] as Map?;
    if (launch == null || launch['visualAvailable'] != true) {
      _clearLaunchScene();
      return;
    }
    final token = launch['token'] as int;
    if (!{'nes-front-loader', 'nes-top-loader'}.contains(launch['console']) ||
        launch['consoleGeneration'] == null ||
        launch['displayGeneration'] == null ||
        _launchPreparingToken == token ||
        _snapshot?['mediaLoading'] == true) return;
    if (_launchScene != null && _launchPreparingToken != token)
      _clearLaunchScene();
    final cover = _coverKey.currentState;
    if (cover == null) return;
    _launchPreparingToken = token;
    try {
      final resolved = await cover.physicalMediaResolved;
      if (!_sameLaunch(token)) return;
      if (!resolved) {
        _action('launch-cancel', variant: token);
        return;
      }
      final media = _physicalKey.currentState;
      if (media?.widget.nesScene == null) {
        _action('launch-unavailable', variant: token);
        return;
      }
      final rendered = await media!.renderReady;
      if (!_sameLaunch(token)) return;
      if (!media.mounted ||
          rendered['error'] != null ||
          rendered['frameRendered'] != true) {
        _action('launch-unavailable', variant: token);
        return;
      }
      final console = await ConsoleModel.findNesLaunchTarget(
          (launch['console'] as String).substring(4));
      final display = await ConsoleModel.findNesLaunchDisplay();
      if (!_sameLaunch(token)) return;
      if (console == null ||
          display == null ||
          console.generation != launch['consoleGeneration'] ||
          display.generation != launch['displayGeneration']) {
        _action('launch-unavailable', variant: token);
        return;
      }
      if (!mounted || !media.mounted) return;
      media.holdForLaunch();
      _launchHeldMedia = media;
      final box = media.context.findRenderObject() as RenderBox;
      final viewport = box.localToGlobal(Offset.zero) & box.size;
      setState(() {
        _launchInitialPose = media.pose;
        _launchLabel = media.widget.label;
        _launchLabelIdentity = media.widget.labelIdentity;
        _launchScene = NesLaunchScene(media.widget.nesScene!, console, display,
            initialViewport: viewport);
      });
    } on FormatException {
      if (_sameLaunch(token)) _action('launch-unavailable', variant: token);
    } on FileSystemException {
      if (_sameLaunch(token)) _action('launch-unavailable', variant: token);
    }
  }

  String? _resourceGeneration;
  Future<void>? _resourceLoad;
  bool _previewSettled = false;
  String? _inspectedPart;
  int _incomingRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bridge.setMethodCallHandler((call) async {
      if (call.method == 'prepare') {
        await _prepareResources(
            (call.arguments as Map).cast<String, dynamic>());
        await bridge.invokeMethod<void>('prepared');
        return;
      }
      if (call.method == 'hide') {
        _clearLaunchScene();
        _incomingRevision++;
        _manualPlayback = null;
        setState(() => _snapshot = null);
        _updatePlayback(true);
        return;
      }
      if (call.method == 'togglePlayback') {
        if ((call.arguments as Map?)?['actionEpoch'] !=
            _snapshot?['actionEpoch']) return;
        _manualPlayback =
            !(_manualPlayback ?? _video?.value.isPlaying ?? settings.autoplay);
        final player = _video;
        if (player != null) {
          if (_manualPlayback! && !_paused) {
            await player.play();
          } else {
            await player.pause();
          }
        }
        return;
      }
      if (call.method == 'snapshot') {
        final snapshot = (call.arguments as Map).cast<String, dynamic>();
        final incoming = snapshot['revision'] as int;
        _incomingRevision = incoming;
        await _prepareResources(snapshot);
        ConsoleModel? console;
        if (snapshot['mode'] == 'console') {
          try {
            console = await ConsoleModel.find(snapshot['system'] as String);
          } catch (error) {
            debugPrint('GShopConsolePreview import unavailable: $error');
          }
        }
        if (!mounted || incoming != _incomingRevision) return;
        final changed = snapshot['identity'] != _snapshot?['identity'] ||
            snapshot['actionEpoch'] != _snapshot?['actionEpoch'];
        if (snapshot['identity'] != _snapshot?['identity']) {
          _clearLaunchScene();
          _previewSettled = false;
          _inspectedPart = null;
        }
        if (changed ||
            (snapshot['settings'] as Map)['autoplay'] != settings.autoplay)
          _manualPlayback = null;
        setState(() {
          _snapshot = snapshot;
          _consoleModel = console?.generation == snapshot['consoleGeneration']
              ? console
              : null;
          if (changed) _slide = 0;
        });
        _updatePlayback(changed);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_rendered(snapshot['revision'] as int));
          unawaited(_prepareLaunchScene());
        });
      }
    });
    unawaited(bridge.invokeMethod<void>('ready'));
  }

  Future<void> _prepareResources(Map<String, dynamic> value) async {
    final resource = value['resourceGeneration'] as String?;
    if (resource != null && resource != _resourceGeneration) {
      _resourceGeneration = resource;
      _resourceLoad = SocketMediaImport(
              readOnly: true,
              directory: Directory(value['resourceRoot'] as String))
          .initialize();
    }
    await _resourceLoad;
  }

  PreviewSettings get settings => PreviewSettings.fromJson(
      (_snapshot?['settings'] as Map? ?? const {}).cast<String, dynamic>());
  List<String> get screenshots =>
      (_snapshot?['screenshots'] as List? ?? const []).cast<String>();
  double get _volume => settings.sound
      ? ((_snapshot?['audioVolume'] as num?)?.toDouble() ?? .3).clamp(0, 1)
      : 0;

  void _playbackChanged() {
    final value = _video?.value;
    final playing = !_paused &&
        value != null &&
        value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        !value.isCompleted &&
        !value.hasError;
    final epoch = _snapshot?['actionEpoch'] as int?;
    if (_reportedPlaying == playing && _reportedEpoch == epoch) return;
    _reportedPlaying = playing;
    _reportedEpoch = epoch;
    unawaited(bridge.invokeMethod<void>('playing', {
      'actionEpoch': epoch,
      'video': _snapshot?['video'],
      'playing': playing,
    }));
    if (mounted && value?.hasError == true) setState(() {});
  }

  Future<void> _rendered(int revision,
      {bool revealStarted = false, bool revealCompleted = false}) async {
    if (!mounted || _snapshot?['revision'] != revision) return;
    unawaited(_prepareLaunchScene());
    final physical = _physicalKey.currentState;
    await _consoleKey.currentState?.renderReady;
    if (physical != null) {
      try {
        await physical.renderReady;
      } catch (_) {
        /* The renderer's snapshot retains the actual failed readiness. */
      }
    }
    if (!mounted || _snapshot?['revision'] != revision) return;
    await bridge.invokeMethod<void>('rendered', {
      'identity': _snapshot?['identity'],
      'revision': revision,
      'details': _snapshot?['details'],
      'viewportWidth': MediaQuery.sizeOf(context).width,
      'viewportHeight': MediaQuery.sizeOf(context).height,
      'model': _consoleKey.currentState?.snapshot ??
          _physicalKey.currentState?.renderSnapshot ??
          _coverKey.currentState?.renderSnapshot['handheldModels'] ??
          _coverKey.currentState?.renderSnapshot['unboxing'],
      'resourceGallery': _galleryKey.currentState?.snapshot,
      'media': _coverKey.currentState?.renderSnapshot,
      'revealStarted': revealStarted,
      'revealCompleted': revealCompleted,
      'videoReady': _video?.value.isInitialized == true,
      'videoPlaying': _reportedPlaying == true,
      'videoVolume': _video?.value.volume,
      'notice': _snapshot?['notice'],
      'readiness': _snapshot?['readiness'],
      'canLaunch': _snapshot?['canLaunch'],
    });
  }

  void _updatePlayback(bool changed) {
    final prefs = settings;
    final path = _snapshot?['sceneView'] != true &&
            !_paused &&
            _snapshot?['gallery'] != true &&
            prefs.background == PreviewBackground.video
        ? (_snapshot?['video'] as String?)
        : null;
    _slideshow?.cancel();
    _slideshow = null;
    // Presentation timing, not synchronization or completion control.
    if (_snapshot?['sceneView'] != true &&
        !_paused &&
        prefs.background == PreviewBackground.slideshow &&
        screenshots.length > 1) {
      _slideshow = Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted) setState(() => _slide = (_slide + 1) % screenshots.length);
      });
    }
    if (path == _videoPath && !changed) {
      final player = _video;
      if (player != null) {
        unawaited(player.setLooping(prefs.loop));
        unawaited(player.setVolume(_volume));
        if ((_manualPlayback ?? prefs.autoplay) && !_paused) {
          unawaited(player.play());
        } else {
          unawaited(player.pause());
        }
      }
      return;
    }
    final generation = ++_generation;
    _videoPath = path;
    final previous = _video;
    previous?.removeListener(_playbackChanged);
    _video = null;
    _playbackChanged();
    _settled = _settled.then((_) async {
      await previous?.dispose();
      if (!mounted || generation != _generation || path == null) return;
      final player = VideoPlayerController.file(File(path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      try {
        await player.initialize();
        if (!mounted || generation != _generation) {
          await player.dispose();
          return;
        }
        final current = settings;
        await player.setLooping(current.loop);
        await player.setVolume(_volume);
        if (!mounted || generation != _generation) {
          await player.dispose();
          return;
        }
        _video = player;
        player.addListener(_playbackChanged);
        if ((_manualPlayback ?? current.autoplay) && !_paused)
          await player.play();
        if (!mounted || generation != _generation) {
          player.removeListener(_playbackChanged);
          if (identical(_video, player)) _video = null;
          await player.dispose();
          return;
        }
        setState(() => _video = player);
        final revision = _snapshot?['revision'] as int?;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && revision != null) unawaited(_rendered(revision));
        });
      } catch (_) {
        player.removeListener(_playbackChanged);
        if (identical(_video, player)) _video = null;
        await player.dispose();
        _playbackChanged();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final token = (_snapshot?['sceneLaunch'] as Map?)?['token'] as int?;
    if (state != AppLifecycleState.resumed && token != null) {
      _action('launch-cancel', variant: token);
    }
    _paused = state != AppLifecycleState.resumed;
    _updatePlayback(false);
  }

  @override
  void dispose() {
    _clearLaunchScene();
    WidgetsBinding.instance.removeObserver(this);
    bridge.setMethodCallHandler(null);
    _slideshow?.cancel();
    _generation++;
    final player = _video;
    player?.removeListener(_playbackChanged);
    _video = null;
    _playbackChanged();
    unawaited(_settled.then((_) => player?.dispose()));
    super.dispose();
  }

  void _action(String action, {int? variant}) =>
      unawaited(bridge.invokeMethod<void>('action', {
        'actionEpoch': _snapshot?['actionEpoch'],
        'revision': _snapshot?['revision'],
        'action': action,
        if (variant != null) 'variant': variant
      }));

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null)
      return const Scaffold(backgroundColor: AppTheme.backgroundColor);
    final prefs = settings;
    final system = SystemModel.supportedSystems
        .where((s) => s.id == snapshot['system'])
        .firstOrNull;
    if (system == null) return const SizedBox.shrink();
    if (snapshot['mode'] == 'console') {
      final model = _consoleModel;
      if (model == null)
        return const Scaffold(
            body: Center(child: Text('Console model unavailable')));
      return Scaffold(
          body: system.id == 'nes'
              ? NesConsoleSelector(
                  collection: model,
                  hardwareKey: _consoleKey,
                  reducedMotion: snapshot['reducedMotion'] == true,
                  onReady: () =>
                      unawaited(_rendered(snapshot['revision'] as int)))
              : ConsoleHardwareView(
                  key: _consoleKey,
                  model: model,
                  title: snapshot['title'] as String,
                  onReady: () =>
                      unawaited(_rendered(snapshot['revision'] as int)),
                  reducedMotion: snapshot['reducedMotion'] == true));
    }
    final game = GameItem(
        filename: snapshot['filename'] as String,
        displayName: snapshot['title'] as String,
        url: '',
        cachedCoverUrl: snapshot['cover'] as String?);
    final details = snapshot['details'] == true;
    final gallery = snapshot['gallery'] == true;
    final player = _video;
    Widget? background;
    if (snapshot['sceneView'] != true &&
        prefs.background != PreviewBackground.off &&
        !_paused) {
      if (player != null &&
          player.value.isInitialized &&
          !player.value.hasError) {
        background = FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
                width: player.value.size.width,
                height: player.value.size.height,
                child: VideoPlayer(player)));
      } else if (screenshots.isNotEmpty) {
        final path = screenshots[_slide % screenshots.length];
        background = Image.file(File.fromUri(Uri.parse(path)),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const SizedBox.shrink());
      }
    }
    return Scaffold(
        body: Container(
            decoration:
                const BoxDecoration(gradient: AppTheme.backgroundGradient),
            child: Stack(fit: StackFit.expand, children: [
              if (background != null)
                ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                        sigmaX: prefs.blur, sigmaY: prefs.blur),
                    child: Opacity(
                        opacity:
                            details ? prefs.brightness * .35 : prefs.brightness,
                        child: background)),
              if (player != null && player.value.isInitialized)
                Positioned(
                    right: 16,
                    top: 16,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: player,
                        builder: (context, value, child) =>
                            IconButton.filledTonal(
                                tooltip: value.isPlaying
                                    ? 'Pause video'
                                    : 'Play video',
                                onPressed: () {
                                  _manualPlayback = !value.isPlaying;
                                  if (_manualPlayback!) {
                                    unawaited(player.play());
                                  } else {
                                    unawaited(player.pause());
                                  }
                                },
                                icon: Icon(value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow)))),
              SafeArea(
                  child: Padding(
                      padding: EdgeInsets.symmetric(vertical: gallery ? 0 : 24),
                      child: Column(children: [
                        if (!gallery) ...[
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(game.displayName,
                                  key: const ValueKey('preview-game-title'),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w600))),
                          Text(system.name,
                              style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                            child: snapshot['gallery'] == true
                                ? snapshot['galleryLoading'] == true
                                    ? const Center(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 16),
                                            Text('Loading resources…')
                                          ]))
                                    : ResourceGallery(
                                        initialView:
                                            snapshot['galleryManual'] == true
                                                ? ResourceView.manual
                                                : null,
                                        initiallyOpening:
                                            snapshot['galleryManual'] == true,
                                        reducedMotion:
                                            snapshot['reducedMotion'] == true,
                                        key: _galleryKey,
                                        identity:
                                            snapshot['identity'] as String,
                                        title: game.displayName,
                                        systemId: system.id,
                                        filename: game.filename,
                                        contentTags:
                                            (snapshot['contentTags'] as List? ??
                                                    const [])
                                                .cast<String>(),
                                        region:
                                            GameMetadata.parse(game.filename)
                                                .region
                                                .name,
                                        dualMode:
                                            snapshot['gbcDualMode'] as String?,
                                        importedModels:
                                            snapshot['threeD'] == true,
                                        volume: _volume,
                                        resources: {
                                          for (final entry
                                              in (snapshot['galleryResources']
                                                          as Map? ??
                                                      {})
                                                  .entries)
                                            entry.key as String:
                                                (entry.value as List)
                                                    .cast<String>(),
                                          if (snapshot['cover'] != null)
                                            'cover-preview': [
                                              snapshot['cover'] as String
                                            ],
                                          if (snapshot['label'] != null)
                                            'support-texture': [
                                              snapshot['label'] as String
                                            ],
                                          'screenshot': screenshots,
                                          if (snapshot['video'] != null)
                                            'video': [
                                              Uri.file(snapshot['video']
                                                      as String)
                                                  .toString()
                                            ],
                                        },
                                        onClose: () => _action('preview'),
                                        onPlayingChanged: (playing) =>
                                            unawaited(bridge.invokeMethod<void>('playing', {
                                              'actionEpoch':
                                                  snapshot['actionEpoch'],
                                              'video': snapshot['video'],
                                              'playing': playing
                                            })))
                                : details && snapshot['sceneView'] != true
                                    ? Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _details(snapshot))
                                    : GestureDetector(
                                        onTap: snapshot['sceneView'] == true ? null : () => _action('details'),
                                        child: prefs.modelVisible && snapshot['mediaLoading'] == true && snapshot['cover'] == null
                                            ? const Center(child: CircularProgressIndicator(key: ValueKey('preview-loading-cover')))
                                            : prefs.modelVisible
                                                ? IgnorePointer(
                                                    ignoring: snapshot['sceneView'] == true && (details || snapshot['sceneLaunch'] != null),
                                                    child: CoverSection(
                                                        onNesReferenceChanged: (style) => _action('nes-reference:${style ?? 'none'}'),
                                                        scenePresentation: snapshot['sceneView'] == true,
                                                        gameInformationVisible: details,
                                                        showGameWatchVariants: true,
                                                        onHardwareReference: () => _action('hardware-source'),
                                                        inspectedHardware: snapshot['inspectedHardware'] as int?,
                                                        hardwareInformationVisible: snapshot['hardwareInformationVisible'] == true,
                                                        onHardwareInspection: (index) => index == null ? _action('hardware-overview') : _action('hardware-inspect', variant: index),
                                                        onHardwareInformation: (show) => _action(show ? 'hardware-info' : 'hardware-hide-info'),
                                                        initiallySettled: _previewSettled,
                                                        initialInspectionPart: _inspectedPart,
                                                        onInspectionChanged: (part) => _inspectedPart = part,
                                                        onReadManual: () {
                                                          _previewSettled =
                                                              true;
                                                          _inspectedPart =
                                                              'booklet';
                                                          _action('manual');
                                                        },
                                                        key: _coverKey,
                                                        game: game,
                                                        system: system,
                                                        coverUrls: const [],
                                                        cachedUrl: snapshot['cover'] as String?,
                                                        physicalLabelUrl: snapshot['label'] as String?,
                                                        gbcDualMode: snapshot['gbcDualMode'] as String?,
                                                        contentTags: (snapshot['contentTags'] as List? ?? const []).cast<String>(),
                                                        packagingResources: {
                                                          for (final entry
                                                              in (snapshot['galleryResources']
                                                                          as Map? ??
                                                                      {})
                                                                  .entries)
                                                            entry.key
                                                                as String: (entry
                                                                        .value
                                                                    as List)
                                                                .cast<String>()
                                                        },
                                                        metadata: GameMetadata.parse(game.filename),
                                                        physicalMediaEnabled: snapshot['threeD'] == true,
                                                        physicalMediaKey: _physicalKey,
                                                        reducedMotion: snapshot['reducedMotion'] == true,
                                                        resourcesReady: snapshot['mediaLoading'] != true && (_videoPath == null || _video?.value.isInitialized == true),
                                                        onReady: () => unawaited(_rendered(snapshot['revision'] as int, revealStarted: true)),
                                                        onRevealed: () {
                                                          _previewSettled =
                                                              true;
                                                          unawaited(_rendered(
                                                              snapshot[
                                                                      'revision']
                                                                  as int,
                                                              revealCompleted:
                                                                  true));
                                                        },
                                                        showPresentationControls: false))
                                                : const Center(child: Icon(Icons.touch_app_outlined, size: 48)))),
                        if (!details &&
                            !gallery &&
                            snapshot['sceneView'] != true)
                          Text(
                              system.id == 'gameandwatch' &&
                                      snapshot['threeD'] == true
                                  ? (snapshot['inspectedHardware'] == null
                                      ? 'Tap a model to inspect'
                                      : 'Select for hardware information')
                                  : 'Select for details',
                              style: TextStyle(color: Colors.white70)),
                      ]))),
              if (!gallery &&
                  snapshot['sceneView'] == true &&
                  snapshot['sceneLaunch'] == null)
                Positioned(
                    left: 16,
                    top: 16,
                    child: IconButton.filledTonal(
                        tooltip: 'Game information',
                        onPressed: () {
                          _physicalKey.currentState?.inspectCartridge();
                          _action('details');
                        },
                        icon: const Icon(Icons.info_outline))),
              if (snapshot['sceneView'] == true && details)
                GameSceneInformation(
                    title: game.displayName,
                    referenceNote:
                        'Box and cartridge models are reference editions. Physical releases can differ.',
                    summary: snapshot['summary'] as String?,
                    credits: snapshot['credits'] as String?,
                    genres: snapshot['genres'] as String?,
                    score: snapshot['scoreLabel'] as String?,
                    onClose: () => _action('close')),
              if (_launchScene != null &&
                  snapshot['sceneLaunch'] is Map &&
                  (snapshot['sceneLaunch'] as Map)['visualAvailable'] == true)
                Positioned.fill(
                    child: NesLaunchPreview(
                        key: ValueKey('nes-launch:${_launchPreparingToken!}'),
                        token: _launchPreparingToken!,
                        scene: _launchScene!,
                        initialPose: _launchInitialPose!,
                        label: _launchLabel!,
                        labelIdentity: _launchLabelIdentity,
                        title: game.displayName,
                        phase: SceneLaunchPhase.values.byName(
                            (snapshot['sceneLaunch'] as Map)['phase']
                                as String),
                        skip: (snapshot['sceneLaunch'] as Map)['skip'] == true,
                        reducedMotion: snapshot['reducedMotion'] == true,
                        onPrepared: (ready) => _action(
                            ready ? 'launch-ready' : 'launch-unavailable',
                            variant: _launchPreparingToken),
                        onFinished: () => _action('launch-finished',
                            variant: _launchPreparingToken),
                        onCancel: () => _action('launch-cancel',
                            variant: _launchPreparingToken),
                        onSkip: () => _action('launch-skip', variant: _launchPreparingToken))),
              if (!gallery &&
                  !details &&
                  snapshot['sceneView'] != true &&
                  system.id == 'gba') ...[
                if (snapshot['scoreLabel'] is String)
                  Positioned(
                      left: 20,
                      bottom: 20,
                      child: _cornerBadge(
                          key: const ValueKey('preview-score'),
                          text: snapshot['scoreLabel'] as String)),
                Positioned(
                    right: 20,
                    bottom: 20,
                    child: _cornerBadge(
                        key: const ValueKey('preview-availability'),
                        icon: snapshot['installed'] == true
                            ? Icons.sd_card
                            : Icons.cloud_download_outlined,
                        text: snapshot['installed'] == true
                            ? 'On device'
                            : 'In Drive')),
              ],
            ])));
  }

  Widget _cornerBadge(
          {required Key key, required String text, IconData? icon}) =>
      Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xed171717),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: 7)
            ],
            Text(text,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ]));

  Widget _details(Map<String, dynamic> snapshot) => Column(children: [
        Expanded(
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              if (snapshot['rating'] != null)
                Text('★ ${(snapshot['rating'] as num).toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 22)),
              if (snapshot['credits'] != null)
                Text(snapshot['credits'] as String),
              if (snapshot['genres'] != null)
                Text(snapshot['genres'] as String),
              const SizedBox(height: 16),
              Text(snapshot['summary'] as String? ?? 'No description yet.',
                  style: const TextStyle(fontSize: 18, height: 1.45)),
              const SizedBox(height: 16),
              Text(snapshot['readiness'] as String? ?? 'Checking local game…'),
              if ((snapshot['notice'] as String?)?.isNotEmpty == true)
                Text(snapshot['notice'] as String),
              if ((snapshot['variants'] as List?)?.length case final int count
                  when count > 1)
                DropdownButton<int>(
                    value: snapshot['variant'] as int,
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < count; i++)
                        DropdownMenuItem(
                            value: i,
                            child: Text(
                                (snapshot['variants'] as List)[i] as String,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (v) {
                      if (v != null) _action('variant', variant: v);
                    }),
            ]))),
        const SizedBox(height: 12),
        Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                  onPressed: snapshot['canLaunch'] == true
                      ? () => _action('launch')
                      : snapshot['canDownload'] == true
                          ? () => _action('download')
                          : null,
                  style: AppTheme.primaryButtonStyle,
                  icon: Icon(snapshot['canLaunch'] == true
                      ? Icons.play_arrow
                      : Icons.download),
                  label: Text(
                      snapshot['canLaunch'] == true ? 'Play' : 'Download')),
              OutlinedButton.icon(
                  onPressed: () => _action('gallery'),
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('Resources')),
              OutlinedButton.icon(
                  onPressed: () => _action('close'),
                  icon: const Icon(Icons.album_outlined),
                  label: const Text('Preview')),
            ]),
      ]);
}
