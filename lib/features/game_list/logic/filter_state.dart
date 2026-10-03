import '../../../models/game_item.dart';
import '../../../models/library_identity.dart';
import '../../../utils/game_metadata.dart';

class FilterOption {
  final String id;
  final String label;
  final String flag;
  final int count;

  const FilterOption({
    required this.id,
    required this.label,
    required this.flag,
    required this.count,
  });
}

class ActiveFilters {
  final Set<String> selectedRegions;
  final Set<String> selectedLanguages;
  final bool favoritesOnly;
  final bool localOnly;
  final Set<String> selectedTags;
  final Set<String> selectedGenres;
  final Set<String> selectedPlatforms;
  final bool matchAllTags;
  final int? top;
  final bool ratingOrder;

  const ActiveFilters({
    this.selectedRegions = const {},
    this.selectedLanguages = const {},
    this.favoritesOnly = false,
    this.localOnly = false,
    this.selectedTags = const {},
    this.selectedGenres = const {},
    this.selectedPlatforms = const {},
    this.matchAllTags = false,
    this.top,
    this.ratingOrder = false,
  });

  bool get hasMetadataFilters =>
      selectedTags.isNotEmpty ||
      selectedGenres.isNotEmpty ||
      selectedPlatforms.isNotEmpty ||
      top != null ||
      ratingOrder;
  bool get isEmpty =>
      selectedRegions.isEmpty &&
      selectedLanguages.isEmpty &&
      !favoritesOnly &&
      !localOnly &&
      !hasMetadataFilters &&
      !matchAllTags;
  bool get isNotEmpty => !isEmpty;

  int get activeCount =>
      selectedRegions.length +
      selectedLanguages.length +
      (favoritesOnly ? 1 : 0) +
      (localOnly ? 1 : 0) +
      selectedTags.length +
      selectedGenres.length +
      selectedPlatforms.length +
      (top == null ? 0 : 1) +
      (ratingOrder ? 1 : 0) +
      (matchAllTags ? 1 : 0);

  static const topChoices = [10, 25, 50, 100];

  ActiveFilters _copy(
          {Set<String>? regions,
          Set<String>? languages,
          bool? favorites,
          bool? local,
          Set<String>? tags,
          Set<String>? genres,
          Set<String>? platforms,
          bool? allTags,
          bool? order,
          int? top,
          bool replaceTop = false}) =>
      ActiveFilters(
        selectedRegions: regions ?? selectedRegions,
        selectedLanguages: languages ?? selectedLanguages,
        favoritesOnly: favorites ?? favoritesOnly,
        localOnly: local ?? localOnly,
        selectedTags: tags ?? selectedTags,
        selectedGenres: genres ?? selectedGenres,
        selectedPlatforms: platforms ?? selectedPlatforms,
        matchAllTags: allTags ?? matchAllTags,
        ratingOrder: order ?? ratingOrder,
        top: replaceTop ? top : this.top,
      );

  Set<String> _toggle(Set<String> values, String value) {
    final next = Set<String>.of(values);
    if (!next.remove(value)) next.add(value);
    return Set.unmodifiable(next);
  }

  ActiveFilters toggleTag(String tag) => _copy(
      tags: _toggle(
          selectedTags, EditionIdentity.normalizeContentTags([tag]).single));
  ActiveFilters toggleGenre(String genre) =>
      _copy(genres: _toggle(selectedGenres, genre));
  ActiveFilters togglePlatform(String platform) =>
      _copy(platforms: _toggle(selectedPlatforms, platform));
  ActiveFilters toggleTagMatch() => _copy(allTags: !matchAllTags);
  ActiveFilters toggleRatingOrder() => _copy(order: !ratingOrder);
  ActiveFilters withTop(int? value) {
    if (value != null && !topChoices.contains(value)) {
      throw ArgumentError('Unsupported Top choice');
    }
    return _copy(top: value, replaceTop: true);
  }

