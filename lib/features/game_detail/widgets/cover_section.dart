import 'package:flutter/material.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../models/game_item.dart';
import '../../../models/system_model.dart';
import '../../../utils/game_metadata.dart';
import '../../../widgets/smart_cover_image.dart';
import '../../../widgets/physical_media_view.dart';
import '../../../widgets/media_cover_fallback.dart';
import '../../../widgets/cover_reveal.dart';
import '../../../services/image_cache_service.dart';

class CoverSection extends StatefulWidget {
  final GameItem game;
  final SystemModel system;
  final List<String> coverUrls;
  final String? cachedUrl;
  final String? physicalLabelUrl;
  final String? gbcDualMode;
  final int? boxArtDecodeWidth;
  final GameMetadataFull metadata;
  final bool isFavorite;
  final bool isInstalled;
  final bool hasThumbnail;
  final GlobalKey<PhysicalMediaViewState>? physicalMediaKey;
  final bool physicalMediaEnabled, reducedMotion;
  final bool showPresentationControls;
  final bool resourcesReady;
  final VoidCallback? onReady;
  final VoidCallback? onRevealed;
  const CoverSection({
    super.key,
    required this.game,
    required this.system,
    required this.coverUrls,
    this.cachedUrl,
    this.physicalLabelUrl,
    this.gbcDualMode,
    this.boxArtDecodeWidth,
    required this.metadata,
    this.isFavorite = false,
    this.isInstalled = false,
    this.hasThumbnail = false,
    this.physicalMediaKey,
    this.physicalMediaEnabled = false,
    this.reducedMotion = false,
    this.showPresentationControls = true,
    this.resourcesReady = true,
    this.onReady,
    this.onRevealed,
  });

  @override
  CoverSectionState createState() => CoverSectionState();
}

class CoverSectionState extends State<CoverSection> {
  bool _physical = true, _reducedMotion = false;
  bool _modelReady = false;
  ImageInfo? _label;
  ImageStream? _labelStream;
  ImageStreamListener? _labelListener;
  int _labelGeneration = 0;
  String? _labelUrl;
  Map<String, Object?> get renderSnapshot => {
        'coverExpected': widget.cachedUrl != null || widget.coverUrls.isNotEmpty,
        'labelExpected': widget.physicalLabelUrl != null,
        'labelDecoded': widget.physicalLabelUrl != null && _label != null,
        'resourcesReady': widget.resourcesReady,
        'modelReady': _modelReady,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLabel();
  }

