import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/download_providers.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/console_notification.dart';
import '../metadata_settings_screen.dart';
import '../models/settings_entry.dart';
import 'settings_list_view.dart';

class SettingsAdvancedTab extends ConsumerStatefulWidget {
  final FocusNode firstFocusNode;

  const SettingsAdvancedTab({super.key, required this.firstFocusNode});

  @override
  ConsumerState<SettingsAdvancedTab> createState() =>
      _SettingsAdvancedTabState();
}

class _SettingsAdvancedTabState extends ConsumerState<SettingsAdvancedTab> {
  Future<void> _exportErrorLog() async {
    final logFile = ref.read(crashLogServiceProvider).getLogFile();
    if (logFile == null) {
      if (mounted) {
        showConsoleNotification(context,
            message: L.of(context).settings_noErrorLog);
      }
      return;
    }
    try {
      await Share.shareXFiles([XFile(logFile.path)]);
    } catch (e) {
      if (mounted) {
        showErrorNotification(context, ref,
            message: 'Share failed: ${getUserFriendlyError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final syncTimeout = ref.watch(syncTimeoutProvider);
    final syncCooldown = ref.watch(syncCooldownProvider);
    final allowHttp = ref.watch(allowNonLanHttpProvider);
    final maxDownloads =
        ref.watch(downloadQueueManagerProvider).state.maxConcurrent;
    final hasLogFile = ref.read(crashLogServiceProvider).getLogFile() != null;

    return SettingsListView(
      firstFocusNode: widget.firstFocusNode,
      sections: [
        SettingsSection(l.settings_sectionDownloads, [
          SettingsEntry.spinner(
            title: l.settings_simultaneousDownloads,
            subtitle: l.settings_simultaneousDownloadsSubtitle,
            value: maxDownloads,
            min: 1,
            max: 3,
            onChanged: (delta) {
              final newValue = (maxDownloads + delta).clamp(1, 3);
              if (newValue != maxDownloads) {
                ref
                    .read(downloadQueueManagerProvider)
                    .setMaxConcurrent(newValue);
                ref.read(feedbackServiceProvider).tick();
              }
            },
          ),
          SettingsEntry.nav(
            icon: Icons.auto_stories_outlined,
            title: 'Get metadata & covers',
            subtitle: 'ScreenScraper · Choose what to scrape',
            onSelect: () => openScreenScraperCollector(context, ref),
          ),
        ]),
        SettingsSection(l.settings_sectionSync, [
          SettingsEntry.cycle(
            title: l.settings_syncTimeout,
            subtitle: l.settings_syncTimeoutSubtitle,
            displayValue: formatSyncTimeout(syncTimeout),
            onCycle: () {
              ref.read(syncTimeoutProvider.notifier).cycle();
              ref.read(feedbackServiceProvider).tick();
            },
          ),
          SettingsEntry.cycle(
            title: l.settings_autoSyncInterval,
            subtitle: l.settings_autoSyncIntervalSubtitle,
            displayValue: formatSyncCooldown(syncCooldown),
            onCycle: () {
              ref.read(syncCooldownProvider.notifier).cycle();
              ref.read(feedbackServiceProvider).tick();
            },
          ),
        ]),
        SettingsSection(l.settings_sectionDebug, [
          SettingsEntry.toggle(
            title: l.settings_allowInsecure,
            subtitle: l.settings_allowInsecureSubtitle,
            value: allowHttp,
            onChanged: () {
              ref.read(allowNonLanHttpProvider.notifier).toggle();
              ref.read(feedbackServiceProvider).tick();
            },
          ),
          if (hasLogFile)
            SettingsEntry.nav(
              icon: Icons.upload_file_rounded,
              title: l.settings_exportErrorLog,
              subtitle: l.settings_exportErrorLogSubtitle,
              onSelect: _exportErrorLog,
            ),
        ]),
      ],
    );
  }
}