  Map<String, dynamic> toJson() => {
        'regions': selectedRegions.toList(),
        'languages': selectedLanguages.toList(),
        'favoritesOnly': favoritesOnly,
        'localOnly': localOnly,
        'tags': selectedTags.toList(),
        'genres': selectedGenres.toList(),
        'platforms': selectedPlatforms.toList(),
        'matchAllTags': matchAllTags,
        'top': top,
        'ratingOrder': ratingOrder,
      };

  factory ActiveFilters.fromJson(Map<String, dynamic> json) {
    Set<String> strings(String key) =>
        Set.unmodifiable((json[key] as List? ?? const []).whereType<String>());
    return ActiveFilters(
        selectedRegions: strings('regions'),
        selectedLanguages: strings('languages'),
        favoritesOnly: json['favoritesOnly'] == true,
        localOnly: json['localOnly'] == true,
        selectedTags: EditionIdentity.normalizeContentTags(strings('tags')),
        selectedGenres: strings('genres'),
        selectedPlatforms: strings('platforms'),
        matchAllTags: json['matchAllTags'] == true,
        top: topChoices.contains(json['top']) ? json['top'] as int : null,
        ratingOrder: json['ratingOrder'] == true);
  }

  ActiveFilters toggleRegion(String region) {
    final newRegions = Set<String>.from(selectedRegions);
    if (newRegions.contains(region)) {
      newRegions.remove(region);
    } else {
      newRegions.add(region);
    }
    return _copy(regions: newRegions);
  }

  ActiveFilters toggleLanguage(String language) {
    final newLanguages = Set<String>.from(selectedLanguages);
    if (newLanguages.contains(language)) {
      newLanguages.remove(language);
    } else {
      newLanguages.add(language);
    }
    return _copy(languages: newLanguages);
  }

  ActiveFilters toggleFavoritesOnly() {
    return _copy(favorites: !favoritesOnly);
  }

  ActiveFilters toggleLocalOnly() {
    return _copy(local: !localOnly);
  }

  ActiveFilters clearAll() {
    return const ActiveFilters();
  }
}

({List<FilterOption> regions, List<FilterOption> languages})
    buildFilterOptions({
  required Map<String, List<GameItem>> groupedGames,
  required Map<String, RegionInfo> regionCache,
  required Map<String, List<LanguageInfo>> languageCache,
}) {
  final regionCounts = <String, _RegionAccum>{};
  final languageCounts = <String, _LangAccum>{};

  for (final entry in groupedGames.entries) {
    final groupRegions = <String>{};
    final groupLanguages = <String>{};

    for (final game in entry.value) {
      final region = regionCache[game.filename];
      if (region != null && region.name != 'Unknown') {
        groupRegions.add(region.name);
        regionCounts.putIfAbsent(
          region.name,
          () => _RegionAccum(region.name, region.flag),
        );
      }

      final languages = languageCache[game.filename];
      if (languages != null) {
        for (final lang in languages) {
          groupLanguages.add(lang.code);
          languageCounts.putIfAbsent(
            lang.code,
            () => _LangAccum(lang.code, lang.name, lang.flag),
          );
        }
      }
    }

    for (final r in groupRegions) {
      regionCounts[r]!.count++;
    }
    for (final l in groupLanguages) {
      languageCounts[l]!.count++;
    }
  }

  final regions = regionCounts.values
      .map((a) =>
          FilterOption(id: a.name, label: a.name, flag: a.flag, count: a.count))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  final languages = languageCounts.values
      .map((a) => FilterOption(
          id: a.code, label: a.label, flag: a.flag, count: a.count))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  return (regions: regions, languages: languages);
}

class _RegionAccum {
  final String name;
  final String flag;
  int count = 0;
  _RegionAccum(this.name, this.flag);
}

class _LangAccum {
  final String code;
  final String label;
  final String flag;
  int count = 0;
  _LangAccum(this.code, this.label, this.flag);
}
