enum RomCacheScope { unified, perConsole }

enum RomCacheOrder { lru, fifo }

/// Independent product retention/capacity limits, not transfer deadlines.
class RomCacheLimits {
  final Duration? keepFor;
  final int? maxGames, maxBytes;
  RomCacheLimits({this.keepFor, this.maxGames, this.maxBytes}) {
    if ((keepFor?.isNegative ?? false) ||
        (maxGames != null && maxGames! < 0) ||
        (maxBytes != null && maxBytes! < 0)) {
      throw ArgumentError('Cache limits must be non-negative');
    }
  }

  static const fields = {'keepMilliseconds', 'maxGames', 'maxBytes'};
  static Map<String, int?> validate(Map value) {
    if (value.keys.any((key) => !fields.contains(key)) ||
        value.values.any((v) => v != null && (v is! int || v < 0))) {
      throw const FormatException('Invalid ROM cache limits');
    }
    return value.cast<String, int?>();
  }

  factory RomCacheLimits.decode(Map value) {
    final row = validate(value);
    return RomCacheLimits(
        keepFor: row['keepMilliseconds'] == null
            ? null
            : Duration(milliseconds: row['keepMilliseconds']!),
        maxGames: row['maxGames'],
        maxBytes: row['maxBytes']);
  }
  Map<String, int?> toJson() => {
        'keepMilliseconds': keepFor?.inMilliseconds,
        'maxGames': maxGames,
        'maxBytes': maxBytes,
      };
}

class RomCachePolicy {
  final bool enabled;
  final RomCacheScope scope;
  final RomCacheOrder order;
  final RomCacheLimits defaults;

