import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import '../../models/game_watch_hardware_info.dart';
import '../../models/game_watch_unboxing_scene.dart';
import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import 'console_hardware_view.dart';
import 'game_watch_preview.dart';

/// Bottom-screen presentation only. Cards and Resources retain exact lookup.
class GameWatchVariantsPreview extends StatefulWidget {
  final String filename, title, identity;
  final bool reducedMotion;
  final int? inspectedIndex;
  final bool informationVisible;
  final ValueChanged<int?>? onInspect;
  final ValueChanged<bool>? onInformation;
  final VoidCallback? onReference;
  final VoidCallback? onReady;
  final Directory? modelsDirectory;
  const GameWatchVariantsPreview(
      {super.key,
      required this.filename,
      required this.title,
      required this.identity,
      this.reducedMotion = false,
      this.inspectedIndex,
      this.informationVisible = false,
      this.onInspect,
      this.onInformation,
      this.onReference,
      this.onReady,
      this.modelsDirectory});
  @override
  State<GameWatchVariantsPreview> createState() =>
      GameWatchVariantsPreviewState();
}

class GameWatchVariantsPreviewState extends State<GameWatchVariantsPreview> {
  final _viewKey = GlobalKey<GameWatchVariantsViewState>();
  late Future<List<GameWatchModelVariant>> _models;
  bool _errorReported = false;
  Map<String, Object?>? get snapshot => _viewKey.currentState?.snapshot;
  void _load() {
    _errorReported = false;
    _models = ConsoleModel.findGameWatchVariants(widget.filename,
        modelsDirectory: widget.modelsDirectory);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GameWatchVariantsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename ||
        oldWidget.modelsDirectory?.path != widget.modelsDirectory?.path) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<GameWatchModelVariant>>(
          future: _models,
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final variants = result.data;
            if (result.hasError && !_errorReported) {
              _errorReported = true;
              debugPrint(
                  'GShopGameWatchVariants import unavailable: ${result.error}');
            }
            if (variants == null || variants.isEmpty) {
              // An optional visual catalogue cannot hide the exact primary or the
              // existing honest fallback when no primary has been imported.
              return GameWatchPreview(
                  filename: widget.filename,
                  title: widget.title,
                  identity: widget.identity,
                  reducedMotion: widget.reducedMotion,
                  onReady: widget.onReady);
            }
            return GameWatchVariantsView(
                key: _viewKey,
                variants: variants,
                inspectedIndex: widget.inspectedIndex,
                informationVisible: widget.informationVisible,
                onInspect: widget.onInspect,
                onInformation: widget.onInformation,
                onReference: widget.onReference,
                reducedMotion: widget.reducedMotion,
                onReady: widget.onReady);
          });
}

class GameWatchVariantsView extends StatefulWidget {
  final List<GameWatchModelVariant> variants;
  final bool reducedMotion;
  final int? inspectedIndex;
  final bool informationVisible;
  final ValueChanged<int?>? onInspect;
  final ValueChanged<bool>? onInformation;
  final VoidCallback? onReference;
  final VoidCallback? onReady;
  const GameWatchVariantsView(
      {super.key,
      required this.variants,
      this.reducedMotion = false,
      this.inspectedIndex,
      this.informationVisible = false,
      this.onInspect,
      this.onInformation,
      this.onReference,
      this.onReady});
  @override
  State<GameWatchVariantsView> createState() => GameWatchVariantsViewState();
}

