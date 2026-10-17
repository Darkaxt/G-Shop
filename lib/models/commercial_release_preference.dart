/// Presentation only. Canonical identity and exact edition ownership remain
/// with the library; this setting never changes files or metadata.
class CommercialReleasePreference {
  final List<String> regions;
  final bool showAllVersions;
  const CommercialReleasePreference({
    this.regions = const ['EUR', 'USA', 'JPN'],
    this.showAllVersions = false,
  });

  factory CommercialReleasePreference.fromJson(Map<String, dynamic> json) {
    final regions = (json['regions'] as List).cast<String>();
    if (regions.length != 3 ||
        regions.toSet().length != 3 ||
        !regions.toSet().containsAll(['EUR', 'USA', 'JPN'])) {
      throw const FormatException('Invalid release preference');
    }
    return CommercialReleasePreference(
        regions: List.unmodifiable(regions),
        showAllVersions: json['showAllVersions'] as bool? ?? false);
  }

  Map<String, dynamic> toJson() => {
        'regions': regions,
        'showAllVersions': showAllVersions,
      };

  CommercialReleasePreference move(int index, int delta) {
    final destination = index + delta;
    if (index < 0 ||
        index >= regions.length ||
        destination < 0 ||
        destination >= regions.length) return this;
    final order = List<String>.of(regions);
    final region = order.removeAt(index);
    order.insert(destination, region);
    return CommercialReleasePreference(
        regions: List.unmodifiable(order), showAllVersions: showAllVersions);
  }

  CommercialReleasePreference showingAll(bool value) =>
      CommercialReleasePreference(regions: regions, showAllVersions: value);

  static String normalizeRegion(String region) =>
      switch (region.toLowerCase()) {
        'eur' || 'eu' || 'europe' => 'eur',
        'usa' || 'us' || 'united states' => 'usa',
        'jpn' || 'jp' || 'japan' => 'jpn',
        _ => region.toLowerCase(),
      };
}
