import '../models/config/provider_config.dart';
import '../models/config/source.dart';
import '../models/config/system_config.dart';

/// Only Drive is executable. Other source kinds remain configuration history.
class SourceResolver {
  const SourceResolver._();
  static List<ProviderConfig> providersFor(
      SystemConfig system, List<Source> sources) {
    final result = <ProviderConfig>[];
    for (final source in sources) {
      if (source.type != SourceType.drive ||
          !source.enabled ||
          (system.enabledSourceIds != null &&
              !system.enabledSourceIds!.contains(source.id))) continue;
      final mapping = system.manualMappings
          .where((m) => m.sourceId == source.id)
          .firstOrNull;
      if (mapping == null) continue;
      result.add(ProviderConfig(
          type: ProviderType.drive,
          priority: mapping.priorityOverride ?? source.priority,
          path: mapping.remotePath,
          drive: source.drive,
          managedBySource: true,
          sourceId: source.id));
    }
    result.sort((a, b) => a.priority.compareTo(b.priority));
    return result;
  }

  static List<Source> sourcesFor(SystemConfig system, List<Source> sources) {
    final ids = providersFor(system, sources).map((p) => p.sourceId).toSet();
    return sources
        .where((s) => s.type == SourceType.drive && ids.contains(s.id))
        .toList();
  }
}
