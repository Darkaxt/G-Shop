import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/responsive/responsive.dart';
import '../core/util/color_contrast.dart';
import '../l10n/app_localizations.dart';
import '../models/download_item.dart';
import '../models/ra_models.dart';
import '../services/metadata/effective_overall_rating.dart';
import 'installed_indicator.dart';
import 'smart_cover_image.dart';

class BaseGameCard extends StatelessWidget {
  // Core
  final String displayName;
  final String? systemId;
  final List<String> coverUrls;
  final String? cachedUrl;
  final bool isInstalled;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  // Optional badges
  final bool isFavorite;
  final String? systemLabel;
  final int variantCount;
  final String? providerLabel;
  final int? raAchievementCount;
  final RaMatchType raMatchType;
  final bool isMastered;
  final EffectiveOverallRating? overallRating;
  final bool showRating;

  /// Optional color for the small "source dot" rendered in the bottom-
  /// right corner of the cover. When `null`, no dot is drawn — used for
  /// games that come from legacy/unmanaged providers or for cards
  /// outside the v3 source pipeline.
  /// Optional list of additional source dots beyond the primary one. Each
  /// entry renders as a small dot stacked to the left of the primary, in
  /// reverse order so the primary stays right-most. Empty list = single dot.
  final List<SourceDotData>? extraSourceDots;
  final Color? sourceDotColor;

  /// When `true`, the source dot is rendered with a hollow ring + share
  /// glyph instead of a solid circle, marking games that came from a
  /// borrowed (read-only / shared) source.
  final bool sourceDotBorrowed;

  // Download status overlay
  final DownloadStatus? downloadStatus;
  final double downloadProgress;

  // Thumbnail pipeline
  final bool hasThumbnail;
  final void Function(String url)? onThumbnailNeeded;

  // Performance
  final int memCacheWidth;
  final ValueNotifier<bool>? scrollSuppression;

  // Optional behavior
  final FocusNode? focusNode;
  final VoidCallback? onTapSelect;
  final VoidCallback? onLongPress;
  final void Function(String)? onCoverFound;

