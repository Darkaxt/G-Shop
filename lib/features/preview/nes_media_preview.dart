import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import '../../models/nes_cartridge_model.dart';
import '../../models/nes_media_catalogue.dart';
import '../../models/nes_unboxing_scene.dart';
import '../../widgets/media_cover_fallback.dart';
import '../../widgets/physical_media_view.dart';
import 'console_hardware_view.dart';

/// Retail reference views preserve every supplied printing and shell choice.
/// Neither ROM program nor a matching title proves an owned manufacturing SKU.
class NesMediaPreview extends StatefulWidget {
  final String filename, identity, title;
  final Widget label;
  final Object labelIdentity;
  final bool reducedMotion;
  final bool resourcesReady;
  final bool informationVisible;
  final GlobalKey<PhysicalMediaViewState>? physicalMediaKey;
  final VoidCallback? onReady;
  final VoidCallback? onResolved;
  final VoidCallback? onResolving;
  final bool compact;
  const NesMediaPreview(
      {super.key,
      required this.filename,
      required this.identity,
      required this.title,
      required this.label,
      required this.labelIdentity,
      required this.reducedMotion,
      this.resourcesReady = true,
      this.informationVisible = false,
      this.onReady,
      this.onResolved,
      this.onResolving,
      this.compact = false,
      this.physicalMediaKey});
  @override
  State<NesMediaPreview> createState() => _NesMediaPreviewState();
}

