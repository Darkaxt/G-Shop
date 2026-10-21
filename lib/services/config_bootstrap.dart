import '../models/config/app_config.dart';
import '../models/config/source.dart';
import '../models/config/provider_config.dart';
import 'source_resolver.dart';
import '../models/config/system_config.dart';
import '../models/system_model.dart';

class ConfigBootstrap {
  /// Read-only active view; the full persisted configuration stays recoverable.
  static AppConfig active(AppConfig config) {
    final sources =
        config.sources.where((s) => s.type == SourceType.drive).toList();
    final ids = sources.map((s) => s.id).toSet();
    final systems = config.systems
        .where((s) =>
            s.manualMappings.any((m) => ids.contains(m.sourceId)) ||
            s.providers.any((p) => p.type == ProviderType.drive))
        .map((s) {
      final managed = SourceResolver.providersFor(s, sources);
      final direct = s.providers.where((p) =>
          p.type == ProviderType.drive &&
          !p.managedBySource &&
          !ids.contains(p.sourceId));
      return s.copyWith(providers: [...direct, ...managed]);
    }).toList();
    return config.copyWith(sources: sources, systems: systems);
  }

  /// A transient sync view: source definitions/mappings are never rewritten.
  static AppConfig forManufacturer(AppConfig config, String manufacturer) {
    final ids = SystemModel.supportedSystems
        .where((s) => s.manufacturer == manufacturer)
        .map((s) => s.id)
        .toSet();
    return config.copyWith(
        systems: config.systems.where((s) => ids.contains(s.id)).toList());
  }

  /// Finds the SystemConfig matching a SystemModel by id.
  static SystemConfig? configForSystem(AppConfig config, SystemModel system) {
    return config.systemById(system.id);
  }
}