  const BaseGameCard({
    super.key,
    required this.displayName,
    this.systemId,
    required this.coverUrls,
    required this.cachedUrl,
    required this.isInstalled,
    required this.isSelected,
    this.isFavorite = false,
    required this.accentColor,
    required this.onTap,
    this.systemLabel,
    this.variantCount = 0,
    this.providerLabel,
    this.raAchievementCount,
    this.raMatchType = RaMatchType.none,
    this.isMastered = false,
    this.overallRating,
    this.showRating = true,
    this.hasThumbnail = false,
    this.onThumbnailNeeded,
    this.memCacheWidth = 500,
    this.scrollSuppression,
    this.focusNode,
    this.onTapSelect,
    this.onLongPress,
    this.onCoverFound,
    this.sourceDotColor,
    this.sourceDotBorrowed = false,
    this.extraSourceDots,
    this.downloadStatus,
    this.downloadProgress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final selectedScale = rs.isSmall ? 1.08 : 1.1;
    final borderSelected = rs.isSmall ? 2.0 : 3.0;
    final titleFontSize =
        isSelected ? (rs.isSmall ? 9.0 : 11.0) : (rs.isSmall ? 7.0 : 9.0);
    final variantFontSize = rs.isSmall ? 6.0 : 8.0;
    final padding = rs.isSmall ? 4.0 : 6.0;
    final borderRadius = rs.isSmall ? 8.0 : 10.0;
    final innerBorderRadius = rs.isSmall ? 6.0 : 8.0;
    final favoritePadding = rs.isSmall ? 3.0 : 4.0;
    final favoriteIconSize = rs.isSmall ? 10.0 : 14.0;

    Widget card = GestureDetector(
      onTapDown: (_) => onTapSelect?.call(),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Transform.scale(
        scale: isSelected ? selectedScale : 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: isSelected
                ? Border.all(color: Colors.white, width: borderSelected)
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.08), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerBorderRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFF151515),
                  child: SmartCoverImage(
                    systemId: systemId,
                    urls: coverUrls,
                    cachedUrl: cachedUrl,
                    fit: BoxFit.contain,
                    onUrlFound: onCoverFound,
                    hasThumbnail: hasThumbnail,
                    onThumbnailNeeded: onThumbnailNeeded,
                    memCacheWidth: memCacheWidth,
                    scrollSuppression: scrollSuppression,
                  ),
                ),
                // Download progress overlay — cover reveals from bottom to top
                if (downloadStatus != null && !downloadStatus!.isTerminal)
                  Positioned.fill(
                    child: _DownloadRevealOverlay(
                      status: downloadStatus!,
                      progress: downloadProgress,
                      accentColor: accentColor,
                    ),
                  ),
                // Header and caption share a bounded column. Actual localized
                // badge heights reserve space instead of overlapping the title
                // or score when text is enlarged on compact cards.
                Positioned.fill(
                  child: Column(children: [
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(padding, padding, padding, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (systemLabel != null)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: rs.isSmall ? 4.0 : 5.0,
                                      vertical: rs.isSmall ? 1.5 : 2.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentColor.forText
                                          .withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      systemLabel!.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: rs.isSmall ? 5.0 : 6.0,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                if (isInstalled) ...[
                                  if (systemLabel != null)
                                    SizedBox(height: rs.isSmall ? 2.0 : 3.0),
                                  _InstalledBadge(isSmall: rs.isSmall),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isFavorite)
                                Container(
                                  padding: EdgeInsets.all(favoritePadding),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.favorite,
                                    size: favoriteIconSize,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              if (raAchievementCount != null &&
                                  raAchievementCount! > 0 &&
                                  raMatchType != RaMatchType.none) ...[
                                if (isFavorite)
                                  SizedBox(height: rs.isSmall ? 2.0 : 3.0),
                                _RaBadge(
                                  count: raAchievementCount!,
                                  matchType: raMatchType,
                                  isMastered: isMastered,
                                  isSmall: rs.isSmall,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (downloadStatus != null && !downloadStatus!.isTerminal)
                      _DownloadStatusIndicator(
                        status: downloadStatus!,
                        progress: downloadProgress,
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            padding,
                            0,
                            padding,
                            padding,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.95),
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showRating && overallRating != null) ...[
                                _CoverRating(
                                    rating: overallRating!,
                                    isSmall: rs.isSmall),
                                SizedBox(height: rs.isSmall ? 3 : 4),
                              ],
                              Flexible(
                                child: LayoutBuilder(
                                    builder: (context, constraints) {
                                  final style = TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.2,
                                    shadows: [
                                      Shadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.9),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  );
                                  final metrics = TextPainter(
                                    text: TextSpan(text: 'M', style: style),
                                    textDirection: Directionality.of(context),
                                    textScaler:
                                        MediaQuery.textScalerOf(context),
                                  )..layout();
                                  final lines = (constraints.maxHeight /
                                          metrics.preferredLineHeight)
                                      .floor()
                                      .clamp(1, 2);
                                  metrics.dispose();
                                  return Text(
                                    displayName,
                                    style: style,
                                    maxLines: lines,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                }),
                              ),
                              if (variantCount > 1 ||
                                  providerLabel != null ||
                                  sourceDotColor != null)
                                Row(
                                  children: [
                                    Expanded(
                                        child: Row(children: [
                                      if (variantCount > 1)
                                        Flexible(
                                            child: Text(
                                          L.of(context).gameCard_variantCount(
                                              variantCount),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: variantFontSize,
                                            color: Colors.grey[400],
                                          ),
                                        )),
                                      if (providerLabel != null) ...[
                                        if (variantCount > 1)
                                          Text(
                                            ' · ',
                                            style: TextStyle(
                                              fontSize: variantFontSize,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        Flexible(
                                            child: Text(
                                          providerLabel!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: rs.isSmall ? 6.0 : 7.0,
                                            color: Colors.grey[500],
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        )),
                                      ],
                                    ])),
                                    if (sourceDotColor != null) ...[
                                      const SizedBox(width: 4),
                                      _SourceDotRow(
                                        primary: SourceDotData(
                                          color: sourceDotColor!,
                                          borrowed: sourceDotBorrowed,
                                        ),
                                        extras: extraSourceDots ?? const [],
                                        isSmall: rs.isSmall,
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                // Installed LED strip (above gradient so it's visible)
                if (isInstalled)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: InstalledLedStrip(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(innerBorderRadius),
                        bottomRight: Radius.circular(innerBorderRadius),
                      ),
                    ),
                  ),
                // Selection line
                if (isSelected)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: rs.isSmall ? 2 : 3,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (focusNode != null) {
      card = Focus(
        focusNode: focusNode,
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: card,
      );
    }

    return card;
  }
}

/// Pure rendering: callers supply the same cached selector used by ranking.
/// No provider, database, image mutation or focus target is introduced here.
class _CoverRating extends StatelessWidget {
  final EffectiveOverallRating rating;
  final bool isSmall;
  const _CoverRating({required this.rating, required this.isSmall});

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final source = rating.rating;
    final ownership = switch (rating.ownership) {
      OverallRatingOwnership.game => l.metadata_gameScore,
      OverallRatingOwnership.originalGame => l.metadata_originalGame,
      OverallRatingOwnership.project => l.metadata_projectScore,
    };
    final states = [
      if (!rating.fresh) l.metadata_staleScore,
      if (rating.ownership != OverallRatingOwnership.game) ownership,
      if (rating.fresh && !rating.rankingEligible) l.metadata_advisoryScore,
    ];
    final scoreDetails = l.metadata_scoreDetails(
      source.sourceLabel,
      _number(source.normalizedValue),
      source.rawValue,
      _number(source.scaleMinimum),
      _number(source.scaleMaximum),
      source.voteCount?.toString() ?? l.metadata_unknownCount,
      source.retrievedAt.toIso8601String().split('T').first,
    );
    final details = '$scoreDetails $ownership'
        '${states.isEmpty ? '' : '. ${states.join(' · ')}'}';
    final color = rating.fresh && rating.rankingEligible
        ? const Color(0xFFF3D98B)
        : const Color(0xFFCCCCCC);
    return Semantics(
      label: details,
      child: ExcludeSemantics(
          child: Tooltip(
        message: details,
        child: Container(
          key: const ValueKey('cover-rating'),
          padding: EdgeInsets.symmetric(
              horizontal: isSmall ? 4 : 5, vertical: isSmall ? 0 : 3),
          decoration: BoxDecoration(
              color: const Color(0xED171717),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.6))),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (source.sourceId == 'igdb') ...[
                    // The upstream square canvas contains a wide wordmark.
                    // Crop only its transparent vertical margin in layout so
                    // the icon does not increase the caption's line height.
                    ClipRect(
                        child: Align(
                            widthFactor: 1,
                            heightFactor: 0.5,
                            child: SvgPicture.asset(
                                'assets/rating_sources/igdb.svg',
                                key: const ValueKey('rating-source-igdb'),
                                width: isSmall ? 14 : 18,
                                height: isSmall ? 14 : 18,
                                excludeFromSemantics: true,
                                colorFilter:
                                    ColorFilter.mode(color, BlendMode.srcIn)))),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                      child: Text(
                          '${source.sourceId == 'igdb' ? '' : '${source.sourceLabel} '}${_number(source.normalizedValue)}/100',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: isSmall ? 7 : 9,
                              height: isSmall ? 1 : null,
                              fontWeight: FontWeight.w700,
                              color: color))),
                ]),
                if (states.isNotEmpty)
                  Text(states.join(' · '),
                      maxLines: isSmall ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: isSmall ? 6 : 7,
                          color: color,
                          height: isSmall ? 1 : 1.2)),
              ]),
        ),
      )),
    );
  }
}

