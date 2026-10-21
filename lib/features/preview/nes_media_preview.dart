import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import '../../models/nes_cartridge_model.dart';
import '../../models/nes_media_catalogue.dart';
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
  final GlobalKey<PhysicalMediaViewState>? physicalMediaKey;
  final VoidCallback? onReady;
  const NesMediaPreview(
      {super.key,
      required this.filename,
      required this.identity,
      required this.title,
      required this.label,
      required this.labelIdentity,
      required this.reducedMotion,
      this.resourcesReady = true,
      this.onReady,
      this.physicalMediaKey});
  @override
  State<NesMediaPreview> createState() => _NesMediaPreviewState();
}

class _NesMediaPreviewState extends State<NesMediaPreview> {
  List<String> _styles = const [];
  String? _style;
  int _edition = 0, _generation = 0;
  bool _boxReady = false, _cartridgeReady = false, _reported = false;
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
    _edition = 0;
    _box = null;
    _choices = null;
    _boxReady = false;
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
          'boxEdition':
              _choices?.isNotEmpty == true ? _choices![_edition].id : null,
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
  @override
  Widget build(BuildContext context) {
    _ready(_generation);
    final generation = _generation;
    final cartridgeStyle = _style;
    return FutureBuilder<List<NesBoxEdition>>(
        future: _editions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final choices = _choices ??= snapshot.data ?? const [];
          if (choices.isNotEmpty) _box ??= choices[_edition].load();
          return Column(children: [
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                    'Reference editions · exact physical edition may differ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white60))),
            Expanded(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(
                      child: Column(children: [
                    if (choices.isNotEmpty)
                      DropdownButton<int>(
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
                              _boxReady = false;
                              _reported = false;
                            });
                          }),
                    Expanded(
                        child: FutureBuilder<ConsoleModel?>(
                            future: _box,
                            builder: (context, boxSnapshot) {
                              if (_box != null &&
                                  boxSnapshot.connectionState !=
                                      ConnectionState.done) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final model = boxSnapshot.data;
                              if (model == null) {
                                if (choices.isEmpty ||
                                    boxSnapshot.connectionState ==
                                        ConnectionState.done) {
                                  _ready(generation, box: true);
                                }
                                return _fallback();
                              }
                              return ConsoleHardwareView(
                                  key: ValueKey(model.generation),
                                  model: model,
                                  title: 'Reference box',
                                  showTitle: false,
                                  turntable: false,
                                  transparentBackground: true,
                                  reducedMotion: widget.reducedMotion,
                                  onReady: () {
                                    if (choices[_edition].id ==
                                        model.retailEditionId) {
                                      _ready(generation, box: true);
                                    }
                                  });
                            })),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(children: [
                    if (_styles.isNotEmpty)
                      DropdownButton<String>(
                          value: _style,
                          isExpanded: true,
                          items: [
                            for (final style in _styles)
                              DropdownMenuItem(
                                  value: style,
                                  child: Text(NesCartridgeModel.labels[style]!,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12)))
                          ],
                          onChanged: (style) {
                            if (style == null || style == _style) return;
                            setState(() {
                              _style = style;
                              _cartridgeReady = false;
                              _reported = false;
                            });
                          }),
                    Expanded(
                        child: _style == null
                            ? _fallback()
                            : PhysicalMediaView(
                                key: widget.physicalMediaKey ??
                                    ValueKey('${widget.identity}:$_style'),
                                identity: '${widget.identity}:$_style',
                                title: widget.title,
                                format: PhysicalMediaFormat.nes,
                                cartridgeStyle: _style,
                                label: widget.label,
                                labelIdentity: widget.labelIdentity,
                                reducedMotion: widget.reducedMotion,
                                onReady: () {
                                  if (_style == cartridgeStyle) {
                                    _ready(generation, cartridge: true);
                                  }
                                })),
                  ])),
                ])),
          ]);
        });
  }
}
