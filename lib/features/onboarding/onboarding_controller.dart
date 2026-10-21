import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/config/app_config.dart';
import '../../models/config/source.dart';
import '../../providers/app_providers.dart';
import '../../services/config_bootstrap.dart';
import '../../services/config_storage_service.dart';
import 'onboarding_state.dart';
export 'onboarding_state.dart';

class OnboardingController extends StateNotifier<OnboardingState> {
  final ConfigStorageService _configStorage;
  AppConfig? _imported;
  OnboardingController(this._configStorage) : super(const OnboardingState());
  void onMessageComplete() => state = state.copyWith(canProceed: true);
  void loadFromConfig(AppConfig config) {
    _imported = config;
    final active = ConfigBootstrap.active(config);
    state = OnboardingState(
        currentStep: active.sources.isEmpty
            ? OnboardingStep.welcome
            : OnboardingStep.complete,
        configuredSystems: {for (final s in active.systems) s.id: s},
        canProceed: active.sources.isNotEmpty);
  }

  Future<void> completeFromDriveSource(String sourceId) async {
    final committed = await _configStorage.loadConfig();
    if (committed?.sourceById(sourceId)?.type != SourceType.drive) {
      throw StateError('Google Drive configuration has not been saved');
    }
    loadFromConfig(committed!);
  }

  Future<AppConfig> buildFinalConfig() async {
    final config =
        await _configStorage.loadConfig() ?? _imported ?? AppConfig.empty;
    if (!config.sources.any((s) => s.type == SourceType.drive)) {
      throw StateError('Connect Google Drive before completing setup');
    }
    // The source/mapping editor already committed atomically. Keep all inactive
    // legacy configuration for recovery rather than replacing it with a view.
    return config;
  }

  Future<void> exportConfig() async =>
      _configStorage.exportConfig(await buildFinalConfig());
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>(
        (ref) => OnboardingController(ref.read(configStorageServiceProvider)));
