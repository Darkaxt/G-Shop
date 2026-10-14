import 'package:flutter/material.dart';

import '../../../models/game_item.dart';
import '../../../models/system_model.dart';
import '../../../utils/game_metadata.dart';
import '../../../widgets/smart_cover_image.dart';
import '../../../widgets/physical_media_view.dart';

class CoverSection extends StatefulWidget {
  final GameItem game;
  final SystemModel system;
  final List<String> coverUrls;
  final String? cachedUrl;
  final String? physicalLabelUrl;
  final String? gbcDualMode;
  final GameMetadataFull metadata;
  final bool isFavorite;
  final bool isInstalled;
  final bool hasThumbnail;
  final GlobalKey<PhysicalMediaViewState>? physicalMediaKey;
  final bool physicalMediaEnabled, reducedMotion;
  final bool showPresentationControls;
  const CoverSection({
    super.key,
    required this.game,
    required this.system,
    required this.coverUrls,
    this.cachedUrl,
    this.physicalLabelUrl,
    this.gbcDualMode,
    required this.metadata,
    this.isFavorite = false,
    this.isInstalled = false,
    this.hasThumbnail = false,
    this.physicalMediaKey,
    this.physicalMediaEnabled = true,
    this.reducedMotion = false,
    this.showPresentationControls = true,
  });

  @override
  State<CoverSection> createState() => _CoverSectionState();
}

class _CoverSectionState extends State<CoverSection> {
  bool _physical = true, _reducedMotion = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game, system = widget.system;
    final format = PhysicalMediaFormat.forSystem(system.id,
        region: widget.metadata.region.name, dualMode: widget.gbcDualMode);
    final physical = format != null && _physical && widget.physicalMediaEnabled;
    final sticker = HandwrittenMediaSticker(
        identity: game.selectionKey,
        title: game.displayName,
        disc: format == PhysicalMediaFormat.disc ||
            format == PhysicalMediaFormat.psp);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: physical
                    ? PhysicalMediaView(
                        key: widget.physicalMediaKey,
                        identity: game.selectionKey,
                        title: game.displayName,
                        format: format,
                        reducedMotion: _reducedMotion || widget.reducedMotion,
                        label: SmartCoverImage(
                            systemId: system.id,
                            urls: const [],
                            cachedUrl: widget.physicalLabelUrl,
                            placeholder: sticker,
                            errorWidget: sticker,
                            fit: BoxFit.fill,
                            memCacheWidth: 640))
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
              if (format != null &&
                  widget.physicalMediaEnabled &&
                  widget.showPresentationControls)
                Positioned(
                    top: 4,
                    right: 4,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: physical ? 'Cover view' : '3D media',
                          onPressed: () =>
                              setState(() => _physical = !_physical),
                          icon: Icon(physical
                              ? Icons.photo_rounded
                              : Icons.view_in_ar_rounded)),
                      if (physical)
                        IconButton(
                            tooltip: 'Reduced motion',
                            isSelected: _reducedMotion,
                            onPressed: () => setState(
                                () => _reducedMotion = !_reducedMotion),
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