  @override
  void didUpdateWidget(CoverSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.selectionKey != widget.game.selectionKey ||
        oldWidget.system.id != widget.system.id ||
        oldWidget.physicalMediaEnabled != widget.physicalMediaEnabled) {
      _modelReady = false;
    }
    _loadLabel();
  }

  void _detachLabel() {
    _labelGeneration++;
    final listener = _labelListener;
    if (listener != null) _labelStream?.removeListener(listener);
    _labelStream = null;
    _labelListener = null;
  }

  void _loadLabel() {
    final url = widget.physicalLabelUrl;
    if (url == _labelUrl) return;
    _detachLabel();
    _labelUrl = url;
    _label?.dispose();
    _label = null;
    _modelReady = false;
    if (url == null) return;
    final ImageProvider provider;
    if (url.startsWith('file://')) {
      provider = FileImage(File.fromUri(Uri.parse(url)));
    } else {
      provider = CachedNetworkImageProvider(url,
          cacheManager: GameCoverCacheManager.instance);
    }
    final generation = _labelGeneration;
    _labelStream = ResizeImage.resizeIfNeeded(640, null, provider)
        .resolve(createLocalImageConfiguration(context));
    _labelListener = ImageStreamListener((image, synchronous) {
      if (!mounted || generation != _labelGeneration) return;
      void resolved() {
        _label = image.clone();
        _modelReady = false;
        _detachLabel();
      }

      if (synchronous) {
        resolved();
      } else {
        setState(resolved);
      }
    }, onError: (_, __) {
      if (generation == _labelGeneration) _detachLabel();
    });
    _labelStream!.addListener(_labelListener!);
  }

  @override
  void dispose() {
    _detachLabel();
    _label?.dispose();
    super.dispose();
  }

  bool get physical => _physical;
  void toggleView() => setState(() => _physical = !_physical);
  void toggleMotion() => setState(() => _reducedMotion = !_reducedMotion);

  @override
  Widget build(BuildContext context) {
    final game = widget.game, system = widget.system;
    final format = PhysicalMediaFormat.forSystem(system.id,
        region: widget.metadata.region.name, dualMode: widget.gbcDualMode);
    final physical = _physical;
    final threeD = format != null && widget.physicalMediaEnabled;
    final url = widget.cachedUrl ?? widget.coverUrls.firstOrNull;
    final ImageProvider? originalBoxArt;
    if (url == null) {
      originalBoxArt = null;
    } else if (url.startsWith('file://')) {
      originalBoxArt = FileImage(File.fromUri(Uri.parse(url)));
    } else {
      originalBoxArt = CachedNetworkImageProvider(url,
          cacheManager: GameCoverCacheManager.instance);
    }
    final ImageProvider? boxArt = originalBoxArt == null
        ? null
        : ResizeImage.resizeIfNeeded(
            widget.boxArtDecodeWidth, null, originalBoxArt);
    final sticker = HandwrittenMediaSticker(
        identity: game.selectionKey,
        title: game.displayName,
        disc: format == PhysicalMediaFormat.disc ||
            format == PhysicalMediaFormat.psp);
    final label = _label?.image;
    final labelWidget =
        label == null ? sticker : RawImage(image: label, fit: BoxFit.fill);
    final mediaReady = widget.resourcesReady &&
        (widget.physicalLabelUrl == null || label != null) &&
        (!threeD || _modelReady);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: physical
                    ? CoverReveal(
                        identity: '${system.id}:${game.selectionKey}',
                        boxArt: boxArt,
                        mediaReady: mediaReady,
                        onReady: widget.onReady,
                        onRevealed: widget.onRevealed,
                        reducedMotion: _reducedMotion || widget.reducedMotion,
                        media: threeD
                            ? PhysicalMediaView(
                                key: widget.physicalMediaKey,
                                identity: game.selectionKey,
                                title: game.displayName,
                                format: format,
                                reducedMotion:
                                    _reducedMotion || widget.reducedMotion,
                                label: labelWidget,
                                labelIdentity: label ??
                                    '${game.selectionKey}:${widget.physicalLabelUrl ?? game.displayName}',
                                onReady: () {
                                  if (mounted &&
                                      !_modelReady &&
                                      identical(label, _label?.image)) {
                                    setState(() => _modelReady = true);
                                  }
                                })
                            : MediaCoverFallback(
                                systemId: system.id,
                                title: game.displayName,
                                identity: game.selectionKey,
                                physicalLabel: widget.physicalLabelUrl == null
                                    ? null
                                    : labelWidget,
                                backgroundColor: Colors.transparent))
                    : Hero(
                        tag: game.filename,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    system.accentColor.withValues(alpha: 0.3),
                                blurRadius: 40,
                                spreadRadius: -5,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 25,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SmartCoverImage(
                                systemId: system.id,
                                fallbackTitle: game.displayName,
                                fallbackIdentity: game.selectionKey,
                                urls: widget.coverUrls,
                                cachedUrl: widget.cachedUrl,
                                fit: BoxFit.contain,
                                hasThumbnail: widget.hasThumbnail,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              if (widget.showPresentationControls)
                Positioned(
                    top: 4,
                    right: 4,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: physical ? 'Cover view' : 'Media preview',
                          onPressed: toggleView,
                          icon: Icon(physical
                              ? Icons.photo_rounded
                              : Icons.album_outlined)),
                      if (physical)
                        IconButton(
                            tooltip: 'Reduced motion',
                            isSelected: _reducedMotion,
                            onPressed: toggleMotion,
                            icon: const Icon(Icons.motion_photos_off_rounded)),
                    ])),
              if (widget.isFavorite)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