  /// Missing fields inherit; explicit null means Never/no capacity limit.
  final Map<String, Map<String, int?>> consoles;
  RomCachePolicy(
      {this.enabled = false,
      this.scope = RomCacheScope.unified,
      this.order = RomCacheOrder.lru,
      RomCacheLimits? defaults,
      Map<String, Map<String, int?>> consoles = const {}})
      : defaults = defaults ?? RomCacheLimits(),
        consoles = Map<String, Map<String, int?>>.unmodifiable(
            consoles.map((key, value) {
          if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(key)) {
            throw const FormatException('Invalid ROM cache console');
          }
          return MapEntry(key,
              Map<String, int?>.unmodifiable(RomCacheLimits.validate(value)));
        }));

  factory RomCachePolicy.decode(Map row) {
    if (row.length != 6 ||
        row['schema'] != 1 ||
        row['enabled'] is! bool ||
        row['defaults'] is! Map ||
        row['consoles'] is! Map ||
        !RomCacheScope.values.any((v) => v.name == row['scope']) ||
        !RomCacheOrder.values.any((v) => v.name == row['order'])) {
      throw const FormatException('Invalid ROM cache policy');
    }
    final overrides = <String, Map<String, int?>>{};
    for (final entry in (row['consoles'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid ROM cache override');
      }
      overrides[entry.key] = RomCacheLimits.validate(entry.value);
    }
    return RomCachePolicy(
        enabled: row['enabled'],
        scope: RomCacheScope.values.byName(row['scope']),
        order: RomCacheOrder.values.byName(row['order']),
        defaults: RomCacheLimits.decode(row['defaults']),
        consoles: overrides);
  }

  RomCacheLimits limitsFor(String platform) => scope == RomCacheScope.unified
      ? defaults
      : RomCacheLimits.decode({...defaults.toJson(), ...?consoles[platform]});
  RomCachePolicy copyWith(
          {bool? enabled,
          RomCacheScope? scope,
          RomCacheOrder? order,
          RomCacheLimits? defaults,
          Map<String, Map<String, int?>>? consoles}) =>
      RomCachePolicy(
          enabled: enabled ?? this.enabled,
          scope: scope ?? this.scope,
          order: order ?? this.order,
          defaults: defaults ?? this.defaults,
          consoles: consoles ?? this.consoles);
  Map<String, Object> toJson() => {
        'schema': 1,
        'enabled': enabled,
        'scope': scope.name,
        'order': order.name,
        'defaults': defaults.toJson(),
        'consoles': consoles
      };

  /// Inputs are complete owned game/edition bundles, never individual discs.
  /// This is a preview: execution must revalidate policy, usage, protection,
  /// cloud bytes, format and local ownership at the existing removal boundary.
  RomCachePlan plan(Iterable<RomCacheEntry> entries,
      {required DateTime now, bool clockTrusted = true}) {
    final protected = <RomCacheEntry>[], unpinned = <RomCacheEntry>[];
    final victims = <RomCacheVictim>[];
    final blocked = <({RomCacheEntry entry, String reason})>[];
    final unmet = <String>{};
    final pools = <String, List<RomCacheEntry>>{};
    DateTime? nextExpiry;
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.id)) throw ArgumentError('Duplicate cache game');
      if (entry.pinned || entry.offlineSample) {
        protected.add(entry);
        continue;
      }
      unpinned.add(entry);
      pools
          .putIfAbsent(
              scope == RomCacheScope.unified ? 'unified' : entry.platform,
              () => [])
          .add(entry);
    }
    var remainingGames = unpinned.length;
    var remainingBytes = unpinned.fold(0, (sum, entry) => sum + entry.bytes);
    for (final pool in pools.entries) {
      final limits = limitsFor(pool.value.first.platform);
      var games = pool.value.length;
      var bytes = pool.value.fold(0, (sum, entry) => sum + entry.bytes);
      final available = <RomCacheEntry>[];
      for (final entry in pool.value) {
        final basis =
            order == RomCacheOrder.fifo ? entry.installedAt : entry.lastUse;
        final reason = entry.block ??
            (!clockTrusted
                ? 'clock_changed'
                : entry.lastUse == null || basis == null
                    ? 'unknown_usage'
                    : entry.lastUse!.isAfter(now) || basis.isAfter(now)
                        ? 'clock_changed'
                        : null);
        if (reason != null) {
          blocked.add((entry: entry, reason: reason));
          continue;
        }
        available.add(entry);
        if (limits.keepFor != null) {
          final expiry = entry.lastUse!.add(limits.keepFor!);
          if (expiry.isAfter(now) &&
              (nextExpiry == null || expiry.isBefore(nextExpiry))) {
            nextExpiry = expiry;
          }
        }
      }
      available.sort((a, b) {
        final left = order == RomCacheOrder.fifo ? a.installedAt! : a.lastUse!;
        final right = order == RomCacheOrder.fifo ? b.installedAt! : b.lastUse!;
        final compared = left.compareTo(right);
        return compared != 0 ? compared : a.id.compareTo(b.id);
      });
      // Expiry is independent of budget. Remove due entries before selecting
      // capacity victims, so an expired newer entry does not over-evict an older
      // nonexpired game when FIFO differs from successful-use ordering.
      final selected = <String>{};
      void select(RomCacheEntry entry, List<String> reasons) {
        selected.add(entry.id);
        games--;
        bytes -= entry.bytes;
        remainingGames--;
        remainingBytes -= entry.bytes;
        victims.add(RomCacheVictim(entry, reasons));
      }

      if (enabled) {
        for (final entry in available) {
          if (limits.keepFor != null &&
              !now.isBefore(entry.lastUse!.add(limits.keepFor!))) {
            select(entry, ['expired']);
          }
        }
        for (final entry in available) {
          if (selected.contains(entry.id)) continue;
          final reasons = <String>[
            if (limits.maxGames != null && games > limits.maxGames!)
              'game_limit',
            if (limits.maxBytes != null && bytes > limits.maxBytes!)
              'byte_limit',
          ];
          if (reasons.isNotEmpty) select(entry, reasons);
        }
      }
      if ((limits.maxGames != null && games > limits.maxGames!) ||
          (limits.maxBytes != null && bytes > limits.maxBytes!)) {
        unmet.add(pool.key);
      }
    }
    return RomCachePlan(victims, blocked, unmet,
        eligibleGames: unpinned.length,
        eligibleBytes: unpinned.fold(0, (sum, entry) => sum + entry.bytes),
        protectedGames: protected.length,
        protectedBytes: protected.fold(0, (sum, entry) => sum + entry.bytes),
        remainingGames: remainingGames,
        remainingBytes: remainingBytes,
        nextExpiry: nextExpiry);
  }
}

class RomCacheEntry {
  final String id, platform;
  final int bytes;
  final DateTime? installedAt, lastUsedAt;
  final bool pinned, offlineSample;
  final String? block;
  const RomCacheEntry(
      {required this.id,
      required this.platform,
      required this.bytes,
      this.installedAt,
      this.lastUsedAt,
      this.pinned = false,
      this.offlineSample = false,
      this.block});
  DateTime? get lastUse => lastUsedAt ?? installedAt;
}

class RomCacheVictim {
  final RomCacheEntry entry;
  final List<String> reasons;
  RomCacheVictim(this.entry, List<String> reasons)
      : reasons = List.unmodifiable(reasons);
}

class RomCachePlan {
  final List<RomCacheVictim> victims;
  final List<({RomCacheEntry entry, String reason})> blocked;
  final Set<String> unmetPools;
  final int eligibleGames,
      eligibleBytes,
      protectedGames,
      protectedBytes,
      remainingGames,
      remainingBytes;
  final DateTime? nextExpiry;
  RomCachePlan(
      List<RomCacheVictim> victims,
      List<({RomCacheEntry entry, String reason})> blocked,
      Set<String> unmetPools,
      {required this.eligibleGames,
      required this.eligibleBytes,
      required this.protectedGames,
      required this.protectedBytes,
      required this.remainingGames,
      required this.remainingBytes,
      this.nextExpiry})
      : victims = List.unmodifiable(victims),
        blocked = List.unmodifiable(blocked),
        unmetPools = Set.unmodifiable(unmetPools);
}
