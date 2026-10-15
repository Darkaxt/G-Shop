import '../models/config/app_config.dart';
import '../models/config/system_config.dart';
import '../models/system_model.dart';

class ConfigBootstrap {
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