class _InstalledBadge extends StatelessWidget {
  final bool isSmall;
  const _InstalledBadge({required this.isSmall});

  @override
  Widget build(BuildContext context) {
    final iconSize = isSmall ? 10.0 : 13.0;
    final fontSize = isSmall ? 6.0 : 7.5;
    final hPad = isSmall ? 4.0 : 5.0;
    final vPad = isSmall ? 2.0 : 3.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: const Color(0xCC0A3A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.greenAccent.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.25),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: iconSize,
            color: Colors.greenAccent,
          ),
          SizedBox(width: isSmall ? 2 : 3),
          Flexible(
              child: Text(
            L.of(context).common_installed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: Colors.greenAccent,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          )),
        ],
      ),
    );
  }
}

class _RaBadge extends StatelessWidget {
  final int count;
  final RaMatchType matchType;
  final bool isMastered;
  final bool isSmall;

  const _RaBadge({
    required this.count,
    required this.matchType,
    this.isMastered = false,
    required this.isSmall,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color accent, Color border) =
        switch ((matchType, isMastered)) {
      (RaMatchType.hashIncompatible, _) => (
          const Color(0xCC424242),
          Colors.grey,
          Colors.grey.withValues(alpha: 0.3),
        ),
      (_, true) => (
          const Color(0xCC0A3A0A),
          Colors.greenAccent,
          Colors.greenAccent.withValues(alpha: 0.4),
        ),
      _ => (
          const Color(0xDD5D4200),
          const Color(0xFFFFD54F),
          const Color(0xFFFFD54F).withValues(alpha: 0.4),
        ),
    };

    final fontSize = isSmall ? 8.0 : 10.0;
    final iconSize = isSmall ? 11.0 : 14.0;
    final hPad = isSmall ? 4.0 : 5.0;
    final vPad = isSmall ? 3.0 : 4.0;

    return Container(
      key: const ValueKey('achievement-badge'),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: isMastered ? 12 : 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            matchType == RaMatchType.hashIncompatible
                ? Icons.emoji_events_outlined
                : Icons.emoji_events,
            size: iconSize,
            color: accent,
          ),
          SizedBox(width: isSmall ? 2 : 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny visual indicator drawn in the bottom-right corner of a game
/// cover, showing which top-level [Source] this game came from.
///
/// Owned source = solid circle in the source colour.
/// Borrowed source = hollow ring in the source colour with a small share
/// glyph in the centre. The glyph distinguishes "this game lives on a
/// friend's server" from "I downloaded this myself" without needing a
/// legend.
/// One source dot's worth of styling — colour + borrowed flag.
class SourceDotData {
  const SourceDotData({required this.color, this.borrowed = false});
  final Color color;
  final bool borrowed;
}

/// Renders the primary source dot plus up to 2 extras to its left, in
/// reverse order so the right-most dot is always the primary. Caps at 3
/// total to keep the corner readable; further sources just don't show.
class _SourceDotRow extends StatelessWidget {
  const _SourceDotRow({
    required this.primary,
    required this.extras,
    required this.isSmall,
  });

  final SourceDotData primary;
  final List<SourceDotData> extras;
  final bool isSmall;

  static const int _maxExtras = 2;

  @override
  Widget build(BuildContext context) {
    final visibleExtras = extras.take(_maxExtras).toList(growable: false);
    final spacing = isSmall ? 3.0 : 4.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final dot in visibleExtras.reversed) ...[
          _SourceDot(
            color: dot.color,
            borrowed: dot.borrowed,
            isSmall: isSmall,
          ),
          SizedBox(width: spacing),
        ],
        _SourceDot(
          color: primary.color,
          borrowed: primary.borrowed,
          isSmall: isSmall,
        ),
      ],
    );
  }
}

