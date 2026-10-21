import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/config/source.dart';
import '../models/config/provider_config.dart';
import '../services/providers/drive_provider.dart';
import '../services/source_provider.dart';

enum SourceHealth { unknown, checking, valid, invalid }

@immutable
class SourceHealthState {
  final Map<String, SourceHealth> statuses;
  final Map<String, String> errors;
  final DateTime? lastCheckAt;

  const SourceHealthState({
    this.statuses = const {},
    this.errors = const {},
    this.lastCheckAt,
  });

  SourceHealth statusFor(String sourceId) =>
      statuses[sourceId] ?? SourceHealth.unknown;

  String? errorFor(String sourceId) => errors[sourceId];

  bool get isStale {
    if (lastCheckAt == null) return true;
    return DateTime.now().difference(lastCheckAt!) > const Duration(minutes: 5);
  }

  SourceHealthState copyWith({
    Map<String, SourceHealth>? statuses,
    Map<String, String>? errors,
    DateTime? lastCheckAt,
  }) {
    return SourceHealthState(
      statuses: statuses ?? this.statuses,
      errors: errors ?? this.errors,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
    );
  }
}

/// Result of a health check for a single source, including discovered
/// platforms so callers can update knownPlatforms and auto-create systems.
class SourceHealthResult {
  final SourceHealth health;
  final String? error;
  final Map<String, int>? discoveredPlatforms;

  const SourceHealthResult.valid(this.discoveredPlatforms)
      : health = SourceHealth.valid,
        error = null;
  const SourceHealthResult.invalid(this.error)
      : health = SourceHealth.invalid,
        discoveredPlatforms = null;
}

class SourceHealthNotifier extends StateNotifier<SourceHealthState> {
  SourceHealthNotifier({
    Future<SourceConnectionResult> Function(Source source)? driveHealthCheck,
  })  : _driveHealthCheck = driveHealthCheck ?? _checkDrive,
        super(const SourceHealthState());

  final Future<SourceConnectionResult> Function(Source source)
      _driveHealthCheck;

  static Future<SourceConnectionResult> _checkDrive(Source source) {
    return DriveProvider(
      ProviderConfig(
        type: ProviderType.drive,
        priority: source.priority,
        sourceId: source.id,
        drive: source.drive,
      ),
    ).testConnection();
  }

  /// Check enabled Drive sources without an interactive account picker. Drive
  /// performs a non-interactive read of its configured root and never opens an
  /// account picker or contributes numeric auto-map platform IDs.
  ///
  /// Returns a map of sourceId → discovered platforms for sources that
  /// responded successfully, so callers can update knownPlatforms and
  /// auto-create missing SystemConfigs.
  Future<Map<String, Map<String, int>>> checkAll(List<Source> sources) async {
    final checkableSources =
        sources.where((s) => s.enabled && s.type == SourceType.drive).toList();
    if (checkableSources.isEmpty) return const {};
    state = state.copyWith(statuses: {
      ...state.statuses,
      for (final source in checkableSources) source.id: SourceHealth.checking
    });
    final results = await Future.wait(checkableSources.map((source) async {
      try {
        final checked = await _driveHealthCheck(source);
        return MapEntry(
            source.id,
            checked.success
                ? const SourceHealthResult.valid(null)
                : SourceHealthResult.invalid(
                    checked.error ?? 'Google Drive connection unavailable'));
      } catch (_) {
        return MapEntry(
            source.id,
            const SourceHealthResult.invalid(
                'Google Drive connection unavailable'));
      }
    }));

    final newStatuses = Map<String, SourceHealth>.from(state.statuses);
    final newErrors = Map<String, String>.from(state.errors);
    final discoveredPlatforms = <String, Map<String, int>>{};

    for (final entry in results) {
      final result = entry.value;
      newStatuses[entry.key] = result.health;
      if (result.health == SourceHealth.valid) {
        newErrors.remove(entry.key);
        if (result.discoveredPlatforms != null) {
          discoveredPlatforms[entry.key] = result.discoveredPlatforms!;
        }
      } else {
        newErrors[entry.key] = result.error ?? 'Connection failed';
      }
    }

    state = SourceHealthState(
      statuses: newStatuses,
      errors: newErrors,
      lastCheckAt: DateTime.now(),
    );

    return discoveredPlatforms;
  }

  void markInvalid(String sourceId, String reason) {
    state = state.copyWith(
      statuses: {...state.statuses, sourceId: SourceHealth.invalid},
      errors: {...state.errors, sourceId: reason},
    );
  }

  void markValid(String sourceId) {
    final errors = Map<String, String>.from(state.errors)..remove(sourceId);
    state = state.copyWith(
      statuses: {...state.statuses, sourceId: SourceHealth.valid},
      errors: errors,
    );
  }

  void markUnknown(Iterable<String> sourceIds) {
    final statuses = Map<String, SourceHealth>.from(state.statuses);
    final errors = Map<String, String>.from(state.errors);
    for (final sourceId in sourceIds) {
      statuses[sourceId] = SourceHealth.unknown;
      errors.remove(sourceId);
    }
    state = state.copyWith(statuses: statuses, errors: errors);
  }
}

final sourceHealthProvider =
    StateNotifierProvider<SourceHealthNotifier, SourceHealthState>((ref) {
  return SourceHealthNotifier();
});
