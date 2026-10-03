import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/util/color_contrast.dart';
import '../../../l10n/app_localizations.dart';
import '../logic/filter_state.dart';

enum _FilterItemType { header, option }

enum _FilterCategory {
  region,
  language,
  top,
  tag,
  genre,
  match,
  order,
  platform
}

class _FilterItem {
  final _FilterItemType type;
  final _FilterCategory category;
  final FilterOption? option;
  final String label;

  const _FilterItem({
    required this.type,
    required this.category,
    this.option,
    required this.label,
  });
}

class FilterOverlay extends StatefulWidget {
  final Color accentColor;
  final List<FilterOption> availableRegions;
  final List<FilterOption> availableLanguages;
  final Set<String> selectedRegions;
  final Set<String> selectedLanguages;
  final bool favoritesOnly;
  final bool localOnly;
  final bool isLocalSystem;
  final void Function(String region) onToggleRegion;
  final void Function(String language) onToggleLanguage;
  final VoidCallback onToggleFavorites;
  final VoidCallback onToggleLocal;
  final VoidCallback onClearAll;
  final VoidCallback onClose;
  final ActiveFilters? discoveryFilters;
  final ValueChanged<ActiveFilters>? onDiscoveryChanged;
  final List<String> availableGenres;
  final Map<String, String> availablePlatforms;
  final String? discoveryScope, discoveryStatus;

  const FilterOverlay({
    super.key,
    required this.accentColor,
    required this.availableRegions,
    required this.availableLanguages,
    required this.selectedRegions,
    required this.selectedLanguages,
    required this.favoritesOnly,
    required this.localOnly,
    required this.isLocalSystem,
    required this.onToggleRegion,
    required this.onToggleLanguage,
    required this.onToggleFavorites,
    required this.onToggleLocal,
    required this.onClearAll,
    required this.onClose,
    this.discoveryFilters,
    this.onDiscoveryChanged,
    this.availableGenres = const [],
    this.availablePlatforms = const {},
    this.discoveryScope,
    this.discoveryStatus,
  });

  @override
  State<FilterOverlay> createState() => _FilterOverlayState();
}