class _NesMediaPreviewState extends State<NesMediaPreview> {
  List<String> _styles = const [];
  String? _style;
  int _edition = 0, _generation = 0;
  bool _boxReady = false, _cartridgeReady = false, _reported = false;
  bool _inspectInside = false;
  int? _resolvedGeneration;
  String? _renderedBoxEdition;
  final _localPhysicalKey = GlobalKey<PhysicalMediaViewState>();
  GlobalKey<PhysicalMediaViewState> get _physicalKey =>
      widget.physicalMediaKey ?? _localPhysicalKey;
  late Future<List<NesBoxEdition>> _editions;
  Future<ConsoleModel?>? _box;
  List<NesBoxEdition>? _choices;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _generation++;
    _styles = NesCartridgeModel.referencesFor(widget.filename);
    _style = _styles.firstOrNull;
    _inspectInside = false;
    _edition = 0;
    _box = null;
    _choices = null;
    _boxReady = false;
    _renderedBoxEdition = null;
    _cartridgeReady = _style == null;
    _reported = false;
    _editions = NesMediaCatalogue.load().then(
        (catalogue) => catalogue?.forArchive(widget.filename) ?? const []);
  }

  @override
  void didUpdateWidget(NesMediaPreview old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity || old.filename != widget.filename)
      _reset();
    if (old.labelIdentity != widget.labelIdentity) {
      _generation++;
      _cartridgeReady = _style == null;
      _reported = false;
    }
    if (old.resourcesReady != widget.resourcesReady) _reported = false;
  }

  void _ready(int generation, {bool box = false, bool cartridge = false}) {
    if (!mounted || generation != _generation) return;
    _boxReady = _boxReady || box;
    _cartridgeReady = _cartridgeReady || cartridge;
    if (!_boxReady || !_cartridgeReady || _reported || !widget.resourcesReady)
      return;
    _reported = true;
    debugPrint('GShopNesMediaReady ${jsonEncode({
          'identity': widget.identity,
          'ready': true,
          'cartridgeRendered': _style != null,
          'boxEdition': _renderedBoxEdition,
          'cartridgeStyle': _style,
          'referenceOnly': true
        })}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation && widget.resourcesReady) {
        widget.onReady?.call();
      }
    });
  }

  Widget _fallback() => MediaCoverFallback(
      systemId: 'nes',
      title: widget.title,
      identity: widget.identity,
      backgroundColor: Colors.transparent);
  void _resolved(int generation) {
    if (_resolvedGeneration == generation) return;
    _resolvedGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _generation == generation) widget.onResolved?.call();
    });
  }

  Widget _cartridge(int generation, {NesUnboxingScene? scene}) {
    final style = _style;
    if (style == null) return _fallback();
    return PhysicalMediaView(
        key: _physicalKey,
        identity: '${widget.identity}:$style',
        title: widget.title,
        format: PhysicalMediaFormat.nes,
        cartridgeStyle: style,
        nesScene: scene,
        resourcesReady: widget.resourcesReady,
        informationVisible: widget.informationVisible,
        inspectInside: _inspectInside,
        label: widget.label,
        labelIdentity: widget.labelIdentity,
        reducedMotion: widget.reducedMotion,
        onReady: () {
          if (generation != _generation || style != _style) return;
          if (scene != null) _renderedBoxEdition = scene.box.retailEditionId;
          _ready(generation, box: scene != null, cartridge: true);
        });
  }

  void _changedSelection({bool box = false}) {
    widget.onResolving?.call();
    _generation++;
    _inspectInside = false;
    _cartridgeReady = _style == null;
    _reported = false;
    if (box) {
      _boxReady = false;
      _renderedBoxEdition = null;
    }
  }

  void _replay() {
    final generation = _generation;
    setState(() => _inspectInside = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation)
        _physicalKey.currentState?.replayUnboxing();
    });
  }

  void _selectStyle(String style) {
    if (style == _style) return;
    final layoutChanged = _styles.contains(style) != _styles.contains(_style);
    setState(() {
      _style = style;
      _changedSelection(box: layoutChanged);
    });
  }

  @override
  Widget build(BuildContext context) {
    _ready(_generation);
    final generation = _generation;
    return FutureBuilder<List<NesBoxEdition>>(
        future: _editions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          final choices = _choices ??= snapshot.data ?? const [];
          if (choices.isEmpty && _styles.isEmpty && _style == null) {
            _resolved(generation);
            _ready(generation, box: true);
            return Stack(fit: StackFit.expand, children: [
              _fallback(),
              Positioned(bottom: 4, right: 4, child: _referenceMenu())
            ]);
          }
          if (choices.isNotEmpty) _box ??= choices[_edition].load();
          final unboxing =
              choices.isNotEmpty && _style != null && _styles.contains(_style);
          return Stack(fit: StackFit.expand, children: [
            Column(children: [
              if (!widget.compact) ...[
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                        'Reference editions · exact physical edition may differ',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.white60))),
                Row(children: [
                  if (choices.isNotEmpty)
                    Expanded(
                        child: DropdownButton<int>(
                            value: _edition,
                            isExpanded: true,
                            items: [
                              for (var i = 0; i < choices.length; i++)
                                DropdownMenuItem(
                                    value: i,
                                    child: Text(choices[i].label,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)))
                            ],
                            onChanged: (i) {
                              if (i == null || i == _edition) return;
                              setState(() {
                                _edition = i;
                                _box = choices[i].load();
                                _changedSelection(box: true);
                              });
                            })),
                  if (choices.isNotEmpty && _style != null)
                    const SizedBox(width: 12),
                  if (_style != null)
                    Expanded(
                        child: DropdownButton<String>(
                            value: _style,
                            isExpanded: true,
                            items: [
                              for (final style in {
                                ..._styles,
                                if (_style != null) _style!
                              })
                                DropdownMenuItem(
                                    value: style,
                                    child: Text(
                                        NesCartridgeModel.labels[style]!,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)))
                            ],
                            onChanged: (style) {
                              if (style == null || style == _style) return;
                              _selectStyle(style);
                            })),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (unboxing)
                    IconButton(
                        tooltip: 'Zoom cartridge',
                        onPressed: () => _physicalKey.currentState
                            ?.inspectCartridge(toggle: true),
                        icon: const Icon(Icons.zoom_in)),
                  if (unboxing)
                    IconButton(
                        tooltip: 'Replay unboxing',
                        onPressed: _replay,
                        icon: const Icon(Icons.replay)),
                  if (_style != null &&
                      NesCartridgeModel.hasInspection(_style!))
                    IconButton(
                        tooltip: _inspectInside
                            ? 'Assemble cartridge'
                            : 'Inspect inside',
                        icon: Icon(_inspectInside
                            ? Icons.close_fullscreen
                            : Icons.open_in_full),
                        onPressed: () =>
                            setState(() => _inspectInside = !_inspectInside)),
                  _referenceMenu(),
                ]),
              ],
              Expanded(
                  child: FutureBuilder<ConsoleModel?>(
                      future: _box,
                      builder: (context, boxSnapshot) {
                        if (_box != null &&
                            boxSnapshot.connectionState != ConnectionState.done)
                          return const Center(
                              child: CircularProgressIndicator());
                        final model = boxSnapshot.data;
                        _resolved(generation);
                        if (unboxing && model != null)
                          return _cartridge(generation,
                              scene: NesUnboxingScene(model, _style!));
                        if (model == null) _ready(generation, box: true);
                        return Row(children: [
                          if (choices.isNotEmpty)
                            Expanded(
                                child: model == null
                                    ? _fallback()
                                    : ConsoleHardwareView(
                                        key: ValueKey(model.generation),
                                        model: model,
                                        title: 'Reference box',
                                        showTitle: false,
                                        turntable: false,
                                        transparentBackground: true,
                                        reducedMotion: widget.reducedMotion,
                                        onReady: () {
                                          if (generation != _generation) return;
                                          _renderedBoxEdition =
                                              model.retailEditionId;
                                          _ready(generation, box: true);
                                        })),
                          if (choices.isNotEmpty) const SizedBox(width: 12),
                          Expanded(child: _cartridge(generation)),
                        ]);
                      })),
            ]),
            if (widget.compact)
              Positioned(
                  top: 4, right: 4, child: _sceneMenu(choices, unboxing)),
          ]);
        });
  }

  Widget _sceneMenu(List<NesBoxEdition> choices, bool unboxing) =>
      PopupMenuButton<String>(
          tooltip: '3D scene options',
          icon: const Icon(Icons.more_vert),
          itemBuilder: (_) => [
                if (unboxing) ...[
                  const PopupMenuItem(
                      value: 'zoom', child: Text('Zoom cartridge')),
                  const PopupMenuItem(
                      value: 'replay', child: Text('Replay unboxing')),
                ],
                if (_style != null && NesCartridgeModel.hasInspection(_style!))
                  PopupMenuItem(
                      value: 'inside',
                      child: Text(_inspectInside
                          ? 'Assemble cartridge'
                          : 'Inspect inside')),
                if (choices.isNotEmpty) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      enabled: false, child: Text('Reference box edition')),
                  for (var i = 0; i < choices.length; i++)
                    PopupMenuItem(
                        value: 'box:$i', child: Text(choices[i].label)),
                ],
                const PopupMenuDivider(),
                const PopupMenuItem(
                    enabled: false, child: Text('Cartridge references')),
                for (final style in _styles)
                  PopupMenuItem(
                      value: 'style:$style',
                      child: Text(NesCartridgeModel.labels[style]!)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    enabled: false, child: Text('Other reference models')),
                for (final e in NesCartridgeModel.labels.entries
                    .where((e) => !_styles.contains(e.key)))
                  PopupMenuItem(value: 'style:${e.key}', child: Text(e.value)),
              ],
          onSelected: (value) {
            if (value == 'zoom') {
              _physicalKey.currentState?.inspectCartridge(toggle: true);
            } else if (value == 'replay') {
              _replay();
            } else if (value == 'inside') {
              setState(() => _inspectInside = !_inspectInside);
            } else if (value.startsWith('style:')) {
              _selectStyle(value.substring(6));
            } else if (value.startsWith('box:')) {
              final index = int.parse(value.substring(4));
              setState(() {
                _edition = index;
                _box = choices[index].load();
                _changedSelection(box: true);
              });
            }
          });

  Widget _referenceMenu() => PopupMenuButton<String>(
      tooltip: 'Other reference models',
      icon: const Icon(Icons.view_in_ar_outlined),
      itemBuilder: (_) => [
            for (final e in NesCartridgeModel.labels.entries)
              PopupMenuItem(value: e.key, child: Text(e.value))
          ],
      onSelected: _selectStyle);
}