class _SourceDot extends StatelessWidget {
  const _SourceDot({
    required this.color,
    required this.borrowed,
    required this.isSmall,
  });

  final Color color;
  final bool borrowed;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    final size = isSmall ? 10.0 : 12.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: borrowed ? Colors.transparent : color,
        border: Border.all(
          color: borrowed ? color : Colors.black.withValues(alpha: 0.5),
          width: borrowed ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: borrowed
          ? Center(
              child: Icon(
                Icons.share,
                size: size - 4,
                color: color,
              ),
            )
          : null,
    );
  }
}

/// eShop-style download overlay: a dark curtain that reveals the cover
/// from bottom to top as the download progresses.
class _DownloadRevealOverlay extends StatelessWidget {
  final DownloadStatus status;
  final double progress;
  final Color accentColor;

  const _DownloadRevealOverlay({
    required this.status,
    required this.progress,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isQueued = status == DownloadStatus.queued;
    final isIndeterminate = status == DownloadStatus.extracting ||
        status == DownloadStatus.moving ||
        status == DownloadStatus.verifying ||
        status == DownloadStatus.publishing;
    final isDownloading = status == DownloadStatus.downloading;

    // Curtain covers (1 - progress) of the card from the top.
    // At 0% → fully covered. At 100% → fully revealed.
    final curtainFraction = isQueued
        ? 1.0
        : (isIndeterminate ? 0.1 : 1.0 - progress.clamp(0.0, 1.0));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: curtainFraction),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Dark curtain from top — shrinks as download progresses
            if (value > 0.005)
              Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
              ),
            // Accent glow line at the reveal edge
            if (isDownloading && value > 0.01 && value < 0.99)
              Positioned(
                top: null,
                left: 0,
                right: 0,
                bottom: (1.0 - value) *
                        (context.findRenderObject()?.paintBounds.height ??
                            200) -
                    1,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                    color: accentColor.withValues(alpha: 0.9),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Participates in the card's measured layout; the reveal curtain still paints
/// behind it, but the score/title can no longer cover transfer status.
class _DownloadStatusIndicator extends StatelessWidget {
  final DownloadStatus status;
  final double progress;
  const _DownloadStatusIndicator(
      {required this.status, required this.progress});

  @override
  Widget build(BuildContext context) {
    final compact = context.rs.isSmall;
    final iconSize = compact ? 12.0 : 22.0;
    if (status == DownloadStatus.downloading && progress > 0.01) {
      return Text('${(progress * 100).toStringAsFixed(0)}%',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: compact ? 8 : 16,
              fontWeight: FontWeight.w800));
    }
    if (status == DownloadStatus.queued) {
      return Icon(Icons.schedule_rounded,
          size: iconSize, color: Colors.white.withValues(alpha: 0.6));
    }
    if (status == DownloadStatus.extracting ||
        status == DownloadStatus.moving ||
        status == DownloadStatus.verifying ||
        status == DownloadStatus.publishing) {
      return SizedBox(
          width: compact ? 12 : 20,
          height: compact ? 12 : 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.amber.withValues(alpha: 0.8)));
    }
    if (status == DownloadStatus.paused ||
        status == DownloadStatus.awaitingAuthorization) {
      final authorization = status == DownloadStatus.awaitingAuthorization;
      return Tooltip(
          message: authorization
              ? L.of(context).downloadStatus_awaitingAuthorization
              : L.of(context).downloadStatus_paused,
          child: Icon(
              authorization ? Icons.lock_outline_rounded : Icons.pause_rounded,
              size: iconSize,
              color: Colors.amber.withValues(alpha: 0.8)));
    }
    return const SizedBox.shrink();
  }
}