class _FilterOverlayState extends State<FilterOverlay>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode(debugLabel: 'FilterOverlay');
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  int _focusedIndex = 0;
  late List<_FilterItem> _items;
  late List<int> _selectableIndices;

  @override
  void initState() {
    super.initState();
    _buildItems();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(FilterOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _buildItems();
  }

  @override
  void dispose() {
    _animController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _buildItems() {
    _items = [];
    _selectableIndices = [];

    // Boolean filters first (most used)
    _selectableIndices.add(_items.length);
    _items.add(const _FilterItem(
      type: _FilterItemType.option,
      category: _FilterCategory.region,
      label: 'Favorites Only',
    ));

    if (!widget.isLocalSystem) {
      _selectableIndices.add(_items.length);
      _items.add(const _FilterItem(
        type: _FilterItemType.option,
        category: _FilterCategory.language,
        label: 'Installed Only',
      ));
    }

    if (widget.availableRegions.isNotEmpty) {
      _items.add(const _FilterItem(
        type: _FilterItemType.header,
        category: _FilterCategory.region,
        label: 'REGIONS',
      ));
      for (final option in widget.availableRegions) {
        _selectableIndices.add(_items.length);
        _items.add(_FilterItem(
          type: _FilterItemType.option,
          category: _FilterCategory.region,
          option: option,
          label: option.label,
        ));
      }
    }

    if (widget.availableLanguages.isNotEmpty) {
      _items.add(const _FilterItem(
        type: _FilterItemType.header,
        category: _FilterCategory.language,
        label: 'LANGUAGES',
      ));
      for (final option in widget.availableLanguages) {
        _selectableIndices.add(_items.length);
        _items.add(_FilterItem(
          type: _FilterItemType.option,
          category: _FilterCategory.language,
          option: option,
          label: option.label,
        ));
      }
    }

    if (widget.discoveryFilters != null && widget.onDiscoveryChanged != null) {
      void item(_FilterCategory category, String label, {bool header = false}) {
        if (!header) _selectableIndices.add(_items.length);
        _items.add(_FilterItem(
            type: header ? _FilterItemType.header : _FilterItemType.option,
            category: category,
            label: label));
      }

      item(_FilterCategory.top, 'discovery', header: true);
      item(_FilterCategory.top, 'all');
      for (final top in ActiveFilters.topChoices) {
        item(_FilterCategory.top, '$top');
      }
      item(_FilterCategory.order, 'ratingOrder');
      if (widget.availablePlatforms.isNotEmpty) {
        item(_FilterCategory.platform, 'scope', header: true);
        for (final platform in widget.availablePlatforms.keys) {
          item(_FilterCategory.platform, platform);
        }
      }
      item(_FilterCategory.tag, 'contentTags', header: true);
      item(_FilterCategory.match, 'match');
      for (final tag in [
        'Hack',
        'T-Eng',
        'Dub',
        'Undub',
        'Uncensor',
        'official',
        'unknown',
        'homebrew',
        'demo'
      ]) {
        item(_FilterCategory.tag, tag);
      }
      if (widget.availableGenres.isNotEmpty) {
        item(_FilterCategory.genre, 'genres', header: true);
        for (final genre in widget.availableGenres) {
          item(_FilterCategory.genre, genre);
        }
      }
    }

    // Ensure focused index is valid
    if (_selectableIndices.isNotEmpty) {
      if (!_selectableIndices.contains(_focusedIndex)) {
        _focusedIndex = _selectableIndices.first;
      }
    }
  }

  void _moveFocus(int delta) {
    if (_selectableIndices.isEmpty) return;
    final currentPos = _selectableIndices.indexOf(_focusedIndex);
    if (currentPos < 0) {
      setState(() => _focusedIndex = _selectableIndices.first);
      return;
    }
    final newPos = (currentPos + delta).clamp(0, _selectableIndices.length - 1);
    if (newPos != currentPos) {
      setState(() => _focusedIndex = _selectableIndices[newPos]);
      _ensureVisible(_focusedIndex);
    }
  }

  void _toggleCurrent() {
    if (!_selectableIndices.contains(_focusedIndex)) return;
    final item = _items[_focusedIndex];
    final filters = widget.discoveryFilters;
    if (filters != null) {
      final next = switch (item.category) {
        _FilterCategory.top => filters.withTop(int.tryParse(item.label)),
        _FilterCategory.tag => filters.toggleTag(item.label),
        _FilterCategory.genre => filters.toggleGenre(item.label),
        _FilterCategory.match => filters.toggleTagMatch(),
        _FilterCategory.order => filters.toggleRatingOrder(),
        _FilterCategory.platform => filters.togglePlatform(item.label),
        _ => null,
      };
      if (next != null) {
        widget.onDiscoveryChanged?.call(next);
        return;
      }
    }

    // Handle toggle filters
    if (item.label == 'Favorites Only') {
      widget.onToggleFavorites();
      return;
    }
    if (item.label == 'Installed Only') {
      widget.onToggleLocal();
      return;
    }

    if (item.option == null) return;

    if (item.category == _FilterCategory.region) {
      widget.onToggleRegion(item.option!.id);
    } else {
      widget.onToggleLanguage(item.option!.id);
    }
  }

  void _ensureVisible(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      const itemHeight = 44.0;
      final offset = index * itemHeight;
      final viewport = _scrollController.position;
      if (offset < viewport.pixels) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else if (offset + itemHeight >
          viewport.pixels + viewport.viewportDimension) {
        _scrollController.animateTo(
          offset + itemHeight - viewport.viewportDimension,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isSelected(_FilterItem item) {
    final filters = widget.discoveryFilters;
    if (filters != null) {
      switch (item.category) {
        case _FilterCategory.top:
          return filters.top == int.tryParse(item.label);
        case _FilterCategory.tag:
          return filters.selectedTags.contains(item.label);
        case _FilterCategory.genre:
          return filters.selectedGenres.contains(item.label);
        case _FilterCategory.match:
          return filters.matchAllTags;
        case _FilterCategory.order:
          return filters.ratingOrder;
        case _FilterCategory.platform:
          return filters.selectedPlatforms.contains(item.label);
        default:
          break;
      }
    }
    if (item.label == 'Favorites Only') return widget.favoritesOnly;
    if (item.label == 'Installed Only') return widget.localOnly;
    if (item.option == null) return false;
    if (item.category == _FilterCategory.region) {
      return widget.selectedRegions.contains(item.option!.id);
    }
    return widget.selectedLanguages.contains(item.option!.id);
  }

  String _localizeLabel(L l, _FilterItem item) {
    if (item.category == _FilterCategory.platform) {
      return item.type == _FilterItemType.header
          ? l.filter_scope
          : widget.availablePlatforms[item.label] ?? item.label;
    }
    if (item.category == _FilterCategory.top) {
      if (item.type == _FilterItemType.header) return l.filter_discoveryTitle;
      final limit = int.tryParse(item.label);
      return limit == null ? l.filter_allGames : l.filter_topLimit(limit);
    }
    if (item.category == _FilterCategory.order) return l.filter_ratingOrder;
    if (item.category == _FilterCategory.match) {
      return widget.discoveryFilters!.matchAllTags
          ? l.filter_allTags
          : l.filter_anyTags;
    }
    if (item.category == _FilterCategory.genre &&
        item.type == _FilterItemType.header) {
      return l.filter_genres;
    }
    if (item.category == _FilterCategory.tag) {
      return switch (item.label) {
        'contentTags' => l.filter_contentTags,
        'official' => l.filter_official,
        'unknown' => l.filter_unknown,
        'homebrew' => l.filter_homebrew,
        'demo' => l.filter_demo,
        _ => item.label,
      };
    }
    switch (item.label) {
      case 'Favorites Only':
        return l.filter_favoritesOnly;
      case 'Installed Only':
        return l.filter_installedOnly;
      case 'REGIONS':
        return l.filter_regions;
      case 'LANGUAGES':
        return l.filter_languages;
      default:
        return item.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final l = L.of(context);
    final totalActive = widget.discoveryFilters?.activeCount ??
        (widget.selectedRegions.length +
            widget.selectedLanguages.length +
            (widget.favoritesOnly ? 1 : 0) +
            (widget.localOnly ? 1 : 0));

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Semi-transparent backdrop
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            // Side panel
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: rs.isPortrait ? rs.screenWidth : rs.screenWidth * 0.38,
              child: SlideTransition(
                position: _slideAnimation,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _moveFocus(-1),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _moveFocus(1),
                    const SingleActivator(LogicalKeyboardKey.enter,
                        includeRepeats: false): _toggleCurrent,
                    const SingleActivator(LogicalKeyboardKey.space,
                        includeRepeats: false): _toggleCurrent,
                    const SingleActivator(LogicalKeyboardKey.gameButtonA,
                        includeRepeats: false): _toggleCurrent,
                    const SingleActivator(LogicalKeyboardKey.escape,
                        includeRepeats: false): widget.onClose,
                    const SingleActivator(LogicalKeyboardKey.gameButtonB,
                        includeRepeats: false): widget.onClose,
                    const SingleActivator(LogicalKeyboardKey.goBack,
                        includeRepeats: false): widget.onClose,
                    const SingleActivator(LogicalKeyboardKey.gameButtonX,
                        includeRepeats: false): widget.onClearAll,
                  },
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    child: _buildPanel(rs, totalActive, l),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(Responsive rs, int totalActive, L l) {
    final padding = rs.isSmall ? rs.spacing.md : rs.spacing.lg;
    final headerFontSize = rs.isSmall ? 16.0 : 20.0;
    final badgeFontSize = rs.isSmall ? 11.0 : 13.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0141414),
        border: Border(
          right: BorderSide(
            color: widget.accentColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(10, 0),
          ),
        ],
      ),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title bar
            Padding(
              padding:
                  EdgeInsets.fromLTRB(padding, padding, padding, rs.spacing.sm),
              child: Row(
                children: [
                  Text(
                    l.filter_title,
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                  const Spacer(),
                  if (totalActive > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.accentColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        l.filter_activeCount(totalActive),
                        style: TextStyle(
                          fontSize: badgeFontSize,
                          fontWeight: FontWeight.w600,
                          color: widget.accentColor.forText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(
              color: Colors.white.withValues(alpha: 0.08),
              height: 1,
            ),
            if (widget.discoveryScope != null)
              Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: padding, vertical: rs.spacing.sm),
                  child: Text(
                      [
                        widget.discoveryScope!,
                        l.filter_basis,
                        if (widget.discoveryStatus != null)
                          widget.discoveryStatus!
                      ].join('\n'),
                      style: TextStyle(
                          fontSize: rs.isSmall ? 11 : 13,
                          color: Colors.grey[300]))),
            // Scrollable list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(vertical: rs.spacing.sm),
                itemCount: _items.length,
                itemExtent: 44,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  if (item.type == _FilterItemType.header) {
                    return _buildHeader(rs, item, l);
                  }
                  return _buildOption(
                    rs,
                    item,
                    l,
                    isFocused: index == _focusedIndex,
                    isSelected: _isSelected(item),
                    index: index,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Responsive rs, _FilterItem item, L l) {
    final fontSize = rs.isSmall ? 10.0 : 11.0;
    final padding = rs.isSmall ? rs.spacing.md : rs.spacing.lg;

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 12, padding, 4),
      child: Text(
        _localizeLabel(l, item),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: Colors.grey[500],
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildOption(
    Responsive rs,
    _FilterItem item,
    L l, {
    required bool isFocused,
    required bool isSelected,
    required int index,
  }) {
    final option = item.option;
    final isToggle = option == null;
    final fontSize = rs.isSmall ? 13.0 : 15.0;
    final countFontSize = rs.isSmall ? 11.0 : 12.0;
    final horizontalPadding = rs.isSmall ? rs.spacing.md : rs.spacing.lg;

    return Semantics(
        button: true,
        toggled: isSelected,
        child: GestureDetector(
          key: switch (item.category) {
            _FilterCategory.top => ValueKey('discovery-top-${item.label}'),
            _FilterCategory.tag => ValueKey('discovery-tag-${item.label}'),
            _FilterCategory.genre => ValueKey('discovery-genre-${item.label}'),
            _FilterCategory.platform =>
              ValueKey('discovery-platform-${item.label}'),
            _FilterCategory.match => const ValueKey('discovery-match'),
            _FilterCategory.order => const ValueKey('discovery-order'),
            _ => null,
          },
          onTap: () {
            setState(() => _focusedIndex = index);
            _toggleCurrent();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: EdgeInsets.symmetric(
              horizontal: horizontalPadding - 4,
              vertical: 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? widget.accentColor
                      .withValues(alpha: isFocused ? 0.18 : 0.08)
                  : isFocused
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(rs.radius.md),
              border: isFocused
                  ? Border.all(
                      color: widget.accentColor.withValues(alpha: 0.7),
                      width: 1.5,
                    )
                  : Border.all(color: Colors.transparent, width: 1.5),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.15),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Checkbox indicator
                SizedBox(
                  width: 20,
                  child: isSelected
                      ? Icon(
                          Icons.check_circle,
                          size: 16,
                          color: widget.accentColor.forIcon,
                        )
                      : Icon(
                          Icons.circle_outlined,
                          size: 16,
                          color:
                              isFocused ? Colors.grey[400] : Colors.grey[600],
                        ),
                ),
                const SizedBox(width: 8),
                // Flag
                if (!isToggle) ...[
                  Text(
                    option.flag,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    item.label == 'Favorites Only'
                        ? Icons.star
                        : Icons.save_alt,
                    size: 16,
                    color: isSelected ? Colors.white : Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                ],
                // Label
                Expanded(
                  child: Text(
                    isToggle ? _localizeLabel(l, item) : option.label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? Colors.white
                          : isFocused
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.grey[400],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Count badge
                if (!isToggle)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${option.count}',
                      style: TextStyle(
                        fontSize: countFontSize,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
  }
}
