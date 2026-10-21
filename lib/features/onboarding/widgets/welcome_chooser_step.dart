import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/console_focusable.dart';
import '../../../models/config/source.dart';
import '../../../providers/game_providers.dart';
import '../../../services/drive/drive_runtime.dart';
import '../../../services/drive/drive_api.dart';
import '../../../services/drive/drive_authorization.dart';
import '../../../services/drive/drive_catalogue.dart';
import '../../sources/drive_source_setup_screen.dart';
import '../../sources/drive_source_mappings_screen.dart';
import '../onboarding_controller.dart';

class WelcomeChooserStep extends ConsumerStatefulWidget {
  const WelcomeChooserStep({super.key});
  @override
  ConsumerState<WelcomeChooserStep> createState() => _WelcomeChooserStepState();
}

class _WelcomeChooserStepState extends ConsumerState<WelcomeChooserStep> {
  final _connectFocus = FocusNode();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _connectFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    final source = await Navigator.of(context).push<Source>(
        MaterialPageRoute(builder: (_) => const DriveSourceSetupScreen()));
    if (!mounted || source == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DriveRuntime.instance.refreshSource(source);
      if (!mounted) return;
      ref.invalidate(bootstrappedConfigProvider);
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => DriveSourceMappingsScreen(source: source)));
      if (!mounted || saved != true) return;
      await ref
          .read(onboardingControllerProvider.notifier)
          .completeFromDriveSource(source.id);
    } catch (error) {
      if (mounted)
        setState(() => _error = error is DriveApiException ||
                error is DriveAuthorizationException ||
                error is DriveCatalogueException
            ? error.toString()
            : 'Could not finish Google Drive setup. Your saved source is retained.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(L.of(context).onboarding_welcomeTitle,
                    style: AppTheme.titleLarge),
                const SizedBox(height: 16),
                const Text('Connect your Google Drive collection',
                    style: TextStyle(color: Colors.white, fontSize: 24)),
                const SizedBox(height: 12),
                const Text(
                    'Choose your private ROM folder and map its consoles. Games download when you need them; your downloads, saves and imported resources stay on this device.',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 32),
                ConsoleFocusable(
                  focusNode: _connectFocus,
                  autofocus: true,
                  onSelect: _busy ? null : _connect,
                  child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColor)),
                      child: Row(children: [
                        const Icon(Icons.cloud_outlined,
                            color: AppTheme.primaryColor),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Text(
                                _busy
                                    ? 'Refreshing Drive catalogue…'
                                    : 'Connect Google Drive',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 20))),
                        if (_busy)
                          const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator())
                      ])),
                ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.redAccent))),
              ]))));
}