class GameWatchVariantsViewState extends State<GameWatchVariantsView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _sequence;
  late List<GameWatchUnboxingScene?> _scenes;
  late List<int> _durations;
  bool _resumed = true;
  int get _durationMs => _durations.fold(0, (sum, value) => sum + value);
  bool get _reduced =>
      widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
  double _progress(int index) {
    if (_durations[index] == 0) return 1;
    final prior = _durations.take(index).fold(0, (sum, value) => sum + value);
    return ((_sequence.value * _durationMs - prior) / _durations[index])
        .clamp(0.0, 1.0);
  }

  void _settleSequence() {
    _sequence.stop();
    _sequence.value = 1;
  }

  void _updateSequence() {
    if (_reduced || _inspected != null || _durationMs == 0) {
      _settleSequence();
    } else if (_reported && _resumed && _sequence.value < 1) {
      _sequence.forward();
    } else if (!_resumed) {
      _sequence.stop();
    }
  }

  void _reportSequence() {
    debugPrint('GShopGameWatchSequence ${jsonEncode({
          'settled': _sequence.value == 1,
          'running': _sequence.isAnimating,
          'foreground': _resumed,
          'reducedMotion': _reduced,
          'durationMs': _durationMs,
          'models': [
            for (var i = 0; i < _keys.length; i++)
              {
                'hardware': widget.variants[i].model.hardwareId,
                'box': widget.variants[i].box?.hardwareId,
                'progress': _progress(i),
                'frameRendered':
                    _keys[i].currentState?.snapshot['frameRendered'],
              }
          ],
        })}');
  }

  late List<GlobalKey<ConsoleHardwareViewState>> _keys;
  final _ready = <int>{};
  int _generation = 0;
  bool _reported = false;
  int? _localInspection;
  bool _localInformation = false;
  int? get _inspected {
    final index =
        widget.onInspect == null ? _localInspection : widget.inspectedIndex;
    return index != null && index >= 0 && index < widget.variants.length
        ? index
        : null;
  }

  bool get _information =>
      _inspected != null &&
      (widget.onInformation == null
          ? _localInformation
          : widget.informationVisible);
  void _inspect(int? index) {
    if (index != null) _settleSequence();
    if (widget.onInspect case final changed?) {
      changed(index);
    } else {
      setState(() {
        _localInspection = index;
        _localInformation = false;
      });
      _announceInspection();
    }
  }

  void _showInformation(bool visible) {
    if (widget.onInformation case final changed?) {
      changed(visible);
    } else {
      setState(() => _localInformation = visible);
      _announceInspection();
    }
  }

  void _announceInspection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _inspected;
      final model = index == null ? null : widget.variants[index].model;
      final state = index == null ? null : _keys[index].currentState?.snapshot;
      debugPrint('GShopGameWatchInspection ${jsonEncode({
            'hardware': model?.hardwareId,
            'informationVisible': _information,
            'sourceUrl': model == null
                ? null
                : GameWatchHardwareInfo.forHardware(model.hardwareId)
                    ?.sourceUrl,
            'geometrySha256': state?['geometrySha256'],
            'frameRendered': state?['frameRendered'],
            'rotationRunning': state?['rotationRunning'],
            'rotationPeriodMs': state?['rotationPeriodMs'],
            'reducedMotion': widget.reducedMotion,
            'layout': widget.variants.length > 1 ? 'semicircle' : 'single',
            'models': [
              for (var i = 0; i < _keys.length; i++)
                {
                  'hardware': widget.variants[i].model.hardwareId,
                  'yaw': _keys[i].currentState?.snapshot['manualYaw'],
                  'opening': _keys[i].currentState?.snapshot['opening'],
                }
            ],
          })}');
    });
  }

  String _signature(List<GameWatchModelVariant> models) => models
      .map((v) =>
          '${v.model.romSet}:${v.model.directory.path}:${v.model.generation}:${v.box?.generation}')
      .join('|');
  void _reset() {
    _sequence.stop();
    _scenes = [
      for (final variant in widget.variants)
        variant.box == null
            ? null
            : GameWatchUnboxingScene(variant.model, variant.box!)
    ];
    _durations = [
      for (var i = 0; i < widget.variants.length; i++)
        _scenes[i]?.durationMs ??
            (widget.variants[i].model.canOpen
                ? widget.variants[i].model.openingDurationMs
                : 0)
    ];
    _sequence.duration = Duration(milliseconds: math.max(1, _durationMs));
    _sequence.value = widget.reducedMotion || _durationMs == 0 ? 1 : 0;
    _generation++;
    _localInspection = null;
    _localInformation = false;
    _keys = [
      for (final _ in widget.variants) GlobalKey<ConsoleHardwareViewState>()
    ];
    _ready.clear();
    _reported = false;
  }

  Map<String, Object?> get snapshot => {
        'sequenceSettled': _sequence.value == 1,
        'sequenceRunning': _sequence.isAnimating,
        'sequenceProgress': [
          for (var i = 0; i < _keys.length; i++) _progress(i)
        ],
        'frameRendered': _reported,
        'expectedModels': widget.variants.length,
        'readyModels': _ready.length,
        'layout': widget.variants.length > 1 ? 'semicircle' : 'single',
        'inspectedIndex': _inspected,
        'informationVisible': _information,
        'error': _keys
            .map((key) => key.currentState?.snapshot['error'])
            .where((value) => value != null)
            .firstOrNull,
        'models': [for (final key in _keys) key.currentState?.snapshot],
      };
  void _rendered(int index, int generation) {
    if (!mounted || generation != _generation || _reported) return;
    _ready.add(index);
    if (_ready.length != widget.variants.length) return;
    _reported = true;
    final size = context.size;
    debugPrint('GShopGameWatchVariants ${jsonEncode({
          'frameRendered': true,
          'expected': widget.variants.length,
          'ready': _ready.length,
          'width': size?.width,
          'height': size?.height,
          'models': [
            for (var i = 0; i < _keys.length; i++)
              {
                'hardware': widget.variants[i].model.hardwareId,
                'geometrySha256':
                    _keys[i].currentState?.snapshot['geometrySha256'],
                'frameRendered':
                    _keys[i].currentState?.snapshot['frameRendered'],
                'error': _keys[i].currentState?.snapshot['error'],
              }
          ],
        })}');
    _updateSequence();
    _reportSequence();
    widget.onReady?.call();
  }

  @override
  void initState() {
    super.initState();
    _sequence = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final generation = _generation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && generation == _generation) _reportSequence();
          });
        }
      });
    WidgetsBinding.instance.addObserver(this);
    _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSequence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _updateSequence();
    _reportSequence();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sequence.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GameWatchVariantsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget.variants) != _signature(widget.variants)) _reset();
    _updateSequence();
    if (oldWidget.inspectedIndex != widget.inspectedIndex ||
        oldWidget.informationVisible != widget.informationVisible) {
      _announceInspection();
    }
  }

  String _label(int index) =>
      widget.variants[index].label ??
      GameWatchHardwareInfo.forHardware(widget.variants[index].model.hardwareId)
          ?.series ??
      'Hardware edition';

  Future<void> _source(GameWatchHardwareInfo? info) async {
    final opened = await launchUrl(
        Uri.parse(
            info?.sourceUrl ?? 'https://nintendogameandwatch.com/collection/'),
        mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The reference page could not be opened.')));
    }
  }

  Widget _informationPanel(int index, double height) {
    final info = GameWatchHardwareInfo.forHardware(
        widget.variants[index].model.hardwareId);
    return Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(64, height - 72)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Material(
                        key: const ValueKey('gamewatch-hardware-information'),
                        color: const Color(0xB3161113),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0x40FFFFFF))),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(info?.title ?? _label(index),
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text(_label(index),
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  if (info?.released case final released?) ...[
                                    const SizedBox(height: 6),
                                    Text('Released $released'),
                                  ],
                                  const SizedBox(height: 12),
                                  Text(
                                      info?.summary ??
                                          'This reference has no matching entry for this hardware edition.',
                                      style: const TextStyle(
                                          fontSize: 14, height: 1.45)),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                      onPressed: widget.onReference ??
                                          () => _source(info),
                                      icon: const Icon(Icons.open_in_new,
                                          size: 17),
                                      label: const Text(
                                          'NintendoGameAndWatch.com')),
                                ])))))));
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final generation = _generation;
        final count = widget.variants.length;
        final inspected = _inspected;
        final width = bounds.maxWidth, height = bounds.maxHeight;
        // Reserve margins once for the whole arc, rather than shrinking each
        // edition twice. Single-model and inspection cameras frame themselves.
        final arc = Rect.fromLTWH(
            width * .125, height * .125, width * .75, height * .75);
        final cellWidth = (arc.width - 12 * (count - 1)) / count;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          for (var i = 0; i < count; i++)
            Builder(builder: (context) {
              // Primary stays first in identity/catalogue order and occupies the
              // rear centre of the arc; the outer editions come toward the viewer.
              final centre = (count - 1) ~/ 2;
              final slot = i == 0
                  ? centre
                  : i <= centre
                      ? i - 1
                      : i;
              final angle = count == 1 ? 0.0 : (slot / (count - 1) - .5) * 1.9;
              final x = arc.center.dx +
                  (count == 1
                      ? 0
                      : (arc.width - cellWidth) /
                          2 *
                          math.sin(angle) /
                          math.sin(.95));
              final y = arc.top + arc.height * (.69 - .20 * math.cos(angle));
              final overview = count == 1
                  ? Rect.fromLTWH(0, 0, width, height)
                  : Rect.fromCenter(
                      center: Offset(x, y),
                      width: cellWidth,
                      height: arc.height * .78);
              final rect = inspected == i
                  ? Rect.fromLTWH(0, 48, width, math.max(1, height - 48))
                  : overview;
              final visible = inspected == null || inspected == i;
              return Positioned.fromRect(
                  rect: rect,
                  child: Offstage(
                      offstage: !visible,
                      child: TickerMode(
                          enabled: visible,
                          child: Stack(fit: StackFit.expand, children: [
                            IgnorePointer(
                                ignoring: _information,
                                child: Semantics(
                                    label: _label(i),
                                    child: ConsoleHardwareView(
                                        key: _keys[i],
                                        model: widget.variants[i].model,
                                        unboxingScene: _scenes[i],
                                        unboxingProgress: _progress(i),
                                        sequenceOpening: _sequence.value < 1
                                            ? (_scenes[i]?.handheldOpening(
                                                    _progress(i)) ??
                                                (widget.variants[i].model.canOpen
                                                    ? _progress(i)
                                                    : 0))
                                            : null,
                                        inspecting: inspected == i,
                                        compositionFill:
                                            inspected == null && count > 1
                                                ? 1
                                                : .75,
                                        onInteraction: _settleSequence,
                                        title: _label(i),
                                        showTitle: false,
                                        turntable: false,
                                        reducedMotion: widget.reducedMotion,
                                        informationRotation:
                                            inspected == i && _information,
                                        stagingYaw:
                                            inspected == null && count > 1
                                                ? .2 - angle * .35
                                                : 0,
                                        onInspect: inspected == null
                                            ? () => _inspect(i)
                                            : null,
                                        transparentBackground: true,
                                        onReady: () =>
                                            _rendered(i, generation)))),
                          ]))));
            }),
          if (inspected != null) ...[
            Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 48,
                child: Row(children: [
                  IconButton(
                      key: const ValueKey('gamewatch-inspection-back'),
                      tooltip:
                          _information ? 'Close information' : 'Back to models',
                      onPressed: () => _information
                          ? _showInformation(false)
                          : _inspect(null),
                      icon:
                          Icon(_information ? Icons.close : Icons.arrow_back)),
                  Expanded(
                      child: Text(_label(inspected),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600))),
                  IconButton(
                      key: const ValueKey('gamewatch-information-toggle'),
                      tooltip: _information
                          ? 'Hide hardware information'
                          : 'Hardware information',
                      onPressed: () => _showInformation(!_information),
                      icon:
                          Icon(_information ? Icons.info : Icons.info_outline)),
                ])),
            if (_information) _informationPanel(inspected, height),
          ],
        ]);
      });
}
