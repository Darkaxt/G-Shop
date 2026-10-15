import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/config/provider_config.dart';
import '../models/config/system_config.dart';
import '../utils/network_constants.dart';
import '../models/game_item.dart';
import 'provider_factory.dart';

class UnifiedGameService {
  final Duration? syncTimeout;
  final Future<List<GameItem>> Function(ProviderConfig, SystemConfig)? fetchProviderGames;
  /// An explicit refresh operation, supplied only by user-triggered sync.
  /// Ordinary browsing reads the last successfully published catalogue without
  /// online traversal or authorization; a missing snapshot still fails visibly.
  final Future<void> Function(ProviderConfig)? prepareDrive;
  /// Only enable for a service whose lifetime is one multi-system sync session.
  /// Separate explicit sync sessions refresh independently.
  final bool shareDrivePreparation;
  final void Function()? onReadingGames;
  final Map<String, Future<void>> _drivePreparations = {};

  UnifiedGameService(
      {this.syncTimeout,
      this.fetchProviderGames,
      this.shareDrivePreparation = false,
      this.prepareDrive,
      this.onReadingGames});

  /// Source scope to pass to cache publication only AFTER this system's fetch
  /// succeeds. Configuration by itself never proves a complete traversal.
  static Set<String> configuredDriveSourceIds(SystemConfig system) => system.providers
      .where((provider) => provider.type == ProviderType.drive)
      .map((provider) => provider.sourceId)
      .whereType<String>()
      .toSet();

  /// Fetches games for a system from its configured providers.
  ///
  /// Providers are combined in priority order. Legacy providers deduplicate
  /// by filename; exact artifacts only deduplicate the same scoped provider ID.
  /// Drive failures reject publication of the entire system refresh.
  Future<List<GameItem>> fetchGamesForSystem(
    SystemConfig system, {
    @Deprecated('merge mode is always on; flag is ignored') bool? merge,
  }) async {
    if (system.providers.isEmpty) {
      throw StateError('No providers configured for system "${system.name}"');
    }
    return _fetchMerged(system);
  }

  Future<List<GameItem>> _fetchMerged(SystemConfig system) async {
    final results = <String, GameItem>{};
    final preparations = shareDrivePreparation
        ? _drivePreparations : <String, Future<void>>{};
    var successes = 0;

    for (final providerConfig in system.providers) {
      try {
        if (providerConfig.type == ProviderType.drive && prepareDrive != null) {
          final key = jsonEncode([providerConfig.sourceId, providerConfig.drive?.accountId, providerConfig.drive?.rootFolderId]);
          await preparations.putIfAbsent(key, () => prepareDrive!(providerConfig));
        }
        onReadingGames?.call();
        final fetch = fetchProviderGames?.call(providerConfig, system) ??
            ProviderFactory.getProvider(providerConfig).fetchGames(system);
        // Drive traversal owns its completion/checkpoint boundary. An outer
        // timer must not publish a partial system while traversal continues.
        final games = providerConfig.type == ProviderType.drive ? await fetch : await fetch.timeout(
              _timeoutFor(providerConfig),
              onTimeout: () =>
                  throw TimeoutException('Server not responding'),
            );
        if (providerConfig.type == ProviderType.drive) {
          for (final game in games) {
            final id = game.remoteArtifact?.id;
            if (id == null || id.providerId != 'drive' ||
                id.sourceId != providerConfig.sourceId ||
                id.accountId != providerConfig.drive?.accountId) {
              throw StateError('Drive catalogue returned an unscoped artifact');
            }
          }
        }
        successes++;

        for (final game in games) {
          if (results.containsKey(game.identityKey)) {
            // Same ROM from a lower-priority provider — store as alternative source
            if (game.providerConfig != null && game.remoteArtifact == null) {
              final existing = results[game.identityKey]!;
              results[game.identityKey] = existing.copyWith(
                alternativeSources: [
                  ...existing.alternativeSources,
                  AlternativeSource(
                    url: game.url,
                    providerConfig: game.providerConfig!,
                  ),
                ],
              );
            }
          } else {
            results[game.identityKey] = game;
          }
        }
      } catch (e) {
        // A successful second provider cannot establish deletion of any Drive
        // entries when that source failed. Preserve the prior system snapshot.
        if (providerConfig.type == ProviderType.drive) rethrow;
        debugPrint('Provider failed: $e');
        continue;
      }
    }

    if (successes == 0) {
      throw StateError('All providers failed for system "${system.name}"');
    }

    return results.values.toList();
  }

  /// RomM paginates (500/page) so needs a much longer outer timeout.
  /// Other providers use per-connection timeouts and need a tighter safety net.
  /// When a user-configured [syncTimeout] is set, it overrides the default
  /// for non-RomM providers. RomM always gets at least 10 minutes.
  Duration _timeoutFor(ProviderConfig config) {
    if (config.type == ProviderType.romm) {
      final userTimeout = syncTimeout ?? NetworkTimeouts.paginatedDiscovery;
      // RomM always gets at least the default 10-minute pagination timeout
      return userTimeout > NetworkTimeouts.paginatedDiscovery
          ? userTimeout
          : NetworkTimeouts.paginatedDiscovery;
    }
    return syncTimeout ?? NetworkTimeouts.providerDiscovery;
  }
}
