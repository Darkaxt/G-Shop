import '../../models/config/system_config.dart';

enum OnboardingStep { welcome, complete }

class OnboardingState {
  final OnboardingStep currentStep;
  final Map<String, SystemConfig> configuredSystems;
  final bool canProceed;
  const OnboardingState(
      {this.currentStep = OnboardingStep.welcome,
      this.configuredSystems = const {},
      this.canProceed = false});
  int get configuredCount => configuredSystems.length;
  bool get isFirstStep => currentStep == OnboardingStep.welcome;
  bool get isLastStep => currentStep == OnboardingStep.complete;
  OnboardingState copyWith(
          {OnboardingStep? currentStep,
          Map<String, SystemConfig>? configuredSystems,
          bool? canProceed}) =>
      OnboardingState(
          currentStep: currentStep ?? this.currentStep,
          configuredSystems: configuredSystems ?? this.configuredSystems,
          canProceed: canProceed ?? this.canProceed);
}
